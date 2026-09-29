-- =========================================================================
-- STGame — Usuários gerenciais, PARTES 2 e 3, e os dois consertos de lentidão.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: o banco precisa já ter a fatia do Quadro (parte 2, fatia 1:
-- aplicar-permissoes-parte-2-quadro.sql), que está no ar desde 29/09.
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo tem 21 migrações, nesta ordem (as mesmas dos arquivos de
-- aplicar de cada fatia, que continuam valendo um por um):
--    1. 20260929251000_premios_permissoes.sql
--    2. 20260929252000_feedbacks_permissoes.sql
--    3. 20260929253000_metas_permissoes.sql
--    4. 20260929254000_tarefas_permissoes.sql
--    5. 20260929255000_solicitacoes_permissoes.sql
--    6. 20260929256000_justificativas_permissoes.sql
--    7. 20260929257000_agenda_permissoes.sql
--    8. 20260929258000_comunicados_permissoes.sql
--    9. 20260929259000_conquistas_permissoes.sql
--   10. 20260929260000_onboarding_permissoes.sql
--   11. 20260929261000_lojas_permissoes.sql
--   12. 20260929262000_equipe_permissoes.sql
--   13. 20260929263000_rh_canal_so_master.sql
--   14. 20260929264000_leituras_painel_fila.sql
--   15. 20260929265000_leituras_quadro.sql
--   16. 20260929265500_desempate_nas_listas.sql
--   17. 20260929265700_fila_fuso_uma_vez.sql
--   18. 20260929266000_leituras_inicio_menu.sql
--   19. 20260929267000_leituras_relatorios.sql
--   20. 20260929268000_leituras_metas.sql
--   21. 20260929268500_lojas_do_gerente_uma_vez.sql
-- Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================

BEGIN;

-- ------------------------------------------------------------------------
-- 20260929251000_premios_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 2: Prêmios (29/09/2026).
--
-- 1. Registrar resgate (prêmio ou abate na comanda), entregar, cancelar e
--    estornar conferem a permissão e a loja no banco (pode). O gerente só
--    resgata para quem trabalha na loja dele, e ninguém registra, entrega,
--    cancela nem estorna o PRÓPRIO resgate.
-- 2. O catálogo de prêmios é da conta inteira (produtosloja = loja de
--    RECOMPENSAS): só o master mexe, agora por função; a gravação direta na
--    tabela fecha.
-- 3. A lista de estornos passa a mostrar resgates cancelados e estornados.
-- 4. Configurações: só o master, com o gerente RECONHECIDO (antes ele era
--    barrado por não ter conta, e o teste passava pelo motivo errado).
-- Para o master nada muda na tela.

