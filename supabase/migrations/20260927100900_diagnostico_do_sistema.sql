-- Etapa 1.12, parte A — diagnóstico do sistema (23/09/2026).
--
-- Motivo: o administrador geral ficou sem conseguir entrar depois da publicação
-- e a tela só dizia "Não foi possível conferir o acesso agora". A causa era o
-- banco ainda não ter recebido estas migrações — e não havia jeito de descobrir
-- isso sem olhar o código.
--
-- Esta função diz o que está faltando, sem revelar valor de segredo nenhum.
-- Se ela própria não existir, a resposta do servidor já é a prova de que o
-- banco está desatualizado.
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_fechar', 'acesso_por_email', 'definir_senha_gestor',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado'
  ];
  v_faltando text[];
  v_tabelas  text[];
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pede o diagnóstico.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_faltando
    FROM unnest(v_esperadas) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);

  SELECT coalesce(array_agg(t ORDER BY t), ARRAY[]::text[]) INTO v_tabelas
    FROM unnest(ARRAY['codigosacesso', 'tentativasacesso', 'senhasgestor', 'fotosexpurgo']) t
   WHERE to_regclass('public.' || t) IS NULL;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;
