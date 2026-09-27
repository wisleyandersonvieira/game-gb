-- Fotos: "apagada" só depois de sair de verdade; e a Saúde confere as
-- rotinas (29/09/2026, pedidos do Wisley).
--
-- 1. FOTOS. A política de uso diz que a foto é apagada depois do prazo. A
--    rotina marcava a entrega como "foto removida" ANTES de o arquivo sair;
--    se a remoção (Edge Function, via pg_net + Vault) nunca rodava, ficava
--    gravado "apagada" para uma foto que continuava guardada. Agora há TRÊS
--    estados, e cada um diz a verdade:
--      * no prazo: a foto aparece;
--      * vencida, na fila (entregas.fotoaguardaremocaoem): a foto NÃO aparece
--        em tela nenhuma — a política promete que ela some depois do prazo —
--        e a entrega diz "foto vencida, sendo apagada";
--      * removida (entregas.fotoexpiradaem): só depois de a Edge Function
--        confirmar que o arquivo saiu.
--    Fila parada (presa em 5 tentativas, ou esperando há mais de 2 dias) vira
--    aviso e erro na aba Rotinas.
--    As entregas que diziam "removida" com o arquivo ainda guardado:
--      * vencidas (o caso normal: a rotina antiga só marcava vencidas) passam
--        a "sendo apagada" — continuam escondidas e o arquivo continua na fila;
--      * dentro do prazo (só se o prazo foi AUMENTADO depois da marcação)
--        voltam a mostrar a foto e saem da fila.
-- 2. SAÚDE. A /saude passa a conferir o que as rotinas precisam para rodar:
--    os segredos do cofre (só se existem, nunca o valor), o agendamento
--    automático (pg_cron) e as mensagens que falharam; e mostra as fotos
--    vencidas ainda guardadas, quantas e há quantos dias.

-- ---------------------------------------------------------------------------
-- 1. O estado "vencida, sendo apagada"
-- ---------------------------------------------------------------------------
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS fotoaguardaremocaoem timestamptz;
COMMENT ON COLUMN public.entregas.fotoaguardaremocaoem IS
  'Quando a foto passou do prazo e o arquivo entrou na fila para ser apagado. Daí em diante a foto não aparece em tela nenhuma; fotoexpiradaem só é gravado quando o arquivo sai de verdade.';

