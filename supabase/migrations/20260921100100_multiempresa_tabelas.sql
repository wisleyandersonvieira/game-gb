-- Fase 2.2: contaid/lojaid em todas as tabelas, vinculos funcionario-loja e
-- tarefa-loja, chaves e unicidades por conta/loja.
-- Gerada por script a partir da classificacao aprovada. Ver docs/DICIONARIO_BANCO.md.

-- 1. O login do painel Flask antigo foi substituido pelo Supabase Auth.
DROP TABLE IF EXISTS public.usuariosadmin;

-- 2. Derruba TODAS as chaves estrangeiras atuais do schema public.
--    Elas voltam adiante como compostas, carregando o contaid junto.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass AS tabela, c.conname AS nome
    FROM pg_constraint c
    JOIN pg_namespace n ON n.oid = c.connamespace
    WHERE c.contype = 'f' AND n.nspname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tabela, r.nome);
  END LOOP;
END $$;

-- 3. O lugar padrao no mapa passa a ser por loja (vai para funcionarioslojas).
ALTER TABLE public.funcionarios DROP COLUMN posicaopadraoid;

-- 4. As 18 linhas de configuracoes semeadas na Fase 1 nao pertencem a conta
--    nenhuma. Os valores passam para uma funcao, que a Fase 4 chama ao criar
--    cada conta nova. A funcao que faz isso e criada no fim desta migracao.

DELETE FROM public.configuracoes;

-- 5. contaid em todas as tabelas. O padrao minha_conta() faz o banco preencher,
--    para o navegador nunca precisar mandar (nem ser acreditado se mandar).
ALTER TABLE public.agendamentos ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.categoriasproduto ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.configuracoes ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.configuracoesescala ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.configuracoessetores ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.conquistas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.conquistasfuncionarios ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.contagensestoque ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.denunciasanonimas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.documentos ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.documentosassinaturas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.documentospessoais ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.documentospessoaisciencia ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.entregas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.escaladiaria ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.feedbacks ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.feedbacksolicitacoes ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.fornecedores ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.freelancers ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.funcionarios ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.funcionariosgrupos ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.grupos ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.historicoranking ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.itenscontagemestoque ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.itensnotafiscalentrada ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.lucromensalhistorico ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasapuracoes ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasinstancias ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasmodelos ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.metasprincipais ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.notasfiscais ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.notasfiscaisentrada ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.onboardingstatus ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.picodiario ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.posicoesloja ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.produtosestoque ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.produtosfornecedor ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.produtosloja ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.resgates ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.solicitacoesinternas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.tarefas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD COLUMN contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT;

-- 6. lojaid nas tabelas de nivel loja, amarrado a mesma conta.
ALTER TABLE public.agendamentos ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.agendamentos ADD CONSTRAINT agendamentos_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.configuracoesescala ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.configuracoesescala ADD CONSTRAINT configuracoesescala_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.contagensestoque ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.contagensestoque ADD CONSTRAINT contagensestoque_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.entregas ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.escaladiaria ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.escaladiaria ADD CONSTRAINT escaladiaria_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.funcionariosgrupos ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.funcionariosgrupos ADD CONSTRAINT funcionariosgrupos_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.grupos ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.grupos ADD CONSTRAINT grupos_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.historicoranking ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.historicoranking ADD CONSTRAINT historicoranking_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.itenscontagemestoque ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.itenscontagemestoque ADD CONSTRAINT itenscontagemestoque_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.itensnotafiscalentrada ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.itensnotafiscalentrada ADD CONSTRAINT itensnotafiscalentrada_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.lucromensalhistorico ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.lucromensalhistorico ADD CONSTRAINT lucromensalhistorico_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasapuracoes ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.metasdiariasapuracoes ADD CONSTRAINT metasdiariasapuracoes_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasinstancias ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.metasdiariasinstancias ADD CONSTRAINT metasdiariasinstancias_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasmodelos ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.metasdiariasmodelos ADD CONSTRAINT metasdiariasmodelos_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.metasprincipais ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.metasprincipais ADD CONSTRAINT metasprincipais_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.notasfiscais ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.notasfiscais ADD CONSTRAINT notasfiscais_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.notasfiscaisentrada ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.notasfiscaisentrada ADD CONSTRAINT notasfiscaisentrada_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.picodiario ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.picodiario ADD CONSTRAINT picodiario_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.posicoesloja ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.posicoesloja ADD CONSTRAINT posicoesloja_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.solicitacoesinternas ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD COLUMN lojaid integer NOT NULL;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;

