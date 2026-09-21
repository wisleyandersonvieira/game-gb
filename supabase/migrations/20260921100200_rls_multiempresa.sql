-- Fase 2.3: isolamento entre contas (RLS).
-- Nenhuma policy USING (true) sobrevive a esta migracao.
-- minha_conta() vem envolvido em (select ...) porque assim o Postgres avalia
-- a funcao uma vez por consulta, em vez de uma vez por linha.

-- 1. Remove as policies provisorias da Fase 1, inclusive as do Storage.
--    Policies se SOMAM: deixar uma antiga para tras abriria o isolamento.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname IN ('public', 'storage')
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

-- 2. Permissoes e RLS nas tabelas novas.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contas TO authenticated;
GRANT ALL ON public.contas TO service_role;
ALTER TABLE public.contas ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contasusuarios TO authenticated;
GRANT ALL ON public.contasusuarios TO service_role;
ALTER TABLE public.contasusuarios ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lojas TO authenticated;
GRANT ALL ON public.lojas TO service_role;
ALTER TABLE public.lojas ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.funcionarioslojas TO authenticated;
GRANT ALL ON public.funcionarioslojas TO service_role;
ALTER TABLE public.funcionarioslojas ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tarefaslojas TO authenticated;
GRANT ALL ON public.tarefaslojas TO service_role;
ALTER TABLE public.tarefaslojas ENABLE ROW LEVEL SECURITY;

-- 3. contas e contasusuarios: o administrador geral cuida do cadastro;
--    o master so enxerga a propria conta e nao se auto-promove.
CREATE POLICY contas_admin_tudo ON public.contas FOR ALL TO authenticated
  USING ((select public.eh_admin_geral())) WITH CHECK ((select public.eh_admin_geral()));
CREATE POLICY contas_master_le ON public.contas FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));
CREATE POLICY contasusuarios_admin_tudo ON public.contasusuarios FOR ALL TO authenticated
  USING ((select public.eh_admin_geral())) WITH CHECK ((select public.eh_admin_geral()));
CREATE POLICY contasusuarios_master_le ON public.contasusuarios FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- 4. O admin geral le as lojas para contar 'X de Y usadas' no painel dele,
--    mas nao alcanca nenhum dado operacional dos clientes.
CREATE POLICY lojas_admin_le ON public.lojas FOR SELECT TO authenticated
  USING ((select public.eh_admin_geral()));

