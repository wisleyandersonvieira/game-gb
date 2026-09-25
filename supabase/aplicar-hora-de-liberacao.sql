-- =========================================================================
-- STGame — "Disponível a partir de": a tarefa só entra na fila na hora
-- combinada, na hora LOCAL DA EMPRESA.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929100600_hora_de_liberacao.sql
--
-- O QUE MUDA PARA QUEM JÁ USA: nada. A coluna nasce VAZIA em todas as
-- atribuições que já existem, e vazio quer dizer "o dia todo" — que é o
-- comportamento de hoje. A configuração de fuso nasce em Brasília.
-- =========================================================================

BEGIN;

-- "Disponível a partir de": a tarefa só entra na fila na hora combinada.
--
-- Pedido do Wisley (25/09/2026): numa loja movimentada as tarefas devem ir
-- surgindo conforme o planejamento, não todas de uma vez às 00h.
--
-- COMPATIBILIDADE: a coluna nasce VAZIA em tudo o que já existe, e vazio quer
-- dizer "o dia todo", que é o comportamento de hoje. Nada muda para quem já
-- está no ar.
--
-- FUSO: a hora é a hora LOCAL DA EMPRESA. Quem decide é uma configuração da
-- conta, porque uma loja em Campo Grande fica uma hora atrás de Brasília e
-- erraria todas as liberações. A conversão é feita AQUI, no banco, com o
-- relógio do servidor — nunca com o relógio do tablet nem do celular.

-- ---------------------------------------------------------------------------
-- 1. A coluna
-- ---------------------------------------------------------------------------
ALTER TABLE public.tarefasatribuidas
  ADD COLUMN IF NOT EXISTS disponivelapartir time;

COMMENT ON COLUMN public.tarefasatribuidas.disponivelapartir IS
  'Hora local da empresa a partir da qual a tarefa entra na fila. Vazio = o dia todo.';

-- ---------------------------------------------------------------------------
-- 2. O fuso da conta
-- ---------------------------------------------------------------------------
-- STABLE, e não IMMUTABLE: lê a configuração da conta. Por isso é uma função
-- NOVA, e instante_local (IMMUTABLE, Brasília) fica como está — ela é usada em
-- outros lugares e mexer nela seria mudar o sistema inteiro de uma vez.
CREATE OR REPLACE FUNCTION public.fuso_da_conta(p_contaid integer)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(
           (SELECT nullif(btrim(valor), '') FROM public.configuracoes
             WHERE contaid = p_contaid AND chave = 'FUSO_HORARIO'),
           'America/Sao_Paulo')
$$;

REVOKE ALL ON FUNCTION public.fuso_da_conta(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fuso_da_conta(integer) TO service_role;

-- O instante exato em que uma hora local da empresa acontece num dia.
CREATE OR REPLACE FUNCTION public.instante_na_conta(p_contaid integer, p_dia date, p_hora time)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (p_dia::timestamp + p_hora) AT TIME ZONE public.fuso_da_conta(p_contaid)
$$;

REVOKE ALL ON FUNCTION public.instante_na_conta(integer, date, time) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.instante_na_conta(integer, date, time) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. A configuração do fuso, em toda conta
-- ---------------------------------------------------------------------------
-- As duas funções abaixo partem da versão MAIS RECENTE (20260928100700), com
-- o diff conferido: entram só a chave nova e a validação dela.
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
    (p_contaid, 'MINUTOS_RODIZIO_ACEITE',       '10',    'Rodizio no aceite: minutos que quem pegou a ultima tarefa disputada da loja espera antes de poder pegar outra. 0 desliga.'),
    (p_contaid, 'MINUTOS_TAREFA_PARADA',        '30',    'A partir de quantos minutos o tablet marca a tarefa como parada ha muito tempo.'),
    (p_contaid, 'TAREFA_ID_FEEDBACK_DIARIO',           '', 'ID da tarefa de feedback diario. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_ID_LEITURA',                   '', 'ID da tarefa de leitura de comunicado. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_MODELO_AGENDAMENTO_ID',        '', 'ID da tarefa modelo usada ao criar um agendamento.'),
    (p_contaid, 'TAREFA_ID_PONTOS_META',               '', 'ID da tarefa que credita os pontos da meta diaria.'),
    (p_contaid, 'TAREFA_ID_NOTA_FISCAL',               '', 'ID da tarefa de envio de nota fiscal.'),
    (p_contaid, 'TAREFA_ID_GUARDAR_MERCADORIA_MODELO', '', 'ID da tarefa modelo de guardar mercadoria.'),
    -- Fuso da empresa: decide a que horas a tarefa fica disponivel. Uma loja
    -- em Campo Grande fica uma hora atras de Brasilia.
    (p_contaid, 'FUSO_HORARIO', 'America/Sao_Paulo',
     'Fuso horario da empresa. Decide a que horas a tarefa fica disponivel para a equipe.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

REVOKE EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) TO service_role;

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

  -- Rodizio no aceite: 0 desliga, e o teto de 2 horas evita travar a loja por
  -- engano ao digitar um numero grande.
  ELSIF NEW.chave = 'MINUTOS_RODIZIO_ACEITE' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer > 120 THEN
      RAISE EXCEPTION 'O tempo de espera precisa ser um número inteiro de 0 a 120 minutos (0 desliga).'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave = 'MINUTOS_TAREFA_PARADA' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer < 5 OR v_texto::integer > 480 THEN
      RAISE EXCEPTION 'O tempo precisa ser um número inteiro de 5 a 480 minutos.'
        USING ERRCODE = 'check_violation';
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

  -- O fuso tem de ser um fuso que o banco conhece: errar aqui erraria TODAS
  -- as liberacoes da conta, e em silencio.
  ELSIF NEW.chave = 'FUSO_HORARIO' THEN
    IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_texto) THEN
      RAISE EXCEPTION 'Fuso horário desconhecido. Use, por exemplo, America/Sao_Paulo.'
        USING ERRCODE = 'check_violation';
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