-- Resgate guarda, opcionalmente, em qual loja o premio foi retirado.
ALTER TABLE public.resgates ADD COLUMN lojaid integer;
ALTER TABLE public.resgates ADD CONSTRAINT resgates_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;

-- 7. Chaves primarias que eram globais passam a ser por conta / por loja.
ALTER TABLE public.configuracoes DROP CONSTRAINT configuracoes_pkey;
ALTER TABLE public.configuracoes ADD PRIMARY KEY (contaid, chave);
ALTER TABLE public.configuracoessetores DROP CONSTRAINT configuracoessetores_pkey;
ALTER TABLE public.configuracoessetores ADD PRIMARY KEY (contaid, setor);
ALTER TABLE public.metasdiariasmodelos DROP CONSTRAINT metasdiariasmodelos_pkey;
ALTER TABLE public.metasdiariasmodelos ADD PRIMARY KEY (lojaid, diasemanaid);
ALTER TABLE public.picodiario DROP CONSTRAINT picodiario_pkey;
ALTER TABLE public.picodiario ADD PRIMARY KEY (lojaid, diasemanaid);

-- 8. Alvos das chaves estrangeiras compostas: (contaid, chave) em cada tabela.
ALTER TABLE public.agendamentos ADD CONSTRAINT agendamentos_conta_unico UNIQUE (contaid, agendamentoid);
ALTER TABLE public.categoriasproduto ADD CONSTRAINT categoriasproduto_conta_unico UNIQUE (contaid, categoriaid);
ALTER TABLE public.configuracoesescala ADD CONSTRAINT configuracoesescala_conta_unico UNIQUE (contaid, configid);
ALTER TABLE public.conquistas ADD CONSTRAINT conquistas_conta_unico UNIQUE (contaid, conquistaid);
ALTER TABLE public.conquistasfuncionarios ADD CONSTRAINT conquistasfuncionarios_conta_unico UNIQUE (contaid, conquistafuncionarioid);
ALTER TABLE public.contagensestoque ADD CONSTRAINT contagensestoque_conta_unico UNIQUE (contaid, contagemid);
ALTER TABLE public.denunciasanonimas ADD CONSTRAINT denunciasanonimas_conta_unico UNIQUE (contaid, denunciaid);
ALTER TABLE public.documentos ADD CONSTRAINT documentos_conta_unico UNIQUE (contaid, documentoid);
ALTER TABLE public.documentosassinaturas ADD CONSTRAINT documentosassinaturas_conta_unico UNIQUE (contaid, assinaturaid);
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_conta_unico UNIQUE (contaid, documentoid);
ALTER TABLE public.documentospessoaisciencia ADD CONSTRAINT documentospessoaisciencia_conta_unico UNIQUE (contaid, cienciaid);
ALTER TABLE public.entregas ADD CONSTRAINT entregas_conta_unico UNIQUE (contaid, entregaid);
ALTER TABLE public.escaladiaria ADD CONSTRAINT escaladiaria_conta_unico UNIQUE (contaid, escalaid);
ALTER TABLE public.feedbacks ADD CONSTRAINT feedbacks_conta_unico UNIQUE (contaid, feedbackid);
ALTER TABLE public.feedbacksolicitacoes ADD CONSTRAINT feedbacksolicitacoes_conta_unico UNIQUE (contaid, solicitacaoid);
ALTER TABLE public.fornecedores ADD CONSTRAINT fornecedores_conta_unico UNIQUE (contaid, fornecedorid);
ALTER TABLE public.freelancers ADD CONSTRAINT freelancers_conta_unico UNIQUE (contaid, freelancerid);
ALTER TABLE public.funcionarios ADD CONSTRAINT funcionarios_conta_unico UNIQUE (contaid, funcionarioid);
ALTER TABLE public.grupos ADD CONSTRAINT grupos_conta_unico UNIQUE (contaid, grupoid);
ALTER TABLE public.historicoranking ADD CONSTRAINT historicoranking_conta_unico UNIQUE (contaid, historicoid);
ALTER TABLE public.itenscontagemestoque ADD CONSTRAINT itenscontagemestoque_conta_unico UNIQUE (contaid, itemcontagemid);
ALTER TABLE public.itensnotafiscalentrada ADD CONSTRAINT itensnotafiscalentrada_conta_unico UNIQUE (contaid, itemnotaid);
ALTER TABLE public.lucromensalhistorico ADD CONSTRAINT lucromensalhistorico_conta_unico UNIQUE (contaid, historicoid);
ALTER TABLE public.metasdiariasapuracoes ADD CONSTRAINT metasdiariasapuracoes_conta_unico UNIQUE (contaid, apuracaoid);
ALTER TABLE public.metasdiariasinstancias ADD CONSTRAINT metasdiariasinstancias_conta_unico UNIQUE (contaid, metainstanciaid);
ALTER TABLE public.metasdiariasmodelos ADD CONSTRAINT metasdiariasmodelos_conta_unico UNIQUE (contaid, diasemanaid);
ALTER TABLE public.metasprincipais ADD CONSTRAINT metasprincipais_conta_unico UNIQUE (contaid, metaprincipalid);
ALTER TABLE public.notasfiscais ADD CONSTRAINT notasfiscais_conta_unico UNIQUE (contaid, notafiscalid);
ALTER TABLE public.notasfiscaisentrada ADD CONSTRAINT notasfiscaisentrada_conta_unico UNIQUE (contaid, notaid);
ALTER TABLE public.onboardingstatus ADD CONSTRAINT onboardingstatus_conta_unico UNIQUE (contaid, funcionarioid);
ALTER TABLE public.picodiario ADD CONSTRAINT picodiario_conta_unico UNIQUE (contaid, diasemanaid);
ALTER TABLE public.posicoesloja ADD CONSTRAINT posicoesloja_conta_unico UNIQUE (contaid, posicaoid);
ALTER TABLE public.produtosestoque ADD CONSTRAINT produtosestoque_conta_unico UNIQUE (contaid, produtoid);
ALTER TABLE public.produtosfornecedor ADD CONSTRAINT produtosfornecedor_conta_unico UNIQUE (contaid, produtofornecedorid);
ALTER TABLE public.produtosloja ADD CONSTRAINT produtosloja_conta_unico UNIQUE (contaid, produtoid);
ALTER TABLE public.resgates ADD CONSTRAINT resgates_conta_unico UNIQUE (contaid, resgateid);
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_conta_unico UNIQUE (contaid, solicitacaoid);
ALTER TABLE public.tarefas ADD CONSTRAINT tarefas_conta_unico UNIQUE (contaid, tarefaid);
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_conta_unico UNIQUE (contaid, atribuicaoid);
ALTER TABLE public.funcionariosgrupos ADD CONSTRAINT funcionariosgrupos_conta_unico UNIQUE (contaid, funcionarioid, grupoid);
-- posicao identificada dentro da loja (usada pelo lugar padrao do funcionario)
ALTER TABLE public.posicoesloja ADD CONSTRAINT posicoesloja_loja_unico UNIQUE (lojaid, posicaoid);

