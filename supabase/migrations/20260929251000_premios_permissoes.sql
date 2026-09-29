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

