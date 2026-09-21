-- Tarefas do sistema (Fase 5) e a regra de "quando a tarefa cai".
-- Decisoes do Wisley em 21/09/2026, registradas em docs/PLANO_MIGRACAO.md.

-- ---------------------------------------------------------------------------
-- 1. Marca qual tarefa do sistema e qual.
--    Vazio nas tarefas comuns. Uma de cada tipo por cliente.
-- ---------------------------------------------------------------------------

ALTER TABLE public.tarefas ADD COLUMN sistema varchar(40);

ALTER TABLE public.tarefas ADD CONSTRAINT tarefas_sistema_conhecido CHECK (
  sistema IS NULL OR sistema IN (
    'feedback_diario', 'leitura', 'pontos_meta', 'nota_fiscal',
    'modelo_agendamento', 'guardar_mercadoria'
  )
);

CREATE UNIQUE INDEX tarefas_sistema_por_conta
  ON public.tarefas (contaid, sistema) WHERE sistema IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. Tarefa do sistema nao se apaga.
--    Editar titulo, descricao e pontos continua liberado.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protege_tarefa_do_sistema()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.sistema IS NOT NULL THEN
    RAISE EXCEPTION
      'A tarefa "%" e do sistema e nao pode ser apagada.', OLD.titulo
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER tarefas_protege_sistema
  BEFORE DELETE ON public.tarefas
  FOR EACH ROW EXECUTE FUNCTION public.protege_tarefa_do_sistema();

-- ---------------------------------------------------------------------------
-- 3. As 4 tarefas de bonus nunca sao atribuidas a ninguem.
--    Elas so recebem entregas automaticas: existem para o ponto ter onde
--    morar. As 2 de modelo continuam podendo virar atribuicao, mas so pelos
--    fluxos de agendamento e de nota fiscal.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.bloqueia_atribuicao_de_bonus()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  marca varchar(40);
BEGIN
  SELECT sistema INTO marca FROM public.tarefas WHERE tarefaid = NEW.tarefaid;

  IF marca IN ('feedback_diario', 'leitura', 'pontos_meta', 'nota_fiscal') THEN
    RAISE EXCEPTION
      'Esta e uma tarefa de bonus do sistema: ela nao se atribui a ninguem, so registra pontos automaticos.'
      USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER tarefasatribuidas_sem_bonus
  BEFORE INSERT ON public.tarefasatribuidas
  FOR EACH ROW EXECUTE FUNCTION public.bloqueia_atribuicao_de_bonus();

