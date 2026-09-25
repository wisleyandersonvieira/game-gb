-- A /saude passa a conferir a ASSINATURA das funções, não só o nome.
--
-- Pedido do Wisley (25/09/2026): "a /saude já confere nome e lista exata de
-- parâmetros de todas as funções que o aplicativo chama?" Não conferia — e foi
-- exatamente esse tipo de diferença que quebrou a entrega no tablet, e que ele
-- só descobriu testando na loja.
--
-- Quem sabe o que o aplicativo espera é o aplicativo. Então ele MANDA a lista
-- (src/integrations/supabase/contrato.ts, gerada dos tipos do banco) e o banco
-- responde o que não bate. Assim a lista não envelhece dentro de uma migração.

CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema(p_esperado jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_abrir_ex', 'tentativa_fechar', 'acesso_por_email',
    'definir_senha_gestor', 'marcar_senha_amao', 'erros_de_login',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado',
    'pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
    'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa', 'tarefa_unica_ja_cumprida',
    'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar',
    'fechamento_valendo', 'ficha_dos_tablets', 'registrar_evento_acesso_loja',
    'rodizio_espera', 'elegiveis_da_tarefa',
    -- Etapa 1.12 C1: o celular do colaborador.
    'eu_inicio', 'eu_tarefas', 'eu_entregar', 'eu_extrato', 'eu_confere_pessoa'
  ];
  v_faltando text[];
  v_tabelas  text[];
  v_chaves   text[];
  v_assinaturas text[];
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pede o diagnóstico.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_faltando
    FROM unnest(v_esperadas) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);

  SELECT coalesce(array_agg(t ORDER BY t), ARRAY[]::text[]) INTO v_tabelas
    FROM unnest(ARRAY['codigosacesso', 'tentativasacesso', 'senhasgestor', 'fotosexpurgo',
                      'tarefascandidatos', 'acessoslojaeventos']) t
   WHERE to_regclass('public.' || t) IS NULL;

  -- Configuração que não chegou em alguma conta: foi assim que a seção
  -- "Aceite de tarefas" apareceu vazia em 25/09/2026.
  SELECT coalesce(array_agg(DISTINCT k ORDER BY k), ARRAY[]::text[]) INTO v_chaves
    FROM public.contas c
    CROSS JOIN unnest(ARRAY['MINUTOS_RODIZIO_ACEITE', 'MINUTOS_TAREFA_PARADA',
                            'DIAS_GUARDAR_FOTO_ENTREGA', 'CONTATO_PRIVACIDADE']) k
   WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                      WHERE g.contaid = c.contaid AND g.chave = k);

  -- ASSINATURAS: o aplicativo manda, para cada funcao que ele chama, os
  -- parametros que espera encontrar. Aqui comparamos com o que o banco tem de
  -- verdade. Conferir so o NOME nao bastava: em 25/09/2026 a entrega quebrou
  -- porque uma funcao tinha mudado de parametros, e o /saude dizia "tudo
  -- certo".
  --
  -- So os parametros p_*: numa funcao que devolve tabela, proargnames traz
  -- tambem o nome das COLUNAS, que nao sao parametro de ninguem.
  WITH doBanco AS (
    SELECT p.proname AS nome,
           coalesce((SELECT array_agg(a ORDER BY a) FROM unnest(coalesce(p.proargnames, ARRAY[]::text[])) a
                      WHERE a LIKE 'p\_%'), ARRAY[]::text[]) AS params
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
  ), doApp AS (
    SELECT j.k AS nome,
           coalesce((SELECT array_agg(x ORDER BY x) FROM jsonb_array_elements_text(j.val) x),
                    ARRAY[]::text[]) AS params
      FROM jsonb_each(coalesce(p_esperado, '{}'::jsonb)) AS j(k, val)
  )
  SELECT coalesce(array_agg(msg ORDER BY msg), ARRAY[]::text[]) INTO v_assinaturas
    FROM (
      SELECT CASE
               WHEN NOT EXISTS (SELECT 1 FROM doBanco b WHERE b.nome = e.nome)
                 THEN e.nome || ' (nao existe no banco)'
               ELSE e.nome || ' (o app espera: ' || array_to_string(e.params, ', ')
                           || '; o banco tem: '
                           || (SELECT string_agg(array_to_string(b.params, ', '), ' / ')
                                 FROM doBanco b WHERE b.nome = e.nome) || ')'
             END AS msg
        FROM doApp e
       WHERE NOT EXISTS (SELECT 1 FROM doBanco b
                          WHERE b.nome = e.nome AND b.params = e.params)
    ) q;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'assinaturasdiferentes', to_jsonb(v_assinaturas),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'configuracoesfaltando', to_jsonb(v_chaves),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

-- A versao sem parametro some: senao ficariam as duas no banco e ninguem
-- saberia qual roda.
DROP FUNCTION IF EXISTS public.diagnostico_do_sistema();

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema(jsonb) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema(jsonb) TO service_role;