-- ---------------------------------------------------------------------------
-- 1. O catálogo de prêmios: só o master, por função
-- ---------------------------------------------------------------------------
-- Faz exatamente o que a tela fazia direto na tabela (as mesmas colunas, as
-- mesmas regras da tabela), com a conta vinda do banco.
-- Prêmio novo: sem p_produtoid. Descrição e estoque vazios = sem descrição e
-- estoque ilimitado, como na tela.
CREATE OR REPLACE FUNCTION public.salvar_premio(p_nome text, p_custoempontos integer,
                                                p_produtoid integer DEFAULT NULL, p_descricao text DEFAULT NULL,
                                                p_estoquedisponivel integer DEFAULT NULL)
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
  -- O catálogo vale para todas as lojas: só o master (decisão do Wisley).
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de prêmios.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_produtoid IS NULL THEN
    INSERT INTO public.produtosloja (contaid, nome, descricao, custoempontos, estoquedisponivel)
    VALUES (v_conta, p_nome, p_descricao, p_custoempontos, p_estoquedisponivel)
    RETURNING produtoid INTO v_id;
  ELSE
    UPDATE public.produtosloja
       SET nome = p_nome, descricao = p_descricao, custoempontos = p_custoempontos, estoquedisponivel = p_estoquedisponivel
     WHERE contaid = v_conta AND produtoid = p_produtoid
    RETURNING produtoid INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Prêmio não encontrado.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_premio(text, integer, integer, text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_premio(text, integer, integer, text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_premio(p_produtoid integer, p_ativo boolean)
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
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de prêmios.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.produtosloja SET ativo = p_ativo WHERE contaid = v_conta AND produtoid = p_produtoid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prêmio não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_premio(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_premio(integer, boolean) TO authenticated;

-- A gravação direta no catálogo fecha (as funções acima fazem o mesmo).
REVOKE INSERT, UPDATE, DELETE ON public.produtosloja FROM authenticated;

-- ---------------------------------------------------------------------------
-- 2. A lista de estornos, com os resgates
-- ---------------------------------------------------------------------------
-- estornos_da_conta: parte de 20260929250000_quadro_permissoes.sql (entram os resgates)
CREATE OR REPLACE FUNCTION public.estornos_da_conta(p_lojaid integer DEFAULT NULL)
RETURNS TABLE (tipo text, quando timestamptz, lojaid integer, loja text, pessoa text,
               descricao text, pontos integer, motivo text, quem text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta vê a lista de estornos.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT 'entrega'::text, e.dataestorno, e.lojaid, l.nome::text, f.nomecompleto::text,
         t.titulo::text, -coalesce(e.pontosganhos, 0), e.motivoestorno::text,
         coalesce(public.autor_em(e.estornadopor, e.dataestorno), 'desconhecido')
    FROM public.entregas e
    JOIN public.lojas l ON l.contaid = e.contaid AND l.lojaid = e.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = e.contaid AND f.funcionarioid = e.funcionarioid
    LEFT JOIN public.tarefas t ON t.contaid = e.contaid AND t.tarefaid = e.tarefaid
   WHERE e.contaid = v_conta AND e.statusvalidacao = 'Estornada'
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  UNION ALL
  -- Resgates cancelados (antes de entregar) e estornados (depois): os pontos
  -- voltam para a pessoa. Resgate registrado sem loja só aparece na lista de
  -- todas as lojas (p_lojaid vazio).
  SELECT CASE r.status WHEN 'Cancelado' THEN 'resgate cancelado' ELSE 'resgate estornado' END,
         CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END,
         r.lojaid, l.nome::text, f.nomecompleto::text,
         CASE WHEN r.valorreais IS NOT NULL THEN 'abate na comanda de ' || public.reais(r.valorreais) ELSE p.nome::text END,
         r.pontosgastos,
         (CASE r.status WHEN 'Cancelado' THEN r.motivocancelamento ELSE r.motivoestorno END)::text,
         coalesce(public.autor_em(CASE r.status WHEN 'Cancelado' THEN r.canceladopor ELSE r.estornadopor END,
                                  CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END), 'desconhecido')
    FROM public.resgates r
    LEFT JOIN public.lojas l ON l.contaid = r.contaid AND l.lojaid = r.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = r.contaid AND f.funcionarioid = r.funcionarioid
    LEFT JOIN public.produtosloja p ON p.contaid = r.contaid AND p.produtoid = r.produtoid
   WHERE r.contaid = v_conta AND r.status IN ('Cancelado', 'Estornado')
     AND (p_lojaid IS NULL OR r.lojaid = p_lojaid)
   -- Desempate fixo: dois estornos no mesmo instante saem sempre na mesma ordem.
   ORDER BY 2 DESC, 1, 6, 5, 9, 8
   LIMIT 500;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Os resgates e as configurações, cada um partindo da versão VIVA no banco
-- ---------------------------------------------------------------------------
-- registrar_troca: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.registrar_troca(p_funcionarioid integer, p_produtoid integer, p_lojaid integer DEFAULT NULL::integer, p_entregar boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_func  public.funcionarios%ROWTYPE;
  v_prod  public.produtosloja%ROWTYPE;
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Prêmios). O
  -- servidor (celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('premios.registrar', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite registrar resgates nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém registra o PRÓPRIO resgate (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém registra o próprio resgate.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- O gerente só resgata para quem trabalha na loja dele (o master, como antes).
  IF NOT public.bot_contexto_confiavel() AND NOT public.sou_master()
     AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                      WHERE fl.contaid = v_conta AND fl.funcionarioid = p_funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo) THEN
    RAISE EXCEPTION 'Esta pessoa não trabalha nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_func.ativo THEN
    RAISE EXCEPTION 'Funcionário inativo não resgata prêmios.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_prod FROM public.produtosloja
   WHERE produtoid = p_produtoid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prêmio não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_prod.sistema IS NOT NULL THEN
    RAISE EXCEPTION 'Para abater na comanda, use o abate na comanda.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT v_prod.ativo THEN
    RAISE EXCEPTION 'O prêmio "%" está desativado.', v_prod.nome USING ERRCODE = 'check_violation';
  END IF;
  IF v_prod.estoquedisponivel IS NOT NULL AND v_prod.estoquedisponivel <= 0 THEN
    RAISE EXCEPTION 'Esgotado: não há mais "%" em estoque.', v_prod.nome USING ERRCODE = 'check_violation';
  END IF;
  IF v_func.saldopontos < v_prod.custoempontos THEN
    RAISE EXCEPTION 'Saldo insuficiente: % tem % pontos e "%" custa %.',
      v_func.nomecompleto, v_func.saldopontos, v_prod.nome, v_prod.custoempontos
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_lojaid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO public.resgates (contaid, funcionarioid, produtoid, lojaid, pontosgastos, datasolicitacao,
                               status, registradopor, dataentrega, entreguepor)
  VALUES (v_conta, p_funcionarioid, p_produtoid, p_lojaid, v_prod.custoempontos, now(),
          CASE WHEN p_entregar THEN 'Entregue' ELSE 'Pendente' END, auth.uid(),
          CASE WHEN p_entregar THEN now() END, CASE WHEN p_entregar THEN auth.uid() END)
  RETURNING resgateid INTO v_id;

  IF v_prod.estoquedisponivel IS NOT NULL THEN
    UPDATE public.produtosloja SET estoquedisponivel = estoquedisponivel - 1 WHERE produtoid = p_produtoid;
  END IF;

  INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, tipo, pontos, descricao, resgateid, criadopor)
  VALUES (v_conta, p_funcionarioid, p_lojaid, 'resgate', -v_prod.custoempontos,
          'Resgate: ' || v_prod.nome, v_id, auth.uid());

  RETURN v_id;
END;
$function$;

-- registrar_troca_por_valor: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.registrar_troca_por_valor(p_funcionarioid integer, p_valorreais numeric, p_lojaid integer DEFAULT NULL::integer, p_entregar boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_func    public.funcionarios%ROWTYPE;
  v_produto integer;
  v_valor   numeric(10,2) := round(p_valorreais, 2);
  v_taxa    numeric;
  v_pontos  integer;
  v_id      integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_valor IS NULL OR v_valor <= 0 THEN
    RAISE EXCEPTION 'Informe um valor maior que zero.' USING ERRCODE = 'check_violation';
  END IF;

  v_taxa := public.taxa_da_conta(v_conta);
  IF v_taxa IS NULL THEN
    RAISE EXCEPTION 'A taxa de conversão de pontos em reais não está configurada.' USING ERRCODE = 'check_violation';
  END IF;
  v_pontos := ceil(v_valor / v_taxa)::integer;

  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Prêmios). O
  -- servidor (celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('premios.registrar', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite registrar resgates nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém registra o PRÓPRIO resgate (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém registra o próprio resgate.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- O gerente só resgata para quem trabalha na loja dele (o master, como antes).
  IF NOT public.bot_contexto_confiavel() AND NOT public.sou_master()
     AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                      WHERE fl.contaid = v_conta AND fl.funcionarioid = p_funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo) THEN
    RAISE EXCEPTION 'Esta pessoa não trabalha nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_func.ativo THEN
    RAISE EXCEPTION 'Funcionário inativo não resgata prêmios.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_func.saldopontos < v_pontos THEN
    RAISE EXCEPTION 'Saldo insuficiente: % tem % pontos (%) e abater % custa % pontos.',
      v_func.nomecompleto, v_func.saldopontos, public.reais(v_func.saldopontos * v_taxa),
      public.reais(v_valor), v_pontos
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_lojaid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT produtoid INTO v_produto FROM public.produtosloja WHERE contaid = v_conta AND sistema = 'abate_comanda';
  IF v_produto IS NULL THEN
    RAISE EXCEPTION 'O abate na comanda não está configurado nesta conta.' USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO public.resgates (contaid, funcionarioid, produtoid, lojaid, pontosgastos, valorreais, taxaconversao,
                               datasolicitacao, status, registradopor, dataentrega, entreguepor)
  VALUES (v_conta, p_funcionarioid, v_produto, p_lojaid, v_pontos, v_valor, v_taxa, now(),
          CASE WHEN p_entregar THEN 'Entregue' ELSE 'Pendente' END, auth.uid(),
          CASE WHEN p_entregar THEN now() END, CASE WHEN p_entregar THEN auth.uid() END)
  RETURNING resgateid INTO v_id;

  INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, tipo, pontos, descricao, resgateid, criadopor)
  VALUES (v_conta, p_funcionarioid, p_lojaid, 'resgate', -v_pontos,
          'Abate na comanda: ' || public.reais(v_valor), v_id, auth.uid());

  RETURN v_id;
END;
$function$;

-- concluir_troca: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.concluir_troca(p_resgateid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_status text;
  v_loja   integer;
  v_pessoa integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT status, lojaid, funcionarioid INTO v_status, v_loja, v_pessoa FROM public.resgates
   WHERE resgateid = p_resgateid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Resgate não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Prêmios). O
  -- servidor (celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('premios.entregar', v_loja) THEN
    RAISE EXCEPTION 'Seu cargo não permite entregar resgates nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém entrega o PRÓPRIO resgate (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_pessoa) THEN
    RAISE EXCEPTION 'Ninguém entrega o próprio resgate.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_status <> 'Pendente' THEN
    RAISE EXCEPTION 'Só um resgate pendente pode ser entregue. Este está: %.', v_status USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.resgates SET status = 'Entregue', dataentrega = now(), entreguepor = auth.uid()
   WHERE resgateid = p_resgateid;
END;
$function$;

-- desfazer_resgate: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.desfazer_resgate(p_resgateid integer, p_de text, p_para text, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_resgate public.resgates%ROWTYPE;
  v_nome    text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_resgate FROM public.resgates
   WHERE resgateid = p_resgateid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Resgate não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_resgate.status <> p_de THEN
    RAISE EXCEPTION 'Só um resgate % pode ser %. Este está: %.',
      lower(p_de), CASE p_para WHEN 'Cancelado' THEN 'cancelado' ELSE 'estornado' END, v_resgate.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Mesma ordem de travas do resgate: pessoa, depois premio.
  PERFORM 1 FROM public.funcionarios WHERE funcionarioid = v_resgate.funcionarioid FOR UPDATE;
  SELECT nome INTO v_nome FROM public.produtosloja WHERE produtoid = v_resgate.produtoid FOR UPDATE;

  IF p_para = 'Cancelado' THEN
    UPDATE public.resgates SET status = 'Cancelado', motivocancelamento = btrim(p_motivo),
           datacancelamento = now(), canceladopor = auth.uid()
     WHERE resgateid = p_resgateid;
  ELSE
    UPDATE public.resgates SET status = 'Estornado', motivoestorno = btrim(p_motivo),
           dataestorno = now(), estornadopor = auth.uid()
     WHERE resgateid = p_resgateid;
  END IF;

  UPDATE public.produtosloja SET estoquedisponivel = estoquedisponivel + 1
   WHERE produtoid = v_resgate.produtoid AND estoquedisponivel IS NOT NULL;

  INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, tipo, pontos, descricao, resgateid, criadopor)
  VALUES (v_conta, v_resgate.funcionarioid, v_resgate.lojaid,
          CASE WHEN p_para = 'Cancelado' THEN 'cancelamento_resgate' ELSE 'estorno_resgate' END,
          v_resgate.pontosgastos,
          CASE WHEN p_para = 'Cancelado' THEN 'Resgate cancelado: ' ELSE 'Resgate estornado: ' END
            || CASE WHEN v_resgate.valorreais IS NOT NULL
                    THEN 'abate na comanda de ' || public.reais(v_resgate.valorreais) ELSE v_nome END
            || ' (' || btrim(p_motivo) || ')',
          p_resgateid, auth.uid());
END;
$function$;

-- cancelar_troca: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.cancelar_troca(p_resgateid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_loja   integer;
  v_pessoa integer;
BEGIN
  -- Antes era um atalho de uma linha para desfazer_resgate. A permissão e a
  -- regra do próprio resgate ficam aqui, na função liberada; o resto continua
  -- igual, dentro de desfazer_resgate.
  SELECT lojaid, funcionarioid INTO v_loja, v_pessoa FROM public.resgates
   WHERE resgateid = p_resgateid AND contaid = v_conta;
  IF FOUND THEN
    -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Prêmios). O
    -- servidor (celular, bot) já conferiu quem é e não passa por aqui.
    IF NOT public.bot_contexto_confiavel() AND NOT public.pode('premios.cancelar', v_loja) THEN
      RAISE EXCEPTION 'Seu cargo não permite cancelar resgates nesta loja.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Ninguém cancela o PRÓPRIO resgate (o usuário gerencial ligado à pessoa).
    IF public.e_o_proprio(v_conta, v_pessoa) THEN
      RAISE EXCEPTION 'Ninguém cancela o próprio resgate.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  PERFORM public.desfazer_resgate(p_resgateid, 'Pendente', 'Cancelado', p_motivo);
END;
$function$;

-- estornar_troca: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.estornar_troca(p_resgateid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_loja   integer;
  v_pessoa integer;
BEGIN
  -- Antes era um atalho de uma linha para desfazer_resgate. A permissão e a
  -- regra do próprio resgate ficam aqui, na função liberada; o resto continua
  -- igual, dentro de desfazer_resgate.
  SELECT lojaid, funcionarioid INTO v_loja, v_pessoa FROM public.resgates
   WHERE resgateid = p_resgateid AND contaid = v_conta;
  IF FOUND THEN
    -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Prêmios). O
    -- servidor (celular, bot) já conferiu quem é e não passa por aqui.
    IF NOT public.bot_contexto_confiavel() AND NOT public.pode('premios.estornar', v_loja) THEN
      RAISE EXCEPTION 'Seu cargo não permite estornar resgates nesta loja.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Ninguém estorna o PRÓPRIO resgate (o usuário gerencial ligado à pessoa).
    IF public.e_o_proprio(v_conta, v_pessoa) THEN
      RAISE EXCEPTION 'Ninguém estorna o próprio resgate.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  PERFORM public.desfazer_resgate(p_resgateid, 'Entregue', 'Estornado', p_motivo);
END;
$function$;

-- alterar_configuracao: parte da versão viva no banco (todas as migrações aplicadas)
CREATE OR REPLACE FUNCTION public.alterar_configuracao(p_chave text, p_valor text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_novo  text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Só o master (decisão do Wisley). O gerente agora TEM conta aqui: quem o
  -- barra é esta regra, e o teste que prova isso deixou de ser pulado.
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta altera as configurações.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_chave LIKE 'TAREFA_%' THEN
    RAISE EXCEPTION 'Esta configuração é mantida pelo sistema.' USING ERRCODE = 'restrict_violation';
  END IF;

  UPDATE public.configuracoes SET valor = p_valor
   WHERE contaid = v_conta AND chave = p_chave
  RETURNING valor INTO v_novo;

  -- A chave pode não existir nesta conta: configuração criada numa versão
  -- posterior à conta. Antes isso dava "Configuração não encontrada" e não
  -- havia jeito de configurar. Agora criamos os padrões que faltam e
  -- tentamos de novo — cria_configuracoes_padrao não mexe no que já existe.
  IF NOT FOUND THEN
    PERFORM public.cria_configuracoes_padrao(v_conta);
    UPDATE public.configuracoes SET valor = p_valor
     WHERE contaid = v_conta AND chave = p_chave
    RETURNING valor INTO v_novo;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Configuração não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN v_novo;
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929252000_feedbacks_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 3: Feedbacks (29/09/2026).
--
-- O feedback é sobre uma PESSOA (não tem loja) e dá pontos. O gerente só dá
-- ou anula feedback de quem está INTEIRAMENTE dentro das lojas em que ele tem
-- a permissão (a mesma borda do "desativar pessoa"; decisão mais restritiva,
-- anotada para o Wisley), e nunca de si mesmo. Anular entra na lista de
-- estornos do master. Para o master nada muda.

-- ---------------------------------------------------------------------------
-- 1. pode_na_pessoa: a permissão sobre uma pessoa (não sobre uma loja)
-- ---------------------------------------------------------------------------
-- Master: pode() da conta (como sempre). Gerente: a pessoa tem pelo menos uma
-- loja ativa, e em TODAS elas ele tem a permissão. Interna.
CREATE OR REPLACE FUNCTION public.pode_na_pessoa(p_codigo text, p_contaid integer, p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN public.sou_master() THEN public.pode(p_codigo)
    ELSE EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid AND fl.ativo)
     AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                      WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                        AND NOT public.pode(p_codigo, fl.lojaid))
  END
$$;
REVOKE ALL ON FUNCTION public.pode_na_pessoa(text, integer, integer) FROM public, anon, authenticated;

-- registrar_feedback: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.registrar_feedback(p_funcionarioid integer, p_dia date, p_nota integer, p_comentario text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_hoje   date    := public.dia_em_sao_paulo(now());
  v_func   public.funcionarios%ROWTYPE;
  v_bonus  integer;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode_na_pessoa('feedbacks.registrar', v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Seu cargo não permite dar feedback a esta pessoa (ela precisa estar só nas suas lojas).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém dá feedback de si mesmo (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém dá feedback de si mesmo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_func.ativo THEN
    RAISE EXCEPTION 'Esta pessoa está inativa.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia IS NULL OR p_dia NOT IN (v_hoje, v_hoje - 1) THEN
    RAISE EXCEPTION 'O feedback só pode ser de hoje ou de ontem.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 0 AND 10 THEN
    RAISE EXCEPTION 'A nota vai de 0 a 10.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT CASE WHEN valor ~ '^[0-9]+$' THEN valor::integer ELSE 0 END INTO v_bonus
    FROM public.configuracoes WHERE contaid = v_conta AND chave = 'PONTOS_BONUS_FEEDBACK_DIARIO';
  v_bonus := coalesce(v_bonus, 0);

  BEGIN
    INSERT INTO public.feedbacks (contaid, funcionarioid, datafeedback, notadia, comentario, origem, registradopor, pontosbonus)
    VALUES (v_conta, p_funcionarioid, p_dia, p_nota, nullif(btrim(coalesce(p_comentario, '')), ''), public.origem_da_acao('bot'), auth.uid(), v_bonus)
    RETURNING feedbackid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION '% já tem feedback de %.', v_func.nomecompleto, to_char(p_dia, 'DD/MM/YYYY')
      USING ERRCODE = 'unique_violation';
  END;

  IF v_bonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, p_funcionarioid, 'bonus', v_bonus,
            'Feedback do dia ' || to_char(p_dia, 'DD/MM/YYYY'), v_id, auth.uid());
  END IF;

  PERFORM public.avaliar_conquistas(v_conta, p_funcionarioid);
  RETURN v_id;
END;
$function$;

-- anular_feedback: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.anular_feedback(p_feedbackid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_fb    public.feedbacks%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_fb FROM public.feedbacks WHERE feedbackid = p_feedbackid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Feedback não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode_na_pessoa('feedbacks.anular', v_conta, v_fb.funcionarioid) THEN
    RAISE EXCEPTION 'Seu cargo não permite anular feedback desta pessoa (ela precisa estar só nas suas lojas).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém anula feedback de si mesmo (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_fb.funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém anula feedback de si mesmo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_fb.anuladoem IS NOT NULL THEN
    RAISE EXCEPTION 'Este feedback já foi anulado.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.feedbacks
     SET anuladoem = now(), anuladopor = auth.uid(), motivoanulacao = btrim(p_motivo)
   WHERE feedbackid = p_feedbackid;

  IF v_fb.pontosbonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, v_fb.funcionarioid, 'estorno_bonus', -v_fb.pontosbonus,
            'Feedback do dia ' || to_char(v_fb.datafeedback, 'DD/MM/YYYY') || ' anulado: ' || btrim(p_motivo),
            p_feedbackid, auth.uid());
  END IF;
END;
$function$;

-- estornos_da_conta: parte de 20260929251000_premios_permissoes.sql (entram os feedbacks anulados)
CREATE OR REPLACE FUNCTION public.estornos_da_conta(p_lojaid integer DEFAULT NULL)
RETURNS TABLE (tipo text, quando timestamptz, lojaid integer, loja text, pessoa text,
               descricao text, pontos integer, motivo text, quem text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta vê a lista de estornos.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT 'entrega'::text, e.dataestorno, e.lojaid, l.nome::text, f.nomecompleto::text,
         t.titulo::text, -coalesce(e.pontosganhos, 0), e.motivoestorno::text,
         coalesce(public.autor_em(e.estornadopor, e.dataestorno), 'desconhecido')
    FROM public.entregas e
    JOIN public.lojas l ON l.contaid = e.contaid AND l.lojaid = e.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = e.contaid AND f.funcionarioid = e.funcionarioid
    LEFT JOIN public.tarefas t ON t.contaid = e.contaid AND t.tarefaid = e.tarefaid
   WHERE e.contaid = v_conta AND e.statusvalidacao = 'Estornada'
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  UNION ALL
  -- Resgates cancelados (antes de entregar) e estornados (depois): os pontos
  -- voltam para a pessoa. Resgate registrado sem loja só aparece na lista de
  -- todas as lojas (p_lojaid vazio).
  SELECT CASE r.status WHEN 'Cancelado' THEN 'resgate cancelado' ELSE 'resgate estornado' END,
         CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END,
         r.lojaid, l.nome::text, f.nomecompleto::text,
         CASE WHEN r.valorreais IS NOT NULL THEN 'abate na comanda de ' || public.reais(r.valorreais) ELSE p.nome::text END,
         r.pontosgastos,
         (CASE r.status WHEN 'Cancelado' THEN r.motivocancelamento ELSE r.motivoestorno END)::text,
         coalesce(public.autor_em(CASE r.status WHEN 'Cancelado' THEN r.canceladopor ELSE r.estornadopor END,
                                  CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END), 'desconhecido')
    FROM public.resgates r
    LEFT JOIN public.lojas l ON l.contaid = r.contaid AND l.lojaid = r.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = r.contaid AND f.funcionarioid = r.funcionarioid
    LEFT JOIN public.produtosloja p ON p.contaid = r.contaid AND p.produtoid = r.produtoid
   WHERE r.contaid = v_conta AND r.status IN ('Cancelado', 'Estornado')
     AND (p_lojaid IS NULL OR r.lojaid = p_lojaid)
  UNION ALL
  -- Feedbacks anulados: o bônus sai de volta da pessoa. Feedback não tem
  -- loja: aparece na lista de todas as lojas e na de cada loja da pessoa.
  SELECT 'feedback anulado', fb.anuladoem, NULL::integer, NULL::text, f.nomecompleto::text,
         'Feedback de ' || to_char(fb.datafeedback, 'DD/MM/YYYY') || ' (nota ' || fb.notadia || ')',
         -coalesce(fb.pontosbonus, 0), fb.motivoanulacao::text,
         coalesce(public.autor_em(fb.anuladopor, fb.anuladoem), 'desconhecido')
    FROM public.feedbacks fb
    LEFT JOIN public.funcionarios f ON f.contaid = fb.contaid AND f.funcionarioid = fb.funcionarioid
   WHERE fb.contaid = v_conta AND fb.anuladoem IS NOT NULL
     AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.contaid = fb.contaid AND fl.funcionarioid = fb.funcionarioid AND fl.lojaid = p_lojaid))
   -- Desempate fixo: dois estornos no mesmo instante saem sempre na mesma ordem.
   ORDER BY 2 DESC, 1, 6, 5, 9, 8
   LIMIT 500;
END;
$$;

-- ------------------------------------------------------------------------
-- 20260929253000_metas_permissoes.sql
-- ------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------
-- 20260929254000_tarefas_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 5: Tarefas (29/09/2026).
--
-- 1. Atribuir e mudar a hora conferem a permissão NA LOJA da atribuição;
--    encerrar atribuição também (vira função: a tela gravava direto).
-- 2. O CATÁLOGO (criar, editar, ativar/desativar e as lojas da tarefa) segue
--    a régua do alcance: o gerente só mexe em tarefa cujas lojas, antes E
--    depois da mudança, estão todas dentro das lojas em que ele tem a
--    permissão. Tarefa sem loja nenhuma: só o master. Vira UMA função (antes
--    eram três gravações separadas da tela).
-- 3. As três tabelas (tarefas, tarefaslojas, tarefasatribuidas) fecham para
--    gravação direta. Para o master nada muda.

-- ---------------------------------------------------------------------------
-- 1. O catálogo de tarefas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_tarefa(p_titulo text, p_pontos integer, p_lojas integer[],
                                                p_tarefaid integer DEFAULT NULL, p_descricao text DEFAULT NULL,
                                                p_setor text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_lojas integer[] := coalesce(p_lojas, ARRAY[]::integer[]);
  v_antes integer[];
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tarefaid IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = v_conta AND tarefaid = p_tarefaid) THEN
      RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    SELECT coalesce(array_agg(lojaid), ARRAY[]::integer[]) INTO v_antes
      FROM public.tarefaslojas WHERE contaid = v_conta AND tarefaid = p_tarefaid AND ativo;
  ELSE
    v_antes := ARRAY[]::integer[];
  END IF;
  -- A régua do alcance: todas as lojas de antes e de depois, com a permissão.
  -- Sem loja nenhuma, pode() da conta: só o master.
  IF (cardinality(v_antes || v_lojas) = 0 AND NOT public.pode('tarefas.catalogo'))
     OR EXISTS (SELECT 1 FROM unnest(v_antes || v_lojas) l WHERE NOT public.pode('tarefas.catalogo', l)) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer nesta tarefa: ela vale (ou passaria a valer) em loja fora das suas.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_tarefaid IS NULL THEN
    INSERT INTO public.tarefas (contaid, titulo, descricao, pontos, setor)
    VALUES (v_conta, p_titulo, p_descricao, p_pontos, p_setor)
    RETURNING tarefaid INTO v_id;
  ELSE
    UPDATE public.tarefas SET titulo = p_titulo, descricao = p_descricao, pontos = p_pontos, setor = p_setor
     WHERE contaid = v_conta AND tarefaid = p_tarefaid;
    v_id := p_tarefaid;
  END IF;

  -- As lojas, como a tela fazia: as escolhidas ativas, as outras desligadas.
  INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid, ativo)
  SELECT v_conta, v_id, l, true FROM unnest(v_lojas) l
  ON CONFLICT (tarefaid, lojaid) DO UPDATE SET ativo = true;
  UPDATE public.tarefaslojas SET ativo = false
   WHERE contaid = v_conta AND tarefaid = v_id AND NOT (lojaid = ANY (v_lojas));
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_tarefa(text, integer, integer[], integer, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_tarefa(text, integer, integer[], integer, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_tarefa(p_tarefaid integer, p_ativa boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_lojas integer[];
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = v_conta AND tarefaid = p_tarefaid) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT coalesce(array_agg(lojaid), ARRAY[]::integer[]) INTO v_lojas
    FROM public.tarefaslojas WHERE contaid = v_conta AND tarefaid = p_tarefaid AND ativo;
  IF (cardinality(v_lojas) = 0 AND NOT public.pode('tarefas.catalogo'))
     OR EXISTS (SELECT 1 FROM unnest(v_lojas) l WHERE NOT public.pode('tarefas.catalogo', l)) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer nesta tarefa: ela vale em loja fora das suas.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tarefas SET ativa = p_ativa WHERE contaid = v_conta AND tarefaid = p_tarefaid;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_tarefa(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_tarefa(integer, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Encerrar atribuições (a tela gravava direto, com o dia do APARELHO; agora
--    é o dia da conta, pelo servidor)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.encerrar_atribuicoes(p_ids integer[])
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
  -- Todas as atribuições pedidas, na loja em que ele pode: ou todas, ou nenhuma.
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
              WHERE ta.contaid = v_conta AND ta.atribuicaoid = ANY (coalesce(p_ids, ARRAY[]::integer[]))
                AND NOT public.pode('tarefas.encerrar_atribuicao', ta.lojaid)) THEN
    RAISE EXCEPTION 'Seu cargo não permite encerrar atribuições nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tarefasatribuidas SET datafimvigencia = public.hoje_da_conta(v_conta)
   WHERE contaid = v_conta AND atribuicaoid = ANY (coalesce(p_ids, ARRAY[]::integer[]));
END;
$$;
REVOKE ALL ON FUNCTION public.encerrar_atribuicoes(integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.encerrar_atribuicoes(integer[]) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.tarefas, public.tarefaslojas, public.tarefasatribuidas FROM authenticated;

-- ---------------------------------------------------------------------------
-- 3. Atribuir e mudar a hora, partindo da versão VIVA no banco
-- ---------------------------------------------------------------------------
-- atribuir_tarefa: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.atribuir_tarefa(p_tarefaid integer, p_lojaid integer, p_funcionarios integer[], p_tipofrequencia text, p_valorfrequencia integer DEFAULT NULL::integer, p_dataagendamento timestamp with time zone DEFAULT NULL::timestamp with time zone, p_horariodisparo time without time zone DEFAULT NULL::time without time zone, p_disponivelapartir time without time zone DEFAULT NULL::time without time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_gente   integer[] := coalesce(p_funcionarios, ARRAY[]::integer[]);
  v_quantos integer;
  v_id      integer;
  v_fid     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT count(DISTINCT x) INTO v_quantos FROM unnest(v_gente) x WHERE x IS NOT NULL;

  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE tarefaid = p_tarefaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Tarefas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('tarefas.atribuir', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite atribuir tarefas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_quantos = 0 AND p_horariodisparo IS NULL THEN
    RAISE EXCEPTION 'Escolha quem faz a tarefa, ou a hora em que a missão vai para o grupo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Todo mundo escolhido precisa estar ativo e ligado a esta loja.
  IF v_quantos > 0 AND EXISTS (
       SELECT 1 FROM unnest(v_gente) g
        WHERE g IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.funcionarios f
                            JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid
                                                            AND fl.contaid = v_conta AND fl.ativo
                           WHERE f.funcionarioid = g AND f.contaid = v_conta AND f.ativo
                             AND fl.lojaid = p_lojaid)) THEN
    RAISE EXCEPTION 'Escolha só pessoas ativas desta loja.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        valorfrequencia, dataagendamento, horariodisparo, compartilhada,
                                        disponivelapartir)
  VALUES (v_conta, p_tarefaid,
          CASE WHEN v_quantos = 1 THEN (SELECT x FROM unnest(v_gente) x WHERE x IS NOT NULL LIMIT 1) END,
          p_lojaid, p_tipofrequencia, p_valorfrequencia, p_dataagendamento,
          CASE WHEN v_quantos = 0 THEN p_horariodisparo END,
          v_quantos > 1,
          p_disponivelapartir)
  RETURNING atribuicaoid INTO v_id;

  IF v_quantos > 1 THEN
    FOREACH v_fid IN ARRAY v_gente LOOP
      IF v_fid IS NOT NULL THEN
        INSERT INTO public.tarefascandidatos (contaid, atribuicaoid, funcionarioid)
        VALUES (v_conta, v_id, v_fid) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN v_id;
END;
$function$;

-- alterar_hora_da_atribuicao: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.alterar_hora_da_atribuicao(p_atribuicaoid integer, p_hora time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Tarefas).
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas
              WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta
                AND NOT public.pode('tarefas.atribuir', lojaid)) THEN
    RAISE EXCEPTION 'Seu cargo não permite mudar a hora nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.tarefasatribuidas
     SET disponivelapartir = p_hora
   WHERE atribuicaoid = p_atribuicaoid
     AND contaid = v_conta
     AND datafimvigencia IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada ou já encerrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929255000_solicitacoes_permissoes.sql
-- ------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------
-- 20260929256000_justificativas_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 7: Justificativas (29/09/2026).
--
-- A justificativa é de uma tarefa atribuída numa LOJA: registrar confere
-- "justificativas.registrar" na loja da atribuição; decidir (aceitar ou
-- recusar) confere "justificativas.decidir". Registrar já aceitando exige as
-- duas. Ninguém registra nem decide a PRÓPRIA justificativa (decisão mais
-- restritiva, anotada para o Wisley). Para o master nada muda.

-- registrar_justificativa: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.registrar_justificativa(p_atribuicaoid integer, p_dia date, p_motivo text, p_aceitar boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_aceitar IS NULL THEN
    RAISE EXCEPTION 'Escolha se já aceita ou se fica para decidir.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_atr FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND funcionarioid IS NOT NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa atribuída não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Justificativas).
  IF NOT public.bot_contexto_confiavel() THEN
    IF NOT public.pode('justificativas.registrar', v_atr.lojaid)
       OR (p_aceitar AND NOT public.pode('justificativas.decidir', v_atr.lojaid)) THEN
      RAISE EXCEPTION 'Seu cargo não permite registrar (ou já aceitar) justificativas nesta loja.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, v_atr.funcionarioid) THEN
      RAISE EXCEPTION 'Ninguém justifica a própria tarefa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.justificaveis(v_atr.funcionarioid, p_dia)) x
                  WHERE (x->>'atribuicaoid')::integer = p_atribuicaoid) THEN
    RAISE EXCEPTION 'Nesse dia a tarefa não caía para a pessoa, ou já foi entregue ou justificada, ou era folga.'
      USING ERRCODE = 'check_violation';
  END IF;

  BEGIN
    INSERT INTO public.justificativas (contaid, lojaid, atribuicaoid, funcionarioid, dia, motivo, status,
                                       origem, registradopor, decididopor, decididoem)
    VALUES (v_conta, v_atr.lojaid, p_atribuicaoid, v_atr.funcionarioid, p_dia, btrim(p_motivo),
            CASE WHEN p_aceitar THEN 'Aceita' ELSE 'Pendente' END,
            public.origem_da_acao('bot'), auth.uid(),
            CASE WHEN p_aceitar THEN auth.uid() END,
            CASE WHEN p_aceitar THEN now() END)
    RETURNING justificativaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Esta tarefa já tem justificativa neste dia.' USING ERRCODE = 'unique_violation';
  END;

  IF p_aceitar THEN
    PERFORM public.avaliar_conquistas(v_conta, v_atr.funcionarioid);
  END IF;
  RETURN v_id;
END;
$function$;

-- decidir_justificativa: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.decidir_justificativa(p_justificativaid integer, p_aceitar boolean, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_j     public.justificativas%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_j FROM public.justificativas
   WHERE justificativaid = p_justificativaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Justificativa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Justificativas).
  IF NOT public.bot_contexto_confiavel() THEN
    IF NOT public.pode('justificativas.decidir', v_j.lojaid) THEN
      RAISE EXCEPTION 'Seu cargo não permite decidir justificativas nesta loja.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, v_j.funcionarioid) THEN
      RAISE EXCEPTION 'Ninguém decide a própria justificativa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  IF v_j.status <> 'Pendente' THEN
    RAISE EXCEPTION 'Esta justificativa já foi decidida.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_aceitar IS NULL THEN
    RAISE EXCEPTION 'Escolha aceitar ou recusar.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT p_aceitar AND length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Para recusar, informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.justificativas
     SET status = CASE WHEN p_aceitar THEN 'Aceita' ELSE 'Recusada' END,
         decididopor = auth.uid(), decididoem = now(),
         motivorecusa = CASE WHEN p_aceitar THEN NULL ELSE btrim(p_motivo) END
   WHERE justificativaid = p_justificativaid;

  IF p_aceitar THEN
    PERFORM public.avaliar_conquistas(v_conta, v_j.funcionarioid);
  END IF;
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929257000_agenda_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 8: Agenda (29/09/2026).
--
-- Toda mudança num agendamento confere a permissão NA LOJA dele:
--   criar, editar, remarcar, trocar responsável, reabrir, cancelar, anexos e
--   recriar a tarefa ...................................... agenda.editar
--   marcar realizado ...................................... agenda.realizado
--   pagamento (R$), inclusive criar já com valor ou pago .. agenda.pagamento
-- agendamento_para_mudar (o ponto único que carrega o agendamento) passa a
-- reconhecer o gerente; o pode() fica escrito em CADA função, logo depois,
-- para a trava estrutural (seção 91) enxergar.
-- Tipos de evento: lista da conta, sem loja = só o master (régua do alcance);
-- a gravação direta na tabela fecha e vira função.
-- Anexos: registrar e remover conferem "agenda.editar"; o ENVIO do arquivo ao
-- Storage continua só do master (a trava das policies só aceita a conta do
-- master como âncora; abrir isso é decisão do Wisley, anotada no MAPA).
-- Para o master nada muda. Nenhum dado é alterado.
-- ---------------------------------------------------------------------------
-- 1. O ponto único reconhece o gerente
-- ---------------------------------------------------------------------------
-- agendamento_para_mudar: parte da versão viva; muda só a conta.
CREATE OR REPLACE FUNCTION public.agendamento_para_mudar(p_agendamentoid integer)
 RETURNS agendamentos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  a public.agendamentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO a FROM public.agendamentos WHERE agendamentoid = p_agendamentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN a;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Cada função que muda um agendamento confere o seu código na loja dele
-- ---------------------------------------------------------------------------
-- editar_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.editar_agendamento(p_agendamentoid integer, p_tipoeventoid integer, p_nomecliente text, p_cpf text, p_telefone text, p_observacoes text, p_aceitawhatsapp boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  a public.agendamentos%ROWTYPE;
  v_tipo text;
  v_cpf text := public.so_digitos(p_cpf);
  v_tel text := public.so_digitos(p_telefone);
  t record;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para editar agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT nome INTO v_tipo FROM public.tiposevento WHERE tipoeventoid = p_tipoeventoid AND contaid = a.contaid;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'Escolha o tipo de evento.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_nomecliente, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o nome do cliente.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_cpf IS NOT NULL AND length(v_cpf) <> 11 THEN
    RAISE EXCEPTION 'O CPF precisa ter 11 números.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_tel IS NOT NULL AND length(v_tel) NOT BETWEEN 10 AND 13 THEN
    RAISE EXCEPTION 'Telefone inválido: use DDD e número.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.agendamentos
     SET tipoeventoid = p_tipoeventoid, tipoevento = v_tipo, nomecliente = btrim(p_nomecliente),
         cpfcliente = v_cpf, telefonecliente = v_tel,
         observacoes = nullif(btrim(coalesce(p_observacoes, '')), ''), aceitawhatsapp = coalesce(p_aceitawhatsapp, false)
   WHERE agendamentoid = a.agendamentoid;

  IF v_tipo IS DISTINCT FROM a.tipoevento THEN
    PERFORM set_config('gamegb.agenda', 'sim', true);
    FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
              WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
      UPDATE public.tarefasatribuidas SET descricaooverride = public.texto_da_tarefa_agenda(a.dataevento, v_tipo)
       WHERE atribuicaoid = t.atribuicaoid;
    END LOOP;
    PERFORM set_config('gamegb.agenda', '', true);
  END IF;

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'editado',
    CASE WHEN v_tipo IS DISTINCT FROM a.tipoevento THEN a.tipoevento END,
    CASE WHEN v_tipo IS DISTINCT FROM a.tipoevento THEN v_tipo END, 'dados do agendamento alterados');
END;
$function$;

-- remarcar_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.remarcar_agendamento(p_agendamentoid integer, p_novadata timestamp with time zone, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE; t record;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para remarcar agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_novadata IS NULL OR public.dia_em_sao_paulo(p_novadata) < public.dia_em_sao_paulo(now()) THEN
    RAISE EXCEPTION 'A nova data não pode estar no passado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_novadata = a.dataevento THEN
    RETURN;
  END IF;

  UPDATE public.agendamentos SET dataevento = p_novadata WHERE agendamentoid = a.agendamentoid;

  -- A tarefa vai junto, se ainda nao foi entregue.
  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas
         SET dataagendamento = p_novadata,
             descricaooverride = public.texto_da_tarefa_agenda(p_novadata, a.tipoevento)
       WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);
  -- Sem tarefa (criado sem ela, ou ela sumiu): recria, se der (29/09/2026).
  PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'remarcado',
    to_char(a.dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    to_char(p_novadata AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), p_motivo);
END;
$function$;

-- trocar_responsavel_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.trocar_responsavel_agendamento(p_agendamentoid integer, p_funcionarioid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE; t record; v_antes text; v_depois text;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para trocar o responsável de agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_funcionarioid = a.funcionarioid THEN
    -- Mesma pessoa: nada muda, mas a tarefa que faltar é recriada.
    PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);
    RETURN;
  END IF;
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, p_funcionarioid) THEN
    RAISE EXCEPTION 'O responsável precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT nomecompleto INTO v_antes FROM public.funcionarios WHERE funcionarioid = a.funcionarioid;
  SELECT nomecompleto INTO v_depois FROM public.funcionarios WHERE funcionarioid = p_funcionarioid;

  UPDATE public.agendamentos SET funcionarioid = p_funcionarioid WHERE agendamentoid = a.agendamentoid;

  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas SET funcionarioid = p_funcionarioid WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);
  -- Sem tarefa (criado sem ela, ou ela sumiu): recria, já com o novo
  -- responsável (29/09/2026).
  PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'responsavel', v_antes, v_depois, NULL);
END;
$function$;

-- reabrir_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.reabrir_agendamento(p_agendamentoid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento <> 'Realizado' THEN
    RAISE EXCEPTION 'Só agendamento realizado pode voltar para confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.agendamentos SET statusagendamento = 'Confirmado', realizadoem = NULL, realizadopor = NULL
   WHERE agendamentoid = a.agendamentoid;
  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'reaberto', 'Realizado', 'Confirmado', p_motivo);
END;
$function$;

-- cancelar_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.cancelar_agendamento(p_agendamentoid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE; t record;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para cancelar agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Para cancelar, informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.agendamentos
     SET statusagendamento = 'Cancelado', canceladoem = now(), canceladopor = auth.uid(), motivocancelamento = btrim(p_motivo)
   WHERE agendamentoid = a.agendamentoid;

  -- A tarefa e encerrada (se ainda nao foi entregue).
  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas SET datafimvigencia = public.dia_em_sao_paulo(now())
       WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'cancelado', 'Confirmado', 'Cancelado', p_motivo);
END;
$function$;

-- registrar_anexo_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.registrar_anexo_agendamento(p_agendamentoid integer, p_caminho text, p_nomearquivo text, p_tipo text, p_tamanho integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE; v_id integer;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento = 'Cancelado' THEN
    RAISE EXCEPTION 'Agendamento cancelado não muda mais.' USING ERRCODE = 'check_violation';
  END IF;
  IF split_part(p_caminho, '/', 1) <> a.contaid::text OR split_part(p_caminho, '/', 2) <> a.lojaid::text
     OR split_part(p_caminho, '/', 3) <> a.agendamentoid::text OR split_part(p_caminho, '/', 4) = '' THEN
    RAISE EXCEPTION 'Arquivo fora da pasta do agendamento.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'agendamentos' AND name = p_caminho) THEN
    RAISE EXCEPTION 'Arquivo não encontrado. Envie de novo.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.agendamentosanexos (contaid, lojaid, agendamentoid, caminho, nomearquivo, tipoarquivo, tamanho, enviadopor)
  VALUES (a.contaid, a.lojaid, a.agendamentoid, p_caminho, left(btrim(p_nomearquivo), 200), p_tipo, p_tamanho, auth.uid())
  RETURNING anexoid INTO v_id;
  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'anexo', NULL, left(btrim(p_nomearquivo), 200), NULL);
  RETURN v_id;
END;
$function$;

-- recriar_tarefa_do_agendamento: parte da versão viva no banco; confere agenda.editar na loja.
CREATE OR REPLACE FUNCTION public.recriar_tarefa_do_agendamento(p_agendamentoid integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, a.funcionarioid) THEN
    RAISE EXCEPTION 'O responsável deste agendamento não trabalha mais na loja: troque o responsável (a tarefa é recriada junto).'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = a.contaid AND sistema = 'modelo_agendamento' AND ativa) THEN
    RAISE EXCEPTION 'A tarefa "Atender agendamento" está desativada ou foi apagada: reative-a no Catálogo de tarefas.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN public.garantir_tarefa_do_agendamento(a.agendamentoid);
END;
$function$;

-- marcar_agendamento_realizado: parte da versão viva no banco; confere agenda.realizado na loja.
CREATE OR REPLACE FUNCTION public.marcar_agendamento_realizado(p_agendamentoid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.realizado', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só agendamento confirmado pode ser marcado como realizado.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.agendamentos SET statusagendamento = 'Realizado', realizadoem = now(), realizadopor = auth.uid()
   WHERE agendamentoid = a.agendamentoid;
  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'realizado', 'Confirmado', 'Realizado', NULL);
END;
$function$;

-- alterar_pagamento_agendamento: parte da versão viva no banco; confere agenda.pagamento na loja.
CREATE OR REPLACE FUNCTION public.alterar_pagamento_agendamento(p_agendamentoid integer, p_status text, p_valor numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a public.agendamentos%ROWTYPE;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.pagamento', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF a.statusagendamento = 'Cancelado' THEN
    RAISE EXCEPTION 'Agendamento cancelado não muda mais.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_status NOT IN ('Pendente', 'Sinal pago', 'Pago') THEN
    RAISE EXCEPTION 'Situação de pagamento inválida.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_status = a.statuspagamento AND p_valor IS NOT DISTINCT FROM a.valor THEN
    RETURN;
  END IF;
  UPDATE public.agendamentos SET statuspagamento = p_status, valor = p_valor WHERE agendamentoid = a.agendamentoid;
  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'pagamento',
    a.statuspagamento || coalesce(' (' || public.reais(a.valor) || ')', ''),
    p_status || coalesce(' (' || public.reais(p_valor) || ')', ''), NULL);
END;
$function$;

-- remover_anexo_agendamento: parte da versão viva; confere agenda.editar na loja do anexo.
CREATE OR REPLACE FUNCTION public.remover_anexo_agendamento(p_anexoid integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); x public.agendamentosanexos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO x FROM public.agendamentosanexos WHERE anexoid = p_anexoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND OR x.removidoem IS NOT NULL THEN
    RAISE EXCEPTION 'Anexo não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('agenda.editar', x.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.agendamentosanexos SET removidoem = now(), removidopor = auth.uid() WHERE anexoid = p_anexoid;
  PERFORM public.registra_agenda(x.contaid, x.lojaid, x.agendamentoid, 'anexo_removido', x.nomearquivo, NULL, NULL);
  RETURN x.caminho;
END;
$function$;

-- criar_agendamento: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.criar_agendamento(p_lojaid integer, p_tipoeventoid integer, p_dataevento timestamp with time zone, p_nomecliente text, p_cpf text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_observacoes text DEFAULT NULL::text, p_valor numeric DEFAULT NULL::numeric, p_pagamento text DEFAULT 'Pendente'::text, p_responsavelid integer DEFAULT NULL::integer, p_aceitawhatsapp boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_loja   public.lojas%ROWTYPE;
  v_tipo   text;
  v_resp   integer;
  v_cpf    text := public.so_digitos(p_cpf);
  v_tel    text := public.so_digitos(p_telefone);
  v_modelo integer;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_loja FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Agenda). Criar
  -- já com valor ou com pagamento feito é mexer no pagamento (R$).
  IF NOT public.bot_contexto_confiavel() THEN
    IF NOT public.pode('agenda.editar', p_lojaid)
       OR ((p_valor IS NOT NULL OR coalesce(p_pagamento, 'Pendente') <> 'Pendente')
           AND NOT public.pode('agenda.pagamento', p_lojaid)) THEN
      RAISE EXCEPTION 'Seu cargo não permite isso na agenda desta loja.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  SELECT nome INTO v_tipo FROM public.tiposevento WHERE tipoeventoid = p_tipoeventoid AND contaid = v_conta AND ativo;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'Escolha o tipo de evento.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_nomecliente, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o nome do cliente.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dataevento IS NULL OR public.dia_em_sao_paulo(p_dataevento) < public.dia_em_sao_paulo(now()) THEN
    RAISE EXCEPTION 'A data do evento não pode estar no passado.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_cpf IS NOT NULL AND length(v_cpf) <> 11 THEN
    RAISE EXCEPTION 'O CPF precisa ter 11 números.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_tel IS NOT NULL AND length(v_tel) NOT BETWEEN 10 AND 13 THEN
    RAISE EXCEPTION 'Telefone inválido: use DDD e número.' USING ERRCODE = 'check_violation';
  END IF;
  v_resp := coalesce(p_responsavelid, v_loja.responsavelagendamentosid);
  IF v_resp IS NULL THEN
    RAISE EXCEPTION 'Escolha o responsável (a loja não tem responsável pelos agendamentos definido).' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.responsavel_valido(v_conta, p_lojaid, v_resp) THEN
    RAISE EXCEPTION 'O responsável precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.agendamentos (contaid, lojaid, nomecliente, cpfcliente, telefonecliente, tipoevento, tipoeventoid,
                                   dataevento, statuspagamento, valor, funcionarioid, observacoes, aceitawhatsapp, registradopor)
  VALUES (v_conta, p_lojaid, btrim(p_nomecliente), v_cpf, v_tel, v_tipo, p_tipoeventoid, p_dataevento,
          coalesce(p_pagamento, 'Pendente'), p_valor, v_resp, nullif(btrim(coalesce(p_observacoes, '')), ''),
          coalesce(p_aceitawhatsapp, false), auth.uid())
  RETURNING agendamentoid INTO v_id;

  -- A tarefa "Atender agendamento" para o responsavel, no dia do evento.
  -- Achada pelo CODIGO interno (nunca pelo nome: renomear nao quebra nada).
  -- Desativada ou apagada: o agendamento nasce sem ela, e isso NAO fica em
  -- silencio (28/09/2026) — vira aviso no Inicio e na Saude.
  SELECT tarefaid INTO v_modelo FROM public.tarefas
   WHERE contaid = v_conta AND sistema = 'modelo_agendamento' AND ativa;
  IF v_modelo IS NULL THEN
    INSERT INTO public.avisossistema (contaid, tipo, texto)
    VALUES (v_conta, 'rotina_sem_tarefa', left(
      'Agenda: o agendamento de ' || btrim(p_nomecliente) || ' (' ||
      to_char(p_dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') ||
      ') foi criado SEM a tarefa de atender, porque a tarefa "Atender agendamento" está desativada ou foi apagada. Reative-a no Catálogo de tarefas.', 300));
  ELSE
    PERFORM set_config('gamegb.agenda', 'sim', true);
    INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataagendamento,
                                          descricaooverride, agendamentoid)
    VALUES (v_conta, v_modelo, v_resp, p_lojaid, 'Unica', p_dataevento,
            public.texto_da_tarefa_agenda(p_dataevento, v_tipo), v_id);
    PERFORM set_config('gamegb.agenda', '', true);
  END IF;

  PERFORM public.registra_agenda(v_conta, p_lojaid, v_id, 'criado', NULL,
                                 to_char(p_dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ' — ' || v_tipo, NULL);
  RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Tipos de evento: só o master, por função
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_tipo_evento(p_nome text, p_tipoeventoid integer DEFAULT NULL)
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
    RAISE EXCEPTION 'Só o dono da conta mexe nos tipos de evento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome ao tipo.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_tipoeventoid IS NULL THEN
    INSERT INTO public.tiposevento (contaid, nome) VALUES (v_conta, btrim(p_nome)) RETURNING tipoeventoid INTO v_id;
  ELSE
    UPDATE public.tiposevento SET nome = btrim(p_nome)
     WHERE contaid = v_conta AND tipoeventoid = p_tipoeventoid RETURNING tipoeventoid INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Tipo de evento não encontrado.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_tipo_evento(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_tipo_evento(text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_tipo_evento(p_tipoeventoid integer, p_ativo boolean)
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
    RAISE EXCEPTION 'Só o dono da conta mexe nos tipos de evento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tiposevento SET ativo = coalesce(p_ativo, true) WHERE contaid = v_conta AND tipoeventoid = p_tipoeventoid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tipo de evento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_tipo_evento(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_tipo_evento(integer, boolean) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.tiposevento FROM authenticated;

-- ------------------------------------------------------------------------
-- 20260929258000_comunicados_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 9: Comunicados (29/09/2026).
--
-- Publicar, editar, arquivar, incluir destinatários: "comunicados.publicar"
-- dentro do ALCANCE (régua do MAPA): "conta inteira" só o master; "lojas",
-- todas as escolhidas dentro das lojas dele; "pessoas", todas as lojas de cada
-- pessoa dentro das dele. Registrar ciência em nome da pessoa: a mesma
-- permissão, na pessoa, e nunca a própria (a ciência paga pontos).
-- Desfazer ciência continua só do master: agora reconhece o gerente e o barra
-- pelo sou_master (é o que o teste volta a provar).
-- Para o master nada muda. Nenhum dado é alterado.
-- publicar_comunicado: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.publicar_comunicado(p_titulo text, p_conteudo text, p_pontos integer, p_alvo text, p_lojas integer[] DEFAULT NULL::integer[], p_funcionarios integer[] DEFAULT NULL::integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_id    integer;
  v_pontos integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_titulo, ''))) = 0 OR length(btrim(coalesce(p_conteudo, ''))) = 0 THEN
    RAISE EXCEPTION 'Preencha o título e o texto.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo NOT IN ('conta', 'lojas', 'funcionarios') THEN
    RAISE EXCEPTION 'Escolha para quem é o comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  -- Pontos: os do comunicado, ou o padrao da tarefa "Leitura de comunicado"
  -- (achada pelo CODIGO guardado em configuracoes, nunca pelo nome). Com a
  -- tarefa desativada ou apagada, o padrao e 0 e isso vira aviso (28/09/2026).
  v_pontos := p_pontos;
  IF v_pontos IS NULL THEN
    SELECT t.pontos INTO v_pontos FROM public.configuracoes c
      JOIN public.tarefas t ON t.tarefaid = nullif(c.valor, '')::integer AND t.contaid = c.contaid
     WHERE c.contaid = v_conta AND c.chave = 'TAREFA_ID_LEITURA' AND t.ativa;
    IF NOT FOUND THEN
      v_pontos := 0;
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      VALUES (v_conta, 'rotina_sem_tarefa', left(
        'Comunicados: "' || btrim(coalesce(p_titulo, '')) || '" foi publicado com 0 ponto por ciência, porque a tarefa "Leitura de comunicado" (que dá o padrão) está desativada ou foi apagada.', 300));
    END IF;
  END IF;
  IF v_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  -- Teto da conta (29/09/2026): a ciência paga sem ninguém aprovar.
  IF v_pontos > public.teto_pontos_ciencia(v_conta) THEN
    RAISE EXCEPTION '% pontos por ciência passa do máximo permitido nesta conta (% pontos). %',
      v_pontos, public.teto_pontos_ciencia(v_conta),
      CASE WHEN p_pontos IS NULL THEN 'O padrão vem da tarefa "Leitura de comunicado": ajuste os pontos dela, ou escreva os pontos no comunicado.'
           ELSE 'Diminua os pontos, ou mude o máximo em Configurações.' END
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'lojas' AND (coalesce(array_length(p_lojas, 1), 0) = 0
       OR EXISTS (SELECT 1 FROM unnest(p_lojas) x(l)
                   WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = x.l AND contaid = v_conta AND ativa))) THEN
    RAISE EXCEPTION 'Escolha lojas ativas da sua conta.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'funcionarios' AND coalesce(array_length(p_funcionarios, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Escolha pelo menos uma pessoa.' USING ERRCODE = 'check_violation';
  END IF;
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados).
  IF NOT public.bot_contexto_confiavel() AND (
       (p_alvo = 'conta' AND NOT public.pode('comunicados.publicar', NULL))
    OR (p_alvo = 'lojas' AND EXISTS (SELECT 1 FROM unnest(p_lojas) x(l) WHERE NOT public.pode('comunicados.publicar', x.l)))
    OR (p_alvo = 'funcionarios' AND EXISTS (SELECT 1 FROM unnest(p_funcionarios) x(f)
                                             WHERE NOT public.pode_na_pessoa('comunicados.publicar', v_conta, x.f)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite publicar para esse alcance (a conta inteira é só do dono; lojas e pessoas, só as suas).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO public.documentos (contaid, titulo, conteudo, pontosporciencia, alvo, criadopor)
  VALUES (v_conta, btrim(p_titulo), btrim(p_conteudo), v_pontos, p_alvo, auth.uid())
  RETURNING documentoid INTO v_id;

  IF p_alvo = 'lojas' THEN
    INSERT INTO public.documentoslojas (contaid, documentoid, lojaid)
    SELECT DISTINCT v_conta, v_id, x FROM unnest(p_lojas) x;
  END IF;

  -- Destinatarios fixados agora (so ativos).
  IF p_alvo = 'funcionarios' THEN
    PERFORM public.incluir_destinatarios(v_id, p_funcionarios);
  ELSE
    INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
    SELECT v_conta, v_id, fid, now() FROM public.alcance_do_comunicado(v_id) fid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas WHERE documentoid = v_id) THEN
    RAISE EXCEPTION 'Nenhum funcionário ativo recebe este comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END;
$function$;

-- editar_comunicado: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.editar_comunicado(p_documentoid integer, p_titulo text, p_conteudo text, p_pontos integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados):
  -- "conta inteira" é só do master; "lojas", todas dentro das dele; "pessoas",
  -- todas as lojas de cada destinatário dentro das dele.
  IF NOT public.bot_contexto_confiavel() AND NOT (
       public.pode('comunicados.publicar', NULL)
    OR (d.alvo = 'lojas' AND NOT EXISTS (
          SELECT 1 FROM public.documentoslojas dl
           WHERE dl.documentoid = d.documentoid AND NOT public.pode('comunicados.publicar', dl.lojaid)))
    OR (d.alvo = 'funcionarios' AND NOT EXISTS (
          SELECT 1 FROM public.documentosassinaturas a
           WHERE a.documentoid = d.documentoid
             AND NOT public.pode_na_pessoa('comunicados.publicar', v_conta, a.funcionarioid)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer neste comunicado (ele alcança lojas ou pessoas fora das suas).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não muda.' USING ERRCODE = 'check_violation';
  END IF;
  IF d.primeiracienciaem IS NOT NULL THEN
    RAISE EXCEPTION 'Este comunicado já tem ciência: o texto e os pontos não mudam. Crie um novo.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF length(btrim(coalesce(p_titulo, ''))) = 0 OR length(btrim(coalesce(p_conteudo, ''))) = 0 THEN
    RAISE EXCEPTION 'Preencha o título e o texto.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_pontos IS NULL OR p_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  -- Teto da conta (29/09/2026). Só vale para o que se grava agora.
  IF p_pontos > public.teto_pontos_ciencia(v_conta) THEN
    RAISE EXCEPTION '% pontos por ciência passa do máximo permitido nesta conta (% pontos). Diminua os pontos, ou mude o máximo em Configurações.',
      p_pontos, public.teto_pontos_ciencia(v_conta) USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.documentos SET titulo = btrim(p_titulo), conteudo = btrim(p_conteudo), pontosporciencia = p_pontos
   WHERE documentoid = p_documentoid;
END;
$function$;

-- incluir_destinatarios: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.incluir_destinatarios(p_documentoid integer, p_funcionarios integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  d public.documentos%ROWTYPE;
  v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados):
  -- "conta inteira" é só do master; "lojas", todas dentro das dele; "pessoas",
  -- todas as lojas de cada destinatário dentro das dele.
  IF NOT public.bot_contexto_confiavel() AND NOT (
       public.pode('comunicados.publicar', NULL)
    OR (d.alvo = 'lojas' AND NOT EXISTS (
          SELECT 1 FROM public.documentoslojas dl
           WHERE dl.documentoid = d.documentoid AND NOT public.pode('comunicados.publicar', dl.lojaid)))
    OR (d.alvo = 'funcionarios' AND NOT EXISTS (
          SELECT 1 FROM public.documentosassinaturas a
           WHERE a.documentoid = d.documentoid
             AND NOT public.pode_na_pessoa('comunicados.publicar', v_conta, a.funcionarioid)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer neste comunicado (ele alcança lojas ou pessoas fora das suas).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.bot_contexto_confiavel()
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f)
                  WHERE NOT public.pode_na_pessoa('comunicados.publicar', v_conta, x.f)) THEN
    RAISE EXCEPTION 'Seu cargo não permite incluir pessoas de fora das suas lojas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não aceita novos destinatários.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(fid)
              WHERE NOT EXISTS (SELECT 1 FROM public.funcionarios f
                                 WHERE f.funcionarioid = x.fid AND f.contaid = v_conta AND f.ativo)) THEN
    RAISE EXCEPTION 'Só funcionários ativos da sua conta podem receber o comunicado.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
  SELECT v_conta, p_documentoid, x.fid, now()
    FROM (SELECT DISTINCT unnest(coalesce(p_funcionarios, '{}'::integer[])) AS fid) x
  ON CONFLICT (documentoid, funcionarioid) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- arquivar_comunicado: parte da versão viva; agora carrega o comunicado antes,
-- para conferir o alcance (mesmo erro de antes quando não acha).
CREATE OR REPLACE FUNCTION public.arquivar_comunicado(p_documentoid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentos
   WHERE documentoid = p_documentoid AND contaid = v_conta AND status = 'Publicado' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado ou já arquivado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados):
  -- "conta inteira" é só do master; "lojas", todas dentro das dele; "pessoas",
  -- todas as lojas de cada destinatário dentro das dele.
  IF NOT public.bot_contexto_confiavel() AND NOT (
       public.pode('comunicados.publicar', NULL)
    OR (d.alvo = 'lojas' AND NOT EXISTS (
          SELECT 1 FROM public.documentoslojas dl
           WHERE dl.documentoid = d.documentoid AND NOT public.pode('comunicados.publicar', dl.lojaid)))
    OR (d.alvo = 'funcionarios' AND NOT EXISTS (
          SELECT 1 FROM public.documentosassinaturas a
           WHERE a.documentoid = d.documentoid
             AND NOT public.pode_na_pessoa('comunicados.publicar', v_conta, a.funcionarioid)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer neste comunicado (ele alcança lojas ou pessoas fora das suas).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.documentos SET status = 'Arquivado', arquivadoem = now(), arquivadopor = auth.uid()
   WHERE documentoid = p_documentoid;
END;
$function$;

-- registrar_ciencia: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.registrar_ciencia(p_assinaturaid integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  s public.documentosassinaturas%ROWTYPE;
  d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO s FROM public.documentosassinaturas WHERE assinaturaid = p_assinaturaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Destinatário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão na pessoa, no banco (usuários gerenciais, parte 2 — Comunicados).
  -- A ciência paga pontos: ninguém registra a própria por aqui.
  IF NOT public.bot_contexto_confiavel() THEN
    IF NOT public.pode_na_pessoa('comunicados.publicar', v_conta, s.funcionarioid) THEN
      RAISE EXCEPTION 'Seu cargo não permite registrar ciência por esta pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, s.funcionarioid) THEN
      RAISE EXCEPTION 'Ninguém registra a própria ciência por aqui.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = s.documentoid FOR UPDATE;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não aceita ciência nova.' USING ERRCODE = 'check_violation';
  END IF;
  IF s.statusassinatura = 'Ciente' THEN
    RETURN false;   -- ja estava: nada muda, nada e pago de novo
  END IF;

  UPDATE public.documentosassinaturas
     SET statusassinatura = 'Ciente', dataciencia = now(), origem = public.origem_da_acao('funcionario'), registradopor = auth.uid(),
         pontospagos = d.pontosporciencia
   WHERE assinaturaid = p_assinaturaid;
  IF d.primeiracienciaem IS NULL THEN
    UPDATE public.documentos SET primeiracienciaem = now() WHERE documentoid = d.documentoid;
  END IF;

  IF d.pontosporciencia > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, assinaturaid, criadopor)
    VALUES (v_conta, s.funcionarioid, 'bonus', d.pontosporciencia, 'Ciência do comunicado: ' || d.titulo,
            p_assinaturaid, auth.uid());
  END IF;
  PERFORM public.avaliar_conquistas(v_conta, s.funcionarioid);
  RETURN true;
END;
$function$;

-- desfazer_ciencia: parte da versão viva; reconhece o gerente, e o sou_master o barra.
CREATE OR REPLACE FUNCTION public.desfazer_ciencia(p_assinaturaid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  s public.documentosassinaturas%ROWTYPE;
  v_titulo text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta desfaz uma ciência.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO s FROM public.documentosassinaturas WHERE assinaturaid = p_assinaturaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Destinatário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF s.statusassinatura <> 'Ciente' THEN
    RAISE EXCEPTION 'Esta ciência não está registrada.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titulo INTO v_titulo FROM public.documentos WHERE documentoid = s.documentoid;

  UPDATE public.documentosassinaturas
     SET statusassinatura = 'Pendente', dataciencia = NULL, pontospagos = 0,
         desfeitaem = now(), desfeitapor = auth.uid(), motivodesfazer = btrim(p_motivo)
   WHERE assinaturaid = p_assinaturaid;
  IF s.pontospagos > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, assinaturaid, criadopor)
    VALUES (v_conta, s.funcionarioid, 'estorno_bonus', -s.pontospagos,
            'Ciência desfeita: ' || v_titulo || ' — ' || btrim(p_motivo), p_assinaturaid, auth.uid());
  END IF;
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929259000_conquistas_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 10: Conquistas (29/09/2026).
--
-- O catálogo de conquistas é da conta inteira, sem loja: pela régua do
-- alcance, só o master mexe nele. Criar já conferia a conta; agora reconhece o
-- gerente e o barra pelo sou_master. Editar e ativar/desativar, que a tela
-- fazia direto na tabela, viram funções só do master, e a gravação direta fecha.
-- Para o master nada muda. Nenhum dado é alterado.

-- criar_conquista: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.criar_conquista(p_nome text, p_descricao text, p_icone text, p_tipo text, p_valor integer, p_dias integer, p_bonus integer, p_retroativa boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_id     integer;
  v_novas  integer := 0;
  f        record;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Catálogo da conta, sem loja: só o master (régua do alcance, parte 2).
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à conquista.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_retroativa IS NULL THEN
    RAISE EXCEPTION 'Escolha se a conquista vale para o histórico ou só a partir de hoje.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.conquistas (contaid, nome, descricao, icone, criteriotipo, criteriovalor, criteriodias,
                                 pontosbonus, contardesde)
  VALUES (v_conta, btrim(p_nome), coalesce(nullif(btrim(p_descricao), ''), btrim(p_nome)),
          nullif(btrim(coalesce(p_icone, '')), ''), p_tipo, p_valor,
          CASE WHEN p_tipo = 'tarefas_aprovadas_periodo' THEN p_dias END,
          coalesce(p_bonus, 0),
          CASE WHEN p_retroativa THEN NULL ELSE now() END)
  RETURNING conquistaid INTO v_id;

  IF p_retroativa AND public.criterio_disponivel(p_tipo) THEN
    FOR f IN SELECT funcionarioid FROM public.funcionarios WHERE contaid = v_conta ORDER BY funcionarioid LOOP
      v_novas := v_novas + public.avaliar_conquistas(v_conta, f.funcionarioid);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('conquistaid', v_id, 'concedidas', v_novas);
END;
$function$;

CREATE OR REPLACE FUNCTION public.editar_conquista(p_conquistaid integer, p_nome text, p_descricao text,
                                                   p_icone text, p_bonus integer)
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
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à conquista.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_bonus IS NULL OR p_bonus < 0 THEN
    RAISE EXCEPTION 'Bônus precisa ser 0 ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.conquistas
     SET nome = btrim(p_nome), descricao = coalesce(nullif(btrim(coalesce(p_descricao, '')), ''), btrim(p_nome)),
         icone = nullif(btrim(coalesce(p_icone, '')), ''), pontosbonus = p_bonus
   WHERE contaid = v_conta AND conquistaid = p_conquistaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conquista não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.editar_conquista(integer, text, text, text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.editar_conquista(integer, text, text, text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_conquista(p_conquistaid integer, p_ativa boolean)
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
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.conquistas SET ativa = coalesce(p_ativa, true) WHERE contaid = v_conta AND conquistaid = p_conquistaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conquista não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_conquista(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_conquista(integer, boolean) TO authenticated;

-- A gravação direta no catálogo fecha (as funções acima fazem o mesmo).
REVOKE INSERT, UPDATE, DELETE ON public.conquistas FROM authenticated;
REVOKE UPDATE (ativa, descricao, icone, nome, pontosbonus) ON public.conquistas FROM authenticated;

-- ------------------------------------------------------------------------
-- 20260929260000_onboarding_permissoes.sql
-- ------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------
-- 20260929261000_lojas_permissoes.sql
-- ------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------
-- 20260929262000_equipe_permissoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 2, fatia 13: Equipe (29/09/2026).
--
-- A gravação da Equipe (dados da pessoa e as lojas dela), que a tela fazia
-- direto nas tabelas, vira a função salvar_pessoa, com as BORDAS:
--   - criar: "equipe.criar" em TODAS as lojas escolhidas (sem loja: só master);
--   - dados da pessoa (nome, cargo, setor, telefone, folga): "equipe.editar"
--     com a pessoa INTEIRA dentro das lojas dele;
--   - lojas da pessoa: ele liga e desliga só as lojas DELE ("equipe.editar"
--     em cada loja que muda); as outras ficam como estão;
--   - CPF de quem já existe: só o master (fecha a coluna);
--   - marcar validador: só o master (mais restritivo; anotado);
--   - ninguém mexe no PRÓPRIO cadastro por aqui.
-- Liberar PIN: "equipe.liberar_pin" na pessoa (não mais só master), e nunca o
-- próprio. Ligar pessoa a jornada: "jornada.vincular" na pessoa, nunca a
-- própria. Apagar jornada: só o master, por função. Desativar e criar acesso
-- continuam no servidor, só do master.
-- Para o master nada muda. Nenhum dado é alterado.
-- liberar_pin: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.liberar_pin(p_funcionarioid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  t public.travaspin%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE contaid = v_conta AND funcionarioid = p_funcionarioid) THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão na pessoa, no banco (usuários gerenciais, parte 2 — Equipe).
  IF NOT public.pode_na_pessoa('equipe.liberar_pin', v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Seu cargo não permite liberar o PIN desta pessoa.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém libera o próprio PIN.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO t FROM public.travaspin WHERE contaid = v_conta AND funcionarioid = p_funcionarioid FOR UPDATE;
  INSERT INTO public.pinliberacoes (contaid, funcionarioid, liberadopor, estavaate, erros)
  VALUES (v_conta, p_funcionarioid, auth.uid(), t.bloqueadoate, t.erros);
  UPDATE public.travaspin SET erros = 0, nivel = 0, bloqueadoate = NULL
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid;
END;
$function$;

-- vincular_jornada: parte da versão viva no banco (exigia o master).
CREATE OR REPLACE FUNCTION public.vincular_jornada(p_funcionarios integer[], p_jornadaid integer)
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
  -- Permissão em cada pessoa, no banco (usuários gerenciais, parte 2 — Equipe):
  -- tudo ou nada; e nunca a própria.
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f)
              WHERE NOT public.pode_na_pessoa('jornada.vincular', v_conta, x.f)
                 OR public.e_o_proprio(v_conta, x.f)) THEN
    RAISE EXCEPTION 'Seu cargo não permite ligar à jornada alguma dessas pessoas (ou é você mesmo).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_jornadaid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.jornadas
                                              WHERE contaid = v_conta AND jornadaid = p_jornadaid AND ativa) THEN
    RAISE EXCEPTION 'Jornada não encontrada ou inativa.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.funcionarios SET jornadaid = p_jornadaid
   WHERE contaid = v_conta AND funcionarioid = ANY (p_funcionarios) AND ativo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------------
-- salvar_pessoa: o que a tela da Equipe gravava direto
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_pessoa(p_funcionarioid integer, p_nomecompleto text, p_cpf text,
                                                p_cargo text, p_setor text, p_telefone text, p_diadefolga integer,
                                                p_lojas integer[], p_validador integer[] DEFAULT '{}')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_lojas  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_lojas, '{}'::integer[])) x ORDER BY 1);
  v_valid  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_validador, '{}'::integer[])) x
                               WHERE x = ANY (coalesce(p_lojas, '{}'::integer[])) ORDER BY 1);
  f        public.funcionarios%ROWTYPE;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_lojas) x(l)
              WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = x.l AND contaid = v_conta)) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF p_funcionarioid IS NULL THEN
    -- Criar: em todas as lojas escolhidas; sem loja, só o master.
    IF (cardinality(v_lojas) = 0 AND NOT public.pode('equipe.criar', NULL))
       OR EXISTS (SELECT 1 FROM unnest(v_lojas) x(l) WHERE NOT public.pode('equipe.criar', x.l)) THEN
      RAISE EXCEPTION 'Seu cargo não permite cadastrar pessoa nessas lojas.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF cardinality(v_valid) > 0 AND NOT public.sou_master() THEN
      RAISE EXCEPTION 'Só o dono da conta marca quem valida.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    INSERT INTO public.funcionarios (contaid, nomecompleto, cpf, cargo, setor, telefonewhatsapp, diadefolga)
    VALUES (v_conta, p_nomecompleto, p_cpf, p_cargo, p_setor, p_telefone, p_diadefolga)
    RETURNING funcionarioid INTO v_id;
  ELSE
    SELECT * INTO f FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    v_id := f.funcionarioid;
    IF NOT public.sou_master() THEN
      IF public.e_o_proprio(v_conta, v_id) THEN
        RAISE EXCEPTION 'Ninguém mexe no próprio cadastro por aqui.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- Dados da pessoa: ela inteira dentro das lojas dele.
      IF (p_nomecompleto, p_cargo, p_setor, p_telefone, p_diadefolga)
           IS DISTINCT FROM (f.nomecompleto::text, f.cargo::text, f.setor::text, f.telefonewhatsapp::text, f.diadefolga)
         AND NOT public.pode_na_pessoa('equipe.editar', v_conta, v_id) THEN
        RAISE EXCEPTION 'Seu cargo não permite mudar os dados desta pessoa (ela trabalha em loja fora das suas).'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- CPF de quem já existe: só o master.
      IF public.so_digitos(p_cpf) IS DISTINCT FROM f.cpf THEN
        RAISE EXCEPTION 'Só o dono da conta muda o CPF de quem já está cadastrado.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- Lojas: só as dele mudam; quem valida, só o master.
      IF EXISTS (
           SELECT 1
             FROM (SELECT l FROM unnest(v_lojas) l
                   UNION SELECT lojaid FROM public.funcionarioslojas WHERE funcionarioid = v_id AND ativo) u(l)
             LEFT JOIN public.funcionarioslojas fl ON fl.funcionarioid = v_id AND fl.lojaid = u.l
            WHERE coalesce(fl.ativo, false) IS DISTINCT FROM (u.l = ANY (v_lojas))
              AND NOT public.pode('equipe.editar', u.l)) THEN
        RAISE EXCEPTION 'Seu cargo não permite tirar nem pôr esta pessoa em loja fora das suas.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      IF EXISTS (
           SELECT 1
             FROM (SELECT l FROM unnest(v_lojas) l
                   UNION SELECT lojaid FROM public.funcionarioslojas WHERE funcionarioid = v_id) u(l)
             LEFT JOIN public.funcionarioslojas fl ON fl.funcionarioid = v_id AND fl.lojaid = u.l
            WHERE coalesce(fl.validador AND fl.ativo, false) IS DISTINCT FROM (u.l = ANY (v_valid))) THEN
        RAISE EXCEPTION 'Só o dono da conta marca quem valida.' USING ERRCODE = 'insufficient_privilege';
      END IF;
    END IF;
    UPDATE public.funcionarios
       SET nomecompleto = p_nomecompleto, cpf = p_cpf, cargo = p_cargo, setor = p_setor,
           telefonewhatsapp = p_telefone, diadefolga = p_diadefolga
     WHERE funcionarioid = v_id;
  END IF;

  -- As lojas, como a tela fazia: sair de uma loja é desativar o vínculo, nunca
  -- apagar (o histórico daquela loja aponta para ele).
  INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid, ativo, validador)
  SELECT v_conta, v_id, l, true, l = ANY (v_valid) FROM unnest(v_lojas) l
  ON CONFLICT (funcionarioid, lojaid) DO UPDATE SET ativo = true, validador = EXCLUDED.validador;
  UPDATE public.funcionarioslojas SET ativo = false, validador = false
   WHERE funcionarioid = v_id AND NOT (lojaid = ANY (v_lojas)) AND (ativo OR validador);
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[], integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[], integer[]) TO authenticated;

-- Apagar jornada: só o master (a tela apagava direto na tabela).
CREATE OR REPLACE FUNCTION public.apagar_jornada(p_jornadaid integer)
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
    RAISE EXCEPTION 'Só o dono da conta apaga jornada.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.apagar_jornada(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.apagar_jornada(integer) TO authenticated;

-- A gravação direta fecha: funcionarios (e a coluna do CPF), funcionarioslojas, jornadas.
REVOKE INSERT, UPDATE, DELETE ON public.funcionarios, public.funcionarioslojas, public.jornadas FROM authenticated;
-- O direito de gravar por COLUNA também sai (ele sobrevive ao REVOKE da tabela).
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT DISTINCT table_name, column_name, privilege_type
             FROM information_schema.column_privileges
            WHERE grantee = 'authenticated' AND table_schema = 'public'
              AND table_name IN ('funcionarios', 'funcionarioslojas', 'jornadas')
              AND privilege_type IN ('INSERT', 'UPDATE') LOOP
    EXECUTE format('REVOKE %s (%I) ON public.%I FROM authenticated', c.privilege_type, c.column_name, c.table_name);
  END LOOP;
END $$;

-- ------------------------------------------------------------------------
-- 20260929263000_rh_canal_so_master.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 3, fatia 1: canal confidencial e documentos
-- pessoais continuam só do master — agora provado com um gerente de verdade
-- (29/09/2026).
--
-- As duas funções que um gerente poderia chamar (tratar relato, abrir
-- documento pessoal) passam a RECONHECER o gerente, e quem o barra é a
-- conferência "só o master" (antes o gerente nem chegava lá: a prova passava
-- pelo motivo errado). As leituras dessas tabelas já exigem "só o master" na
-- própria regra; o teste passa a conferir isso termo a termo.
-- Para o master nada muda. Nenhum dado é alterado.

-- tratar_relato: parte da versão viva; muda só a conta de quem chama.
CREATE OR REPLACE FUNCTION public.tratar_relato(p_denunciaid integer, p_status text, p_resposta text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_atual public.denunciasanonimas%ROWTYPE;
  v_resp  text := nullif(btrim(coalesce(p_resposta, '')), '');
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta acessa o canal confidencial.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_status NOT IN ('Em análise', 'Tratada') THEN
    RAISE EXCEPTION 'Situação inválida.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_atual FROM public.denunciasanonimas
   WHERE denunciaid = p_denunciaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relato não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.denunciasanonimas
     SET status       = p_status,
         resposta     = coalesce(v_resp, resposta),
         respondidoem = CASE WHEN v_resp IS NOT NULL AND v_resp IS DISTINCT FROM resposta
                             THEN public.dia_em_sao_paulo(now()) ELSE respondidoem END,
         tratadopor   = auth.uid(),
         tratadoem    = now()
   WHERE denunciaid = p_denunciaid;
END;
$function$;

-- liberar_documento_pessoal: parte da versão viva; muda só a conta de quem chama.
CREATE OR REPLACE FUNCTION public.liberar_documento_pessoal(p_documentoid integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := coalesce(public.minha_conta(), public.conta_do_gestor_editavel()); d public.documentospessoais%ROWTYPE;
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta abre documentos pessoais.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentospessoais WHERE documentoid = p_documentoid AND contaid = v_conta;
  IF NOT FOUND OR d.situacao = 'Excluido' THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.documentosacessos (contaid, documentoid, caminho, acao, usuario)
  VALUES (v_conta, d.documentoid, d.caminhoarquivo, 'visualizacao', auth.uid());
  RETURN d.caminhoarquivo;
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929264000_leituras_painel_fila.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 3, fatia 1: a base das leituras por loja, o
-- painel da loja e a fila (29/09/2026).
--
-- O gerente continua "fechado": minha_conta() segue vazia para ele, então toda
-- regra de leitura das tabelas e toda função que lê pela conta seguem sem
-- mostrar nada a ele. Nada disso muda.
-- O que muda: cada tela da lista (Início, bolinhas do menu, Quadro, fila,
-- painel da loja, relatórios, metas) ganha um RAMO DO GERENTE, no começo da
-- função, que só lê as lojas em que ele tem a permissão de VER aquela tela.
-- O caminho do master fica igual, linha por linha.
-- Mais restritivo (parte 4 refina): no painel, o bloco da meta (tem R$) só com
-- "Ver valores em R$"; o da agenda (tem nome de cliente) só com "Agenda: ver".

-- A conta do gerente que chama (ativo, conta não cancelada); vazio para
-- qualquer outro. Não recebe nada: só diz a conta de quem pergunta.
CREATE OR REPLACE FUNCTION public.conta_do_gerente()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.contaid
    FROM public.contasusuarios cu
    JOIN public.usuariosgerenciais ug ON ug.contaid = cu.contaid AND ug.userid = cu.userid AND ug.ativo
    JOIN public.contas c ON c.contaid = cu.contaid AND c.status <> 'cancelada'
   WHERE cu.userid = auth.uid() AND cu.papel = 'gerente'
$$;
REVOKE ALL ON FUNCTION public.conta_do_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_do_gerente() TO authenticated;

-- painel_da_loja: parte da versão viva (20260924... montar_painel); ramo do gerente.
CREATE OR REPLACE FUNCTION public.painel_da_loja(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.minha_conta();
  v_painel  jsonb;
  v_gerente boolean := false;
BEGIN
  IF v_conta IS NULL THEN
    -- Ramo do gerente (parte 3): só a loja em que ele pode ver o painel.
    v_conta := public.conta_do_gerente();
    IF v_conta IS NULL OR NOT public.pode('painel.ver', p_lojaid) THEN
      RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    v_gerente := true;
  END IF;

  v_painel := public.montar_painel(v_conta, p_lojaid, false);
  IF v_painel IS NULL THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_gerente THEN
    IF NOT public.pode('valores.ver_rs', p_lojaid) THEN
      v_painel := v_painel - 'meta';
    END IF;
    IF NOT public.pode('agenda.ver', p_lojaid) THEN
      v_painel := v_painel - 'agenda';
    END IF;
  END IF;
  RETURN v_painel;
END;
$function$;

-- fila_da_loja: parte da versão viva; o gerente vê a fila da loja em que pode
-- ver o Quadro.
CREATE OR REPLACE FUNCTION public.fila_da_loja(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text, disponivel boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.*
    FROM public.fila_de_hoje(coalesce(public.minha_conta(),
                                      CASE WHEN public.pode('quadro.ver', p_lojaid) THEN public.conta_do_gerente() END),
                             p_lojaid) f
   ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid
$function$;

-- ------------------------------------------------------------------------
-- 20260929265000_leituras_quadro.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 3, fatia 2: o Quadro por loja (29/09/2026).
--
-- As leituras do Quadro ganham o ramo do gerente: validação (pendentes e
-- histórico), a lista para registrar entrega, a fila de um dia que passou, e as
-- tarefas de quem está de folga. O master segue pelo caminho de sempre (as
-- mesmas linhas); o gerente é desviado, no começo, para uma versão que lê SÓ a
-- loja pedida e só se ele pode (Quadro: ver; registrar entrega; passar folga).
-- As versões do gerente usam o "hoje" da conta (hoje_da_conta), nunca o relógio
-- de São Paulo escrito à mão.

-- ---------------------------------------------------------------------------
-- 1. Validação (pendentes e histórico)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.quadro_validacao_gerente(p_lojaid integer, p_de date, p_ate date, p_offset integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.conta_do_gerente();
  v_hoje  date;
  v_fuso  text;
  v_ate   date;
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  IF v_conta IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje := public.hoje_da_conta(v_conta);
  v_fuso := public.fuso_da_conta(v_conta);
  v_ate  := coalesce(p_ate, v_hoje - 1);
  v_de   := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$$;
REVOKE ALL ON FUNCTION public.quadro_validacao_gerente(integer, date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.quadro_validacao_gerente(integer, date, date, integer) TO authenticated;

-- quadro_validacao: parte da versão viva; muda só o desvio do gerente no começo.
CREATE OR REPLACE FUNCTION public.quadro_validacao(p_lojaid integer, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_dia   jsonb   := public.meu_hoje();
  v_hoje  date    := (v_dia->>'hoje')::date;
  v_fuso  text    := v_dia->>'fuso';
  v_ate   date    := coalesce(p_ate, (v_dia->>'hoje')::date - 1);
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.quadro_validacao_gerente(p_lojaid, p_de, p_ate, p_offset);
  END IF;
  v_de := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 -- Foto vencida (na fila para apagar) não aparece (29/09/2026).
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  -- O histórico não leva "sem hora da foto": a decisão já foi tomada.
  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    -- Pediu 51 para saber se tem mais; devolve 50.
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. A lista para registrar entrega em nome de alguém
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar_gerente(p_lojaid integer)
RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer,
              nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_da_conta(ctx.conta, ta.dataagendamento) < public.hoje_da_conta(ctx.conta)) AS atrasada
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid AND f.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND public.pode('quadro.registrar_entrega', p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.funcionarioid IS NOT NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, public.hoje_da_conta(ctx.conta), public.fuso_da_conta(ctx.conta))
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, public.hoje_da_conta(ctx.conta), false)
     AND NOT public.passada_hoje(ta.atribuicaoid, public.hoje_da_conta(ctx.conta))
     AND NOT EXISTS (
       SELECT 1 FROM public.entregas e
        WHERE e.contaid = ctx.conta AND e.atribuicaoid = ta.atribuicaoid
          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
          AND (ta.tipofrequencia = 'Unica' OR public.dia_da_conta(ctx.conta, e.dataenvio) = public.hoje_da_conta(ctx.conta)))
   ORDER BY f.nomecompleto, t.titulo
$$;
REVOKE ALL ON FUNCTION public.atribuicoes_para_entregar_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.atribuicoes_para_entregar_gerente(integer) TO authenticated;

-- atribuicoes_para_entregar: parte da versão viva; o gerente sai pela versão dele.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < hoje.dia) AS atrasada
  FROM public.tarefasatribuidas ta
  CROSS JOIN hoje
  JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
  JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
  WHERE ta.lojaid = p_lojaid
    AND ta.datafimvigencia IS NULL
    AND ta.funcionarioid IS NOT NULL
    AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, hoje.dia)
    AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, hoje.dia, false)
    AND NOT public.passada_hoje(ta.atribuicaoid, hoje.dia)
    AND NOT EXISTS (
      SELECT 1 FROM public.entregas e
      WHERE e.atribuicaoid = ta.atribuicaoid
        AND e.statusvalidacao IN ('Pendente', 'Aprovada')
        AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)
    )
    -- Ramo do gerente (parte 3): este caminho é o de sempre; o gerente vai
    -- para a versão dele, que lê só a loja pedida.
    AND NOT (public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL)
  UNION ALL
  SELECT g.* FROM public.atribuicoes_para_entregar_gerente(p_lojaid) g
   WHERE public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
  ORDER BY 5, 2
$function$;

-- ---------------------------------------------------------------------------
-- 3. A fila de um dia que passou
-- ---------------------------------------------------------------------------
-- Versão do gerente: a mesma leitura, com a conta dele escrita em cada tabela.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia_gerente(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_conta    integer := public.conta_do_gerente();
  v_hoje     date  := public.hoje_da_conta(public.conta_do_gerente());
  v_fuso     text  := public.fuso_da_conta(public.conta_do_gerente());
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
BEGIN
  IF v_conta IS NULL OR v_hoje IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid AND ta.contaid = v_conta
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid AND p.contaid = v_conta
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$$;
REVOKE ALL ON FUNCTION public.fila_de_um_dia_gerente(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fila_de_um_dia_gerente(integer, date) TO authenticated;

-- fila_de_um_dia: parte da versão viva; muda só o desvio do gerente.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_h        jsonb := public.meu_hoje();
  v_hoje     date  := (v_h->>'hoje')::date;
  v_fuso     text  := v_h->>'fuso';
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
  v_conta    integer := public.minha_conta();
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF v_conta IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fila_de_um_dia_gerente(p_lojaid, p_dia);
  END IF;
  IF v_conta IS NULL OR v_hoje IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$function$;

-- alcance_da_fila: parte da versão viva; responde também ao gerente (só datas).
CREATE OR REPLACE FUNCTION public.alcance_da_fila()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object('hoje', h.hoje, 'primeirodia', a.primeirodia)
    FROM (SELECT (public.meu_hoje()->>'hoje')::date AS hoje) h
    CROSS JOIN LATERAL public.fila_alcance(h.hoje) a
   WHERE (public.minha_conta() IS NOT NULL OR public.conta_do_gerente() IS NOT NULL) AND h.hoje IS NOT NULL
$function$;

-- ---------------------------------------------------------------------------
-- 4. Tarefas de quem está de folga (para passar a outra pessoa)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje_gerente(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta),
  hoje AS (SELECT public.hoje_da_conta(ctx.conta) AS dia, ctx.conta FROM ctx
            WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara, hoje.conta, hoje.dia
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(hoje.conta, hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia AND i.contaid = hoje.conta
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e
                                    WHERE e.contaid = it.conta AND e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_da_conta(it.conta, e.dataenvio) = it.dia)))
           ORDER BY f.nomecompleto, t.titulo), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid AND t.contaid = it.conta
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid AND f.contaid = it.conta
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara AND p.contaid = it.conta
$$;
REVOKE ALL ON FUNCTION public.tarefas_de_folga_hoje_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tarefas_de_folga_hoje_gerente(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje_gerente(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto), '[]'::jsonb)
    FROM ctx
    JOIN public.funcionarios f       ON f.contaid = ctx.conta AND f.ativo
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
                                    AND fl.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.hoje_da_conta(ctx.conta))
$$;
REVOKE ALL ON FUNCTION public.quem_trabalha_hoje_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.quem_trabalha_hoje_gerente(integer) TO authenticated;

-- tarefas_de_folga_hoje e quem_trabalha_hoje: partem das versões vivas; o
-- caminho de sempre fica dentro do ELSE, igual.
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.tarefas_de_folga_hoje_gerente(p_lojaid)
           ELSE (
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(public.minha_conta(), hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e, hoje
                                    WHERE e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)))
           ORDER BY f.nomecompleto, t.titulo), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara
           ) END