-- As contas que JÁ EXISTEM recebem a chave nova. Sem isso, a seção de
-- Configurações apareceria vazia — já aconteceu em 25/09/2026.
DO $backfill$
DECLARE c integer;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_configuracoes_padrao(c);
  END LOOP;
END $backfill$;

-- ---------------------------------------------------------------------------
-- 4. A fila da loja sabe quando cada tarefa libera
-- ---------------------------------------------------------------------------
-- A tarefa NÃO some da fila antes da hora: ela vem marcada como não liberada,
-- para o tablet mostrar "Ainda não liberadas (N)" com o horário. Quem recusa
-- pegar antes da hora é pegar_tarefa, logo abaixo.
--
-- Parte da versão mais recente (20260929100200), com o diff conferido.
DROP FUNCTION IF EXISTS public.fila_da_loja(integer);

CREATE OR REPLACE FUNCTION public.fila_da_loja(p_lojaid integer)
RETURNS TABLE (
  atribuicaoid   integer,
  entregarid     integer,
  titulo         varchar,
  pontos         integer,
  tipofrequencia varchar,
  aberta         boolean,
  donoid         integer,
  quempegou      integer,
  quempegounome  text,
  pegaem         timestamptz,
  situacao       text,
  atrasada       boolean,
  -- Desde quando a tarefa está disponível HOJE. O cronômetro do tablet conta
  -- a partir daqui, e não de quando a tela abriu: dois tablets mostram o
  -- mesmo número.
  disponiveldesde timestamptz,
  -- true quando o rodízio está ligado e esta tarefa é disputada (aviso do cartão).
  rodizio        boolean,
  -- O relógio do servidor, para os aparelhos acertarem o deles.
  agora          timestamptz,
  -- Quem entregou, quando e em que pé está a entrega. A faixa "Feitas hoje"
  -- do tablet mostrava só o título e os pontos: a equipe não via quem fez.
  -- Sai da ENTREGA, não do aceite, porque tarefa com dono não passa por
  -- missoesaceites e ficaria sem nome.
  feitapor       text,
  feitaem        timestamptz,
  feitasituacao  text,
  -- "Disponível a partir de": antes da hora a tarefa NÃO pode ser pega.
  -- liberada = já passou da hora (ou não tem hora nenhuma).
  liberada       boolean,
  liberaas       timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (
    SELECT public.minha_conta() AS conta,
           public.dia_em_sao_paulo(now()) AS dia,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = public.minha_conta() AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
  )
  SELECT ta.atribuicaoid,
         CASE WHEN a.aceiteid IS NOT NULL THEN coalesce(a.novaatribuicaoid, ta.atribuicaoid) END,
         t.titulo,
         t.pontos,
         ta.tipofrequencia,
         (ta.funcionarioid IS NULL),
         ta.funcionarioid,
         a.funcionarioid,
         public.nome_curto(qp.nomecompleto),
         a.aceitoem,
         CASE
           -- Tarefa Única: entregue num dia, acabou (vale para a tarefa com
           -- dono e para qualquer cópia da compartilhada).
           WHEN ta.tipofrequencia = 'Unica'
                AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid) THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                           AND public.dia_em_sao_paulo(e.dataenvio) = ctx.dia) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < ctx.dia),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_local(ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_local(ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_em_sao_paulo(ta.dataagendamento) = ctx.dia
                THEN ta.dataagendamento END,
           -- A hora de liberação também conta: o cronômetro de uma tarefa que
           -- abre às 18h começa às 18h, e não à meia-noite — senão ela nasceria
           -- vermelha, com 18 horas de "parada".
           lib.quando),
         (ctx.rodizio > 0 AND ta.funcionarioid IS NULL),
         now(),
         -- nome_curto(NULL) devolve texto VAZIO, nao nulo: sem este CASE a
         -- coluna vinha '' para toda tarefa sem entrega, e "sem nome" deixava
         -- de ser distinguivel de "nome vazio".
         CASE WHEN ent.funcionarioid IS NOT NULL THEN public.nome_curto(fez.nomecompleto) END,
         ent.dataenvio,
         ent.statusvalidacao,
         (lib.quando IS NULL OR lib.quando <= now()),
         lib.quando
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.revogadoem IS NULL
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só de hoje.
    -- Busca mais ampla que a regra faz a tarefa ainda POR FAZER aparecer com
    -- o nome de quem a entregou ontem, ou de quem teve o aceite revogado.
    LEFT JOIN LATERAL (
      SELECT e.funcionarioid, e.dataenvio, e.statusvalidacao
        FROM public.entregas e
       WHERE e.contaid = ctx.conta
         AND e.statusvalidacao IN ('Pendente', 'Aprovada')
         AND (
           (ta.tipofrequencia = 'Unica'
            AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                         WHERE c.contaid = ctx.conta AND c.atribuicaoid = e.atribuicaoid
                           AND (c.atribuicaoid = ta.atribuicaoid
                                OR c.origematribuicaoid = ta.atribuicaoid)))
           OR (e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
               AND public.dia_em_sao_paulo(e.dataenvio) = ctx.dia)
         )
       ORDER BY e.dataenvio DESC
       LIMIT 1
    ) ent ON true
    LEFT JOIN public.funcionarios fez  ON fez.funcionarioid = ent.funcionarioid AND fez.contaid = ctx.conta
    -- A hora de liberação, no fuso DA EMPRESA. A conversão é feita aqui, com
    -- o relógio do servidor: o tablet e o celular não opinam.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN ta.disponivelapartir IS NOT NULL
                  THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.disponivelapartir) END AS quando
    ) lib ON true
   WHERE ctx.conta IS NOT NULL
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT public.passada_hoje(ta.atribuicaoid, ctx.dia)
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3
$$;

