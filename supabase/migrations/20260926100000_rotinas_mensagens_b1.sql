-- Etapa 1.13B1: rotinas com mensagem (jornada, comunicados, folga e missões).
--
-- Regras (decisões do Wisley, 22/09/2026):
--   * Jornada por pessoa: hora de entrada e hora de saída, iguais todos os dias.
--     Sem horário, a pessoa não recebe as mensagens de jornada (só os avisos).
--   * Silêncio 22:00–07:00, ajustável, mas NUNCA dentro do turno da pessoa:
--     quem entra às 18:00 e sai às 02:00 recebe normalmente nesse período.
--   * No máximo 8 mensagens automáticas por pessoa por dia (ajustável).
--   * Folga e afastamento: nada é enviado; os avisos ficam guardados e viram
--     UM resumo ("Enquanto você esteve fora: ...") no próximo dia de trabalho,
--     olhando no máximo 7 dias para trás.
--   * Rotina nunca repete: cada mensagem de rotina tem uma etiqueta única e,
--     se falhar, NÃO é reenviada. Aviso do que aconteceu com a pessoa (entrega
--     aprovada, recusada, conquista) é reenviado: melhor duas vezes que nenhuma.
--   * Bot bloqueado pela pessoa (403): para de tentar, marca o vínculo, avisa
--     o master e volta sozinho quando ela usar o bot de novo.
--   * "Primeiro que clicar" (folga e missões) é atômico e usa as mesmas
--     funções das telas. Todo ponto continua passando pelo livro.

-- ---------------------------------------------------------------------------
-- 1. Jornada da pessoa
-- ---------------------------------------------------------------------------
-- horarionotificacao é a HORA DE ENTRADA (nome herdado do sistema antigo).
-- O padrão 08:00 era automático, sem ninguém escolher: sai, e todos ficam sem
-- horário até o master preencher na tela Equipe.
ALTER TABLE public.funcionarios ALTER COLUMN horarionotificacao DROP DEFAULT;
UPDATE public.funcionarios SET horarionotificacao = NULL;
ALTER TABLE public.funcionarios ADD COLUMN horariosaida time;
COMMENT ON COLUMN public.funcionarios.horarionotificacao IS 'Hora de entrada. Vazio = a pessoa não recebe as mensagens de jornada.';
COMMENT ON COLUMN public.funcionarios.horariosaida IS 'Hora de saída. Vazio = entrada + 8h20 (regra do sistema antigo). Menor que a entrada = turno da noite, que atravessa a meia-noite.';

-- ---------------------------------------------------------------------------
-- 2. Bot bloqueado pela pessoa
-- ---------------------------------------------------------------------------
ALTER TABLE public.telegramvinculos ADD COLUMN bloqueadoem timestamptz;
COMMENT ON COLUMN public.telegramvinculos.bloqueadoem IS 'Quando o Telegram recusou o envio (pessoa bloqueou o bot ou saiu do grupo). Limpo sozinho quando ela usa o bot de novo.';

-- ---------------------------------------------------------------------------
-- 3. Liga/desliga de cada rotina, por loja
-- ---------------------------------------------------------------------------
CREATE TABLE public.mensagensrotinas (
  contaid  integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  lojaid   integer NOT NULL,
  rotina   varchar(30) NOT NULL CHECK (rotina IN ('inicio_jornada', 'lembrete3', 'lembrete6', 'fim_jornada',
                                                  'comunicado_novo', 'comunicado_lembrete', 'folga_drop', 'missao')),
  ativo    boolean NOT NULL DEFAULT true,
  alteradoem timestamptz NOT NULL DEFAULT now(),
  alteradopor uuid,
  PRIMARY KEY (contaid, lojaid, rotina),
  CONSTRAINT mensagensrotinas_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);
ALTER TABLE public.mensagensrotinas ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.mensagensrotinas TO authenticated;
GRANT ALL ON public.mensagensrotinas TO service_role;
CREATE POLICY mensagensrotinas_sel ON public.mensagensrotinas FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- Ligada por padrão: só aparece aqui o que o master desligou ou reativou.
CREATE OR REPLACE FUNCTION public.rotina_ligada(p_contaid integer, p_lojaid integer, p_rotina text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT ativo FROM public.mensagensrotinas
                    WHERE contaid = p_contaid AND lojaid = p_lojaid AND rotina = p_rotina), true)
$$;

-- Em alguma loja da pessoa a rotina está ligada?
CREATE OR REPLACE FUNCTION public.rotina_ligada_pessoa(p_contaid integer, p_funcionarioid integer, p_rotina text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                   JOIN public.lojas l ON l.lojaid = fl.lojaid AND l.contaid = p_contaid AND l.ativa
                  WHERE fl.funcionarioid = p_funcionarioid AND fl.contaid = p_contaid AND fl.ativo
                    AND public.rotina_ligada(p_contaid, fl.lojaid, p_rotina))
$$;