$function$;

CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.quem_trabalha_hoje_gerente(p_lojaid)
           ELSE (
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto), '[]'::jsonb)
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE f.ativo
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.dia_em_sao_paulo(now()))
           ) END
$function$;

-- ------------------------------------------------------------------------
-- 20260929265500_desempate_nas_listas.sql
-- ------------------------------------------------------------------------
-- Desempate fixo nas listas (29/09/2026, pedido do Wisley).
--
-- Duas linhas com o mesmo horário (ou o mesmo nome/título) saíam em ordem
-- incerta: a mesma consulta, rodada duas vezes, podia devolver a lista em
-- ordens diferentes. Isso já sujou duas provas de antes/depois. Cada lista de
-- gestão ordenada por horário, nome ou título ganha, no fim da ordenação, o
-- número da própria linha (a chave). A numeração das linhas da lista do dia
-- (tarefasdodia.itemid) passa a sair sempre na mesma ordem (loja, atribuição).
-- Cada função parte da versão viva e muda SÓ a ordenação.
-- Nenhum dado é alterado.

-- agendamentos_sem_tarefa: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH dia AS (SELECT (public.meu_hoje()->>'hoje')::date AS hoje, public.meu_hoje()->>'fuso' AS fuso),
  futuros AS (
    SELECT a.*, dia.fuso FROM public.agendamentos a, dia
     WHERE a.lojaid = p_lojaid AND a.statusagendamento = 'Confirmado'
       AND (a.dataevento AT TIME ZONE dia.fuso)::date >= dia.hoje
  ),
  situacao AS (
    SELECT f.*,
           ta.atribuicaoid,
           ta.datafimvigencia AS datafimvigencia_ta,
           EXISTS (SELECT 1 FROM public.entregas e
                    WHERE e.atribuicaoid = ta.atribuicaoid AND e.statusvalidacao IN ('Pendente', 'Aprovada')) AS entregue,
           t.ativa AS tarefaativa,
           EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                     JOIN public.funcionarios fu ON fu.contaid = fl.contaid AND fu.funcionarioid = fl.funcionarioid
                    WHERE fl.lojaid = f.lojaid AND fl.funcionarioid = ta.funcionarioid AND fl.ativo AND fu.ativo) AS respnaloja
      FROM futuros f
      -- A última tarefa do agendamento, em aberto ou não (a entregue e
      -- encerrada não é problema).
      LEFT JOIN LATERAL (SELECT x.* FROM public.tarefasatribuidas x
                          WHERE x.agendamentoid = f.agendamentoid
                          ORDER BY x.atribuicaoid DESC LIMIT 1) ta ON true
      LEFT JOIN public.tarefas t ON t.contaid = ta.contaid AND t.tarefaid = ta.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'agendamentoid', s.agendamentoid,
           'quando', to_char(s.dataevento AT TIME ZONE s.fuso, 'DD/MM/YYYY HH24:MI'),
           'cliente', s.nomecliente,
           'responsavel', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = s.funcionarioid),
           'motivo', CASE WHEN s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL THEN 'sem_tarefa'
                          WHEN NOT s.tarefaativa THEN 'tarefa_desativada'
                          ELSE 'responsavel_fora' END)
         ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