REVOKE ALL ON FUNCTION public.fila_da_loja(integer)     FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.fila_da_loja(integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Ninguem pega antes da hora
-- ---------------------------------------------------------------------------
-- Parte da versao mais recente (20260928100700), com o diff conferido.
CREATE OR REPLACE FUNCTION public.pegar_tarefa(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.dia_em_sao_paulo(now());
  m       public.tarefasatribuidas%ROWTYPE;
  v_lista boolean;
  v_nova  integer;
  v_espera integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Sem pessoa para pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND datafimvigencia IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF m.origematribuicaoid IS NOT NULL THEN
    RAISE EXCEPTION 'Esta tarefa já está no nome de alguém.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje) THEN
    RAISE EXCEPTION 'Esta tarefa não vale para hoje.' USING ERRCODE = 'check_violation';
  END IF;
  -- Antes da hora combinada ninguém pega. A hora é a da EMPRESA, convertida
  -- aqui no banco: o tablet não opina sobre que horas são.
  IF m.disponivelapartir IS NOT NULL
     AND public.instante_na_conta(v_conta, v_hoje, m.disponivelapartir) > now() THEN
    RAISE EXCEPTION 'Esta tarefa libera às %.', to_char(m.disponivelapartir, 'HH24"h"MI')
      USING ERRCODE = 'check_violation';
  END IF;
  IF m.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(v_conta, p_atribuicaoid) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = m.lojaid
                                                   AND fl.ativo AND fl.contaid = v_conta
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = v_conta AND f.ativo
                    AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                               f.datafimafastamento, v_hoje)) THEN
    RAISE EXCEPTION 'Só quem trabalha hoje nesta loja pode pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    IF m.funcionarioid <> p_funcionarioid THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                    WHERE c.contaid = v_conta AND c.atribuicaoid = p_atribuicaoid) INTO v_lista;
    IF v_lista AND NOT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                                WHERE c.contaid = v_conta AND c.atribuicaoid = p_atribuicaoid
                                  AND c.funcionarioid = p_funcionarioid) THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Rodízio: quem pegou a última tarefa disputada desta loja espera um pouco
  -- antes de pegar outra. Só vale para tarefa sem dono, e nunca deixa a loja
  -- parada (ver rodizio_espera).
  v_espera := public.rodizio_espera(v_conta, m.lojaid, p_funcionarioid, p_atribuicaoid);
  IF v_espera > 0 THEN
    RAISE EXCEPTION 'Você pegou a última tarefa. Esta libera para você em % min.',
      greatest(1, ceil(v_espera / 60.0)::integer) USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
  VALUES (v_conta, p_atribuicaoid, v_hoje, p_funcionarioid, public.canal_atual())
  ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa já foi pega hoje.' USING ERRCODE = 'unique_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    RETURN p_atribuicaoid;
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        dataatribuicao, dataagendamento, origematribuicaoid)
  VALUES (v_conta, m.tarefaid, p_funcionarioid, m.lojaid, 'Unica', now(), now(), p_atribuicaoid)
  RETURNING atribuicaoid INTO v_nova;

  UPDATE public.missoesaceites SET novaatribuicaoid = v_nova
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
  RETURN v_nova;