-- Tela: liga/desliga (só o master).
CREATE OR REPLACE FUNCTION public.definir_rotina_mensagem(p_lojaid integer, p_rotina text, p_ativo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.mensagensrotinas (contaid, lojaid, rotina, ativo, alteradopor)
  VALUES (v_conta, p_lojaid, p_rotina, p_ativo, auth.uid())
  ON CONFLICT (contaid, lojaid, rotina)
  DO UPDATE SET ativo = EXCLUDED.ativo, alteradoem = now(), alteradopor = auth.uid();
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Configurações novas (silêncio e limite diário)
-- ---------------------------------------------------------------------------
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
    (p_contaid, 'HORARIO_GERACAO_TAREFAS',       '00:05', 'Hora em que a lista de tarefas do dia é gerada.'),
    (p_contaid, 'HORARIO_CONFERENCIA_LIVRO',     '03:00', 'Hora da conferência diária do livro de pontos e da limpeza do registro de rotinas.'),
    (p_contaid, 'HORARIO_FECHAMENTO_MENSAL',     '08:00', 'Hora do fechamento mensal do ranking (executa no dia 1).'),
    (p_contaid, 'HORARIO_DELEGACAO_FOLGA',       '09:05', 'Hora da delegacao automatica das tarefas de quem esta de folga.'),
    (p_contaid, 'HORARIO_LEMBRETE_COMUNICADOS',  '09:00', 'Hora do lembrete de comunicados pendentes de leitura.'),
    (p_contaid, 'HORARIO_LEMBRETE_HOJE',         '08:00', 'Hora do lembrete dos agendamentos de hoje.'),
    (p_contaid, 'HORARIO_LEMBRETE_DIARIO_AMANHA','09:00', 'Hora do lembrete dos agendamentos de amanha.'),
    (p_contaid, 'HORARIO_LEMBRETE_SEMANAL',      '08:00', 'Hora do lembrete semanal de agendamentos.'),
    (p_contaid, 'HORARIO_SILENCIO_INICIO',       '22:00', 'A partir desta hora o bot não manda mensagem automática (não vale dentro do turno da pessoa).'),
    (p_contaid, 'HORARIO_SILENCIO_FIM',          '07:00', 'A partir desta hora o bot volta a mandar mensagem automática.'),
    (p_contaid, 'MAX_MENSAGENS_AUTOMATICAS_DIA', '8',     'Máximo de mensagens automáticas por pessoa por dia.'),
    (p_contaid, 'MAX_TAREFAS_FOLGA_POR_PESSOA',  '3',     'Máximo de tarefas de folga que uma pessoa pode pegar por dia pelo grupo.'),
    (p_contaid, 'TAREFA_ID_FEEDBACK_DIARIO',           '', 'ID da tarefa de feedback diario. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_ID_LEITURA',                   '', 'ID da tarefa de leitura de comunicado. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_MODELO_AGENDAMENTO_ID',        '', 'ID da tarefa modelo usada ao criar um agendamento.'),
    (p_contaid, 'TAREFA_ID_PONTOS_META',               '', 'ID da tarefa que credita os pontos da meta diaria.'),
    (p_contaid, 'TAREFA_ID_NOTA_FISCAL',               '', 'ID da tarefa de envio de nota fiscal.'),
    (p_contaid, 'TAREFA_ID_GUARDAR_MERCADORIA_MODELO', '', 'ID da tarefa modelo de guardar mercadoria.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;
REVOKE EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) TO service_role;

-- As contas que já existem também ganham as chaves novas.
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_configuracoes_padrao(c.contaid);
  END LOOP;
END $$;

-- Validação: os MAX_* são inteiros de 1 a 50.
CREATE OR REPLACE FUNCTION public.valida_configuracao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_texto text := btrim(coalesce(NEW.valor, ''));
  v_num   numeric;
BEGIN
  IF NEW.chave = 'TAXA_CONVERSAO_PONTO_REAL' THEN
    BEGIN
      v_num := replace(v_texto, ',', '.')::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'A taxa precisa ser um número, como 0,03.' USING ERRCODE = 'check_violation';
    END;
    IF v_num IS NULL OR v_num <= 0 OR v_num > 10 THEN
      RAISE EXCEPTION 'A taxa precisa ser maior que zero e no máximo R$ 10 por ponto.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_num::text;

  ELSIF NEW.chave LIKE 'PONTOS_BONUS_%' OR NEW.chave = 'MAX_DIFERENCA_FOTO_SEGUNDOS' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro, sem vírgula.' USING ERRCODE = 'check_violation';
    END IF;
    v_num := CASE WHEN NEW.chave LIKE 'PONTOS_BONUS_%' THEN 10000 ELSE 86400 END;
    IF v_texto::numeric > v_num THEN
      RAISE EXCEPTION 'Valor alto demais para %.', NEW.chave USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave IN ('MAX_MENSAGENS_AUTOMATICAS_DIA', 'MAX_TAREFAS_FOLGA_POR_PESSOA') THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer < 1 OR v_texto::integer > 50 THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro de 1 a 50.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave LIKE 'HORARIO_%' THEN
    IF v_texto !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
      RAISE EXCEPTION 'O horário precisa estar no formato HH:MM, entre 00:00 e 23:59.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave LIKE 'TAREFA_%' THEN
    IF v_texto <> '' AND v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'ID de tarefa inválido.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.atualizadoem := now();
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Colunas novas da fila
-- ---------------------------------------------------------------------------
ALTER TABLE public.mensagensfila ADD COLUMN funcionarioid integer;
ALTER TABLE public.mensagensfila ADD CONSTRAINT mensagensfila_funcionario_fk
  FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.mensagensfila ADD COLUMN automatica boolean NOT NULL DEFAULT true;
ALTER TABLE public.mensagensfila ADD COLUMN naoreenviar boolean NOT NULL DEFAULT false;
ALTER TABLE public.mensagensfila ADD COLUMN chave text;
ALTER TABLE public.mensagensfila ADD COLUMN juntarchave text;
COMMENT ON COLUMN public.mensagensfila.chave IS 'Etiqueta única da rotina (ex.: inicio:12:2026-09-23). O banco recusa a segunda mensagem com a mesma etiqueta.';
COMMENT ON COLUMN public.mensagensfila.naoreenviar IS 'Rotina: se falhar, não tenta de novo (melhor faltar que repetir). Aviso da pessoa é sempre reenviado.';
COMMENT ON COLUMN public.mensagensfila.juntarchave IS 'Avisos com a mesma etiqueta viram uma mensagem só.';
CREATE UNIQUE INDEX mensagensfila_chave_unica ON public.mensagensfila (contaid, chave) WHERE chave IS NOT NULL;
CREATE INDEX mensagensfila_guardadas_idx ON public.mensagensfila (contaid, funcionarioid) WHERE status = 'guardada';
CREATE INDEX mensagensfila_contagem_idx ON public.mensagensfila (contaid, funcionarioid, enviadoem) WHERE status = 'enviada' AND automatica;

-- Situação nova: 'guardada' (aviso retido porque a pessoa está de folga).
ALTER TABLE public.mensagensfila DROP CONSTRAINT mensagensfila_status_check;
ALTER TABLE public.mensagensfila ADD CONSTRAINT mensagensfila_status_check
  CHECK (status IN ('pendente', 'enviando', 'enviada', 'falhou', 'descartada', 'guardada'));

-- ---------------------------------------------------------------------------
-- 6. Jornada e janela de envio
-- ---------------------------------------------------------------------------
-- Instante de uma hora local (São Paulo) num dia.
CREATE OR REPLACE FUNCTION public.instante_local(p_dia date, p_hora time)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT (p_dia::timestamp + p_hora) AT TIME ZONE 'America/Sao_Paulo'
$$;

-- O turno que COMEÇA em p_dia. Saída menor que a entrada = turno da noite,
-- que termina no dia seguinte (ex.: 18:00 → 02:00).
CREATE OR REPLACE FUNCTION public.jornada_da_pessoa(p_contaid integer, p_funcionarioid integer, p_dia date)
RETURNS TABLE (trabalha boolean, temhorario boolean, inicio timestamptz, fim timestamptz)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, p_dia),
         f.horarionotificacao IS NOT NULL,
         public.instante_local(p_dia, f.horarionotificacao),
         public.instante_local(p_dia, f.horarionotificacao)
           + CASE WHEN coalesce(f.horariosaida, f.horarionotificacao + interval '8 hours 20 minutes')
                       > f.horarionotificacao
                  THEN coalesce(f.horariosaida, f.horarionotificacao + interval '8 hours 20 minutes')
                       - f.horarionotificacao
                  ELSE coalesce(f.horariosaida, f.horarionotificacao + interval '8 hours 20 minutes')
                       - f.horarionotificacao + interval '24 hours' END
    FROM public.funcionarios f
   WHERE f.contaid = p_contaid AND f.funcionarioid = p_funcionarioid AND f.ativo
$$;

-- Está dentro do silêncio da conta? (22:00–07:00, atravessando a meia-noite)
CREATE OR REPLACE FUNCTION public.no_silencio(p_contaid integer, p_hora time)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN ini = fim THEN false
              WHEN ini < fim THEN p_hora >= ini AND p_hora < fim
              ELSE p_hora >= ini OR p_hora < fim END
    FROM (SELECT public.rotina_horario(p_contaid, 'HORARIO_SILENCIO_INICIO', '22:00') AS ini,
                 public.rotina_horario(p_contaid, 'HORARIO_SILENCIO_FIM', '07:00') AS fim) x
$$;

-- Pode mandar agora para esta pessoa (ou para um grupo, com funcionário vazio)?
-- Devolve {pode, motivo, proxima}. O silêncio NÃO vale dentro do turno.
CREATE OR REPLACE FUNCTION public.bot_janela(p_contaid integer, p_funcionarioid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje  date;
  v_hora  time;
  v_fim   time := public.rotina_horario(p_contaid, 'HORARIO_SILENCIO_FIM', '07:00');
  j       record;
  d       date;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;

  -- Grupo (ou o Telegram do master): só o silêncio.
  IF p_funcionarioid IS NULL THEN
    IF public.no_silencio(p_contaid, v_hora) THEN
      RETURN jsonb_build_object('pode', false, 'motivo', 'silencio',
        'proxima', CASE WHEN v_hora < v_fim THEN public.instante_local(v_hoje, v_fim)
                        ELSE public.instante_local(v_hoje + 1, v_fim) END);
    END IF;
    RETURN jsonb_build_object('pode', true);
  END IF;

  SELECT * INTO j FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, v_hoje);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('pode', false, 'motivo', 'sem_pessoa');
  END IF;

  IF j.temhorario THEN
    -- Dentro do turno de hoje ou do que começou ontem (turno da noite)?
    IF EXISTS (
      SELECT 1 FROM generate_series(v_hoje - 1, v_hoje, interval '1 day') g
       CROSS JOIN LATERAL public.jornada_da_pessoa(p_contaid, p_funcionarioid, g::date) t
       WHERE t.trabalha AND p_agora >= t.inicio AND p_agora <= t.fim + interval '30 minutes') THEN
      RETURN jsonb_build_object('pode', true);
    END IF;
    -- Fora do turno: espera o próximo começo (até 8 dias à frente).
    FOR d IN SELECT g::date FROM generate_series(v_hoje, v_hoje + 8, interval '1 day') g LOOP
      SELECT * INTO j FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, d);
      IF j.trabalha AND j.inicio > p_agora THEN
        RETURN jsonb_build_object('pode', false,
          'motivo', CASE WHEN d = v_hoje THEN 'fora_do_turno' ELSE 'folga' END,
          'proxima', j.inicio);
      END IF;
    END LOOP;
    RETURN jsonb_build_object('pode', false, 'motivo', 'folga', 'proxima', public.instante_local(v_hoje + 1, v_fim));
  END IF;

  -- Sem horário: valem a folga e o silêncio.
  IF NOT j.trabalha THEN
    FOR d IN SELECT g::date FROM generate_series(v_hoje + 1, v_hoje + 8, interval '1 day') g LOOP
      IF (SELECT t.trabalha FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, d) t) THEN
        RETURN jsonb_build_object('pode', false, 'motivo', 'folga', 'proxima', public.instante_local(d, v_fim));
      END IF;
    END LOOP;
    RETURN jsonb_build_object('pode', false, 'motivo', 'folga', 'proxima', public.instante_local(v_hoje + 1, v_fim));
  END IF;
  IF public.no_silencio(p_contaid, v_hora) THEN
    RETURN jsonb_build_object('pode', false, 'motivo', 'silencio',
      'proxima', CASE WHEN v_hora < v_fim THEN public.instante_local(v_hoje, v_fim)
                      ELSE public.instante_local(v_hoje + 1, v_fim) END);
  END IF;
  RETURN jsonb_build_object('pode', true);