$function$;

-- conflitos_agendamento: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.conflitos_agendamento(p_lojaid integer, p_dataevento timestamp with time zone, p_ignorar integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object('quando', dataevento, 'tipo', tipoevento) ORDER BY dataevento, agendamentoid), '[]'::jsonb)
    FROM public.agendamentos
   WHERE lojaid = p_lojaid AND statusagendamento = 'Confirmado'
     AND (p_ignorar IS NULL OR agendamentoid <> p_ignorar)
     AND dataevento BETWEEN p_dataevento - interval '2 hours' AND p_dataevento + interval '2 hours'
$function$;

-- fila_de_um_dia: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_h        jsonb := public.meu_hoje();
  v_hoje     date  := (v_h->>'hoje')::date;
  v_fuso     text  := v_h->>'fuso';
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
  v_conta    integer := public.minha_conta();
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF v_conta IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fila_de_um_dia_gerente(p_lojaid, p_dia);
  END IF;
  IF v_conta IS NULL OR v_hoje IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio, e.entregaid), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem, a.aceiteid), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$function$;

-- fila_de_um_dia_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia_gerente(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta    integer := public.conta_do_gerente();
  v_hoje     date  := public.hoje_da_conta(public.conta_do_gerente());
  v_fuso     text  := public.fuso_da_conta(public.conta_do_gerente());
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
BEGIN
  IF v_conta IS NULL OR v_hoje IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio, e.entregaid), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem, a.aceiteid), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid AND ta.contaid = v_conta
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid AND p.contaid = v_conta
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$function$;

