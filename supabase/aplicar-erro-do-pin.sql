-- =========================================================================
-- STGame — o erro do PIN passa a dizer o motivo de verdade.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929100800_erro_do_pin_diz_o_motivo.sql
--
-- O QUE MUDA PARA QUEM JÁ USA: nada muda de comportamento. Só duas mensagens
-- passaram a dizer mais: quem pegou a tarefa primeiro, e quantos minutos falta
-- esperar quando a trava fecha.
-- =========================================================================

BEGIN;

-- O erro do PIN passa a dizer o MOTIVO de verdade.
--
-- Pedido do Wisley (25/09/2026): no balcão, a pessoa digita o PIN, o sistema
-- recusa, e ela fica olhando o teclado sem entender. A mensagem aparecia atrás
-- da modal, e quando aparecia dizia pouco.
--
-- Aqui ficam as duas mensagens que o banco precisava melhorar. As outras já
-- diziam o motivo certo e sobem inteiras até a tela.

-- ---------------------------------------------------------------------------
-- 1. "Já foi pega" passa a dizer POR QUEM
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100600), com o diff conferido.
CREATE OR REPLACE FUNCTION public.pegar_tarefa(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_quem text;
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.dia_em_sao_paulo(now());
  m       public.tarefasatribuidas%ROWTYPE;
  v_lista boolean;
  v_nova  integer;
  v_espera integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Sem pessoa para pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND datafimvigencia IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF m.origematribuicaoid IS NOT NULL THEN
    RAISE EXCEPTION 'Esta tarefa já está no nome de alguém.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje) THEN
    RAISE EXCEPTION 'Esta tarefa não vale para hoje.' USING ERRCODE = 'check_violation';
  END IF;
  -- Antes da hora combinada ninguém pega. A hora é a da EMPRESA, convertida
  -- aqui no banco: o tablet não opina sobre que horas são.
  IF m.disponivelapartir IS NOT NULL
     AND public.instante_na_conta(v_conta, v_hoje, m.disponivelapartir) > now() THEN
    RAISE EXCEPTION 'Esta tarefa libera às %.', to_char(m.disponivelapartir, 'HH24"h"MI')
      USING ERRCODE = 'check_violation';
  END IF;
  IF m.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(v_conta, p_atribuicaoid) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = m.lojaid
                                                   AND fl.ativo AND fl.contaid = v_conta
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = v_conta AND f.ativo
                    AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                               f.datafimafastamento, v_hoje)) THEN
    RAISE EXCEPTION 'Só quem trabalha hoje nesta loja pode pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    IF m.funcionarioid <> p_funcionarioid THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                    WHERE c.contaid = v_conta AND c.atribuicaoid = p_atribuicaoid) INTO v_lista;
    IF v_lista AND NOT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                                WHERE c.contaid = v_conta AND c.atribuicaoid = p_atribuicaoid
                                  AND c.funcionarioid = p_funcionarioid) THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Rodízio: quem pegou a última tarefa disputada desta loja espera um pouco
  -- antes de pegar outra. Só vale para tarefa sem dono, e nunca deixa a loja
  -- parada (ver rodizio_espera).
  v_espera := public.rodizio_espera(v_conta, m.lojaid, p_funcionarioid, p_atribuicaoid);
  IF v_espera > 0 THEN
    RAISE EXCEPTION 'Você pegou a última tarefa. Esta libera para você em % min.',
      greatest(1, ceil(v_espera / 60.0)::integer) USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
  VALUES (v_conta, p_atribuicaoid, v_hoje, p_funcionarioid, public.canal_atual())
  ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  IF NOT FOUND THEN
    -- Com o NOME: no balcao, "ja foi pega" sem dizer por quem deixa a pessoa
    -- procurando o que nao existe.
    SELECT public.nome_curto(f.nomecompleto) INTO v_quem
      FROM public.missoesaceites a
      JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
     WHERE a.contaid = v_conta AND a.atribuicaoid = p_atribuicaoid AND a.dia = v_hoje
       AND a.revogadoem IS NULL;
    RAISE EXCEPTION 'Esta tarefa já foi pega hoje por %.', coalesce(v_quem, 'outra pessoa')
      USING ERRCODE = 'unique_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    RETURN p_atribuicaoid;
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        dataatribuicao, dataagendamento, origematribuicaoid)
  VALUES (v_conta, m.tarefaid, p_funcionarioid, m.lojaid, 'Unica', now(), now(), p_atribuicaoid)
  RETURNING atribuicaoid INTO v_nova;

  UPDATE public.missoesaceites SET novaatribuicaoid = v_nova
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
  RETURN v_nova;