END;
$$;

-- Quantas mensagens automáticas esta pessoa já recebeu hoje (dia de São Paulo).
CREATE OR REPLACE FUNCTION public.bot_enviadas_hoje(p_contaid integer, p_funcionarioid integer, p_agora timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::integer FROM public.mensagensfila
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND automatica AND status = 'enviada'
     AND enviadoem >= public.instante_local(public.dia_em_sao_paulo(p_agora), '00:00')
$$;

-- ---------------------------------------------------------------------------
-- 7. Missões da equipe (tarefa sem dono, que alguém pega no grupo)
-- ---------------------------------------------------------------------------
-- Uma missão é uma linha de tarefasatribuidas SEM funcionário, com loja e
-- horário de disparo. Quem pega ganha uma tarefa única de hoje, ligada à
-- missão por origematribuicaoid (por isso conta como esforço extra).
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_missao_tem_horario
  CHECK (funcionarioid IS NOT NULL OR agendamentoid IS NOT NULL OR horariodisparo IS NOT NULL);

CREATE TABLE public.missoesaceites (
  contaid          integer NOT NULL REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  atribuicaoid     integer NOT NULL,
  dia              date    NOT NULL,
  funcionarioid    integer NOT NULL,
  novaatribuicaoid integer,
  canal            varchar(10) NOT NULL DEFAULT 'app' CHECK (canal IN ('app', 'telegram')),
  aceitoem         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contaid, atribuicaoid, dia),
  CONSTRAINT missoesaceites_missao_fk FOREIGN KEY (contaid, atribuicaoid)
    REFERENCES public.tarefasatribuidas (contaid, atribuicaoid) ON DELETE RESTRICT,
  CONSTRAINT missoesaceites_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT
);
ALTER TABLE public.missoesaceites ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.missoesaceites TO authenticated;
GRANT ALL ON public.missoesaceites TO service_role;
CREATE POLICY missoesaceites_sel ON public.missoesaceites FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- Aceitar a missão. O primeiro que clicar leva: a chave (conta, missão, dia)
-- garante isso mesmo com dois cliques no mesmo instante.
CREATE OR REPLACE FUNCTION public.pegar_missao(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.dia_em_sao_paulo(now());
  m       public.tarefasatribuidas%ROWTYPE;
  v_nova  integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND funcionarioid IS NULL
     AND horariodisparo IS NOT NULL AND datafimvigencia IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Missão não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje) THEN
    RAISE EXCEPTION 'Esta missão não vale para hoje.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = m.lojaid
                                                   AND fl.ativo AND fl.contaid = v_conta
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = v_conta AND f.ativo
                    AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                               f.datafimafastamento, v_hoje)) THEN
    RAISE EXCEPTION 'Só quem trabalha hoje nesta loja pode pegar a missão.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
  VALUES (v_conta, p_atribuicaoid, v_hoje, p_funcionarioid, public.canal_atual())
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta missão já foi pega hoje.' USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        dataatribuicao, dataagendamento, origematribuicaoid)
  VALUES (v_conta, m.tarefaid, p_funcionarioid, m.lojaid, 'Unica', now(), now(), p_atribuicaoid)
  RETURNING atribuicaoid INTO v_nova;

  UPDATE public.missoesaceites SET novaatribuicaoid = v_nova
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = v_hoje;
  RETURN v_nova;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Textos das rotinas (montados na HORA DE ENVIAR)
-- ---------------------------------------------------------------------------
-- Tarefas em aberto da pessoa hoje, por loja.
CREATE OR REPLACE FUNCTION public.bot_abertas_da_pessoa(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('atribuicaoid', a.atribuicaoid, 'titulo', a.titulo,
                                               'pontos', a.pontos, 'loja', l.nome, 'atrasada', a.atrasada)
                            ORDER BY l.nome, a.atrasada DESC, a.titulo), '[]'::jsonb)
    FROM public.funcionarioslojas fl
    JOIN public.lojas l ON l.lojaid = fl.lojaid AND l.contaid = p_contaid AND l.ativa
    CROSS JOIN LATERAL public.atribuicoes_para_entregar(fl.lojaid) a
   WHERE fl.funcionarioid = p_funcionarioid AND fl.contaid = p_contaid AND fl.ativo
     AND a.funcionarioid = p_funcionarioid
$$;

