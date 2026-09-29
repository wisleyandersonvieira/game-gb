-- =========================================================================
-- STGame — O BANCO ESTÁ COMPLETO?
--
-- Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Só LÊ. Não altera nada.
--
-- Diz, item por item, o que já está no banco e o que falta. Se aparecer
-- qualquer "FALTA", a última coluna diz o que fazer.
--
-- REGRA (29/09/2026): o conferidor NUNCA manda rodar um arquivo mais velho
-- que o mais novo já aplicado — rodar um arquivo velho por cima desfaz a
-- entrega mais recente (quase aconteceu com a linha 340). Nesse caso ele
-- diz "NÃO rode" e pede para chamar o Claude. "Mais velho" é pela data da
-- migração de cada arquivo (tabela "arquivos", conferida por teste), e não
-- pelo número da linha.
--
-- Onde dá, a conferência RODA a função e olha o que volta (sem gravar
-- nada); onde não dá (a função precisa de alguém logado, de um dado real ou
-- gravaria algo), ela procura um trecho do código. Ver o comentário de cada
-- linha.
-- =========================================================================

-- Roda uma consulta de LEITURA e diz se ela devolveu verdadeiro. Função que
-- ainda não existe (banco atrasado) vira "falso", não erro. Temporária: some
-- quando a janela fecha; não altera nada no banco.
CREATE OR REPLACE FUNCTION pg_temp.tenta(p_consulta text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE r boolean;
BEGIN
  EXECUTE p_consulta INTO r;
  RETURN coalesce(r, false);
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

WITH arquivos(arquivo, versao) AS (VALUES
  ('aplicar-aceite-e-som.sql', '20260929100700'),
  ('aplicar-admin-clientes-e-redes.sql', '20260929160000'),
  ('aplicar-barra-da-fila.sql', '20260929240000'),
  ('aplicar-colaborador-pede-resgate.sql', '20260929101000'),
  ('aplicar-concluidas-e-venda-de-ontem.sql', '20260929244000'),
  ('aplicar-consertos-da-revisao-c1.sql', '20260929100400'),
  ('aplicar-desempate-e-dias-sem-lancamento.sql', '20260929245000'),
  ('aplicar-desempate-nas-listas.sql', '20260929265500'),
  ('aplicar-disponivel-uma-fonte.sql', '20260929238000'),
  ('aplicar-entrega-da-copia.sql', '20260929234000'),
  ('aplicar-entrega-do-celular.sql', '20260929235000'),
  ('aplicar-etapa-1.12-parte-A.sql', '20260927100900'),
  ('aplicar-etapa-1.12-parte-B1.sql', '20260928100800'),
  ('aplicar-etapa-1.12-parte-C.sql', '20260929100000'),
  ('aplicar-faixa-meta-do-mes.sql', '20260929241000'),
  ('aplicar-fechar-papel-gerente.sql', '20260929247000'),
  ('aplicar-fila-fuso-uma-vez.sql', '20260929265700'),
  ('aplicar-folha-de-acesso.sql', '20260929150000'),
  ('aplicar-foto-da-fila.sql', '20260929237000'),
  ('aplicar-hoje-da-conta.sql', '20260929140000'),
  ('aplicar-hora-de-liberacao.sql', '20260929100600'),
  ('aplicar-inicio-da-fila.sql', '20260929242000'),
  ('aplicar-jornadas.sql', '20260929190000'),
  ('aplicar-lojas-do-gerente-uma-vez.sql', '20260929268500'),
  ('aplicar-mapa-da-jornada.sql', '20260929210000'),
  ('aplicar-mapa-intervalo-por-dia.sql', '20260929233000'),
  ('aplicar-menu-e-catalogo.sql', '20260929236000'),
  ('aplicar-mural-no-tablet.sql', '20260929101200'),
  ('aplicar-ninguem-gera-pontos-para-si.sql', '20260929271000'),
  ('aplicar-parte-4-porta-do-gerente.sql', '20260929270000'),
  ('aplicar-pedido-no-tablet.sql', '20260929100900'),
  ('aplicar-permissoes-parte-1-ajustes.sql', '20260929249000'),
  ('aplicar-permissoes-parte-1-base.sql', '20260929248000'),
  ('aplicar-permissoes-parte-2-agenda.sql', '20260929257000'),
  ('aplicar-permissoes-parte-2-comunicados.sql', '20260929258000'),
  ('aplicar-permissoes-parte-2-conquistas.sql', '20260929259000'),
  ('aplicar-permissoes-parte-2-equipe.sql', '20260929262000'),
  ('aplicar-permissoes-parte-2-feedbacks.sql', '20260929252000'),
  ('aplicar-permissoes-parte-2-justificativas.sql', '20260929256000'),
  ('aplicar-permissoes-parte-2-lojas.sql', '20260929261000'),
  ('aplicar-permissoes-parte-2-metas.sql', '20260929253000'),
  ('aplicar-permissoes-parte-2-onboarding.sql', '20260929260000'),
  ('aplicar-permissoes-parte-2-premios.sql', '20260929251000'),
  ('aplicar-permissoes-parte-2-quadro.sql', '20260929250000'),
  ('aplicar-permissoes-parte-2-solicitacoes.sql', '20260929255000'),
  ('aplicar-permissoes-parte-2-tarefas.sql', '20260929254000'),
  ('aplicar-permissoes-parte-3-inicio.sql', '20260929266000'),
  ('aplicar-permissoes-parte-3-metas.sql', '20260929268000'),
  ('aplicar-permissoes-parte-3-painel-fila.sql', '20260929264000'),
  ('aplicar-permissoes-parte-3-quadro.sql', '20260929265000'),
  ('aplicar-permissoes-parte-3-relatorios.sql', '20260929267000'),
  ('aplicar-permissoes-parte-3-rh.sql', '20260929263000'),
  ('aplicar-pin-do-tablet-numa-ida.sql', '20260929130000'),
  ('aplicar-primeiro-acesso-e-tv.sql', '20260929180000'),
  ('aplicar-quadro-e-intervalo.sql', '20260929200000'),
  ('aplicar-quem-fez-no-tablet.sql', '20260929100200'),
  ('aplicar-quem-pode-aceitar.sql', '20260929239000'),
  ('aplicar-remover-anexo.sql', '20260929170000'),
  ('aplicar-som-por-loja.sql', '20260929120000'),
  ('aplicar-tarefas-comuns-e-atribuicoes.sql', '20260929220000'),
  ('aplicar-tela-meta-especial.sql', '20260929243000'),
  ('aplicar-teto-fotos-e-agenda.sql', '20260929232000'),
  ('aplicar-trava-do-pin-por-pessoa.sql', '20260929246000'),
  ('aplicar-tv-configuravel.sql', '20260929101100'),
  ('aplicar-tv-por-codigo.sql', '20260929100500')
),
esperado(ordem, parte, tipo, nome, arquivo) AS (VALUES
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
  (51, 'B1',   'funcao', 'elegiveis_da_tarefa',          'aplicar-etapa-1.12-parte-B1.sql'),
  -- C1: o celular do colaborador
  (70, 'C1',   'funcao', 'eu_inicio',                    'aplicar-etapa-1.12-parte-C.sql'),
  (71, 'C1',   'funcao', 'eu_tarefas',                   'aplicar-etapa-1.12-parte-C.sql'),
  (72, 'C1',   'funcao', 'eu_entregar',                  'aplicar-etapa-1.12-parte-C.sql'),
  (73, 'C1',   'funcao', 'eu_extrato',                   'aplicar-etapa-1.12-parte-C.sql'),
  -- TV por codigo curto
  (90, 'TV',   'funcao', 'tv_novo_codigo',               'aplicar-tv-por-codigo.sql'),
  (91, 'TV',   'funcao', 'parear_tv',                    'aplicar-tv-por-codigo.sql'),
  (92, 'TV',   'funcao', 'tv_buscar_link',               'aplicar-tv-por-codigo.sql'),
  (93, 'TV',   'tabela', 'codigostv',                    'aplicar-tv-por-codigo.sql'),
  -- Hora de liberacao da tarefa
  (96, 'HORA', 'funcao', 'instante_na_conta',            'aplicar-hora-de-liberacao.sql'),
  (97, 'HORA', 'funcao', 'fuso_da_conta',                'aplicar-hora-de-liberacao.sql'),
  (98, 'HORA', 'funcao', 'alterar_hora_da_atribuicao',   'aplicar-hora-de-liberacao.sql'),
  -- Ajuste do tablet e consertos da revisao
  (80, 'C1+',  'funcao', 'eu_confere_pessoa',            'aplicar-consertos-da-revisao-c1.sql')
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
  -- Comportamento: sem ninguém logado (esta janela), meu_acesso diz "semlogin".
  (60, 'B1', 'versao', 'meu_acesso responde "semlogin"', 'aplicar-etapa-1.12-parte-B1.sql',
       pg_temp.tenta($q$SELECT public.meu_acesso()->>'tipo' = 'semlogin'$q$)),
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
                WHERE n.nspname = 'public' AND p.proname = 'rodizio_espera')),
  (74, 'C1', 'versao', 'entregas marca a foto sem hora', 'aplicar-etapa-1.12-parte-C.sql',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'entregas'
                  AND column_name = 'semhorafoto')),
  (75, 'C1', 'versao', 'registrar_entrega ficou UMA so (a de 6 parametros)', 'aplicar-etapa-1.12-parte-C.sql',
       1 = (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'registrar_entrega')),
  (76, 'C1', 'versao', 'nenhuma funcao eu_* liberada para quem esta logado', 'aplicar-etapa-1.12-parte-C.sql',
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname LIKE 'eu\_%'
                      AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
  (81, 'C1+', 'versao', 'o tablet diz quem fez em "Feitas hoje"', 'aplicar-quem-fez-no-tablet.sql',
       EXISTS (SELECT 1 FROM information_schema.parameters
                WHERE specific_schema = 'public' AND parameter_name = 'feitapor')),
  -- Comportamento: o diagnóstico devolve a lista de assinaturas diferentes.
  (82, 'C1+', 'versao', 'a /saude confere a assinatura das funcoes', 'aplicar-consertos-da-revisao-c1.sql',
       pg_temp.tenta($q$SELECT public.diagnostico_do_sistema() ? 'assinaturasdiferentes'$q$)),
  (83, 'C1+', 'versao', 'a prova da foto e feita pelo servidor', 'aplicar-consertos-da-revisao-c1.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'eu_confere_pessoa')),
  (84, 'C1+', 'versao', 'conta cancelada fecha tambem as leituras do celular', 'aplicar-consertos-da-revisao-c1.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'eu_confere_pessoa') LIKE '%cancelada%'),
  (85, 'C1+', 'versao', 'o Inicio do colaborador passa pela conferencia unica', 'aplicar-consertos-da-revisao-c1.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'eu_inicio') LIKE '%eu_confere_pessoa%'),
  -- Estas duas conferem se a REGRA continua valendo (não só se a migração
  -- foi aplicada). Vieram do ramo revisao-c1-guardada, conferido linha a
  -- linha e apagado em 28/09/2026.
  (86, 'C1+', 'versao', 'a entrega pelo celular exige que a tarefa esteja na fila de hoje', 'aplicar-consertos-da-revisao-c1.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'eu_entregar') LIKE '%fila_da_loja(%'
       AND (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'eu_entregar') LIKE '%não está na fila de hoje%'),
  (87, 'C1+', 'versao', 'o tablet grava a impressao digital da foto (a mesma foto nao prova duas tarefas)', 'aplicar-consertos-da-revisao-c1.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'visao_entregar') LIKE '%p_fotoidunico%'),
  (94, 'TV', 'versao', 'a trava conhece o pareamento da TV', 'aplicar-tv-por-codigo.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'tentativa_abrir_ex') LIKE '%tvcodigo%'),
  (95, 'TV', 'versao', 'ninguem le a tabela dos codigos pelo navegador', 'aplicar-tv-por-codigo.sql',
       to_regclass('public.codigostv') IS NOT NULL
       AND NOT has_table_privilege('authenticated', 'public.codigostv', 'SELECT')),
  (99, 'HORA', 'versao', 'a tarefa pode ter hora de liberacao', 'aplicar-hora-de-liberacao.sql',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'tarefasatribuidas'
                  AND column_name = 'disponivelapartir')),
  (100, 'HORA', 'versao', 'a fila sabe o que ja liberou', 'aplicar-hora-de-liberacao.sql',
       EXISTS (SELECT 1 FROM information_schema.parameters
                WHERE specific_schema = 'public' AND parameter_name = 'liberada')),
  (101, 'HORA', 'versao', 'o fuso da empresa chegou em TODA conta', 'aplicar-hora-de-liberacao.sql',
       NOT EXISTS (SELECT 1 FROM public.contas c
                    WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                                       WHERE g.contaid = c.contaid AND g.chave = 'FUSO_HORARIO'))),
  (110, 'ACEITE', 'versao', 'o tablet exige aceite antes de entregar', 'aplicar-aceite-e-som.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'visao_entregar') LIKE '%Aceite a tarefa%'),
  (111, 'ACEITE', 'versao', 'o celular exige aceite antes de entregar', 'aplicar-aceite-e-som.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'eu_entregar') LIKE '%Aceite a tarefa%'),
  -- Antes conferia a chave SOM_TAREFA_NOVA na conta. Em 25/09/2026 o som virou
  -- configuracao POR LOJA, e as chaves da conta foram removidas.
  (112, 'B2', 'versao', 'o som do tablet e configurado por loja', 'aplicar-som-por-loja.sql',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'lojas'
                  AND column_name = 'somrepetirminutos')),
  (120, 'B2', 'versao', 'o tablet abre pedido', 'aplicar-pedido-no-tablet.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'visao_abrir_pedido')),
  (121, 'B2', 'versao', 'o pedido guarda a observacao', 'aplicar-pedido-no-tablet.sql',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'solicitacoesinternas'
                  AND column_name = 'observacao')),
  (130, 'C2', 'versao', 'o colaborador pede resgate', 'aplicar-colaborador-pede-resgate.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'eu_pedir_resgate')),
  (131, 'C2', 'versao', 'a lista do gestor mostra de onde veio', 'aplicar-colaborador-pede-resgate.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'listar_trocas') LIKE '%origem%'),
  (140, 'TV2', 'versao', 'a TV e configuravel por loja', 'aplicar-tv-configuravel.sql',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'lojas'
                  AND column_name = 'tvblocos')),
  -- Comportamento: o painel de uma loja ativa traz "podiomes" e "emandamento".
  -- Banco sem loja nenhuma: não há o que rodar, então procura no código.
  (141, 'TV2', 'versao', 'o painel traz "em andamento" e o podio do mes', 'aplicar-tv-configuravel.sql',
       pg_temp.tenta($q$SELECT coalesce(
         (SELECT (x.p ? 'podiomes') AND (x.p ? 'emandamento')
            FROM (SELECT public.montar_painel(l.contaid, l.lojaid, true) AS p
                    FROM public.lojas l WHERE l.ativa ORDER BY l.lojaid LIMIT 1) x),
         (SELECT prosrc LIKE '%podiomes%' FROM pg_proc WHERE proname = 'montar_painel'))$q$)),
  (150, 'B2', 'versao', 'o mural esta no tablet', 'aplicar-mural-no-tablet.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'visao_mural')),
  (160, 'B2', 'versao', 'o PIN do tablet confere numa ida so', 'aplicar-pin-do-tablet-numa-ida.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'visao_pegar_com_pin')),
  (170, 'B2', 'versao', 'o dia de hoje vem de um lugar so (hoje_da_conta)', 'aplicar-hoje-da-conta.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'hoje_da_conta')),
  (180, 'B2', 'versao', 'a folha de acesso em PDF (e o codigo so no 1o acesso)', 'aplicar-folha-de-acesso.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'folha_de_acesso')),
  (190, 'ADMIN', 'versao', 'redes, anexos e codigo da empresa curto', 'aplicar-admin-clientes-e-redes.sql',
       EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'redes')),
  (200, 'ADMIN', 'versao', 'remover anexo (com registro)', 'aplicar-remover-anexo.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'anexos_admin')),
  (210, 'C1', 'versao', 'primeiro acesso tudo ou nada (senha, PIN e codigo juntos)', 'aplicar-primeiro-acesso-e-tv.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'concluir_primeiro_acesso')),
  (220, 'PESSOAS', 'versao', 'jornadas (horario de expediente com nome)', 'aplicar-jornadas.sql',
       EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'jornadas')),
  (230, 'OPERACAO', 'versao', 'quadro (historico por periodo) e intervalo cortado no fim do expediente', 'aplicar-quadro-e-intervalo.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'quadro_validacao')),
  (240, 'PESSOAS', 'versao', 'mapa da jornada (intervalo de planejamento)', 'aplicar-mapa-da-jornada.sql',
       EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'intervalosdomapa')),
  (250, 'OPERACAO', 'versao', 'tarefas do sistema viram comuns; atribuicoes com filtro', 'aplicar-tarefas-comuns-e-atribuicoes.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'atribuicoes_da_loja')),
  (260, 'OPERACAO', 'versao', 'teto de pontos por ciencia, fotos que nao mentem, saude e agenda', 'aplicar-teto-fotos-e-agenda.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'agendamentos_sem_tarefa')),
  (270, 'PESSOAS', 'versao', 'intervalo do mapa por dia da semana', 'aplicar-mapa-intervalo-por-dia.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'mapa_da_semana')),
  (280, 'OPERACAO', 'versao', 'entrega da copia de tarefa que se repete (tablet travado)', 'aplicar-entrega-da-copia.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'registrar_entrega'
                  AND p.prosrc LIKE '%vale pelo tipo da tarefa ORIGINAL%')),
  (290, 'C1', 'versao', 'entrega do celular numa ida (igual ao tablet)', 'aplicar-entrega-do-celular.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'eu_entregar_e_listar')),
  (300, 'OPERACAO', 'versao', 'contadores do menu e catalogo de tarefas numa consulta', 'aplicar-menu-e-catalogo.sql',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'catalogo_de_tarefas')),
  (310, 'OPERACAO', 'versao', 'foto da fila no fim do dia e filtro por dia do Quadro', 'aplicar-foto-da-fila.sql',
       EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'fotosdafila')),
  -- Comportamento: o "Para fazer" da TV tem o mesmo tamanho que a lista de
  -- disponíveis da fila, numa loja ativa. Sem loja: procura no código.
  (320, 'OPERACAO', 'versao', 'TV, tablet e Quadro com a mesma lista de disponiveis', 'aplicar-disponivel-uma-fonte.sql',
       pg_temp.tenta($q$SELECT coalesce(
         (SELECT jsonb_array_length(public.montar_painel(l.contaid, l.lojaid, true)->'parafazer')
                 = (SELECT count(*) FROM public.fila_de_hoje(l.contaid, l.lojaid) f WHERE f.disponivel)
            FROM public.lojas l WHERE l.ativa ORDER BY l.lojaid LIMIT 1),
         (SELECT prosrc LIKE '%fila_de_hoje(%' FROM pg_proc WHERE proname = 'montar_painel'))$q$)),
  (330, 'OPERACAO', 'versao', 'tablet mostra quem pode aceitar (a mesma regra do aceite)', 'aplicar-quem-pode-aceitar.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'pegar_tarefa') LIKE '%quem_pode_pegar(%'
       AND (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'visao_fila') LIKE '%quem_pode_aceitar(%'),
  -- Comportamento: a barra fecha (total = aprovadas + em validação + em
  -- andamento + para fazer + ainda não liberadas), numa loja ativa. Antes
  -- procurava uma palavra no código, e mandaria reaplicar este arquivo por
  -- cima da entrega seguinte (29/09/2026). Sem loja: procura no código.
  (340, 'OPERACAO', 'versao', 'a barra da TV conta o que a fila conta', 'aplicar-barra-da-fila.sql',
       pg_temp.tenta($q$SELECT coalesce(
         (SELECT (x.p->'progresso'->>'total')::integer
                 = (x.p->'progresso'->>'aprovadas')::integer + (x.p->'progresso'->>'emvalidacao')::integer
                   + (x.p->'progresso'->>'emandamento')::integer + jsonb_array_length(x.p->'parafazer')
                   + (x.p->'progresso'->>'aindanaoliberadas')::integer
            FROM (SELECT public.montar_painel(l.contaid, l.lojaid, true) AS p
                    FROM public.lojas l WHERE l.ativa ORDER BY l.lojaid LIMIT 1) x),
         (SELECT prosrc SIMILAR TO '%(aindanaoliberadas|progresso_da_fila\()%' FROM pg_proc WHERE proname = 'montar_painel'))$q$)),
  (350, 'OPERACAO', 'versao', 'TV com a faixa "Meta do mes"', 'aplicar-faixa-meta-do-mes.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'salvar_tv_da_loja') LIKE '%metames%'),
  (360, 'OPERACAO', 'versao', 'o Inicio conta as tarefas de hoje pela fila', 'aplicar-inicio-da-fila.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'painel_inicio') LIKE '%fila_da_loja(%'),
  (370, 'OPERACAO', 'versao', 'TV com a tela "Meta especial"', 'aplicar-tela-meta-especial.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'meta_para_painel') LIKE '%especial%lancado%'),
  (380, 'OPERACAO', 'versao', 'concluidas com uma conta (TV = Inicio) e aviso da venda de ontem', 'aplicar-concluidas-e-venda-de-ontem.sql',
       (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'painel_inicio') LIKE '%vendaontem%'),
  -- Comportamento: a regra dos dias sem lançamento responde, e a meta do mês
  -- de uma loja que tem meta traz "diassemlancamento". Sem loja com meta do
  -- mês: procura no código.
  (390, 'OPERACAO', 'versao', 'desempate fixo nas listas e dias sem lancamento na meta do mes', 'aplicar-desempate-e-dias-sem-lancamento.sql',
       pg_temp.tenta($q$SELECT (SELECT count(*) >= 0 FROM public.dias_sem_lancamento(0, '2000-01-01', '2000-01-01', 'America/Sao_Paulo'))
         AND coalesce(
           (SELECT (public.meta_para_painel(mp.contaid, mp.lojaid, true)->'mes') ? 'diassemlancamento'
              FROM public.metasprincipais mp
             WHERE now() BETWEEN mp.datainicio AND mp.datafim + 1 ORDER BY mp.lojaid LIMIT 1),
           (SELECT prosrc LIKE '%diassemlancamento%' FROM pg_proc WHERE proname = 'meta_para_painel'))$q$)),
  -- Comportamento: a escada do bloqueio responde 1, 3, 10 e para em 10, e a
  -- lista "toque no seu nome" responde (numa loja que não existe: vazia).
  (400, 'OPERACAO', 'versao', 'trava do PIN do tablet por pessoa (1, 3, 10 min) e liberar PIN', 'aplicar-trava-do-pin-por-pessoa.sql',
       pg_temp.tenta($q$SELECT ARRAY[public.pin_minutos_do_degrau(1), public.pin_minutos_do_degrau(2),
                                     public.pin_minutos_do_degrau(3), public.pin_minutos_do_degrau(9)] = ARRAY[1, 3, 10, 10]
                       AND public.visao_equipe_de_hoje(0, 0) = '[]'::jsonb
                       AND to_regprocedure('public.liberar_pin(integer)') IS NOT NULL$q$)),
  -- O papel "gerente" fechado: nenhuma das três portas o aceita mais. (Não dá
  -- para RODAR como um gerente daqui: o SQL Editor não tem o login dele.)
  (410, 'OPERACAO', 'versao', 'papel gerente fechado (sem conta e sem login ate existir cargo)', 'aplicar-fechar-papel-gerente.sql',
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public'
                      AND p.proname IN ('minha_conta', 'minha_conta_editavel', 'acesso_por_email')
                      AND p.prosrc LIKE '%gerente%')),
  -- Comportamento: o catálogo responde, pode() de quem não tem login é "não",
  -- e a escrita direta numa tabela sem tela foi fechada.
  (420, 'OPERACAO', 'versao', 'permissoes, parte 1: catalogo, cargos, pode() e tabelas sem tela fechadas', 'aplicar-permissoes-parte-1-base.sql',
       pg_temp.tenta($q$SELECT (SELECT count(*) > 50 FROM public.catalogo_de_permissoes())
                       AND public.pode('quadro.aprovar', 0) = false
                       AND to_regclass('public.usuarioslojas') IS NOT NULL
                       AND NOT has_table_privilege('authenticated', 'public.fornecedores', 'INSERT')$q$)),
  -- As duas travas do login do último master no lugar, e o histórico só do master.
  (430, 'OPERACAO', 'versao', 'ultimo master ATIVO (login nao se apaga nem se bloqueia) e historico so do master', 'aplicar-permissoes-parte-1-ajustes.sql',
       (SELECT count(*) = 2 FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass
                                             AND tgname IN ('stgame_ultimo_master_apagar', 'stgame_ultimo_master_bloquear'))
       AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'permissoeshistorico'
                                               AND qual LIKE '%sou_master()%')),
  -- A tabela de autores, a trava do login com atos, aprovar conferindo a
  -- permissão e a lista de estornos. (Rodar aprovar daqui gravaria.)
  (440, 'OPERACAO', 'versao', 'Quadro com permissao e loja no banco; estornos; login que ja fez algo nao se apaga', 'aplicar-permissoes-parte-2-quadro.sql',
       to_regclass('public.autores') IS NOT NULL
       AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass AND tgname = 'stgame_login_com_atos')
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'aprovar_entrega') LIKE '%pode(''quadro.aprovar''%'
       AND to_regprocedure('public.estornos_da_conta(integer)') IS NOT NULL),
  -- O catálogo de prêmios por função (e a tabela fechada) e os resgates com permissão.
  (450, 'OPERACAO', 'versao', 'Premios com permissao e loja no banco; catalogo de premios so do master, por funcao', 'aplicar-permissoes-parte-2-premios.sql',
       to_regprocedure('public.salvar_premio(text, integer, integer, text, integer)') IS NOT NULL
       AND NOT has_table_privilege('authenticated', 'public.produtosloja', 'INSERT')
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'registrar_troca') LIKE '%pode(''premios.registrar''%'),
  -- Feedbacks conferem a pessoa inteira dentro das lojas (pode_na_pessoa).
  (460, 'OPERACAO', 'versao', 'Feedbacks com permissao sobre a pessoa; anulados na lista de estornos', 'aplicar-permissoes-parte-2-feedbacks.sql',
       to_regprocedure('public.pode_na_pessoa(text, integer, integer)') IS NOT NULL
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'anular_feedback') LIKE '%pode_na_pessoa(''feedbacks.anular''%'),
  (470, 'OPERACAO', 'versao', 'Metas com permissao e loja no banco; metas da semana e especiais por funcao', 'aplicar-permissoes-parte-2-metas.sql',
       to_regprocedure('public.salvar_metas_da_semana(integer, jsonb)') IS NOT NULL
       AND NOT has_table_privilege('authenticated', 'public.metasespeciais', 'INSERT')
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'lancar_venda_do_dia') LIKE '%pode(''metas.lancar_venda''%'),
  (480, 'OPERACAO', 'versao', 'Tarefas com permissao e loja; catalogo com a regua do alcance, por funcao', 'aplicar-permissoes-parte-2-tarefas.sql',
       to_regprocedure('public.salvar_tarefa(text, integer, integer[], integer, text, text)') IS NOT NULL
       AND NOT has_table_privilege('authenticated', 'public.tarefasatribuidas', 'UPDATE')
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'atribuir_tarefa') LIKE '%pode(''tarefas.atribuir''%'),
  (490, 'OPERACAO', 'versao', 'Solicitacoes com permissao e loja no banco', 'aplicar-permissoes-parte-2-solicitacoes.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'mudar_situacao_solicitacao') LIKE '%pode(''solicitacoes.recusar''%'
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'abrir_solicitacao') LIKE '%pode(''solicitacoes.abrir''%'),
  (500, 'OPERACAO', 'versao', 'Justificativas com permissao e loja no banco', 'aplicar-permissoes-parte-2-justificativas.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'registrar_justificativa') LIKE '%pode(''justificativas.registrar''%'
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'decidir_justificativa') LIKE '%pode(''justificativas.decidir''%'),
  (510, 'OPERACAO', 'versao', 'Agenda com permissao e loja no banco', 'aplicar-permissoes-parte-2-agenda.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'alterar_pagamento_agendamento') LIKE '%pode(''agenda.pagamento''%'
       AND to_regprocedure('public.salvar_tipo_evento(text, integer)') IS NOT NULL),
  (520, 'OPERACAO', 'versao', 'Comunicados com permissao e alcance no banco', 'aplicar-permissoes-parte-2-comunicados.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'publicar_comunicado') LIKE '%pode(''comunicados.publicar''%'
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'registrar_ciencia') LIKE '%pode_na_pessoa(''comunicados.publicar''%'),
  (530, 'OPERACAO', 'versao', 'Conquistas: catalogo so do master, por funcao', 'aplicar-permissoes-parte-2-conquistas.sql',
       to_regprocedure('public.editar_conquista(integer, text, text, text, integer)') IS NOT NULL
       AND NOT has_table_privilege('authenticated', 'public.conquistas', 'UPDATE')
       AND NOT has_column_privilege('authenticated', 'public.conquistas', 'nome', 'UPDATE')),
  (540, 'OPERACAO', 'versao', 'Onboarding com permissao na pessoa; etapas so do master', 'aplicar-permissoes-parte-2-onboarding.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'iniciar_onboarding') LIKE '%pode_na_pessoa(''onboarding.conduzir''%'
       AND to_regprocedure('public.salvar_etapa_onboarding(integer, text, integer, boolean)') IS NOT NULL
       AND NOT has_column_privilege('authenticated', 'public.onboardingetapas', 'nome', 'UPDATE')),
  (550, 'OPERACAO', 'versao', 'Lojas e TV com permissao e loja no banco', 'aplicar-permissoes-parte-2-lojas.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'salvar_tv_da_loja') LIKE '%pode(''lojas.tv''%'
       AND to_regprocedure('public.editar_loja(integer, text, text, text, integer, integer)') IS NOT NULL
       AND NOT has_column_privilege('authenticated', 'public.lojas', 'nome', 'UPDATE')),
  (560, 'OPERACAO', 'versao', 'Equipe com as bordas; CPF e escrita direta fechados', 'aplicar-permissoes-parte-2-equipe.sql',
       to_regprocedure('public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[], integer[])') IS NOT NULL
       AND NOT has_column_privilege('authenticated', 'public.funcionarios', 'cpf', 'UPDATE')
       AND NOT has_table_privilege('authenticated', 'public.funcionarioslojas', 'INSERT')),
  (570, 'OPERACAO', 'versao', 'Canal e documentos pessoais: so o master, provado com gerente', 'aplicar-permissoes-parte-3-rh.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'tratar_relato') LIKE '%conta_do_gestor_editavel()%'
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'liberar_documento_pessoal') LIKE '%conta_do_gestor_editavel()%'),
  (580, 'OPERACAO', 'versao', 'Leituras do gerente: painel da loja e fila', 'aplicar-permissoes-parte-3-painel-fila.sql',
       to_regprocedure('public.conta_do_gerente()') IS NOT NULL
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'painel_da_loja') LIKE '%pode(''painel.ver''%'),
  (590, 'OPERACAO', 'versao', 'Leituras do gerente: Quadro', 'aplicar-permissoes-parte-3-quadro.sql',
       to_regprocedure('public.quadro_validacao_gerente(integer, date, date, integer)') IS NOT NULL
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'quadro_validacao') LIKE '%quadro_validacao_gerente%'),
  (595, 'OPERACAO', 'versao', 'Desempate fixo nas listas', 'aplicar-desempate-nas-listas.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'quadro_validacao') LIKE '%ORDER BY x.dataenvio, x.entregaid)%'
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'lista_do_dia_gerar') LIKE '%ORDER BY c.lojaid, c.atribuicaoid%'),
  (597, 'OPERACAO', 'versao', 'Fila: fuso e dia calculados uma vez', 'aplicar-fila-fuso-uma-vez.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'fila_no_dia') LIKE '%WITH ctx AS MATERIALIZED%'),
  (600, 'OPERACAO', 'versao', 'Leituras do gerente: Inicio e bolinhas do menu', 'aplicar-permissoes-parte-3-inicio.sql',
       to_regprocedure('public.painel_inicio_gerente(integer)') IS NOT NULL
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'contagem_do_menu') LIKE '%contagem_do_menu_gerente%'),
  (610, 'OPERACAO', 'versao', 'Leituras do gerente: Relatorios', 'aplicar-permissoes-parte-3-relatorios.sql',
       to_regprocedure('public.pendencias_da_pessoa_gerente(integer, date, date)') IS NOT NULL
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'historico_da_pessoa') LIKE '%historico_da_pessoa_gerente%'),
  (620, 'OPERACAO', 'versao', 'Leituras do gerente: Metas', 'aplicar-permissoes-parte-3-metas.sql',
       to_regprocedure('public.metas_do_mes_gerente(integer, date)') IS NOT NULL
       AND (SELECT prosrc FROM pg_proc WHERE proname = 'metas_do_mes') LIKE '%metas_do_mes_gerente%'),
  (625, 'OPERACAO', 'versao', 'Lojas do gerente calculadas uma vez por leitura', 'aplicar-lojas-do-gerente-uma-vez.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'contagem_do_menu_gerente') LIKE '%(SELECT public.lojas_onde_posso(''premios.ver''))::integer[]%'),
  (630, 'OPERACAO', 'versao', 'Porta do gerente: seletor de loja e menu', 'aplicar-parte-4-porta-do-gerente.sql',
       to_regprocedure('public.minhas_lojas()') IS NOT NULL AND to_regprocedure('public.minhas_permissoes()') IS NOT NULL),
  (640, 'OPERACAO', 'versao', 'Ninguem gera pontos para si mesmo (comunicado)', 'aplicar-ninguem-gera-pontos-para-si.sql',
       (SELECT prosrc FROM pg_proc WHERE proname = 'incluir_destinatarios') LIKE '%ninguém gera pontos para si%')
),
tudo AS (
  SELECT x.*, a.versao
    FROM (SELECT ordem, parte, tipo, nome, arquivo, tem FROM situacao
          UNION ALL
          SELECT ordem, parte, tipo, nome, arquivo, tem FROM versao) x
    LEFT JOIN arquivos a ON a.arquivo = x.arquivo
),
-- O arquivo mais novo que JÁ está aplicado (alguma conferência dele passou).
aplicado AS (
  SELECT t.arquivo, t.versao FROM tudo t WHERE t.tem AND t.versao IS NOT NULL
   ORDER BY t.versao DESC LIMIT 1
)
SELECT CASE WHEN t.tem THEN 'ok' ELSE '>>> FALTA' END AS "situacao",
       t.parte AS "parte", t.tipo AS "tipo", t.nome AS "nome",
       CASE WHEN t.tem THEN ''
            -- Arquivo sem data conhecida, ou MAIS VELHO que o mais novo já
            -- aplicado: rodar desfaria a entrega mais recente.
            WHEN t.versao IS NULL OR t.versao < (SELECT versao FROM aplicado)
            THEN 'NÃO rode ' || t.arquivo || ': já está aplicado um arquivo mais novo ('
                 || (SELECT arquivo FROM aplicado) || '). Rodar este desfaria a entrega mais recente. Chame o Claude.'
            ELSE 'rode ' || t.arquivo END AS "o que fazer"
  FROM tudo t
 ORDER BY t.tem, t.ordem;