-- fila_no_dia: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.fila_no_dia(p_contaid integer, p_lojaid integer, p_dia date, p_fim timestamp with time zone)
 RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (
    SELECT p_contaid AS conta,
           p_dia AS dia,
           public.fuso_da_conta(p_contaid) AS fuso,
           -- O fim do dia (a meia-noite seguinte), ou infinity para hoje.
           p_fim AS fim,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = p_contaid AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
  )
  SELECT ta.atribuicaoid,
         CASE WHEN a.aceiteid IS NOT NULL THEN coalesce(a.novaatribuicaoid, ta.atribuicaoid) END,
         t.titulo,
         t.pontos,
         ta.tipofrequencia,
         (ta.funcionarioid IS NULL),
         ta.funcionarioid,
         a.funcionarioid,
         public.nome_curto(qp.nomecompleto),
         a.aceitoem,
         CASE
           -- Tarefa Única: entregue num dia, acabou (vale para a tarefa com
           -- dono e para qualquer cópia da compartilhada).
           WHEN ta.tipofrequencia = 'Unica' AND unica.cumprida THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.dataenvio < ctx.fim
                           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                           AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         -- Atrasada é o que AINDA falta fazer. A Única entregue hoje, mesmo
         -- marcada para ontem, está em "Feitas hoje": não é atrasada.
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.dia
          AND NOT unica.cumprida),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_na_conta(ctx.conta, ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) = ctx.dia
                THEN ta.dataagendamento END,
           -- A hora de liberação também conta: o cronômetro de uma tarefa que
           -- abre às 18h começa às 18h, e não à meia-noite — senão ela nasceria
           -- vermelha, com 18 horas de "parada".
           lib.quando),
         (ctx.rodizio > 0 AND ta.funcionarioid IS NULL),
         now(),
         -- nome_curto(NULL) devolve texto VAZIO, nao nulo: sem este CASE a
         -- coluna vinha '' para toda tarefa sem entrega, e "sem nome" deixava
         -- de ser distinguivel de "nome vazio".
         CASE WHEN ent.funcionarioid IS NOT NULL THEN public.nome_curto(fez.nomecompleto) END,
         ent.dataenvio,
         ent.statusvalidacao,
         (lib.quando IS NULL OR lib.quando <= now()),
         lib.quando,
         ctx.dia,
         ctx.fuso
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.aceitoem < ctx.fim
                                      AND (a.revogadoem IS NULL OR a.revogadoem >= ctx.fim)
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- Única cumprida (a de tarefa_unica_ja_cumprida, no fim do dia): entregue
    -- por qualquer cópia, em qualquer dia até o fim deste.
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM public.entregas e
          JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = ctx.conta
         WHERE e.contaid = ctx.conta
           AND e.dataenvio < ctx.fim
           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
           AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)) AS cumprida
    ) unica ON true
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só do dia.
    -- A situação é a do fim do dia: recusada ou estornada DEPOIS dele, ainda
    -- estava pendente ou aprovada.
    LEFT JOIN LATERAL (
      SELECT e.funcionarioid, e.dataenvio,
             CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                  WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                  WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= ctx.fim THEN 'Pendente'
                  ELSE e.statusvalidacao END::varchar AS statusvalidacao
        FROM public.entregas e
       WHERE e.contaid = ctx.conta
         AND e.dataenvio < ctx.fim
         AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
              OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
              OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
         AND (
           (ta.tipofrequencia = 'Unica'
            AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                         WHERE c.contaid = ctx.conta AND c.atribuicaoid = e.atribuicaoid
                           AND (c.atribuicaoid = ta.atribuicaoid
                                OR c.origematribuicaoid = ta.atribuicaoid)))
           OR (e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
               AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia)
         )
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 1
    ) ent ON true
    LEFT JOIN public.funcionarios fez  ON fez.funcionarioid = ent.funcionarioid AND fez.contaid = ctx.conta
    -- A hora de liberação, no fuso DA EMPRESA. A conversão é feita aqui, com
    -- o relógio do servidor: o tablet e o celular não opinam.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN ta.disponivelapartir IS NOT NULL
                  THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.disponivelapartir) END AS quando
    ) lib ON true
   WHERE ctx.conta IS NOT NULL
     -- Valia no fim do dia: criada antes dele e não encerrada antes dele.
     AND coalesce(ta.criadaem, '-infinity'::timestamptz) < ctx.fim
     AND (ta.datafimvigencia IS NULL OR ta.encerradaem >= ctx.fim)
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     -- tem_justificativa(..., false), no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.justificativas j
                      WHERE j.contaid = ctx.conta AND j.atribuicaoid = ta.atribuicaoid
                        AND (ta.tipofrequencia = 'Unica' OR j.dia = ctx.dia)
                        AND j.registradoem < ctx.fim
                        AND (j.status IN ('Aceita', 'Pendente')
                             OR (j.status = 'Recusada' AND j.decididoem >= ctx.fim)))
     -- passada_hoje, no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.tarefasdodia p
                      WHERE p.contaid = ctx.conta AND p.atribuicaoid = ta.atribuicaoid AND p.dia = ctx.dia
                        AND p.passadapara IS NOT NULL
                        AND coalesce(p.passadaem, '-infinity'::timestamptz) < ctx.fim)
     -- A Única entregue num dia ANTERIOR acabou: não volta na fila de hoje.
     -- Sem isto ela ficava para sempre em "Feitas hoje" (a regra de "feita"
     -- da Única vale para qualquer dia, porque ela só se faz uma vez), e
     -- ainda marcada como atrasada. A TV já tinha esta regra; a fila, não.
     AND NOT (ta.tipofrequencia = 'Unica'
              AND EXISTS (SELECT 1 FROM public.entregas e
                            JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid
                                                           AND c.contaid = ctx.conta
                           WHERE e.contaid = ctx.conta
                             AND e.dataenvio < ctx.fim
                             AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                  OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                             AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                             AND public.dia_no_fuso(e.dataenvio, ctx.fuso) < ctx.dia))
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3, 1
$function$;

-- quadro_validacao: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quadro_validacao(p_lojaid integer, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_dia   jsonb   := public.meu_hoje();
  v_hoje  date    := (v_dia->>'hoje')::date;
  v_fuso  text    := v_dia->>'fuso';
  v_ate   date    := coalesce(p_ate, (v_dia->>'hoje')::date - 1);
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.quadro_validacao_gerente(p_lojaid, p_de, p_ate, p_offset);
  END IF;
  v_de := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio, x.entregaid), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 -- Foto vencida (na fila para apagar) não aparece (29/09/2026).
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  -- O histórico não leva "sem hora da foto": a decisão já foi tomada.
  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    -- Pediu 51 para saber se tem mais; devolve 50.
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$function$;

-- quadro_validacao_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quadro_validacao_gerente(p_lojaid integer, p_de date, p_ate date, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gerente();
  v_hoje  date;
  v_fuso  text;
  v_ate   date;
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  IF v_conta IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje := public.hoje_da_conta(v_conta);
  v_fuso := public.fuso_da_conta(v_conta);
  v_ate  := coalesce(p_ate, v_hoje - 1);
  v_de   := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio, x.entregaid), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$function$;

-- atribuicoes_para_entregar: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < hoje.dia) AS atrasada
  FROM public.tarefasatribuidas ta
  CROSS JOIN hoje
  JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
  JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
  WHERE ta.lojaid = p_lojaid
    AND ta.datafimvigencia IS NULL
    AND ta.funcionarioid IS NOT NULL
    AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, hoje.dia)
    AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, hoje.dia, false)
    AND NOT public.passada_hoje(ta.atribuicaoid, hoje.dia)
    AND NOT EXISTS (
      SELECT 1 FROM public.entregas e
      WHERE e.atribuicaoid = ta.atribuicaoid
        AND e.statusvalidacao IN ('Pendente', 'Aprovada')
        AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)
    )
    -- Ramo do gerente (parte 3): este caminho é o de sempre; o gerente vai
    -- para a versão dele, que lê só a loja pedida.
    AND NOT (public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL)
  UNION ALL
  SELECT g.* FROM public.atribuicoes_para_entregar_gerente(p_lojaid) g
   WHERE public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
  ORDER BY 5, 2, 1
$function$;

-- atribuicoes_para_entregar_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar_gerente(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_da_conta(ctx.conta, ta.dataagendamento) < public.hoje_da_conta(ctx.conta)) AS atrasada
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid AND f.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND public.pode('quadro.registrar_entrega', p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.funcionarioid IS NOT NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, public.hoje_da_conta(ctx.conta), public.fuso_da_conta(ctx.conta))
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, public.hoje_da_conta(ctx.conta), false)
     AND NOT public.passada_hoje(ta.atribuicaoid, public.hoje_da_conta(ctx.conta))
     AND NOT EXISTS (
       SELECT 1 FROM public.entregas e
        WHERE e.contaid = ctx.conta AND e.atribuicaoid = ta.atribuicaoid
          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
          AND (ta.tipofrequencia = 'Unica' OR public.dia_da_conta(ctx.conta, e.dataenvio) = public.hoje_da_conta(ctx.conta)))
   ORDER BY f.nomecompleto, t.titulo, ta.atribuicaoid
$function$;

-- painel_inicio: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.painel_inicio(p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje      date := public.dia_em_sao_paulo(now());
  v_mes_ini   date := date_trunc('month', public.dia_em_sao_paulo(now()))::date;
  v_mes_fim   date := (date_trunc('month', public.dia_em_sao_paulo(now())) + interval '1 month - 1 day')::date;
  v_sem_ini   date := (date_trunc('week', public.dia_em_sao_paulo(now())) - interval '7 weeks')::date;
  v_lojas     integer[];
  v_cartoes   jsonb;
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
  v_guia      jsonb;
BEGIN
  IF public.minha_conta() IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Lojas consideradas: a escolhida ou todas as ativas (a RLS já limita à conta).
  IF p_lojaid IS NULL THEN
    SELECT coalesce(array_agg(lojaid), '{}') INTO v_lojas FROM public.lojas WHERE ativa;
  ELSE
    SELECT array_agg(lojaid) INTO v_lojas FROM public.lojas WHERE lojaid = p_lojaid;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;

  -- Tarefas de hoje: a MESMA fila do tablet, do Quadro e da TV (29/09/2026,
  -- decisão do Wisley — a sexta vez que a mesma pergunta tinha duas
  -- respostas). Antes este cartão tinha regra própria: só tarefa com dono,
  -- contava quem estava de folga e ficava de fora a missão da equipe.
  -- fila_da_loja confere a conta de quem pede; a RLS já limitou v_lojas.
  -- A MESMA conta da TV (progresso_da_fila): a fração "concluídas" conta só
  -- as APROVADAS; o que espera o gestor fica à parte (29/09/2026).
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_da_loja(l.lojaid) f;

  -- Meta do dia: soma das lojas que têm meta hoje.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  -- Meta do mês: soma das metas do mês das lojas.
  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1,
                                                            public.meu_hoje()->>'fuso')) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.lojaid = ANY (v_lojas) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             -- Dias (por loja) do mês com meta e sem venda lançada, até ontem.
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  v_cartoes := jsonb_build_object(
    'tarefas',      v_tarefas,
    'metadia',      v_metadia,
    'metames',      v_metames,
    'validar',      (SELECT count(*) FROM public.entregas
                      WHERE lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
    'agendahoje',   (SELECT count(*) FROM public.agendamentos
                      WHERE lojaid = ANY (v_lojas) AND statusagendamento <> 'Cancelado'
                        AND public.dia_em_sao_paulo(dataevento) = v_hoje),
    'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                               'pessoas',     count(DISTINCT s.funcionarioid))
                       FROM public.documentosassinaturas s
                       JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                       JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                      WHERE s.statusassinatura = 'Pendente'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                       JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.ativo
                      WHERE o.statusworkflow = 'Em andamento'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                      WHERE lojaid = ANY (v_lojas) AND status IN ('Aberta', 'Em andamento')),
    'justificativas', (SELECT count(*) FROM public.justificativas
                        WHERE lojaid = ANY (v_lojas) AND status = 'Pendente'));

  -- Vendas do mês, dia a dia, contra a meta (soma das lojas).
  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                            AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas;

  -- Pontos por semana (últimas 8, começando na segunda), pelo livro.
  -- Entraram: aprovações e bônus, já descontados os estornos.
  -- Saíram: resgates, já descontados cancelamentos e estornos de resgate.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(mv.datamovimento))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE 'America/Sao_Paulo')
       AND (p_lojaid IS NULL OR mv.lojaid = p_lojaid)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês (pelo dia da decisão).
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.dataaprovacao))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN v_mes_ini AND v_hoje
    UNION ALL
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.datarecusa))::date, 'r'
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_em_sao_paulo(e.datarecusa) BETWEEN v_mes_ini AND v_hoje
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês (pontos aprovados no mês).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT * FROM public.ranking_pontos(v_mes_ini, v_hoje, p_lojaid) LIMIT 5) r;

  -- Próximos agendamentos: hora, tipo e responsável (sem dados do cliente).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid
       WHERE a.lojaid = ANY (v_lojas) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
        JOIN public.lojas l        ON l.lojaid = e.lojaid
       WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  -- Guia de primeiros passos (vale para a conta toda).
  v_guia := jsonb_build_object(
    'loja',    EXISTS (SELECT 1 FROM public.lojas WHERE ativa),
    'equipe',  EXISTS (SELECT 1 FROM public.funcionarios f
                         JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.ativo
                        WHERE f.ativo),
    'tarefas', EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
                         JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
                        WHERE ta.datafimvigencia IS NULL AND t.sistema IS NULL),
    'meta',    EXISTS (SELECT 1 FROM public.metasdiariasmodelos WHERE valormeta > 0)
               OR EXISTS (SELECT 1 FROM public.metasprincipais),
    'tv',      EXISTS (SELECT 1 FROM public.linkstv WHERE revogadoem IS NULL));

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes',      v_cartoes,
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    'guia',         v_guia,
    -- Avisos (calculados na hora, sem rotina).
    'avisos', jsonb_build_object(
      -- VENDA DE ONTEM NÃO LANÇADA (29/09/2026): loja ativa que tinha meta
      -- ontem (a especial da data ou o modelo do dia da semana, com valor) e
      -- não tem lançamento de ontem. Loja que não abre tem meta zero naquele
      -- dia (ou uma especial com valor 0 no feriado) e não avisa. Só ontem:
      -- não acumula. Todas as lojas que a pessoa enxerga, com ou sem filtro.
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                       CROSS JOIN LATERAL (SELECT (public.meu_hoje()->>'hoje')::date - 1 AS dia) o
                      WHERE l.ativa
                        -- A MESMA regra da faixa do mês (dias_sem_lancamento).
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, o.dia, o.dia,
                                                                               public.meu_hoje()->>'fuso'))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE lojaid = ANY (v_lojas) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                          WHERE s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND (p_lojaid IS NULL OR EXISTS (
                                  SELECT 1 FROM public.funcionarioslojas fl
                                   WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
      'livro', (SELECT CASE WHEN r.resultado = 'ok' THEN 'ok'
                            WHEN r.detalhe ? 'diferencas' THEN 'diferenca' ELSE 'erro' END
                  FROM public.rotinasexecucoes r
                 WHERE r.rotina = 'conferencia_livro'
                 ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1)),
    -- Última geração da lista de hoje (para "rodou sozinha às 00:05 ✓").
    'rotina', (SELECT jsonb_build_object('quando', coalesce(r.terminadoem, r.iniciadoem),
                                         'resultado', r.resultado, 'origem', r.origem)
                 FROM public.rotinasexecucoes r
                WHERE r.rotina = 'lista_do_dia' AND r.referencia = v_hoje
                ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1));