-- Lista as tarefas em texto e os botões de foto (no máximo 10).
CREATE OR REPLACE FUNCTION public.bot_lista_tarefas(p_itens jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH x AS (
    SELECT row_number() OVER () AS i, e->>'titulo' AS titulo, (e->>'pontos')::integer AS pontos,
           e->>'loja' AS loja, (e->>'atrasada')::boolean AS atrasada, (e->>'atribuicaoid')::integer AS atribuicaoid
      FROM jsonb_array_elements(p_itens) e),
  y AS (SELECT x.*, lag(x.loja) OVER (ORDER BY x.i) AS lojaanterior FROM x)
  SELECT jsonb_build_object(
    'texto', coalesce(string_agg(
       CASE WHEN y.loja IS DISTINCT FROM y.lojaanterior THEN E'\n🏪 <b>' || public.bot_html(y.loja) || E'</b>\n' ELSE '' END
       || '• ' || CASE WHEN y.atrasada THEN '⚠️ ' ELSE '' END || public.bot_html(y.titulo) || ' (' || y.pontos || ' pts)',
       E'\n' ORDER BY y.i), ''),
    'botoes', coalesce(jsonb_agg(jsonb_build_array(jsonb_build_object(
                'text', '📸 ' || left(y.titulo, 28), 'callback_data', 'ent:' || y.atribuicaoid))
                ORDER BY y.i) FILTER (WHERE y.i <= 10), '[]'::jsonb))
    FROM y
$$;

-- Resumo do que ficou guardado enquanto a pessoa esteve fora (7 dias).
CREATE OR REPLACE FUNCTION public.bot_resumo_ausencia(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v_txt text;
BEGIN
  -- O que ficou guardado há mais de 7 dias não vira mensagem.
  UPDATE public.mensagensfila SET status = 'descartada', erro = 'guardada demais'
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND status = 'guardada'
     AND criadoem < now() - interval '7 days';

  SELECT string_agg(x.linha, ', ' ORDER BY x.n DESC) INTO v_txt
    FROM (SELECT count(*)::integer AS n,
                 count(*) || ' ' || CASE tipo
                   WHEN 'entrega_aprovada' THEN CASE WHEN count(*) = 1 THEN 'entrega aprovada' ELSE 'entregas aprovadas' END
                   WHEN 'entrega_recusada' THEN CASE WHEN count(*) = 1 THEN 'entrega recusada' ELSE 'entregas recusadas' END
                   WHEN 'conquista'        THEN CASE WHEN count(*) = 1 THEN 'conquista' ELSE 'conquistas' END
                   WHEN 'comunicado_novo'  THEN CASE WHEN count(*) = 1 THEN 'comunicado' ELSE 'comunicados' END
                   ELSE CASE WHEN count(*) = 1 THEN 'aviso' ELSE 'avisos' END END AS linha
            FROM public.mensagensfila
           WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND status = 'guardada'
           GROUP BY tipo) x;
  IF v_txt IS NULL THEN
    RETURN NULL;
  END IF;
  UPDATE public.mensagensfila SET status = 'descartada', erro = 'resumida'
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND status = 'guardada';
  RETURN jsonb_build_object('metodo', 'sendMessage',
    'texto', '👋 Bom te ver de volta! Enquanto você esteve fora: <b>' || v_txt || E'</b>.\nUse o menu para ver o que falta.');
END;
$$;

-- Monta a mensagem de cada rotina. NULL = não há mais motivo para enviar
-- (ex.: a tarefa já foi feita, o comunicado já teve ciência).
CREATE OR REPLACE FUNCTION public.bot_texto_rotina(p_tipo text, p_contaid integer, p_funcionarioid integer,
                                                   p_referencia integer)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date := public.dia_em_sao_paulo(now());
  v_nome   text;
  v_itens  jsonb;
  v_lista  jsonb;
  v_bot    jsonb := '[]'::jsonb;
  v_texto  text;
  v_hora   time := (now() AT TIME ZONE 'America/Sao_Paulo')::time;
  r        record;
  v_n      integer;
BEGIN
  SELECT public.nome_curto(nomecompleto) INTO v_nome FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = p_contaid;

  IF p_tipo IN ('inicio_jornada', 'lembrete3', 'lembrete6') THEN
    v_itens := public.bot_abertas_da_pessoa(p_contaid, p_funcionarioid);
    IF p_tipo <> 'inicio_jornada' AND jsonb_array_length(v_itens) = 0 THEN
      RETURN NULL;                                   -- já fez tudo: lembrete não sai
    END IF;
    v_lista := public.bot_lista_tarefas(v_itens);
    IF p_tipo = 'inicio_jornada' THEN
      v_texto := CASE WHEN v_hora < '12:00' THEN '☀️ Bom dia' WHEN v_hora < '18:00' THEN '🌤️ Boa tarde' ELSE '🌙 Boa noite' END
                 || ', <b>' || public.bot_html(v_nome) || '</b>!';
      v_texto := v_texto || CASE WHEN jsonb_array_length(v_itens) = 0
                                 THEN E'\n\nVocê não tem tarefas hoje. Bom trabalho! ✨'
                                 ELSE E'\n\n<b>Suas tarefas de hoje</b>' || (v_lista->>'texto') END;
      IF public.bot_falta_feedback_ontem(p_contaid, p_funcionarioid) THEN
        v_texto := v_texto || E'\n\n⭐ Você não avaliou o dia de ontem.';
        v_bot := jsonb_build_array(jsonb_build_array(jsonb_build_object('text', '⭐ Avaliar ontem', 'callback_data', 'fbm:ontem')));
      END IF;
    ELSE
      v_texto := '👋 <b>' || public.bot_html(v_nome) || '</b>, ainda em aberto:' || (v_lista->>'texto');
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage', 'texto', v_texto,
                              'botoes', (v_lista->'botoes') || v_bot);

  ELSIF p_tipo = 'fim_jornada' THEN
    SELECT count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada') AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente') AS pendentes
      INTO r
      FROM public.entregas e
     WHERE e.contaid = p_contaid AND e.funcionarioid = p_funcionarioid
       AND public.dia_em_sao_paulo(e.dataenvio) = v_hoje;
    SELECT coalesce(sum(pontos), 0) INTO v_n FROM public.movimentospontos
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
       AND public.dia_em_sao_paulo(datamovimento) = v_hoje AND pontos > 0;
    v_itens := public.bot_abertas_da_pessoa(p_contaid, p_funcionarioid);
    v_texto := '🌆 Fim de expediente, <b>' || public.bot_html(v_nome) || E'</b>!\n\n'
               || '✅ ' || r.aprovadas || ' aprovadas · ⏳ ' || r.pendentes || ' em validação · 🎯 +' || v_n || ' pontos hoje';
    IF jsonb_array_length(v_itens) > 0 THEN
      v_texto := v_texto || E'\n\nFicou pendente:' || (public.bot_lista_tarefas(v_itens)->>'texto');
    ELSE
      v_texto := v_texto || E'\n\nVocê fechou o dia sem pendências. Trabalho incrível! 🏆';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.feedbacks WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                     AND datafeedback = v_hoje AND anuladoem IS NULL) THEN
      v_texto := v_texto || E'\n\nComo foi o seu dia?';
      v_bot := jsonb_build_array(jsonb_build_array(jsonb_build_object('text', '⭐ Avaliar meu dia', 'callback_data', 'fbm:hoje')));
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage', 'texto', v_texto, 'botoes', v_bot);

  ELSIF p_tipo IN ('comunicado_novo', 'comunicado_lembrete') THEN
    SELECT d.titulo, left(d.conteudo, 2500) AS conteudo, d.pontosporciencia AS pontos INTO r
      FROM public.documentosassinaturas s
      JOIN public.documentos d ON d.documentoid = s.documentoid AND d.contaid = p_contaid AND d.status = 'Publicado'
     WHERE s.assinaturaid = p_referencia AND s.contaid = p_contaid AND s.statusassinatura = 'Pendente';
    IF NOT FOUND THEN
      RETURN NULL;                                   -- já deu ciência ou o comunicado saiu do ar
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage',
      'texto', CASE WHEN p_tipo = 'comunicado_novo' THEN '📢 <b>' ELSE '⏰ Ainda sem a sua ciência: <b>' END
               || public.bot_html(r.titulo) || E'</b>\n\n' || public.bot_html(r.conteudo)
               || CASE WHEN coalesce(r.pontos, 0) > 0 THEN E'\n\n🎁 +' || r.pontos || ' pontos ao confirmar.' ELSE '' END,
      'botoes', jsonb_build_array(jsonb_build_array(
                  jsonb_build_object('text', '✅ Estou ciente', 'callback_data', 'ci:' || p_referencia))));

  ELSIF p_tipo = 'folga_drop' THEN
    SELECT jsonb_agg(jsonb_build_object('atribuicaoid', x.atribuicaoid, 'titulo', x.titulo, 'pontos', x.pontos,
                                        'pessoa', public.nome_curto(x.nomecompleto), 'motivo', x.situacao)
                     ORDER BY x.titulo) INTO v_itens
      FROM (SELECT c.atribuicaoid, t.titulo, c.pontos, f.nomecompleto, c.situacao
              FROM public.lista_candidatos(p_contaid, v_hoje) c
              JOIN public.tarefas t      ON t.tarefaid = c.tarefaid AND t.contaid = p_contaid
              JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = p_contaid
             WHERE c.lojaid = p_referencia AND c.situacao IN ('folga', 'afastamento')
               AND NOT public.passada_hoje(c.atribuicaoid, v_hoje)
               AND NOT public.tem_justificativa(c.atribuicaoid, c.tipofrequencia, v_hoje, false)
               AND NOT EXISTS (SELECT 1 FROM public.entregas e
                                WHERE e.atribuicaoid = c.atribuicaoid AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  AND (c.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = v_hoje))
             LIMIT 10) x;
    IF v_itens IS NULL THEN
      RETURN NULL;
    END IF;
    SELECT string_agg('• <b>' || public.bot_html(e->>'titulo') || '</b> · ' || (e->>'pontos') || ' pts · '
                      || CASE WHEN e->>'motivo' = 'afastamento' THEN '🌴 ' ELSE '🏠 ' END || public.bot_html(e->>'pessoa'), E'\n'),
           jsonb_agg(jsonb_build_array(jsonb_build_object('text', '🚀 Pegar: ' || left(e->>'titulo', 25),
                                                          'callback_data', 'fg:' || (e->>'atribuicaoid'))))
      INTO v_texto, v_bot
      FROM jsonb_array_elements(v_itens) e;
    RETURN jsonb_build_object('metodo', 'sendMessage',
      'texto', E'⚡ <b>Tarefas de quem está de folga hoje</b>\nQuem pegar, faz e ganha os pontos:\n' || v_texto,
      'botoes', v_bot);

  ELSIF p_tipo = 'missao' THEN
    SELECT t.titulo, t.pontos, l.nome AS loja INTO r
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
      JOIN public.lojas l   ON l.lojaid = ta.lojaid AND l.contaid = p_contaid
     WHERE ta.atribuicaoid = p_referencia AND ta.contaid = p_contaid AND ta.datafimvigencia IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.missoesaceites m
                        WHERE m.contaid = p_contaid AND m.atribuicaoid = p_referencia AND m.dia = v_hoje);
    IF NOT FOUND THEN
      RETURN NULL;
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage',
      'texto', E'🚨 <b>Missão da equipe!</b>\n\n📝 ' || public.bot_html(r.titulo) || E'\n💰 ' || r.pontos
               || E' pontos\n\nO primeiro que aceitar fica com ela hoje.',
      'botoes', jsonb_build_array(jsonb_build_array(
                  jsonb_build_object('text', '🙋 Eu aceito!', 'callback_data', 'ms:' || p_referencia))));

  ELSIF p_tipo = 'resumo_ausencia' THEN
    RETURN public.bot_resumo_ausencia(p_contaid, p_funcionarioid);
  END IF;
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Fila: janela de envio, limite diário, avisos juntados e bot bloqueado
-- ---------------------------------------------------------------------------
-- Enfileirar com todos os detalhes. A versão curta (1.13A) continua valendo.
CREATE OR REPLACE FUNCTION public.bot_enfileirar_ex(p_contaid integer, p_lojaid integer, p_chatid bigint,
                                                    p_funcionarioid integer, p_tipo text, p_conteudo jsonb,
                                                    p_referencia integer, p_chave text, p_juntarchave text,
                                                    p_naoreenviar boolean, p_quando timestamptz)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_id bigint;
