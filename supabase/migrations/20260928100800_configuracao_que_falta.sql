-- Etapa 1.12 — a configuração que falta não pode travar a tela (25/09/2026).
--
-- O que aconteceu: a seção "Aceite de tarefas" apareceu com o título e a
-- explicação, e NENHUM campo. Duas causas somadas:
--   1) a conta do Wisley é anterior às chaves novas, e a migração que as
--      preenche nas contas existentes ainda não tinha sido aplicada;
--   2) a tela escondia o campo quando a chave não existia, e `alterar_configuracao`
--      só sabia ALTERAR — criar era impossível.
--
-- A causa 1 é de aplicação; a 2 é de projeto, e é a que conserto aqui: quando
-- a chave não existe, a função cria os padrões que faltam e segue. A tela
-- passa a mostrar o campo com o valor padrão (ver configuracoes.tsx).
--
-- É a segunda vez que uma configuração nova não chega numa conta antiga. O
-- teste de isolamento passou a exigir que TODA chave padrão exista em TODA
-- conta (seção 53).
CREATE OR REPLACE FUNCTION public.alterar_configuracao(p_chave text, p_valor text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_novo  text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.contasusuarios
                  WHERE userid = auth.uid() AND contaid = v_conta AND papel = 'master') THEN
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
$$;

REVOKE ALL ON FUNCTION public.alterar_configuracao(text, text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.alterar_configuracao(text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- O diagnóstico (/saude) passa a cobrar também as funções do rodízio
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
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
    'rodizio_espera', 'elegiveis_da_tarefa'
  ];
  v_faltando text[];
  v_tabelas  text[];
  v_chaves   text[];
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

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'configuracoesfaltando', to_jsonb(v_chaves),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;

-- ---------------------------------------------------------------------------
-- A CAUSA DE FUNDO: conta nova nascia sem configuração nenhuma
-- ---------------------------------------------------------------------------
-- `cria_configuracoes_padrao` só era chamada pela função de servidor que
-- cadastra um cliente, e por migrações que preenchiam as contas existentes.
-- Ou seja: a garantia dependia de alguém lembrar. Agora é do banco.
CREATE OR REPLACE FUNCTION public.contas_configuracoes_padrao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.cria_configuracoes_padrao(NEW.contaid);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contas_configuracoes_padrao ON public.contas;
CREATE TRIGGER contas_configuracoes_padrao
  AFTER INSERT ON public.contas
  FOR EACH ROW EXECUTE FUNCTION public.contas_configuracoes_padrao();

REVOKE ALL ON FUNCTION public.contas_configuracoes_padrao() FROM public, anon, authenticated;

-- E as contas que já existem recebem TUDO o que faltar — não só as chaves
-- desta versão. `cria_configuracoes_padrao` não mexe no que já está lá.
DO $preencher$
DECLARE c record;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_configuracoes_padrao(c.contaid);
  END LOOP;
END $preencher$;