END;
$$;

REVOKE ALL ON FUNCTION public.pegar_tarefa(integer, integer)    FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.pegar_tarefa(integer, integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. A trava passa a dizer QUANTOS MINUTOS faltam
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100500), com o diff conferido.
CREATE OR REPLACE FUNCTION public.tentativa_abrir_ex(p_contaid integer, p_tipo text,
                                                     p_chave text, p_origem text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_minutos integer;
  v_janela  interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave   text     := left(coalesce(p_chave, ''), 64);
  v_origem  text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros   integer;
  v_outros  integer;
  v_esperar integer  := 0;
  v_id      bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tipo NOT IN ('senha', 'pin', 'tablet', 'pintablet', 'lojamanual', 'tvcodigo') THEN
    RAISE EXCEPTION 'Tipo de tentativa inválido.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- ---- Login da loja com senha DIGITADA: atraso, nunca bloqueio ----------
  -- Bloquear devolveria o problema que fez a trava ser desligada na parte A:
  -- o engraçadinho erra de propósito e a loja fica sem sistema. O atraso
  -- castiga quem adivinha e não tira a loja do ar.
  IF p_tipo = 'lojamanual' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'lojamanual' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '15 minutes'
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = 'lojamanual'
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    v_outros := 0;
    IF v_origem <> 'sem-ip' THEN
      SELECT count(*) INTO v_outros FROM public.tentativasacesso t
       WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'lojamanual' AND t.origem = v_origem
         AND NOT t.sucesso AND t.em > now() - interval '15 minutes'
         AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                               WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = 'lojamanual'
                                 AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    END IF;
    v_erros := greatest(v_erros, v_outros);
    IF v_erros > 0 THEN
      v_esperar := least(500 * (2 ^ least(v_erros - 1, 10))::integer, 10000);
    END IF;

    INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
    VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
    RETURNING tentativaid INTO v_id;
    DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
    RETURN jsonb_build_object('tentativaid', v_id, 'esperar', v_esperar);
  END IF;

  -- ---- Os outros tipos, como já eram --------------------------------------
  -- Quando a trava fecha, ela diz QUANTOS MINUTOS faltam: no balcao, "espere
  -- um pouco" nao ajuda ninguem. O tempo e ate a tentativa mais antiga sair
  -- da janela de 24 horas.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      SELECT greatest(1, ceil(extract(epoch FROM (min(t.em) + interval '1 day') - now()) / 60)::integer)
        INTO v_minutos
        FROM public.tentativasacesso t
       WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
         AND t.em > now() - interval '1 day';
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0, 'minutos', v_minutos);
    END IF;
  END IF;

  IF p_tipo = 'pintablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pintablet' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '1 day';
    IF v_erros >= 20 THEN
      SELECT greatest(1, ceil(extract(epoch FROM (min(t.em) + interval '1 day') - now()) / 60)::integer)
        INTO v_minutos
        FROM public.tentativasacesso t
       WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pintablet' AND t.chave = v_chave
         AND NOT t.sucesso AND t.em > now() - interval '1 day';
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0, 'minutos', v_minutos);
    END IF;
  END IF;

  IF p_tipo <> 'tablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN jsonb_build_object('tentativaid', v_id, 'esperar', 0);
END;
$$;

REVOKE ALL ON FUNCTION public.tentativa_abrir_ex(integer, text, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tentativa_abrir_ex(integer, text, text, text) TO service_role;

-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
BEGIN
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'pegar_tarefa') NOT LIKE '%foi pega hoje por%' THEN
    RAISE EXCEPTION 'A mensagem ainda não diz quem pegou a tarefa primeiro.';
  END IF;
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'tentativa_abrir_ex') NOT LIKE '%minutos%' THEN
    RAISE EXCEPTION 'A trava ainda não diz quantos minutos faltam.';
  END IF;
  RAISE NOTICE 'tudo certo: o erro do PIN diz o motivo.';
END $verifica$;

COMMIT;