BEGIN
  IF p_chatid IS NULL THEN RETURN NULL; END IF;
  -- Vínculo com o bot bloqueado: nem enfileira.
  IF EXISTS (SELECT 1 FROM public.telegramvinculos
              WHERE contaid = p_contaid AND chatid = p_chatid AND ativo AND bloqueadoem IS NOT NULL) THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.mensagensfila (contaid, lojaid, chatid, funcionarioid, tipo, conteudo, referencia,
                                    chave, juntarchave, naoreenviar, proximaem)
  VALUES (p_contaid, p_lojaid, p_chatid, p_funcionarioid, p_tipo, coalesce(p_conteudo, '{}'), p_referencia,
          p_chave, p_juntarchave, coalesce(p_naoreenviar, false), coalesce(p_quando, now()))
  ON CONFLICT DO NOTHING                      -- a etiqueta única impede repetir
  RETURNING filaid INTO v_id;
  IF v_id IS NOT NULL THEN
    PERFORM public.bot_fila_disparar();
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_enfileirar(p_contaid integer, p_lojaid integer, p_chatid bigint, p_tipo text,
                                               p_conteudo jsonb, p_referencia integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.bot_enfileirar_ex(p_contaid, p_lojaid, p_chatid, NULL, p_tipo, p_conteudo, p_referencia,
                                  NULL, NULL, false, now())
$$;

-- O Telegram recusou o envio para este chat (pessoa bloqueou o bot, saiu do
-- grupo ou apagou a conta): para de tentar, marca e avisa o master.
CREATE OR REPLACE FUNCTION public.bot_marcar_bloqueio(p_contaid integer, p_chatid bigint, p_erro text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v record; v_texto text;
BEGIN
  SELECT v2.vinculoid, v2.tipo, v2.funcionarioid, v2.lojaid, v2.papelgrupo,
         coalesce(f.nomecompleto, l.nome, 'Telegram') AS nome
    INTO v
    FROM public.telegramvinculos v2
    LEFT JOIN public.funcionarios f ON f.funcionarioid = v2.funcionarioid AND f.contaid = v2.contaid
    LEFT JOIN public.lojas l        ON l.lojaid = v2.lojaid AND l.contaid = v2.contaid
   WHERE v2.contaid = p_contaid AND v2.chatid = p_chatid AND v2.ativo AND v2.bloqueadoem IS NULL;
  IF NOT FOUND THEN RETURN; END IF;

  UPDATE public.telegramvinculos SET bloqueadoem = now() WHERE vinculoid = v.vinculoid;
  UPDATE public.mensagensfila SET status = 'descartada', erro = left(coalesce(p_erro, 'bloqueado'), 300)
   WHERE contaid = p_contaid AND chatid = p_chatid AND status IN ('pendente', 'guardada');

  v_texto := CASE v.tipo
    WHEN 'pessoa' THEN v.nome || ' bloqueou o bot no Telegram e parou de receber as mensagens.'
    WHEN 'grupo'  THEN 'O bot não consegue mais falar no grupo ' ||
                       CASE WHEN v.papelgrupo = 'gestao' THEN 'de gestão' ELSE 'da equipe' END || ' da ' || v.nome || '.'
    ELSE 'O bot não consegue mais falar no seu Telegram.' END;
  INSERT INTO public.avisossistema (contaid, tipo, texto) VALUES (p_contaid, 'telegram_bloqueado', left(v_texto, 300));
  PERFORM public.bot_enfileirar(p_contaid, v.lojaid, m.chatid, 'bloqueio',
            jsonb_build_object('metodo', 'sendMessage', 'texto', '⚠️ ' || public.bot_html(v_texto)), v.vinculoid)
     FROM public.telegramvinculos m
    WHERE m.contaid = p_contaid AND m.tipo = 'master' AND m.ativo AND m.bloqueadoem IS NULL;
END;
$$;

-- A pessoa voltou a falar com o bot: o bloqueio some sozinho.
CREATE OR REPLACE FUNCTION public.bot_visto(p_chatid bigint)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.telegramvinculos SET bloqueadoem = NULL
   WHERE chatid = p_chatid AND ativo AND bloqueadoem IS NOT NULL
$$;

-- Junta vários avisos de entrega aprovada numa mensagem só.
CREATE OR REPLACE FUNCTION public.bot_texto_juntado(p_conteudos jsonb)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN count(*) = 1
              THEN '✅ Sua entrega <b>' || public.bot_html(min(e->>'titulo')) || '</b> foi aprovada! +'
                   || sum(coalesce((e->>'pontos')::integer, 0)) || ' pontos.'
              ELSE '✅ <b>' || count(*) || ' entregas aprovadas</b>: '
                   || string_agg(public.bot_html(e->>'titulo'), ', ') || ' · +'
                   || sum(coalesce((e->>'pontos')::integer, 0)) || ' pontos.' END
    FROM jsonb_array_elements(p_conteudos) e
$$;

-- Pega o que vai sair agora, respeitando turno, silêncio, folga e limite.
CREATE OR REPLACE FUNCTION public.bot_fila_pegar(p_limite integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r       public.mensagensfila%ROWTYPE;
  v_out   jsonb := '[]';
  v_cont  jsonb := '{}';
  v_n     integer;
  v_env   jsonb;
  l       jsonb;
  j       jsonb;
  v_max   integer;
  v_irmas jsonb;
  v_ids   bigint[];
BEGIN
  -- Presa em "enviando" há mais de 5 minutos: rotina não repete, aviso volta.
  UPDATE public.mensagensfila SET status = 'falhou', erro = 'sem resposta do envio'
   WHERE status = 'enviando' AND naoreenviar AND proximaem < now() - interval '5 minutes';
  UPDATE public.mensagensfila SET status = 'pendente'
   WHERE status = 'enviando' AND NOT naoreenviar AND proximaem < now() - interval '5 minutes';
  DELETE FROM public.mensagensfila
   WHERE status IN ('enviada', 'descartada', 'falhou') AND criadoem < now() - interval '7 days';

  FOR r IN SELECT * FROM public.mensagensfila WHERE status = 'pendente' AND proximaem <= now()
            ORDER BY filaid FOR UPDATE SKIP LOCKED LIMIT greatest(p_limite, 1) * 4 LOOP
    EXIT WHEN jsonb_array_length(v_out) >= greatest(p_limite, 1);
    -- Pode ter mudado nesta mesma rodada (ex.: juntada com outra mensagem).
    CONTINUE WHEN (SELECT m.status FROM public.mensagensfila m WHERE m.filaid = r.filaid) <> 'pendente';

    -- 1) Janela: turno da pessoa, silêncio e folga.
    j := public.bot_janela(r.contaid, r.funcionarioid, now());
    IF NOT (j->>'pode')::boolean THEN
      IF j->>'motivo' = 'folga' AND NOT r.naoreenviar THEN
        UPDATE public.mensagensfila SET status = 'guardada' WHERE filaid = r.filaid;
      ELSIF j->>'motivo' IN ('folga', 'sem_pessoa') THEN
        UPDATE public.mensagensfila SET status = 'descartada', erro = j->>'motivo' WHERE filaid = r.filaid;
      ELSE
        UPDATE public.mensagensfila SET proximaem = coalesce((j->>'proxima')::timestamptz, now() + interval '1 hour')
         WHERE filaid = r.filaid;
      END IF;
      CONTINUE;
    END IF;

    -- 2) Limite diário por pessoa.
    IF r.automatica AND r.funcionarioid IS NOT NULL THEN
      v_max := coalesce(nullif(btrim((SELECT valor FROM public.configuracoes
                                       WHERE contaid = r.contaid AND chave = 'MAX_MENSAGENS_AUTOMATICAS_DIA')), '')::integer, 8);
      IF public.bot_enviadas_hoje(r.contaid, r.funcionarioid, now()) >= v_max THEN
        IF r.naoreenviar THEN
          UPDATE public.mensagensfila SET status = 'descartada', erro = 'limite do dia' WHERE filaid = r.filaid;
        ELSE
          UPDATE public.mensagensfila
             SET proximaem = public.instante_local(public.dia_em_sao_paulo(now()) + 1, '00:01')
           WHERE filaid = r.filaid;
        END IF;
        CONTINUE;
      END IF;
    END IF;

    -- 3) Limite do Telegram: 18 por minuto no grupo, 3 por rodada no privado.
    v_n := coalesce((v_cont->>(r.chatid::text))::integer,
                    CASE WHEN r.chatid < 0 THEN (SELECT count(*)::integer FROM public.mensagensfila
                                                  WHERE chatid = r.chatid AND status = 'enviada'
                                                    AND enviadoem > now() - interval '1 minute') ELSE 0 END);
    CONTINUE WHEN (r.chatid < 0 AND v_n >= 18) OR (r.chatid > 0 AND v_n >= 3);
    v_cont := v_cont || jsonb_build_object(r.chatid::text, v_n + 1);

    -- 4) O que vai na mensagem.
    IF r.tipo IN ('entrega_nova', 'editar_entrega') THEN
      l := public.bot_legenda_entrega(r.referencia);
      IF l IS NULL OR (r.tipo = 'entrega_nova' AND NOT (l->>'pendente')::boolean) THEN
        UPDATE public.mensagensfila SET status = 'descartada' WHERE filaid = r.filaid;
        CONTINUE;
      END IF;
      IF r.tipo = 'entrega_nova' THEN
        v_env := jsonb_build_object('metodo', CASE WHEN (l->>'temfoto')::boolean THEN 'sendPhoto' ELSE 'sendMessage' END,
                                    'texto', l->>'texto', 'foto_tg', l->'foto_tg', 'foto_storage', l->'foto_storage',
                                    'botoes', l->'botoes');
      ELSE
        v_env := jsonb_build_object('metodo', CASE WHEN (l->>'temfoto')::boolean THEN 'editMessageCaption' ELSE 'editMessageText' END,
                                    'texto', l->>'texto', 'message_id',
                                    (SELECT avisomsgid FROM public.entregas WHERE entregaid = r.referencia));
      END IF;

    ELSIF r.tipo IN ('inicio_jornada', 'lembrete3', 'lembrete6', 'fim_jornada', 'comunicado_novo',
                     'comunicado_lembrete', 'folga_drop', 'missao', 'resumo_ausencia') THEN
      v_env := public.bot_texto_rotina(r.tipo, r.contaid, r.funcionarioid, r.referencia);
      IF v_env IS NULL THEN
        UPDATE public.mensagensfila SET status = 'descartada', erro = 'nao faz mais sentido' WHERE filaid = r.filaid;
        CONTINUE;
      END IF;

    ELSIF r.juntarchave IS NOT NULL THEN
      SELECT jsonb_agg(m.conteudo ORDER BY m.filaid), array_agg(m.filaid)
        INTO v_irmas, v_ids
        FROM public.mensagensfila m
       WHERE m.contaid = r.contaid AND m.chatid = r.chatid AND m.juntarchave = r.juntarchave
         AND m.status = 'pendente' AND m.proximaem <= now() AND m.filaid <> r.filaid;
      IF v_irmas IS NULL THEN
        v_env := r.conteudo;
      ELSE
        UPDATE public.mensagensfila SET status = 'descartada', erro = 'juntada' WHERE filaid = ANY (v_ids);
        v_env := jsonb_build_object('metodo', 'sendMessage',
                   'texto', public.bot_texto_juntado(jsonb_build_array(r.conteudo) || v_irmas));
      END IF;
    ELSE
      v_env := r.conteudo;
    END IF;

    UPDATE public.mensagensfila SET status = 'enviando', tentativas = tentativas + 1, proximaem = now() WHERE filaid = r.filaid;
    v_out := v_out || jsonb_build_array(v_env || jsonb_build_object('filaid', r.filaid, 'chat_id', r.chatid, 'tipo', r.tipo));
  END LOOP;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_fila_resultado(p_filaid bigint, p_ok boolean, p_msgid bigint, p_erro text, p_esperar integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE r public.mensagensfila%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = p_filaid FOR UPDATE;
  IF NOT FOUND OR r.status <> 'enviando' THEN RETURN; END IF;

  IF p_ok THEN
    UPDATE public.mensagensfila SET status = 'enviada', enviadoem = now(), erro = NULL WHERE filaid = p_filaid;
    PERFORM public.usar_mensagens(r.contaid, r.lojaid, 'telegram', r.tipo, 1);
    IF r.tipo = 'entrega_nova' AND p_msgid IS NOT NULL THEN
      UPDATE public.entregas SET avisochatid = r.chatid, avisomsgid = p_msgid
       WHERE entregaid = r.referencia AND contaid = r.contaid;
    END IF;
    RETURN;
  END IF;

  -- Bloqueado, expulso do grupo ou conta apagada: para de tentar.
  IF p_erro ~* '(blocked|deactivated|kicked|chat not found|chat_id is empty)' THEN
    UPDATE public.mensagensfila SET status = 'falhou', erro = left(p_erro, 300) WHERE filaid = p_filaid;
    PERFORM public.bot_marcar_bloqueio(r.contaid, r.chatid, p_erro);
    RETURN;
  END IF;

  IF coalesce(p_esperar, 0) > 0 THEN                    -- o Telegram pediu para esperar: não foi enviada
    UPDATE public.mensagensfila SET status = 'pendente', proximaem = now() + make_interval(secs => p_esperar),
           erro = left(p_erro, 300) WHERE filaid = p_filaid;
  ELSIF r.naoreenviar OR r.tentativas >= 5 THEN         -- rotina não repete
    UPDATE public.mensagensfila SET status = 'falhou', erro = left(p_erro, 300) WHERE filaid = p_filaid;
  ELSE
    UPDATE public.mensagensfila SET status = 'pendente', proximaem = now() + make_interval(mins => power(2, r.tentativas)::integer),
           erro = left(p_erro, 300) WHERE filaid = p_filaid;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Avisos da pessoa: agora sabem de quem são (para o limite e a folga)
-- ---------------------------------------------------------------------------
ALTER TABLE public.rotinasexecucoes DROP CONSTRAINT rotinasexecucoes_rotina_check;
ALTER TABLE public.rotinasexecucoes ADD CONSTRAINT rotinasexecucoes_rotina_check
  CHECK (rotina IN ('lista_do_dia', 'fechamento_mensal', 'conferencia_livro', 'limpeza', 'mensagens'));

CREATE OR REPLACE FUNCTION public.bot_aviso_entrega()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_titulo text; v_chat bigint;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.statusvalidacao = 'Pendente' THEN
      PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, public.bot_chat_do_grupo(NEW.contaid, NEW.lojaid, 'gestao'),
                                    'entrega_nova', '{}', NEW.entregaid);
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.statusvalidacao = 'Pendente' AND NEW.statusvalidacao IN ('Aprovada', 'Recusada') THEN
    SELECT titulo INTO v_titulo FROM public.tarefas WHERE tarefaid = NEW.tarefaid;
    v_chat := public.bot_chat_da_pessoa(NEW.contaid, NEW.funcionarioid);
    IF NEW.statusvalidacao = 'Aprovada' THEN
      -- Espera 2 minutos: várias aprovações seguidas viram uma mensagem só.
      PERFORM public.bot_enfileirar_ex(NEW.contaid, NEW.lojaid, v_chat, NEW.funcionarioid, 'entrega_aprovada',
        jsonb_build_object('metodo', 'sendMessage', 'titulo', v_titulo, 'pontos', coalesce(NEW.pontosganhos, 0),
          'texto', '✅ Sua entrega <b>' || public.bot_html(v_titulo) || '</b> foi aprovada! +'
                   || coalesce(NEW.pontosganhos, 0) || ' pontos.'),
        NEW.entregaid, NULL,
        'aprovadas:' || NEW.funcionarioid || ':' || public.dia_em_sao_paulo(now()), false, now() + interval '2 minutes');
    ELSE
      PERFORM public.bot_enfileirar_ex(NEW.contaid, NEW.lojaid, v_chat, NEW.funcionarioid, 'entrega_recusada',
        jsonb_build_object('metodo', 'sendMessage', 'texto',
          '❌ Sua entrega <b>' || public.bot_html(v_titulo) || E'</b> foi recusada.\nMotivo: '
          || public.bot_html(NEW.motivorecusa) || E'\n\nVocê pode enviar de novo em 📋 Minhas tarefas.'),
        NEW.entregaid, NULL, NULL, false, now());
    END IF;
    IF NEW.avisomsgid IS NOT NULL AND coalesce(NEW.canalvalidacao, 'app') <> 'telegram' THEN
      PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, NEW.avisochatid, 'editar_entrega', '{}', NEW.entregaid);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_aviso_conquista()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE k public.conquistas%ROWTYPE;