END;
$$;

REVOKE ALL ON FUNCTION public.pegar_tarefa(integer, integer)    FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.pegar_tarefa(integer, integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Atribuir com hora, e ALTERAR a hora de uma atribuição que já existe
-- ---------------------------------------------------------------------------
-- A versão antiga (7 parâmetros) sai: senão ficariam as duas no banco e
-- ninguém saberia qual roda.
DROP FUNCTION IF EXISTS public.atribuir_tarefa(integer, integer, integer[], text, integer, timestamptz, time);

CREATE OR REPLACE FUNCTION public.atribuir_tarefa(
  p_tarefaid        integer,
  p_lojaid          integer,
  p_funcionarios    integer[],
  p_tipofrequencia  text,
  p_valorfrequencia integer     DEFAULT NULL,
  p_dataagendamento timestamptz DEFAULT NULL,
  p_horariodisparo  time        DEFAULT NULL,
  -- Hora local da empresa a partir da qual a tarefa entra na fila.
  -- Vazio = o dia todo, como sempre foi.
  p_disponivelapartir time      DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.minha_conta_editavel();
  v_gente   integer[] := coalesce(p_funcionarios, ARRAY[]::integer[]);
  v_quantos integer;
  v_id      integer;
  v_fid     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT count(DISTINCT x) INTO v_quantos FROM unnest(v_gente) x WHERE x IS NOT NULL;

  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE tarefaid = p_tarefaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_quantos = 0 AND p_horariodisparo IS NULL THEN
    RAISE EXCEPTION 'Escolha quem faz a tarefa, ou a hora em que a missão vai para o grupo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Todo mundo escolhido precisa estar ativo e ligado a esta loja.
  IF v_quantos > 0 AND EXISTS (
       SELECT 1 FROM unnest(v_gente) g
        WHERE g IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.funcionarios f
                            JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid
                                                            AND fl.contaid = v_conta AND fl.ativo
                           WHERE f.funcionarioid = g AND f.contaid = v_conta AND f.ativo
                             AND fl.lojaid = p_lojaid)) THEN
    RAISE EXCEPTION 'Escolha só pessoas ativas desta loja.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        valorfrequencia, dataagendamento, horariodisparo, compartilhada,
                                        disponivelapartir)
  VALUES (v_conta, p_tarefaid,
          CASE WHEN v_quantos = 1 THEN (SELECT x FROM unnest(v_gente) x WHERE x IS NOT NULL LIMIT 1) END,
          p_lojaid, p_tipofrequencia, p_valorfrequencia, p_dataagendamento,
          CASE WHEN v_quantos = 0 THEN p_horariodisparo END,
          v_quantos > 1,
          p_disponivelapartir)
  RETURNING atribuicaoid INTO v_id;

  IF v_quantos > 1 THEN
    FOREACH v_fid IN ARRAY v_gente LOOP
      IF v_fid IS NOT NULL THEN
        INSERT INTO public.tarefascandidatos (contaid, atribuicaoid, funcionarioid)
        VALUES (v_conta, v_id, v_fid) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.atribuir_tarefa(integer, integer, integer[], text, integer, timestamptz, time, time)
  FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.atribuir_tarefa(integer, integer, integer[], text, integer, timestamptz, time, time)
  TO authenticated, service_role;

