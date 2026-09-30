-- =========================================================================
-- STGame — Jornada por loja, o gerente na jornada e no Mapa, e a recusa que diz o motivo.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-rotinas-conferidas.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo tem TRÊS migrações, nesta ordem:
--   20260929291000_recusa_diz_o_motivo.sql
--   20260929292000_jornada_por_loja.sql
--   20260929293000_mapa_do_gerente.sql
--
-- CLASSIFICAÇÃO: ACRESCENTA (cria uma tabela, uma permissão nova, uma leitura e gatilhos; salvar_jornada ganha um parâmetro OPCIONAL; o texto da recusa muda em 64 funções. Toda jornada que existe nasce com todas as lojas da conta: o site no ar continua funcionando igual)
--
-- O QUE MUDA: para o master, nada muda hoje: as jornadas que existem valem em todas as lojas. Jornada nova escolhe as lojas; o gerente com a permissão nova cria, edita e apaga jornada que caiba inteira nas lojas dele, e marca o intervalo do Mapa de quem é das lojas dele. Pessoa só se liga a jornada com uma loja em comum. A recusa diz o motivo de verdade em vez de 'Sua conta não pode alterar dados no momento'.
-- =========================================================================


BEGIN;

-- ======== 20260929291000_recusa_diz_o_motivo.sql ========
-- CLASSIFICAÇÃO: ACRESCENTA
-- (cria uma função interna e muda SÓ o texto de uma recusa em 64 funções; o
-- que elas recebem, devolvem e decidem não muda.)
--
-- A recusa diz a verdade (30/09/2026, item 7 do pedido da jornada por loja).
-- Antes, 64 funções respondiam "Sua conta não pode alterar dados no momento."
-- a quem não tinha permissão — o que parece problema passageiro e não é.
-- Agora a frase vem de UM lugar (motivo_da_recusa) e diz o motivo de verdade:
--   * sem login: "Você precisa entrar no sistema para fazer isso."
--   * conta suspensa ou cancelada: "A conta está suspensa: por enquanto nada
--     pode ser alterado..." (esse é o único caso em que "no momento" era verdade);
--   * gerente com o acesso desativado: "Seu acesso de gerente está desativado...";
--   * gerente ativo: "Esta ação não está liberada para o seu cargo.";
--   * qualquer outro acesso (tablet, colaborador): "Esta ação não está
--     liberada para o seu acesso."
-- Em cada uma das 64 funções, a única mudança é a linha da recusa: o gerador
-- confere, função por função, que tirando essa troca o texto é idêntico ao da
-- versão que vale hoje.

CREATE OR REPLACE FUNCTION public.motivo_da_recusa()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH eu AS (
    SELECT cu.contaid, cu.papel, c.status
      FROM public.contasusuarios cu JOIN public.contas c ON c.contaid = cu.contaid
     WHERE cu.userid = auth.uid()
  ), bot AS (
    SELECT c.contaid, c.status FROM public.contas c WHERE c.contaid = public.conta_do_bot()
  )
  SELECT CASE
    WHEN auth.uid() IS NULL AND NOT EXISTS (SELECT 1 FROM bot)
      THEN 'Você precisa entrar no sistema para fazer isso.'
    WHEN EXISTS (SELECT 1 FROM eu WHERE status <> 'ativa') OR EXISTS (SELECT 1 FROM bot WHERE status <> 'ativa')
      THEN 'A conta está ' || coalesce((SELECT status FROM eu), (SELECT status FROM bot))
           || ': por enquanto nada pode ser alterado. Fale com o suporte do STGame.'
    WHEN EXISTS (SELECT 1 FROM eu WHERE papel = 'gerente')
         AND NOT EXISTS (SELECT 1 FROM eu JOIN public.usuariosgerenciais ug
                          ON ug.contaid = eu.contaid AND ug.userid = auth.uid() AND ug.ativo)
      THEN 'Seu acesso de gerente está desativado. Fale com o dono da conta.'
    WHEN EXISTS (SELECT 1 FROM eu WHERE papel = 'gerente')
      THEN 'Esta ação não está liberada para o seu cargo.'
    ELSE 'Esta ação não está liberada para o seu acesso.'
  END
$$;
COMMENT ON FUNCTION public.motivo_da_recusa() IS
  'A frase da recusa, com o motivo de verdade (permissão do cargo, conta suspensa, acesso desativado). Interna: só as funções que recusam a chamam.';