END;
$function$;

-- visao_mural: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.visao_mural(p_contaid integer, p_lojaid integer, p_funcionarioid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
             'quando',       s.dataenvio) ORDER BY s.dataenvio, s.assinaturaid), '[]'::jsonb)
      FROM public.documentosassinaturas s
      JOIN public.documentos d ON d.documentoid = s.documentoid AND d.contaid = p_contaid
     WHERE s.contaid = p_contaid
       AND s.funcionarioid = p_funcionarioid
       -- SÓ o que falta ler. Nada de histórico: o tablet é compartilhado.
       AND s.statusassinatura = 'Pendente'
       AND d.status = 'Publicado');
END;
$function$;

-- tarefas_nao_pegas: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(atribuicaoid integer, lojaid integer, loja character varying, titulo character varying, pontos integer, atribuidos text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.minha_conta() AS conta,
                      public.hoje_da_conta(public.minha_conta()) AS dia,
                      public.fuso_da_conta(public.minha_conta()) AS fuso)
  SELECT ta.atribuicaoid, ta.lojaid, l.nome, t.titulo, t.pontos,
         coalesce((SELECT string_agg(public.nome_curto(f.nomecompleto), ', ' ORDER BY f.nomecompleto)
                     FROM public.tarefascandidatos c
                     JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = ctx.conta
                    WHERE c.contaid = ctx.conta AND c.atribuicaoid = ta.atribuicaoid),
                  'toda a equipe da loja')
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.funcionarioid IS NULL
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
   WHERE ctx.conta IS NOT NULL
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo, ta.atribuicaoid
$function$;

-- quem_trabalha_hoje: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.quem_trabalha_hoje_gerente(p_lojaid)
           ELSE (
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto, f.funcionarioid), '[]'::jsonb)
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE f.ativo
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.dia_em_sao_paulo(now()))
           ) END
$function$;

-- quem_trabalha_hoje_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje_gerente(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto, f.funcionarioid), '[]'::jsonb)
    FROM ctx
    JOIN public.funcionarios f       ON f.contaid = ctx.conta AND f.ativo
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
                                    AND fl.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.hoje_da_conta(ctx.conta))
$function$;

-- tarefas_de_folga_hoje: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.tarefas_de_folga_hoje_gerente(p_lojaid)
           ELSE (
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(public.minha_conta(), hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e, hoje
                                    WHERE e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)))
           ORDER BY f.nomecompleto, t.titulo, it.atribuicaoid), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara
           ) END
$function$;

-- tarefas_de_folga_hoje_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje_gerente(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta),
  hoje AS (SELECT public.hoje_da_conta(ctx.conta) AS dia, ctx.conta FROM ctx
            WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara, hoje.conta, hoje.dia
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(hoje.conta, hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia AND i.contaid = hoje.conta
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e
                                    WHERE e.contaid = it.conta AND e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_da_conta(it.conta, e.dataenvio) = it.dia)))
           ORDER BY f.nomecompleto, t.titulo, it.atribuicaoid), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid AND t.contaid = it.conta
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid AND f.contaid = it.conta
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara AND p.contaid = it.conta
$function$;

-- pendencias_da_pessoa: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.dia_em_sao_paulo(now()) - 1) AS fim
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, lim
     WHERE dg.contaid = public.minha_conta() AND dg.dia BETWEEN lim.ini AND lim.fim
  ),
  itens AS (
    -- Dias com lista congelada.
    SELECT i.dia, i.atribuicaoid, i.tipofrequencia, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN gerados g           ON g.dia = i.dia
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid
     WHERE i.funcionarioid = p_funcionarioid
       AND i.situacao = 'devida'
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = i.dia))
    UNION ALL
    -- Dias sem lista: regra do cadastro.
    SELECT g.d::date, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_em_sao_paulo(e.dataenvio) = g.d::date)
    UNION ALL
    SELECT public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN lim.ini AND lim.fim
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) NOT IN (SELECT dia FROM gerados)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo, i.atribuicaoid), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
$function$;

-- tarefas_pegas_da_pessoa: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_pegas_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS TABLE(dia date, titulo character varying, pontos integer, loja character varying, entregue boolean, revogadoem timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.minha_conta() AS conta)
  SELECT a.dia, t.titulo, t.pontos, l.nome,
         EXISTS (SELECT 1 FROM public.entregas e
                  WHERE e.contaid = ctx.conta AND e.atribuicaoid = a.novaatribuicaoid
                    AND e.statusvalidacao IN ('Pendente', 'Aprovada')),
         a.revogadoem
    FROM ctx
    JOIN public.missoesaceites a     ON a.contaid = ctx.conta AND a.funcionarioid = p_funcionarioid
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.atribuicaoid = a.novaatribuicaoid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    LEFT JOIN public.lojas l         ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND a.novaatribuicaoid IS NOT NULL
     AND a.dia BETWEEN p_de AND p_ate
   ORDER BY a.dia DESC, t.titulo, a.aceiteid
$function$;

-- ranking_pontos: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.ranking_pontos(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
  FROM public.entregas e
  JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
  WHERE e.statusvalidacao = 'Aprovada'
    AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN p_de AND p_ate
    AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  GROUP BY f.funcionarioid, f.nomecompleto
  ORDER BY 3 DESC, 2, 1
$function$;

-- analise_de_tarefas: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.analise_de_tarefas(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM public.entregas e
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM public.justificativas j
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR j.lojaid = p_lojaid)
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo, t.tarefaid), '[]'::jsonb)
    FROM juntos j
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid
$function$;

-- situacao_dos_acessos: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
 RETURNS TABLE(funcionarioid integer, temacesso boolean, nuncaentrou boolean, semsenha boolean, sempin boolean, codigopendente boolean, codigoexpiraem timestamp with time zone, redefinidoem timestamp with time zone, codigogeradoem timestamp with time zone, codigogeradopor text, codigoreimprimivel boolean, folhaemitidaem timestamp with time zone, folhaemitidapor text, folhas integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem,
         k.criadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = k.criadopor),
         k.codigocifrado IS NOT NULL,
         fa.emitidaem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = fa.emitidapor),
         coalesce(fa.total, 0)::integer
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem, criadoem, criadopor, codigocifrado FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC, x.folhaid DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
   ORDER BY f.funcionarioid
$function$;

-- folha_de_acesso: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.folha_de_acesso(p_contaid integer, p_funcionarioids integer[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'conta',  c.nomefantasia,
    'codigoempresa', c.codigo,
    'pessoas', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'funcionarioid', f.funcionarioid,
               'nome',          f.nomecompleto,
               'cargo',         f.cargo,
               'cpf',           f.cpf,
               'ativo',         f.ativo,
               'lojas',         coalesce((SELECT jsonb_agg(l.nome ORDER BY l.nome)
                                            FROM public.funcionarioslojas fl
                                            JOIN public.lojas l ON l.contaid = fl.contaid AND l.lojaid = fl.lojaid
                                           WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid
                                             AND fl.ativo AND l.ativa), '[]'::jsonb),
               'temacesso',     cu.userid IS NOT NULL,
               'jaentrou',      (f.senhahashapp IS NOT NULL OR f.pinhash IS NOT NULL),
               'codigo',        CASE WHEN k.codigoid IS NOT NULL THEN jsonb_build_object(
                                  'codigoid', k.codigoid, 'cifrado', k.codigocifrado,
                                  'expiraem', k.expiraem, 'criadoem', k.criadoem) END
             ) ORDER BY f.nomecompleto, f.funcionarioid)
        FROM public.funcionarios f
        LEFT JOIN public.contasusuarios cu
               ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
        LEFT JOIN LATERAL (SELECT k2.codigoid, k2.codigocifrado, k2.expiraem, k2.criadoem
                             FROM public.codigosacesso k2
                            WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                              AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                            ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
       WHERE f.contaid = c.contaid AND f.funcionarioid = ANY (p_funcionarioids)), '[]'::jsonb))
    FROM public.contas c
   WHERE c.contaid = p_contaid AND public.bot_contexto_confiavel()
$function$;

-- rotinas_resumo_admin: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.rotinas_resumo_admin()
 RETURNS TABLE(contaid integer, rotina text, ultimaem timestamp with time zone, situacao text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.eh_admin_geral() THEN
    RAISE EXCEPTION 'Só o administrador geral vê este resumo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
    SELECT DISTINCT ON (r.contaid, r.rotina)
           r.contaid, r.rotina::text, coalesce(r.terminadoem, r.iniciadoem),
           CASE WHEN r.resultado = 'ok' THEN 'ok'
                WHEN r.detalhe ? 'diferencas' THEN 'diferenca'
                ELSE 'erro' END
      FROM public.rotinasexecucoes r
     ORDER BY r.contaid, r.rotina, r.iniciadoem DESC, r.execucaoid DESC;
END;
$function$;

-- eu_resgates: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.eu_resgates(p_contaid integer, p_funcionarioid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'resgateid', r.resgateid,
             'nome',      p.nome,
             'pontos',    r.pontosgastos,
             'quando',    r.datasolicitacao,
             'status',    r.status) ORDER BY r.datasolicitacao DESC, r.resgateid DESC), '[]'::jsonb)
      FROM public.resgates r
      JOIN public.produtosloja p ON p.produtoid = r.produtoid AND p.contaid = p_contaid
     WHERE r.contaid = p_contaid AND r.funcionarioid = p_funcionarioid
       AND r.datasolicitacao > now() - interval '90 days');
END;
$function$;

-- eu_tarefas: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.eu_tarefas(p_contaid integer, p_funcionarioid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje date := public.hoje_da_conta(p_contaid);
  v_fuso text := public.fuso_da_conta(p_contaid);
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', x.atribuicaoid,
             'titulo',       x.titulo,
             'pontos',       x.pontos,
             'loja',         x.loja,
             'pegaem',       x.pegaem,
             'situacao',     x.situacao,
             -- Enquanto não libera, a tela do celular mostra "a partir das 15h".
             'liberaas',     x.liberaas,
             'liberada',     x.liberada) ORDER BY x.pegaem NULLS LAST, x.titulo, x.atribuicaoid), '[]'::jsonb)
      FROM (
        SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome AS loja, a.aceitoem AS pegaem,
               CASE WHEN e.entregaid IS NULL THEN 'a_fazer'
                    WHEN e.statusvalidacao = 'Pendente'  THEN 'esperando'
                    WHEN e.statusvalidacao = 'Aprovada'  THEN 'aprovada'
                    ELSE 'recusada' END AS situacao,
               -- A hora de liberação, no fuso da EMPRESA e com o relógio do
               -- servidor. O celular não converte nada.
               CASE WHEN ta.disponivelapartir IS NOT NULL
                    THEN public.instante_na_conta(p_contaid, v_hoje, ta.disponivelapartir) END AS liberaas,
               (ta.disponivelapartir IS NULL
                OR public.instante_na_conta(p_contaid, v_hoje, ta.disponivelapartir) <= now()) AS liberada
          FROM public.tarefasatribuidas ta
          JOIN public.tarefas t  ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
                                AND coalesce(t.ativa, true)
          -- Loja desativada não gera mais tarefa: era LEFT JOIN e passava.
          JOIN public.lojas l    ON l.lojaid = ta.lojaid AND l.contaid = p_contaid AND l.ativa
          JOIN public.funcionarios fu ON fu.funcionarioid = p_funcionarioid AND fu.contaid = p_contaid
          LEFT JOIN public.missoesaceites a
                 ON a.contaid = p_contaid AND a.novaatribuicaoid = ta.atribuicaoid AND a.revogadoem IS NULL
          LEFT JOIN LATERAL (
            SELECT e2.entregaid, e2.statusvalidacao FROM public.entregas e2
             WHERE e2.contaid = p_contaid AND e2.atribuicaoid = ta.atribuicaoid
               AND (ta.tipofrequencia = 'Unica' OR public.dia_no_fuso(e2.dataenvio, v_fuso) = v_hoje)
             ORDER BY e2.dataenvio DESC, e2.entregaid DESC LIMIT 1) e ON true
         WHERE ta.contaid = p_contaid
           AND ta.funcionarioid = p_funcionarioid
           AND ta.datafimvigencia IS NULL
           AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje, v_fuso)
           AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
           AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
           -- A CÓPIA de quem pegou uma tarefa compartilhada é daquele dia: o
           -- aceite vale só no dia, e depois dele ninguém entrega por ela.
           -- Cópia de outro dia só aparece no dia em que o gestor a recusou
           -- ou estornou (para a pessoa ver que precisa refazer — refazer é
           -- aceitar de novo no tablet, e isso gera outra cópia). Sem isto, a
           -- cópia estornada ficava "recusada" no celular para sempre.
           AND (ta.origematribuicaoid IS NULL
                OR public.dia_no_fuso(ta.dataagendamento, v_fuso) = v_hoje
                OR EXISTS (SELECT 1 FROM public.entregas e4
                            WHERE e4.contaid = p_contaid AND e4.atribuicaoid = ta.atribuicaoid
                              AND public.dia_no_fuso(coalesce(e4.dataestorno, e4.datarecusa), v_fuso) = v_hoje))
           -- A Única entregue num dia ANTERIOR acabou: não volta hoje (a
           -- mesma regra da fila do tablet e da TV).
           AND NOT (ta.tipofrequencia = 'Unica'
                    AND EXISTS (SELECT 1 FROM public.entregas e3
                                 WHERE e3.contaid = p_contaid AND e3.atribuicaoid = ta.atribuicaoid
                                   AND e3.statusvalidacao IN ('Pendente', 'Aprovada')
                                   AND public.dia_no_fuso(e3.dataenvio, v_fuso) < v_hoje))
           -- Folga, afastamento e vínculo com a loja: as mesmas condições da
           -- fila do tablet.
           AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                      fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
           AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                        WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid
                          AND fl.lojaid = ta.lojaid AND fl.ativo)
      ) x);
END;
$function$;

-- anexos_admin: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.anexos_admin()
 RETURNS TABLE(anexoid integer, contaid integer, redeid integer, nomearquivo character varying, tipo character varying, tamanho integer, enviadoem timestamp with time zone, enviadopor text, removidoem timestamp with time zone, removidopor text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.eh_admin_geral() THEN
    RAISE EXCEPTION 'Só o administrador geral.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT a.anexoid, a.contaid, a.redeid, a.nomearquivo, a.tipo, a.tamanho, a.enviadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = a.enviadopor),
         a.removidoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = a.removidopor)
    FROM public.anexosadmin a
   ORDER BY a.enviadoem DESC, a.anexoid DESC;
END;
$function$;

-- lista_do_dia_gerar: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.lista_do_dia_gerar(p_contaid integer, p_dia date, p_hoje date, p_recuperado boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_novos      integer := 0;
  v_cancelados integer := 0;
  v_ajustados  integer := 0;
BEGIN
  IF p_dia > p_hoje THEN
    RAISE EXCEPTION 'Não se gera lista de um dia que ainda não chegou.' USING ERRCODE = 'check_violation';
  END IF;
  -- Uma geração por conta de cada vez (duas rodadas simultâneas esperam).
  PERFORM pg_advisory_xact_lock(7311, p_contaid);

  INSERT INTO public.tarefasdodia (contaid, lojaid, dia, atribuicaoid, funcionarioid, tarefaid,
                                   tipofrequencia, pontos, situacao, recuperado)
  SELECT p_contaid, c.lojaid, p_dia, c.atribuicaoid, c.funcionarioid, c.tarefaid,
         c.tipofrequencia, c.pontos, c.situacao, p_recuperado
    FROM public.lista_candidatos(p_contaid, p_dia) c
   -- A numeração das linhas (itemid) sai sempre na mesma ordem.
   ORDER BY c.lojaid, c.atribuicaoid
  ON CONFLICT (contaid, dia, atribuicaoid) DO NOTHING;
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  IF p_dia = p_hoje THEN
    UPDATE public.tarefasdodia i
       SET situacao = 'cancelada'
     WHERE i.contaid = p_contaid AND i.dia = p_dia AND i.situacao <> 'cancelada'
       AND NOT EXISTS (SELECT 1 FROM public.lista_candidatos(p_contaid, p_dia) c WHERE c.atribuicaoid = i.atribuicaoid)
       AND NOT public.item_tratado(i.atribuicaoid, i.tipofrequencia, i.dia, i.passadapara);
    GET DIAGNOSTICS v_cancelados = ROW_COUNT;

    UPDATE public.tarefasdodia i
       SET situacao = c.situacao
      FROM public.lista_candidatos(p_contaid, p_dia) c
     WHERE i.contaid = p_contaid AND i.dia = p_dia AND i.atribuicaoid = c.atribuicaoid
       AND i.situacao IS DISTINCT FROM c.situacao
       AND NOT public.item_tratado(i.atribuicaoid, i.tipofrequencia, i.dia, i.passadapara);
    GET DIAGNOSTICS v_ajustados = ROW_COUNT;
  END IF;

  INSERT INTO public.diasgerados (contaid, dia, recuperado)
  VALUES (p_contaid, p_dia, p_recuperado)
  ON CONFLICT (contaid, dia) DO NOTHING;

  RETURN jsonb_build_object(
    'dia', p_dia, 'novos', v_novos, 'cancelados', v_cancelados, 'ajustados', v_ajustados,
    'devidas',  (SELECT count(*) FROM public.tarefasdodia WHERE contaid = p_contaid AND dia = p_dia AND situacao = 'devida'),
    'folgas',   (SELECT count(*) FROM public.tarefasdodia WHERE contaid = p_contaid AND dia = p_dia
                   AND situacao IN ('folga', 'afastamento')),
    'canceladas', (SELECT count(*) FROM public.tarefasdodia WHERE contaid = p_contaid AND dia = p_dia AND situacao = 'cancelada'));
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929265700_fila_fuso_uma_vez.sql
-- ------------------------------------------------------------------------
-- A fila do dia calcula o fuso UMA vez (29/09/2026).
--
-- Medido com volume de loja real (90 dias de entregas): a fila (base do
-- Início, do Quadro, do painel, do tablet e da TV) buscava o fuso a cada
-- linha consultada e convertia o horário de TODAS as entregas de cada tarefa
-- para saber se alguma caiu no dia — o Início levava 3,1 s. Agora o fuso e o
-- dia (como intervalo de meia-noite a meia-noite) saem UMA vez, e a entrega
-- é comparada com o intervalo. O resultado é o mesmo (prova exaustiva). Parte da versão mais nova (20260929265500_desempate_nas_listas.sql).
-- Nenhum dado é alterado.

CREATE OR REPLACE FUNCTION public.fila_no_dia(p_contaid integer, p_lojaid integer, p_dia date, p_fim timestamp with time zone)
 RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- MATERIALIZED: o fuso (e o resto do contexto) sai UMA vez por leitura.
  -- Sem isso o Postgres copiava o contexto para dentro de cada subconsulta e
  -- buscava o fuso a cada linha (484 mil vezes em 3 leituras, com 90 dias de
  -- entregas: 2,2 s só nisso).
  WITH ctx AS MATERIALIZED (
    SELECT p_contaid AS conta,
           p_dia AS dia,
           public.fuso_da_conta(p_contaid) AS fuso,
           -- O dia no fuso da conta como INTERVALO (meia-noite a meia-noite):
           -- comparar o horário da entrega com ele é a mesma pergunta que
           -- "dia_no_fuso(horário) = dia", sem converter linha por linha.
           (p_dia::timestamp AT TIME ZONE coalesce(public.fuso_da_conta(p_contaid), 'America/Sao_Paulo')) AS diaini,
           ((p_dia + 1)::timestamp AT TIME ZONE coalesce(public.fuso_da_conta(p_contaid), 'America/Sao_Paulo')) AS diafim,
           -- O fim do dia (a meia-noite seguinte), ou infinity para hoje.
           p_fim AS fim,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = p_contaid AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
  )
  SELECT ta.atribuicaoid,
         CASE WHEN a.aceiteid IS NOT NULL THEN coalesce(a.novaatribuicaoid, ta.atribuicaoid) END,
         t.titulo,
         t.pontos,
         ta.tipofrequencia,
         (ta.funcionarioid IS NULL),
         ta.funcionarioid,
         a.funcionarioid,
         public.nome_curto(qp.nomecompleto),
         a.aceitoem,
         CASE
           -- Tarefa Única: entregue num dia, acabou (vale para a tarefa com
           -- dono e para qualquer cópia da compartilhada).
           WHEN ta.tipofrequencia = 'Unica' AND unica.cumprida THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.dataenvio < ctx.fim
                           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                           AND (e.dataenvio >= ctx.diaini AND e.dataenvio < ctx.diafim)) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         -- Atrasada é o que AINDA falta fazer. A Única entregue hoje, mesmo
         -- marcada para ontem, está em "Feitas hoje": não é atrasada.
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.dia
          AND NOT unica.cumprida),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_na_conta(ctx.conta, ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) = ctx.dia
                THEN ta.dataagendamento END,
           -- A hora de liberação também conta: o cronômetro de uma tarefa que
           -- abre às 18h começa às 18h, e não à meia-noite — senão ela nasceria
           -- vermelha, com 18 horas de "parada".
           lib.quando),
         (ctx.rodizio > 0 AND ta.funcionarioid IS NULL),
         now(),
         -- nome_curto(NULL) devolve texto VAZIO, nao nulo: sem este CASE a
         -- coluna vinha '' para toda tarefa sem entrega, e "sem nome" deixava
         -- de ser distinguivel de "nome vazio".
         CASE WHEN ent.funcionarioid IS NOT NULL THEN public.nome_curto(fez.nomecompleto) END,
         ent.dataenvio,
         ent.statusvalidacao,
         (lib.quando IS NULL OR lib.quando <= now()),
         lib.quando,
         ctx.dia,
         ctx.fuso
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.aceitoem < ctx.fim
                                      AND (a.revogadoem IS NULL OR a.revogadoem >= ctx.fim)
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- Única cumprida (a de tarefa_unica_ja_cumprida, no fim do dia): entregue
    -- por qualquer cópia, em qualquer dia até o fim deste.
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM public.entregas e
          JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = ctx.conta
         WHERE e.contaid = ctx.conta
           AND e.dataenvio < ctx.fim
           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
           AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)) AS cumprida
    ) unica ON true
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só do dia.
    -- A situação é a do fim do dia: recusada ou estornada DEPOIS dele, ainda
    -- estava pendente ou aprovada.
    LEFT JOIN LATERAL (
      SELECT e.funcionarioid, e.dataenvio,
             CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                  WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                  WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= ctx.fim THEN 'Pendente'
                  ELSE e.statusvalidacao END::varchar AS statusvalidacao
        FROM public.entregas e
       WHERE e.contaid = ctx.conta
         AND e.dataenvio < ctx.fim
         AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
              OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
              OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
         AND (
           (ta.tipofrequencia = 'Unica'
            AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                         WHERE c.contaid = ctx.conta AND c.atribuicaoid = e.atribuicaoid
                           AND (c.atribuicaoid = ta.atribuicaoid
                                OR c.origematribuicaoid = ta.atribuicaoid)))
           OR (e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
               AND (e.dataenvio >= ctx.diaini AND e.dataenvio < ctx.diafim))
         )
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 1
    ) ent ON true
    LEFT JOIN public.funcionarios fez  ON fez.funcionarioid = ent.funcionarioid AND fez.contaid = ctx.conta
    -- A hora de liberação, no fuso DA EMPRESA. A conversão é feita aqui, com
    -- o relógio do servidor: o tablet e o celular não opinam.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN ta.disponivelapartir IS NOT NULL
                  THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.disponivelapartir) END AS quando
    ) lib ON true
   WHERE ctx.conta IS NOT NULL
     -- Valia no fim do dia: criada antes dele e não encerrada antes dele.
     AND coalesce(ta.criadaem, '-infinity'::timestamptz) < ctx.fim
     AND (ta.datafimvigencia IS NULL OR ta.encerradaem >= ctx.fim)
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     -- tem_justificativa(..., false), no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.justificativas j
                      WHERE j.contaid = ctx.conta AND j.atribuicaoid = ta.atribuicaoid
                        AND (ta.tipofrequencia = 'Unica' OR j.dia = ctx.dia)
                        AND j.registradoem < ctx.fim
                        AND (j.status IN ('Aceita', 'Pendente')
                             OR (j.status = 'Recusada' AND j.decididoem >= ctx.fim)))
     -- passada_hoje, no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.tarefasdodia p
                      WHERE p.contaid = ctx.conta AND p.atribuicaoid = ta.atribuicaoid AND p.dia = ctx.dia
                        AND p.passadapara IS NOT NULL
                        AND coalesce(p.passadaem, '-infinity'::timestamptz) < ctx.fim)
     -- A Única entregue num dia ANTERIOR acabou: não volta na fila de hoje.
     -- Sem isto ela ficava para sempre em "Feitas hoje" (a regra de "feita"
     -- da Única vale para qualquer dia, porque ela só se faz uma vez), e
     -- ainda marcada como atrasada. A TV já tinha esta regra; a fila, não.
     AND NOT (ta.tipofrequencia = 'Unica'
              AND EXISTS (SELECT 1 FROM public.entregas e
                            JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid
                                                           AND c.contaid = ctx.conta
                           WHERE e.contaid = ctx.conta
                             AND e.dataenvio < ctx.fim
                             AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                  OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                             AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                             AND e.dataenvio < ctx.diaini))
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3, 1
$function$;

