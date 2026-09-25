-- =========================================================================
-- STGame — O BANCO ESTÁ COMPLETO?
--
-- Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Só LÊ. Não altera nada.
--
-- Diz, item por item, o que já está no banco e o que falta. Se aparecer
-- qualquer "FALTA", rode o arquivo indicado na última coluna.
-- =========================================================================

WITH esperado(ordem, parte, tipo, nome, arquivo) AS (VALUES
  -- Parte A
  ( 1, 'A',    'funcao', 'tentativa_abrir',              'aplicar-etapa-1.12-parte-A.sql'),
  ( 2, 'A',    'funcao', 'acesso_por_email',             'aplicar-etapa-1.12-parte-A.sql'),
  ( 3, 'A',    'funcao', 'definir_senha_gestor',         'aplicar-etapa-1.12-parte-A.sql'),
  ( 4, 'A',    'funcao', 'definir_pin',                  'aplicar-etapa-1.12-parte-A.sql'),
  ( 5, 'A',    'funcao', 'criar_acesso_loja',            'aplicar-etapa-1.12-parte-A.sql'),
  ( 6, 'A',    'funcao', 'criar_acesso_colaborador',     'aplicar-etapa-1.12-parte-A.sql'),
  ( 7, 'A',    'funcao', 'meu_acesso',                   'aplicar-etapa-1.12-parte-A.sql'),
  ( 8, 'A',    'funcao', 'rotina_expurgo_fotos',         'aplicar-etapa-1.12-parte-A.sql'),
  ( 9, 'A',    'tabela', 'codigosacesso',                'aplicar-etapa-1.12-parte-A.sql'),
  (10, 'A',    'tabela', 'tentativasacesso',             'aplicar-etapa-1.12-parte-A.sql'),
  (11, 'A',    'tabela', 'senhasgestor',                 'aplicar-etapa-1.12-parte-A.sql'),
  (12, 'A',    'tabela', 'fotosexpurgo',                 'aplicar-etapa-1.12-parte-A.sql'),
  -- B1: tarefa compartilhada e tablet
  (20, 'B1',   'funcao', 'pegar_tarefa',                 'aplicar-etapa-1.12-parte-B1.sql'),
  (21, 'B1',   'funcao', 'revogar_aceite',               'aplicar-etapa-1.12-parte-B1.sql'),
  (22, 'B1',   'funcao', 'atribuir_tarefa',              'aplicar-etapa-1.12-parte-B1.sql'),
  (23, 'B1',   'funcao', 'fila_da_loja',                 'aplicar-etapa-1.12-parte-B1.sql'),
  (24, 'B1',   'funcao', 'tarefas_nao_pegas',            'aplicar-etapa-1.12-parte-B1.sql'),
  (25, 'B1',   'funcao', 'tarefas_pegas_da_pessoa',      'aplicar-etapa-1.12-parte-B1.sql'),
  (26, 'B1',   'funcao', 'tarefa_unica_ja_cumprida',     'aplicar-etapa-1.12-parte-B1.sql'),
  (27, 'B1',   'funcao', 'visao_fila',                   'aplicar-etapa-1.12-parte-B1.sql'),
  (28, 'B1',   'funcao', 'visao_pessoa_do_pin',          'aplicar-etapa-1.12-parte-B1.sql'),
  (29, 'B1',   'funcao', 'visao_pegar',                  'aplicar-etapa-1.12-parte-B1.sql'),
  (30, 'B1',   'funcao', 'visao_entregar',               'aplicar-etapa-1.12-parte-B1.sql'),
  (31, 'B1',   'tabela', 'tarefascandidatos',            'aplicar-etapa-1.12-parte-B1.sql'),
  (32, 'B1',   'funcao', 'fechamento_valendo',           'aplicar-etapa-1.12-parte-B1.sql'),
  (33, 'B1',   'funcao', 'ficha_dos_tablets',            'aplicar-etapa-1.12-parte-B1.sql'),
  (34, 'B1',   'funcao', 'registrar_evento_acesso_loja', 'aplicar-etapa-1.12-parte-B1.sql'),
  (35, 'B1',   'tabela', 'acessoslojaeventos',           'aplicar-etapa-1.12-parte-B1.sql'),
  -- B1: senha digitada do tablet  (ESTA PARTE O LOGIN PRECISA)
  (40, 'B1',   'funcao', 'tentativa_abrir_ex',           'aplicar-etapa-1.12-parte-B1.sql'),
  (41, 'B1',   'funcao', 'marcar_senha_amao',            'aplicar-etapa-1.12-parte-B1.sql'),
  (42, 'B1',   'funcao', 'erros_de_login',               'aplicar-etapa-1.12-parte-B1.sql'),
  -- B1: rodizio no aceite
  (50, 'B1',   'funcao', 'rodizio_espera',               'aplicar-etapa-1.12-parte-B1.sql'),
  (51, 'B1',   'funcao', 'elegiveis_da_tarefa',          'aplicar-etapa-1.12-parte-B1.sql')
),
situacao AS (
  SELECT e.*,
         CASE e.tipo
           WHEN 'funcao' THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome)
           ELSE to_regclass('public.' || e.nome) IS NOT NULL
         END AS tem
    FROM esperado e
),
-- Existir não basta: várias funções FORAM SUBSTITUÍDAS por versões novas.
-- Se só olhássemos o nome, uma função velha passaria por boa. Aqui olhamos
-- também um pedaço do conteúdo que só a versão nova tem.
versao(ordem, parte, tipo, nome, arquivo, tem) AS (VALUES
  (60, 'B1', 'versao', 'meu_acesso responde "semlogin"', 'aplicar-etapa-1.12-parte-B1.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'meu_acesso'
                  AND p.prosrc LIKE '%semlogin%')),
  (61, 'B1', 'versao', 'acesso_por_email diz se a senha e digitada', 'aplicar-etapa-1.12-parte-B1.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'acesso_por_email'
                  AND p.prosrc LIKE '%senhamanual%')),
  (62, 'B1', 'versao', 'fila_da_loja tem o cronometro', 'aplicar-etapa-1.12-parte-B1.sql',
       EXISTS (SELECT 1 FROM information_schema.parameters
                WHERE specific_schema = 'public' AND parameter_name = 'disponiveldesde')),
  (63, 'B1', 'versao', 'senhasgestor marca senha digitada', 'aplicar-etapa-1.12-parte-B1.sql',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'senhasgestor'
                  AND column_name = 'definidaamao')),
  (64, 'B1', 'versao', 'TODA configuracao padrao em TODA conta', 'aplicar-etapa-1.12-parte-B1.sql',
       NOT EXISTS (
         SELECT 1 FROM public.contas c
         CROSS JOIN LATERAL (
           SELECT (regexp_matches(p.prosrc, '\(p_contaid, ''([A-Z_]+)''', 'g'))[1] AS k
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'cria_configuracoes_padrao'
         ) chaves
         WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                            WHERE g.contaid = c.contaid AND g.chave = chaves.k))),
  (65, 'B1', 'versao', 'conta nova ja nasce com as configuracoes (gatilho)', 'aplicar-etapa-1.12-parte-B1.sql',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'contas_configuracoes_padrao')),
  (66, 'B1', 'funcao', 'rodizio_espera', 'aplicar-etapa-1.12-parte-B1.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'rodizio_espera'))
)
SELECT CASE WHEN tem THEN 'ok' ELSE '>>> FALTA' END AS "situacao",
       parte AS "parte", tipo AS "tipo", nome AS "nome",
       CASE WHEN tem THEN '' ELSE arquivo END AS "rode este arquivo"
  FROM (SELECT ordem, parte, tipo, nome, arquivo, tem FROM situacao
        UNION ALL
        SELECT ordem, parte, tipo, nome, arquivo, tem FROM versao) x
 ORDER BY tem, ordem;
