-- =========================================================================
-- STGame — Quem não vê valor não grava; entrega sem foto do gerente à vista.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-parte-5-usuarios-e-cargos.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929288000_valor_e_entrega_sem_foto.sql
--
-- CLASSIFICAÇÃO: ACRESCENTA (cria uma coluna; as funções mudam por dentro sem mudar o que recebem nem o que devolvem ao master)
--
-- O QUE MUDA: sem "Ver valores em R$", o gerente não grava pagamento de
-- agenda, agendamento com valor, abate em comanda nem venda. A entrega que um
-- gerente registra sem foto aparece na lista de Estornos do master. O
-- gerente vê o histórico das vendas das lojas dele. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Quem não pode ver um valor não pode gravá-lo; e a entrega sem foto do
-- gerente à vista do master (30/09/2026, decisões do Wisley).
--
-- 1. REGRA GERAL (CLAUDE.md): sem "Ver valores em R$" na loja, ninguém grava
--    valor em R$ nela. Hoje: o pagamento da agenda, o agendamento criado com
--    valor, o resgate "abate na comanda" e o lançamento da venda do dia. A
--    seção 114 do teste reprova função nova que receba valor em R$ sem
--    conferir a permissão (ou que não seja só do master).
-- 2. Quem registrou cada entrega passa a ficar gravado (entregas.registradopor).
--    A entrega registrada por um GERENTE e SEM FOTO entra na lista de
--    Estornos do master (não é bloqueada: fica à vista). As entregas antigas
--    não têm esse registro e não aparecem.
-- 3. O histórico das vendas também para o gerente: só das lojas em que ele
--    vê Metas E "Ver valores em R$" (é ele quem lança).
-- Para o master nada muda. Nenhum dado é alterado.
-- Classificação: ACRESCENTA (cria uma coluna e muda regras só para o gerente).

ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS registradopor uuid;
COMMENT ON COLUMN public.entregas.registradopor IS 'Quem registrou a entrega (login). Vazio nas entregas anteriores a 30/09/2026 e nas do bot.';

-- criar_agendamento: parte da versão viva (de 20260929257000_agenda_permissoes.sql).
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

-- alterar_pagamento_agendamento: parte da versão viva (de 20260929257000_agenda_permissoes.sql).
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
  -- Quem não pode ver um valor não pode gravá-lo.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('valores.ver_rs', a.lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não grava pagamento.' USING ERRCODE = 'insufficient_privilege';
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

-- registrar_troca_por_valor: parte da versão viva (de 20260929251000_premios_permissoes.sql).
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

-- lancar_venda_do_dia: parte da versão viva (de 20260929253000_metas_permissoes.sql).
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

-- registrar_entrega: parte da versão viva (de 20260929250000_quadro_permissoes.sql); grava quem registrou.
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
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
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

-- estornos_da_conta: parte da versão viva (de 20260929252000_feedbacks_permissoes.sql); mais a entrega sem foto do gerente.
CREATE OR REPLACE FUNCTION public.estornos_da_conta(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(tipo text, quando timestamp with time zone, lojaid integer, loja text, pessoa text, descricao text, pontos integer, motivo text, quem text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  UNION ALL
  -- Entrega registrada por um GERENTE sem foto (30/09/2026, decisão do
  -- Wisley): não é bloqueada, fica à vista do master aqui.
  SELECT 'entrega sem foto', e.dataenvio, e.lojaid, l.nome::text, f.nomecompleto::text,
         t.titulo::text || ' (' || e.statusvalidacao || ')', coalesce(e.pontosganhos, 0), e.observacao::text,
         coalesce(public.autor_em(e.registradopor, e.dataenvio), 'desconhecido')
    FROM public.entregas e
    JOIN public.lojas l ON l.contaid = e.contaid AND l.lojaid = e.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = e.contaid AND f.funcionarioid = e.funcionarioid
    LEFT JOIN public.tarefas t ON t.contaid = e.contaid AND t.tarefaid = e.tarefaid
   WHERE e.contaid = v_conta AND e.pathfotoevidencia IS NULL
     AND EXISTS (SELECT 1 FROM public.contasusuarios cu
                  WHERE cu.contaid = e.contaid AND cu.userid = e.registradopor AND cu.papel = 'gerente')
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
   -- Desempate fixo: dois estornos no mesmo instante saem sempre na mesma ordem.
   ORDER BY 2 DESC, 1, 6, 5, 9, 8
   LIMIT 500;
END;
$function$;

-- historico_das_vendas: parte da versão viva (de 20260929273000_meta_so_do_master.sql); também o gerente, das lojas dele.
CREATE OR REPLACE FUNCTION public.historico_das_vendas(p_lojaid integer)
 RETURNS TABLE(historicoid integer, dataapuracao date, valoranterior numeric, valornovo numeric, motivo text, alteradoem timestamp with time zone, quem text, foivoce boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT h.historicoid, h.dataapuracao, h.valoranterior, h.valornovo, h.motivo::text, h.alteradoem,
         coalesce(public.autor_em(h.alteradopor, h.alteradoem), CASE WHEN h.alteradopor IS NULL THEN 'Sistema' ELSE 'desconhecido' END),
         h.alteradopor IS NOT DISTINCT FROM auth.uid()
    FROM public.metashistorico h
   WHERE h.lojaid = p_lojaid
     AND ((public.sou_master() AND h.contaid = public.minha_conta())
       -- O gerente: das lojas em que ele vê Metas E valores em R$ (é ele quem lança).
       OR (NOT public.sou_master() AND h.contaid = public.conta_do_gerente()
           AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)))
   ORDER BY h.alteradoem DESC, h.historicoid DESC
   LIMIT 200
$function$;

COMMIT;
