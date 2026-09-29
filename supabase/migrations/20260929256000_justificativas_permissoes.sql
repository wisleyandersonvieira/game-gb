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

