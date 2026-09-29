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