-- 5. Isolamento por conta em todas as tabelas de dados.
--    Leitura: a conta do usuario. Escrita: so se a conta estiver ativa
--    (conta suspensa fica somente leitura).
CREATE POLICY agendamentos_sel ON public.agendamentos FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY agendamentos_ins ON public.agendamentos FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY agendamentos_upd ON public.agendamentos FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY agendamentos_del ON public.agendamentos FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY categoriasproduto_sel ON public.categoriasproduto FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY categoriasproduto_ins ON public.categoriasproduto FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY categoriasproduto_upd ON public.categoriasproduto FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY categoriasproduto_del ON public.categoriasproduto FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoes_sel ON public.configuracoes FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY configuracoes_ins ON public.configuracoes FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoes_upd ON public.configuracoes FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoes_del ON public.configuracoes FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoesescala_sel ON public.configuracoesescala FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY configuracoesescala_ins ON public.configuracoesescala FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoesescala_upd ON public.configuracoesescala FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoesescala_del ON public.configuracoesescala FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoessetores_sel ON public.configuracoessetores FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY configuracoessetores_ins ON public.configuracoessetores FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoessetores_upd ON public.configuracoessetores FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY configuracoessetores_del ON public.configuracoessetores FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY conquistas_sel ON public.conquistas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY conquistas_ins ON public.conquistas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY conquistas_upd ON public.conquistas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY conquistas_del ON public.conquistas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY conquistasfuncionarios_sel ON public.conquistasfuncionarios FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY conquistasfuncionarios_ins ON public.conquistasfuncionarios FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY conquistasfuncionarios_upd ON public.conquistasfuncionarios FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY conquistasfuncionarios_del ON public.conquistasfuncionarios FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY contagensestoque_sel ON public.contagensestoque FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY contagensestoque_ins ON public.contagensestoque FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY contagensestoque_upd ON public.contagensestoque FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY contagensestoque_del ON public.contagensestoque FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY denunciasanonimas_sel ON public.denunciasanonimas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY denunciasanonimas_ins ON public.denunciasanonimas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY denunciasanonimas_upd ON public.denunciasanonimas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY denunciasanonimas_del ON public.denunciasanonimas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentos_sel ON public.documentos FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY documentos_ins ON public.documentos FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentos_upd ON public.documentos FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentos_del ON public.documentos FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentosassinaturas_sel ON public.documentosassinaturas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY documentosassinaturas_ins ON public.documentosassinaturas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentosassinaturas_upd ON public.documentosassinaturas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentosassinaturas_del ON public.documentosassinaturas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentospessoais_sel ON public.documentospessoais FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY documentospessoais_ins ON public.documentospessoais FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentospessoais_upd ON public.documentospessoais FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentospessoais_del ON public.documentospessoais FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentospessoaisciencia_sel ON public.documentospessoaisciencia FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY documentospessoaisciencia_ins ON public.documentospessoaisciencia FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentospessoaisciencia_upd ON public.documentospessoaisciencia FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY documentospessoaisciencia_del ON public.documentospessoaisciencia FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY entregas_sel ON public.entregas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY entregas_ins ON public.entregas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY entregas_upd ON public.entregas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY entregas_del ON public.entregas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY escaladiaria_sel ON public.escaladiaria FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY escaladiaria_ins ON public.escaladiaria FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY escaladiaria_upd ON public.escaladiaria FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY escaladiaria_del ON public.escaladiaria FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY feedbacks_sel ON public.feedbacks FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY feedbacks_ins ON public.feedbacks FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY feedbacks_upd ON public.feedbacks FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY feedbacks_del ON public.feedbacks FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY feedbacksolicitacoes_sel ON public.feedbacksolicitacoes FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY feedbacksolicitacoes_ins ON public.feedbacksolicitacoes FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY feedbacksolicitacoes_upd ON public.feedbacksolicitacoes FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY feedbacksolicitacoes_del ON public.feedbacksolicitacoes FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY fornecedores_sel ON public.fornecedores FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY fornecedores_ins ON public.fornecedores FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY fornecedores_upd ON public.fornecedores FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY fornecedores_del ON public.fornecedores FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY freelancers_sel ON public.freelancers FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY freelancers_ins ON public.freelancers FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY freelancers_upd ON public.freelancers FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY freelancers_del ON public.freelancers FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionarios_sel ON public.funcionarios FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY funcionarios_ins ON public.funcionarios FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionarios_upd ON public.funcionarios FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionarios_del ON public.funcionarios FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionariosgrupos_sel ON public.funcionariosgrupos FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY funcionariosgrupos_ins ON public.funcionariosgrupos FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionariosgrupos_upd ON public.funcionariosgrupos FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionariosgrupos_del ON public.funcionariosgrupos FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY grupos_sel ON public.grupos FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY grupos_ins ON public.grupos FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY grupos_upd ON public.grupos FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY grupos_del ON public.grupos FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY historicoranking_sel ON public.historicoranking FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY historicoranking_ins ON public.historicoranking FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY historicoranking_upd ON public.historicoranking FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY historicoranking_del ON public.historicoranking FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY itenscontagemestoque_sel ON public.itenscontagemestoque FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY itenscontagemestoque_ins ON public.itenscontagemestoque FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY itenscontagemestoque_upd ON public.itenscontagemestoque FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY itenscontagemestoque_del ON public.itenscontagemestoque FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY itensnotafiscalentrada_sel ON public.itensnotafiscalentrada FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY itensnotafiscalentrada_ins ON public.itensnotafiscalentrada FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY itensnotafiscalentrada_upd ON public.itensnotafiscalentrada FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY itensnotafiscalentrada_del ON public.itensnotafiscalentrada FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY lucromensalhistorico_sel ON public.lucromensalhistorico FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY lucromensalhistorico_ins ON public.lucromensalhistorico FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY lucromensalhistorico_upd ON public.lucromensalhistorico FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY lucromensalhistorico_del ON public.lucromensalhistorico FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasapuracoes_sel ON public.metasdiariasapuracoes FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY metasdiariasapuracoes_ins ON public.metasdiariasapuracoes FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasapuracoes_upd ON public.metasdiariasapuracoes FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasapuracoes_del ON public.metasdiariasapuracoes FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasinstancias_sel ON public.metasdiariasinstancias FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY metasdiariasinstancias_ins ON public.metasdiariasinstancias FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasinstancias_upd ON public.metasdiariasinstancias FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasinstancias_del ON public.metasdiariasinstancias FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasmodelos_sel ON public.metasdiariasmodelos FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY metasdiariasmodelos_ins ON public.metasdiariasmodelos FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasmodelos_upd ON public.metasdiariasmodelos FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasdiariasmodelos_del ON public.metasdiariasmodelos FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasprincipais_sel ON public.metasprincipais FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY metasprincipais_ins ON public.metasprincipais FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasprincipais_upd ON public.metasprincipais FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY metasprincipais_del ON public.metasprincipais FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY notasfiscais_sel ON public.notasfiscais FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY notasfiscais_ins ON public.notasfiscais FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY notasfiscais_upd ON public.notasfiscais FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY notasfiscais_del ON public.notasfiscais FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY notasfiscaisentrada_sel ON public.notasfiscaisentrada FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY notasfiscaisentrada_ins ON public.notasfiscaisentrada FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY notasfiscaisentrada_upd ON public.notasfiscaisentrada FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY notasfiscaisentrada_del ON public.notasfiscaisentrada FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY onboardingstatus_sel ON public.onboardingstatus FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY onboardingstatus_ins ON public.onboardingstatus FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY onboardingstatus_upd ON public.onboardingstatus FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY onboardingstatus_del ON public.onboardingstatus FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY picodiario_sel ON public.picodiario FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY picodiario_ins ON public.picodiario FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY picodiario_upd ON public.picodiario FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY picodiario_del ON public.picodiario FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY posicoesloja_sel ON public.posicoesloja FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY posicoesloja_ins ON public.posicoesloja FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY posicoesloja_upd ON public.posicoesloja FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY posicoesloja_del ON public.posicoesloja FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosestoque_sel ON public.produtosestoque FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY produtosestoque_ins ON public.produtosestoque FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosestoque_upd ON public.produtosestoque FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosestoque_del ON public.produtosestoque FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosfornecedor_sel ON public.produtosfornecedor FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY produtosfornecedor_ins ON public.produtosfornecedor FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosfornecedor_upd ON public.produtosfornecedor FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosfornecedor_del ON public.produtosfornecedor FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosloja_sel ON public.produtosloja FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY produtosloja_ins ON public.produtosloja FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosloja_upd ON public.produtosloja FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY produtosloja_del ON public.produtosloja FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY resgates_sel ON public.resgates FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY resgates_ins ON public.resgates FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY resgates_upd ON public.resgates FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY resgates_del ON public.resgates FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY solicitacoesinternas_sel ON public.solicitacoesinternas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY solicitacoesinternas_ins ON public.solicitacoesinternas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY solicitacoesinternas_upd ON public.solicitacoesinternas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY solicitacoesinternas_del ON public.solicitacoesinternas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefas_sel ON public.tarefas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY tarefas_ins ON public.tarefas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefas_upd ON public.tarefas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefas_del ON public.tarefas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefasatribuidas_sel ON public.tarefasatribuidas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY tarefasatribuidas_ins ON public.tarefasatribuidas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefasatribuidas_upd ON public.tarefasatribuidas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefasatribuidas_del ON public.tarefasatribuidas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionarioslojas_sel ON public.funcionarioslojas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY funcionarioslojas_ins ON public.funcionarioslojas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionarioslojas_upd ON public.funcionarioslojas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY funcionarioslojas_del ON public.funcionarioslojas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefaslojas_sel ON public.tarefaslojas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY tarefaslojas_ins ON public.tarefaslojas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefaslojas_upd ON public.tarefaslojas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY tarefaslojas_del ON public.tarefaslojas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));
CREATE POLICY lojas_sel ON public.lojas FOR SELECT TO authenticated USING (contaid = (select public.minha_conta()));
CREATE POLICY lojas_ins ON public.lojas FOR INSERT TO authenticated WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY lojas_upd ON public.lojas FOR UPDATE TO authenticated USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY lojas_del ON public.lojas FOR DELETE TO authenticated USING (contaid = (select public.minha_conta_editavel()));

-- 6. Storage: cada arquivo mora em <contaid>/<lojaid>/...
--    A primeira pasta do caminho tem que ser a conta do usuario.
CREATE POLICY entregas_sel ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'entregas' AND split_part(name, '/', 1) = (select public.minha_conta())::text);
CREATE POLICY entregas_ins ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'entregas' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY entregas_upd ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'entregas' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY entregas_del ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'entregas' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY notas_fiscais_sel ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'notas-fiscais' AND split_part(name, '/', 1) = (select public.minha_conta())::text);
CREATE POLICY notas_fiscais_ins ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'notas-fiscais' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY notas_fiscais_upd ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'notas-fiscais' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY notas_fiscais_del ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'notas-fiscais' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY documentos_rh_sel ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta())::text);
CREATE POLICY documentos_rh_ins ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY documentos_rh_upd ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY documentos_rh_del ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY layout_loja_sel ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'layout-loja' AND split_part(name, '/', 1) = (select public.minha_conta())::text);
CREATE POLICY layout_loja_ins ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'layout-loja' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY layout_loja_upd ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'layout-loja' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
CREATE POLICY layout_loja_del ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'layout-loja' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text);
