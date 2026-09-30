-- Usuários gerenciais, PARTE 4, fatia 8: Onboarding (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Conduzir o
-- onboarding é cadastro: exige a pessoa INTEIRA nas lojas dele (parte 2).
-- Ver segue a mesma regra, com "Onboarding: ver": as pessoas, a situação e
-- as etapas de quem está inteiro nas lojas dele. As etapas do roteiro são o
-- catálogo da conta (só leitura). Os DOCUMENTOS PESSOAIS continuam só do
-- master (a tela só os lê para o master; nada aqui os entrega).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.etapas_de_onboarding()
RETURNS TABLE(etapaid integer, nome character varying, ordem integer, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT e.etapaid, e.nome, e.ordem, e.ativo
    FROM public.onboardingetapas e
   WHERE (public.sou_master() AND e.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND e.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('onboarding.ver'))::integer[]) > 0)
   ORDER BY e.ordem, e.nome, e.etapaid
$$;
REVOKE ALL ON FUNCTION public.etapas_de_onboarding() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.etapas_de_onboarding() TO authenticated;

CREATE OR REPLACE FUNCTION public.onboarding_status_da_tela()
RETURNS TABLE(funcionarioid integer, statusworkflow character varying, iniciadoem timestamptz, concluidoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.funcionarioid, s.statusworkflow, s.iniciadoem, s.concluidoem
    FROM public.onboardingstatus s
   WHERE (public.sou_master() AND s.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente()
          AND coalesce(public.pode_na_pessoa('onboarding.ver', s.contaid, s.funcionarioid), false))
   ORDER BY s.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.onboarding_status_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.onboarding_status_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.onboarding_itens_da_tela()
RETURNS TABLE(itemid integer, funcionarioid integer, etapaid integer, concluidoem timestamptz, observacao text, documentoid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT i.itemid, i.funcionarioid, i.etapaid, i.concluidoem, i.observacao,
         -- O documento ligado: só o número, e só para o master.
         CASE WHEN public.sou_master() THEN i.documentoid END
    FROM public.onboardingitens i
   WHERE (public.sou_master() AND i.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND i.contaid = public.conta_do_gerente()
          AND coalesce(public.pode_na_pessoa('onboarding.ver', i.contaid, i.funcionarioid), false))
   ORDER BY i.funcionarioid, i.itemid
$$;
REVOKE ALL ON FUNCTION public.onboarding_itens_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.onboarding_itens_da_tela() TO authenticated;
