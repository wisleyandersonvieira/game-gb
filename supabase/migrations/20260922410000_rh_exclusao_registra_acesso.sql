-- Etapa 1.10, ajuste: excluir "por engano" registra o acesso e libera,
-- por 2 minutos, so a remocao do arquivo no Storage (o Storage confere a
-- leitura ao apagar).

ALTER TABLE public.documentosacessos DROP CONSTRAINT documentosacessos_acao_check;
ALTER TABLE public.documentosacessos ADD CONSTRAINT documentosacessos_acao_check
  CHECK (acao IN ('envio', 'visualizacao', 'exclusao'));

CREATE OR REPLACE FUNCTION public.excluir_documento_por_engano(p_documentoid integer, p_motivo text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel(); d public.documentospessoais%ROWTYPE;
BEGIN
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO d FROM public.documentospessoais WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF d.situacao <> 'Ativo' THEN
    RAISE EXCEPTION 'Só um documento ativo pode ser excluído por engano.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.documentospessoaisciencia WHERE documentoid = p_documentoid AND status = 'Ciente') THEN
    RAISE EXCEPTION 'O documento já tem ciência: não se apaga. Substitua por nova versão ou arquive.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF d.dataupload < now() - interval '7 days' THEN
    RAISE EXCEPTION 'Passaram mais de 7 dias do envio: não se apaga. Substitua por nova versão ou arquive.' USING ERRCODE = 'restrict_violation';
  END IF;
  UPDATE public.documentospessoais
     SET situacao = 'Excluido', excluidoem = now(), excluidopor = auth.uid(), motivoexclusao = btrim(p_motivo)
   WHERE documentoid = p_documentoid;
  -- Registra e libera, por 2 minutos, so a remocao do arquivo.
  INSERT INTO public.documentosacessos (contaid, documentoid, caminho, acao, usuario)
  VALUES (v_conta, p_documentoid, d.caminhoarquivo, 'exclusao', auth.uid());
  RETURN d.caminhoarquivo;
END;
$$;

DROP POLICY documentos_rh_sel ON storage.objects;
CREATE POLICY documentos_rh_sel ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta())::text
         AND (public.documento_rh_liberado(name, 'visualizacao') OR public.documento_rh_liberado(name, 'envio')
              OR public.documento_rh_liberado(name, 'exclusao')));

GRANT EXECUTE ON FUNCTION public.excluir_documento_por_engano(integer, text) TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;
