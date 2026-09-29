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