BEGIN
  SELECT * INTO k FROM public.conquistas WHERE conquistaid = NEW.conquistaid;
  PERFORM public.bot_enfileirar_ex(NEW.contaid, NULL, public.bot_chat_da_pessoa(NEW.contaid, NEW.funcionarioid),
    NEW.funcionarioid, 'conquista',
    jsonb_build_object('metodo', 'sendMessage', 'texto',
      '🏅 Nova conquista: ' || coalesce(k.icone, '') || ' <b>' || public.bot_html(k.nome) || '</b>!'
      || CASE WHEN coalesce(NEW.pontosbonus, 0) > 0 THEN ' +' || NEW.pontosbonus || ' pontos de bônus.' ELSE '' END),
    NEW.conquistafuncionarioid, NULL, NULL, false, now());
  RETURN NEW;
END;
$$;

-- Comunicado novo: chega com o botão "Estou ciente" (uma vez por pessoa).
CREATE OR REPLACE FUNCTION public.bot_aviso_comunicado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.statusassinatura = 'Pendente'
     AND public.rotina_ligada_pessoa(NEW.contaid, NEW.funcionarioid, 'comunicado_novo') THEN
    PERFORM public.bot_enfileirar_ex(NEW.contaid, NULL, public.bot_chat_da_pessoa(NEW.contaid, NEW.funcionarioid),
      NEW.funcionarioid, 'comunicado_novo', '{}', NEW.assinaturaid,
      'com:' || NEW.assinaturaid, NULL, false, now());
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER documentosassinaturas_aviso_telegram AFTER INSERT ON public.documentosassinaturas
  FOR EACH ROW EXECUTE FUNCTION public.bot_aviso_comunicado();