-- ---------------------------------------------------------------------------
-- 4. Quando uma tarefa recorrente cai num dia.
--    Uma so regra, para a tela e as rotinas nunca discordarem.
--
--    Unica   : a partir da data marcada, e ACUMULA enquanto nao for entregue
--              (comportamento real do sistema antigo).
--    Semanal : 1 = domingo ... 7 = sabado, igual a funcionarios.diadefolga.
--    Mensal  : se o dia escolhido nao existe no mes (31 em abril, 30 em
--              fevereiro), cai no ultimo dia do mes.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.tarefa_cai_no_dia(
  p_tipofrequencia varchar,
  p_valorfrequencia integer,
  p_dataagendamento timestamptz,
  p_dia date
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  ultimo_dia integer;
BEGIN
  IF p_tipofrequencia = 'Diaria' THEN
    RETURN true;

  ELSIF p_tipofrequencia = 'Semanal' THEN
    -- extract(dow) devolve 0 = domingo; somamos 1 para a convencao do sistema.
    RETURN p_valorfrequencia = extract(dow FROM p_dia)::integer + 1;

  ELSIF p_tipofrequencia = 'Mensal' THEN
    ultimo_dia := extract(day FROM (date_trunc('month', p_dia) + interval '1 month - 1 day'))::integer;
    RETURN extract(day FROM p_dia)::integer = least(p_valorfrequencia, ultimo_dia);

  ELSIF p_tipofrequencia = 'Unica' THEN
    RETURN p_dataagendamento IS NULL
        OR (p_dataagendamento AT TIME ZONE 'America/Sao_Paulo')::date <= p_dia;
  END IF;

  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tarefa_cai_no_dia(varchar, integer, timestamptz, date)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Cria as 6 tarefas do sistema de um cliente e guarda os IDs em
--    configuracoes. Chamada ao cadastrar o cliente, junto com as
--    configuracoes padrao.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cria_tarefas_do_sistema(p_contaid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
  novo_id integer;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('feedback_diario',    'Feedback diário',        'Registra os pontos de quem manda a nota do dia.',                    0,  'TAREFA_ID_FEEDBACK_DIARIO'),
      ('leitura',            'Leitura de comunicado',  'Registra os pontos de quem confirma a leitura de um comunicado.',    0,  'TAREFA_ID_LEITURA'),
      ('pontos_meta',        'Pontos da meta diária',  'Registra os pontos que a equipe ganha ao bater a meta do dia.',      0,  'TAREFA_ID_PONTOS_META'),
      ('nota_fiscal',        'Envio de nota fiscal',   'Registra os pontos de quem envia a foto de uma nota fiscal.',        0,  'TAREFA_ID_NOTA_FISCAL'),
      ('modelo_agendamento', 'Atender agendamento',    'Modelo: cada agendamento novo vira uma tarefa para o responsável.',  10, 'TAREFA_MODELO_AGENDAMENTO_ID'),
      ('guardar_mercadoria', 'Guardar mercadoria',     'Modelo: cada nota fiscal aprovada vira uma tarefa de guardar.',      10, 'TAREFA_ID_GUARDAR_MERCADORIA_MODELO')
    ) AS t(marca, titulo, descricao, pontos, chave)
  LOOP
    INSERT INTO public.tarefas (contaid, titulo, descricao, pontos, sistema)
    VALUES (p_contaid, r.titulo, r.descricao, r.pontos, r.marca)
    ON CONFLICT (contaid, sistema) WHERE sistema IS NOT NULL DO NOTHING
    RETURNING tarefaid INTO novo_id;

    IF novo_id IS NULL THEN
      SELECT tarefaid INTO novo_id
      FROM public.tarefas WHERE contaid = p_contaid AND sistema = r.marca;
    END IF;

    UPDATE public.configuracoes
    SET valor = novo_id::text, atualizadoem = now()
    WHERE contaid = p_contaid AND chave = r.chave;
  END LOOP;

  -- Tarefa do sistema vale em todas as lojas do cliente.
  INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid)
  SELECT p_contaid, t.tarefaid, l.lojaid
  FROM public.tarefas t
  CROSS JOIN public.lojas l
  WHERE t.contaid = p_contaid AND t.sistema IS NOT NULL
    AND l.contaid = p_contaid
  ON CONFLICT (tarefaid, lojaid) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cria_tarefas_do_sistema(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.cria_tarefas_do_sistema(integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. Loja nova ja nasce com as tarefas do sistema ligadas a ela.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.liga_tarefas_do_sistema_na_loja()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid)
  SELECT NEW.contaid, t.tarefaid, NEW.lojaid
  FROM public.tarefas t
  WHERE t.contaid = NEW.contaid AND t.sistema IS NOT NULL
  ON CONFLICT (tarefaid, lojaid) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lojas_liga_tarefas_do_sistema
  AFTER INSERT ON public.lojas
  FOR EACH ROW EXECUTE FUNCTION public.liga_tarefas_do_sistema_na_loja();

-- ---------------------------------------------------------------------------
-- 7. Clientes cadastrados antes desta migracao ganham as tarefas do sistema
--    agora. E idempotente: rodar de novo nao duplica nada.
-- ---------------------------------------------------------------------------

DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_tarefas_do_sistema(c.contaid);
  END LOOP;
END $$;
