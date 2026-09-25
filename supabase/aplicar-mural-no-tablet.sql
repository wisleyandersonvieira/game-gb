-- =========================================================================
-- STGame — Etapa 1.12, parte B2: o MURAL no tablet da loja.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929101200_mural_no_tablet.sql
--
-- O QUE MUDA PARA QUEM JÁ USA: nada. Só entram duas funções novas, que o
-- tablet passa a chamar. A ciência continua sendo a mesma do gestor e do
-- celular, com o mesmo bônus e a mesma proteção contra pagar duas vezes.
-- =========================================================================

BEGIN;

-- Etapa 1.12, parte B2 — o MURAL no tablet da loja.
--
-- A equipe lê os comunicados e dá ciência pelo tablet do balcão, assinando com
-- o PIN. É o mesmo caminho de Solicitações: PIN → passe assinado → tela.
--
-- O QUE MUDA EM RELAÇÃO AO GESTOR: no tablet a pessoa vê SÓ os comunicados
-- dela que ainda esperam ciência. Nada de lista de quem já leu, nada de
-- histórico, nada dos colegas — o tablet é de todo mundo, e o que aparece
-- nele é visto por quem passa.
--
-- A ciência PAGA PONTOS quando o comunicado tem bônus, e por isso ela continua
-- passando por `registrar_ciencia`, que já é idempotente: dar ciência duas
-- vezes não paga duas vezes (ela devolve `false` e não grava movimento).

-- ---------------------------------------------------------------------------
-- 1. O mural dela
-- ---------------------------------------------------------------------------
-- Recebe conta e loja: nunca liberada para quem está logado (Etapa 1.6).
CREATE OR REPLACE FUNCTION public.visao_mural(p_contaid integer, p_lojaid integer,
                                              p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre o mural da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Quem lê tem de ser gente ativa DESTA loja.
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl
                     ON fl.funcionarioid = f.funcionarioid AND fl.contaid = p_contaid AND fl.ativo
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = p_contaid AND f.ativo
                    AND fl.lojaid = p_lojaid) THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'assinaturaid', s.assinaturaid,
             'titulo',       d.titulo,
             'conteudo',     d.conteudo,
             'pontos',       d.pontosporciencia,
             'quando',       s.dataenvio) ORDER BY s.dataenvio), '[]'::jsonb)
      FROM public.documentosassinaturas s
      JOIN public.documentos d ON d.documentoid = s.documentoid AND d.contaid = p_contaid
     WHERE s.contaid = p_contaid
       AND s.funcionarioid = p_funcionarioid
       -- SÓ o que falta ler. Nada de histórico: o tablet é compartilhado.
       AND s.statusassinatura = 'Pendente'
       AND d.status = 'Publicado');
END;
$$;

REVOKE ALL ON FUNCTION public.visao_mural(integer, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_mural(integer, integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Dar ciência pelo tablet
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.visao_dar_ciencia(p_contaid integer, p_lojaid integer,
                                                    p_funcionarioid integer, p_assinaturaid integer)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_dona integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra ciência pelo tablet.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- O comunicado tem de ser DELA. É o que impede dar ciência no nome de
  -- outra pessoa, mesmo chamando esta função direto, sem passar pela tela.
  SELECT funcionarioid INTO v_dona
    FROM public.documentosassinaturas
   WHERE assinaturaid = p_assinaturaid AND contaid = p_contaid;
  IF NOT FOUND OR v_dona <> p_funcionarioid THEN
    RAISE EXCEPTION 'Este comunicado não é seu.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  -- Pelo MESMO caminho do gestor e do celular. Ela já é idempotente: dar
  -- ciência duas vezes devolve false e não paga de novo.
  RETURN public.registrar_ciencia(p_assinaturaid);
END;
$$;

REVOKE ALL ON FUNCTION public.visao_dar_ciencia(integer, integer, integer, integer)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_dar_ciencia(integer, integer, integer, integer) TO service_role;

-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'visao_mural') THEN
    RAISE EXCEPTION 'Faltou a função do mural do tablet.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'visao_dar_ciencia') THEN
    RAISE EXCEPTION 'Faltou a função de dar ciência pelo tablet.';
  END IF;

  -- As duas recebem conta e loja: nunca podem ficar liberadas para quem
  -- está logado no navegador.
  IF has_function_privilege('authenticated', 'public.visao_mural(integer, integer, integer)', 'EXECUTE')
     OR has_function_privilege('authenticated',
          'public.visao_dar_ciencia(integer, integer, integer, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Alguma função do mural ficou liberada para o usuário logado.';
  END IF;

  -- A ciência continua passando pelo caminho de sempre, que é o que garante
  -- o bônus uma vez só.
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'visao_dar_ciencia')
     NOT LIKE '%registrar_ciencia%' THEN
    RAISE EXCEPTION 'O tablet deixou de usar o caminho de ciência de sempre.';
  END IF;

  RAISE NOTICE 'tudo certo: o mural está no tablet.';
END $verifica$;

COMMIT;