-- ---------------------------------------------------------------------------
-- 1a. A rotina enfileira e esconde; não diz "removida"
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260927100800_pin_tablet_e_expurgo.sql),
-- com o diff conferido.
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
  v_atraso integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    -- Já fez o trabalho do dia: com "ok", ou com o aviso de fila parada (que
    -- tem os números). Erro inesperado (sem números) tenta de novo.
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje
                  AND (resultado = 'ok' OR detalhe ? 'enfileiradas')) THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    -- 29/09/2026: a rotina só PÕE NA FILA o arquivo vencido. A entrega NÃO
    -- é marcada aqui: "foto removida" só é gravado quando o arquivo sai de
    -- verdade (expurgo_resultado). Antes, a entrega era marcada antes, e uma
    -- remoção que nunca rodava deixava gravado "apagada" para foto que
    -- continuava guardada.
    -- Fica de fora o arquivo que ainda serve a uma entrega DENTRO do prazo
    -- (apagá-lo levaria a foto dela junto) e o que já está na fila.
    INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
    SELECT p_contaid, e.entregaid, e.pathfotoevidencia
      FROM public.entregas e
     WHERE e.contaid = p_contaid
       AND e.pathfotoevidencia IS NOT NULL
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias)
       AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                        WHERE f.contaid = p_contaid AND f.caminho = e.pathfotoevidencia)
       AND NOT EXISTS (SELECT 1 FROM public.entregas r
                        WHERE r.contaid = p_contaid AND r.pathfotoevidencia = e.pathfotoevidencia
                          AND r.dataenvio >= p_agora - make_interval(days => v_dias))
     ORDER BY e.dataenvio
     LIMIT 2000
    ON CONFLICT (contaid, caminho) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Na fila = vencida: some das telas (a política promete), sem dizer
    -- "removida". Todas as entregas que usam o arquivo estão vencidas: o
    -- arquivo que ainda serve a uma no prazo não entra na fila.
    UPDATE public.entregas e
       SET fotoaguardaremocaoem = p_agora
      FROM public.fotosexpurgo f
     WHERE f.contaid = p_contaid AND f.removidoem IS NULL
       AND e.contaid = p_contaid AND e.pathfotoevidencia = f.caminho
       AND e.fotoaguardaremocaoem IS NULL AND e.fotoexpiradaem IS NULL;

    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    -- Remoção que não acontece não fica calada: presa (5 tentativas) ou
    -- atrasada (na fila há mais de 2 dias, sinal de que a remoção nem roda).
    SELECT count(*) FILTER (WHERE tentativas >= 5),
           coalesce(max(extract(day FROM p_agora - criadoem))::integer, 0)
      INTO v_presas, v_atraso
      FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL;
    IF v_presas > 0 OR v_atraso > 2 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso', left(
               'Fotos vencidas continuam guardadas: ' ||
               (SELECT count(*) FROM public.fotosexpurgo WHERE contaid = p_contaid AND removidoem IS NULL) ||
               ' esperando para sair, a mais antiga há ' || v_atraso || ' dia(s)' ||
               CASE WHEN v_presas > 0 THEN ', ' || v_presas || ' com a remoção falhando 5 vezes' ELSE '' END ||
               '. Veja a Saúde do sistema.', 300)
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('enfileiradas', v_n, 'dias', v_dias, 'presas', v_presas, 'atraso', v_atraso),
                                      'fotos vencidas continuam no armazenamento');
      RETURN jsonb_build_object('enfileiradas', v_n, 'dias', v_dias, 'presas', v_presas, 'atraso', v_atraso);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('enfileiradas', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('enfileiradas', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1b. "Foto removida" só quando o arquivo saiu
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260927100100_expurgo_fotos_entrega.sql),
-- com o diff conferido.
CREATE OR REPLACE FUNCTION public.expurgo_resultado(p_ids integer[], p_erro text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra o resultado do expurgo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_erro IS NULL THEN
    -- O arquivo saiu de verdade: SÓ AGORA a entrega diz "foto removida"
    -- (29/09/2026). Todas as entregas que apontavam para o arquivo — que só
    -- entrou na fila porque nenhuma delas estava mais no prazo.
    WITH saiu AS (
      UPDATE public.fotosexpurgo SET removidoem = now(), erro = NULL
       WHERE expurgoid = ANY (p_ids) AND removidoem IS NULL
      RETURNING contaid, caminho, removidoem
    )
    UPDATE public.entregas e
       SET fotoexpiradaem = s.removidoem, pathfotoevidencia = NULL
      FROM saiu s
     WHERE e.contaid = s.contaid AND e.pathfotoevidencia = s.caminho;
  ELSE
    UPDATE public.fotosexpurgo SET erro = left(p_erro, 500)
     WHERE expurgoid = ANY (p_ids) AND removidoem IS NULL;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1c. Consertar o que já está gravado errado
-- ---------------------------------------------------------------------------
-- Entrega marcada "removida" cujo arquivo NÃO saiu (continua na fila). Roda
-- de novo sem efeito.
-- (a) Dentro do prazo de hoje (só acontece se o prazo foi aumentado depois
--     da marcação): a foto volta a aparecer e o arquivo SAI da fila.
WITH no_prazo AS (
  UPDATE public.entregas e
     SET pathfotoevidencia = f.caminho, fotoexpiradaem = NULL, fotoaguardaremocaoem = NULL
    FROM public.fotosexpurgo f
   WHERE f.contaid = e.contaid AND f.entregaid = e.entregaid
     AND f.removidoem IS NULL
     AND e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL
     AND e.dataenvio >= now() - make_interval(days => public.dias_guardar_foto(e.contaid))
  RETURNING f.expurgoid
)
DELETE FROM public.fotosexpurgo WHERE expurgoid IN (SELECT expurgoid FROM no_prazo);
-- (b) Vencida (o caso normal): continua escondida e na fila, e passa a dizer
--     a verdade — "sendo apagada", não "removida".
UPDATE public.entregas e
   SET pathfotoevidencia = f.caminho, fotoexpiradaem = NULL, fotoaguardaremocaoem = f.criadoem
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.entregaid = e.entregaid
   AND f.removidoem IS NULL
   AND e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL;

-- (c) Toda foto que JÁ passou do prazo e ainda não estava na fila entra
--     nela agora, e some das telas na hora — sem esperar a rotina da
--     madrugada (a política promete que ela some depois do prazo). As mesmas
--     regras da rotina: nunca o arquivo que ainda serve a uma entrega no
--     prazo.
INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
SELECT DISTINCT ON (e.contaid, e.pathfotoevidencia) e.contaid, e.entregaid, e.pathfotoevidencia
  FROM public.entregas e
 WHERE e.pathfotoevidencia IS NOT NULL AND e.fotoexpiradaem IS NULL
   AND e.dataenvio < now() - make_interval(days => public.dias_guardar_foto(e.contaid))
   AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                    WHERE f.contaid = e.contaid AND f.caminho = e.pathfotoevidencia)
   AND NOT EXISTS (SELECT 1 FROM public.entregas r
                    WHERE r.contaid = e.contaid AND r.pathfotoevidencia = e.pathfotoevidencia
                      AND r.dataenvio >= now() - make_interval(days => public.dias_guardar_foto(e.contaid)))
 ORDER BY e.contaid, e.pathfotoevidencia, e.dataenvio
ON CONFLICT (contaid, caminho) DO NOTHING;
UPDATE public.entregas e
   SET fotoaguardaremocaoem = now()
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.removidoem IS NULL AND e.pathfotoevidencia = f.caminho
   AND e.fotoaguardaremocaoem IS NULL AND e.fotoexpiradaem IS NULL;
-- E pede a remoção já (sem cofre/pg_net, como no teste, não faz nada; a
-- Saúde mostra).
SELECT public.fotos_expurgo_disparar();

-- ---------------------------------------------------------------------------
-- 1d. O Quadro não mostra foto vencida
-- ---------------------------------------------------------------------------
-- A única tela que mostra a foto da entrega. Parte da versão mais recente
-- (20260929200000_quadro_e_intervalo.sql), com o diff conferido: a foto na
-- fila para apagar sai sem caminho, e vem o estado "sendo apagada".
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
                 -- Foto vencida (na fila para apagar) não aparece (29/09/2026).
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
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
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
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

-- ---------------------------------------------------------------------------
-- 2a. Fotos vencidas ainda guardadas, de uma conta (interna)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fotos_vencidas_da_conta(p_contaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH d AS (SELECT public.dias_guardar_foto(p_contaid) AS dias),
  v AS (
    SELECT e.dataenvio FROM public.entregas e, d
     WHERE e.contaid = p_contaid AND e.pathfotoevidencia IS NOT NULL AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < now() - make_interval(days => d.dias)
  )
  SELECT jsonb_build_object(
    'vencidas', (SELECT count(*) FROM v),
    -- Há quantos dias a mais antiga passou do prazo.
    'diasdeatraso', coalesce((SELECT extract(day FROM now() - min(v.dataenvio) - make_interval(days => d.dias))::integer
                                FROM v, d GROUP BY d.dias), 0),
    'presas', (SELECT count(*) FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5))
$$;
REVOKE ALL ON FUNCTION public.fotos_vencidas_da_conta(integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2b. A saúde da MINHA conta (qualquer um logado nela; a conta sai do login)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.saude_da_minha_conta()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object(
    'fotos', public.fotos_vencidas_da_conta(v_conta),
    'mensagensfalhadas', (SELECT count(*) FROM public.mensagensfila
                           WHERE contaid = v_conta AND status = 'falhou' AND criadoem >= now() - interval '24 hours'));
END;
$$;
REVOKE ALL ON FUNCTION public.saude_da_minha_conta() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.saude_da_minha_conta() TO authenticated;

-- ---------------------------------------------------------------------------
-- 2c. A saúde da PLATAFORMA (só o servidor chama, para a /saude)
-- ---------------------------------------------------------------------------
-- Cofre: diz só SE cada segredo existe, nunca o valor. Agendamento: os jobs
-- que as rotinas precisam, se estão ativos, e a última execução. Números
-- somados de todas as contas: a tela só mostra ao admin geral (ou com a
-- chave da Saúde).
CREATE OR REPLACE FUNCTION public.saude_das_rotinas()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_segredos jsonb := '{}'::jsonb;
  v_jobs     jsonb := '[]'::jsonb;
  v_nome     text;
  v_existe   boolean;
  v_fotos    jsonb;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    FOREACH v_nome IN ARRAY ARRAY['stgame_funcoes_url', 'stgame_fila_segredo', 'stgame_expurgo_segredo'] LOOP
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = $1 AND coalesce(decrypted_secret, '''') <> '''')'
        INTO v_existe USING v_nome;
      v_segredos := v_segredos || jsonb_build_object(v_nome, v_existe);
    END LOOP;
  END IF;

  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE $q$
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'nome', n.nome,
               'existe', j.jobid IS NOT NULL,
               'ativo', coalesce(j.active, false),
               'ultimaexecucao', r.end_time,
               'ultimostatus', r.status) ORDER BY n.nome), '[]'::jsonb)
        FROM unnest(ARRAY['gamegb-rotinas', 'stgame-telegram-fila']) n(nome)
        LEFT JOIN cron.job j ON j.jobname = n.nome
        LEFT JOIN LATERAL (SELECT d.end_time, d.status FROM cron.job_run_details d
                            WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1) r ON true
    $q$ INTO v_jobs;
  END IF;

  SELECT jsonb_build_object(
           'vencidas', coalesce(sum((f->>'vencidas')::integer), 0),
           'diasdeatraso', coalesce(max((f->>'diasdeatraso')::integer), 0),
           'presas', coalesce(sum((f->>'presas')::integer), 0))
    INTO v_fotos
    FROM (SELECT public.fotos_vencidas_da_conta(c.contaid) f FROM public.contas c) x;

  RETURN jsonb_build_object(
    'cofre', to_regclass('vault.decrypted_secrets') IS NOT NULL,
    'pgnet', to_regproc('net.http_post') IS NOT NULL,
    'segredos', v_segredos,
    'agendador', to_regclass('cron.job') IS NOT NULL,
    'jobs', v_jobs,
    'mensagensfalhadas', (SELECT count(*) FROM public.mensagensfila
                           WHERE status = 'falhou' AND criadoem >= now() - interval '24 hours'),
    'fotos', v_fotos);
END;
$$;
REVOKE ALL ON FUNCTION public.saude_das_rotinas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.saude_das_rotinas() TO service_role;