-- ------------------------------------------------------------------------
-- 20260929266000_leituras_inicio_menu.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 3, fatia 3: o Início e as bolinhas do menu por
-- loja (29/09/2026).
--
-- O master segue pelo caminho de sempre. O gerente é desviado, no começo, para
-- versões que leem só as lojas em que ele pode ver o Início (inicio.ver), e
-- cada cartão ainda pede a permissão da tela dele:
--   meta, vendas (R$) ....... metas.ver + valores.ver_rs
--   agenda .................. agenda.ver
--   solicitações ............ solicitacoes.ver
--   justificativas .......... justificativas.ver
--   comunicados, onboarding . comunicados.ver / onboarding.ver, contando só
--                             quem está INTEIRO nas lojas dele
-- O que é da conta inteira (guia de primeiros passos, conferência do livro,
-- rotina da lista) não vai para o gerente. Bolinhas do menu: cada uma conta só
-- o que ele pode abrir, nas lojas dele (regra 4).

CREATE OR REPLACE FUNCTION public.painel_inicio_gerente(p_lojaid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta     integer := public.conta_do_gerente();
  v_hoje      date;
  v_fuso      text;
  v_mes_ini   date;
  v_mes_fim   date;
  v_sem_ini   date;
  v_lojas     integer[];
  v_rs        integer[];   -- lojas com meta e R$
  v_agenda_l  integer[];
  v_solic_l   integer[];
  v_just_l    integer[];
  v_metas_l   integer[];
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje    := public.hoje_da_conta(v_conta);
  v_fuso    := public.fuso_da_conta(v_conta);
  v_mes_ini := date_trunc('month', v_hoje)::date;
  v_mes_fim := (date_trunc('month', v_hoje) + interval '1 month - 1 day')::date;
  v_sem_ini := (date_trunc('week', v_hoje) - interval '7 weeks')::date;

  SELECT coalesce(array_agg(l.lojaid ORDER BY l.lojaid), '{}') INTO v_lojas
    FROM public.lojas l
   WHERE l.contaid = v_conta AND l.ativa
     AND l.lojaid = ANY (public.lojas_onde_posso('inicio.ver'))
     AND (p_lojaid IS NULL OR l.lojaid = p_lojaid);
  IF p_lojaid IS NOT NULL AND cardinality(v_lojas) = 0 THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_rs       := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x) AND public.pode('valores.ver_rs', x));
  v_metas_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x));
  v_agenda_l := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('agenda.ver', x));
  v_solic_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('solicitacoes.ver', x));
  v_just_l   := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('justificativas.ver', x));

  -- Tarefas de hoje: a mesma fila do tablet, do Quadro e da TV.
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_de_hoje(v_conta, l.lojaid) f;

  -- Meta do dia e do mês: só nas lojas com meta e R$.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.contaid = v_conta AND a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1, v_fuso)) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.contaid = v_conta AND mp.lojaid = ANY (v_rs) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                             AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas
   WHERE cardinality(v_rs) > 0;
  v_vendas := coalesce(v_vendas, '[]'::jsonb);

  -- Pontos por semana, pelo livro, só o que foi lançado nas lojas dele.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_no_fuso(mv.datamovimento, v_fuso))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.contaid = v_conta AND mv.lojaid = ANY (v_lojas)
       AND mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE v_fuso)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês.
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_no_fuso(e.dataaprovacao, v_fuso))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
    UNION ALL
    SELECT date_trunc('week', public.dia_no_fuso(e.datarecusa, v_fuso))::date, 'r'
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_no_fuso(e.datarecusa, v_fuso) BETWEEN v_mes_ini AND v_hoje
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês nas lojas dele (pontos das entregas aprovadas ali).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint AS pontos, count(*)::bigint AS entregas
            FROM public.entregas e
            JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
           WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
             AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
           GROUP BY f.funcionarioid, f.nomecompleto
           ORDER BY 3 DESC, 2, 1
           LIMIT 5) r;

  -- Próximos agendamentos: só nas lojas em que ele vê a agenda.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid AND l.contaid = v_conta
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
       WHERE a.contaid = v_conta AND a.lojaid = ANY (v_agenda_l) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
        JOIN public.lojas l        ON l.lojaid = e.lojaid AND l.contaid = v_conta
       WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes', jsonb_build_object(
      'tarefas',      v_tarefas,
      'metadia',      v_metadia,
      'metames',      v_metames,
      'validar',      (SELECT count(*) FROM public.entregas
                        WHERE contaid = v_conta AND lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
      'agendahoje',   (SELECT count(*) FROM public.agendamentos
                        WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento <> 'Cancelado'
                          AND public.dia_no_fuso(dataevento, v_fuso) = v_hoje),
      'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                 'pessoas',     count(DISTINCT s.funcionarioid))
                         FROM public.documentosassinaturas s
                         JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                         JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                          AND public.pode_na_pessoa('comunicados.ver', v_conta, s.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                         JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE o.contaid = v_conta AND o.statusworkflow = 'Em andamento'
                          AND public.pode_na_pessoa('onboarding.ver', v_conta, o.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                        WHERE contaid = v_conta AND lojaid = ANY (v_solic_l) AND status IN ('Aberta', 'Em andamento')),
      'justificativas', (SELECT count(*) FROM public.justificativas
                          WHERE contaid = v_conta AND lojaid = ANY (v_just_l) AND status = 'Pendente')),
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    -- O guia de primeiros passos é da conta inteira: para o gerente, nada a
    -- mostrar (tudo "feito" esconde o guia).
    'guia', jsonb_build_object('loja', true, 'equipe', true, 'tarefas', true, 'meta', true, 'tv', true),
    'avisos', jsonb_build_object(
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                      WHERE l.contaid = v_conta AND l.ativa AND l.lojaid = ANY (v_metas_l)
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, v_hoje - 1, v_hoje - 1, v_fuso))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                          WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND public.pode_na_pessoa('comunicados.ver', v_conta, s.funcionarioid)
                            AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                         WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'livro', NULL),
    'rotina', NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.painel_inicio_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.painel_inicio_gerente(integer) TO authenticated;

-- painel_inicio: parte da versão viva; muda só o desvio do gerente.
CREATE OR REPLACE FUNCTION public.painel_inicio(p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje      date := public.dia_em_sao_paulo(now());
  v_mes_ini   date := date_trunc('month', public.dia_em_sao_paulo(now()))::date;
  v_mes_fim   date := (date_trunc('month', public.dia_em_sao_paulo(now())) + interval '1 month - 1 day')::date;
  v_sem_ini   date := (date_trunc('week', public.dia_em_sao_paulo(now())) - interval '7 weeks')::date;
  v_lojas     integer[];
  v_cartoes   jsonb;
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
  v_guia      jsonb;
BEGIN
  IF public.minha_conta() IS NULL THEN
    -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
    IF public.conta_do_gerente() IS NOT NULL THEN
      RETURN public.painel_inicio_gerente(p_lojaid);
    END IF;
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Lojas consideradas: a escolhida ou todas as ativas (a RLS já limita à conta).
  IF p_lojaid IS NULL THEN
    SELECT coalesce(array_agg(lojaid), '{}') INTO v_lojas FROM public.lojas WHERE ativa;
  ELSE
    SELECT array_agg(lojaid) INTO v_lojas FROM public.lojas WHERE lojaid = p_lojaid;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;

  -- Tarefas de hoje: a MESMA fila do tablet, do Quadro e da TV (29/09/2026,
  -- decisão do Wisley — a sexta vez que a mesma pergunta tinha duas
  -- respostas). Antes este cartão tinha regra própria: só tarefa com dono,
  -- contava quem estava de folga e ficava de fora a missão da equipe.
  -- fila_da_loja confere a conta de quem pede; a RLS já limitou v_lojas.
  -- A MESMA conta da TV (progresso_da_fila): a fração "concluídas" conta só
  -- as APROVADAS; o que espera o gestor fica à parte (29/09/2026).
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_da_loja(l.lojaid) f;

  -- Meta do dia: soma das lojas que têm meta hoje.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  -- Meta do mês: soma das metas do mês das lojas.
  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1,
                                                            public.meu_hoje()->>'fuso')) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.lojaid = ANY (v_lojas) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             -- Dias (por loja) do mês com meta e sem venda lançada, até ontem.
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  v_cartoes := jsonb_build_object(
    'tarefas',      v_tarefas,
    'metadia',      v_metadia,
    'metames',      v_metames,
    'validar',      (SELECT count(*) FROM public.entregas
                      WHERE lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
    'agendahoje',   (SELECT count(*) FROM public.agendamentos
                      WHERE lojaid = ANY (v_lojas) AND statusagendamento <> 'Cancelado'
                        AND public.dia_em_sao_paulo(dataevento) = v_hoje),
    'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                               'pessoas',     count(DISTINCT s.funcionarioid))
                       FROM public.documentosassinaturas s
                       JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                       JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                      WHERE s.statusassinatura = 'Pendente'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                       JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.ativo
                      WHERE o.statusworkflow = 'Em andamento'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                      WHERE lojaid = ANY (v_lojas) AND status IN ('Aberta', 'Em andamento')),
    'justificativas', (SELECT count(*) FROM public.justificativas
                        WHERE lojaid = ANY (v_lojas) AND status = 'Pendente'));

  -- Vendas do mês, dia a dia, contra a meta (soma das lojas).
  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                            AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas;

  -- Pontos por semana (últimas 8, começando na segunda), pelo livro.
  -- Entraram: aprovações e bônus, já descontados os estornos.
  -- Saíram: resgates, já descontados cancelamentos e estornos de resgate.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(mv.datamovimento))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE 'America/Sao_Paulo')
       AND (p_lojaid IS NULL OR mv.lojaid = p_lojaid)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês (pelo dia da decisão).
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.dataaprovacao))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN v_mes_ini AND v_hoje
    UNION ALL
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.datarecusa))::date, 'r'
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_em_sao_paulo(e.datarecusa) BETWEEN v_mes_ini AND v_hoje
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês (pontos aprovados no mês).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT * FROM public.ranking_pontos(v_mes_ini, v_hoje, p_lojaid) LIMIT 5) r;

  -- Próximos agendamentos: hora, tipo e responsável (sem dados do cliente).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid
       WHERE a.lojaid = ANY (v_lojas) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
        JOIN public.lojas l        ON l.lojaid = e.lojaid
       WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  -- Guia de primeiros passos (vale para a conta toda).
  v_guia := jsonb_build_object(
    'loja',    EXISTS (SELECT 1 FROM public.lojas WHERE ativa),
    'equipe',  EXISTS (SELECT 1 FROM public.funcionarios f
                         JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.ativo
                        WHERE f.ativo),
    'tarefas', EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
                         JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
                        WHERE ta.datafimvigencia IS NULL AND t.sistema IS NULL),
    'meta',    EXISTS (SELECT 1 FROM public.metasdiariasmodelos WHERE valormeta > 0)
               OR EXISTS (SELECT 1 FROM public.metasprincipais),
    'tv',      EXISTS (SELECT 1 FROM public.linkstv WHERE revogadoem IS NULL));

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes',      v_cartoes,
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    'guia',         v_guia,
    -- Avisos (calculados na hora, sem rotina).
    'avisos', jsonb_build_object(
      -- VENDA DE ONTEM NÃO LANÇADA (29/09/2026): loja ativa que tinha meta
      -- ontem (a especial da data ou o modelo do dia da semana, com valor) e
      -- não tem lançamento de ontem. Loja que não abre tem meta zero naquele
      -- dia (ou uma especial com valor 0 no feriado) e não avisa. Só ontem:
      -- não acumula. Todas as lojas que a pessoa enxerga, com ou sem filtro.
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                       CROSS JOIN LATERAL (SELECT (public.meu_hoje()->>'hoje')::date - 1 AS dia) o
                      WHERE l.ativa
                        -- A MESMA regra da faixa do mês (dias_sem_lancamento).
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, o.dia, o.dia,
                                                                               public.meu_hoje()->>'fuso'))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE lojaid = ANY (v_lojas) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                          WHERE s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND (p_lojaid IS NULL OR EXISTS (
                                  SELECT 1 FROM public.funcionarioslojas fl
                                   WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
      'livro', (SELECT CASE WHEN r.resultado = 'ok' THEN 'ok'
                            WHEN r.detalhe ? 'diferencas' THEN 'diferenca' ELSE 'erro' END
                  FROM public.rotinasexecucoes r
                 WHERE r.rotina = 'conferencia_livro'
                 ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1)),
    -- Última geração da lista de hoje (para "rodou sozinha às 00:05 ✓").
    'rotina', (SELECT jsonb_build_object('quando', coalesce(r.terminadoem, r.iniciadoem),
                                         'resultado', r.resultado, 'origem', r.origem)
                 FROM public.rotinasexecucoes r
                WHERE r.rotina = 'lista_do_dia' AND r.referencia = v_hoje
                ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1));
END;
$function$;

-- tarefas_nao_pegas: parte da versão viva; o gerente lê só as lojas dele.
CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(atribuicaoid integer, lojaid integer, loja character varying, titulo character varying, pontos integer, atribuidos text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Ramo do gerente (parte 3): sem conta de master, a conta do gerente, e só
  -- as lojas em que ele pode ver o Início.
  WITH ctx AS (SELECT coalesce(public.minha_conta(), public.conta_do_gerente()) AS conta,
                      public.hoje_da_conta(coalesce(public.minha_conta(), public.conta_do_gerente())) AS dia,
                      public.fuso_da_conta(coalesce(public.minha_conta(), public.conta_do_gerente())) AS fuso,
                      public.minha_conta() IS NULL AS gerente)
  SELECT ta.atribuicaoid, ta.lojaid, l.nome, t.titulo, t.pontos,
         coalesce((SELECT string_agg(public.nome_curto(f.nomecompleto), ', ' ORDER BY f.nomecompleto)
                     FROM public.tarefascandidatos c
                     JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = ctx.conta
                    WHERE c.contaid = ctx.conta AND c.atribuicaoid = ta.atribuicaoid),
                  'toda a equipe da loja')
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.funcionarioid IS NULL
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
   WHERE ctx.conta IS NOT NULL
     AND (NOT ctx.gerente OR ta.lojaid = ANY (public.lojas_onde_posso('inicio.ver')))
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo, ta.atribuicaoid
$function$;

-- As bolinhas do menu do gerente: cada uma conta só o que ele pode abrir,
-- nas lojas dele. Resgate sem loja não conta (é da conta inteira).
CREATE OR REPLACE FUNCTION public.contagem_do_menu_gerente()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT jsonb_build_object(
    'entregas', (SELECT count(*) FROM public.entregas e
                   JOIN public.lojas l ON l.lojaid = e.lojaid AND l.contaid = ctx.conta AND l.ativa
                  WHERE e.contaid = ctx.conta AND e.statusvalidacao = 'Pendente'
                    AND e.lojaid = ANY (public.lojas_onde_posso('quadro.ver'))),
    'resgates', (SELECT count(*) FROM public.resgates r
                  WHERE r.contaid = ctx.conta AND r.status = 'Pendente'
                    AND r.lojaid = ANY (public.lojas_onde_posso('premios.ver'))),
    'solicitacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('loja', c.loja, 'situacao', c.situacao, 'quantos', c.quantos))
                                FROM (SELECT s.lojaid AS loja, s.status::text AS situacao, count(*)::integer AS quantos
                                        FROM public.solicitacoesinternas s
                                        JOIN public.lojas l ON l.lojaid = s.lojaid AND l.contaid = ctx.conta AND l.ativa
                                       WHERE s.contaid = ctx.conta AND s.status IN ('Aberta', 'Em andamento')
                                         AND s.lojaid = ANY (public.lojas_onde_posso('solicitacoes.ver'))
                                       GROUP BY s.lojaid, s.status) c), '[]'::jsonb))
    FROM ctx
   WHERE ctx.conta IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.contagem_do_menu_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.contagem_do_menu_gerente() TO authenticated;

-- contagem_do_menu: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.contagem_do_menu()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.contagem_do_menu_gerente()
           ELSE (
  SELECT jsonb_build_object(
    -- Quadro: entregas esperando aprovação, nas lojas ativas.
    'entregas', (SELECT count(*) FROM public.entregas e
                   JOIN public.lojas l ON l.lojaid = e.lojaid AND l.ativa
                  WHERE e.statusvalidacao = 'Pendente'),
    -- Prêmios: pedidos de resgate esperando o gestor (a mesma conta de antes).
    'resgates', (SELECT count(*) FROM public.resgates r WHERE r.status = 'Pendente'),
    -- Solicitações: por loja e situação (o menu soma; as abas usam por loja).
    'solicitacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('loja', c.loja, 'situacao', c.situacao, 'quantos', c.quantos))
                                FROM public.contagem_solicitacoes() c), '[]'::jsonb))
           ) END
$function$;

-- ------------------------------------------------------------------------
-- 20260929267000_leituras_relatorios.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 3, fatia 4: Relatórios por loja (29/09/2026).
--
-- Análise de tarefas: só as lojas em que o gerente pode ver os relatórios.
-- Relatórios de UMA pessoa (histórico, pendências, tarefas pegas): só de quem
-- está INTEIRO nas lojas dele (a mesma régua das ações sobre a pessoa), e só o
-- que aconteceu nessas lojas. O master segue pelo caminho de sempre.

