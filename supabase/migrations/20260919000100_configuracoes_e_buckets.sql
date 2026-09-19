-- Tabela configuracoes (chave/valor) e buckets do Storage.
-- Substitui os parametros fixos do legado/config.py. Nenhum ID fixo no codigo.
-- Referencia: docs/PLANO_MIGRACAO.md (Fase 1)

CREATE TABLE public.configuracoes (
  chave varchar(100) PRIMARY KEY,
  valor text,
  descricao text,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.configuracoes TO authenticated;
GRANT ALL ON public.configuracoes TO service_role;
ALTER TABLE public.configuracoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "configuracoes_all_auth" ON public.configuracoes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Parametros com valor conhecido.
INSERT INTO public.configuracoes (chave, valor, descricao) VALUES
  ('TAXA_CONVERSAO_PONTO_REAL',    '0.03',  'Quanto vale 1 ponto em reais.'),
  ('PONTOS_BONUS_FEEDBACK_DIARIO', '5',     'Pontos de bonus por enviar o feedback do dia.'),
  ('PONTOS_BONUS_NOTA_FISCAL',     '10',    'Pontos de bonus por enviar uma nota fiscal.'),
  ('MAX_DIFERENCA_FOTO_SEGUNDOS',  '120',   'Tolerancia, em segundos, entre a hora da foto (EXIF) e o envio.'),
  ('HORARIO_FECHAMENTO_MENSAL',    '08:00', 'Hora do fechamento mensal do ranking (executa no dia 1).'),
  ('HORARIO_DELEGACAO_FOLGA',      '09:05', 'Hora da delegacao automatica das tarefas de quem esta de folga.'),
  ('HORARIO_LEMBRETE_COMUNICADOS', '09:00', 'Hora do lembrete de comunicados pendentes de leitura.'),
  ('HORARIO_LEMBRETE_HOJE',        '08:00', 'Hora do lembrete dos agendamentos de hoje.'),
  ('HORARIO_LEMBRETE_DIARIO_AMANHA','09:00','Hora do lembrete dos agendamentos de amanha.'),
  ('HORARIO_LEMBRETE_SEMANAL',     '08:00', 'Hora do lembrete semanal de agendamentos.');

-- IDs especiais: o banco esta limpo, entao estes registros ainda nao existem.
-- Preencher o valor depois de recadastrar cada tarefa/pessoa.
INSERT INTO public.configuracoes (chave, valor, descricao) VALUES
  ('TAREFA_ID_FEEDBACK_DIARIO',             '', 'ID da tarefa de feedback diario. Preencher apos recadastrar.'),
  ('TAREFA_ID_LEITURA',                     '', 'ID da tarefa de leitura de comunicado. Preencher apos recadastrar.'),
  ('TAREFA_MODELO_AGENDAMENTO_ID',          '', 'ID da tarefa modelo usada ao criar um agendamento. Preencher apos recadastrar.'),
  ('TAREFA_ID_PONTOS_META',                 '', 'ID da tarefa que credita os pontos da meta diaria. Preencher apos recadastrar.'),
  ('TAREFA_ID_NOTA_FISCAL',                 '', 'ID da tarefa de envio de nota fiscal. Preencher apos recadastrar.'),
  ('TAREFA_ID_GUARDAR_MERCADORIA_MODELO',   '', 'ID da tarefa modelo de guardar mercadoria. Preencher apos recadastrar.'),
  ('ID_GESTOR_PADRAO',                      '', 'ID do funcionario gestor padrao. Preencher apos recadastrar.'),
  ('RESPONSAVEL_AGENDAMENTOS_ID',           '', 'ID do funcionario responsavel pelos agendamentos. Preencher apos recadastrar.');

-- ---------------------------------------------------------------------------
-- Buckets do Storage (privados; URLs assinadas revistas na Fase 12)
-- ---------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public) VALUES
  ('entregas',       'entregas',       false),
  ('notas-fiscais',  'notas-fiscais',  false),
  ('documentos-rh',  'documentos-rh',  false),
  ('layout-loja',    'layout-loja',    false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "entregas_all_auth" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'entregas') WITH CHECK (bucket_id = 'entregas');
CREATE POLICY "notas_fiscais_all_auth" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'notas-fiscais') WITH CHECK (bucket_id = 'notas-fiscais');
CREATE POLICY "documentos_rh_all_auth" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'documentos-rh') WITH CHECK (bucket_id = 'documentos-rh');
CREATE POLICY "layout_loja_all_auth" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'layout-loja') WITH CHECK (bucket_id = 'layout-loja');
