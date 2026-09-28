-- =========================================================================
-- STGame — TV: a faixa "Meta do mês".
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-barra-da-fila.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929241000_faixa_meta_do_mes.sql
--
-- O QUE MUDA: Lojas -> Configurar TV ganha a faixa "Meta do mês"
-- (desmarcada por padrão: a TV de quem não mexer fica igual). Nenhum dado é
-- alterado.
-- =========================================================================


BEGIN;

-- TV: a faixa "Meta do mês" (29/09/2026, pedido do Wisley).
--
-- Mais uma faixa fina, marcável em Lojas -> Configurar TV como as outras
-- duas, em todas as telas: o nome da meta do mês, o progresso e o
-- percentual. Os dados já vinham para a TV (meta_para_painel -> 'mes'); o
-- valor em R$ só vem quando a loja marcou "Mostrar valores em R$", regra que
-- já mora no banco (a TV nem recebe o número).
--
-- Muda só a configuração: a chave nova 'metames' (desmarcada por padrão; a
-- TV de quem não mexer fica igual) e "mostrar R$" valendo para qualquer
-- faixa de meta.

-- Parte da versão mais recente (20260929101100_tv_configuravel.sql), com o
-- diff conferido: entra 'metames' na lista de chaves.
CREATE OR REPLACE FUNCTION public.salvar_tv_da_loja(
  p_lojaid   integer,
  p_blocos   jsonb,
  p_segundos integer,
  p_valores  boolean
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_limpo jsonb   := '{}'::jsonb;
  k       text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF coalesce(p_segundos, 60) NOT IN (30, 60, 120) THEN
    RAISE EXCEPTION 'O tempo da troca é 30, 60 ou 120 segundos.' USING ERRCODE = 'check_violation';
  END IF;

  -- Só as chaves que a gente conhece entram: o navegador não inventa bloco.
  FOREACH k IN ARRAY ARRAY['barra', 'meta', 'metames', 'parafazer', 'emandamento',
                           'emvalidacao', 'atividade', 'podiohoje', 'podiomes'] LOOP
    v_limpo := v_limpo || jsonb_build_object(k, coalesce((p_blocos->>k)::boolean, false));
  END LOOP;

  UPDATE public.lojas
     SET tvblocos = v_limpo,
         tvsegundos = coalesce(p_segundos, 60),
         mostrarvalorestv = coalesce(p_valores, false)
   WHERE lojaid = p_lojaid AND contaid = v_conta;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_tv_da_loja(integer, jsonb, integer, boolean) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.salvar_tv_da_loja(integer, jsonb, integer, boolean) TO authenticated, service_role;

-- Parte da versão mais recente (20260929101100_tv_configuravel.sql), com o
-- diff conferido: "valores" vale com a faixa do dia OU a do mês.
CREATE OR REPLACE FUNCTION public.tv_blocos_da_loja(p_contaid integer, p_lojaid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_blocos jsonb;
  v_valores boolean;
  v_algum  boolean;
BEGIN
  SELECT tvblocos, mostrarvalorestv INTO v_blocos, v_valores
    FROM public.lojas WHERE lojaid = p_lojaid AND contaid = p_contaid;

  -- Alguma coluna marcada? Só as faixas não fazem uma tela.
  SELECT coalesce(bool_or((v_blocos->>k)::boolean), false) INTO v_algum
    FROM unnest(ARRAY['parafazer', 'emandamento', 'emvalidacao',
                      'atividade', 'podiohoje', 'podiomes']) k;

  IF v_blocos IS NULL OR NOT v_algum THEN
    v_blocos := public.tv_blocos_padrao();
  END IF;

  -- "Mostrar valores em R$" mora aqui agora, e só faz sentido com uma das
  -- faixas de meta (a do dia ou a do mês, 29/09/2026).
  RETURN v_blocos || jsonb_build_object(
    'valores', coalesce(v_valores, false)
               AND (coalesce((v_blocos->>'meta')::boolean, false) OR coalesce((v_blocos->>'metames')::boolean, false)));
END;
$$;
REVOKE ALL ON FUNCTION public.tv_blocos_da_loja(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tv_blocos_da_loja(integer, integer) TO service_role;

COMMIT;
