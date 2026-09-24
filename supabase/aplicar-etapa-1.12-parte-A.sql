-- =========================================================================
-- STGame — Etapa 1.12, parte A: TUDO O QUE FALTA NO BANCO, num arquivo só.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Leva alguns segundos. Se der erro, NADA é aplicado (roda tudo junto ou
-- nada), e é só me mandar a mensagem.
--
-- Pode rodar duas vezes sem problema: tudo aqui confere antes de criar.
--
-- Este arquivo é a junção destas migrações, na ordem:
--   20260927100000_correcao_janela_fora_do_turno.sql
--   20260927100100_expurgo_fotos_entrega.sql
--   20260927100200_cpf_e_limpeza.sql
--   20260927100300_acessos_papeis_e_contexto.sql
--   20260927100400_pin_e_travas.sql
--   20260927100500_acesso_por_codigo_e_senha_propria.sql
--   20260927100600_travas_atomicas_e_senha_do_gestor.sql
--   20260927100700_trava_sem_bloquear_o_dono.sql
--   20260927100800_pin_tablet_e_expurgo.sql
--   20260927100900_diagnostico_do_sistema.sql
-- =========================================================================

BEGIN;

-- =========================================================================
-- 20260927100000_correcao_janela_fora_do_turno.sql
-- =========================================================================

-- Correção da Etapa 1.13B1: aviso gerado DEPOIS do fim do turno.
--
-- Defeito encontrado em 23/09/2026 (o teste de isolamento só passava se
-- rodasse entre 08:00 e 17:30, por causa disto):
--   bot_janela procurava a próxima entrada a partir de hoje e, quando ela caía
--   em outro dia, devolvia motivo 'folga'. Só que o fim normal do expediente
--   cai exatamente nesse caso: quem trabalha das 08:00 às 17:00 e tem uma
--   entrega aprovada às 18:00 era tratado como se estivesse de folga.
--   Resultado: o aviso virava 'guardada', não chegava na entrada seguinte e
--   voltava só como resumo ("1 entrega aprovada"), perdendo o conteúdo — ou
--   sumia de vez, se ficasse guardado mais de 7 dias.
--
-- Regra certa (é o que o plano já dizia): quem TRABALHA hoje e está fora do
-- turno espera a próxima entrada ('fora_do_turno'). 'folga' fica só para quem
-- realmente não trabalha hoje — aí sim o aviso é guardado e vira resumo na
-- volta.
--
-- Só muda o motivo devolvido; o resto de bot_janela é igual ao da 1.13B1.

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
  v_trabalha_hoje boolean;
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

  -- Guardado antes do laço abaixo, que reaproveita a variável j.
  v_trabalha_hoje := j.trabalha;

  IF j.temhorario THEN
    -- Dentro do turno de hoje ou do que começou ontem (turno da noite)?
    IF EXISTS (
      SELECT 1 FROM generate_series(v_hoje - 1, v_hoje, interval '1 day') g
       CROSS JOIN LATERAL public.jornada_da_pessoa(p_contaid, p_funcionarioid, g::date) t
       WHERE t.trabalha AND p_agora >= t.inicio AND p_agora <= t.fim + interval '30 minutes') THEN
      RETURN jsonb_build_object('pode', true);
    END IF;
    -- Fora do turno: espera o próximo começo (até 8 dias à frente).
    -- Quem trabalha hoje está só fora do horário, não de folga: o aviso espera
    -- a próxima entrada, mesmo que ela seja amanhã.
    FOR d IN SELECT g::date FROM generate_series(v_hoje, v_hoje + 8, interval '1 day') g LOOP
      SELECT * INTO j FROM public.jornada_da_pessoa(p_contaid, p_funcionarioid, d);
      IF j.trabalha AND j.inicio > p_agora THEN
        RETURN jsonb_build_object('pode', false,
          'motivo', CASE WHEN d = v_hoje OR v_trabalha_hoje THEN 'fora_do_turno' ELSE 'folga' END,
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

-- Continua interna (só o servidor chama, pelas funções da fila).
REVOKE ALL ON FUNCTION public.bot_janela(integer, integer, timestamptz) FROM public, anon, authenticated;


-- =========================================================================
-- 20260927100100_expurgo_fotos_entrega.sql
-- =========================================================================

-- Expurgo automático das fotos de entrega (decisão do Wisley, 23/09/2026).
--
-- A política de uso diz que a foto é guardada por tempo limitado e depois
-- apagada. Isto faz a frase virar verdade.
--
-- Regras:
--   * Prazo POR CONTA em configuracoes: DIAS_GUARDAR_FOTO_ENTREGA, padrão 180,
--     mínimo 90. O master muda na tela Configurações.
--   * Apaga só o ARQUIVO. O registro da entrega, os pontos e o histórico ficam
--     de pé: a entrega passa a mostrar "foto removida por tempo"
--     (entregas.fotoexpiradaem).
--   * NÃO vale para documento de RH, que tem regra própria (documentospessoais).
--   * SQL não apaga arquivo do Storage. Então a rotina só marca e guarda o
--     caminho numa fila (fotosexpurgo); quem apaga de verdade é a Edge Function
--     expurgo-fotos, no mesmo molde da fila do Telegram (pg_net + Vault +
--     cabeçalho secreto + chave de servidor).
--   * fotoidunico NÃO é apagado: é a marca que impede reenviar a mesma foto.

-- ---------------------------------------------------------------------------
-- 1. Marca na entrega
-- ---------------------------------------------------------------------------
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS fotoexpiradaem timestamptz;
COMMENT ON COLUMN public.entregas.fotoexpiradaem IS
  'Quando a foto foi apagada por tempo. Preenchida pela rotina de expurgo; a entrega continua valendo.';

-- ---------------------------------------------------------------------------
-- 2. Fila do que precisa sair do Storage
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fotosexpurgo (
  expurgoid   integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid     integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  entregaid   integer NOT NULL,
  caminho     text NOT NULL,
  criadoem    timestamptz NOT NULL DEFAULT now(),
  removidoem  timestamptz,
  tentativas  integer NOT NULL DEFAULT 0,
  erro        text,
  CONSTRAINT fotosexpurgo_entrega_fk FOREIGN KEY (contaid, entregaid)
    REFERENCES public.entregas (contaid, entregaid) ON DELETE RESTRICT,
  CONSTRAINT fotosexpurgo_conta_unico UNIQUE (contaid, expurgoid)
);
CREATE INDEX IF NOT EXISTS fotosexpurgo_pendentes_idx ON public.fotosexpurgo (criadoem) WHERE removidoem IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS fotosexpurgo_caminho_unico ON public.fotosexpurgo (contaid, caminho);

-- Ninguém lê nem escreve pelo navegador: é serviço interno, e o caminho do
-- arquivo não interessa a nenhuma tela. RLS ligada e sem policy = nega tudo.
ALTER TABLE public.fotosexpurgo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fotosexpurgo FROM anon, authenticated;
GRANT ALL ON public.fotosexpurgo TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Configuração nova (prazo em dias) — funções recriadas por inteiro
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
    (p_contaid, 'DIAS_GUARDAR_FOTO_ENTREGA',     '180',   'Por quantos dias a foto da entrega fica guardada. Depois disso o arquivo é apagado; a entrega e os pontos ficam. Mínimo 90.'),
    (p_contaid, 'HORARIO_GERACAO_TAREFAS',       '00:05', 'Hora em que a lista de tarefas do dia é gerada.'),
    (p_contaid, 'HORARIO_CONFERENCIA_LIVRO',     '03:00', 'Hora da conferência diária do livro de pontos, da limpeza do registro de rotinas e do expurgo de fotos.'),
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
    (p_contaid, 'CONTATO_PRIVACIDADE',           '',      'Nome e contato de quem responde sobre dados pessoais (aparece na política de uso).'),
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

  -- Prazo da foto: nunca menos de 90 dias (a política de uso promete um prazo,
  -- e um prazo curto demais apagaria prova de entrega ainda em discussão).
  ELSIF NEW.chave = 'DIAS_GUARDAR_FOTO_ENTREGA' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O prazo precisa ser um número inteiro de dias.' USING ERRCODE = 'check_violation';
    END IF;
    IF v_texto::integer < 90 OR v_texto::integer > 3650 THEN
      RAISE EXCEPTION 'O prazo precisa ser de 90 a 3650 dias.' USING ERRCODE = 'check_violation';
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

  ELSIF NEW.chave = 'CONTATO_PRIVACIDADE' THEN
    IF length(v_texto) > 200 THEN
      RAISE EXCEPTION 'O contato pode ter no máximo 200 letras.' USING ERRCODE = 'check_violation';
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
-- 4. A rotina
-- ---------------------------------------------------------------------------
ALTER TABLE public.rotinasexecucoes DROP CONSTRAINT IF EXISTS rotinasexecucoes_rotina_check;
ALTER TABLE public.rotinasexecucoes DROP CONSTRAINT IF EXISTS rotinasexecucoes_rotina_check;
ALTER TABLE public.rotinasexecucoes ADD CONSTRAINT rotinasexecucoes_rotina_check
  CHECK (rotina IN ('lista_do_dia', 'fechamento_mensal', 'conferencia_livro', 'limpeza', 'mensagens', 'expurgo_fotos'));

-- Avisa a Edge Function que há arquivo para apagar (pg_net). Sem pg_net/Vault
-- (testes), não faz nada: a rotina do dia seguinte tenta de novo.
CREATE OR REPLACE FUNCTION public.fotos_expurgo_disparar()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_url text; v_segredo text;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NULL OR to_regproc('net.http_post') IS NULL THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fotosexpurgo WHERE removidoem IS NULL AND tentativas < 5) THEN
    RETURN;
  END IF;
  EXECUTE $q$SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'stgame_funcoes_url'$q$ INTO v_url;
  EXECUTE $q$SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'stgame_expurgo_segredo'$q$ INTO v_segredo;
  IF v_url IS NULL OR v_segredo IS NULL THEN
    RETURN;
  END IF;
  EXECUTE 'SELECT net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 60000)'
    USING rtrim(v_url, '/') || '/expurgo-fotos', '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-expurgo-segredo', v_segredo);
END;
$$;

-- Quantos dias esta conta guarda a foto (mínimo 90, mesmo se alguém gravar
-- um valor esquisito direto no banco).
CREATE OR REPLACE FUNCTION public.dias_guardar_foto(p_contaid integer)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT greatest(90, coalesce((SELECT nullif(btrim(valor), '')::integer
                                  FROM public.configuracoes
                                 WHERE contaid = p_contaid AND chave = 'DIAS_GUARDAR_FOTO_ENTREGA'), 180))
$$;