-- ---------------------------------------------------------------------------
-- Análise de tarefas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.analise_de_tarefas_gerente(p_de date, p_ate date, p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta, public.fuso_da_conta(public.conta_do_gerente()) AS fuso,
                      ARRAY(SELECT x FROM unnest(public.lojas_onde_posso('relatorios.ver')) x
                             WHERE p_lojaid IS NULL OR x = p_lojaid) AS lojas),
  ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM ctx JOIN public.entregas e ON e.contaid = ctx.conta AND e.lojaid = ANY (ctx.lojas)
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_no_fuso(e.dataenvio, ctx.fuso) BETWEEN p_de AND p_ate
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM ctx
      JOIN public.justificativas j     ON j.contaid = ctx.conta AND j.lojaid = ANY (ctx.lojas)
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid AND ta.contaid = ctx.conta
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo, t.tarefaid), '[]'::jsonb)
    FROM juntos j
    JOIN ctx ON true
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid AND t.contaid = ctx.conta
$$;
REVOKE ALL ON FUNCTION public.analise_de_tarefas_gerente(date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.analise_de_tarefas_gerente(date, date, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- Histórico da pessoa
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.historico_da_pessoa_gerente(p_funcionarioid integer, p_limite integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta, public.lojas_onde_posso('relatorios.ver') AS lojas)
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT e.dataenvio AS ds, e.entregaid AS id,
             jsonb_build_object('titulo', t.titulo, 'loja', l.nome, 'enviadaem', e.dataenvio,
                                'status', e.statusvalidacao, 'pontos', e.pontosganhos,
                                'motivo', coalesce(e.motivorecusa, e.motivoestorno)) AS x
        FROM ctx
        JOIN public.entregas e   ON e.contaid = ctx.conta AND e.funcionarioid = p_funcionarioid
                                AND e.lojaid = ANY (ctx.lojas)
        JOIN public.tarefas t    ON t.tarefaid = e.tarefaid AND t.contaid = ctx.conta
        LEFT JOIN public.lojas l ON l.lojaid = e.lojaid AND l.contaid = ctx.conta
       WHERE ctx.conta IS NOT NULL AND e.atribuicaoid IS NOT NULL
         AND public.pode_na_pessoa('relatorios.ver', ctx.conta, p_funcionarioid)
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 500))
    ) s
$$;
REVOKE ALL ON FUNCTION public.historico_da_pessoa_gerente(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_da_pessoa_gerente(integer, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- Pendências da pessoa (o que era devido e não foi entregue nem justificado)
-- ---------------------------------------------------------------------------
-- A mesma regra da versão de sempre, com a conta escrita em cada tabela, o dia
-- da conta (nunca o relógio de São Paulo à mão) e só as lojas dele.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa_gerente(p_funcionarioid integer, p_de date, p_ate date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta, public.fuso_da_conta(public.conta_do_gerente()) AS fuso,
                      public.lojas_onde_posso('relatorios.ver') AS lojas),
  ok AS (SELECT ctx.* FROM ctx
          WHERE ctx.conta IS NOT NULL AND public.pode_na_pessoa('relatorios.ver', ctx.conta, p_funcionarioid)),
  lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.hoje_da_conta(ok.conta) - 1) AS fim
      FROM ok
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, lim, ok
     WHERE dg.contaid = ok.conta AND dg.dia BETWEEN lim.ini AND lim.fim
  ),
  itens AS (
    SELECT i.dia, i.atribuicaoid, i.tipofrequencia, t.titulo, i.pontos, l.nome AS loja
      FROM ok
      JOIN public.tarefasdodia i ON i.contaid = ok.conta AND i.lojaid = ANY (ok.lojas)
      JOIN gerados g             ON g.dia = i.dia
      JOIN public.tarefas t      ON t.tarefaid = i.tarefaid AND t.contaid = ok.conta
      LEFT JOIN public.lojas l   ON l.lojaid = i.lojaid AND l.contaid = ok.conta
     WHERE i.funcionarioid = p_funcionarioid
       AND i.situacao = 'devida'
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.contaid = ok.conta AND e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_no_fuso(e.dataenvio, ok.fuso) = i.dia))
    UNION ALL
    SELECT g.d::date, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM ok
      JOIN public.tarefasatribuidas ta ON ta.contaid = ok.conta AND ta.lojaid = ANY (ok.lojas)
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid AND t.contaid = ok.conta
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid AND f.contaid = ok.conta
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid AND l.contaid = ok.conta
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_no_fuso(ta.dataatribuicao, ok.fuso), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date, ok.fuso)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.contaid = ok.conta AND e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_no_fuso(e.dataenvio, ok.fuso) = g.d::date)
    UNION ALL
    SELECT public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ok.fuso), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM ok
      JOIN public.tarefasatribuidas ta ON ta.contaid = ok.conta AND ta.lojaid = ANY (ok.lojas)
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid AND t.contaid = ok.conta
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid AND l.contaid = ok.conta
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ok.fuso) BETWEEN lim.ini AND lim.fim
       AND public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ok.fuso) NOT IN (SELECT dia FROM gerados)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.contaid = ok.conta AND e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo, i.atribuicaoid), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
$$;
REVOKE ALL ON FUNCTION public.pendencias_da_pessoa_gerente(integer, date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pendencias_da_pessoa_gerente(integer, date, date) TO authenticated;

-- analise_de_tarefas: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.analise_de_tarefas(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.analise_de_tarefas_gerente(p_de, p_ate, p_lojaid)
           ELSE (
  WITH ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM public.entregas e
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM public.justificativas j
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR j.lojaid = p_lojaid)
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo, t.tarefaid), '[]'::jsonb)
    FROM juntos j
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid
           ) END
$function$;

-- historico_da_pessoa: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.historico_da_pessoa(p_funcionarioid integer, p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.historico_da_pessoa_gerente(p_funcionarioid, p_limite)
           ELSE (
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT e.dataenvio AS ds, e.entregaid AS id,
             jsonb_build_object('titulo', t.titulo, 'loja', l.nome, 'enviadaem', e.dataenvio,
                                'status', e.statusvalidacao, 'pontos', e.pontosganhos,
                                'motivo', coalesce(e.motivorecusa, e.motivoestorno)) AS x
        FROM public.entregas e
        JOIN public.tarefas t    ON t.tarefaid = e.tarefaid
        LEFT JOIN public.lojas l ON l.lojaid = e.lojaid
       WHERE e.funcionarioid = p_funcionarioid AND e.atribuicaoid IS NOT NULL
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 500))
    ) s
           ) END
$function$;

-- pendencias_da_pessoa: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.pendencias_da_pessoa_gerente(p_funcionarioid, p_de, p_ate)
           ELSE (
  WITH lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.dia_em_sao_paulo(now()) - 1) AS fim
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, lim
     WHERE dg.contaid = public.minha_conta() AND dg.dia BETWEEN lim.ini AND lim.fim
  ),
  itens AS (
    -- Dias com lista congelada.
    SELECT i.dia, i.atribuicaoid, i.tipofrequencia, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN gerados g           ON g.dia = i.dia
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid
     WHERE i.funcionarioid = p_funcionarioid
       AND i.situacao = 'devida'
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = i.dia))
    UNION ALL
    -- Dias sem lista: regra do cadastro.
    SELECT g.d::date, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_em_sao_paulo(e.dataenvio) = g.d::date)
    UNION ALL
    SELECT public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN lim.ini AND lim.fim
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) NOT IN (SELECT dia FROM gerados)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo, i.atribuicaoid), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
           ) END
$function$;

-- tarefas_pegas_da_pessoa: parte da versão viva; o gerente lê só as lojas dele.
CREATE OR REPLACE FUNCTION public.tarefas_pegas_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS TABLE(dia date, titulo character varying, pontos integer, loja character varying, entregue boolean, revogadoem timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Ramo do gerente (parte 3): a conta dele, só de quem está inteiro nas lojas
  -- dele, e só as tarefas dessas lojas.
  WITH ctx AS (SELECT coalesce(public.minha_conta(), public.conta_do_gerente()) AS conta,
                      public.minha_conta() IS NULL AS gerente)
  SELECT a.dia, t.titulo, t.pontos, l.nome,
         EXISTS (SELECT 1 FROM public.entregas e
                  WHERE e.contaid = ctx.conta AND e.atribuicaoid = a.novaatribuicaoid
                    AND e.statusvalidacao IN ('Pendente', 'Aprovada')),
         a.revogadoem
    FROM ctx
    JOIN public.missoesaceites a     ON a.contaid = ctx.conta AND a.funcionarioid = p_funcionarioid
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.atribuicaoid = a.novaatribuicaoid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    LEFT JOIN public.lojas l         ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND (NOT ctx.gerente OR (public.pode_na_pessoa('relatorios.ver', ctx.conta, p_funcionarioid)
                              AND ta.lojaid = ANY (public.lojas_onde_posso('relatorios.ver'))))
     AND a.novaatribuicaoid IS NOT NULL
     AND a.dia BETWEEN p_de AND p_ate
   ORDER BY a.dia DESC, t.titulo, a.aceiteid
$function$;

-- ------------------------------------------------------------------------
-- 20260929268000_leituras_metas.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 3, fatia 5: Metas por loja (29/09/2026).
--
-- O mês da meta tem R$ em toda linha: o gerente só lê com "Metas: ver" E "Ver
-- valores em R$" naquela loja (mais restritivo; a parte 4 decide o que mostrar
-- em percentual). Sem as duas, vem vazio. O master segue pelo caminho de sempre.
-- (Tudo aqui é lido pela LOJA, que já prende a conta.)

CREATE OR REPLACE FUNCTION public.metas_do_mes_gerente(p_lojaid integer, p_mes date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ok AS (SELECT 1 WHERE public.conta_do_gerente() IS NOT NULL
                        AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)),
  lim AS (
    SELECT date_trunc('month', p_mes)::date AS ini,
           (date_trunc('month', p_mes) + interval '1 month - 1 day')::date AS fim
  ),
  dias AS (
    SELECT g::date AS d FROM lim, generate_series(lim.ini, lim.fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d AS dia,
           a.apuracaoid, a.valordia,
           coalesce(a.valormetadia, md.valormeta) AS valormeta,
           CASE WHEN a.apuracaoid IS NOT NULL THEN a.pontosmetadia ELSE md.pontospremio END AS pontos,
           coalesce(a.origemmeta, md.origem) AS origem,
           coalesce(a.descricaometa, md.descricao) AS descricao,
           (SELECT count(*) FROM public.movimentospontos mv
              JOIN public.metaspremiacoes p ON p.premiacaoid = mv.premiacaoid
             WHERE p.apuracaoid = a.apuracaoid AND p.tipo = 'dia' AND p.estornadoem IS NULL
               AND mv.tipo = 'bonus') AS premiados
      FROM dias d
      JOIN ok ON true
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = p_lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(p_lojaid, d.d) md ON true
  ),
  mes AS (
    SELECT m.metaprincipalid, m.nomemeta, m.valormetatotal, m.pontospremio,
           EXISTS (SELECT 1 FROM public.metaspremiacoes p
                    WHERE p.metaprincipalid = m.metaprincipalid AND p.tipo = 'mes' AND p.estornadoem IS NULL) AS premiado
      FROM public.metasprincipais m, lim, ok
     WHERE m.lojaid = p_lojaid AND m.datainicio = lim.ini
  )
  SELECT CASE WHEN EXISTS (SELECT 1 FROM ok) THEN jsonb_build_object(
    'mes',       (SELECT to_jsonb(mes) FROM mes),
    'vendido',   (SELECT coalesce(sum(valordia), 0) FROM linhas),
    'somametas', (SELECT coalesce(sum(valormeta), 0) FROM linhas),
    'diaslancados', (SELECT count(*) FROM linhas WHERE apuracaoid IS NOT NULL),
    'dias',      (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'dia', dia, 'apuracaoid', apuracaoid, 'vendido', valordia, 'meta', valormeta,
                    'pontos', pontos, 'origem', origem, 'descricao', descricao,
                    'bateu', valordia IS NOT NULL AND coalesce(valormeta, 0) > 0 AND valordia >= valormeta,
                    'premiados', premiados) ORDER BY dia), '[]'::jsonb) FROM linhas),
    'primeirodiaeditavel', public.primeiro_dia_editavel_meta()
  ) END
$$;
REVOKE ALL ON FUNCTION public.metas_do_mes_gerente(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_do_mes_gerente(integer, date) TO authenticated;

-- metas_do_mes: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.metas_do_mes(p_lojaid integer, p_mes date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.metas_do_mes_gerente(p_lojaid, p_mes)
           ELSE (
  WITH lim AS (
    SELECT date_trunc('month', p_mes)::date AS ini,
           (date_trunc('month', p_mes) + interval '1 month - 1 day')::date AS fim
  ),
  dias AS (
    SELECT g::date AS d FROM lim, generate_series(lim.ini, lim.fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d AS dia,
           a.apuracaoid, a.valordia,
           coalesce(a.valormetadia, md.valormeta) AS valormeta,
           CASE WHEN a.apuracaoid IS NOT NULL THEN a.pontosmetadia ELSE md.pontospremio END AS pontos,
           coalesce(a.origemmeta, md.origem) AS origem,
           coalesce(a.descricaometa, md.descricao) AS descricao,
           (SELECT count(*) FROM public.movimentospontos mv
              JOIN public.metaspremiacoes p ON p.premiacaoid = mv.premiacaoid
             WHERE p.apuracaoid = a.apuracaoid AND p.tipo = 'dia' AND p.estornadoem IS NULL
               AND mv.tipo = 'bonus') AS premiados
      FROM dias d
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = p_lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(p_lojaid, d.d) md ON true
  ),
  mes AS (
    SELECT m.metaprincipalid, m.nomemeta, m.valormetatotal, m.pontospremio,
           EXISTS (SELECT 1 FROM public.metaspremiacoes p
                    WHERE p.metaprincipalid = m.metaprincipalid AND p.tipo = 'mes' AND p.estornadoem IS NULL) AS premiado
      FROM public.metasprincipais m, lim
     WHERE m.lojaid = p_lojaid AND m.datainicio = lim.ini
  )
  SELECT jsonb_build_object(
    'mes',       (SELECT to_jsonb(mes) FROM mes),
    'vendido',   (SELECT coalesce(sum(valordia), 0) FROM linhas),
    'somametas', (SELECT coalesce(sum(valormeta), 0) FROM linhas),
    'diaslancados', (SELECT count(*) FROM linhas WHERE apuracaoid IS NOT NULL),
    'dias',      (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'dia', dia, 'apuracaoid', apuracaoid, 'vendido', valordia, 'meta', valormeta,
                    'pontos', pontos, 'origem', origem, 'descricao', descricao,
                    'bateu', valordia IS NOT NULL AND coalesce(valormeta, 0) > 0 AND valordia >= valormeta,
                    'premiados', premiados) ORDER BY dia), '[]'::jsonb) FROM linhas),
    'primeirodiaeditavel', public.primeiro_dia_editavel_meta()
  )
           ) END
$function$;

-- ------------------------------------------------------------------------
-- 20260929268500_lojas_do_gerente_uma_vez.sql
-- ------------------------------------------------------------------------
-- As lojas do gerente calculadas UMA vez por leitura (29/09/2026).
--
-- Medido com volume de loja real: nas bolinhas do menu (que entram em toda
-- tela), "em que lojas ele pode ver?" era perguntado a cada linha de entrega
-- (609 vezes numa leitura, 173 ms). Entre parênteses com SELECT, o Postgres
-- calcula a lista uma vez. O resultado é o mesmo. Partem da versão mais nova
-- (20260929266000_leituras_inicio_menu.sql). Nenhum dado é alterado.

-- contagem_do_menu_gerente: muda só o (SELECT ...) em volta das lojas.
CREATE OR REPLACE FUNCTION public.contagem_do_menu_gerente()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT jsonb_build_object(
    'entregas', (SELECT count(*) FROM public.entregas e
                   JOIN public.lojas l ON l.lojaid = e.lojaid AND l.contaid = ctx.conta AND l.ativa
                  WHERE e.contaid = ctx.conta AND e.statusvalidacao = 'Pendente'
                    AND e.lojaid = ANY ((SELECT public.lojas_onde_posso('quadro.ver'))::integer[])),
    'resgates', (SELECT count(*) FROM public.resgates r
                  WHERE r.contaid = ctx.conta AND r.status = 'Pendente'
                    AND r.lojaid = ANY ((SELECT public.lojas_onde_posso('premios.ver'))::integer[])),
    'solicitacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('loja', c.loja, 'situacao', c.situacao, 'quantos', c.quantos))
                                FROM (SELECT s.lojaid AS loja, s.status::text AS situacao, count(*)::integer AS quantos
                                        FROM public.solicitacoesinternas s
                                        JOIN public.lojas l ON l.lojaid = s.lojaid AND l.contaid = ctx.conta AND l.ativa
                                       WHERE s.contaid = ctx.conta AND s.status IN ('Aberta', 'Em andamento')
                                         AND s.lojaid = ANY ((SELECT public.lojas_onde_posso('solicitacoes.ver'))::integer[])
                                       GROUP BY s.lojaid, s.status) c), '[]'::jsonb))
    FROM ctx
   WHERE ctx.conta IS NOT NULL
$$;

-- tarefas_nao_pegas: muda só o (SELECT ...) em volta das lojas.
CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(atribuicaoid integer, lojaid integer, loja character varying, titulo character varying, pontos integer, atribuidos text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Ramo do gerente (parte 3): sem conta de master, a conta do gerente, e só
  -- as lojas em que ele pode ver o Início.
  WITH ctx AS (SELECT coalesce(public.minha_conta(), public.conta_do_gerente()) AS conta,
                      public.hoje_da_conta(coalesce(public.minha_conta(), public.conta_do_gerente())) AS dia,
                      public.fuso_da_conta(coalesce(public.minha_conta(), public.conta_do_gerente())) AS fuso,
                      public.minha_conta() IS NULL AS gerente)
  SELECT ta.atribuicaoid, ta.lojaid, l.nome, t.titulo, t.pontos,
         coalesce((SELECT string_agg(public.nome_curto(f.nomecompleto), ', ' ORDER BY f.nomecompleto)
                     FROM public.tarefascandidatos c
                     JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = ctx.conta
                    WHERE c.contaid = ctx.conta AND c.atribuicaoid = ta.atribuicaoid),
                  'toda a equipe da loja')
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.funcionarioid IS NULL
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
   WHERE ctx.conta IS NOT NULL
     AND (NOT ctx.gerente OR ta.lojaid = ANY ((SELECT public.lojas_onde_posso('inicio.ver'))::integer[]))
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo, ta.atribuicaoid
$function$;

-- painel_inicio_gerente: muda só o (SELECT ...) em volta das lojas.
CREATE OR REPLACE FUNCTION public.painel_inicio_gerente(p_lojaid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta     integer := public.conta_do_gerente();
  v_hoje      date;
  v_fuso      text;
  v_mes_ini   date;
  v_mes_fim   date;
  v_sem_ini   date;
  v_lojas     integer[];
  v_rs        integer[];   -- lojas com meta e R$
  v_agenda_l  integer[];
  v_solic_l   integer[];
  v_just_l    integer[];
  v_metas_l   integer[];
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje    := public.hoje_da_conta(v_conta);
  v_fuso    := public.fuso_da_conta(v_conta);
  v_mes_ini := date_trunc('month', v_hoje)::date;
  v_mes_fim := (date_trunc('month', v_hoje) + interval '1 month - 1 day')::date;
  v_sem_ini := (date_trunc('week', v_hoje) - interval '7 weeks')::date;

  SELECT coalesce(array_agg(l.lojaid ORDER BY l.lojaid), '{}') INTO v_lojas
    FROM public.lojas l
   WHERE l.contaid = v_conta AND l.ativa
     AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('inicio.ver'))::integer[])
     AND (p_lojaid IS NULL OR l.lojaid = p_lojaid);
  IF p_lojaid IS NOT NULL AND cardinality(v_lojas) = 0 THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_rs       := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x) AND public.pode('valores.ver_rs', x));
  v_metas_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x));
  v_agenda_l := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('agenda.ver', x));
  v_solic_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('solicitacoes.ver', x));
  v_just_l   := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('justificativas.ver', x));

  -- Tarefas de hoje: a mesma fila do tablet, do Quadro e da TV.
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_de_hoje(v_conta, l.lojaid) f;

  -- Meta do dia e do mês: só nas lojas com meta e R$.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.contaid = v_conta AND a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1, v_fuso)) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.contaid = v_conta AND mp.lojaid = ANY (v_rs) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                             AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas
   WHERE cardinality(v_rs) > 0;
  v_vendas := coalesce(v_vendas, '[]'::jsonb);

  -- Pontos por semana, pelo livro, só o que foi lançado nas lojas dele.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_no_fuso(mv.datamovimento, v_fuso))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.contaid = v_conta AND mv.lojaid = ANY (v_lojas)
       AND mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE v_fuso)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês.
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_no_fuso(e.dataaprovacao, v_fuso))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
    UNION ALL
    SELECT date_trunc('week', public.dia_no_fuso(e.datarecusa, v_fuso))::date, 'r'
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_no_fuso(e.datarecusa, v_fuso) BETWEEN v_mes_ini AND v_hoje
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês nas lojas dele (pontos das entregas aprovadas ali).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint AS pontos, count(*)::bigint AS entregas
            FROM public.entregas e
            JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
           WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
             AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
           GROUP BY f.funcionarioid, f.nomecompleto
           ORDER BY 3 DESC, 2, 1
           LIMIT 5) r;

  -- Próximos agendamentos: só nas lojas em que ele vê a agenda.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid AND l.contaid = v_conta
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
       WHERE a.contaid = v_conta AND a.lojaid = ANY (v_agenda_l) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
        JOIN public.lojas l        ON l.lojaid = e.lojaid AND l.contaid = v_conta
       WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes', jsonb_build_object(
      'tarefas',      v_tarefas,
      'metadia',      v_metadia,
      'metames',      v_metames,
      'validar',      (SELECT count(*) FROM public.entregas
                        WHERE contaid = v_conta AND lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
      'agendahoje',   (SELECT count(*) FROM public.agendamentos
                        WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento <> 'Cancelado'
                          AND public.dia_no_fuso(dataevento, v_fuso) = v_hoje),
      'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                 'pessoas',     count(DISTINCT s.funcionarioid))
                         FROM public.documentosassinaturas s
                         JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                         JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                          AND public.pode_na_pessoa('comunicados.ver', v_conta, s.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                         JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE o.contaid = v_conta AND o.statusworkflow = 'Em andamento'
                          AND public.pode_na_pessoa('onboarding.ver', v_conta, o.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                        WHERE contaid = v_conta AND lojaid = ANY (v_solic_l) AND status IN ('Aberta', 'Em andamento')),
      'justificativas', (SELECT count(*) FROM public.justificativas
                          WHERE contaid = v_conta AND lojaid = ANY (v_just_l) AND status = 'Pendente')),
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    -- O guia de primeiros passos é da conta inteira: para o gerente, nada a
    -- mostrar (tudo "feito" esconde o guia).
    'guia', jsonb_build_object('loja', true, 'equipe', true, 'tarefas', true, 'meta', true, 'tv', true),
    'avisos', jsonb_build_object(
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                      WHERE l.contaid = v_conta AND l.ativa AND l.lojaid = ANY (v_metas_l)
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, v_hoje - 1, v_hoje - 1, v_fuso))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                          WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND public.pode_na_pessoa('comunicados.ver', v_conta, s.funcionarioid)
                            AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                         WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'livro', NULL),
    'rotina', NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.painel_inicio_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.painel_inicio_gerente(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.contagem_do_menu_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.contagem_do_menu_gerente() TO authenticated;

COMMIT;
