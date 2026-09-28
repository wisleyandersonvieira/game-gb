-- =========================================================================
-- STGame — TV: a tela "Meta especial".
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-inicio-da-fila.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929243000_tela_meta_especial.sql
--
-- O QUE MUDA: a TV passa a receber a meta especial de hoje (nome, pontos
-- para cada um, lançada ou não, batida). Configurar TV ganha "Meta
-- especial" (desmarcada por padrão). Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- TV: a tela "Meta especial" (29/09/2026, pedido do Wisley).
--
-- Nos dias com meta especial (Metas -> Metas especiais, com valor), ela vira
-- uma tela inteira no rodízio da TV: o nome enorme, os pontos para cada um
-- da equipe, o progresso e, quando batida, a comemoração. Nos outros dias
-- não existe. Usa só o que já existe: metasespeciais, o lançamento da venda
-- do dia e o prêmio pago no lançamento.
--
--   * meta_para_painel ganha 'especial' (três estados: não lançada,
--     lançada, batida). R$ só com "Mostrar valores em R$", como o resto.
--     O dia passa a vir de hoje_da_conta (o lugar único).
--   * Configurar TV ganha a chave 'metaespecial' (desmarcada por padrão).

-- Parte da versão mais recente (20260922200000_metas_de_faturamento.sql), com
-- o diff conferido: entra 'especial'; o dia vem de hoje_da_conta.
CREATE OR REPLACE FUNCTION public.meta_para_painel(p_contaid integer, p_lojaid integer, p_tv boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje    date := public.hoje_da_conta(p_contaid);
  v_valores boolean;
  v_ap      public.metasdiariasapuracoes%ROWTYPE;
  v_md      record;
  v_meta    numeric;
  v_vendido numeric;
  v_dia     jsonb;
  v_mes     jsonb;
  m         public.metasprincipais%ROWTYPE;
  v_total   numeric;
  v_dias    integer;
  v_esp     jsonb;
  v_pontos  integer;
BEGIN
  SELECT NOT p_tv OR mostrarvalorestv INTO v_valores
    FROM public.lojas WHERE lojaid = p_lojaid AND contaid = p_contaid;

  -- Meta de hoje: a guardada no lancamento, ou a do modelo/especial.
  SELECT * INTO v_ap FROM public.metasdiariasapuracoes WHERE lojaid = p_lojaid AND dataapuracao = v_hoje;
  SELECT * INTO v_md FROM public.meta_do_dia(p_lojaid, v_hoje);
  v_meta := coalesce(v_ap.valormetadia, v_md.valormeta);
  v_vendido := coalesce(v_ap.valordia, 0);
  IF coalesce(v_meta, 0) > 0 THEN
    v_dia := jsonb_build_object(
      'percentual', round(v_vendido * 100 / v_meta, 1),
      'bateu',      v_vendido >= v_meta,
      'lancado',    v_ap.apuracaoid IS NOT NULL,
      'especial',   CASE WHEN coalesce(v_ap.origemmeta, v_md.origem) = 'especial'
                         THEN coalesce(v_ap.descricaometa, v_md.descricao) END);
    IF v_valores THEN
      v_dia := v_dia || jsonb_build_object('vendido', v_vendido, 'meta', v_meta);
    END IF;
  END IF;

  -- META ESPECIAL de hoje (29/09/2026): a tela inteira da TV. Só a que tem
  -- VALOR (a sem valor é "dia sem meta": nunca é batida nem paga). Três
  -- estados, sem número inventado:
  --   * ninguém lançou a venda de hoje: 'lancado' = false, sem percentual;
  --   * lançada: percentual e se bateu; em R$ só com "mostrar valores";
  --   * batida: 'bateu' = true (o prêmio é pago no lançamento).
  -- Os pontos são para CADA pessoa da equipe (pagar_premio_meta).
  IF coalesce(v_ap.origemmeta, v_md.origem) = 'especial' AND coalesce(v_meta, 0) > 0 THEN
    v_pontos := CASE WHEN v_ap.apuracaoid IS NOT NULL THEN v_ap.pontosmetadia ELSE v_md.pontospremio END;
    v_esp := jsonb_build_object(
      'nome',    coalesce(v_ap.descricaometa, v_md.descricao),
      'pontos',  coalesce(v_pontos, 0),
      'lancado', v_ap.apuracaoid IS NOT NULL);
    IF v_ap.apuracaoid IS NOT NULL THEN
      v_esp := v_esp || jsonb_build_object(
        'percentual', round(v_vendido * 100 / v_meta, 1),
        'bateu',      v_vendido >= v_meta);
      IF v_valores THEN
        v_esp := v_esp || jsonb_build_object('vendido', v_vendido, 'meta', v_meta,
                                             'falta', greatest(v_meta - v_vendido, 0));
      END IF;
    END IF;
  END IF;

  SELECT * INTO m FROM public.metasprincipais
   WHERE lojaid = p_lojaid AND contaid = p_contaid AND v_hoje BETWEEN datainicio AND datafim;
  IF FOUND THEN
    SELECT coalesce(sum(valordia), 0), count(*) INTO v_total, v_dias
      FROM public.metasdiariasapuracoes WHERE lojaid = p_lojaid AND dataapuracao BETWEEN m.datainicio AND m.datafim;
    v_mes := jsonb_build_object(
      'nome',       m.nomemeta,
      'percentual', round(v_total * 100 / m.valormetatotal, 1),
      'bateu',      v_total >= m.valormetatotal);
    IF v_valores THEN
      v_mes := v_mes || jsonb_build_object(
        'vendido', v_total, 'meta', m.valormetatotal,
        'projecao', CASE WHEN v_dias > 0
                         THEN round(v_total / v_dias * (m.datafim - m.datainicio + 1), 2) END);
    END IF;
  END IF;

  IF v_dia IS NULL AND v_mes IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('dia', v_dia, 'mes', v_mes, 'valores', v_valores)
         || CASE WHEN v_esp IS NOT NULL THEN jsonb_build_object('especial', v_esp) ELSE '{}'::jsonb END;
END;
$$;
REVOKE ALL ON FUNCTION public.meta_para_painel(integer, integer, boolean) FROM public, anon, authenticated;

-- Parte da versão mais recente (20260929241000_faixa_meta_do_mes.sql), com o
-- diff conferido: entra 'metaespecial' na lista de chaves.
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
$$;
REVOKE ALL ON FUNCTION public.salvar_tv_da_loja(integer, jsonb, integer, boolean) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.salvar_tv_da_loja(integer, jsonb, integer, boolean) TO authenticated, service_role;

COMMIT;
