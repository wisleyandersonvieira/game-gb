-- "Que dia é hoje nesta loja": UM lugar só (27/09/2026).
--
-- O defeito que trouxe isto: às 09h35, a coluna "Feitas hoje" do tablet
-- mostrava seis entregas de ONTEM, todas marcadas como atrasadas. Não era um
-- filtro de 24 horas: a fila não perguntava o dia nenhum para a tarefa Única.
-- A regra de "feita" da Única vale para qualquer dia (ela só se faz uma vez),
-- e a Única continua "caindo no dia" de todos os dias depois do agendamento.
-- Resultado: entregue uma vez, ela ficava para SEMPRE em "Feitas hoje", e
-- como a data marcada já tinha passado, ainda vinha com "atrasada". A TV já
-- tinha a regra certa; a fila do tablet, a do gestor e o celular, não.
--
-- E a causa de fundo: três fontes diferentes respondiam "que dia é hoje".
--   1. São Paulo FIXO, embutido no banco (`dia_em_sao_paulo`, e o fuso
--      escrito à mão em mais 8 funções): 57 funções.
--   2. O fuso DA CONTA (configuração FUSO_HORARIO): só a hora de liberação.
--      A própria fila misturava 1 e 2.
--   3. O APARELHO: 13 telas calculavam "hoje" com o relógio e o fuso do
--      navegador (uma delas, o extrato do celular, em UTC: depois das 21h ela
--      já achava que era amanhã).
--
-- O LUGAR ÚNICO, daqui em diante:
--   fuso_da_conta(conta)          qual fuso vale para a conta (já existia)
--   hoje_da_conta(conta)          QUE DIA É HOJE para a conta, pelo relógio do servidor
--   dia_da_conta(conta, instante) em que dia da conta caiu um instante
--   dia_no_fuso(instante, fuso)   o mesmo, para usar linha a linha depois de
--                                 buscar o fuso UMA vez (buscar o fuso a cada
--                                 linha deixa a consulta 15x mais lenta: medido)
--   meu_hoje()                    o que as TELAS perguntam (hoje, fuso, agora)
--
-- Esta migração passa para o lugar único tudo o que a loja vê: a fila do
-- tablet e do gestor, aceitar, entregar, o PIN, o celular e a TV (11
-- funções). As outras ~46 (painel do gestor, ranking, metas, agenda,
-- relatórios, bot) seguem em São Paulo fixo até a próxima etapa; o teste de
-- isolamento conta quantas faltam e reprova se esse número SUBIR.

