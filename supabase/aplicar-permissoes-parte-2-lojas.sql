-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 12: Lojas e TV.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-onboarding.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929261000_lojas_permissoes.sql
--
-- O QUE MUDA: TV, som do tablet e dados da loja conferem a permissão na loja;
-- criar, ativar e trocar o gestor só o master; a gravação direta em lojas
-- fecha. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 12: Lojas e TV (29/09/2026).
--
-- TV (criar e revogar link, parear, blocos da TV): "lojas.tv" na loja.
-- Mostrar valores em R$ na TV: além disso, "valores.ver_rs" na loja.
-- Som do tablet: "lojas.tablet_som". Editar os dados da loja (nome, cidade,
-- endereço, responsável pela agenda): "lojas.editar". Trocar o GESTOR da loja,
-- criar loja e ativar/desativar: só o master (mexe no limite contratado).
-- A gravação direta em lojas fecha e vira função.
-- Para o master nada muda. Nenhum dado é alterado.
-- criar_link_tv: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.criar_link_tv(p_lojaid integer, p_nome text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_codigo text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome ao link (ex.: TV do balcão).' USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada ou desativada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Lojas e TV).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('lojas.tv', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 64 caracteres aleatorios (duas UUID v4): impossivel de adivinhar.
  v_codigo := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  INSERT INTO public.linkstv (contaid, lojaid, nome, tokenhash, criadopor)
  VALUES (v_conta, p_lojaid, btrim(p_nome),
          encode(sha256(convert_to(v_codigo, 'UTF8')), 'hex'), auth.uid());

  RETURN v_codigo;
END;
$function$;

-- revogar_link_tv: parte da versão viva; carrega o link antes, para conferir a loja.
CREATE OR REPLACE FUNCTION public.revogar_link_tv(p_linktvid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_loja  integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT lojaid INTO v_loja FROM public.linkstv
   WHERE linktvid = p_linktvid AND contaid = v_conta AND revogadoem IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link não encontrado ou já revogado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Lojas e TV).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('lojas.tv', v_loja) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.linkstv SET revogadoem = now() WHERE linktvid = p_linktvid;
END;
$function$;

-- parear_tv: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.parear_tv(p_codigo text, p_lojaid integer, p_nome text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_codigo text    := upper(btrim(coalesce(p_codigo, '')));
  v_id     bigint;
  v_token  text;
  v_link   integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à TV (ex.: TV do balcão).' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada ou desativada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Lojas e TV).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('lojas.tv', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- O código tem de existir, estar no prazo e ainda não ter sido usado.
  -- FOR UPDATE: dois gestores digitando o mesmo código ao mesmo tempo, só um
  -- pareia.
  SELECT codigotvid INTO v_id
    FROM public.codigostv
   WHERE codigo = v_codigo AND expiraem > now() AND pareadoem IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Código inválido ou vencido. Veja o código que está na TV agora.'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Daqui para baixo é exatamente o que "Criar link" sempre fez.
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  INSERT INTO public.linkstv (contaid, lojaid, nome, tokenhash, criadopor)
  VALUES (v_conta, p_lojaid, btrim(p_nome),
          encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), auth.uid())
  RETURNING linktvid INTO v_link;

  UPDATE public.codigostv
     SET contaid = v_conta, linktvid = v_link, token = v_token, pareadoem = now()
   WHERE codigotvid = v_id;
END;
$function$;

-- salvar_tv_da_loja: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.salvar_tv_da_loja(p_lojaid integer, p_blocos jsonb, p_segundos integer, p_valores boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_limpo jsonb   := '{}'::jsonb;
  k       text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Lojas e TV).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('lojas.tv', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Mudar o "mostrar valores em R$" pede também a permissão de ver R$.
  IF NOT public.bot_contexto_confiavel()
     AND coalesce(p_valores, false) IS DISTINCT FROM (SELECT mostrarvalorestv FROM public.lojas WHERE lojaid = p_lojaid)
     AND NOT public.pode('valores.ver_rs', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite mudar se a TV mostra valores em R$.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF coalesce(p_segundos, 60) NOT IN (30, 60, 120) THEN
    RAISE EXCEPTION 'O tempo da troca é 30, 60 ou 120 segundos.' USING ERRCODE = 'check_violation';
  END IF;

  -- Só as chaves que a gente conhece entram: o navegador não inventa bloco.
  FOREACH k IN ARRAY ARRAY['barra', 'meta', 'metames', 'metaespecial', 'parafazer', 'emandamento',
                           'emvalidacao', 'atividade', 'podiohoje', 'podiomes'] LOOP
    v_limpo := v_limpo || jsonb_build_object(k, coalesce((p_blocos->>k)::boolean, false));
  END LOOP;

  UPDATE public.lojas
     SET tvblocos = v_limpo,
         tvsegundos = coalesce(p_segundos, 60),
         mostrarvalorestv = coalesce(p_valores, false)
   WHERE lojaid = p_lojaid AND contaid = v_conta;
END;
$function$;

-- salvar_som_da_loja: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.salvar_som_da_loja(p_lojaid integer, p_ligado boolean, p_volume integer, p_repetir integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Lojas e TV).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('lojas.tablet_som', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Os três níveis da janela, e nada além deles: o navegador não escolhe o
  -- número, escolhe o nível.
  IF coalesce(p_volume, 19) NOT IN (10, 19, 45) THEN
    RAISE EXCEPTION 'O volume é baixo, médio ou alto.' USING ERRCODE = 'check_violation';
  END IF;
  IF coalesce(p_repetir, 0) NOT IN (0, 5, 10, 15, 30) THEN
    RAISE EXCEPTION 'A repetição é de 5, 10, 15 ou 30 minutos, ou desligada.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.lojas
     SET somtarefanova     = coalesce(p_ligado, true),
         somvolume         = coalesce(p_volume, 19),
         somrepetirminutos = coalesce(p_repetir, 0)
   WHERE lojaid = p_lojaid AND contaid = v_conta;
END;
$function$;

-- ---------------------------------------------------------------------------
-- A loja em si: criar e ativar só o master; editar os dados, "lojas.editar"
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.criar_loja(p_nome text, p_cidade text DEFAULT NULL, p_endereco text DEFAULT NULL)
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
    RAISE EXCEPTION 'Só o dono da conta cria loja (mexe no limite contratado).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.lojas (contaid, nome, cidade, endereco)
  VALUES (v_conta, btrim(coalesce(p_nome, '')), nullif(btrim(coalesce(p_cidade, '')), ''), nullif(btrim(coalesce(p_endereco, '')), ''))
  RETURNING lojaid INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.criar_loja(text, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.criar_loja(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_loja(p_lojaid integer, p_ativa boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta ativa ou desativa loja (mexe no limite contratado).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.lojas SET ativa = coalesce(p_ativa, true) WHERE contaid = v_conta AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_loja(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_loja(integer, boolean) TO authenticated;

-- Editar os dados. Trocar o gestor da loja é só do master (decisão pelo mais
-- restritivo); mandar o mesmo gestor de volta não é trocar.
CREATE OR REPLACE FUNCTION public.editar_loja(p_lojaid integer, p_nome text, p_cidade text, p_endereco text,
                                              p_gestorid integer, p_responsavelagendamentosid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); l public.lojas%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO l FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Lojas e TV).
  IF NOT public.pode('lojas.editar', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite editar esta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_gestorid IS DISTINCT FROM l.gestorid AND NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta troca o gestor da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.lojas
     SET nome = btrim(coalesce(p_nome, '')), cidade = nullif(btrim(coalesce(p_cidade, '')), ''),
         endereco = nullif(btrim(coalesce(p_endereco, '')), ''),
         gestorid = p_gestorid, responsavelagendamentosid = p_responsavelagendamentosid
   WHERE lojaid = p_lojaid;
END;
$$;
REVOKE ALL ON FUNCTION public.editar_loja(integer, text, text, text, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.editar_loja(integer, text, text, text, integer, integer) TO authenticated;

-- A gravação direta em lojas fecha (as funções acima fazem o mesmo).
REVOKE INSERT, UPDATE, DELETE ON public.lojas FROM authenticated;
REVOKE INSERT (ativa, cidade, contaid, criadoem, endereco, gestorid, lojaid, mostrarvalorestv, nome,
               responsavelagendamentosid, somrepetirminutos, somtarefanova, somvolume, tvblocos, tvsegundos),
       UPDATE (ativa, cidade, contaid, criadoem, endereco, gestorid, lojaid, mostrarvalorestv, nome,
               responsavelagendamentosid, somrepetirminutos, somtarefanova, somvolume, tvblocos, tvsegundos)
  ON public.lojas FROM authenticated;


COMMIT;
