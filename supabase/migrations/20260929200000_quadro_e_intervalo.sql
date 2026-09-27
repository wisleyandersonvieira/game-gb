-- O Quadro numa consulta só, com histórico por período; e o intervalo da
-- jornada que passa do fim do expediente (27/09/2026).

-- ---------------------------------------------------------------------------
-- 1. Intervalo até o fim do turno
-- ---------------------------------------------------------------------------
-- Antes, um intervalo que terminasse depois do fim do expediente era
-- ignorado inteiro (o sistema mandava mensagem no "almoço"). Agora ele vale
-- até o fim dele ou do turno, o que vier primeiro. Turno da noite com
-- intervalo cruzando a meia-noite já funcionava (a pausa é calculada no dia
-- certo). Nenhum caso prende a mensagem: no fim do intervalo, ou do turno, a
-- janela é conferida de novo.
-- Parte da versão mais recente (20260929190000), com o diff conferido.
CREATE OR REPLACE FUNCTION public.bot_janela(p_contaid integer, p_funcionarioid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje  date;
  v_hora  time;
  v_fim   time := public.rotina_horario(p_contaid, 'HORARIO_SILENCIO_FIM', '07:00');
  j       record;
  d       date;
  v_trabalha_hoje boolean;
  v_pausafim timestamptz;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;

  -- Grupo (ou o Telegram do master): só o silêncio.
  IF p_funcionarioid IS NULL THEN
    IF public.no_silencio(p_contaid, v_hora) THEN
      RETURN jsonb_build_object('pode', false, 'motivo', 'silencio',
        'proxima', CASE WHEN v_hora < v_fim THEN public.instante_local(v_hoje, v_fim)
                        ELSE public.instante_local(v_hoje + 1, v_fim) END);
    END IF;
    RETURN jsonb_build_object('pode', true);
  END IF;

  SELECT * INTO j FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, v_hoje);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('pode', false, 'motivo', 'sem_pessoa');
  END IF;

  -- Guardado antes do laço abaixo, que reaproveita a variável j.
  v_trabalha_hoje := j.trabalha;

  IF j.temhorario THEN
    -- No INTERVALO da jornada (almoço): silêncio até ele acabar. Não é
    -- marcação de nada — só a hora em que o sistema não manda mensagem.
    -- O intervalo vale do começo dele até o fim DELE ou do turno, o que vier
    -- primeiro (27/09/2026): um intervalo que passa do fim do expediente era
    -- ignorado inteiro. A mensagem sempre volta a andar: no fim do intervalo
    -- (ou do turno) a janela é conferida de novo.
    SELECT least(t.pausafim, t.fim) INTO v_pausafim
      FROM generate_series(v_hoje - 1, v_hoje, interval '1 day') g
     CROSS JOIN LATERAL public.jornada_da_pessoa(p_contaid, p_funcionarioid, g::date) t
     WHERE t.trabalha AND t.pausainicio IS NOT NULL
       AND t.pausainicio >= t.inicio AND t.pausainicio < t.fim
       AND p_agora >= t.pausainicio AND p_agora < least(t.pausafim, t.fim)
     LIMIT 1;
    IF v_pausafim IS NOT NULL THEN
      RETURN jsonb_build_object('pode', false, 'motivo', 'intervalo', 'proxima', v_pausafim);
    END IF;
    -- Dentro do turno de hoje ou do que começou ontem (turno da noite)?
    IF EXISTS (
      SELECT 1 FROM generate_series(v_hoje - 1, v_hoje, interval '1 day') g
       CROSS JOIN LATERAL public.jornada_da_pessoa(p_contaid, p_funcionarioid, g::date) t
       WHERE t.trabalha AND p_agora >= t.inicio AND p_agora <= t.fim + interval '30 minutes') THEN
      RETURN jsonb_build_object('pode', true);
    END IF;
    -- Fora do turno: espera o próximo começo (até 8 dias à frente).
    -- Quem trabalha hoje está só fora do horário, não de folga: o aviso espera
    -- a próxima entrada, mesmo que ela seja amanhã.
    FOR d IN SELECT g::date FROM generate_series(v_hoje, v_hoje + 8, interval '1 day') g LOOP
      SELECT * INTO j FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, d);
      IF j.trabalha AND j.inicio > p_agora THEN
        RETURN jsonb_build_object('pode', false,
          'motivo', CASE WHEN d = v_hoje OR v_trabalha_hoje THEN 'fora_do_turno' ELSE 'folga' END,
          'proxima', j.inicio);
      END IF;
    END LOOP;
    RETURN jsonb_build_object('pode', false, 'motivo', 'folga', 'proxima', public.instante_local(v_hoje + 1, v_fim));
  END IF;

  -- Sem horário: valem a folga e o silêncio.
  IF NOT j.trabalha THEN
    FOR d IN SELECT g::date FROM generate_series(v_hoje + 1, v_hoje + 8, interval '1 day') g LOOP
      IF (SELECT t.trabalha FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, d) t) THEN
        RETURN jsonb_build_object('pode', false, 'motivo', 'folga', 'proxima', public.instante_local(d, v_fim));
      END IF;
    END LOOP;
    RETURN jsonb_build_object('pode', false, 'motivo', 'folga', 'proxima', public.instante_local(v_hoje + 1, v_fim));
  END IF;
  IF public.no_silencio(p_contaid, v_hora) THEN
    RETURN jsonb_build_object('pode', false, 'motivo', 'silencio',
      'proxima', CASE WHEN v_hora < v_fim THEN public.instante_local(v_hoje, v_fim)
                      ELSE public.instante_local(v_hoje + 1, v_fim) END);
  END IF;
  RETURN jsonb_build_object('pode', true);
END;
$$;

REVOKE ALL ON FUNCTION public.bot_janela(integer, integer, timestamptz) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. O Quadro: pendentes + histórico do período, numa consulta só
-- ---------------------------------------------------------------------------
-- Antes a tela fazia duas rodadas (as entregas; depois tarefas, nomes e
-- fotos). Agora: esta função traz tudo menos o link das fotos.
--   * PENDENTES: todas, de qualquer dia (é lista de coisa a fazer).
--   * HISTÓRICO (aprovadas, recusadas e estornadas): pela data da ENTREGA,
--     no período pedido; por padrão os 7 dias até ONTEM (o de hoje já está
--     em "Feitas hoje"). Período invertido é recusado; no máximo 93 dias; 50
--     por vez, com "carregar mais".
-- É SECURITY INVOKER: quem lê é quem chamou, com as regras de acesso dele.
CREATE INDEX IF NOT EXISTS entregas_loja_envio_idx ON public.entregas (lojaid, dataenvio DESC);

CREATE OR REPLACE FUNCTION public.quadro_validacao(p_lojaid integer, p_de date DEFAULT NULL,
                                                   p_ate date DEFAULT NULL, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dia   jsonb   := public.meu_hoje();
  v_hoje  date    := (v_dia->>'hoje')::date;
  v_fuso  text    := v_dia->>'fuso';
  v_ate   date    := coalesce(p_ate, (v_dia->>'hoje')::date - 1);
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  v_de := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 e.observacao, e.pathfotoevidencia, e.fotoexpiradaem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  -- O histórico não leva "sem hora da foto": a decisão já foi tomada.
  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 e.pathfotoevidencia, e.fotoexpiradaem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    -- Pediu 51 para saber se tem mais; devolve 50.
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$$;
REVOKE ALL ON FUNCTION public.quadro_validacao(integer, date, date, integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.quadro_validacao(integer, date, date, integer) TO authenticated;
