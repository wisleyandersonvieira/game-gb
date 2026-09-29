-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 4: Metas.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-feedbacks.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929253000_metas_permissoes.sql
--
-- O QUE MUDA: lançar venda, meta do mês, metas da semana e metas especiais
-- conferem permissão e loja no banco; as metas da semana e as especiais passam
-- a gravar por função. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 4: Metas (29/09/2026).
--
-- Meta é da LOJA. Lançar a venda do dia, a meta do mês, as metas por dia da
-- semana e as metas especiais conferem a permissão NA LOJA (pode). As metas
-- por dia da semana e as especiais eram gravadas direto na tabela pela tela:
-- viram funções, e a gravação direta fecha. Para o master nada muda.

-- ---------------------------------------------------------------------------
-- 1. As gravações que eram direto na tabela
-- ---------------------------------------------------------------------------
-- Metas por dia da semana: o que a tela fazia (upsert por loja e dia).
-- p_linhas: [{"diasemanaid": 1, "nomedia": "Domingo", "valormeta": 0, "pontospremio": 0}, ...]
CREATE OR REPLACE FUNCTION public.salvar_metas_da_semana(p_lojaid integer, p_linhas jsonb)
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
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.pode('metas.criar_meta', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer nas metas desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.metasdiariasmodelos (contaid, lojaid, diasemanaid, nomedia, valormeta, pontospremio)
  SELECT v_conta, p_lojaid, (l->>'diasemanaid')::integer, l->>'nomedia', (l->>'valormeta')::numeric, (l->>'pontospremio')::integer
    FROM jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) l
  ON CONFLICT (lojaid, diasemanaid) DO UPDATE
     SET nomedia = EXCLUDED.nomedia, valormeta = EXCLUDED.valormeta, pontospremio = EXCLUDED.pontospremio;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_metas_da_semana(integer, jsonb) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_metas_da_semana(integer, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.criar_meta_especial(p_lojaid integer, p_data date, p_descricao text,
                                                      p_valormeta numeric, p_pontospremio integer)
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
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.pode('metas.meta_especial', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite criar meta especial nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.metasespeciais (contaid, lojaid, data, descricao, valormeta, pontospremio)
  VALUES (v_conta, p_lojaid, p_data, p_descricao, p_valormeta, p_pontospremio)
  RETURNING metaespecialid INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.criar_meta_especial(integer, date, text, numeric, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.criar_meta_especial(integer, date, text, numeric, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.apagar_meta_especial(p_metaespecialid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_loja integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT lojaid INTO v_loja FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
  -- Não existe (ou é de outra conta): como antes, não apaga nada.
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT public.pode('metas.meta_especial', v_loja) THEN
    RAISE EXCEPTION 'Seu cargo não permite apagar meta especial nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
END;
$$;
REVOKE ALL ON FUNCTION public.apagar_meta_especial(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.apagar_meta_especial(integer) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.metasdiariasmodelos, public.metasespeciais FROM authenticated;

-- ---------------------------------------------------------------------------
-- 2. Lançar a venda e a meta do mês, partindo da versão VIVA no banco
-- ---------------------------------------------------------------------------
-- lancar_venda_do_dia: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.lancar_venda_do_dia(p_lojaid integer, p_dia date, p_valor numeric, p_motivo text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_hoje   date    := public.dia_em_sao_paulo(now());
  v_ap     public.metasdiariasapuracoes%ROWTYPE;
  v_meta   record;
  v_mp     integer;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Metas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('metas.lancar_venda', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite lançar a venda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_dia IS NULL OR p_dia > v_hoje THEN
    RAISE EXCEPTION 'Não dá para lançar venda de um dia que ainda não chegou.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < public.primeiro_dia_editavel_meta() THEN
    RAISE EXCEPTION 'Só dá para lançar ou corrigir vendas do mês atual e do mês anterior.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_valor IS NULL OR p_valor < 0 THEN
    RAISE EXCEPTION 'O valor vendido precisa ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;

  -- Um lancamento por vez para a mesma loja e dia, e para o mesmo mes.
  PERFORM pg_advisory_xact_lock(p_lojaid, p_dia - date '2000-01-01');
  PERFORM pg_advisory_xact_lock(p_lojaid, -(extract(year FROM p_dia)::integer * 12 + extract(month FROM p_dia)::integer));

  SELECT * INTO v_ap FROM public.metasdiariasapuracoes WHERE lojaid = p_lojaid AND dataapuracao = p_dia;

  IF NOT FOUND THEN
    SELECT * INTO v_meta FROM public.meta_do_dia(p_lojaid, p_dia);
    SELECT metaprincipalid INTO v_mp FROM public.metasprincipais
     WHERE lojaid = p_lojaid AND datainicio = date_trunc('month', p_dia)::date;
    INSERT INTO public.metasdiariasapuracoes (contaid, lojaid, metaprincipalid, dataapuracao, valordia,
                                              valormetadia, pontosmetadia, origemmeta, descricaometa,
                                              lancadopor, atualizadopor)
    VALUES (v_conta, p_lojaid, v_mp, p_dia, round(p_valor, 2),
            v_meta.valormeta, coalesce(v_meta.pontospremio, 0), v_meta.origem, v_meta.descricao,
            auth.uid(), auth.uid())
    RETURNING apuracaoid INTO v_id;
    INSERT INTO public.metashistorico (contaid, lojaid, apuracaoid, dataapuracao, valoranterior, valornovo, motivo, alteradopor)
    VALUES (v_conta, p_lojaid, v_id, p_dia, NULL, round(p_valor, 2), v_motivo, auth.uid());
  ELSE
    v_id := v_ap.apuracaoid;
    IF v_ap.valordia = round(p_valor, 2) THEN
      RETURN v_id;   -- nada mudou
    END IF;
    IF v_motivo IS NULL THEN
      RAISE EXCEPTION 'Este dia já tem lançamento. Para corrigir, informe o motivo.' USING ERRCODE = 'check_violation';
    END IF;
    UPDATE public.metasdiariasapuracoes
       SET valordia = round(p_valor, 2), atualizadopor = auth.uid(), atualizadoem = now()
     WHERE apuracaoid = v_id;
    INSERT INTO public.metashistorico (contaid, lojaid, apuracaoid, dataapuracao, valoranterior, valornovo, motivo, alteradopor)
    VALUES (v_conta, p_lojaid, v_id, p_dia, v_ap.valordia, round(p_valor, 2), v_motivo, auth.uid());
  END IF;

  PERFORM public.reavaliar_meta_do_dia(v_id);
  PERFORM public.reavaliar_meta_do_mes(v_conta, p_lojaid, p_dia);
  RETURN v_id;
END;
$function$;

-- salvar_meta_do_mes: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.salvar_meta_do_mes(p_lojaid integer, p_mes date, p_nome text, p_valor numeric, p_pontos integer, p_descricao text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_ini   date := date_trunc('month', p_mes)::date;
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Metas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('metas.criar_meta', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer na meta do mês desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_ini < public.primeiro_dia_editavel_meta() THEN
    RAISE EXCEPTION 'Só dá para mexer na meta do mês atual, do anterior e dos próximos.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_valor IS NULL OR p_valor <= 0 THEN
    RAISE EXCEPTION 'A meta do mês precisa ser maior que zero.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_pontos IS NULL OR p_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos do prêmio precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM pg_advisory_xact_lock(p_lojaid, -(extract(year FROM v_ini)::integer * 12 + extract(month FROM v_ini)::integer));

  INSERT INTO public.metasprincipais (contaid, lojaid, nomemeta, descricao, valormetatotal, datainicio, datafim,
                                      pontospremio, criadopor)
  VALUES (v_conta, p_lojaid, coalesce(nullif(btrim(coalesce(p_nome, '')), ''), 'Meta de ' || to_char(v_ini, 'MM/YYYY')),
          nullif(btrim(coalesce(p_descricao, '')), ''), round(p_valor, 2), v_ini,
          (v_ini + interval '1 month - 1 day')::date, p_pontos, auth.uid())
  ON CONFLICT (lojaid, datainicio) DO UPDATE
     SET nomemeta = EXCLUDED.nomemeta, descricao = EXCLUDED.descricao,
         valormetatotal = EXCLUDED.valormetatotal, pontospremio = EXCLUDED.pontospremio, atualizadoem = now()
  RETURNING metaprincipalid INTO v_id;

  -- Lancamentos do mes que ainda nao estavam ligados a meta.
  UPDATE public.metasdiariasapuracoes SET metaprincipalid = v_id
   WHERE lojaid = p_lojaid AND dataapuracao BETWEEN v_ini AND (v_ini + interval '1 month - 1 day')::date
     AND metaprincipalid IS DISTINCT FROM v_id;

  PERFORM public.reavaliar_meta_do_mes(v_conta, p_lojaid, v_ini);
  RETURN v_id;
END;
$function$;


COMMIT;