REVOKE ALL ON FUNCTION public.motivo_da_recusa() FROM public, anon, authenticated;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO a FROM public.agendamentos WHERE agendamentoid = p_agendamentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN a;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.alterar_hora_da_atribuicao(p_atribuicaoid integer, p_hora time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_fb FROM public.feedbacks WHERE feedbackid = p_feedbackid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Feedback não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT (public.sou_master() OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                        WHERE fl.contaid = v_conta AND fl.funcionarioid = v_fb.funcionarioid AND fl.ativo
                                          AND public.pode('feedbacks.anular', fl.lojaid))) THEN
    RAISE EXCEPTION 'Seu cargo não permite anular feedback desta pessoa (ela precisa trabalhar em uma das suas lojas).' USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.apagar_jornada(p_jornadaid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta apaga jornada.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.apagar_meta_especial(p_metaespecialid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_loja integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT lojaid INTO v_loja FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
  -- Não existe (ou é de outra conta): como antes, não apaga nada.
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta apaga meta especial.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.aprovar_entrega(p_entregaid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_entrega public.entregas%ROWTYPE;
  v_pontos  integer;
  v_titulo  text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_entrega FROM public.entregas
   WHERE entregaid = p_entregaid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Quadro). O
  -- servidor (tablet, celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('quadro.aprovar', v_entrega.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite aprovar entregas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém aprova a PRÓPRIA entrega (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_entrega.funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém aprova a própria entrega.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_entrega.statusvalidacao <> 'Pendente' THEN
    RAISE EXCEPTION 'Só uma entrega pendente pode ser aprovada. Esta está: %.', v_entrega.statusvalidacao
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT pontos, titulo INTO v_pontos, v_titulo FROM public.tarefas
   WHERE tarefaid = v_entrega.tarefaid AND contaid = v_conta;

  UPDATE public.entregas
     SET statusvalidacao = 'Aprovada', pontosganhos = v_pontos,
         dataaprovacao = now(), aprovadopor = auth.uid()
   WHERE entregaid = p_entregaid;

  IF v_pontos <> 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, tipo, pontos, descricao, entregaid, criadopor)
    VALUES (v_conta, v_entrega.funcionarioid, v_entrega.lojaid, 'aprovacao', v_pontos,
            'Tarefa aprovada: ' || v_titulo, p_entregaid, auth.uid());
  END IF;

  PERFORM public.apos_aprovar_entrega(p_entregaid);
  RETURN v_pontos;
END;
$function$;

CREATE OR REPLACE FUNCTION public.arquivar_comunicado(p_documentoid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.ativar_conquista(p_conquistaid integer, p_ativa boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.conquistas SET ativa = coalesce(p_ativa, true) WHERE contaid = v_conta AND conquistaid = p_conquistaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conquista não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ativar_loja(p_lojaid integer, p_ativa boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta ativa ou desativa loja (mexe no limite contratado).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.lojas SET ativa = coalesce(p_ativa, true) WHERE contaid = v_conta AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ativar_premio(p_produtoid integer, p_ativo boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de prêmios.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.produtosloja SET ativo = p_ativo WHERE contaid = v_conta AND produtoid = p_produtoid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prêmio não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ativar_tarefa(p_tarefaid integer, p_ativa boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_lojas integer[];
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

CREATE OR REPLACE FUNCTION public.ativar_tipo_evento(p_tipoeventoid integer, p_ativo boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe nos tipos de evento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tiposevento SET ativo = coalesce(p_ativo, true) WHERE contaid = v_conta AND tipoeventoid = p_tipoeventoid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tipo de evento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    -- Quem não pode ver um valor não pode gravá-lo.
    IF p_valor IS NOT NULL AND NOT public.pode('valores.ver_rs', p_lojaid) THEN
      RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não grava valor.' USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.criar_loja(p_nome text, p_cidade text DEFAULT NULL::text, p_endereco text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria loja (mexe no limite contratado).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.lojas (contaid, nome, cidade, endereco)
  VALUES (v_conta, btrim(coalesce(p_nome, '')), nullif(btrim(coalesce(p_cidade, '')), ''), nullif(btrim(coalesce(p_endereco, '')), ''))
  RETURNING lojaid INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.criar_meta_especial(p_lojaid integer, p_data date, p_descricao text, p_valormeta numeric, p_pontospremio integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria meta especial.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.metasespeciais (contaid, lojaid, data, descricao, valormeta, pontospremio)
  VALUES (v_conta, p_lojaid, p_data, p_descricao, p_valormeta, p_pontospremio)
  RETURNING metaespecialid INTO v_id;
  RETURN v_id;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.editar_comunicado(p_documentoid integer, p_titulo text, p_conteudo text, p_pontos integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
  -- Ninguém gera pontos para si: dar pontos a um comunicado em que você é destinatário, não.
  IF p_pontos > 0 AND EXISTS (SELECT 1 FROM public.documentosassinaturas a
                               WHERE a.documentoid = p_documentoid AND public.e_o_proprio(v_conta, a.funcionarioid)) THEN
    RAISE EXCEPTION 'Você é destinatário deste comunicado: ele não pode valer pontos (ninguém gera pontos para si mesmo).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.documentos SET titulo = btrim(p_titulo), conteudo = btrim(p_conteudo), pontosporciencia = p_pontos
   WHERE documentoid = p_documentoid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.editar_conquista(p_conquistaid integer, p_nome text, p_descricao text, p_icone text, p_bonus integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

CREATE OR REPLACE FUNCTION public.editar_loja(p_lojaid integer, p_nome text, p_cidade text, p_endereco text, p_gestorid integer, p_responsavelagendamentosid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); l public.lojas%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

CREATE OR REPLACE FUNCTION public.encerrar_atribuicoes(p_ids integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

CREATE OR REPLACE FUNCTION public.estornar_entrega(p_entregaid integer, p_motivo text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_entrega public.entregas%ROWTYPE;
  v_titulo  text;
  v_saldo   integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo do estorno.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_entrega FROM public.entregas
   WHERE entregaid = p_entregaid AND contaid = v_conta
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Quadro). O
  -- servidor (tablet, celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('quadro.estornar', v_entrega.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite estornar entregas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém estorna a PRÓPRIA entrega (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_entrega.funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém estorna a própria entrega.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_entrega.statusvalidacao <> 'Aprovada' THEN
    RAISE EXCEPTION 'Só uma entrega aprovada pode ser estornada. Esta está: %.', v_entrega.statusvalidacao
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT titulo INTO v_titulo FROM public.tarefas WHERE tarefaid = v_entrega.tarefaid;

  UPDATE public.entregas
     SET statusvalidacao = 'Estornada', motivoestorno = btrim(p_motivo),
         dataestorno = now(), estornadopor = auth.uid()
   WHERE entregaid = p_entregaid;

  IF coalesce(v_entrega.pontosganhos, 0) <> 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, tipo, pontos, descricao, entregaid, criadopor)
    VALUES (v_conta, v_entrega.funcionarioid, v_entrega.lojaid, 'estorno_entrega', -v_entrega.pontosganhos,
            'Estorno: ' || v_titulo || ' (' || btrim(p_motivo) || ')', p_entregaid, auth.uid());
  END IF;

  SELECT saldopontos INTO v_saldo FROM public.funcionarios WHERE funcionarioid = v_entrega.funcionarioid;
  RETURN v_saldo;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exige_master_editavel()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.minha_conta_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta mexe nos documentos pessoais.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_conta;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

  -- Ninguém gera pontos para si: comunicado com pontos não inclui quem inclui.
  IF d.pontosporciencia > 0
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f) WHERE public.e_o_proprio(v_conta, x.f)) THEN
    RAISE EXCEPTION 'Comunicado com pontos não pode ter você como destinatário: ninguém gera pontos para si mesmo.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
  SELECT v_conta, p_documentoid, x.fid, now()
    FROM (SELECT DISTINCT unnest(coalesce(p_funcionarios, '{}'::integer[])) AS fid) x
  ON CONFLICT (documentoid, funcionarioid) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.iniciar_onboarding(p_funcionarioid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Metas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('metas.lancar_venda', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite lançar a venda desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Quem não pode ver um valor não pode gravá-lo.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('valores.ver_rs', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não lança venda.' USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.marcar_etapa_onboarding(p_itemid integer, p_feito boolean, p_observacao text DEFAULT NULL::text, p_documentoid integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); i public.onboardingitens%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.passar_tarefa_de_folga(p_atribuicaoid integer, p_funcionarioid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_hoje  date    := public.dia_em_sao_paulo(now());
  v_item  public.tarefasdodia%ROWTYPE;
  v_nome  text;
  v_nova  integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Garante a lista de hoje (se a rotina ainda não rodou).
  PERFORM public.lista_do_dia_gerar(v_conta, v_hoje, v_hoje, false);

  SELECT * INTO v_item FROM public.tarefasdodia
   WHERE contaid = v_conta AND dia = v_hoje AND atribuicaoid = p_atribuicaoid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa não está na lista de hoje.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Quadro). O
  -- servidor (tablet, celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('quadro.passar_folga', v_item.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite passar tarefas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_item.situacao NOT IN ('folga', 'afastamento') THEN
    RAISE EXCEPTION 'Só se passa tarefa de quem está de folga ou afastado hoje.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_item.passadapara IS NOT NULL THEN
    SELECT nomecompleto INTO v_nome FROM public.funcionarios WHERE funcionarioid = v_item.passadapara;
    RAISE EXCEPTION 'Esta tarefa já foi passada hoje para %.', v_nome USING ERRCODE = 'unique_violation';
  END IF;
  IF public.item_tratado(v_item.atribuicaoid, v_item.tipofrequencia, v_hoje, NULL) THEN
    RAISE EXCEPTION 'Esta tarefa já foi entregue ou justificada hoje.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_funcionarioid = v_item.funcionarioid OR NOT EXISTS (
       SELECT 1 FROM public.funcionarios f
         JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = v_item.lojaid
                                         AND fl.ativo AND fl.contaid = v_conta
        WHERE f.funcionarioid = p_funcionarioid AND f.contaid = v_conta AND f.ativo
          AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                     f.datafimafastamento, v_hoje)) THEN
    RAISE EXCEPTION 'Escolha alguém ativo, da mesma loja, que trabalha hoje.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        dataatribuicao, dataagendamento, origematribuicaoid)
  VALUES (v_conta, v_item.tarefaid, p_funcionarioid, v_item.lojaid, 'Unica', now(), now(), v_item.atribuicaoid)
  RETURNING atribuicaoid INTO v_nova;

  UPDATE public.tarefasdodia
     SET passadapara = p_funcionarioid, passadaatribuicaoid = v_nova, passadaem = now(), passadapor = auth.uid()
   WHERE itemid = v_item.itemid;

  RETURN v_nova;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pegar_tarefa(p_atribuicaoid integer, p_funcionarioid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_quem text;
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.hoje_da_conta(v_conta);
  m       public.tarefasatribuidas%ROWTYPE;
  v_pode  boolean;
  v_nova  integer;
  v_espera integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Pegar em nome de alguém não tem tela: por fora, só o master. O tablet e
  -- o bot chamam por dentro, pelo servidor (29/09/2026).
  IF NOT public.bot_contexto_confiavel() AND NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta faz isso por aqui.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Sem pessoa para pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND datafimvigencia IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF m.origematribuicaoid IS NOT NULL THEN
    RAISE EXCEPTION 'Esta tarefa já está no nome de alguém.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje, public.fuso_da_conta(v_conta)) THEN
    RAISE EXCEPTION 'Esta tarefa não vale para hoje.' USING ERRCODE = 'check_violation';
  END IF;
  -- Antes da hora combinada ninguém pega. A hora é a da EMPRESA, convertida
  -- aqui no banco: o tablet não opina sobre que horas são.
  IF m.disponivelapartir IS NOT NULL
     AND public.instante_na_conta(v_conta, v_hoje, m.disponivelapartir) > now() THEN
    RAISE EXCEPTION 'Esta tarefa libera às %.', to_char(m.disponivelapartir, 'HH24"h"MI')
      USING ERRCODE = 'check_violation';
  END IF;
  IF m.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(v_conta, p_atribuicaoid) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  -- QUEM PODE PEGAR: a regra mora em quem_pode_pegar (29/09/2026). A janela
  -- "quem pode aceitar" do tablet pergunta para a mesma função.
  SELECT q.pode INTO v_pode
    FROM public.quem_pode_pegar(v_conta, p_atribuicaoid, v_hoje) q
   WHERE q.funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Só quem trabalha hoje nesta loja pode pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT v_pode THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Rodízio: quem pegou a última tarefa disputada desta loja espera um pouco
  -- antes de pegar outra. Só vale para tarefa sem dono, e nunca deixa a loja
  -- parada (ver rodizio_espera).
  v_espera := public.rodizio_espera(v_conta, m.lojaid, p_funcionarioid, p_atribuicaoid);
  IF v_espera > 0 THEN
    RAISE EXCEPTION 'Você pegou a última tarefa. Esta libera para você em % min.',
      greatest(1, ceil(v_espera / 60.0)::integer) USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
  VALUES (v_conta, p_atribuicaoid, v_hoje, p_funcionarioid, public.canal_atual())
  ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  IF NOT FOUND THEN
    -- Com o NOME: no balcao, "ja foi pega" sem dizer por quem deixa a pessoa
    -- procurando o que nao existe.
    SELECT public.nome_curto(f.nomecompleto) INTO v_quem
      FROM public.missoesaceites a
      JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
     WHERE a.contaid = v_conta AND a.atribuicaoid = p_atribuicaoid AND a.dia = v_hoje
       AND a.revogadoem IS NULL;
    RAISE EXCEPTION 'Esta tarefa já foi pega hoje por %.', coalesce(v_quem, 'outra pessoa')
      USING ERRCODE = 'unique_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    RETURN p_atribuicaoid;
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        dataatribuicao, dataagendamento, origematribuicaoid)
  VALUES (v_conta, m.tarefaid, p_funcionarioid, m.lojaid, 'Unica', now(), now(), p_atribuicaoid)
  RETURNING atribuicaoid INTO v_nova;

  UPDATE public.missoesaceites SET novaatribuicaoid = v_nova
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
  RETURN v_nova;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    SELECT v_conta, v_id, fid, now() FROM public.alcance_do_comunicado(v_id) fid
     -- Com pontos, quem publica não recebe o próprio comunicado (ninguém gera pontos para si).
     WHERE v_pontos = 0 OR NOT public.e_o_proprio(v_conta, fid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas WHERE documentoid = v_id) THEN
    RAISE EXCEPTION 'Nenhum funcionário ativo recebe este comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.recusar_entrega(p_entregaid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_entrega public.entregas%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa()
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo da recusa.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_entrega FROM public.entregas
  WHERE entregaid = p_entregaid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Quadro). O
  -- servidor (tablet, celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('quadro.recusar', v_entrega.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite recusar entregas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_entrega.statusvalidacao <> 'Pendente' THEN
    RAISE EXCEPTION 'Só uma entrega pendente pode ser recusada. Esta está: %.', v_entrega.statusvalidacao
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.entregas
  SET statusvalidacao = 'Recusada',
      motivorecusa    = btrim(p_motivo),
      datarecusa      = now(),
      recusadopor     = auth.uid()
  WHERE entregaid = p_entregaid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refazer_fechamento(p_ano integer, p_mes integer, p_motivo text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  f       public.fechamentosmensais%ROWTYPE;
  v_novo  integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta refaz o fechamento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM pg_advisory_xact_lock(7312, v_conta);
  SELECT * INTO f FROM public.fechamentosmensais
   WHERE contaid = v_conta AND ano = p_ano AND mes = p_mes AND situacao <> 'substituido'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esse mês ainda não foi fechado.' USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.fechamentosmensais SET situacao = 'substituido', substituidoem = now()
   WHERE fechamentoid = f.fechamentoid;

  -- A versão nova fica na mesma situação da anterior (provisória ou definitiva).
  INSERT INTO public.fechamentosmensais (contaid, ano, mes, versao, situacao, origem, motivo, fechadopor, definitivoem)
  VALUES (v_conta, p_ano, p_mes, f.versao + 1, f.situacao, 'master', btrim(p_motivo), auth.uid(),
          CASE WHEN f.situacao = 'definitivo' THEN now() END)
  RETURNING fechamentoid INTO v_novo;
  PERFORM public.fechamento_calcular(v_conta, v_novo);

  PERFORM public.rotina_registrar(v_conta, 'fechamento_mensal', public.dia_em_sao_paulo(now()), 'manual',
    clock_timestamp(), 'ok',
    jsonb_build_object('mes', lpad(p_mes::text, 2, '0') || '/' || p_ano, 'acao', 'refeito pelo master',
                       'versao', f.versao + 1, 'fechamentoid', v_novo), NULL);
  RETURN v_novo;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.registrar_ciencia_documento(p_documentoid integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.minha_conta_editavel(); v_n integer; v_fid integer := public.funcionario_do_bot();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- O master, ou a própria pessoa dona do documento (pelo Telegram).
  IF NOT public.sou_master() AND NOT (v_fid IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.documentospessoais
        WHERE documentoid = p_documentoid AND contaid = v_conta AND funcionarioid = v_fid AND situacao = 'Ativo')) THEN
    RAISE EXCEPTION 'Só o responsável pela conta mexe nos documentos pessoais.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentospessoais
                  WHERE documentoid = p_documentoid AND contaid = v_conta AND situacao IN ('Ativo', 'Arquivado')) THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.documentospessoaisciencia
     SET status = 'Ciente', dataciencia = now(), origem = public.origem_da_acao('funcionario'), registradopor = auth.uid()
   WHERE documentoid = p_documentoid AND contaid = v_conta AND status = 'Pendente';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.registrar_entrega(p_atribuicaoid integer, p_observacao text DEFAULT NULL::text, p_pathfoto text DEFAULT NULL::text, p_aprovar boolean DEFAULT false, p_fotoidunico text DEFAULT NULL::text, p_semhorafoto boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_hoje  date    := public.hoje_da_conta(v_conta);
  v_foto  text    := nullif(btrim(coalesce(p_pathfoto, '')), '');
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa()
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_atr FROM public.tarefasatribuidas
  WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Quadro). O
  -- servidor (tablet, celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('quadro.registrar_entrega', v_atr.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite registrar entregas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém registra a PRÓPRIA entrega (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_atr.funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém registra a própria entrega.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_atr.datafimvigencia IS NOT NULL THEN
    RAISE EXCEPTION 'Esta atribuição foi encerrada.' USING ERRCODE = 'check_violation';
  END IF;

  IF v_atr.funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Atribuição sem funcionário não recebe entrega.' USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.tarefa_cai_no_dia(v_atr.tipofrequencia, v_atr.valorfrequencia, v_atr.dataagendamento, v_hoje, public.fuso_da_conta(v_conta)) THEN
    RAISE EXCEPTION 'Esta tarefa não cai hoje.' USING ERRCODE = 'check_violation';
  END IF;

  -- Unica: depois de entregue (pendente ou aprovada) em qualquer dia, acabou.
  -- Na compartilhada, vale para qualquer cópia: senão a tarefa voltava todo
  -- dia e pagava de novo.
  -- 29/09/2026: vale pelo tipo da tarefa ORIGINAL. A cópia de quem pegou uma
  -- tarefa compartilhada (ou recebeu a de quem está de folga) nasce sempre
  -- "Unica", até quando a original é diária; antes, a regra olhava o tipo da
  -- CÓPIA e, numa tarefa diária, achava a entrega de uma cópia de ONTEM: o
  -- tablet mostrava "Em andamento" (a fila olha a original) e a entrega era
  -- recusada para sempre com "já foi entregue". Na cópia de tarefa que se
  -- repete, a trava é a de sempre: uma entrega por dia.
  IF coalesce((SELECT o.tipofrequencia FROM public.tarefasatribuidas o
                WHERE o.contaid = v_conta AND o.atribuicaoid = v_atr.origematribuicaoid),
              v_atr.tipofrequencia) = 'Unica'
     AND public.tarefa_unica_ja_cumprida(v_conta, coalesce(v_atr.origematribuicaoid, p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF v_foto IS NOT NULL AND v_foto NOT LIKE v_conta || '/' || v_atr.lojaid || '/%' THEN
    RAISE EXCEPTION 'A foto precisa estar na pasta da própria loja.' USING ERRCODE = 'check_violation';
  END IF;

  -- A mesma foto não prova duas tarefas: pelo caminho e pela imagem em si.
  IF v_foto IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                     WHERE e.contaid = v_conta AND e.pathfotoevidencia = v_foto) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;
  IF p_fotoidunico IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                            WHERE e.contaid = v_conta AND e.fotoidunico = p_fotoidunico) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Entregar vale como aceite (tarefa com dono; a cópia da compartilhada já
  -- nasceu de um aceite).
  IF v_atr.origematribuicaoid IS NULL THEN
    INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
    VALUES (v_conta, p_atribuicaoid, v_hoje, v_atr.funcionarioid, public.canal_atual())
    ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  END IF;

  BEGIN
    INSERT INTO public.entregas (
      contaid, tarefaid, funcionarioid, lojaid, atribuicaoid,
      dataenvio, pathfotoevidencia, observacao, statusvalidacao,
      fotoidunico, semhorafoto, registradopor
    ) VALUES (
      v_conta, v_atr.tarefaid, v_atr.funcionarioid, v_atr.lojaid, p_atribuicaoid,
      now(), v_foto, nullif(btrim(coalesce(p_observacao, '')), ''), 'Pendente',
      nullif(btrim(coalesce(p_fotoidunico, '')), ''), coalesce(p_semhorafoto, false), auth.uid()
    )
    RETURNING entregaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Já existe uma entrega desta atribuição hoje, pendente ou aprovada.'
      USING ERRCODE = 'unique_violation';
  END;

  IF p_aprovar THEN
    PERFORM public.aprovar_entrega(v_id);
  END IF;

  RETURN v_id;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT (public.sou_master() OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                        WHERE fl.contaid = v_conta AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                                          AND public.pode('feedbacks.registrar', fl.lojaid))) THEN
    RAISE EXCEPTION 'Seu cargo não permite dar feedback a esta pessoa (ela precisa trabalhar em uma das suas lojas).' USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Quem não pode ver um valor não pode gravá-lo (antes de qualquer outra
  -- conta, para a mensagem ser a certa).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('valores.ver_rs', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não registra abate em comanda.' USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.remover_anexo_agendamento(p_anexoid integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); x public.agendamentosanexos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.revogar_aceite(p_atribuicaoid integer, p_dia date, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_motivo text    := nullif(btrim(coalesce(p_motivo, '')), '');
  a        public.missoesaceites%ROWTYPE;
  v_alvo   integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_motivo IS NULL THEN
    RAISE EXCEPTION 'Diga o motivo da revogação.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO a FROM public.missoesaceites
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = p_dia AND revogadoem IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há aceite ativo para revogar.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Quadro). O
  -- servidor (tablet, celular, bot) já conferiu quem é e não passa por aqui.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('quadro.revogar_aceite', (SELECT ta.lojaid FROM public.tarefasatribuidas ta WHERE ta.contaid = v_conta AND ta.atribuicaoid = p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Seu cargo não permite revogar aceites nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_alvo := coalesce(a.novaatribuicaoid, a.atribuicaoid);

  -- Tranca a atribuição em que a entrega entraria, ANTES de conferir. Sem
  -- isto, uma entrega no mesmo instante passava pela conferência.
  PERFORM 1 FROM public.tarefasatribuidas
   WHERE contaid = v_conta AND atribuicaoid = v_alvo FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.entregas e
              WHERE e.contaid = v_conta AND e.atribuicaoid = v_alvo
                AND e.statusvalidacao IN ('Pendente', 'Aprovada')) THEN
    RAISE EXCEPTION 'Já existe entrega desta tarefa. Recuse a entrega antes de revogar o aceite.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.missoesaceites
     SET revogadoem = now(), revogadopor = auth.uid(), motivorevogacao = v_motivo
   WHERE aceiteid = a.aceiteid;

  IF a.novaatribuicaoid IS NOT NULL THEN
    UPDATE public.tarefasatribuidas SET datafimvigencia = p_dia
     WHERE contaid = v_conta AND atribuicaoid = a.novaatribuicaoid;
  END IF;
END;
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.rodar_geracao_hoje()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.minha_conta_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta roda a rotina.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN public.rotina_lista_do_dia(v_conta, now(), 'manual');
END;
$function$;

CREATE OR REPLACE FUNCTION public.salvar_etapa_onboarding(p_etapaid integer, p_nome text DEFAULT NULL::text, p_ordem integer DEFAULT NULL::integer, p_ativo boolean DEFAULT NULL::boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Metas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria e muda a meta do mês.' USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.salvar_metas_da_semana(p_lojaid integer, p_linhas jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria e muda as metas da semana.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.metasdiariasmodelos (contaid, lojaid, diasemanaid, nomedia, valormeta, pontospremio)
  SELECT v_conta, p_lojaid, (l->>'diasemanaid')::integer, l->>'nomedia', (l->>'valormeta')::numeric, (l->>'pontospremio')::integer
    FROM jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) l
  ON CONFLICT (lojaid, diasemanaid) DO UPDATE
     SET nomedia = EXCLUDED.nomedia, valormeta = EXCLUDED.valormeta, pontospremio = EXCLUDED.pontospremio;
END;
$function$;

CREATE OR REPLACE FUNCTION public.salvar_pessoa(p_funcionarioid integer, p_nomecompleto text, p_cpf text, p_cargo text, p_setor text, p_telefone text, p_diadefolga integer, p_lojas integer[], p_validador integer[] DEFAULT '{}'::integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_lojas  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_lojas, '{}'::integer[])) x ORDER BY 1);
  v_valid  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_validador, '{}'::integer[])) x
                               WHERE x = ANY (coalesce(p_lojas, '{}'::integer[])) ORDER BY 1);
  f        public.funcionarios%ROWTYPE;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
      -- Lojas: trocar as lojas é CADASTRO: a pessoa inteira nas lojas dele
      -- (decisão 4); e só as lojas dele mudam; quem valida, só o master.
      IF EXISTS (
           SELECT 1
             FROM (SELECT l FROM unnest(v_lojas) l
                   UNION SELECT lojaid FROM public.funcionarioslojas WHERE funcionarioid = v_id AND ativo) u(l)
             LEFT JOIN public.funcionarioslojas fl ON fl.funcionarioid = v_id AND fl.lojaid = u.l
            WHERE coalesce(fl.ativo, false) IS DISTINCT FROM (u.l = ANY (v_lojas)))
         AND NOT public.pode_na_pessoa('equipe.editar', v_conta, v_id) THEN
        RAISE EXCEPTION 'Esta pessoa trabalha também em loja fora das suas: só o dono da conta troca as lojas dela.'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.salvar_premio(p_nome text, p_custoempontos integer, p_produtoid integer DEFAULT NULL::integer, p_descricao text DEFAULT NULL::text, p_estoquedisponivel integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.salvar_tarefa(p_titulo text, p_pontos integer, p_lojas integer[], p_tarefaid integer DEFAULT NULL::integer, p_descricao text DEFAULT NULL::text, p_setor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_lojas integer[] := coalesce(p_lojas, ARRAY[]::integer[]);
  v_antes integer[];
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

CREATE OR REPLACE FUNCTION public.salvar_tipo_evento(p_nome text, p_tipoeventoid integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
$function$;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

CREATE OR REPLACE FUNCTION public.vincular_jornada(p_funcionarios integer[], p_jornadaid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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

-- ======== 20260929292000_jornada_por_loja.sql ========
-- CLASSIFICAÇÃO: ACRESCENTA
-- (cria uma tabela, uma permissão nova, uma leitura e três gatilhos; salvar_jornada
-- ganha um parâmetro OPCIONAL, as lojas: chamada sem ele, como a do site no ar,
-- faz o que fazia. Toda jornada que já existe nasce com TODAS as lojas da conta,
-- então nada muda para ninguém hoje.)
--
-- Jornada por loja (30/09/2026, decisões do Wisley):
-- 1. A jornada ganha a lista de lojas em que vale (jornadaslojas), como o
--    catálogo de tarefas. O master marca as que quiser; o gerente, só as dele.
-- 2. Permissão nova "Jornada: criar, editar e apagar" (jornada.editar), que
--    nasce negada para todo cargo. O gerente só mexe em jornada cujo alcance
--    cabe INTEIRO nas lojas em que ele tem a permissão — nem o nome, nem um
--    horário, se ela vale também para loja de fora. Apagar: o mesmo, e só sem
--    ninguém vinculado.
-- 3. Pessoa só se vincula a jornada com pelo menos UMA loja em comum. Quem
--    decide é o banco: o gatilho recusa por qualquer caminho, até direto na
--    tabela. E tirar a pessoa da única loja em comum (mantendo-a em outras)
--    também é recusado: o vínculo não fica apontando para uma jornada que não
--    vale para ela.
-- 4. Não se tira uma loja da jornada enquanto houver pessoa daquela loja
--    vinculada a ela: a mensagem diz quantas e de qual loja.
-- 6. As jornadas que já existem: TODAS as lojas da conta (ativas ou não). Com
--    isso elas continuam só do master (o alcance não cabe nas lojas de nenhum
--    gerente). A loja criada DEPOIS não entra sozinha em jornada nenhuma: o
--    master a marca na jornada (a opção mais restritiva).

-- ---------------------------------------------------------------------------
-- 1. As lojas de cada jornada
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.jornadaslojas (
  contaid   integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid),
  jornadaid integer NOT NULL,
  lojaid    integer NOT NULL,
  CONSTRAINT jornadaslojas_pkey PRIMARY KEY (contaid, jornadaid, lojaid),
  CONSTRAINT jornadaslojas_jornada_fk FOREIGN KEY (contaid, jornadaid)
    REFERENCES public.jornadas (contaid, jornadaid) ON DELETE CASCADE,
  CONSTRAINT jornadaslojas_loja_fk FOREIGN KEY (contaid, lojaid)
    REFERENCES public.lojas (contaid, lojaid)
);
COMMENT ON TABLE public.jornadaslojas IS
  'Em que lojas cada jornada vale (30/09/2026). Pessoa só se vincula a jornada com uma loja em comum; loja com gente vinculada não sai da jornada. Grava só pela salvar_jornada.';
CREATE INDEX IF NOT EXISTS jornadaslojas_loja_idx ON public.jornadaslojas (contaid, lojaid);
ALTER TABLE public.jornadaslojas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.jornadaslojas FROM anon, authenticated;
GRANT SELECT ON public.jornadaslojas TO authenticated;
GRANT ALL ON public.jornadaslojas TO service_role;
DROP POLICY IF EXISTS jornadaslojas_sel ON public.jornadaslojas;
CREATE POLICY jornadaslojas_sel ON public.jornadaslojas FOR SELECT TO authenticated
  USING (contaid = (SELECT public.minha_conta()));

-- As jornadas que já existem: todas as lojas da conta. Rodar de novo não duplica.
INSERT INTO public.jornadaslojas (contaid, jornadaid, lojaid)
SELECT j.contaid, j.jornadaid, l.lojaid
  FROM public.jornadas j JOIN public.lojas l ON l.contaid = j.contaid
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Os gatilhos: o banco garante a loja em comum, por qualquer caminho
-- ---------------------------------------------------------------------------
-- A pessoa ativa só aponta para jornada com loja em comum. (Tirar a pessoa de
-- TODAS as lojas — saída da empresa — não é barrado aqui.)
CREATE OR REPLACE FUNCTION public.jornada_serve_a_pessoa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_contaid integer; v_func integer; v_jornada integer; v_nome text; v_jnome text;
BEGIN
  IF TG_TABLE_NAME = 'funcionarios' THEN
    IF NEW.jornadaid IS NULL OR NOT NEW.ativo THEN RETURN NEW; END IF;
    v_contaid := NEW.contaid; v_func := NEW.funcionarioid; v_jornada := NEW.jornadaid; v_nome := NEW.nomecompleto;
  ELSE
    -- funcionarioslojas: a pessoa saiu (ou foi desligada) de uma loja.
    SELECT f.contaid, f.funcionarioid, f.jornadaid, f.nomecompleto INTO v_contaid, v_func, v_jornada, v_nome
      FROM public.funcionarios f
     WHERE f.contaid = OLD.contaid AND f.funcionarioid = OLD.funcionarioid AND f.ativo AND f.jornadaid IS NOT NULL;
    IF v_jornada IS NULL THEN RETURN NULL; END IF;
  END IF;
  -- Jornada que não é da conta da pessoa: quem recusa é a chave estrangeira
  -- (funcionarios_jornada_fk), como sempre foi.
  IF NOT EXISTS (SELECT 1 FROM public.jornadas j WHERE j.contaid = v_contaid AND j.jornadaid = v_jornada) THEN
    RETURN CASE WHEN TG_TABLE_NAME = 'funcionarios' THEN NEW END;
  END IF;
  -- Saindo de TODAS as lojas (saída da empresa): o desligamento passa. Mas
  -- vincular pessoa sem loja nenhuma, não (não há loja em comum).
  IF TG_TABLE_NAME <> 'funcionarios' AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = v_contaid AND fl.funcionarioid = v_func AND fl.ativo) THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                   JOIN public.jornadaslojas jl ON jl.contaid = fl.contaid AND jl.lojaid = fl.lojaid AND jl.jornadaid = v_jornada
                  WHERE fl.contaid = v_contaid AND fl.funcionarioid = v_func AND fl.ativo) THEN
    SELECT j.nome INTO v_jnome FROM public.jornadas j WHERE j.contaid = v_contaid AND j.jornadaid = v_jornada;
    IF TG_TABLE_NAME = 'funcionarios' THEN
      RAISE EXCEPTION 'A jornada "%" não vale para nenhuma loja de %. Escolha uma jornada de uma das lojas dessa pessoa.', v_jnome, v_nome
        USING ERRCODE = 'check_violation';
    END IF;
    RAISE EXCEPTION '% está na jornada "%", que não vale para nenhuma das outras lojas dessa pessoa. Mude a jornada dela antes (ou marque a loja na jornada).', v_nome, v_jnome
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN CASE WHEN TG_TABLE_NAME = 'funcionarios' THEN NEW END;
END;
$$;
REVOKE ALL ON FUNCTION public.jornada_serve_a_pessoa() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS funcionarios_jornada_na_loja ON public.funcionarios;
CREATE TRIGGER funcionarios_jornada_na_loja BEFORE INSERT OR UPDATE OF jornadaid ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.jornada_serve_a_pessoa();
DROP TRIGGER IF EXISTS funcionarioslojas_jornada_na_loja ON public.funcionarioslojas;
CREATE TRIGGER funcionarioslojas_jornada_na_loja AFTER UPDATE OF ativo OR DELETE ON public.funcionarioslojas
  FOR EACH ROW EXECUTE FUNCTION public.jornada_serve_a_pessoa();

-- Loja com gente vinculada não sai da jornada (a jornada apagada leva as
-- lojas junto: ela só se apaga sem ninguém, então nada é barrado aí).
CREATE OR REPLACE FUNCTION public.loja_sai_da_jornada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_n integer; v_loja text;
BEGIN
  SELECT count(*) INTO v_n
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
   WHERE f.contaid = OLD.contaid AND f.jornadaid = OLD.jornadaid AND f.ativo AND fl.lojaid = OLD.lojaid;
  IF v_n > 0 THEN
    SELECT l.nome INTO v_loja FROM public.lojas l WHERE l.contaid = OLD.contaid AND l.lojaid = OLD.lojaid;
    RAISE EXCEPTION 'Não dá para tirar a loja % desta jornada: % pessoa(s) dessa loja estão vinculadas a ela. Mude a jornada dessas pessoas em Equipe antes.', v_loja, v_n
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.loja_sai_da_jornada() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS jornadaslojas_loja_com_gente ON public.jornadaslojas;
CREATE TRIGGER jornadaslojas_loja_com_gente BEFORE DELETE ON public.jornadaslojas
  FOR EACH ROW EXECUTE FUNCTION public.loja_sai_da_jornada();

-- ---------------------------------------------------------------------------
-- 3. A permissão nova (nasce negada para todo cargo). Parte da versão viva.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.catalogo_de_permissoes()
 RETURNS TABLE(codigo text, tela text, nome text, ordem integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT v.codigo, v.tela, v.nome, v.ordem FROM (VALUES
    ('inicio.ver',                'Início',          'Ver',                                   10),
    ('painel.ver',                'Painel da loja',  'Ver',                                   20),
    ('quadro.ver',                'Quadro',          'Ver',                                   30),
    ('quadro.registrar_entrega',  'Quadro',          'Registrar entrega',                     31),
    ('quadro.aprovar',            'Quadro',          'Aprovar',                               32),
    ('quadro.recusar',            'Quadro',          'Recusar',                               33),
    ('quadro.estornar',           'Quadro',          'Estornar entrega aprovada',             34),
    ('quadro.revogar_aceite',     'Quadro',          'Revogar aceite',                        35),
    ('quadro.passar_folga',       'Quadro',          'Passar tarefa de quem está de folga',   36),
    ('tarefas.ver',               'Tarefas',         'Ver',                                   40),
    ('tarefas.atribuir',          'Tarefas',         'Atribuir',                              41),
    ('tarefas.encerrar_atribuicao','Tarefas',        'Encerrar atribuição',                   42),
    ('tarefas.catalogo',          'Tarefas',         'Editar catálogo (criar, editar, desativar)', 43),
    ('solicitacoes.ver',          'Solicitações',    'Ver',                                   50),
    ('solicitacoes.abrir',        'Solicitações',    'Abrir',                                 51),
    ('solicitacoes.concluir',     'Solicitações',    'Concluir',                              52),
    ('solicitacoes.recusar',      'Solicitações',    'Recusar',                               53),
    ('relatorios.ver',            'Relatórios',      'Ver',                                   60),
    ('equipe.ver',                'Equipe',          'Ver',                                   70),
    ('equipe.criar',              'Equipe',          'Criar pessoa',                          71),
    ('equipe.editar',             'Equipe',          'Editar',                                72),
    ('equipe.desativar',          'Equipe',          'Desativar e reativar',                  73),
    ('equipe.criar_acesso',       'Equipe',          'Criar acesso',                          74),
    ('equipe.redefinir_acesso',   'Equipe',          'Redefinir acesso',                      75),
    ('equipe.liberar_pin',        'Equipe',          'Liberar PIN',                           76),
    ('jornada.ver',               'Jornada',         'Ver',                                   80),
    ('jornada.vincular',          'Jornada',         'Ligar pessoa a uma jornada',            81),
    ('jornada.mapa',              'Jornada',         'Mapa e exportar',                       82),
    ('jornada.editar',            'Jornada',         'Criar, editar e apagar jornada',        83),
    ('feedbacks.ver',             'Feedbacks',       'Ver',                                   90),
    ('feedbacks.registrar',       'Feedbacks',       'Registrar',                             91),
    ('feedbacks.anular',          'Feedbacks',       'Anular',                                92),
    ('justificativas.ver',        'Justificativas',  'Ver',                                  100),
    ('justificativas.registrar',  'Justificativas',  'Registrar',                            101),
    ('justificativas.decidir',    'Justificativas',  'Aceitar e recusar',                    102),
    ('ranking.ver',               'Ranking',         'Ver',                                  110),
    ('conquistas.ver',            'Conquistas',      'Ver',                                  111),
    ('extrato.ver',               'Extrato',         'Ver',                                  112),
    ('premios.ver',               'Prêmios',         'Ver',                                  120),
    ('premios.registrar',         'Prêmios',         'Registrar resgate',                    121),
    ('premios.entregar',          'Prêmios',         'Aprovar (entregar) resgate',           122),
    ('premios.cancelar',          'Prêmios',         'Cancelar resgate',                     123),
    ('premios.estornar',          'Prêmios',         'Estornar resgate',                     124),
    ('metas.ver',                 'Metas',           'Ver',                                  130),
    ('metas.lancar_venda',        'Metas',           'Lançar venda',                         131),
    ('agenda.ver',                'Agenda',          'Ver',                                  140),
    ('agenda.editar',             'Agenda',          'Criar e editar',                       141),
    ('agenda.realizado',          'Agenda',          'Marcar realizado',                     142),
    ('agenda.pagamento',          'Agenda',          'Pagamento',                            143),
    ('comunicados.ver',           'Comunicados',     'Ver',                                  150),
    ('comunicados.publicar',      'Comunicados',     'Publicar',                             151),
    ('onboarding.ver',            'Onboarding',      'Ver',                                  160),
    ('onboarding.conduzir',       'Onboarding',      'Conduzir',                             161),
    ('lojas.ver',                 'Lojas',           'Ver',                                  170),
    ('lojas.editar',              'Lojas',           'Editar',                               171),
    ('lojas.tv',                  'Lojas',           'Configurar TV',                        172),
    ('lojas.tablet_som',          'Lojas',           'Som do tablet',                        173),
    ('lojas.tablet_acesso',       'Lojas',           'Senha do tablet',                      174),
    ('valores.ver_rs',            'Todas as telas',  'Ver valores em R$',                    180)
  ) AS v(codigo, tela, nome, ordem)
$function$;

-- ---------------------------------------------------------------------------
-- 4. Criar e editar: o master em qualquer loja da conta; o gerente só com a
--    jornada INTEIRA nas lojas em que ele pode editar jornada
-- ---------------------------------------------------------------------------
-- A versão anterior (7 parâmetros) sai: esta aceita a mesma chamada, e as
-- lojas são opcionais (sem elas: jornada nova = todas as lojas da conta, só
-- para o master; jornada que existe = as lojas não mudam).
DROP FUNCTION IF EXISTS public.salvar_jornada(integer, text, jsonb, time, time, text, boolean);
CREATE OR REPLACE FUNCTION public.salvar_jornada(p_jornadaid integer, p_nome text, p_dias jsonb,
                                                 p_pausainicio time, p_pausafim time, p_observacao text,
                                                 p_ativa boolean, p_lojas integer[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
  v_id     integer;
  v_lojas  integer[];
  v_antes  integer[];
  v_falta  text;
  d        jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_master AND cardinality((SELECT public.lojas_onde_posso('jornada.editar'))::integer[]) = 0 THEN
    RAISE EXCEPTION 'Criar e editar jornada não está liberado para o seu cargo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF btrim(coalesce(p_nome, '')) = '' THEN
    RAISE EXCEPTION 'Dê um nome à jornada.' USING ERRCODE = 'check_violation';
  END IF;
  IF jsonb_typeof(p_dias) IS DISTINCT FROM 'array' OR jsonb_array_length(p_dias) = 0 THEN
    RAISE EXCEPTION 'Preencha a entrada e a saída de pelo menos um dia.' USING ERRCODE = 'check_violation';
  END IF;
  IF (p_pausainicio IS NULL) <> (p_pausafim IS NULL) THEN
    RAISE EXCEPTION 'O intervalo precisa de começo e fim (ou fica sem intervalo).' USING ERRCODE = 'check_violation';
  END IF;

  -- As lojas pedidas: da conta, pelo menos uma; o gerente, só as dele.
  IF p_lojas IS NOT NULL THEN
    SELECT array_agg(DISTINCT x ORDER BY x) INTO v_lojas FROM unnest(p_lojas) x WHERE x IS NOT NULL;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Marque pelo menos uma loja em que a jornada vale.' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_lojas) x
                WHERE NOT EXISTS (SELECT 1 FROM public.lojas l WHERE l.contaid = v_conta AND l.lojaid = x)) THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    IF NOT v_master AND EXISTS (SELECT 1 FROM unnest(v_lojas) x WHERE NOT public.pode('jornada.editar', x)) THEN
      RAISE EXCEPTION 'Você só pode marcar as lojas em que o seu cargo cria e edita jornada.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF p_jornadaid IS NULL THEN
    IF v_lojas IS NULL THEN
      IF NOT v_master THEN
        RAISE EXCEPTION 'Marque as lojas em que a jornada vale.' USING ERRCODE = 'check_violation';
      END IF;
      SELECT array_agg(l.lojaid ORDER BY l.lojaid) INTO v_lojas FROM public.lojas l WHERE l.contaid = v_conta;
    END IF;
    INSERT INTO public.jornadas (contaid, nome, pausainicio, pausafim, observacao, ativa)
    VALUES (v_conta, btrim(p_nome), p_pausainicio, p_pausafim, nullif(btrim(coalesce(p_observacao, '')), ''),
            coalesce(p_ativa, true))
    RETURNING jornadaid INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid) THEN
      RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    SELECT array_agg(jl.lojaid ORDER BY jl.lojaid) INTO v_antes
      FROM public.jornadaslojas jl WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid;
    -- O gerente só mexe se a jornada INTEIRA couber nas lojas dele (nem o nome).
    IF NOT v_master AND (v_antes IS NULL OR EXISTS (SELECT 1 FROM unnest(v_antes) x WHERE NOT public.pode('jornada.editar', x))) THEN
      RAISE EXCEPTION 'Esta jornada vale também para lojas que não são suas: só quem cuida de todas elas pode alterá-la.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Tirar loja com gente vinculada dela: a mensagem diz quantas e de qual.
    IF v_lojas IS NOT NULL THEN
      SELECT string_agg(l.nome || ' (' || x.n || ' pessoa' || CASE WHEN x.n = 1 THEN '' ELSE 's' END || ')', ', ' ORDER BY l.nome)
        INTO v_falta
        FROM (SELECT fl.lojaid, count(DISTINCT f.funcionarioid) AS n
                FROM public.funcionarios f
                JOIN public.funcionarioslojas fl ON fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
               WHERE f.contaid = v_conta AND f.jornadaid = p_jornadaid AND f.ativo
                 AND fl.lojaid = ANY (coalesce(v_antes, '{}'::integer[])) AND NOT fl.lojaid = ANY (v_lojas)
               GROUP BY fl.lojaid) x
        JOIN public.lojas l ON l.contaid = v_conta AND l.lojaid = x.lojaid;
      IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Não dá para tirar da jornada a(s) loja(s) %: há gente dessa(s) loja(s) vinculada a ela. Mude a jornada dessas pessoas em Equipe antes.', v_falta
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    UPDATE public.jornadas
       SET nome = btrim(p_nome), pausainicio = p_pausainicio, pausafim = p_pausafim,
           observacao = nullif(btrim(coalesce(p_observacao, '')), ''), ativa = coalesce(p_ativa, true)
     WHERE contaid = v_conta AND jornadaid = p_jornadaid
    RETURNING jornadaid INTO v_id;
    DELETE FROM public.jornadasdias WHERE contaid = v_conta AND jornadaid = v_id;
  END IF;

  FOR d IN SELECT * FROM jsonb_array_elements(p_dias) LOOP
    IF (d->>'dia')::integer NOT BETWEEN 1 AND 7 THEN
      RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
    END IF;
    IF (d->>'entrada')::time = (d->>'saida')::time THEN
      RAISE EXCEPTION 'Entrada e saída iguais no mesmo dia.' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO public.jornadasdias (contaid, jornadaid, diasemana, entrada, saida)
    VALUES (v_conta, v_id, (d->>'dia')::smallint, (d->>'entrada')::time, (d->>'saida')::time);
  END LOOP;

  -- As lojas: só quando vieram (sem elas, numa edição, ficam como estão).
  IF v_lojas IS NOT NULL THEN
    DELETE FROM public.jornadaslojas
     WHERE contaid = v_conta AND jornadaid = v_id AND NOT lojaid = ANY (v_lojas);
    INSERT INTO public.jornadaslojas (contaid, jornadaid, lojaid)
    SELECT v_conta, v_id, x FROM unnest(v_lojas) x
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Já existe uma jornada com esse nome (ou o mesmo dia apareceu duas vezes).' USING ERRCODE = 'unique_violation';
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_jornada(integer, text, jsonb, time, time, text, boolean, integer[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.salvar_jornada(integer, text, jsonb, time, time, text, boolean, integer[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Apagar: o master; o gerente com a jornada INTEIRA nas lojas dele. E
--    ninguém apaga jornada com gente vinculada.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apagar_jornada(p_jornadaid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
  v_nome   text;
  v_n      integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_master AND cardinality((SELECT public.lojas_onde_posso('jornada.editar'))::integer[]) = 0 THEN
    RAISE EXCEPTION 'Apagar jornada não está liberado para o seu cargo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT j.nome INTO v_nome FROM public.jornadas j WHERE j.contaid = v_conta AND j.jornadaid = p_jornadaid;
  IF v_nome IS NULL THEN
    RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT v_master THEN
    IF NOT EXISTS (SELECT 1 FROM public.jornadaslojas jl WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid)
       OR EXISTS (SELECT 1 FROM public.jornadaslojas jl
                   WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid AND NOT public.pode('jornada.editar', jl.lojaid)) THEN
      RAISE EXCEPTION 'Esta jornada vale também para lojas que não são suas: só quem cuida de todas elas pode apagá-la.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  SELECT count(*) INTO v_n FROM public.funcionarios WHERE contaid = v_conta AND jornadaid = p_jornadaid;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'A jornada "%" tem % pessoa(s) vinculada(s). Mova essas pessoas para outra jornada (ou "sem jornada") antes de apagar.', v_nome, v_n
      USING ERRCODE = 'foreign_key_violation';   -- o mesmo texto e codigo de antes (protege_jornada_em_uso)
  END IF;
  DELETE FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Vincular: só com loja em comum. Parte da versão viva.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vincular_jornada(p_funcionarios integer[], p_jornadaid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_n integer; v_fora text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
  -- Só jornada com pelo menos UMA loja em comum com cada pessoa (30/09/2026).
  -- O gatilho de funcionarios garante o mesmo por qualquer caminho; aqui a
  -- mensagem diz quem.
  IF p_jornadaid IS NOT NULL THEN
    SELECT string_agg(f.nomecompleto, ', ' ORDER BY f.nomecompleto) INTO v_fora
      FROM public.funcionarios f
     WHERE f.contaid = v_conta AND f.funcionarioid = ANY (p_funcionarios) AND f.ativo
       AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                         JOIN public.jornadaslojas jl ON jl.contaid = fl.contaid AND jl.lojaid = fl.lojaid AND jl.jornadaid = p_jornadaid
                        WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo);
    IF v_fora IS NOT NULL THEN
      RAISE EXCEPTION 'Esta jornada não vale para nenhuma loja de: %. Escolha uma jornada das lojas dessa(s) pessoa(s).', v_fora
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  UPDATE public.funcionarios SET jornadaid = p_jornadaid
   WHERE contaid = v_conta AND funcionarioid = ANY (p_funcionarios) AND ativo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. As leituras: a lista de jornadas (com as lojas e se o gerente pode editar)
--    e as jornadas que servem para as pessoas que vão ser vinculadas
-- ---------------------------------------------------------------------------
-- O gerente vê as jornadas que valem em pelo menos uma loja em que ele vê a
-- Jornada; das lojas de fora, só quantas são (o nome não).
DROP FUNCTION IF EXISTS public.jornadas_da_tela();
CREATE FUNCTION public.jornadas_da_tela()
RETURNS TABLE(jornadaid integer, nome character varying, pausainicio time, pausafim time, observacao text,
              ativa boolean, lojas integer[], outraslojas integer, editavel boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ver AS (SELECT (SELECT public.lojas_onde_posso('jornada.ver'))::integer[] AS l),
       edita AS (SELECT (SELECT public.lojas_onde_posso('jornada.editar'))::integer[] AS l),
       todas AS (
    SELECT j.*, coalesce((SELECT array_agg(jl.lojaid ORDER BY jl.lojaid) FROM public.jornadaslojas jl
                           WHERE jl.contaid = j.contaid AND jl.jornadaid = j.jornadaid), '{}'::integer[]) AS alcance
      FROM public.jornadas j
     WHERE (public.sou_master() AND j.contaid = public.minha_conta())
        OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente())
  )
  SELECT t.jornadaid, t.nome, t.pausainicio, t.pausafim, t.observacao, t.ativa,
         CASE WHEN public.sou_master() THEN t.alcance
              ELSE ARRAY(SELECT x FROM unnest(t.alcance) x WHERE x = ANY ((SELECT l FROM ver)::integer[]) ORDER BY x) END,
         CASE WHEN public.sou_master() THEN 0
              ELSE (SELECT count(*)::integer FROM unnest(t.alcance) x WHERE NOT x = ANY ((SELECT l FROM ver)::integer[])) END,
         public.sou_master()
           OR (cardinality(t.alcance) > 0 AND t.alcance <@ (SELECT l FROM edita))
    FROM todas t
   WHERE public.sou_master() OR t.alcance && (SELECT l FROM ver)
   ORDER BY t.nome, t.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_da_tela() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.jornadas_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.dias_das_jornadas()
RETURNS TABLE(jornadaid integer, diasemana smallint, entrada time, saida time)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT d.jornadaid, d.diasemana, d.entrada, d.saida
    FROM public.jornadasdias d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente()
          AND EXISTS (SELECT 1 FROM public.jornadaslojas jl
                       WHERE jl.contaid = d.contaid AND jl.jornadaid = d.jornadaid
                         AND jl.lojaid = ANY ((SELECT public.lojas_onde_posso('jornada.ver'))::integer[])))
   ORDER BY d.jornadaid, d.diasemana
$$;

-- As jornadas ATIVAS que servem para TODAS as pessoas da lista (uma loja em
-- comum com cada uma). É o que a Equipe mostra na hora de vincular.
CREATE OR REPLACE FUNCTION public.jornadas_que_servem(p_funcionarios integer[])
RETURNS TABLE(jornadaid integer, nome character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH c AS (
    SELECT CASE WHEN public.sou_master() THEN public.minha_conta()
                WHEN cardinality((SELECT public.lojas_onde_posso('jornada.vincular'))::integer[]) > 0
                THEN public.conta_do_gerente() END AS contaid
  )
  SELECT j.jornadaid, j.nome
    FROM public.jornadas j, c
   WHERE j.contaid = c.contaid AND j.ativa
     AND cardinality(coalesce(p_funcionarios, '{}'::integer[])) > 0
     AND NOT EXISTS (
       SELECT 1 FROM unnest(p_funcionarios) x(f)
        WHERE NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                            JOIN public.jornadaslojas jl ON jl.contaid = fl.contaid AND jl.lojaid = fl.lojaid AND jl.jornadaid = j.jornadaid
                           WHERE fl.contaid = c.contaid AND fl.funcionarioid = x.f AND fl.ativo))
     -- O gerente só pergunta por gente das lojas em que ele liga pessoa a jornada.
     AND (public.sou_master() OR NOT EXISTS (
       SELECT 1 FROM unnest(p_funcionarios) y(f)
        WHERE NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = c.contaid AND fl.funcionarioid = y.f AND fl.ativo
                             AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('jornada.vincular'))::integer[]))))
   ORDER BY j.nome, j.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_que_servem(integer[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.jornadas_que_servem(integer[]) TO authenticated;

-- ======== 20260929293000_mapa_do_gerente.sql ========

-- CLASSIFICAÇÃO: ACRESCENTA
-- (muda por dentro duas funções do Mapa, sem mudar o que recebem; o mapa
-- ganha um campo novo, que o site no ar ignora.)
--
-- O Mapa da jornada para o gerente (30/09/2026, item 5 da jornada por loja):
-- com "Jornada: mapa e exportar" numa loja, ele marca o intervalo de quem
-- tem uma loja em comum com ele (planejamento do dia a dia), nunca o próprio.
-- O mapa diz à tela se quem vê pode marcar e exportar naquela loja (podemapa).
-- Continua valendo: o intervalo do mapa só existe para enxergar e imprimir;
-- nenhuma regra do sistema o lê (bot, tarefa, liberação, nota, rodízio). As
-- duas únicas funções que tocam intervalosdomapa continuam sendo estas.

-- salvar_intervalo_do_mapa: parte da versão viva.
CREATE OR REPLACE FUNCTION public.salvar_intervalo_do_mapa(p_funcionarioid integer, p_diasemana integer, p_inicio time without time zone, p_fim time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- O gerente: só quem tem uma loja em comum com ele, onde ele pode mexer no
  -- Mapa; nunca o próprio intervalo (30/09/2026).
  IF NOT v_master THEN
    IF NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                    WHERE fl.contaid = v_conta AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                      AND public.pode('jornada.mapa', fl.lojaid)) THEN
      RAISE EXCEPTION 'Marcar o intervalo desta pessoa não está liberado para o seu cargo (ela não é de uma loja em que você mexe no Mapa).'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
      RAISE EXCEPTION 'Você não marca o seu próprio intervalo.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  IF p_diasemana IS NULL OR p_diasemana NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND ativo) THEN
    RAISE EXCEPTION 'Colaborador não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF p_inicio IS NULL AND p_fim IS NULL THEN
    DELETE FROM public.intervalosdomapa
     WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND diasemana = p_diasemana;
    RETURN;
  END IF;
  IF p_inicio IS NULL OR p_fim IS NULL THEN
    RAISE EXCEPTION 'Preencha o começo e o fim do intervalo (ou tire o intervalo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_inicio = p_fim THEN
    RAISE EXCEPTION 'O começo e o fim do intervalo são iguais.' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.intervalosdomapa (contaid, funcionarioid, diasemana, inicio, fim)
  VALUES (v_conta, p_funcionarioid, p_diasemana, p_inicio, p_fim)
  ON CONFLICT (contaid, funcionarioid, diasemana)
  DO UPDATE SET inicio = EXCLUDED.inicio, fim = EXCLUDED.fim, atualizadoem = now();
END;
$function$;

-- mapa_da_jornada: parte da versão viva; só o campo podemapa é novo.
CREATE OR REPLACE FUNCTION public.mapa_da_jornada(p_lojaid integer, p_diasemana integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- A conta: a do master, ou a do gerente que vê a Jornada nesta loja. As
  -- regras das tabelas faziam esse corte para o master; agora é explícito.
  v_conta integer := CASE WHEN public.sou_master() THEN public.minha_conta()
                          WHEN public.conta_do_gerente() IS NOT NULL AND public.pode('jornada.ver', p_lojaid)
                          THEN public.conta_do_gerente() END;
  v_hoje date := CASE WHEN public.sou_master() THEN (public.meu_hoje()->>'hoje')::date
                      ELSE public.hoje_da_conta(public.conta_do_gerente()) END;
  v_dia  integer := coalesce(p_diasemana, extract(dow FROM v_hoje)::integer + 1);
  v_loja text;
BEGIN
  IF v_dia NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT l.nome INTO v_loja FROM public.lojas l WHERE l.lojaid = p_lojaid AND l.contaid = v_conta;

  RETURN jsonb_build_object(
    'diasemana', v_dia,
    'hoje', v_hoje,
    'loja', v_loja,
    -- Quem vê pode marcar o intervalo e exportar nesta loja? (30/09/2026)
    'podemapa', v_conta IS NOT NULL AND (public.sou_master() OR public.pode('jornada.mapa', p_lojaid)),
    'pessoas', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'funcionarioid', f.funcionarioid,
               'nome', f.nomecompleto,
               'cargo', f.cargo,
               -- A mesma ordem de dia_de_trabalho: afastamento e folga
               -- vencem o horário.
               'situacao', CASE
                 WHEN f.datainicioafastamento IS NOT NULL AND f.datafimafastamento IS NOT NULL
                      AND v_hoje BETWEEN f.datainicioafastamento AND f.datafimafastamento THEN 'afastado'
                 WHEN f.diadefolga = v_dia THEN 'folga'
                 WHEN f.jornadaid IS NULL THEN 'sem_jornada'
                 WHEN jd.entrada IS NULL THEN 'sem_horario'
                 ELSE 'trabalha' END,
               'afastadoate', f.datafimafastamento,
               -- Domingo de folga do mês (1º, 2º...): só avisa no mapa de domingo.
               'domingofolga', CASE WHEN v_dia = 1 AND coalesce(f.domingofolgamensal, 0) > 0
                                    THEN f.domingofolgamensal END,
               'entrada', to_char(jd.entrada, 'HH24:MI'),
               'saida', to_char(jd.saida, 'HH24:MI'),
               'intervaloinicio', to_char(im.inicio, 'HH24:MI'),
               'intervalofim', to_char(im.fim, 'HH24:MI'))
             ORDER BY jd.entrada NULLS LAST, f.nomecompleto)
        FROM public.funcionarioslojas fl
        JOIN public.funcionarios f
          ON f.contaid = fl.contaid AND f.funcionarioid = fl.funcionarioid AND f.ativo
        LEFT JOIN public.jornadasdias jd
          ON jd.contaid = f.contaid AND jd.jornadaid = f.jornadaid AND jd.diasemana = v_dia
        -- 29/09/2026: o intervalo é do DIA da semana escolhido.
        LEFT JOIN public.intervalosdomapa im
          ON im.contaid = f.contaid AND im.funcionarioid = f.funcionarioid AND im.diasemana = v_dia
       WHERE fl.contaid = v_conta AND fl.lojaid = p_lojaid AND fl.ativo), '[]'::jsonb));
END;
$function$;

COMMIT;