-- Mudar a hora sem encerrar e criar de novo: encerrar perderia o histórico da
-- atribuição, e o gestor teria de refazer tudo só para mexer no horário.
CREATE OR REPLACE FUNCTION public.alterar_hora_da_atribuicao(p_atribuicaoid integer, p_hora time)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.tarefasatribuidas
     SET disponivelapartir = p_hora
   WHERE atribuicaoid = p_atribuicaoid
     AND contaid = v_conta
     AND datafimvigencia IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada ou já encerrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.alterar_hora_da_atribuicao(integer, time) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.alterar_hora_da_atribuicao(integer, time) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. O celular do colaborador mostra "a partir das 15h"
-- ---------------------------------------------------------------------------
-- Parte da versao mais recente (20260929100100), com o diff conferido.
CREATE OR REPLACE FUNCTION public.eu_tarefas(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', x.atribuicaoid,
             'titulo',       x.titulo,
             'pontos',       x.pontos,
             'loja',         x.loja,
             'pegaem',       x.pegaem,
             'situacao',     x.situacao,
             -- Enquanto não libera, a tela do celular mostra "a partir das 15h".
             'liberaas',     x.liberaas,
             'liberada',     x.liberada) ORDER BY x.pegaem NULLS LAST, x.titulo), '[]'::jsonb)
      FROM (
        SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome AS loja, a.aceitoem AS pegaem,
               CASE WHEN e.entregaid IS NULL THEN 'a_fazer'
                    WHEN e.statusvalidacao = 'Pendente'  THEN 'esperando'
                    WHEN e.statusvalidacao = 'Aprovada'  THEN 'aprovada'
                    ELSE 'recusada' END AS situacao,
               -- A hora de liberação, no fuso da EMPRESA e com o relógio do
               -- servidor. O celular não converte nada.
               CASE WHEN ta.disponivelapartir IS NOT NULL
                    THEN public.instante_na_conta(p_contaid, v_hoje, ta.disponivelapartir) END AS liberaas,
               (ta.disponivelapartir IS NULL
                OR public.instante_na_conta(p_contaid, v_hoje, ta.disponivelapartir) <= now()) AS liberada
          FROM public.tarefasatribuidas ta
          JOIN public.tarefas t  ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
                                AND coalesce(t.ativa, true)
          -- Loja desativada não gera mais tarefa: era LEFT JOIN e passava.
          JOIN public.lojas l    ON l.lojaid = ta.lojaid AND l.contaid = p_contaid AND l.ativa
          JOIN public.funcionarios fu ON fu.funcionarioid = p_funcionarioid AND fu.contaid = p_contaid
          LEFT JOIN public.missoesaceites a
                 ON a.contaid = p_contaid AND a.novaatribuicaoid = ta.atribuicaoid AND a.revogadoem IS NULL
          LEFT JOIN LATERAL (
            SELECT e2.entregaid, e2.statusvalidacao FROM public.entregas e2
             WHERE e2.contaid = p_contaid AND e2.atribuicaoid = ta.atribuicaoid
               AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e2.dataenvio) = v_hoje)
             ORDER BY e2.dataenvio DESC LIMIT 1) e ON true
         WHERE ta.contaid = p_contaid
           AND ta.funcionarioid = p_funcionarioid
           AND ta.datafimvigencia IS NULL
           AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje)
           AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
           AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
           -- Folga, afastamento e vínculo com a loja: as mesmas condições da
           -- fila do tablet.
           AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                      fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
           AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                        WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid
                          AND fl.lojaid = ta.lojaid AND fl.ativo)
      ) x);
END;
$$;