-- ---------------------------------------------------------------------------
-- 1. O lugar único
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dia_no_fuso(p_instante timestamptz, p_fuso text)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT (p_instante AT TIME ZONE coalesce(p_fuso, 'America/Sao_Paulo'))::date
$$;
REVOKE ALL ON FUNCTION public.dia_no_fuso(timestamptz, text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.dia_no_fuso(timestamptz, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dia_da_conta(p_contaid integer, p_instante timestamptz)
RETURNS date
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.dia_no_fuso(p_instante, public.fuso_da_conta(p_contaid))
$$;
REVOKE ALL ON FUNCTION public.dia_da_conta(integer, timestamptz) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dia_da_conta(integer, timestamptz) TO service_role;

-- A hora é SEMPRE a do servidor (now()): relógio de aparelho não entra.
CREATE OR REPLACE FUNCTION public.hoje_da_conta(p_contaid integer)
RETURNS date
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.dia_da_conta(p_contaid, now())
$$;
REVOKE ALL ON FUNCTION public.hoje_da_conta(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.hoje_da_conta(integer) TO service_role;

-- O que as telas perguntam. Vale para qualquer login (gestor, tablet,
-- colaborador): a conta sai do próprio login, e a resposta só diz o dia e o
-- fuso dela. Quem não tem conta (o administrador geral) recebe São Paulo.
CREATE OR REPLACE FUNCTION public.meu_hoje()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH c AS (SELECT (SELECT cu.contaid FROM public.contasusuarios cu WHERE cu.userid = auth.uid()) AS conta)
  SELECT jsonb_build_object('hoje', public.hoje_da_conta(c.conta),
                            'fuso', public.fuso_da_conta(c.conta),
                            'agora', now())
    FROM c
$$;
REVOKE ALL ON FUNCTION public.meu_hoje() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.meu_hoje() TO authenticated, service_role;

-- "A tarefa cai neste dia?" com o fuso da conta. A versão de 4 parâmetros
-- (São Paulo fixo) continua para as funções que ainda não passaram, e agora
-- chama esta: a regra é uma só.
CREATE OR REPLACE FUNCTION public.tarefa_cai_no_dia(
  p_tipofrequencia varchar,
  p_valorfrequencia integer,
  p_dataagendamento timestamptz,
  p_dia date,
  p_fuso text
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
        OR public.dia_no_fuso(p_dataagendamento, p_fuso) <= p_dia;
  END IF;

  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.tarefa_cai_no_dia(varchar, integer, timestamptz, date, text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.tarefa_cai_no_dia(varchar, integer, timestamptz, date, text)
  TO authenticated, service_role;

-- Parte da única versão (20260921110000): o corpo vira uma chamada à de cima.
CREATE OR REPLACE FUNCTION public.tarefa_cai_no_dia(
  p_tipofrequencia varchar,
  p_valorfrequencia integer,
  p_dataagendamento timestamptz,
  p_dia date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.tarefa_cai_no_dia(p_tipofrequencia, p_valorfrequencia, p_dataagendamento, p_dia,
                                  'America/Sao_Paulo')
$$;

-- ---------------------------------------------------------------------------
-- 2. A fila (tablet e "Fila do dia" do gestor)
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100600), com o diff conferido. Ganha
-- duas colunas no fim (hoje, fuso), e por isso é recriada: o Postgres não
-- deixa mudar as colunas de retorno com CREATE OR REPLACE.
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
  liberaas       timestamptz,
  -- O dia de hoje DA EMPRESA e o fuso dela, ditos pelo servidor. A tela usa
  -- os dois para escrever "ontem às 19h47" quando uma hora não é de hoje, sem
  -- consultar o relógio nem o fuso do aparelho.
  hoje           date,
  fuso           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (
    SELECT public.minha_conta() AS conta,
           -- O dia de hoje e o fuso vêm do LUGAR ÚNICO (hoje_da_conta /
           -- fuso_da_conta), uma vez por consulta.
           public.hoje_da_conta(public.minha_conta()) AS dia,
           public.fuso_da_conta(public.minha_conta()) AS fuso,
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
                           AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         -- Atrasada é o que AINDA falta fazer. A Única entregue hoje, mesmo
         -- marcada para ontem, está em "Feitas hoje": não é atrasada.
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.dia
          AND NOT public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid)),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_na_conta(ctx.conta, ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) = ctx.dia
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
         lib.quando,
         ctx.dia,
         ctx.fuso
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
               AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia)
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
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT public.passada_hoje(ta.atribuicaoid, ctx.dia)
     -- A Única entregue num dia ANTERIOR acabou: não volta na fila de hoje.
     -- Sem isto ela ficava para sempre em "Feitas hoje" (a regra de "feita"
     -- da Única vale para qualquer dia, porque ela só se faz uma vez), e
     -- ainda marcada como atrasada. A TV já tinha esta regra; a fila, não.
     AND NOT (ta.tipofrequencia = 'Unica'
              AND EXISTS (SELECT 1 FROM public.entregas e
                            JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid
                                                           AND c.contaid = ctx.conta
                           WHERE e.contaid = ctx.conta
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                             AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                             AND public.dia_no_fuso(e.dataenvio, ctx.fuso) < ctx.dia))
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
-- 3. O resto do que a loja vê: cada uma parte da versão mais recente, e só
--    trocam as datas (e, no celular, entra a mesma regra da Única da fila).
-- ---------------------------------------------------------------------------

-- tarefas_nao_pegas: parte de 20260928100200_consertos_revisao_b1.sql
CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL)
RETURNS TABLE (
  atribuicaoid integer,
  lojaid       integer,
  loja         varchar,
  titulo       varchar,
  pontos       integer,
  atribuidos   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.minha_conta() AS conta,
                      public.hoje_da_conta(public.minha_conta()) AS dia,
                      public.fuso_da_conta(public.minha_conta()) AS fuso)
  SELECT ta.atribuicaoid, ta.lojaid, l.nome, t.titulo, t.pontos,
         coalesce((SELECT string_agg(public.nome_curto(f.nomecompleto), ', ' ORDER BY f.nomecompleto)
                     FROM public.tarefascandidatos c
                     JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = ctx.conta
                    WHERE c.contaid = ctx.conta AND c.atribuicaoid = ta.atribuicaoid),
                  'toda a equipe da loja')
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.funcionarioid IS NULL
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
   WHERE ctx.conta IS NOT NULL
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo
$$;

-- pegar_tarefa: parte de 20260929100800_erro_do_pin_diz_o_motivo.sql
CREATE OR REPLACE FUNCTION public.pegar_tarefa(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_quem text;
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.hoje_da_conta(v_conta);
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
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje, public.fuso_da_conta(v_conta)) THEN
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
    -- Com o NOME: no balcao, "ja foi pega" sem dizer por quem deixa a pessoa
    -- procurando o que nao existe.
    SELECT public.nome_curto(f.nomecompleto) INTO v_quem
      FROM public.missoesaceites a
      JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
     WHERE a.contaid = v_conta AND a.atribuicaoid = p_atribuicaoid AND a.dia = v_hoje
       AND a.revogadoem IS NULL;
    RAISE EXCEPTION 'Esta tarefa já foi pega hoje por %.', coalesce(v_quem, 'outra pessoa')
      USING ERRCODE = 'unique_violation';
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

-- visao_pessoa_do_pin: parte de 20260929130000_pin_do_tablet_numa_ida.sql
CREATE OR REPLACE FUNCTION public.visao_pessoa_do_pin(p_contaid integer, p_lojaid integer, p_pinhash text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.hoje_da_conta(p_contaid);
  f      record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT fu.funcionarioid, fu.nomecompleto INTO f
    FROM public.funcionarios fu
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = fu.funcionarioid AND fl.contaid = p_contaid
                                    AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE fu.contaid = p_contaid AND fu.ativo
     AND fu.pinhash = p_pinhash::bpchar
     AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
   LIMIT 1;

  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('funcionarioid', f.funcionarioid,
                            'nome', public.nome_curto(f.nomecompleto));
END;
$$;

-- visao_entregar: parte de 20260929100700_aceite_obrigatorio_e_som.sql
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
  v_hoje date := public.hoje_da_conta(p_contaid);
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

  -- NINGUEM ENTREGA SEM ACEITAR ANTES (regra do Wisley, 25/09/2026).
  --
  -- Antes: entregar sem ter pegado VALIA como aceite, e a tarefa de dono
  -- unico nem passava pelo aceite. Agora o caminho e sempre o mesmo, e vale
  -- para TODA tarefa: aceitar com o PIN, depois entregar.
  --
  -- A regra mora aqui, no banco, e nao na tela: esconder o botao nao resolve,
  -- porque quem sabe mexer no navegador contorna. Esta funcao so o servidor
  -- chama, e e por ela que passa toda entrega feita no tablet.
  SELECT novaatribuicaoid, funcionarioid INTO v_alvo, v_dono
    FROM public.missoesaceites
   WHERE contaid = p_contaid AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aceite a tarefa antes de entregar.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Quem aceitou e o unico que entrega. Ja valia para tarefa disputada;
  -- passa a valer para todas.
  IF v_dono <> p_funcionarioid THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Tarefa com dono unico nao gera copia: o aceite fica na propria atribuicao.
  v_alvo := coalesce(v_alvo, p_atribuicaoid);

  RETURN public.registrar_entrega(v_alvo, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

-- registrar_entrega: parte de 20260929100000_visao_do_colaborador.sql
CREATE OR REPLACE FUNCTION public.registrar_entrega(
  p_atribuicaoid integer,
  p_observacao   text    DEFAULT NULL,
  p_pathfoto     text    DEFAULT NULL,
  p_aprovar      boolean DEFAULT false,
  -- Impressão digital da imagem: a mesma foto não prova duas tarefas, nem
  -- que o arquivo mude de nome. O Telegram já usava este campo com o id dele.
  p_fotoidunico  text    DEFAULT NULL,
  -- true quando o arquivo não trazia a hora em que a foto foi tirada. A
  -- entrega entra assim mesmo e o Quadro avisa: o gestor decide na aprovação.
  p_semhorafoto  boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_hoje  date    := public.hoje_da_conta(v_conta);
  v_foto  text    := nullif(btrim(coalesce(p_pathfoto, '')), '');
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_atr FROM public.tarefasatribuidas
  WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_atr.datafimvigencia IS NOT NULL THEN
    RAISE EXCEPTION 'Esta atribuição foi encerrada.' USING ERRCODE = 'check_violation';
  END IF;

  IF v_atr.funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Atribuição sem funcionário não recebe entrega.' USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.tarefa_cai_no_dia(v_atr.tipofrequencia, v_atr.valorfrequencia, v_atr.dataagendamento, v_hoje, public.fuso_da_conta(v_conta)) THEN
    RAISE EXCEPTION 'Esta tarefa não cai hoje.' USING ERRCODE = 'check_violation';
  END IF;

  -- Unica: depois de entregue (pendente ou aprovada) em qualquer dia, acabou.
  -- Na compartilhada, vale para qualquer cópia: senão a tarefa voltava todo
  -- dia e pagava de novo.
  IF v_atr.tipofrequencia = 'Unica'
     AND public.tarefa_unica_ja_cumprida(v_conta, coalesce(v_atr.origematribuicaoid, p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF v_foto IS NOT NULL AND v_foto NOT LIKE v_conta || '/' || v_atr.lojaid || '/%' THEN
    RAISE EXCEPTION 'A foto precisa estar na pasta da própria loja.' USING ERRCODE = 'check_violation';
  END IF;

  -- A mesma foto não prova duas tarefas: pelo caminho e pela imagem em si.
  IF v_foto IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                     WHERE e.contaid = v_conta AND e.pathfotoevidencia = v_foto) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;
  IF p_fotoidunico IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                            WHERE e.contaid = v_conta AND e.fotoidunico = p_fotoidunico) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Entregar vale como aceite (tarefa com dono; a cópia da compartilhada já
  -- nasceu de um aceite).
  IF v_atr.origematribuicaoid IS NULL THEN
    INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
    VALUES (v_conta, p_atribuicaoid, v_hoje, v_atr.funcionarioid, public.canal_atual())
    ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  END IF;

  BEGIN
    INSERT INTO public.entregas (
      contaid, tarefaid, funcionarioid, lojaid, atribuicaoid,
      dataenvio, pathfotoevidencia, observacao, statusvalidacao,
      fotoidunico, semhorafoto
    ) VALUES (
      v_conta, v_atr.tarefaid, v_atr.funcionarioid, v_atr.lojaid, p_atribuicaoid,
      now(), v_foto, nullif(btrim(coalesce(p_observacao, '')), ''), 'Pendente',
      nullif(btrim(coalesce(p_fotoidunico, '')), ''), coalesce(p_semhorafoto, false)
    )
    RETURNING entregaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Já existe uma entrega desta atribuição hoje, pendente ou aprovada.'
      USING ERRCODE = 'unique_violation';
  END;

  IF p_aprovar THEN
    PERFORM public.aprovar_entrega(v_id);
  END IF;

  RETURN v_id;
END;
$$;

-- eu_entregar: parte de 20260929100700_aceite_obrigatorio_e_som.sql
CREATE OR REPLACE FUNCTION public.eu_entregar(p_contaid integer, p_funcionarioid integer,
                                              p_atribuicaoid integer, p_caminho text,
                                              p_observacao text, p_fotoidunico text,
                                              p_semhorafoto boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_lojaid integer; v_hoje date := public.hoje_da_conta(p_contaid);
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

  -- NINGUEM ENTREGA SEM ACEITAR ANTES. O aceite e sempre no TABLET da loja:
  -- o celular entrega o que ela ja assumiu com o PIN.
  --
  -- A atribuicao que chega aqui e a da PESSOA (a copia, quando a tarefa era
  -- disputada), entao o aceite pode estar nela mesma ou na atribuicao de
  -- origem.
  IF NOT EXISTS (
    SELECT 1 FROM public.missoesaceites a
     WHERE a.contaid = p_contaid AND a.dia = v_hoje AND a.revogadoem IS NULL
       AND a.funcionarioid = p_funcionarioid
       AND (a.novaatribuicaoid = p_atribuicaoid OR a.atribuicaoid = p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Aceite a tarefa no tablet da loja antes de entregar.'
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN public.registrar_entrega(p_atribuicaoid, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

-- eu_tarefas: parte de 20260929100600_hora_de_liberacao.sql
CREATE OR REPLACE FUNCTION public.eu_tarefas(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.hoje_da_conta(p_contaid);
  v_fuso text := public.fuso_da_conta(p_contaid);
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
               AND (ta.tipofrequencia = 'Unica' OR public.dia_no_fuso(e2.dataenvio, v_fuso) = v_hoje)
             ORDER BY e2.dataenvio DESC LIMIT 1) e ON true
         WHERE ta.contaid = p_contaid
           AND ta.funcionarioid = p_funcionarioid
           AND ta.datafimvigencia IS NULL
           AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje, v_fuso)
           AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
           AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
           -- A Única entregue num dia ANTERIOR acabou: não volta hoje (a
           -- mesma regra da fila do tablet e da TV).
           AND NOT (ta.tipofrequencia = 'Unica'
                    AND EXISTS (SELECT 1 FROM public.entregas e3
                                 WHERE e3.contaid = p_contaid AND e3.atribuicaoid = ta.atribuicaoid
                                   AND e3.statusvalidacao IN ('Pendente', 'Aprovada')
                                   AND public.dia_no_fuso(e3.dataenvio, v_fuso) < v_hoje))
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

-- eu_inicio: parte de 20260929100400_conta_cancelada_e_limite_da_foto.sql
CREATE OR REPLACE FUNCTION public.eu_inicio(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.hoje_da_conta(p_contaid);
  f      record;
  v_nota numeric;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Uma porta só para as quatro funções: pessoa ativa E conta não cancelada.
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT nomecompleto, saldopontos INTO f
    FROM public.funcionarios
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT r.nota INTO v_nota
    FROM public.ranking_mensal_da_conta(p_contaid,
           extract(year FROM v_hoje)::integer, extract(month FROM v_hoje)::integer,
           NULL, v_hoje - 1) r
   WHERE r.funcionarioid = p_funcionarioid;

  RETURN jsonb_build_object(
    'nome',   public.nome_curto(f.nomecompleto),
    -- Saldo só em pontos. Nunca convertido em dinheiro nesta visão.
    'saldo',  f.saldopontos,
    'nota',   v_nota,
    'feedbackpendente', public.bot_falta_feedback_ontem(p_contaid, p_funcionarioid),
    'comunicados', (SELECT count(*) FROM public.documentosassinaturas s
                     WHERE s.contaid = p_contaid AND s.funcionarioid = p_funcionarioid
                       AND s.statusassinatura = 'Pendente'));
END;
$$;

-- eu_extrato: parte de 20260929100100_consertos_revisao_c1.sql
CREATE OR REPLACE FUNCTION public.eu_extrato(p_contaid integer, p_funcionarioid integer,
                                             p_de date, p_ate date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fuso text := public.fuso_da_conta(p_contaid);
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN jsonb_build_object(
    'saldo', (SELECT saldopontos FROM public.funcionarios
               WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid),
    'linhas', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'quando', m.datamovimento,
               'pontos', m.pontos,
               'tipo',   m.tipo,
               'descricao', m.descricao) ORDER BY m.datamovimento DESC, m.movimentoid DESC), '[]'::jsonb)
        FROM public.movimentospontos m
       WHERE m.contaid = p_contaid AND m.funcionarioid = p_funcionarioid
         AND public.dia_no_fuso(m.datamovimento, v_fuso) BETWEEN p_de AND p_ate));
END;
$$;

-- montar_painel: parte de 20260929101100_tv_configuravel.sql
CREATE OR REPLACE FUNCTION public.montar_painel(p_contaid integer, p_lojaid integer, p_tv boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje       date := public.hoje_da_conta(p_contaid);
  v_fuso       text := public.fuso_da_conta(p_contaid);
  v_loja       text;
  v_dia        jsonb;
  v_validacao  jsonb;
  v_pendentes  integer;
  v_podio      jsonb;
  v_atividade  jsonb;
  v_andamento  jsonb;
  v_podiomes   jsonb;
BEGIN
  SELECT nome INTO v_loja FROM public.lojas WHERE lojaid = p_lojaid AND contaid = p_contaid;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Tarefas do dia e a situacao de cada uma hoje.
  WITH dia AS (
    SELECT t.titulo,
           t.pontos,
           CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
           (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
            AND public.dia_no_fuso(ta.dataagendamento, v_fuso) < v_hoje) AS atrasada,
           (SELECT e.statusvalidacao
              FROM public.entregas e
             WHERE e.atribuicaoid = ta.atribuicaoid
               AND e.statusvalidacao IN ('Pendente', 'Aprovada')
               AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
             ORDER BY e.entregaid DESC
             LIMIT 1) AS situacao
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid
      JOIN public.funcionarioslojas fl ON fl.funcionarioid = ta.funcionarioid AND fl.lojaid = ta.lojaid
     WHERE ta.contaid = p_contaid
       AND ta.lojaid = p_lojaid
       AND ta.datafimvigencia IS NULL
       AND f.ativo AND fl.ativo AND coalesce(t.ativa, true)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje, v_fuso)
       -- Justificada como "nao se aplica" (pendente ou aceita) nao e tarefa de hoje.
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
       -- Passada hoje para quem está trabalhando: sai da lista de quem está de folga.
       AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
       -- Unica entregue num dia anterior ja nao e tarefa de hoje.
       AND NOT (ta.tipofrequencia = 'Unica' AND EXISTS (
             SELECT 1 FROM public.entregas e2
              WHERE e2.atribuicaoid = ta.atribuicaoid
                AND e2.statusvalidacao IN ('Pendente', 'Aprovada')
                AND public.dia_no_fuso(e2.dataenvio, v_fuso) < v_hoje))
  )
  SELECT jsonb_build_object(
           'total',       count(*),
           'aprovadas',   count(*) FILTER (WHERE situacao = 'Aprovada'),
           'emvalidacao', count(*) FILTER (WHERE situacao = 'Pendente'),
           'parafazer',   coalesce(
                            jsonb_agg(
                              jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                                 'pontos', pontos, 'atrasada', atrasada)
                              ORDER BY atrasada DESC, pessoa, titulo
                            ) FILTER (WHERE situacao IS NULL),
                            '[]'::jsonb))
    INTO v_dia
    FROM dia;

  -- Em validacao: todas as pendentes da loja, de qualquer dia.
  SELECT count(*) INTO v_pendentes
    FROM public.entregas
   WHERE contaid = p_contaid AND lojaid = p_lojaid AND statusvalidacao = 'Pendente';

  SELECT coalesce(jsonb_agg(
           jsonb_build_object('titulo', titulo, 'pessoa', pessoa, 'pontos', pontos,
                              'enviadaem', dataenvio, 'dehoje', dehoje)
           ORDER BY dataenvio), '[]'::jsonb)
    INTO v_validacao
    FROM (
      SELECT t.titulo, t.pontos, e.dataenvio,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje AS dehoje
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio
       LIMIT 50
    ) s;

  -- Podio do dia: pontos aprovados hoje na loja.
  SELECT coalesce(jsonb_agg(jsonb_build_object('pessoa', pessoa, 'pontos', pontos)
                            ORDER BY pontos DESC, pessoa), '[]'::jsonb)
    INTO v_podio
    FROM (
      SELECT CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             sum(e.pontosganhos)::integer AS pontos
        FROM public.entregas e
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataaprovacao, v_fuso) = v_hoje
       GROUP BY f.funcionarioid, f.nomecompleto
       ORDER BY sum(e.pontosganhos) DESC, f.nomecompleto
       LIMIT 3
    ) s;

  -- Atividade recente: as ultimas aprovacoes do dia.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pontos', pontos, 'aprovadaem', dataaprovacao)
                            ORDER BY dataaprovacao DESC), '[]'::jsonb)
    INTO v_atividade
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataaprovacao,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataaprovacao, v_fuso) = v_hoje
       ORDER BY e.dataaprovacao DESC
       LIMIT 10
    ) s;

  -- EM ANDAMENTO: quem pegou e ainda nao entregou. A TV precisa disto para a
  -- coluna do mesmo nome; antes so existia na fila do tablet, que o visitante
  -- sem login nao alcanca.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pegaem', pegaem)
                            ORDER BY pegaem), '[]'::jsonb)
    INTO v_andamento
    FROM (
      SELECT t.titulo, a.aceitoem AS pegaem,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.missoesaceites a
        JOIN public.tarefasatribuidas ta ON ta.contaid = a.contaid AND ta.atribuicaoid = a.atribuicaoid
        JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
        JOIN public.funcionarios f       ON f.funcionarioid = a.funcionarioid AND f.contaid = p_contaid
       WHERE a.contaid = p_contaid AND ta.lojaid = p_lojaid
         AND a.dia = v_hoje AND a.revogadoem IS NULL
         -- Ja entregue sai daqui: vira "esperando o gestor" ou "feita".
         AND NOT EXISTS (SELECT 1 FROM public.entregas e
                          WHERE e.contaid = p_contaid
                            AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                            AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
       ORDER BY a.aceitoem
       LIMIT 10
    ) s;

  -- PODIO DO MES: pontos aprovados no mes, nesta loja. O pódio de hoje ja
  -- existia; este e o outro bloco que a TV passou a poder mostrar.
  SELECT coalesce(jsonb_agg(jsonb_build_object('pessoa', pessoa, 'pontos', pontos)
                            ORDER BY pontos DESC, pessoa), '[]'::jsonb)
    INTO v_podiomes
    FROM (
      SELECT CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             sum(e.pontosganhos)::integer AS pontos
        FROM public.entregas e
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = p_contaid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataaprovacao, v_fuso)
             BETWEEN date_trunc('month', v_hoje)::date AND v_hoje
       GROUP BY 1
       ORDER BY 2 DESC
       LIMIT 5
    ) s;

  RETURN jsonb_build_object(
    'loja',         v_loja,
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'progresso',    jsonb_build_object('total',       v_dia->'total',
                                       'aprovadas',   v_dia->'aprovadas',
                                       'emvalidacao', v_dia->'emvalidacao'),
    'parafazer',    v_dia->'parafazer',
    'emvalidacao',  v_validacao,
    'pendentes',    v_pendentes,
    'podio',        v_podio,
    'emandamento',  v_andamento,
    'podiomes',     v_podiomes,
    'atividade',    v_atividade,
    'meta',         public.meta_para_painel(p_contaid, p_lojaid, p_tv),
    'agenda',       public.agenda_para_painel(p_contaid, p_lojaid, p_tv)
  );
END;
$$;
