-- Fotos: "apagada" só depois de sair de verdade; e a Saúde confere as
-- rotinas (29/09/2026, pedidos do Wisley).
--
-- 1. FOTOS. A política de uso diz que a foto é apagada depois do prazo. A
--    rotina marcava a entrega como "foto removida" ANTES de o arquivo sair;
--    se a remoção (Edge Function, via pg_net + Vault) nunca rodava, ficava
--    gravado "apagada" para uma foto que continuava guardada. Agora:
--      * a rotina só põe o arquivo vencido na fila;
--      * "foto removida" só é gravado quando a Edge Function confirma que o
--        arquivo saiu (expurgo_resultado);
--      * fila parada (presa em 5 tentativas, ou esperando há mais de 2 dias)
--        vira aviso e erro na aba Rotinas;
--      * as entregas que já diziam "removida" com o arquivo ainda guardado
--        VOLTAM a mostrar a foto (o registro deixa de mentir).
-- 2. SAÚDE. A /saude passa a conferir o que as rotinas precisam para rodar:
--    os segredos do cofre (só se existem, nunca o valor), o agendamento
--    automático (pg_cron) e as mensagens que falharam; e mostra as fotos
--    vencidas ainda guardadas, quantas e há quantos dias.

-- ---------------------------------------------------------------------------
-- 1a. A rotina só enfileira
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
-- Entrega marcada "removida" cujo arquivo continua na fila (não saiu): volta
-- a apontar para a foto, que continua guardada. Roda de novo sem efeito.
UPDATE public.entregas e
   SET pathfotoevidencia = f.caminho, fotoexpiradaem = NULL
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.entregaid = e.entregaid
   AND f.removidoem IS NULL
   AND e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL;

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