-- 9. Vinculos funcionario-loja e tarefa-loja.
--    Tirar alguem de uma loja = ativo = false. Nunca apagar: ON DELETE RESTRICT
--    nas FKs que apontam para ca preserva o historico.
CREATE TABLE public.funcionarioslojas (
  contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  funcionarioid integer NOT NULL,
  lojaid integer NOT NULL,
  posicaopadraoid integer,
  ativo boolean NOT NULL DEFAULT true,
  criadoem timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (funcionarioid, lojaid),
  UNIQUE (contaid, funcionarioid, lojaid),
  FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT,
  -- o lugar padrao tem que ser uma posicao do mapa daquela mesma loja
  FOREIGN KEY (lojaid, posicaopadraoid) REFERENCES public.posicoesloja (lojaid, posicaoid) ON DELETE RESTRICT
);

CREATE TABLE public.tarefaslojas (
  contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  tarefaid integer NOT NULL,
  lojaid integer NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  criadoem timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tarefaid, lojaid),
  UNIQUE (contaid, tarefaid, lojaid),
  FOREIGN KEY (contaid, tarefaid) REFERENCES public.tarefas (contaid, tarefaid) ON DELETE RESTRICT,
  FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);

-- 10. As 39 chaves estrangeiras de volta, agora compostas com o contaid.
--    Como as duas pontas leem o MESMO contaid da mesma linha, e impossivel
--    apontar para um registro de outra conta.
ALTER TABLE public.agendamentos ADD CONSTRAINT agendamentos_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.conquistasfuncionarios ADD CONSTRAINT conquistasfuncionarios_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.conquistasfuncionarios ADD CONSTRAINT conquistasfuncionarios_conquistaid_fk FOREIGN KEY (contaid, conquistaid) REFERENCES public.conquistas (contaid, conquistaid) ON DELETE RESTRICT;
ALTER TABLE public.contagensestoque ADD CONSTRAINT contagensestoque_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.documentos ADD CONSTRAINT documentos_funcionariocriadorid_fk FOREIGN KEY (contaid, funcionariocriadorid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.documentosassinaturas ADD CONSTRAINT documentosassinaturas_documentoid_fk FOREIGN KEY (contaid, documentoid) REFERENCES public.documentos (contaid, documentoid) ON DELETE RESTRICT;
ALTER TABLE public.documentosassinaturas ADD CONSTRAINT documentosassinaturas_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.documentospessoaisciencia ADD CONSTRAINT documentospessoaisciencia_documentoid_fk FOREIGN KEY (contaid, documentoid) REFERENCES public.documentospessoais (contaid, documentoid) ON DELETE RESTRICT;
ALTER TABLE public.documentospessoaisciencia ADD CONSTRAINT documentospessoaisciencia_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_tarefaid_fk FOREIGN KEY (contaid, tarefaid) REFERENCES public.tarefas (contaid, tarefaid) ON DELETE RESTRICT;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.escaladiaria ADD CONSTRAINT escaladiaria_posicaoid_fk FOREIGN KEY (contaid, posicaoid) REFERENCES public.posicoesloja (contaid, posicaoid) ON DELETE RESTRICT;
ALTER TABLE public.escaladiaria ADD CONSTRAINT escaladiaria_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.escaladiaria ADD CONSTRAINT escaladiaria_freelancerid_fk FOREIGN KEY (contaid, freelancerid) REFERENCES public.freelancers (contaid, freelancerid) ON DELETE RESTRICT;
ALTER TABLE public.feedbacks ADD CONSTRAINT feedbacks_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.feedbacksolicitacoes ADD CONSTRAINT feedbacksolicitacoes_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.funcionariosgrupos ADD CONSTRAINT funcionariosgrupos_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.funcionariosgrupos ADD CONSTRAINT funcionariosgrupos_grupoid_fk FOREIGN KEY (contaid, grupoid) REFERENCES public.grupos (contaid, grupoid) ON DELETE RESTRICT;
ALTER TABLE public.historicoranking ADD CONSTRAINT historicoranking_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.itenscontagemestoque ADD CONSTRAINT itenscontagemestoque_contagemid_fk FOREIGN KEY (contaid, contagemid) REFERENCES public.contagensestoque (contaid, contagemid) ON DELETE RESTRICT;
ALTER TABLE public.itenscontagemestoque ADD CONSTRAINT itenscontagemestoque_produtoid_fk FOREIGN KEY (contaid, produtoid) REFERENCES public.produtosestoque (contaid, produtoid) ON DELETE RESTRICT;
ALTER TABLE public.itensnotafiscalentrada ADD CONSTRAINT itensnotafiscalentrada_notaid_fk FOREIGN KEY (contaid, notaid) REFERENCES public.notasfiscaisentrada (contaid, notaid) ON DELETE RESTRICT;
ALTER TABLE public.itensnotafiscalentrada ADD CONSTRAINT itensnotafiscalentrada_produtofornecedorid_fk FOREIGN KEY (contaid, produtofornecedorid) REFERENCES public.produtosfornecedor (contaid, produtofornecedorid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasapuracoes ADD CONSTRAINT metasdiariasapuracoes_metaprincipalid_fk FOREIGN KEY (contaid, metaprincipalid) REFERENCES public.metasprincipais (contaid, metaprincipalid) ON DELETE RESTRICT;
ALTER TABLE public.metasdiariasapuracoes ADD CONSTRAINT metasdiariasapuracoes_funcionarioid_lancamento_fk FOREIGN KEY (contaid, funcionarioid_lancamento) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.notasfiscais ADD CONSTRAINT notasfiscais_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.notasfiscaisentrada ADD CONSTRAINT notasfiscaisentrada_fornecedorid_fk FOREIGN KEY (contaid, fornecedorid) REFERENCES public.fornecedores (contaid, fornecedorid) ON DELETE RESTRICT;
ALTER TABLE public.onboardingstatus ADD CONSTRAINT onboardingstatus_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.produtosfornecedor ADD CONSTRAINT produtosfornecedor_produtoid_fk FOREIGN KEY (contaid, produtoid) REFERENCES public.produtosestoque (contaid, produtoid) ON DELETE RESTRICT;
ALTER TABLE public.produtosfornecedor ADD CONSTRAINT produtosfornecedor_fornecedorid_fk FOREIGN KEY (contaid, fornecedorid) REFERENCES public.fornecedores (contaid, fornecedorid) ON DELETE RESTRICT;
ALTER TABLE public.resgates ADD CONSTRAINT resgates_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.resgates ADD CONSTRAINT resgates_produtoid_fk FOREIGN KEY (contaid, produtoid) REFERENCES public.produtosloja (contaid, produtoid) ON DELETE RESTRICT;
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_tarefaid_fk FOREIGN KEY (contaid, tarefaid) REFERENCES public.tarefas (contaid, tarefaid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_funcionarioid_fk FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_grupoid_fk FOREIGN KEY (contaid, grupoid) REFERENCES public.grupos (contaid, grupoid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_funcionarioresponsavelid_fk FOREIGN KEY (contaid, funcionarioresponsavelid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_origematribuicaoid_fk FOREIGN KEY (contaid, origematribuicaoid) REFERENCES public.tarefasatribuidas (contaid, atribuicaoid) ON DELETE RESTRICT;

-- 11. Regra do plano: so atribuir tarefa a quem trabalha numa loja onde a
--     tarefa vale. Garantida pela estrutura, nao pela tela.
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_funcionario_na_loja_fk
  FOREIGN KEY (funcionarioid, lojaid) REFERENCES public.funcionarioslojas (funcionarioid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_tarefa_na_loja_fk
  FOREIGN KEY (tarefaid, lojaid) REFERENCES public.tarefaslojas (tarefaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_funcionario_na_loja_fk
  FOREIGN KEY (funcionarioid, lojaid) REFERENCES public.funcionarioslojas (funcionarioid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.escaladiaria ADD CONSTRAINT escaladiaria_funcionario_na_loja_fk
  FOREIGN KEY (funcionarioid, lojaid) REFERENCES public.funcionarioslojas (funcionarioid, lojaid) ON DELETE RESTRICT;

-- 12. Unicidades, agora por conta ou por loja (nunca globais).
CREATE UNIQUE INDEX fornecedores_cnpj_por_conta ON public.fornecedores (contaid, cnpj);
CREATE UNIQUE INDEX conquistas_nome_por_conta ON public.conquistas (contaid, lower(nome));
CREATE UNIQUE INDEX categoriasproduto_nome_por_conta ON public.categoriasproduto (contaid, lower(nomecategoria));
CREATE UNIQUE INDEX grupos_nome_por_loja ON public.grupos (lojaid, lower(nomegrupo));
CREATE UNIQUE INDEX feedbacks_um_por_dia ON public.feedbacks (funcionarioid, datafeedback);
CREATE UNIQUE INDEX metasdiariasapuracoes_um_por_dia ON public.metasdiariasapuracoes (metaprincipalid, dataapuracao);
CREATE UNIQUE INDEX lucromensalhistorico_um_por_mes ON public.lucromensalhistorico (lojaid, ano, mes);
CREATE UNIQUE INDEX historicoranking_um_por_mes ON public.historicoranking (lojaid, ano, mes, funcionarioid);
CREATE UNIQUE INDEX configuracoesescala_uma_por_loja ON public.configuracoesescala (lojaid);
CREATE UNIQUE INDEX produtosfornecedor_depara ON public.produtosfornecedor (fornecedorid, lower(descricaoxml));
-- EAN: o legado grava o texto 'SEM EAN' quando o produto nao tem codigo de
-- barras, entao a unicidade precisa ignorar esse marcador e os nulos.
CREATE UNIQUE INDEX produtosfornecedor_ean_por_conta ON public.produtosfornecedor (contaid, ean)
  WHERE ean IS NOT NULL AND upper(ean) <> 'SEM EAN';
-- chat de grupo do Telegram: unico no sistema inteiro, porque um unico bot
-- atende todas as contas e precisa saber de quem e a mensagem (Fase 15).
CREATE UNIQUE INDEX grupos_chatidtelegram_global ON public.grupos (chatidtelegram) WHERE chatidtelegram IS NOT NULL;
-- chat da pessoa: unico so dentro da conta. A mesma pessoa pode trabalhar
-- para duas empresas clientes diferentes. Ver Fase 15 no plano.
CREATE UNIQUE INDEX funcionarios_chatidtelegram_por_conta ON public.funcionarios (contaid, chatidtelegram) WHERE chatidtelegram IS NOT NULL;

-- 13. Semeia as configuracoes de uma conta nova (chamada na Fase 4).
CREATE OR REPLACE FUNCTION public.cria_configuracoes_padrao(p_contaid integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  INSERT INTO public.configuracoes (contaid, chave, valor, descricao) VALUES
    (p_contaid, 'TAXA_CONVERSAO_PONTO_REAL',     '0.03',  'Quanto vale 1 ponto em reais.'),
    (p_contaid, 'PONTOS_BONUS_FEEDBACK_DIARIO',  '5',     'Pontos de bonus por enviar o feedback do dia.'),
    (p_contaid, 'PONTOS_BONUS_NOTA_FISCAL',      '10',    'Pontos de bonus por enviar uma nota fiscal.'),
    (p_contaid, 'MAX_DIFERENCA_FOTO_SEGUNDOS',   '120',   'Tolerancia, em segundos, entre a hora da foto (EXIF) e o envio.'),
    (p_contaid, 'HORARIO_FECHAMENTO_MENSAL',     '08:00', 'Hora do fechamento mensal do ranking (executa no dia 1).'),
    (p_contaid, 'HORARIO_DELEGACAO_FOLGA',       '09:05', 'Hora da delegacao automatica das tarefas de quem esta de folga.'),
    (p_contaid, 'HORARIO_LEMBRETE_COMUNICADOS',  '09:00', 'Hora do lembrete de comunicados pendentes de leitura.'),
    (p_contaid, 'HORARIO_LEMBRETE_HOJE',         '08:00', 'Hora do lembrete dos agendamentos de hoje.'),
    (p_contaid, 'HORARIO_LEMBRETE_DIARIO_AMANHA','09:00', 'Hora do lembrete dos agendamentos de amanha.'),
    (p_contaid, 'HORARIO_LEMBRETE_SEMANAL',      '08:00', 'Hora do lembrete semanal de agendamentos.'),
    (p_contaid, 'TAREFA_ID_FEEDBACK_DIARIO',           '', 'ID da tarefa de feedback diario. Preenchido ao recadastrar.'),
    (p_contaid, 'TAREFA_ID_LEITURA',                   '', 'ID da tarefa de leitura de comunicado. Preenchido ao recadastrar.'),
    (p_contaid, 'TAREFA_MODELO_AGENDAMENTO_ID',        '', 'ID da tarefa modelo usada ao criar um agendamento.'),
    (p_contaid, 'TAREFA_ID_PONTOS_META',               '', 'ID da tarefa que credita os pontos da meta diaria.'),
    (p_contaid, 'TAREFA_ID_NOTA_FISCAL',               '', 'ID da tarefa de envio de nota fiscal.'),
    (p_contaid, 'TAREFA_ID_GUARDAR_MERCADORIA_MODELO', '', 'ID da tarefa modelo de guardar mercadoria.'),
    (p_contaid, 'ID_GESTOR_PADRAO',                    '', 'ID do funcionario gestor padrao.'),
    (p_contaid, 'RESPONSAVEL_AGENDAMENTOS_ID',         '', 'ID do funcionario responsavel pelos agendamentos.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

-- 13. Indices nas colunas de conta/loja, usadas por toda policy de RLS.
CREATE INDEX agendamentos_contaid_idx ON public.agendamentos (contaid);
CREATE INDEX categoriasproduto_contaid_idx ON public.categoriasproduto (contaid);
CREATE INDEX configuracoes_contaid_idx ON public.configuracoes (contaid);
CREATE INDEX configuracoesescala_contaid_idx ON public.configuracoesescala (contaid);
CREATE INDEX configuracoessetores_contaid_idx ON public.configuracoessetores (contaid);
CREATE INDEX conquistas_contaid_idx ON public.conquistas (contaid);
CREATE INDEX conquistasfuncionarios_contaid_idx ON public.conquistasfuncionarios (contaid);
CREATE INDEX contagensestoque_contaid_idx ON public.contagensestoque (contaid);
CREATE INDEX denunciasanonimas_contaid_idx ON public.denunciasanonimas (contaid);
CREATE INDEX documentos_contaid_idx ON public.documentos (contaid);
CREATE INDEX documentosassinaturas_contaid_idx ON public.documentosassinaturas (contaid);
CREATE INDEX documentospessoais_contaid_idx ON public.documentospessoais (contaid);
CREATE INDEX documentospessoaisciencia_contaid_idx ON public.documentospessoaisciencia (contaid);
CREATE INDEX entregas_contaid_idx ON public.entregas (contaid);
CREATE INDEX escaladiaria_contaid_idx ON public.escaladiaria (contaid);
CREATE INDEX feedbacks_contaid_idx ON public.feedbacks (contaid);
CREATE INDEX feedbacksolicitacoes_contaid_idx ON public.feedbacksolicitacoes (contaid);
CREATE INDEX fornecedores_contaid_idx ON public.fornecedores (contaid);
CREATE INDEX freelancers_contaid_idx ON public.freelancers (contaid);
CREATE INDEX funcionarios_contaid_idx ON public.funcionarios (contaid);
CREATE INDEX funcionariosgrupos_contaid_idx ON public.funcionariosgrupos (contaid);
CREATE INDEX grupos_contaid_idx ON public.grupos (contaid);
CREATE INDEX historicoranking_contaid_idx ON public.historicoranking (contaid);
CREATE INDEX itenscontagemestoque_contaid_idx ON public.itenscontagemestoque (contaid);
CREATE INDEX itensnotafiscalentrada_contaid_idx ON public.itensnotafiscalentrada (contaid);
CREATE INDEX lucromensalhistorico_contaid_idx ON public.lucromensalhistorico (contaid);
CREATE INDEX metasdiariasapuracoes_contaid_idx ON public.metasdiariasapuracoes (contaid);
CREATE INDEX metasdiariasinstancias_contaid_idx ON public.metasdiariasinstancias (contaid);
CREATE INDEX metasdiariasmodelos_contaid_idx ON public.metasdiariasmodelos (contaid);
CREATE INDEX metasprincipais_contaid_idx ON public.metasprincipais (contaid);
CREATE INDEX notasfiscais_contaid_idx ON public.notasfiscais (contaid);
CREATE INDEX notasfiscaisentrada_contaid_idx ON public.notasfiscaisentrada (contaid);
CREATE INDEX onboardingstatus_contaid_idx ON public.onboardingstatus (contaid);
CREATE INDEX picodiario_contaid_idx ON public.picodiario (contaid);
CREATE INDEX posicoesloja_contaid_idx ON public.posicoesloja (contaid);
CREATE INDEX produtosestoque_contaid_idx ON public.produtosestoque (contaid);
CREATE INDEX produtosfornecedor_contaid_idx ON public.produtosfornecedor (contaid);
CREATE INDEX produtosloja_contaid_idx ON public.produtosloja (contaid);
CREATE INDEX resgates_contaid_idx ON public.resgates (contaid);
CREATE INDEX solicitacoesinternas_contaid_idx ON public.solicitacoesinternas (contaid);
CREATE INDEX tarefas_contaid_idx ON public.tarefas (contaid);
CREATE INDEX tarefasatribuidas_contaid_idx ON public.tarefasatribuidas (contaid);
CREATE INDEX agendamentos_lojaid_idx ON public.agendamentos (lojaid);
CREATE INDEX configuracoesescala_lojaid_idx ON public.configuracoesescala (lojaid);
CREATE INDEX contagensestoque_lojaid_idx ON public.contagensestoque (lojaid);
CREATE INDEX entregas_lojaid_idx ON public.entregas (lojaid);
CREATE INDEX escaladiaria_lojaid_idx ON public.escaladiaria (lojaid);
CREATE INDEX funcionariosgrupos_lojaid_idx ON public.funcionariosgrupos (lojaid);
CREATE INDEX grupos_lojaid_idx ON public.grupos (lojaid);
CREATE INDEX historicoranking_lojaid_idx ON public.historicoranking (lojaid);
CREATE INDEX itenscontagemestoque_lojaid_idx ON public.itenscontagemestoque (lojaid);
CREATE INDEX itensnotafiscalentrada_lojaid_idx ON public.itensnotafiscalentrada (lojaid);
CREATE INDEX lucromensalhistorico_lojaid_idx ON public.lucromensalhistorico (lojaid);
CREATE INDEX metasdiariasapuracoes_lojaid_idx ON public.metasdiariasapuracoes (lojaid);
CREATE INDEX metasdiariasinstancias_lojaid_idx ON public.metasdiariasinstancias (lojaid);
CREATE INDEX metasdiariasmodelos_lojaid_idx ON public.metasdiariasmodelos (lojaid);
CREATE INDEX metasprincipais_lojaid_idx ON public.metasprincipais (lojaid);
CREATE INDEX notasfiscais_lojaid_idx ON public.notasfiscais (lojaid);
CREATE INDEX notasfiscaisentrada_lojaid_idx ON public.notasfiscaisentrada (lojaid);
CREATE INDEX picodiario_lojaid_idx ON public.picodiario (lojaid);
CREATE INDEX posicoesloja_lojaid_idx ON public.posicoesloja (lojaid);
CREATE INDEX solicitacoesinternas_lojaid_idx ON public.solicitacoesinternas (lojaid);
CREATE INDEX tarefasatribuidas_lojaid_idx ON public.tarefasatribuidas (lojaid);
