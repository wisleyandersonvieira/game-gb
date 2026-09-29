-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 11: Onboarding.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-conquistas.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929260000_onboarding_permissoes.sql
--
-- O QUE MUDA: iniciar e marcar etapas conferem a permissão na pessoa, nunca a
-- própria; etapas do modelo só do master, por função. Para o master nada muda.
-- Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 11: Onboarding (29/09/2026).
--
-- Iniciar e marcar etapas: "onboarding.conduzir" NA PESSOA (todas as lojas dela
-- dentro das dele), e ninguém conduz o próprio. Ligar documento pessoal à
-- etapa: só o master (documento pessoal é só do master). As etapas do modelo
-- são um catálogo da conta, sem loja: só o master, por função; a gravação
-- direta fecha. Para o master nada muda. Nenhum dado é alterado.

-- iniciar_onboarding: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.iniciar_onboarding(p_funcionarioid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta AND ativo) THEN
    RAISE EXCEPTION 'Funcionário ativo não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão na pessoa, no banco (usuários gerenciais, parte 2 — Onboarding).
  IF NOT public.bot_contexto_confiavel() THEN
    IF NOT public.pode_na_pessoa('onboarding.conduzir', v_conta, p_funcionarioid) THEN
      RAISE EXCEPTION 'Seu cargo não permite conduzir o onboarding desta pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
      RAISE EXCEPTION 'Ninguém conduz o próprio onboarding.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  INSERT INTO public.onboardingstatus (contaid, funcionarioid, iniciadopor)
  VALUES (v_conta, p_funcionarioid, auth.uid())
  ON CONFLICT (funcionarioid) DO NOTHING;
  INSERT INTO public.onboardingitens (contaid, funcionarioid, etapaid)
  SELECT v_conta, p_funcionarioid, e.etapaid FROM public.onboardingetapas e
   WHERE e.contaid = v_conta AND e.ativo
  ON CONFLICT (funcionarioid, etapaid) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE public.onboardingstatus SET statusworkflow = 'Em andamento', concluidoem = NULL
   WHERE funcionarioid = p_funcionarioid AND v_n > 0;
  RETURN v_n;
END;
$function$;

-- marcar_etapa_onboarding: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.marcar_etapa_onboarding(p_itemid integer, p_feito boolean, p_observacao text DEFAULT NULL::text, p_documentoid integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); i public.onboardingitens%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO i FROM public.onboardingitens WHERE itemid = p_itemid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Etapa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão na pessoa, no banco (usuários gerenciais, parte 2 — Onboarding).
  -- Documento pessoal é só do master: o gerente não liga documento à etapa.
  IF NOT public.bot_contexto_confiavel() THEN
    IF NOT public.pode_na_pessoa('onboarding.conduzir', v_conta, i.funcionarioid) THEN
      RAISE EXCEPTION 'Seu cargo não permite conduzir o onboarding desta pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, i.funcionarioid) THEN
      RAISE EXCEPTION 'Ninguém conduz o próprio onboarding.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF p_documentoid IS NOT NULL AND NOT public.sou_master() THEN
      RAISE EXCEPTION 'Só o dono da conta liga documento pessoal a uma etapa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  IF p_documentoid IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.documentospessoais
        WHERE documentoid = p_documentoid AND contaid = v_conta AND funcionarioid = i.funcionarioid AND situacao <> 'Excluido') THEN
    RAISE EXCEPTION 'O documento precisa ser desta pessoa.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.onboardingitens
     SET concluidoem = CASE WHEN p_feito THEN coalesce(concluidoem, now()) END,
         concluidopor = CASE WHEN p_feito THEN coalesce(concluidopor, auth.uid()) END,
         observacao = coalesce(nullif(btrim(coalesce(p_observacao, '')), ''), observacao),
         documentoid = coalesce(p_documentoid, documentoid)
   WHERE itemid = p_itemid;
  UPDATE public.onboardingstatus s
     SET statusworkflow = CASE WHEN x.faltam = 0 THEN 'Concluído' ELSE 'Em andamento' END,
         concluidoem = CASE WHEN x.faltam = 0 THEN coalesce(s.concluidoem, now()) END
    FROM (SELECT count(*) FILTER (WHERE concluidoem IS NULL) AS faltam
            FROM public.onboardingitens WHERE funcionarioid = i.funcionarioid) x
   WHERE s.funcionarioid = i.funcionarioid;
END;
$function$;

-- As etapas do modelo: só o master. Sem p_etapaid, cria (no fim da fila, se
-- a ordem não vier); com p_etapaid, muda só o que vier preenchido.
CREATE OR REPLACE FUNCTION public.salvar_etapa_onboarding(p_etapaid integer, p_nome text DEFAULT NULL,
                                                          p_ordem integer DEFAULT NULL, p_ativo boolean DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe nas etapas do onboarding.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_nome IS NOT NULL AND length(btrim(p_nome)) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à etapa.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_etapaid IS NULL THEN
    IF p_nome IS NULL THEN
      RAISE EXCEPTION 'Dê um nome à etapa.' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO public.onboardingetapas (contaid, nome, ordem, ativo)
    VALUES (v_conta, btrim(p_nome),
            coalesce(p_ordem, (SELECT coalesce(max(ordem), 0) + 1 FROM public.onboardingetapas WHERE contaid = v_conta)),
            coalesce(p_ativo, true))
    RETURNING etapaid INTO v_id;
  ELSE
    UPDATE public.onboardingetapas
       SET nome = coalesce(btrim(p_nome), nome), ordem = coalesce(p_ordem, ordem), ativo = coalesce(p_ativo, ativo)
     WHERE contaid = v_conta AND etapaid = p_etapaid
    RETURNING etapaid INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Etapa não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_etapa_onboarding(integer, text, integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_etapa_onboarding(integer, text, integer, boolean) TO authenticated;

-- A gravação direta nas etapas fecha (a função acima faz o mesmo).
REVOKE INSERT, UPDATE, DELETE ON public.onboardingetapas FROM authenticated;
REVOKE INSERT (ativo, contaid, criadoem, etapaid, nome, ordem), UPDATE (ativo, contaid, criadoem, etapaid, nome, ordem)
  ON public.onboardingetapas FROM authenticated;


COMMIT;
