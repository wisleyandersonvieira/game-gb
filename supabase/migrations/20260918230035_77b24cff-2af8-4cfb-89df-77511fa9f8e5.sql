CREATE TABLE public.funcionarios (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  nome TEXT NOT NULL,
  setor TEXT,
  cargo TEXT,
  telefone TEXT,
  chat_id_telegram TEXT,
  ativo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.funcionarios TO authenticated;
GRANT ALL ON public.funcionarios TO service_role;
ALTER TABLE public.funcionarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "funcionarios_all_auth" ON public.funcionarios FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE public.tarefas (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  titulo TEXT NOT NULL,
  descricao TEXT,
  pontos INTEGER NOT NULL DEFAULT 0,
  setor TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tarefas TO authenticated;
GRANT ALL ON public.tarefas TO service_role;
ALTER TABLE public.tarefas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tarefas_all_auth" ON public.tarefas FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE public.tarefas_atribuidas (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tarefa_id UUID NOT NULL REFERENCES public.tarefas(id) ON DELETE CASCADE,
  funcionario_id UUID NOT NULL REFERENCES public.funcionarios(id) ON DELETE CASCADE,
  tipo_frequencia TEXT NOT NULL DEFAULT 'Unica',
  valor_frequencia INTEGER,
  data_agendamento DATE,
  descricao_override TEXT,
  data_fim_vigencia DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tarefas_atribuidas TO authenticated;
GRANT ALL ON public.tarefas_atribuidas TO service_role;
ALTER TABLE public.tarefas_atribuidas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tarefas_atribuidas_all_auth" ON public.tarefas_atribuidas FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE public.entregas (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  atribuicao_id UUID NOT NULL REFERENCES public.tarefas_atribuidas(id) ON DELETE CASCADE,
  tarefa_id UUID NOT NULL REFERENCES public.tarefas(id) ON DELETE CASCADE,
  funcionario_id UUID NOT NULL REFERENCES public.funcionarios(id) ON DELETE CASCADE,
  status_validacao TEXT NOT NULL DEFAULT 'Pendente',
  pontos_ganhos INTEGER NOT NULL DEFAULT 0,
  observacao TEXT,
  motivo_recusa TEXT,
  foto_url TEXT,
  data_envio TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas TO authenticated;
GRANT ALL ON public.entregas TO service_role;
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "entregas_all_auth" ON public.entregas FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE INDEX idx_atribuidas_func ON public.tarefas_atribuidas(funcionario_id);
CREATE INDEX idx_entregas_func ON public.entregas(funcionario_id);
CREATE INDEX idx_entregas_status ON public.entregas(status_validacao);

CREATE OR REPLACE FUNCTION public.update_updated_at_column() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER trg_funcionarios_updated BEFORE UPDATE ON public.funcionarios FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER trg_tarefas_updated BEFORE UPDATE ON public.tarefas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER trg_atribuidas_updated BEFORE UPDATE ON public.tarefas_atribuidas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER trg_entregas_updated BEFORE UPDATE ON public.entregas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();