REVOKE ALL ON FUNCTION public.eu_tarefas(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_tarefas(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 8. Nem se entrega antes da hora (celular e tablet)
-- ---------------------------------------------------------------------------
-- As duas partem da versao mais recente (20260929100100), com o diff
-- conferido: entra so a condicao f.liberada.
CREATE OR REPLACE FUNCTION public.eu_entregar(p_contaid integer, p_funcionarioid integer,
                                              p_atribuicaoid integer, p_caminho text,
                                              p_observacao text, p_fotoidunico text,
                                              p_semhorafoto boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_lojaid integer;
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT ta.lojaid INTO v_lojaid
    FROM public.tarefasatribuidas ta
   WHERE ta.atribuicaoid = p_atribuicaoid AND ta.contaid = p_contaid
     AND ta.funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa não é sua.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, v_lojaid, 'colaborador');

  -- Na fila de hoje E ja liberada: antes da hora combinada nao se entrega,
  -- como nao se pega.
  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(v_lojaid) f
                  WHERE (f.atribuicaoid = p_atribuicaoid OR f.entregarid = p_atribuicaoid)
                    AND f.situacao <> 'feita' AND f.liberada) THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN public.registrar_entrega(p_atribuicaoid, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

REVOKE ALL ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
  TO service_role;

CREATE OR REPLACE FUNCTION public.visao_entregar(p_contaid integer, p_lojaid integer,
                                                 p_funcionarioid integer, p_atribuicaoid integer,
                                                 p_caminho text, p_observacao text,
                                                 p_fotoidunico text DEFAULT NULL,
                                                 p_semhorafoto boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  m      public.tarefasatribuidas%ROWTYPE;
  v_hoje date := public.dia_em_sao_paulo(now());
  v_alvo integer;
  v_dono integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  -- Na fila de hoje E ja liberada.
  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(p_lojaid) f
                  WHERE f.atribuicaoid = p_atribuicaoid AND f.situacao <> 'feita' AND f.liberada) THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF m.funcionarioid IS NULL THEN
    SELECT novaatribuicaoid, funcionarioid INTO v_alvo, v_dono
      FROM public.missoesaceites
     WHERE contaid = p_contaid AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
    IF v_alvo IS NULL THEN
      v_alvo := public.pegar_tarefa(p_atribuicaoid, p_funcionarioid);
    ELSIF v_dono <> p_funcionarioid THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF m.funcionarioid <> p_funcionarioid THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  ELSE
    v_alvo := p_atribuicaoid;
  END IF;

  RETURN public.registrar_entrega(v_alvo, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

REVOKE ALL ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text, text, boolean)
  TO service_role;

-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
DECLARE v_conta integer; v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'tarefasatribuidas'
                    AND column_name = 'disponivelapartir') THEN
    RAISE EXCEPTION 'Faltou a coluna tarefasatribuidas.disponivelapartir.';
  END IF;

  -- COMPATIBILIDADE: nada do que já existe pode ter ganhado hora.
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas WHERE disponivelapartir IS NOT NULL) THEN
    RAISE EXCEPTION 'Alguma atribuição que já existia ganhou hora. Isto não devia acontecer.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'alterar_hora_da_atribuicao') THEN
    RAISE EXCEPTION 'Faltou a função de mudar o horário da atribuição.';
  END IF;

  -- A fila tem de saber dizer o que já liberou.
  IF NOT EXISTS (SELECT 1 FROM information_schema.parameters
                  WHERE specific_schema = 'public' AND parameter_name = 'liberada') THEN
    RAISE EXCEPTION 'A fila da loja não sabe dizer o que já liberou.';
  END IF;

  -- Toda conta tem de ter o fuso, senão a seção de Configurações fica vazia.
  IF EXISTS (SELECT 1 FROM public.contas c
              WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                                 WHERE g.contaid = c.contaid AND g.chave = 'FUSO_HORARIO')) THEN
    RAISE EXCEPTION 'O fuso horário não chegou em alguma conta.';
  END IF;

  -- E a conversão tem de ser a da EMPRESA, não a do servidor.
  SELECT contaid INTO v_conta FROM public.contas LIMIT 1;
  IF v_conta IS NOT NULL THEN
    IF to_char(public.instante_na_conta(v_conta, v_hoje, '15:00'::time) AT TIME ZONE 'UTC', 'HH24:MI')
       = '15:00' THEN
      RAISE EXCEPTION 'A hora está sendo tratada como hora do servidor, não da empresa.';
    END IF;
  END IF;

  RAISE NOTICE 'tudo certo: a tarefa pode ter hora de liberação.';
END $verifica$;

COMMIT;