-- Marca as fotos vencidas e põe o caminho na fila de remoção. Uma vez por dia,
-- depois do horário da conferência. No máximo 2.000 por rodada, para não
-- travar o banco numa conta com muita foto antiga.
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    WITH vencidas AS (
      SELECT e.entregaid, e.pathfotoevidencia
        FROM public.entregas e
       WHERE e.contaid = p_contaid
         AND e.pathfotoevidencia IS NOT NULL
         AND e.fotoexpiradaem IS NULL
         AND e.dataenvio < p_agora - make_interval(days => v_dias)
       ORDER BY e.dataenvio
       LIMIT 2000
    ), na_fila AS (
      INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
      SELECT p_contaid, v.entregaid, v.pathfotoevidencia FROM vencidas v
      ON CONFLICT (contaid, caminho) DO NOTHING
      RETURNING entregaid
    )
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM vencidas v
     WHERE e.contaid = p_contaid AND e.entregaid = v.entregaid;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('fotos', v_n, 'dias', v_dias), NULL);
    IF v_n > 0 THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;
    RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Quem apaga o arquivo: a Edge Function expurgo-fotos
-- ---------------------------------------------------------------------------

-- A Edge Function pede a lista do que apagar (só a chave de servidor chama).
CREATE OR REPLACE FUNCTION public.expurgo_pegar(p_limite integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_out jsonb;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pode pedir a lista de expurgo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Conta a tentativa na hora de entregar a lista: se a Edge Function morrer no
  -- meio, o mesmo caminho não fica sendo tentado para sempre (para em 5).
  WITH alvo AS (
    SELECT expurgoid FROM public.fotosexpurgo
     WHERE removidoem IS NULL AND tentativas < 5
     ORDER BY criadoem
     LIMIT greatest(coalesce(p_limite, 100), 1)
     FOR UPDATE SKIP LOCKED
  ), pegos AS (
    UPDATE public.fotosexpurgo f
       SET tentativas = f.tentativas + 1
      FROM alvo a
     WHERE f.expurgoid = a.expurgoid
     RETURNING f.expurgoid, f.caminho, f.criadoem
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', expurgoid, 'caminho', caminho) ORDER BY criadoem), '[]'::jsonb)
    INTO v_out FROM pegos;
  RETURN v_out;
END;
$$;

-- A Edge Function conta o que apagou.
CREATE OR REPLACE FUNCTION public.expurgo_resultado(p_ids integer[], p_erro text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra o resultado do expurgo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_erro IS NULL THEN
    UPDATE public.fotosexpurgo SET removidoem = now(), erro = NULL
     WHERE expurgoid = ANY (p_ids) AND removidoem IS NULL;
  ELSE
    UPDATE public.fotosexpurgo SET erro = left(p_erro, 500)
     WHERE expurgoid = ANY (p_ids) AND removidoem IS NULL;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. O despachante passa a chamar o expurgo (função recriada por inteiro)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rotinas_despachar(p_agora timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE c record; v_n integer := 0; v_erros integer := 0;
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
      PERFORM public.rotina_expurgo_fotos(c.contaid, p_agora);
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
-- 7. Permissões: nada disso é do navegador
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rotina_expurgo_fotos(integer, timestamptz) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.fotos_expurgo_disparar()                   FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.dias_guardar_foto(integer)                 FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.rotinas_despachar(timestamptz)             FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.expurgo_pegar(integer)                     FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.expurgo_resultado(integer[], text)         FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.expurgo_pegar(integer)             TO service_role;
GRANT  EXECUTE ON FUNCTION public.expurgo_resultado(integer[], text) TO service_role;


-- =========================================================================
-- 20260927100200_cpf_e_limpeza.sql
-- =========================================================================

-- Etapa 1.12, parte A (1/3): CPF da equipe e limpeza do que veio do sistema
-- antigo.
--
-- O CPF passa a valer de verdade: é por ele que o colaborador entra no app.
-- Regras (decisões do Wisley, 23/09/2026):
--   * Guardado só com números (11 dígitos), validado com os dois dígitos
--     verificadores. "111.111.111-11" e afins são recusados.
--   * Único POR CONTA (não no mundo): a mesma pessoa pode trabalhar em duas
--     empresas clientes. Vale entre os ativos, para não travar recontratação.
--   * As colunas senhahash, verificadorcpf e nivelacesso são heranças mortas do
--     sistema Flask: nenhuma função e nenhuma tela usam. Saem agora, para
--     ninguém confundir com o acesso novo.

-- ---------------------------------------------------------------------------
-- 1. Só números, 11 dígitos, verificador certo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cpf_valido(p_cpf text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v text := regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g');
  d1 integer := 0;
  d2 integer := 0;
  i  integer;
BEGIN
  IF length(v) <> 11 THEN
    RETURN false;
  END IF;
  -- Todos os dígitos iguais passam na conta dos verificadores, mas não são CPF.
  IF v ~ '^(.)\1{10}$' THEN
    RETURN false;
  END IF;
  FOR i IN 1..9 LOOP
    d1 := d1 + substr(v, i, 1)::integer * (11 - i);
  END LOOP;
  d1 := 11 - (d1 % 11);
  IF d1 >= 10 THEN d1 := 0; END IF;
  IF d1 <> substr(v, 10, 1)::integer THEN
    RETURN false;
  END IF;
  FOR i IN 1..10 LOOP
    d2 := d2 + substr(v, i, 1)::integer * (12 - i);
  END LOOP;
  d2 := 11 - (d2 % 11);
  IF d2 >= 10 THEN d2 := 0; END IF;
  RETURN d2 = substr(v, 11, 1)::integer;
END;
$$;
COMMENT ON FUNCTION public.cpf_valido(text) IS 'CPF com 11 dígitos e verificadores certos (aceita com ou sem pontuação).';

-- Gatilho: guarda só os números e recusa CPF inválido.
CREATE OR REPLACE FUNCTION public.normaliza_cpf_funcionario()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.cpf := nullif(regexp_replace(coalesce(NEW.cpf, ''), '[^0-9]', '', 'g'), '');
  IF NEW.cpf IS NOT NULL AND NOT public.cpf_valido(NEW.cpf) THEN
    RAISE EXCEPTION 'CPF inválido. Confira os números.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

-- Os CPFs que já estão no banco (importação antiga) viram só números; os que
-- não passam na validação ficam vazios, para o master recadastrar.
UPDATE public.funcionarios
   SET cpf = nullif(regexp_replace(coalesce(cpf, ''), '[^0-9]', '', 'g'), '')
 WHERE cpf IS NOT NULL;
UPDATE public.funcionarios SET cpf = NULL
 WHERE cpf IS NOT NULL AND NOT public.cpf_valido(cpf);

-- Se a importação trouxe o mesmo CPF duas vezes na mesma conta, fica só o
-- primeiro: o índice único abaixo não pode falhar na migração.
UPDATE public.funcionarios f SET cpf = NULL
 WHERE f.cpf IS NOT NULL AND f.ativo
   AND EXISTS (SELECT 1 FROM public.funcionarios o
                WHERE o.contaid = f.contaid AND o.cpf = f.cpf AND o.ativo AND o.funcionarioid < f.funcionarioid);

-- A coluna continua varchar(14): assim a tela pode mandar "529.982.247-25"
-- que o gatilho guarda "52998224725". Se o tipo fosse varchar(11), o banco
-- recusaria o CPF com pontos ANTES de o gatilho limpar.
COMMENT ON COLUMN public.funcionarios.cpf IS
  'Guardado só com números (11 dígitos); aceita digitação com pontos. É o login do colaborador no app. Único por conta entre os ativos.';

DROP TRIGGER IF EXISTS funcionarios_normaliza_cpf ON public.funcionarios;
CREATE TRIGGER funcionarios_normaliza_cpf
  BEFORE INSERT OR UPDATE OF cpf ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.normaliza_cpf_funcionario();

-- Único por conta, entre os ativos.
CREATE UNIQUE INDEX IF NOT EXISTS funcionarios_cpf_unico_na_conta
  ON public.funcionarios (contaid, cpf) WHERE cpf IS NOT NULL AND ativo;


-- ---------------------------------------------------------------------------
-- 2. Fora o que sobrou do sistema antigo
-- ---------------------------------------------------------------------------
-- (Os GRANTs por coluna somem junto com a coluna.)
ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS senhahash;
ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS verificadorcpf;
ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS nivelacesso;

-- ---------------------------------------------------------------------------
-- 3. Permissões
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.cpf_valido(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cpf_valido(text) TO authenticated, service_role;


-- =========================================================================
-- 20260927100300_acessos_papeis_e_contexto.sql
-- =========================================================================

-- Etapa 1.12, parte A (2/3): os dois acessos novos, o contexto das visões e a
-- política de uso versionada.
--
-- Desenho aprovado em 23/09/2026:
--   * Um login por LOJA (tablet) e um por COLABORADOR (celular, entra por CPF),
--     guardados em contasusuarios, junto com o master.
--   * minha_conta() responde NULO para esses dois. Com isso, as ~200 regras de
--     acesso que já existem passam a negar tudo para eles, sem serem
--     reescritas: eles não leem nenhuma tabela pelo endereço.
--   * Tudo o que essas visões fazem passa por função de servidor, que entra
--     num "contexto da visão" — o mesmo desenho já aprovado do bot, e que só
--     vale quando quem chama é o servidor.
--   * A política de uso é um comunicado. Cada versão nova é um comunicado novo;
--     as ciências antigas continuam guardadas, ligadas à versão que valia.

-- ---------------------------------------------------------------------------
-- 1. Papéis novos em contasusuarios
-- ---------------------------------------------------------------------------
ALTER TABLE public.contasusuarios DROP CONSTRAINT IF EXISTS contasusuarios_papel_check;
ALTER TABLE public.contasusuarios DROP CONSTRAINT IF EXISTS contasusuarios_papel_check;
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_papel_check
  CHECK (papel IN ('master', 'gerente', 'loja', 'colaborador'));

ALTER TABLE public.contasusuarios ADD COLUMN IF NOT EXISTS lojaid integer;
ALTER TABLE public.contasusuarios ADD COLUMN IF NOT EXISTS funcionarioid integer;
ALTER TABLE public.contasusuarios ADD COLUMN IF NOT EXISTS criadopor uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.contasusuarios DROP CONSTRAINT IF EXISTS contasusuarios_loja_fk;
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_loja_fk
  FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.contasusuarios DROP CONSTRAINT IF EXISTS contasusuarios_funcionario_fk;
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_funcionario_fk
  FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;

-- Cada papel tem o seu vínculo, e só o dele.
ALTER TABLE public.contasusuarios DROP CONSTRAINT IF EXISTS contasusuarios_vinculo_do_papel;
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_vinculo_do_papel CHECK (
  (papel IN ('master', 'gerente') AND lojaid IS NULL AND funcionarioid IS NULL)
  OR (papel = 'loja'        AND lojaid IS NOT NULL AND funcionarioid IS NULL)
  OR (papel = 'colaborador' AND funcionarioid IS NOT NULL AND lojaid IS NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS contasusuarios_um_acesso_por_loja
  ON public.contasusuarios (contaid, lojaid) WHERE lojaid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS contasusuarios_um_acesso_por_pessoa
  ON public.contasusuarios (contaid, funcionarioid) WHERE funcionarioid IS NOT NULL;

COMMENT ON COLUMN public.contasusuarios.papel IS
  'master (dono da conta), gerente (Etapa 1.14), loja (tablet) ou colaborador (celular).';

-- ---------------------------------------------------------------------------
-- 1a. Código da empresa (por onde o colaborador entra)
-- ---------------------------------------------------------------------------
-- O colaborador abre stgame.app/e/<codigo> (link e QR que o gestor imprime) ou
-- digita esse código na tela de login. É por ele que o app sabe de qual
-- empresa a pessoa é, antes de ela entrar.
ALTER TABLE public.contas ADD COLUMN IF NOT EXISTS codigo varchar(30);

UPDATE public.contas SET codigo =
  left(regexp_replace(lower(translate(nome,
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
         'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
       '[^a-z0-9]+', '', 'g'), 22) || contaid::text
 WHERE codigo IS NULL;
UPDATE public.contas SET codigo = 'empresa' || contaid::text WHERE btrim(coalesce(codigo, '')) = '';

-- Conta nova nasce com o código pronto (o admin não precisa inventar um).
CREATE OR REPLACE FUNCTION public.codigo_padrao_da_conta()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v text;
BEGIN
  IF btrim(coalesce(NEW.codigo, '')) <> '' THEN
    NEW.codigo := lower(btrim(NEW.codigo));
    RETURN NEW;
  END IF;
  v := left(regexp_replace(lower(translate(coalesce(NEW.nome, ''),
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
         'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
       '[^a-z0-9]+', '', 'g'), 22);
  IF v = '' THEN v := 'empresa'; END IF;
  NEW.codigo := v || NEW.contaid::text;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contas_codigo_padrao ON public.contas;
CREATE TRIGGER contas_codigo_padrao
  BEFORE INSERT ON public.contas
  FOR EACH ROW EXECUTE FUNCTION public.codigo_padrao_da_conta();

ALTER TABLE public.contas ALTER COLUMN codigo SET NOT NULL;
ALTER TABLE public.contas DROP CONSTRAINT IF EXISTS contas_codigo_formato;
ALTER TABLE public.contas ADD CONSTRAINT contas_codigo_formato
  CHECK (codigo ~ '^[a-z0-9-]{3,30}$');
CREATE UNIQUE INDEX IF NOT EXISTS contas_codigo_unico ON public.contas (codigo);
COMMENT ON COLUMN public.contas.codigo IS
  'Código público da empresa, usado no link/QR de entrada do colaborador (stgame.app/e/<codigo>).';

-- O navegador não escreve o código (a tabela contas já é só do admin geral).
-- Quem procura a empresa pelo código é o servidor, na tela de login.
CREATE OR REPLACE FUNCTION public.conta_por_codigo(p_codigo text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE c record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura empresa por código.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT contaid, nome, status INTO c FROM public.contas
   WHERE codigo = lower(btrim(coalesce(p_codigo, '')));
  IF NOT FOUND OR c.status = 'cancelada' THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('contaid', c.contaid, 'nome', c.nome);
END;
$$;
REVOKE ALL ON FUNCTION public.conta_por_codigo(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_por_codigo(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 1b. Marcas de acesso na pessoa
-- ---------------------------------------------------------------------------
-- Senha e PIN começam com os 6 primeiros dígitos do CPF e são trocados no
-- primeiro acesso. Enquanto forem provisórios, o gestor vê o aviso na Equipe.
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS senhaprovisoria    boolean NOT NULL DEFAULT true;
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS pinprovisorio      boolean NOT NULL DEFAULT true;
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS primeiroacessoem   timestamptz;
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS acessoredefinidoem timestamptz;
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS acessoredefinidopor uuid REFERENCES auth.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.funcionarios.primeiroacessoem IS 'Quando a pessoa entrou no app pela primeira vez. Vazio = nunca entrou.';

-- O navegador do master não escreve estas colunas: em funcionarios o UPDATE é
-- liberado coluna por coluna (a tela grava só os campos de cadastro), e coluna
-- nova nasce sem permissão. Elas mudam só pelas funções de acesso.

-- ---------------------------------------------------------------------------
-- 2. minha_conta(): só master e gerente (mais o contexto de servidor)
-- ---------------------------------------------------------------------------
-- É a peça central do isolamento das visões novas: quem entra como loja ou
-- como colaborador não tem conta nenhuma para a RLS, então não lê nada.
CREATE OR REPLACE FUNCTION public.minha_conta()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT contaid FROM public.contasusuarios
                    WHERE userid = auth.uid() AND papel IN ('master', 'gerente')),
                  public.conta_do_bot())
$$;

CREATE OR REPLACE FUNCTION public.minha_conta_editavel()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.contaid
    FROM public.contas c
   WHERE c.status = 'ativa'
     AND c.contaid = coalesce((SELECT contaid FROM public.contasusuarios
                                WHERE userid = auth.uid() AND papel IN ('master', 'gerente')),
                              public.conta_do_bot())
$$;

-- ---------------------------------------------------------------------------
-- 3. Contexto das visões (tablet e colaborador)
-- ---------------------------------------------------------------------------
-- Mesmo mecanismo do bot: só vale quando quem chama é o servidor
-- (bot_contexto_confiavel), e dura até o fim da transação.
CREATE OR REPLACE FUNCTION public.loja_da_visao()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.bot_contexto_confiavel()
              THEN nullif(current_setting('stgame.visao_loja', true), '')::integer END
$$;

CREATE OR REPLACE FUNCTION public.entrar_na_visao(p_contaid integer, p_funcionarioid integer,
                                                  p_lojaid integer, p_canal text)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Contexto das visões só no servidor.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_canal NOT IN ('tablet', 'colaborador') THEN
    RAISE EXCEPTION 'Canal inválido.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_contaid IS NULL THEN
    RAISE EXCEPTION 'Sem conta no contexto.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('stgame.bot_conta', p_contaid::text, true);
  PERFORM set_config('stgame.bot_funcionario', coalesce(p_funcionarioid::text, ''), true);
  PERFORM set_config('stgame.bot_canal', p_canal, true);
  PERFORM set_config('stgame.visao_loja', coalesce(p_lojaid::text, ''), true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Quem sou eu (usada pelo app para saber para onde levar quem entrou)
-- ---------------------------------------------------------------------------
-- Só fala do próprio login (auth.uid()). Não recebe parâmetro nenhum, por isso
-- pode ser liberada para quem está logado.
CREATE OR REPLACE FUNCTION public.meu_acesso()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  a     record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;
  IF public.eh_admin_geral() THEN
    RETURN jsonb_build_object('tipo', 'admin');
  END IF;

  SELECT cu.papel, cu.contaid, cu.lojaid, cu.funcionarioid,
         c.status AS statusconta, c.nome AS nomeconta,
         l.nome AS nomeloja, l.ativa AS lojaativa,
         f.nomecompleto AS nomepessoa, f.ativo AS pessoaativa,
         f.senhaprovisoria, f.pinprovisorio
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;

  -- Desligado na hora: pessoa inativa, loja desativada ou conta cancelada
  -- perdem o acesso na mesma hora, sem esperar a sessão vencer.
  IF a.statusconta = 'cancelada'
     OR (a.papel = 'loja' AND coalesce(a.lojaativa, false) = false)
     OR (a.papel = 'colaborador' AND coalesce(a.pessoaativa, false) = false) THEN
    RETURN jsonb_build_object('tipo', 'desligado');
  END IF;

  RETURN jsonb_build_object(
    'tipo', a.papel,
    'conta', a.nomeconta,
    'loja', a.nomeloja,
    'nome', coalesce(a.nomepessoa, a.nomeloja, a.nomeconta),
    'somenteleitura', a.statusconta <> 'ativa',
    'senhaprovisoria', coalesce(a.senhaprovisoria, false),
    'pinprovisorio', coalesce(a.pinprovisorio, false),
    'politicapendente', CASE WHEN a.papel = 'colaborador'
                             THEN public.politica_pendente(a.contaid, a.funcionarioid) ELSE false END);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Política de uso: um comunicado por versão
-- ---------------------------------------------------------------------------
-- A versão em vigor fica em configuracoes (POLITICA_USO_DOCUMENTOID). Publicar
-- uma versão nova arquiva a anterior; as ciências antigas continuam guardadas,
-- ligadas ao comunicado daquela versão.
CREATE OR REPLACE FUNCTION public.politica_documento(p_contaid integer)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
   WHERE contaid = p_contaid AND chave = 'POLITICA_USO_DOCUMENTOID'
$$;

-- Esta pessoa ainda deve ciência na versão em vigor?
CREATE OR REPLACE FUNCTION public.politica_pendente(p_contaid integer, p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
           WHEN public.politica_documento(p_contaid) IS NULL THEN false
           ELSE NOT EXISTS (SELECT 1 FROM public.documentosassinaturas a
                             WHERE a.contaid = p_contaid
                               AND a.documentoid = public.politica_documento(p_contaid)
                               AND a.funcionarioid = p_funcionarioid
                               AND a.statusassinatura = 'Ciente')
         END
$$;

-- Publica uma versão nova (só o master). Sempre com 0 ponto de ciência:
-- ninguém ganha ponto por aceitar a política.
CREATE OR REPLACE FUNCTION public.publicar_politica_de_uso(p_conteudo text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.exige_master_editavel();
  v_antigo integer := public.politica_documento(v_conta);
  v_novo  integer;
  v_texto text := btrim(coalesce(p_conteudo, ''));
BEGIN
  IF length(v_texto) < 200 THEN
    RAISE EXCEPTION 'A política de uso está curta demais: confira o texto.' USING ERRCODE = 'check_violation';
  END IF;

  v_novo := public.publicar_comunicado(
    'Política de uso do sistema — ' || to_char(public.dia_em_sao_paulo(now()), 'DD/MM/YYYY'),
    v_texto, 0, 'conta', NULL, NULL);

  IF v_antigo IS NOT NULL THEN
    PERFORM public.arquivar_comunicado(v_antigo);
  END IF;

  UPDATE public.configuracoes SET valor = v_novo::text
   WHERE contaid = v_conta AND chave = 'POLITICA_USO_DOCUMENTOID';
  IF NOT FOUND THEN
    INSERT INTO public.configuracoes (contaid, chave, valor, descricao)
    VALUES (v_conta, 'POLITICA_USO_DOCUMENTOID', v_novo::text,
            'Comunicado da versão da política de uso em vigor. Preenchido pelo sistema.');
  END IF;
  RETURN v_novo;
END;
$$;

-- O colaborador lê a política dele (e só a dele) para aceitar no primeiro
-- acesso. Fala só do próprio login, então pode ir para a tela.
CREATE OR REPLACE FUNCTION public.minha_politica_de_uso()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('assinaturaid', a.assinaturaid, 'titulo', d.titulo, 'conteudo', d.conteudo)
    FROM public.contasusuarios cu
    JOIN public.documentos d
      ON d.contaid = cu.contaid AND d.documentoid = public.politica_documento(cu.contaid)
    JOIN public.documentosassinaturas a
      ON a.contaid = cu.contaid AND a.documentoid = d.documentoid AND a.funcionarioid = cu.funcionarioid
   WHERE cu.userid = auth.uid() AND cu.papel = 'colaborador'
$$;

-- A ciência da política: entra no contexto da visão e usa a MESMA função de
-- ciência das telas do gestor (nada de caminho paralelo). Só o servidor chama.
CREATE OR REPLACE FUNCTION public.politica_dar_ciencia(p_contaid integer, p_funcionarioid integer,
                                                       p_assinaturaid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra a ciência da política.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas
                  WHERE assinaturaid = p_assinaturaid AND contaid = p_contaid
                    AND funcionarioid = p_funcionarioid
                    AND documentoid = public.politica_documento(p_contaid)) THEN
    RAISE EXCEPTION 'Esta ciência não é da política em vigor.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, NULL, 'colaborador');
  RETURN public.registrar_ciencia(p_assinaturaid);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permissões
-- ---------------------------------------------------------------------------
-- Recebem conta/loja por parâmetro: internas, nunca liberadas.
REVOKE ALL ON FUNCTION public.entrar_na_visao(integer, integer, integer, text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.politica_documento(integer)                      FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.politica_pendente(integer, integer)              FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.loja_da_visao()                                  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.entrar_na_visao(integer, integer, integer, text) TO service_role;

-- Falam só do próprio login: podem ser chamadas pelas telas.
REVOKE ALL ON FUNCTION public.meu_acesso() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.meu_acesso() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.publicar_politica_de_uso(text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.publicar_politica_de_uso(text) TO authenticated;
REVOKE ALL ON FUNCTION public.minha_politica_de_uso() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.minha_politica_de_uso() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.politica_dar_ciencia(integer, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.politica_dar_ciencia(integer, integer, integer) TO service_role;


-- =========================================================================
-- 20260927100400_pin_e_travas.sql
-- =========================================================================

-- Etapa 1.12, parte A (3/3): PIN do tablet, travas de tentativa e criação dos
-- acessos.
--
-- Como o PIN é guardado (decisão do Wisley, 23/09/2026):
--   * 6 dígitos, único na conta inteira (cobre quem trabalha em várias lojas).
--   * O banco NUNCA vê o número. Quem embaralha é o servidor, com HMAC e uma
--     chave que só ele tem (STGAME_PIN_PEPPER, fora do banco). Aqui só entra o
--     resultado embaralhado, de 64 letras.
--   * Por ser sempre o mesmo resultado para o mesmo número, o banco acha a
--     pessoa DIRETO pelo índice: a janela do tablet responde igual com 5 ou
--     500 pessoas. Comparar uma a uma (como se faz com senha) ficaria lento.
--   * Quem tiver só o banco não consegue testar número nenhum: falta a chave.
--
-- Tentativas: toda tentativa de senha ou de PIN fica registrada, SEM o que foi
-- digitado. Nem o CPF entra: guarda-se o mesmo embaralhado do servidor.

-- ---------------------------------------------------------------------------
-- 1. O PIN na pessoa
-- ---------------------------------------------------------------------------
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS pinhash char(64);
COMMENT ON COLUMN public.funcionarios.pinhash IS
  'PIN do tablet, embaralhado pelo servidor (HMAC com chave fora do banco). O número nunca é guardado.';

-- Único entre as pessoas ativas da conta. A tela nunca diz de quem é o número
-- repetido: só "escolha outro número".
CREATE UNIQUE INDEX IF NOT EXISTS funcionarios_pin_unico_na_conta
  ON public.funcionarios (contaid, pinhash) WHERE pinhash IS NOT NULL AND ativo;

-- Nem o master escreve o PIN direto: em funcionarios o UPDATE é liberado
-- coluna por coluna, e coluna nova nasce sem permissão. O PIN entra só pelas
-- funções abaixo.
-- O master consegue LER esta coluna (o SELECT da tabela é dele), e tudo bem:
-- sem a chave do servidor, o embaralhado não vira número nenhum.

-- ---------------------------------------------------------------------------
-- 2. Registro de tentativas
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tentativasacesso (
  tentativaid bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  -- Vazio só nas tentativas de senha do master, quando o e-mail digitado
  -- ainda não achou conta nenhuma (a tabela é interna: ninguém a lê pelo
  -- navegador, e nada dela sai para as telas).
  contaid     integer REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  tipo        varchar(10) NOT NULL CHECK (tipo IN ('senha', 'pin')),
  chave       char(64) NOT NULL,
  origem      varchar(40) NOT NULL,
  sucesso     boolean NOT NULL,
  em          timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.tentativasacesso IS
  'Tentativas de entrar (senha) e de usar o PIN. Nunca guarda o que foi digitado: "chave" é o CPF/e-mail embaralhado pelo servidor.';
CREATE INDEX IF NOT EXISTS tentativasacesso_chave_idx  ON public.tentativasacesso (contaid, tipo, chave, em DESC);
CREATE INDEX IF NOT EXISTS tentativasacesso_origem_idx ON public.tentativasacesso (contaid, tipo, origem, em DESC);

ALTER TABLE public.tentativasacesso ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tentativasacesso FROM anon, authenticated;
GRANT ALL ON public.tentativasacesso TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Trava: 5 erros seguidos
-- ---------------------------------------------------------------------------
-- PIN: 5 erros em 1 minuto travam a janela DAQUELE tablet. Num PIN errado não
-- existe pessoa identificada, então a conta é por tablet — e um acerto zera.
-- Senha: 5 erros em 15 minutos travam, contados pelo CPF/e-mail E pela origem
-- (só trocar de CPF na mesma tela não adianta).
CREATE OR REPLACE FUNCTION public.acesso_travado(p_contaid integer, p_tipo text, p_chave text, p_origem text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_erros  integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor confere a trava de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Erros desta origem desde o último acerto dela.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = p_origem AND NOT t.sucesso
     AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.origem = p_origem AND s.sucesso),
                         '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN true;
  END IF;

  IF p_tipo = 'pin' THEN
    RETURN false;
  END IF;

  -- Senha: também pelo CPF/e-mail, para não bastar trocar de aparelho.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = p_chave AND NOT t.sucesso
     AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.chave = p_chave AND s.sucesso),
                         '-infinity'::timestamptz);
  RETURN v_erros >= 5;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_tentativa(p_contaid integer, p_tipo text, p_chave text,
                                                      p_origem text, p_sucesso boolean)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, left(coalesce(p_chave, ''), 64), left(coalesce(p_origem, 'app'), 40), p_sucesso);
  -- Não vira histórico: o que passou de 7 dias sai.
  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Criar e mexer nos acessos (só pelo servidor)
-- ---------------------------------------------------------------------------
-- O servidor cria o login no Supabase Auth e chama estas funções para amarrar
-- o login à conta. Elas conferem tudo de novo do lado do banco.
CREATE OR REPLACE FUNCTION public.criar_acesso_loja(p_contaid integer, p_lojaid integer, p_userid uuid, p_quem uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor cria acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE contaid = p_contaid AND lojaid = p_lojaid AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada nesta conta.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.contasusuarios (contaid, userid, papel, lojaid, criadopor)
  VALUES (p_contaid, p_userid, 'loja', p_lojaid, p_quem);
END;
$$;

CREATE OR REPLACE FUNCTION public.criar_acesso_colaborador(p_contaid integer, p_funcionarioid integer,
                                                           p_userid uuid, p_pinhash text, p_quem uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_compin boolean := true;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor cria acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo AND cpf IS NOT NULL) THEN
    RAISE EXCEPTION 'Pessoa não encontrada, inativa ou sem CPF.' USING ERRCODE = 'no_data_found';
  END IF;

  INSERT INTO public.contasusuarios (contaid, userid, papel, funcionarioid, criadopor)
  VALUES (p_contaid, p_userid, 'colaborador', p_funcionarioid, p_quem);

  -- O PIN inicial são os 6 primeiros dígitos do CPF. Se outra pessoa da conta
  -- já usa esse número, a pessoa entra SEM PIN e o gestor vê "PIN pendente".
  BEGIN
    UPDATE public.funcionarios
       SET senhaprovisoria = true, pinprovisorio = true, pinhash = left(p_pinhash, 64)
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;
  EXCEPTION WHEN unique_violation THEN
    v_compin := false;
    UPDATE public.funcionarios
       SET senhaprovisoria = true, pinprovisorio = true, pinhash = NULL
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;
  END;
  RETURN v_compin;
END;
$$;

-- A pessoa escolhe o PIN dela (ou o gestor redefine para o inicial).
CREATE OR REPLACE FUNCTION public.definir_pin(p_contaid integer, p_funcionarioid integer,
                                              p_pinhash text, p_provisorio boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor define PIN.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios
     SET pinhash = left(p_pinhash, 64), pinprovisorio = coalesce(p_provisorio, false)
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
EXCEPTION WHEN unique_violation THEN
  -- Nunca dizer de quem é o número.
  RAISE EXCEPTION 'Escolha outro número.' USING ERRCODE = 'unique_violation';
END;
$$;

CREATE OR REPLACE FUNCTION public.marcar_senha_trocada(p_contaid integer, p_funcionarioid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor muda a marca de senha.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios
     SET senhaprovisoria = false,
         primeiroacessoem = coalesce(primeiroacessoem, now())
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;
END;
$$;

-- "Redefinir acesso" na Equipe: senha e PIN voltam para os 6 primeiros dígitos
-- do CPF, com registro de quem redefiniu e quando. Quem confere se p_quem é o
-- master é a função de servidor, com o token de quem pediu.
CREATE OR REPLACE FUNCTION public.redefinir_acesso(p_contaid integer, p_funcionarioid integer,
                                                   p_pinhash text, p_quem uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_compin boolean := true;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor redefine acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo) THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  BEGIN
    UPDATE public.funcionarios
       SET senhaprovisoria = true, pinprovisorio = true, pinhash = left(p_pinhash, 64),
           acessoredefinidoem = now(), acessoredefinidopor = p_quem
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  EXCEPTION WHEN unique_violation THEN
    -- O PIN inicial já é de outra pessoa: fica sem PIN, como pendente.
    v_compin := false;
    UPDATE public.funcionarios
       SET senhaprovisoria = true, pinprovisorio = true, pinhash = NULL,
           acessoredefinidoem = now(), acessoredefinidopor = p_quem
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  END;
  RETURN v_compin;
END;
$$;

-- Situação do acesso de cada pessoa, para a tela Equipe. Não devolve o PIN
-- nem o CPF: só as marcas.
DROP FUNCTION IF EXISTS public.situacao_dos_acessos();
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
RETURNS TABLE (funcionarioid integer, temacesso boolean, nuncaentrou boolean,
               senhaprovisoria boolean, pinprovisorio boolean, sempin boolean,
               redefinidoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhaprovisoria,
         f.pinprovisorio,
         f.pinhash IS NULL,
         f.acessoredefinidoem
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
$$;

-- ---------------------------------------------------------------------------
-- 5. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  -- Recebem conta/pessoa por parâmetro: só o servidor, nunca o navegador.
  FOREACH f IN ARRAY ARRAY[
    'public.acesso_travado(integer, text, text, text)',
    'public.registrar_tentativa(integer, text, text, text, boolean)',
    'public.criar_acesso_loja(integer, integer, uuid, uuid)',
    'public.criar_acesso_colaborador(integer, integer, uuid, text, uuid)',
    'public.definir_pin(integer, integer, text, boolean)',
    'public.marcar_senha_trocada(integer, integer)',
    'public.redefinir_acesso(integer, integer, text, uuid)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;

-- Fala só da própria conta e só para o master: pode ir para a tela.
REVOKE ALL ON FUNCTION public.situacao_dos_acessos() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.situacao_dos_acessos() TO authenticated;


-- =========================================================================
-- 20260927100500_acesso_por_codigo_e_senha_propria.sql
-- =========================================================================

-- Etapa 1.12, parte A — consertos da revisão adversarial (23/09/2026).
--
-- O que a revisão achou e o que muda aqui:
--
-- 1) A trava de tentativas era opcional: dava para falar direto com o Supabase,
--    pulando o nosso servidor. E a senha inicial (6 primeiros do CPF) era
--    adivinhável por quem soubesse o CPF.
--    → A senha do colaborador passa a ser conferida por NÓS: o resumo dela fica
--      em funcionarios.senhahashapp (PBKDF2 calculado no servidor, com sal por
--      pessoa). A senha que o Supabase guarda vira um valor que ninguém conhece
--      nem consegue adivinhar (o servidor recalcula quando precisa). Falar
--      direto com o Supabase deixa de servir para alguma coisa.
--    → Não existe mais "senha padrão". Quem ainda não criou a senha entra uma
--      única vez com um CÓDIGO sorteado pelo gestor (uso único, 7 dias).
--
-- 2) A tela de escolher o PIN era um adivinhador sem limite ("escolha outro
--    número" dizia que o número era de alguém).
--    → Toda tentativa de PIN passa pela trava, com teto por dia.
--
-- 3) Médias: PIN e senha somem quando a pessoa é desativada; trocar o CPF passa
--    a valer para o login; o master não lê mais as colunas de segredo; a origem
--    da tentativa é definida pelo servidor; foto presa no expurgo vira aviso.
--
-- O PIN inicial também deixa de existir: a pessoa escolhe o dela no primeiro
-- acesso.

-- ---------------------------------------------------------------------------
-- 1. A senha do app é nossa
-- ---------------------------------------------------------------------------
ALTER TABLE public.funcionarios ADD COLUMN IF NOT EXISTS senhahashapp text;
COMMENT ON COLUMN public.funcionarios.senhahashapp IS
  'Resumo da senha do app (PBKDF2 com sal por pessoa, calculado no servidor). Vazio = ainda não criou senha: só entra com o código de primeiro acesso.';

-- As marcas de "provisório" não fazem mais sentido: agora o que vale é existir
-- ou não existir senha e PIN.
ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS senhaprovisoria;
ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS pinprovisorio;

-- ---------------------------------------------------------------------------
-- 2. Código de primeiro acesso (uso único, com validade)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.codigosacesso (
  codigoid      integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  funcionarioid integer NOT NULL,
  codigohash    char(64) NOT NULL UNIQUE,
  expiraem      timestamptz NOT NULL,
  usadoem       timestamptz,
  canceladoem   timestamptz,
  criadopor     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  criadoem      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT codigosacesso_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT codigosacesso_conta_unico UNIQUE (contaid, codigoid)
);
COMMENT ON TABLE public.codigosacesso IS
  'Código de primeiro acesso: uso único, validade curta, só o resumo (HMAC do servidor) é guardado. Gerar outro cancela o anterior.';
CREATE INDEX IF NOT EXISTS codigosacesso_pendentes_idx ON public.codigosacesso (contaid, funcionarioid)
  WHERE usadoem IS NULL AND canceladoem IS NULL;

ALTER TABLE public.codigosacesso ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.codigosacesso FROM anon, authenticated;
GRANT ALL ON public.codigosacesso TO service_role;

-- Gera o código (o texto vem pronto do servidor; aqui entra só o resumo).
CREATE OR REPLACE FUNCTION public.criar_codigo_acesso(p_contaid integer, p_funcionarioid integer,
                                                      p_codigohash text, p_dias integer, p_quem uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor gera código de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo) THEN
    RAISE EXCEPTION 'Pessoa não encontrada ou desativada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Gerar outro cancela o anterior: só um código vale por vez.
  UPDATE public.codigosacesso SET canceladoem = now()
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
     AND usadoem IS NULL AND canceladoem IS NULL;
  INSERT INTO public.codigosacesso (contaid, funcionarioid, codigohash, expiraem, criadopor)
  VALUES (p_contaid, p_funcionarioid, left(p_codigohash, 64),
          now() + make_interval(days => greatest(coalesce(p_dias, 7), 1)), p_quem);
END;
$$;

-- Usa o código: devolve a pessoa, ou nada. Uso único de verdade (a marca de
-- usado entra na mesma operação que confere).
CREATE OR REPLACE FUNCTION public.usar_codigo_acesso(p_contaid integer, p_cpf text, p_codigohash text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE c record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor usa código de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT k.codigoid, k.funcionarioid, f.nomecompleto
    INTO c
    FROM public.codigosacesso k
    JOIN public.funcionarios f ON f.contaid = k.contaid AND f.funcionarioid = k.funcionarioid AND f.ativo
   WHERE k.contaid = p_contaid
     AND k.codigohash = left(p_codigohash, 64)
     AND k.usadoem IS NULL AND k.canceladoem IS NULL
     AND k.expiraem > now()
     AND f.cpf = regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g')
     FOR UPDATE OF k;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  UPDATE public.codigosacesso SET usadoem = now() WHERE codigoid = c.codigoid;
  RETURN jsonb_build_object('funcionarioid', c.funcionarioid, 'nome', c.nomecompleto);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Senha e PIN: guardar e conferir
-- ---------------------------------------------------------------------------
-- O servidor confere a senha; o banco só guarda e entrega o resumo.
CREATE OR REPLACE FUNCTION public.senha_app_de(p_contaid integer, p_cpf text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE f record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor confere senha.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT fu.funcionarioid, fu.senhahashapp, cu.userid
    INTO f
    FROM public.funcionarios fu
    JOIN public.contasusuarios cu
      ON cu.contaid = fu.contaid AND cu.funcionarioid = fu.funcionarioid AND cu.papel = 'colaborador'
   WHERE fu.contaid = p_contaid AND fu.ativo
     AND fu.cpf = regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g');
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('funcionarioid', f.funcionarioid, 'userid', f.userid, 'senhahash', f.senhahashapp);
END;
$$;

CREATE OR REPLACE FUNCTION public.definir_senha_app(p_contaid integer, p_funcionarioid integer, p_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor define senha.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios
     SET senhahashapp = p_hash,
         primeiroacessoem = coalesce(primeiroacessoem, now())
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- A pessoa escolhe o PIN dela. Não existe mais PIN inicial.
CREATE OR REPLACE FUNCTION public.definir_pin(p_contaid integer, p_funcionarioid integer,
                                              p_pinhash text, p_provisorio boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor define PIN.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios
     SET pinhash = left(p_pinhash, 64)
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Escolha outro número.' USING ERRCODE = 'unique_violation';
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Trava: agora com teto por dia (a tela do PIN era um adivinhador)
-- ---------------------------------------------------------------------------
-- PIN: 5 erros em 1 minuto travam aquele tablet (um acerto zera) E no máximo
-- 30 tentativas por dia da mesma chave — o que mata o adivinhador, mesmo que
-- alguém espere entre uma tentativa e outra.
-- Senha: 5 erros em 15 minutos, contados pela chave e pela origem.
CREATE OR REPLACE FUNCTION public.acesso_travado(p_contaid integer, p_tipo text, p_chave text, p_origem text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  -- Teto por dia: o que mata o adivinhador de PIN mesmo com espera entre as
  -- tentativas. (Fica em variável porque o IF do Postgres não aceita CASE.)
  v_teto   integer := CASE WHEN p_tipo = 'pin' THEN 30 ELSE 50 END;
  v_erros  integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor confere a trava de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Teto do dia, por chave (pessoa ou tablet): vale para senha e para PIN.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = p_chave
     AND t.em > now() - interval '1 day';
  IF v_erros >= v_teto THEN
    RETURN true;
  END IF;

  -- Erros desta origem desde o último acerto dela.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = p_origem AND NOT t.sucesso
     AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.origem = p_origem AND s.sucesso),
                         '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN true;
  END IF;

  -- E pela chave (CPF, e-mail ou pessoa), para não bastar trocar de aparelho.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = p_chave AND NOT t.sucesso
     AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.chave = p_chave AND s.sucesso),
                         '-infinity'::timestamptz);
  RETURN v_erros >= 5;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Desativar a pessoa apaga os segredos dela
-- ---------------------------------------------------------------------------
-- O login no Supabase é derrubado pelo servidor (a tela chama a função de
-- desativar); aqui garantimos que senha e PIN somem por qualquer caminho.
CREATE OR REPLACE FUNCTION public.limpa_acesso_ao_desativar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativo AND NOT NEW.ativo THEN
    NEW.pinhash := NULL;
    NEW.senhahashapp := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS funcionarios_limpa_acesso ON public.funcionarios;
CREATE TRIGGER funcionarios_limpa_acesso
  BEFORE UPDATE OF ativo ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.limpa_acesso_ao_desativar();

-- Cancela os códigos pendentes de quem foi desativado.
CREATE OR REPLACE FUNCTION public.cancela_codigos_ao_desativar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativo AND NOT NEW.ativo THEN
    UPDATE public.codigosacesso SET canceladoem = now()
     WHERE contaid = NEW.contaid AND funcionarioid = NEW.funcionarioid
       AND usadoem IS NULL AND canceladoem IS NULL;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS funcionarios_cancela_codigos ON public.funcionarios;
CREATE TRIGGER funcionarios_cancela_codigos
  AFTER UPDATE OF ativo ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.cancela_codigos_ao_desativar();

-- ---------------------------------------------------------------------------
-- 6. Trocar o CPF de quem já tem acesso só pelo caminho certo
-- ---------------------------------------------------------------------------
-- O CPF é o login. Trocar direto na tabela deixaria a pessoa sem conseguir
-- entrar, sem aviso nenhum. A troca passa a exigir a função de servidor, que
-- muda o CPF e o login no mesmo movimento.
CREATE OR REPLACE FUNCTION public.protege_troca_de_cpf()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER   -- precisa enxergar o contexto do servidor (como os outros gatilhos)
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.cpf IS DISTINCT FROM OLD.cpf
     AND OLD.cpf IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.contasusuarios
                  WHERE contaid = NEW.contaid AND funcionarioid = NEW.funcionarioid AND papel = 'colaborador')
     AND NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Esta pessoa já entra no app pelo CPF. Use "Trocar CPF" na Equipe, para o login mudar junto.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS funcionarios_protege_cpf ON public.funcionarios;
CREATE TRIGGER funcionarios_protege_cpf
  BEFORE UPDATE OF cpf ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.protege_troca_de_cpf();

-- ---------------------------------------------------------------------------
-- 7. Nem o master lê os segredos
-- ---------------------------------------------------------------------------
-- A tabela funcionarios tinha SELECT no nível da tabela, então o master lia
-- pinhash e senhahashapp. Agora o SELECT é coluna a coluna, menos essas duas.
DO $$
DECLARE v_colunas text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) INTO v_colunas
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'funcionarios'
     AND column_name NOT IN ('pinhash', 'senhahashapp');
  EXECUTE 'REVOKE SELECT ON public.funcionarios FROM authenticated';
  EXECUTE format('GRANT SELECT (%s) ON public.funcionarios TO authenticated', v_colunas);
END $$;

-- ---------------------------------------------------------------------------
-- 8. Situação do acesso, sem as marcas antigas
-- ---------------------------------------------------------------------------
-- As colunas devolvidas mudaram, então a função é recriada do zero.
DROP FUNCTION IF EXISTS public.situacao_dos_acessos();
DROP FUNCTION IF EXISTS public.situacao_dos_acessos();
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
RETURNS TABLE (funcionarioid integer, temacesso boolean, nuncaentrou boolean,
               semsenha boolean, sempin boolean, codigopendente boolean,
               codigoexpiraem timestamptz, redefinidoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC LIMIT 1) k ON true
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
$$;

CREATE OR REPLACE FUNCTION public.meu_acesso()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  a     record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;
  IF public.eh_admin_geral() THEN
    RETURN jsonb_build_object('tipo', 'admin');
  END IF;

  SELECT cu.papel, cu.contaid, cu.lojaid, cu.funcionarioid,
         c.status AS statusconta, c.nome AS nomeconta,
         l.nome AS nomeloja, l.ativa AS lojaativa,
         f.nomecompleto AS nomepessoa, f.ativo AS pessoaativa,
         f.senhahashapp IS NULL AS semsenha, f.pinhash IS NULL AS sempin
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;

  -- Desligado na hora: pessoa inativa, loja desativada ou conta cancelada.
  IF a.statusconta = 'cancelada'
     OR (a.papel = 'loja' AND coalesce(a.lojaativa, false) = false)
     OR (a.papel = 'colaborador' AND coalesce(a.pessoaativa, false) = false) THEN
    RETURN jsonb_build_object('tipo', 'desligado');
  END IF;

  RETURN jsonb_build_object(
    'tipo', a.papel,
    'conta', a.nomeconta,
    'loja', a.nomeloja,
    'nome', coalesce(a.nomepessoa, a.nomeloja, a.nomeconta),
    'somenteleitura', a.statusconta <> 'ativa',
    'semsenha', coalesce(a.semsenha, false),
    'sempin', coalesce(a.sempin, false),
    'politicapendente', CASE WHEN a.papel = 'colaborador'
                             THEN public.politica_pendente(a.contaid, a.funcionarioid) ELSE false END);
END;
$$;

-- Criar o acesso não define mais PIN nem senha: quem define é a pessoa, no
-- primeiro acesso, depois de usar o código.
CREATE OR REPLACE FUNCTION public.criar_acesso_colaborador(p_contaid integer, p_funcionarioid integer,
                                                           p_userid uuid, p_pinhash text, p_quem uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor cria acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo AND cpf IS NOT NULL) THEN
    RAISE EXCEPTION 'Pessoa não encontrada, inativa ou sem CPF.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.contasusuarios (contaid, userid, papel, funcionarioid, criadopor)
  VALUES (p_contaid, p_userid, 'colaborador', p_funcionarioid, p_quem);
  -- Sem senha e sem PIN: a pessoa cria os dois no primeiro acesso.
  UPDATE public.funcionarios SET senhahashapp = NULL, pinhash = NULL
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;
  RETURN true;
END;
$$;

-- Redefinir acesso: apaga senha e PIN e deixa a pessoa pronta para o código novo.
CREATE OR REPLACE FUNCTION public.redefinir_acesso(p_contaid integer, p_funcionarioid integer,
                                                   p_pinhash text, p_quem uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor redefine acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios
     SET senhahashapp = NULL, pinhash = NULL,
         acessoredefinidoem = now(), acessoredefinidopor = p_quem
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN true;
END;
$$;

-- Trocar o CPF de quem já entra pelo app (o servidor muda o login junto).
CREATE OR REPLACE FUNCTION public.trocar_cpf(p_contaid integer, p_funcionarioid integer, p_cpf text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor troca o CPF de quem tem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios SET cpf = p_cpf
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Expurgo: foto presa vira aviso (antes sumia em silêncio)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    WITH vencidas AS (
      SELECT e.entregaid, e.pathfotoevidencia
        FROM public.entregas e
       WHERE e.contaid = p_contaid
         AND e.pathfotoevidencia IS NOT NULL
         AND e.fotoexpiradaem IS NULL
         AND e.dataenvio < p_agora - make_interval(days => v_dias)
       ORDER BY e.dataenvio
       LIMIT 2000
    ), na_fila AS (
      INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
      SELECT p_contaid, v.entregaid, v.pathfotoevidencia FROM vencidas v
      ON CONFLICT (contaid, caminho) DO NOTHING
      RETURNING entregaid
    )
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM vencidas v
     WHERE e.contaid = p_contaid AND e.entregaid = v.entregaid;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Arquivo que falhou 5 vezes: o banco já diz "apagada", mas o arquivo
    -- continua lá. Isso NÃO pode passar em silêncio.
    SELECT count(*) INTO v_presas FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5;
    IF v_presas > 0 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso',
             v_presas || ' foto(s) marcada(s) como apagada(s) continuam no armazenamento: a remoção falhou 5 vezes.'
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas),
                                      v_presas || ' foto(s) não saíram do armazenamento');
      RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('fotos', v_n, 'dias', v_dias), NULL);
    IF v_n > 0 THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;
    RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.criar_codigo_acesso(integer, integer, text, integer, uuid)',
    'public.usar_codigo_acesso(integer, text, text)',
    'public.senha_app_de(integer, text)',
    'public.definir_senha_app(integer, integer, text)',
    'public.trocar_cpf(integer, integer, text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;

-- O endereço público que devolvia o nome da empresa some (era código morto e
-- servia para descobrir a carteira de clientes).
DROP FUNCTION IF EXISTS public.conta_por_codigo(text);

-- Procura a empresa pelo código, só para o servidor (sem devolver nome).
CREATE OR REPLACE FUNCTION public.conta_do_codigo(p_codigo text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_id integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura empresa por código.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT contaid INTO v_id FROM public.contas
   WHERE codigo = lower(btrim(coalesce(p_codigo, ''))) AND status <> 'cancelada';
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.conta_do_codigo(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_do_codigo(text) TO service_role;

-- Código de empresa novo deixa de ser adivinhável (antes era o nome + o número
-- da conta, o que permitia enumerar a carteira de clientes).
CREATE OR REPLACE FUNCTION public.codigo_padrao_da_conta()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v text;
BEGIN
  IF btrim(coalesce(NEW.codigo, '')) <> '' THEN
    NEW.codigo := lower(btrim(NEW.codigo));
    RETURN NEW;
  END IF;
  v := left(regexp_replace(lower(translate(coalesce(NEW.nome, ''),
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
         'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
       '[^a-z0-9]+', '', 'g'), 18);
  IF v = '' THEN v := 'empresa'; END IF;
  NEW.codigo := v || '-' || left(replace(gen_random_uuid()::text, '-', ''), 6);
  RETURN NEW;
END;
$$;


-- =========================================================================
-- 20260927100600_travas_atomicas_e_senha_do_gestor.sql
-- =========================================================================

-- Etapa 1.12, parte A — consertos da SEGUNDA revisão adversarial (23/09/2026).
--
-- O que a segunda rodada achou e o que muda aqui:
--
-- 1) A trava não era atômica: conferir e registrar eram duas idas ao banco, e
--    uma rajada de pedidos simultâneos passava toda de uma vez (o teto de 30
--    por dia virava 30 POR RAJADA, e o adivinhador de PIN voltava).
--    → Agora é UMA função só, que tranca a chave, conta e registra na mesma
--      transação. Duas tentativas da mesma pessoa entram em fila.
--
-- 2) A porta do Supabase continuava aberta para o MASTER e para o TABLET: dava
--    para falar direto com o Supabase e pular a nossa trava.
--    → A senha deles passa a ser conferida por nós também, como a do
--      colaborador. Quem ainda não tem senha guardada por nós entra uma última
--      vez pela senha antiga, e nesse momento ela é convertida (ninguém fica
--      trancado do lado de fora).
--
-- 3) Defeitos que eu mesmo introduzi na leva anterior:
--    - situacao_dos_acessos ficou sem permissão e quebrava a tela Equipe;
--    - o gatilho que cancela códigos não era security definer e quebrava a
--      desativação pelo navegador;
--    - o expurgo, ao encontrar uma foto presa, parava de chamar a remoção das
--      outras, para sempre;
--    - trocar o CPF de pessoa inativa ficou impossível por qualquer caminho.

-- ---------------------------------------------------------------------------
-- 1. Trava atômica: conferir e registrar viram uma coisa só
-- ---------------------------------------------------------------------------
-- Abre a tentativa: tranca a chave (quem chegar junto espera), confere os
-- limites e JÁ registra a tentativa. Devolve o número dela, ou nada se estiver
-- travado. O resultado (deu certo ou não) entra depois, em tentativa_fechar.
CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER   -- grava na tabela de tentativas, que e fechada para todos
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_teto   integer  := CASE WHEN p_tipo = 'pin' THEN 30 ELSE 50 END;
  v_chave  text     := left(coalesce(p_chave, ''), 64);
  v_origem text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros  integer;
  v_id     bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Duas tentativas da mesma chave nunca contam ao mesmo tempo: a segunda
  -- espera a primeira terminar. É isto que faz o teto valer de verdade.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.acesso:' || p_tipo || ':' || v_chave, 0));

  -- Teto do dia por chave (o que mata o adivinhador de PIN).
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
     AND t.em > now() - interval '1 day';
  IF v_erros >= v_teto THEN
    RETURN NULL;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
     AND NOT t.sucesso AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN NULL;
  END IF;

  -- E erros seguidos desta origem (mesmo aparelho tentando vários CPFs).
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
     AND v_origem <> 'sem-ip' AND NOT t.sucesso AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN NULL;
  END IF;

  -- Registra JÁ (como erro): quem não voltar para fechar conta como tentativa.
  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.tentativa_fechar(p_tentativaid bigint, p_sucesso boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor fecha tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tentativasacesso SET sucesso = coalesce(p_sucesso, false)
   WHERE tentativaid = p_tentativaid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. A senha do gestor e a do tablet também passam a ser nossas
-- ---------------------------------------------------------------------------
-- O colaborador guarda o resumo da senha em funcionarios.senhahashapp. O master
-- e o tablet não têm cadastro de funcionário: ficam aqui.
CREATE TABLE IF NOT EXISTS public.senhasgestor (
  userid       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Vazio no administrador geral, que não pertence a conta nenhuma.
  contaid      integer REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  senhahashapp text NOT NULL,
  atualizadoem timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.senhasgestor IS
  'Resumo da senha do master, do administrador geral e do tablet (PBKDF2 calculado no servidor). Sem isto, a senha ficaria só no Supabase e daria para tentar direto lá, pulando a nossa trava.';

ALTER TABLE public.senhasgestor ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.senhasgestor FROM anon, authenticated;
GRANT ALL ON public.senhasgestor TO service_role;

-- Quem é este e-mail, e qual o resumo da senha dele.
CREATE OR REPLACE FUNCTION public.acesso_por_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE u record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura acesso por e-mail.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT au.id AS userid, s.senhahashapp, cu.contaid, cu.papel
    INTO u
    FROM auth.users au
    LEFT JOIN public.senhasgestor s ON s.userid = au.id
    LEFT JOIN public.contasusuarios cu ON cu.userid = au.id
   WHERE lower(au.email) = lower(btrim(coalesce(p_email, '')));
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid, 'papel', u.papel);
END;
$$;

CREATE OR REPLACE FUNCTION public.definir_senha_gestor(p_userid uuid, p_contaid integer, p_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor define senha de gestor.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.senhasgestor (userid, contaid, senhahashapp)
  VALUES (p_userid, p_contaid, p_hash)
  ON CONFLICT (userid) DO UPDATE SET senhahashapp = excluded.senhahashapp,
                                     contaid = excluded.contaid,
                                     atualizadoem = now();
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Consertos dos defeitos que entraram na leva anterior
-- ---------------------------------------------------------------------------

-- (a) A tela Equipe precisa desta função: ela tinha perdido a permissão no
--     DROP/CREATE anterior.
GRANT EXECUTE ON FUNCTION public.situacao_dos_acessos() TO authenticated;

-- (b) Os gatilhos da desativação mexem em tabela fechada ao navegador: sem
--     security definer, desativar alguém pela tela falharia.
CREATE OR REPLACE FUNCTION public.cancela_codigos_ao_desativar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativo AND NOT NEW.ativo THEN
    UPDATE public.codigosacesso SET canceladoem = now()
     WHERE contaid = NEW.contaid AND funcionarioid = NEW.funcionarioid
       AND usadoem IS NULL AND canceladoem IS NULL;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.limpa_acesso_ao_desativar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativo AND NOT NEW.ativo THEN
    NEW.pinhash := NULL;
    NEW.senhahashapp := NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- (c) Trocar o CPF de quem está inativo passa a ser possível (pelo servidor):
--     antes ficava um beco sem saída para corrigir cadastro de ex-funcionário.
CREATE OR REPLACE FUNCTION public.trocar_cpf(p_contaid integer, p_funcionarioid integer, p_cpf text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor troca o CPF de quem tem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios SET cpf = p_cpf
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- (d) Expurgo: a foto presa vira aviso, mas NÃO pode parar a remoção das
--     outras. Antes, a partir do primeiro arquivo preso, nenhuma foto nova era
--     apagada de verdade — e o banco dizia que estavam apagadas.
--     Também: só marca como expirada a entrega cujo caminho entrou mesmo na
--     fila de remoção.
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    WITH vencidas AS (
      SELECT e.entregaid, e.pathfotoevidencia
        FROM public.entregas e
       WHERE e.contaid = p_contaid
         AND e.pathfotoevidencia IS NOT NULL
         AND e.fotoexpiradaem IS NULL
         AND e.dataenvio < p_agora - make_interval(days => v_dias)
       ORDER BY e.dataenvio
       LIMIT 2000
    ), na_fila AS (
      INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
      SELECT p_contaid, v.entregaid, v.pathfotoevidencia FROM vencidas v
      ON CONFLICT (contaid, caminho) DO NOTHING
      RETURNING entregaid
    )
    -- Só some da entrega o que realmente entrou na fila de remoção.
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM na_fila f
     WHERE e.contaid = p_contaid AND e.entregaid = f.entregaid;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Chama a remoção SEMPRE que houver fila, inclusive quando já existe
    -- arquivo preso: o problema de um não pode travar o dos outros.
    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    SELECT count(*) INTO v_presas FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5;
    IF v_presas > 0 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso',
             v_presas || ' foto(s) marcada(s) como apagada(s) continuam no armazenamento: a remoção falhou 5 vezes.'
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas),
                                      v_presas || ' foto(s) não saíram do armazenamento');
      RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('fotos', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.tentativa_abrir(integer, text, text, text)',
    'public.tentativa_fechar(bigint, boolean)',
    'public.acesso_por_email(text)',
    'public.definir_senha_gestor(uuid, integer, text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;

-- A função antiga de conferir trava sai de cena: quem confere agora registra
-- na mesma operação (era esse o furo).
DROP FUNCTION IF EXISTS public.acesso_travado(integer, text, text, text);
DROP FUNCTION IF EXISTS public.registrar_tentativa(integer, text, text, text, boolean);


-- =========================================================================
-- 20260927100700_trava_sem_bloquear_o_dono.sql
-- =========================================================================

-- Etapa 1.12, parte A — consertos da TERCEIRA revisão adversarial (23/09/2026).
--
-- 1) DEFEITO NOVO, criado pelo conserto anterior: com 5 tentativas erradas,
--    qualquer pessoa (sem login nenhum) travava a conta de qualquer outra por
--    15 minutos — e, com 50, por um dia inteiro. Travar o e-mail do tablet
--    deixaria a loja sem sistema no balcão.
--    → O teto do dia conta só ERRO, e sai do login: ele fica só onde não dá
--      para outra pessoa gastar a cota (escolher o PIN, que exige estar
--      logado). No login sobram os 5 erros em 15 minutos, e um acerto zera.
--      O pior caso vira 15 minutos, não um dia.
--
-- 2) O login por e-mail (gestor, administrador e tablet) não conferia papel,
--    pessoa ativa, loja ativa nem situação da conta.
--    → Agora confere, no banco, antes de devolver o resumo da senha.
--
-- 3) A senha guardada do gestor/tablet nunca era apagada: desativar a loja não
--    tirava a senha do tablet.
--    → Desativar a loja apaga a senha do tablet; redefinir também.
--
-- 4) A corrida sobrevivia na contagem por ORIGEM (mesma origem, CPFs
--    diferentes): "espalhar uma senha comum por vários CPFs" não era contido.
--    → A tranca passa a valer também para a origem.
--
-- 5) O expurgo passou a marcar de menos quando duas entregas apontam para o
--    mesmo arquivo.

-- ---------------------------------------------------------------------------
-- 1. Trava que segura o atacante sem trancar o dono
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave  text     := left(coalesce(p_chave, ''), 64);
  v_origem text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros  integer;
  v_id     bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Duas trancas, SEMPRE nesta ordem (chave e depois origem), para duas
  -- tentativas nunca contarem ao mesmo tempo — nem a mesma pessoa, nem o mesmo
  -- aparelho tentando pessoas diferentes. A ordem fixa evita travar uma na
  -- outra.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- Teto do dia: SÓ para o PIN, e contando só erro. No PIN quem tenta já está
  -- logado como a própria pessoa, então ninguém gasta a cota de outro. No
  -- login não existe teto de dia: senão bastava errar 50 vezes o e-mail de
  -- alguém para deixar essa pessoa sem sistema até o dia seguinte.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela (o acerto zera).
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
     AND NOT t.sucesso AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN NULL;
  END IF;

  -- E erros seguidos desta origem (o mesmo aparelho tentando vários CPFs).
  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. O login por e-mail confere papel, pessoa ativa, loja ativa e conta
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.acesso_por_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE u record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura acesso por e-mail.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT au.id AS userid, s.senhahashapp, cu.contaid, cu.papel,
         c.status AS statusconta, l.ativa AS lojaativa,
         lower(au.email) = 'wisley_anderson@hotmail.com' AS ehadmin
    INTO u
    FROM auth.users au
    LEFT JOIN public.senhasgestor s ON s.userid = au.id
    LEFT JOIN public.contasusuarios cu ON cu.userid = au.id
    LEFT JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
   WHERE lower(au.email) = lower(btrim(coalesce(p_email, '')));
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Esta porta é do gestor, do administrador geral e do tablet. O colaborador
  -- entra pelo CPF, com as conferências dele.
  IF NOT (u.ehadmin OR u.papel IN ('master', 'gerente', 'loja')) THEN
    RETURN NULL;
  END IF;
  -- Conta cancelada e loja desativada perdem o acesso no LOGIN, não só depois.
  IF u.papel IS NOT NULL AND coalesce(u.statusconta, 'ativa') = 'cancelada' THEN
    RETURN NULL;
  END IF;
  IF u.papel = 'loja' AND coalesce(u.lojaativa, false) = false THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid, 'papel', coalesce(u.papel, 'admin'));
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. A senha guardada do tablet some quando a loja é desativada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.limpa_senha_do_tablet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativa AND NOT NEW.ativa THEN
    DELETE FROM public.senhasgestor s
     USING public.contasusuarios cu
     WHERE cu.contaid = NEW.contaid AND cu.lojaid = NEW.lojaid AND cu.papel = 'loja'
       AND s.userid = cu.userid;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS lojas_limpa_senha_do_tablet ON public.lojas;
CREATE TRIGGER lojas_limpa_senha_do_tablet
  AFTER UPDATE OF ativa ON public.lojas
  FOR EACH ROW EXECUTE FUNCTION public.limpa_senha_do_tablet();

-- Apagar a senha guardada de um acesso (usada ao desativar pelo servidor).
CREATE OR REPLACE FUNCTION public.limpar_senha_gestor(p_userid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor apaga senha guardada.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.senhasgestor WHERE userid = p_userid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Expurgo: marcar pelo caminho que está na fila (não só pelo que acabou de
--    entrar), senão duas entregas com o mesmo arquivo deixam uma para trás
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    -- Põe na fila o que venceu (um caminho só entra uma vez)...
    INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
    SELECT p_contaid, e.entregaid, e.pathfotoevidencia
      FROM public.entregas e
     WHERE e.contaid = p_contaid
       AND e.pathfotoevidencia IS NOT NULL
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias)
     ORDER BY e.dataenvio
     LIMIT 2000
    ON CONFLICT (contaid, caminho) DO NOTHING;

    -- ...e marca TODA entrega cujo arquivo está na fila (duas entregas podem
    -- apontar para a mesma foto: nenhuma pode ficar para trás).
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM public.fotosexpurgo f
     WHERE e.contaid = p_contaid AND f.contaid = p_contaid
       AND e.pathfotoevidencia = f.caminho
       AND e.fotoexpiradaem IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    SELECT count(*) INTO v_presas FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5;
    IF v_presas > 0 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso',
             v_presas || ' foto(s) marcada(s) como apagada(s) continuam no armazenamento: a remoção falhou 5 vezes.'
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas),
                                      v_presas || ' foto(s) não saíram do armazenamento');
      RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('fotos', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Senha do app pelo número da pessoa (não pelo CPF, que pode estar vazio)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.senha_app_do_funcionario(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE f record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor confere senha.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT fu.senhahashapp INTO f FROM public.funcionarios fu
   WHERE fu.contaid = p_contaid AND fu.funcionarioid = p_funcionarioid AND fu.ativo;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('senhahash', f.senhahashapp);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.limpar_senha_gestor(uuid)',
    'public.senha_app_do_funcionario(integer, integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;


-- =========================================================================
-- 20260927100800_pin_tablet_e_expurgo.sql
-- =========================================================================

-- Etapa 1.12, parte A — consertos da QUARTA revisão adversarial (23/09/2026).
--
-- Três defeitos que os meus próprios consertos criaram, e a decisão do Wisley
-- sobre o tablet.
--
-- 1) O adivinhador de PIN voltou. Ao fazer o teto do dia contar só ERRO (para
--    ninguém trancar a conta de outro), esqueci que no adivinhador o resultado
--    comum é ACERTO: o número livre é aceito, e acerto não contava nem para o
--    teto — e ainda zerava a janela.
--    → No PIN o teto conta TODA tentativa, como era antes. Ali isso não tranca
--      ninguém: quem tenta já está logado como a própria pessoa, então só
--      gasta a própria cota. No login continua contando só erro.
--
-- 2) Desativar e reativar alguém deixava a pessoa sem entrar para sempre: a
--    desativação sorteava uma senha que ninguém guardava.
--    → A reativação devolve a senha interna (quem faz isso é o servidor).
--      Aqui fica só a marca de que a pessoa precisa disso.
--
-- 3) O expurgo passou a apagar foto DENTRO do prazo: bastava outra entrega
--    apontar para o mesmo arquivo.
--    → Volta a marcar só entrega que venceu de verdade.
--
-- 4) Decisão do Wisley: a trava por e-mail não pode derrubar o tablet da loja
--    num horário de pico. Como a senha do tablet é sorteada pelo servidor (14
--    caracteres, 70 bits), adivinhar é impossível na prática, e a trava por
--    chave só transferia o prejuízo do atacante para a loja.
--    → Para o tablet vale só a trava por ORIGEM (que é quem realmente segura o
--      atacante). Isso NÃO vale para gestor e colaborador, que têm senha
--      escolhida por pessoa.

-- ---------------------------------------------------------------------------
-- 1. Tipo novo de tentativa: o tablet
-- ---------------------------------------------------------------------------
ALTER TABLE public.tentativasacesso DROP CONSTRAINT IF EXISTS tentativasacesso_tipo_check;
ALTER TABLE public.tentativasacesso DROP CONSTRAINT IF EXISTS tentativasacesso_tipo_check;
ALTER TABLE public.tentativasacesso ADD CONSTRAINT tentativasacesso_tipo_check
  CHECK (tipo IN ('senha', 'pin', 'tablet'));
COMMENT ON COLUMN public.tentativasacesso.tipo IS
  'senha (gestor e colaborador), pin (tablet) ou tablet (login do próprio tablet, sem trava por chave).';

CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave  text     := left(coalesce(p_chave, ''), 64);
  v_origem text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros  integer;
  v_id     bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tipo NOT IN ('senha', 'pin', 'tablet') THEN
    RAISE EXCEPTION 'Tipo de tentativa inválido.' USING ERRCODE = 'check_violation';
  END IF;

  -- Duas trancas, SEMPRE nesta ordem (chave e depois origem), para duas
  -- tentativas nunca contarem ao mesmo tempo. A ordem fixa evita travar uma na
  -- outra.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- PIN: teto de 30 no dia contando TODA tentativa (acerto inclusive). É o que
  -- impede usar a tela do PIN como adivinhador: ali o resultado comum é
  -- acerto. E não tranca ninguém de fora, porque quem tenta já está logado
  -- como a própria pessoa: só gasta a própria cota.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela (o acerto zera).
  -- NÃO vale para o tablet: a senha dele é sorteada pelo servidor (impossível
  -- de adivinhar) e travá-la por e-mail só deixaria a loja sem sistema.
  IF p_tipo <> 'tablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta origem: é o eixo que o atacante controla e a vítima
  -- não. Vale para todos, inclusive para o tablet.
  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. O login por e-mail: quem não tem papel nenhum não entra
-- ---------------------------------------------------------------------------
-- Antes, um login sem vínculo (convite pela metade, cadastro órfão) passava
-- pela conferência por causa da lógica de três valores do SQL — e ainda era
-- rotulado como "admin".
CREATE OR REPLACE FUNCTION public.acesso_por_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE u record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura acesso por e-mail.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT au.id AS userid, s.senhahashapp, cu.contaid, coalesce(cu.papel, '') AS papel,
         coalesce(c.status, 'ativa') AS statusconta, l.ativa AS lojaativa,
         coalesce(lower(au.email) = 'wisley_anderson@hotmail.com', false) AS ehadmin
    INTO u
    FROM auth.users au
    LEFT JOIN public.senhasgestor s ON s.userid = au.id
    LEFT JOIN public.contasusuarios cu ON cu.userid = au.id
    LEFT JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
   WHERE lower(au.email) = lower(btrim(coalesce(p_email, '')));
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Esta porta é do gestor, do administrador geral e do tablet. O colaborador
  -- entra pelo CPF, com as conferências dele. Sem papel, ninguém entra.
  IF NOT (u.ehadmin OR u.papel IN ('master', 'gerente', 'loja')) THEN
    RETURN NULL;
  END IF;
  IF u.papel <> '' AND u.statusconta = 'cancelada' THEN
    RETURN NULL;
  END IF;
  IF u.papel = 'loja' AND coalesce(u.lojaativa, false) = false THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid,
                            'papel', CASE WHEN u.papel = '' THEN 'admin' ELSE u.papel END);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Expurgo: marcar só o que venceu de verdade
-- ---------------------------------------------------------------------------
-- O conserto anterior passou a marcar toda entrega que dividisse o caminho com
-- uma vencida — e apagava foto de entrega recente, possivelmente ainda em
-- discussão de validação.
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
    SELECT p_contaid, e.entregaid, e.pathfotoevidencia
      FROM public.entregas e
     WHERE e.contaid = p_contaid
       AND e.pathfotoevidencia IS NOT NULL
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias)
     ORDER BY e.dataenvio
     LIMIT 2000
    ON CONFLICT (contaid, caminho) DO NOTHING;

    -- Marca as entregas VENCIDAS cujo arquivo está na fila. O prazo entra aqui
    -- também: sem ele, uma entrega recente que dividisse o caminho com uma
    -- vencida perdia a foto junto.
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM public.fotosexpurgo f
     WHERE e.contaid = p_contaid AND f.contaid = p_contaid
       AND e.pathfotoevidencia = f.caminho
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias);
    GET DIAGNOSTICS v_n = ROW_COUNT;

    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    SELECT count(*) INTO v_presas FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5;
    IF v_presas > 0 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso',
             v_presas || ' foto(s) marcada(s) como apagada(s) continuam no armazenamento: a remoção falhou 5 vezes.'
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas),
                                      v_presas || ' foto(s) não saíram do armazenamento');
      RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('fotos', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;


-- =========================================================================
-- 20260927100900_diagnostico_do_sistema.sql
-- =========================================================================

-- Etapa 1.12, parte A — diagnóstico do sistema (23/09/2026).
--
-- Motivo: o administrador geral ficou sem conseguir entrar depois da publicação
-- e a tela só dizia "Não foi possível conferir o acesso agora". A causa era o
-- banco ainda não ter recebido estas migrações — e não havia jeito de descobrir
-- isso sem olhar o código.
--
-- Esta função diz o que está faltando, sem revelar valor de segredo nenhum.
-- Se ela própria não existir, a resposta do servidor já é a prova de que o
-- banco está desatualizado.
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_fechar', 'acesso_por_email', 'definir_senha_gestor',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado'
  ];
  v_faltando text[];
  v_tabelas  text[];
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pede o diagnóstico.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_faltando
    FROM unnest(v_esperadas) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);

  SELECT coalesce(array_agg(t ORDER BY t), ARRAY[]::text[]) INTO v_tabelas
    FROM unnest(ARRAY['codigosacesso', 'tentativasacesso', 'senhasgestor', 'fotosexpurgo']) t
   WHERE to_regclass('public.' || t) IS NULL;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;


COMMIT;

-- Conferência final: deve responder "tudo certo".
SELECT CASE WHEN count(*) = 5 THEN 'tudo certo: o banco recebeu a parte A'
            ELSE 'ATENÇÃO: faltou alguma coisa — me avise' END AS resultado
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('tentativa_abrir', 'acesso_por_email', 'meu_acesso',
                     'usar_codigo_acesso', 'diagnostico_do_sistema');
