-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 6: Solicitações.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-tarefas.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929255000_solicitacoes_permissoes.sql
--
-- O QUE MUDA: abrir, mudar a situação e recusar conferem permissão e loja no
-- banco. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 6: Solicitações (29/09/2026).
--
-- Abrir, mudar a situação e recusar conferem a permissão NA LOJA da
-- solicitação. Recusar é "solicitacoes.recusar"; qualquer outra mudança de
-- situação (em andamento, concluída) é "solicitacoes.concluir". Para o master
-- nada muda.

-- abrir_solicitacao: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.abrir_solicitacao(p_lojaid integer, p_funcionarioid integer, p_tipo text, p_categoria text, p_descricao text, p_quantidade numeric DEFAULT NULL::numeric, p_unidade text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Solicitações).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('solicitacoes.abrir', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite abrir solicitações nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarioslojas
                  WHERE funcionarioid = p_funcionarioid AND lojaid = p_lojaid AND contaid = v_conta AND ativo) THEN
    RAISE EXCEPTION 'Quem pediu precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_descricao, ''))) = 0 THEN
    RAISE EXCEPTION 'Descreva o pedido.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_tipo NOT IN ('Compra', 'Manutencao') THEN
    RAISE EXCEPTION 'Tipo inválido.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM set_config('gamegb.observacao', '', true);
  INSERT INTO public.solicitacoesinternas (contaid, lojaid, funcionarioid, tipo, categoria, descricao,
                                           quantidade, unidade, registradopor)
  VALUES (v_conta, p_lojaid, p_funcionarioid, p_tipo, nullif(btrim(coalesce(p_categoria, '')), ''),
          btrim(p_descricao), CASE WHEN p_tipo = 'Compra' THEN p_quantidade END,
          CASE WHEN p_tipo = 'Compra' THEN nullif(btrim(coalesce(p_unidade, '')), '') END, auth.uid())
  RETURNING solicitacaoid INTO v_id;
  RETURN v_id;
END;
$function$;

-- mudar_situacao_solicitacao: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.mudar_situacao_solicitacao(p_solicitacaoid integer, p_status text, p_observacao text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_obs   text := nullif(btrim(coalesce(p_observacao, '')), '');
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_status = 'Recusada' AND v_obs IS NULL THEN
    RAISE EXCEPTION 'Para recusar, informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM 1 FROM public.solicitacoesinternas WHERE solicitacaoid = p_solicitacaoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitação não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Solicitações).
  IF NOT public.bot_contexto_confiavel() THEN
    IF p_status = 'Recusada' THEN
      IF NOT public.pode('solicitacoes.recusar', (SELECT lojaid FROM public.solicitacoesinternas
                                                   WHERE solicitacaoid = p_solicitacaoid AND contaid = v_conta)) THEN
        RAISE EXCEPTION 'Seu cargo não permite recusar solicitações nesta loja.' USING ERRCODE = 'insufficient_privilege';
      END IF;
    ELSIF NOT public.pode('solicitacoes.concluir', (SELECT lojaid FROM public.solicitacoesinternas
                                                     WHERE solicitacaoid = p_solicitacaoid AND contaid = v_conta)) THEN
      RAISE EXCEPTION 'Seu cargo não permite mudar a situação de solicitações nesta loja.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  PERFORM set_config('gamegb.observacao', coalesce(v_obs, ''), true);
  UPDATE public.solicitacoesinternas
     SET status = p_status,
         motivorecusa = CASE WHEN p_status = 'Recusada' THEN v_obs ELSE motivorecusa END
   WHERE solicitacaoid = p_solicitacaoid;
  PERFORM set_config('gamegb.observacao', '', true);
END;
$function$;


COMMIT;
