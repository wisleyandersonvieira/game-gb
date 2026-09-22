-- Correção da Etapa 1.13B1: aviso gerado DEPOIS do fim do turno.
--
-- Defeito encontrado em 23/09/2026 (o teste de isolamento só passava se
-- rodasse entre 08:00 e 17:30, por causa disto):
--   bot_janela procurava a próxima entrada a partir de hoje e, quando ela caía
--   em outro dia, devolvia motivo 'folga'. Só que o fim normal do expediente
--   cai exatamente nesse caso: quem trabalha das 08:00 às 17:00 e tem uma
--   entrega aprovada às 18:00 era tratado como se estivesse de folga.
--   Resultado: o aviso virava 'guardada', não chegava na entrada seguinte e
--   voltava só como resumo ("1 entrega aprovada"), perdendo o conteúdo — ou
--   sumia de vez, se ficasse guardado mais de 7 dias.
--
-- Regra certa (é o que o plano já dizia): quem TRABALHA hoje e está fora do
-- turno espera a próxima entrada ('fora_do_turno'). 'folga' fica só para quem
-- realmente não trabalha hoje — aí sim o aviso é guardado e vira resumo na
-- volta.
--
-- Só muda o motivo devolvido; o resto de bot_janela é igual ao da 1.13B1.

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

-- Continua interna (só o servidor chama, pelas funções da fila).
REVOKE ALL ON FUNCTION public.bot_janela(integer, integer, timestamptz) FROM public, anon, authenticated;