-- ---------------------------------------------------------------------------
-- 11. O motor das rotinas com mensagem
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rotina_mensagens(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje    date;
  v_hora    time;
  v_inicio  timestamptz := clock_timestamp();
  v_n       integer := 0;
  p         record;
  j         record;
  l         record;
  m         record;
  a         record;
  d         date;
  v_chat    bigint;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;

  -- ---- Por pessoa (quem tem o Telegram ligado e não bloqueou o bot) -------
  FOR p IN
    SELECT f.funcionarioid, v.chatid
      FROM public.funcionarios f
      JOIN public.telegramvinculos v ON v.funcionarioid = f.funcionarioid AND v.contaid = p_contaid
                                    AND v.tipo = 'pessoa' AND v.ativo AND v.bloqueadoem IS NULL
     WHERE f.contaid = p_contaid AND f.ativo
  LOOP
    -- Voltou da folga ou do afastamento: um resumo só do que ficou guardado.
    IF EXISTS (SELECT 1 FROM public.mensagensfila
                WHERE contaid = p_contaid AND funcionarioid = p.funcionarioid AND status = 'guardada')
       AND (public.bot_janela(p_contaid, p.funcionarioid, p_agora)->>'pode')::boolean THEN
      IF public.bot_enfileirar_ex(p_contaid, NULL, p.chatid, p.funcionarioid, 'resumo_ausencia', '{}',
           p.funcionarioid, 'resumo:' || p.funcionarioid || ':' || v_hoje, NULL, true, p_agora) IS NOT NULL THEN
        v_n := v_n + 1;
      END IF;
    END IF;

    -- Jornada: o turno que começou hoje e o que começou ontem (turno da noite).
    FOREACH d IN ARRAY ARRAY[v_hoje - 1, v_hoje] LOOP
      SELECT * INTO j FROM public.jornada_da_pessoa(p_contaid, p.funcionarioid, d);
      CONTINUE WHEN NOT FOUND OR NOT j.trabalha OR NOT j.temhorario;

      IF p_agora >= j.inicio AND p_agora < j.inicio + interval '2 hours'
         AND public.rotina_ligada_pessoa(p_contaid, p.funcionarioid, 'inicio_jornada')
         AND public.bot_enfileirar_ex(p_contaid, NULL, p.chatid, p.funcionarioid, 'inicio_jornada', '{}', NULL,
               'inicio:' || p.funcionarioid || ':' || d, NULL, true, p_agora) IS NOT NULL THEN
        v_n := v_n + 1;
      END IF;

      IF p_agora >= j.inicio + interval '3 hours' AND p_agora < least(j.inicio + interval '6 hours', j.fim)
         AND public.rotina_ligada_pessoa(p_contaid, p.funcionarioid, 'lembrete3')
         AND public.bot_enfileirar_ex(p_contaid, NULL, p.chatid, p.funcionarioid, 'lembrete3', '{}', NULL,
               'lembrete3:' || p.funcionarioid || ':' || d, NULL, true, p_agora) IS NOT NULL THEN
        v_n := v_n + 1;
      END IF;

      IF p_agora >= j.inicio + interval '6 hours' AND p_agora < j.fim
         AND public.rotina_ligada_pessoa(p_contaid, p.funcionarioid, 'lembrete6')
         AND public.bot_enfileirar_ex(p_contaid, NULL, p.chatid, p.funcionarioid, 'lembrete6', '{}', NULL,
               'lembrete6:' || p.funcionarioid || ':' || d, NULL, true, p_agora) IS NOT NULL THEN
        v_n := v_n + 1;
      END IF;

      IF p_agora >= j.fim AND p_agora < j.fim + interval '25 minutes'
         AND public.rotina_ligada_pessoa(p_contaid, p.funcionarioid, 'fim_jornada')
         AND public.bot_enfileirar_ex(p_contaid, NULL, p.chatid, p.funcionarioid, 'fim_jornada', '{}', NULL,
               'fim:' || p.funcionarioid || ':' || d, NULL, true, p_agora) IS NOT NULL THEN
        v_n := v_n + 1;
      END IF;
    END LOOP;
  END LOOP;

  -- ---- Lembrete de comunicado sem ciência há mais de 24 h -----------------
  IF v_hora >= public.rotina_horario(p_contaid, 'HORARIO_LEMBRETE_COMUNICADOS', '09:00') THEN
    FOR a IN
      SELECT s.assinaturaid, s.funcionarioid, public.bot_chat_da_pessoa(p_contaid, s.funcionarioid) AS chatid
        FROM public.documentosassinaturas s
        JOIN public.documentos doc ON doc.documentoid = s.documentoid AND doc.contaid = p_contaid
                                  AND doc.status = 'Publicado'
       WHERE s.contaid = p_contaid AND s.statusassinatura = 'Pendente'
         AND s.dataenvio < p_agora - interval '24 hours'
         AND public.rotina_ligada_pessoa(p_contaid, s.funcionarioid, 'comunicado_lembrete')
       LIMIT 200
    LOOP
      IF a.chatid IS NOT NULL
         AND public.bot_enfileirar_ex(p_contaid, NULL, a.chatid, a.funcionarioid, 'comunicado_lembrete', '{}',
               a.assinaturaid, 'com24:' || a.assinaturaid, NULL, true, p_agora) IS NOT NULL THEN
        v_n := v_n + 1;
      END IF;
    END LOOP;
  END IF;

  -- ---- Por loja: tarefas de folga e missões (no grupo da equipe) ----------
  FOR l IN SELECT lojaid FROM public.lojas WHERE contaid = p_contaid AND ativa LOOP
    v_chat := public.bot_chat_do_grupo(p_contaid, l.lojaid, 'equipe');
    CONTINUE WHEN v_chat IS NULL;

    IF v_hora >= public.rotina_horario(p_contaid, 'HORARIO_DELEGACAO_FOLGA', '09:05')
       AND v_hora < public.rotina_horario(p_contaid, 'HORARIO_DELEGACAO_FOLGA', '09:05') + interval '2 hours'
       AND public.rotina_ligada(p_contaid, l.lojaid, 'folga_drop')
       AND public.bot_enfileirar_ex(p_contaid, l.lojaid, v_chat, NULL, 'folga_drop', '{}', l.lojaid,
             'folga:' || l.lojaid || ':' || v_hoje, NULL, true, p_agora) IS NOT NULL THEN
      v_n := v_n + 1;
    END IF;

    IF public.rotina_ligada(p_contaid, l.lojaid, 'missao') THEN
      FOR m IN
        SELECT ta.atribuicaoid, ta.horariodisparo
          FROM public.tarefasatribuidas ta
          JOIN public.tarefas t ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid AND coalesce(t.ativa, true)
         WHERE ta.contaid = p_contaid AND ta.lojaid = l.lojaid AND ta.funcionarioid IS NULL
           AND ta.horariodisparo IS NOT NULL AND ta.datafimvigencia IS NULL
           AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje)
      LOOP
        IF v_hora >= m.horariodisparo AND v_hora < m.horariodisparo + interval '2 hours'
           AND public.bot_enfileirar_ex(p_contaid, l.lojaid, v_chat, NULL, 'missao', '{}', m.atribuicaoid,
                 'missao:' || m.atribuicaoid || ':' || v_hoje, NULL, true, p_agora) IS NOT NULL THEN
          v_n := v_n + 1;
        END IF;
      END LOOP;
    END IF;
  END LOOP;

  IF v_n > 0 THEN
    PERFORM public.rotina_registrar(p_contaid, 'mensagens', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('mensagens', v_n), NULL, false);
  END IF;
  RETURN jsonb_build_object('mensagens', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.rotinas_despachar(p_agora timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c       record;
  v_n     integer := 0;
  v_erros integer := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(7310) THEN
    RETURN jsonb_build_object('ocupado', true);
  END IF;

  FOR c IN SELECT contaid FROM public.contas WHERE status = 'ativa' ORDER BY contaid LOOP
    BEGIN
      PERFORM public.rotina_lista_do_dia(c.contaid, p_agora, 'agendada');
      PERFORM public.rotina_fechamento_mensal(c.contaid, p_agora);
      PERFORM public.rotina_conferencia_livro(c.contaid, p_agora);
      PERFORM public.rotina_limpeza(c.contaid, p_agora);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      PERFORM public.rotina_registrar(c.contaid, 'lista_do_dia', NULL, 'agendada', clock_timestamp(), 'erro', NULL, SQLERRM);
    END;
    -- As mensagens ficam num bloco próprio: um erro aqui não atrapalha a lista do dia.
    BEGIN
      PERFORM public.rotina_mensagens(c.contaid, p_agora);
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      PERFORM public.rotina_registrar(c.contaid, 'mensagens', NULL, 'agendada', clock_timestamp(), 'erro', NULL, SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('contas', v_n, 'erros', v_erros);
END;
$$;
-- ---------------------------------------------------------------------------
-- 12. "O primeiro que clicar" pelo grupo da equipe
-- ---------------------------------------------------------------------------
-- Quem apertou o botão no grupo: tem de ser uma pessoa da mesma conta, ativa,
-- com o Telegram ligado e que trabalha hoje.
CREATE OR REPLACE FUNCTION public.bot_pessoa_do_grupo(p_chatgrupo bigint, p_usuario bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE g jsonb := public.bot_grupo(p_chatgrupo); r record;
BEGIN
  IF NOT (g->>'vinculado')::boolean THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'grupo');
  END IF;
  SELECT v.funcionarioid, f.nomecompleto INTO r
    FROM public.telegramvinculos v
    JOIN public.funcionarios f ON f.funcionarioid = v.funcionarioid AND f.contaid = v.contaid AND f.ativo
   WHERE v.chatid = p_usuario AND v.contaid = (g->>'contaid')::integer AND v.tipo = 'pessoa' AND v.ativo;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_vinculo');
  END IF;
  RETURN g || jsonb_build_object('ok', true, 'funcionarioid', r.funcionarioid,
                                 'nome', public.nome_curto(r.nomecompleto));
END;
$$;

-- Pegar uma tarefa de quem está de folga (mesma função do "Passar para…").
CREATE OR REPLACE FUNCTION public.bot_pegar_folga(p_chatgrupo bigint, p_usuario bigint, p_atribuicaoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  q      jsonb := public.bot_pessoa_do_grupo(p_chatgrupo, p_usuario);
  v_hoje date  := public.dia_em_sao_paulo(now());
  v_max  integer;
  v_tit  text;
BEGIN
  IF NOT (q->>'ok')::boolean THEN RETURN q; END IF;
  v_max := coalesce(nullif(btrim((SELECT valor FROM public.configuracoes
                                   WHERE contaid = (q->>'contaid')::integer
                                     AND chave = 'MAX_TAREFAS_FOLGA_POR_PESSOA')), '')::integer, 3);
  IF (SELECT count(*) FROM public.tarefasdodia
       WHERE contaid = (q->>'contaid')::integer AND dia = v_hoje
         AND passadapara = (q->>'funcionarioid')::integer) >= v_max THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'limite', 'max', v_max, 'nome', q->>'nome');
  END IF;

  PERFORM public.bot_entrar((q->>'contaid')::integer, (q->>'funcionarioid')::integer, NULL);
  BEGIN
    PERFORM public.passar_tarefa_de_folga(p_atribuicaoid, (q->>'funcionarioid')::integer);
  EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('ok', false, 'erro', 'ja_pega', 'mensagem', SQLERRM);
    WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  SELECT t.titulo INTO v_tit FROM public.tarefasatribuidas ta
    JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
   WHERE ta.atribuicaoid = p_atribuicaoid;
  RETURN jsonb_build_object('ok', true, 'titulo', v_tit, 'nome', q->>'nome', 'lojaid', (q->>'lojaid')::integer);
END;
$$;

-- Aceitar a missão da equipe.
CREATE OR REPLACE FUNCTION public.bot_pegar_missao(p_chatgrupo bigint, p_usuario bigint, p_atribuicaoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb := public.bot_pessoa_do_grupo(p_chatgrupo, p_usuario); v_tit text;
BEGIN
  IF NOT (q->>'ok')::boolean THEN RETURN q; END IF;
  PERFORM public.bot_entrar((q->>'contaid')::integer, (q->>'funcionarioid')::integer, NULL);
  BEGIN
    PERFORM public.pegar_missao(p_atribuicaoid, (q->>'funcionarioid')::integer);
  EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('ok', false, 'erro', 'ja_pega', 'mensagem', SQLERRM);
    WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  SELECT t.titulo INTO v_tit FROM public.tarefasatribuidas ta
    JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
   WHERE ta.atribuicaoid = p_atribuicaoid;
  RETURN jsonb_build_object('ok', true, 'titulo', v_tit, 'nome', q->>'nome');
END;
$$;

-- Texto atualizado da mensagem do grupo (depois de alguém pegar uma tarefa).
CREATE OR REPLACE FUNCTION public.bot_texto_grupo(p_chatgrupo bigint, p_tipo text, p_referencia integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE g jsonb := public.bot_grupo(p_chatgrupo);
BEGIN
  IF NOT (g->>'vinculado')::boolean OR p_tipo NOT IN ('folga_drop', 'missao') THEN
    RETURN NULL;
  END IF;
  RETURN public.bot_texto_rotina(p_tipo, (g->>'contaid')::integer, NULL, p_referencia);
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Telas: horário da equipe
-- ---------------------------------------------------------------------------
-- Aplica o mesmo horário a uma ou a várias pessoas de uma vez.
CREATE OR REPLACE FUNCTION public.definir_horario_equipe(p_funcionarios integer[], p_entrada time, p_saida time)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel(); v_n integer;
BEGIN
  IF p_entrada IS NULL AND p_saida IS NOT NULL THEN
    RAISE EXCEPTION 'Para ter hora de saída, a pessoa precisa ter hora de entrada.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.funcionarios
     SET horarionotificacao = p_entrada, horariosaida = CASE WHEN p_entrada IS NULL THEN NULL ELSE p_saida END
   WHERE contaid = v_conta AND funcionarioid = ANY (p_funcionarios) AND ativo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  -- Internas (rotinas e peças): ninguém chama direto.
  FOREACH f IN ARRAY ARRAY[
    'public.instante_local(date, time)', 'public.jornada_da_pessoa(integer, integer, date)',
    'public.no_silencio(integer, time)', 'public.bot_janela(integer, integer, timestamptz)',
    'public.bot_enviadas_hoje(integer, integer, timestamptz)', 'public.rotina_ligada(integer, integer, text)',
    'public.rotina_ligada_pessoa(integer, integer, text)', 'public.rotina_mensagens(integer, timestamptz)',
    'public.bot_enfileirar_ex(integer, integer, bigint, integer, text, jsonb, integer, text, text, boolean, timestamptz)',
    'public.bot_marcar_bloqueio(integer, bigint, text)', 'public.bot_texto_juntado(jsonb)',
    'public.bot_abertas_da_pessoa(integer, integer)', 'public.bot_lista_tarefas(jsonb)',
    'public.bot_resumo_ausencia(integer, integer)', 'public.bot_texto_rotina(text, integer, integer, integer)',
    'public.bot_aviso_comunicado()', 'public.pegar_missao(integer, integer)',
    'public.bot_pessoa_do_grupo(bigint, bigint)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
  END LOOP;

  -- O webhook e a fila (Edge Functions, com a chave de servidor).
  FOREACH f IN ARRAY ARRAY[
    'public.bot_visto(bigint)', 'public.bot_pegar_folga(bigint, bigint, integer)',
    'public.bot_pegar_missao(bigint, bigint, integer)', 'public.bot_texto_grupo(bigint, text, integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;

  -- As telas do master.
  FOREACH f IN ARRAY ARRAY[
    'public.definir_rotina_mensagem(integer, text, boolean)',
    'public.definir_horario_equipe(integer[], time, time)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $$;
