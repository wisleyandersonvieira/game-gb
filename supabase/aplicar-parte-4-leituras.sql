-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 4: as telas leem pelo banco, e a fila
-- do dia não cresce com os dias de uso.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- CLASSIFICAÇÃO: ACRESCENTA — o site que está no ar continua funcionando com
-- o banco novo: só cria funções e índices, e as funções que já existiam
-- mudam por dentro sem mudar o que devolvem ao master. Aplique ESTE ARQUIVO
-- ANTES do merge.
--
-- ATENÇÃO: o banco precisa já ter aplicar-parte-4-e-decisoes.sql (29/09).
--
-- Este arquivo tem 12 migrações, nesta ordem:
--   1. 20260929275000_fila_nao_cresce_com_os_dias.sql
--   2. 20260929276000_leituras_premios_extrato_ranking.sql
--   3. 20260929277000_leituras_feedbacks_justificativas_solicitacoes.sql
--   4. 20260929278000_leituras_tarefas_metas.sql
--   5. 20260929279000_leituras_agenda.sql
--   6. 20260929280000_leituras_conquistas.sql
--   7. 20260929281000_leituras_comunicados.sql
--   8. 20260929282000_leituras_onboarding.sql
--   9. 20260929283000_leituras_equipe.sql
--   10. 20260929284000_leituras_lojas_jornada.sql
--   11. 20260929285000_codigo_e_valores_rs.sql
--   12. 20260929286000_comunicados_e_inicio_do_gerente_uma_vez.sql
--
-- Para o master nada muda na tela. Nenhum dado é alterado.
-- =========================================================================

BEGIN;

-- ------------------------------------------------------------------------
-- 20260929275000_fila_nao_cresce_com_os_dias.sql
-- ------------------------------------------------------------------------
-- A fila do dia não pode ficar mais lenta a cada dia de uso (29/09/2026).
--
-- A medição com 12 meses de uso (pedido do Wisley) mostrou o Início e o
-- Quadro crescendo em linha reta com os dias: Início 1,2 s com 3 meses, 4,1 s
-- com 12. A causa: a fila do dia, para cada tarefa, lia o histórico INTEIRO de
-- entregas da conta ("a Única já foi cumprida?" e "qual entrega a deixou
-- feita?"): não havia índice para achar as entregas de UMA tarefa, e a busca
-- com "OU" não conseguia usá-lo.
--
-- 1. Dois índices: entregas por tarefa (e data), e cópias por tarefa de origem.
-- 2. fila_no_dia (parte da versão viva, de 20260929265700): a pergunta da
--    Única só é feita para a Única; a entrega que deixou a tarefa feita é
--    buscada pela tarefa, em duas buscas unidas, com a MESMA resposta.
-- 3. atribuicoes_para_entregar_gerente (parte da versão viva, de
--    20260929265500): o fuso e o dia de hoje uma vez só, e a entrega de hoje
--    pelo intervalo do dia (a regra do CLAUDE.md), em vez de converter cada
--    entrega do histórico.
-- 4. As justificativas de uma tarefa, por índice (a fila perguntava para
--    cada tarefa, lendo todas as da conta).
-- 5. Início (master e gerente) e ranking: os filtros "dia da aprovação (ou
--    da recusa) entre o começo do mês e hoje" convertiam a data de cada
--    entrega do ANO para comparar. A regra continua a mesma linha; na frente
--    dela entra uma janela de datas um pouco maior (2 dias antes, 3 depois,
--    em UTC: cobre qualquer fuso), que o índice consegue usar. A janela só
--    corta o que a regra já cortaria: a resposta é a mesma por construção.
-- 6. tarefa_unica_ja_cumprida: a mesma pergunta, começando pelas cópias.
-- Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE INDEX IF NOT EXISTS entregas_atribuicao_envio_idx ON public.entregas (atribuicaoid, dataenvio DESC);
CREATE INDEX IF NOT EXISTS justificativas_atribuicao_dia_idx ON public.justificativas (atribuicaoid, dia);
CREATE INDEX IF NOT EXISTS tarefasatribuidas_origem_idx ON public.tarefasatribuidas (origematribuicaoid)
  WHERE origematribuicaoid IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fila_no_dia(p_contaid integer, p_lojaid integer, p_dia date, p_fim timestamp with time zone)
 RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- MATERIALIZED: o fuso (e o resto do contexto) sai UMA vez por leitura.
  -- Sem isso o Postgres copiava o contexto para dentro de cada subconsulta e
  -- buscava o fuso a cada linha (484 mil vezes em 3 leituras, com 90 dias de
  -- entregas: 2,2 s só nisso).
  WITH ctx AS MATERIALIZED (
    SELECT p_contaid AS conta,
           p_dia AS dia,
           public.fuso_da_conta(p_contaid) AS fuso,
           -- O dia no fuso da conta como INTERVALO (meia-noite a meia-noite):
           -- comparar o horário da entrega com ele é a mesma pergunta que
           -- "dia_no_fuso(horário) = dia", sem converter linha por linha.
           (p_dia::timestamp AT TIME ZONE coalesce(public.fuso_da_conta(p_contaid), 'America/Sao_Paulo')) AS diaini,
           ((p_dia + 1)::timestamp AT TIME ZONE coalesce(public.fuso_da_conta(p_contaid), 'America/Sao_Paulo')) AS diafim,
           -- O fim do dia (a meia-noite seguinte), ou infinity para hoje.
           p_fim AS fim,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = p_contaid AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
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
           WHEN ta.tipofrequencia = 'Unica' AND unica.cumprida THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.dataenvio < ctx.fim
                           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                           AND (e.dataenvio >= ctx.diaini AND e.dataenvio < ctx.diafim)) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         -- Atrasada é o que AINDA falta fazer. A Única entregue hoje, mesmo
         -- marcada para ontem, está em "Feitas hoje": não é atrasada.
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.dia
          AND NOT unica.cumprida),
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
                                      AND a.dia = ctx.dia AND a.aceitoem < ctx.fim
                                      AND (a.revogadoem IS NULL OR a.revogadoem >= ctx.fim)
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- Única cumprida (a de tarefa_unica_ja_cumprida, no fim do dia): entregue
    -- por qualquer cópia, em qualquer dia até o fim deste.
    LEFT JOIN LATERAL (
      -- Só a Única pergunta (nas outras a resposta não é usada): sem isto,
      -- cada tarefa do dia lia o histórico inteiro de entregas da conta.
      SELECT ta.tipofrequencia = 'Unica' AND EXISTS (
        SELECT 1 FROM public.entregas e
          JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = ctx.conta
         WHERE e.contaid = ctx.conta
           AND e.dataenvio < ctx.fim
           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
           AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)) AS cumprida
    ) unica ON true
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só do dia.
    -- A situação é a do fim do dia: recusada ou estornada DEPOIS dele, ainda
    -- estava pendente ou aprovada.
    LEFT JOIN LATERAL (
      -- Duas buscas pela TAREFA (índice por atribuição), em vez de uma só com
      -- "OU", que obrigava a ler o histórico da loja inteira a cada tarefa:
      --   Única: qualquer cópia, qualquer dia;
      --   todas: a cópia de quem pegou, e só do dia.
      -- A mesma resposta de antes: o "OU" continua valendo, pela união.
      SELECT x.funcionarioid, x.dataenvio, x.statusvalidacao
        FROM (SELECT e.funcionarioid, e.dataenvio, e.entregaid, e.statusvalidacao AS st, e.dataaprovacao
                FROM public.tarefasatribuidas c
                JOIN public.entregas e ON e.atribuicaoid = c.atribuicaoid AND e.contaid = ctx.conta
               WHERE ta.tipofrequencia = 'Unica'
                 AND c.contaid = ctx.conta
                 AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                 AND e.dataenvio < ctx.fim
                 AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                      OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                      OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
              UNION ALL
              SELECT e.funcionarioid, e.dataenvio, e.entregaid, e.statusvalidacao, e.dataaprovacao
                FROM public.entregas e
               WHERE e.contaid = ctx.conta
                 AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                 AND e.dataenvio >= ctx.diaini AND e.dataenvio < ctx.diafim
                 AND e.dataenvio < ctx.fim
                 AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                      OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                      OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))) y
       CROSS JOIN LATERAL (
         SELECT y.funcionarioid, y.dataenvio,
                CASE WHEN y.st = 'Recusada' THEN 'Pendente'
                     WHEN y.st = 'Estornada' THEN 'Aprovada'
                     WHEN y.st = 'Aprovada' AND y.dataaprovacao >= ctx.fim THEN 'Pendente'
                     ELSE y.st END::varchar AS statusvalidacao) x
       ORDER BY y.dataenvio DESC, y.entregaid DESC
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
     -- Valia no fim do dia: criada antes dele e não encerrada antes dele.
     AND coalesce(ta.criadaem, '-infinity'::timestamptz) < ctx.fim
     AND (ta.datafimvigencia IS NULL OR ta.encerradaem >= ctx.fim)
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     -- tem_justificativa(..., false), no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.justificativas j
                      WHERE j.contaid = ctx.conta AND j.atribuicaoid = ta.atribuicaoid
                        AND (ta.tipofrequencia = 'Unica' OR j.dia = ctx.dia)
                        AND j.registradoem < ctx.fim
                        AND (j.status IN ('Aceita', 'Pendente')
                             OR (j.status = 'Recusada' AND j.decididoem >= ctx.fim)))
     -- passada_hoje, no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.tarefasdodia p
                      WHERE p.contaid = ctx.conta AND p.atribuicaoid = ta.atribuicaoid AND p.dia = ctx.dia
                        AND p.passadapara IS NOT NULL
                        AND coalesce(p.passadaem, '-infinity'::timestamptz) < ctx.fim)
     -- A Única entregue num dia ANTERIOR acabou: não volta na fila de hoje.
     -- Sem isto ela ficava para sempre em "Feitas hoje" (a regra de "feita"
     -- da Única vale para qualquer dia, porque ela só se faz uma vez), e
     -- ainda marcada como atrasada. A TV já tinha esta regra; a fila, não.
     AND NOT (ta.tipofrequencia = 'Unica'
              AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                            JOIN public.entregas e ON e.atribuicaoid = c.atribuicaoid
                           WHERE e.contaid = ctx.conta
                             AND e.dataenvio < ctx.fim
                             AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                  OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                             AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                             AND e.dataenvio < ctx.diaini))
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3, 1
$function$;

-- atribuicoes_para_entregar_gerente: parte da versão viva.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar_gerente(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- O fuso e o dia de hoje saem UMA vez (antes, a cada linha e a cada
  -- entrega do histórico: a lista crescia com os dias de uso).
  WITH ctx0 AS MATERIALIZED (SELECT public.conta_do_gerente() AS conta),
  ctx AS MATERIALIZED (
    SELECT c.conta, public.fuso_da_conta(c.conta) AS fuso, public.hoje_da_conta(c.conta) AS hoje,
           (public.hoje_da_conta(c.conta)::timestamp AT TIME ZONE public.fuso_da_conta(c.conta)) AS diaini,
           ((public.hoje_da_conta(c.conta) + 1)::timestamp AT TIME ZONE public.fuso_da_conta(c.conta)) AS diafim
      FROM ctx0 c)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.hoje) AS atrasada
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid AND f.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND public.pode('quadro.registrar_entrega', p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.funcionarioid IS NOT NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.hoje, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.hoje, false)
     AND NOT public.passada_hoje(ta.atribuicaoid, ctx.hoje)
     AND NOT EXISTS (
       SELECT 1 FROM public.entregas e
        WHERE e.contaid = ctx.conta AND e.atribuicaoid = ta.atribuicaoid
          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
          AND (ta.tipofrequencia = 'Unica' OR (e.dataenvio >= ctx.diaini AND e.dataenvio < ctx.diafim)))
   ORDER BY f.nomecompleto, t.titulo, ta.atribuicaoid
$function$;

-- painel_inicio: parte da versão viva (de 20260929266000_leituras_inicio_menu.sql); só a janela de datas.
CREATE OR REPLACE FUNCTION public.painel_inicio(p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje      date := public.dia_em_sao_paulo(now());
  v_mes_ini   date := date_trunc('month', public.dia_em_sao_paulo(now()))::date;
  v_mes_fim   date := (date_trunc('month', public.dia_em_sao_paulo(now())) + interval '1 month - 1 day')::date;
  v_sem_ini   date := (date_trunc('week', public.dia_em_sao_paulo(now())) - interval '7 weeks')::date;
  v_lojas     integer[];
  v_cartoes   jsonb;
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
  v_guia      jsonb;
BEGIN
  IF public.minha_conta() IS NULL THEN
    -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
    IF public.conta_do_gerente() IS NOT NULL THEN
      RETURN public.painel_inicio_gerente(p_lojaid);
    END IF;
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Lojas consideradas: a escolhida ou todas as ativas (a RLS já limita à conta).
  IF p_lojaid IS NULL THEN
    SELECT coalesce(array_agg(lojaid), '{}') INTO v_lojas FROM public.lojas WHERE ativa;
  ELSE
    SELECT array_agg(lojaid) INTO v_lojas FROM public.lojas WHERE lojaid = p_lojaid;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;

  -- Tarefas de hoje: a MESMA fila do tablet, do Quadro e da TV (29/09/2026,
  -- decisão do Wisley — a sexta vez que a mesma pergunta tinha duas
  -- respostas). Antes este cartão tinha regra própria: só tarefa com dono,
  -- contava quem estava de folga e ficava de fora a missão da equipe.
  -- fila_da_loja confere a conta de quem pede; a RLS já limitou v_lojas.
  -- A MESMA conta da TV (progresso_da_fila): a fração "concluídas" conta só
  -- as APROVADAS; o que espera o gestor fica à parte (29/09/2026).
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_da_loja(l.lojaid) f;

  -- Meta do dia: soma das lojas que têm meta hoje.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  -- Meta do mês: soma das metas do mês das lojas.
  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1,
                                                            public.meu_hoje()->>'fuso')) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.lojaid = ANY (v_lojas) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             -- Dias (por loja) do mês com meta e sem venda lançada, até ontem.
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  v_cartoes := jsonb_build_object(
    'tarefas',      v_tarefas,
    'metadia',      v_metadia,
    'metames',      v_metames,
    'validar',      (SELECT count(*) FROM public.entregas
                      WHERE lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
    'agendahoje',   (SELECT count(*) FROM public.agendamentos
                      WHERE lojaid = ANY (v_lojas) AND statusagendamento <> 'Cancelado'
                        AND public.dia_em_sao_paulo(dataevento) = v_hoje),
    'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                               'pessoas',     count(DISTINCT s.funcionarioid))
                       FROM public.documentosassinaturas s
                       JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                       JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                      WHERE s.statusassinatura = 'Pendente'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                       JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.ativo
                      WHERE o.statusworkflow = 'Em andamento'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                      WHERE lojaid = ANY (v_lojas) AND status IN ('Aberta', 'Em andamento')),
    'justificativas', (SELECT count(*) FROM public.justificativas
                        WHERE lojaid = ANY (v_lojas) AND status = 'Pendente'));

  -- Vendas do mês, dia a dia, contra a meta (soma das lojas).
  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                            AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas;

  -- Pontos por semana (últimas 8, começando na segunda), pelo livro.
  -- Entraram: aprovações e bônus, já descontados os estornos.
  -- Saíram: resgates, já descontados cancelamentos e estornos de resgate.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(mv.datamovimento))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE 'America/Sao_Paulo')
       AND (p_lojaid IS NULL OR mv.lojaid = p_lojaid)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês (pelo dia da decisão).
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.dataaprovacao))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
    UNION ALL
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.datarecusa))::date, 'r'
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_em_sao_paulo(e.datarecusa) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.datarecusa >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.datarecusa < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês (pontos aprovados no mês).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT * FROM public.ranking_pontos(v_mes_ini, v_hoje, p_lojaid) LIMIT 5) r;

  -- Próximos agendamentos: hora, tipo e responsável (sem dados do cliente).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid
       WHERE a.lojaid = ANY (v_lojas) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
        JOIN public.lojas l        ON l.lojaid = e.lojaid
       WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  -- Guia de primeiros passos (vale para a conta toda).
  v_guia := jsonb_build_object(
    'loja',    EXISTS (SELECT 1 FROM public.lojas WHERE ativa),
    'equipe',  EXISTS (SELECT 1 FROM public.funcionarios f
                         JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.ativo
                        WHERE f.ativo),
    'tarefas', EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
                         JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
                        WHERE ta.datafimvigencia IS NULL AND t.sistema IS NULL),
    'meta',    EXISTS (SELECT 1 FROM public.metasdiariasmodelos WHERE valormeta > 0)
               OR EXISTS (SELECT 1 FROM public.metasprincipais),
    'tv',      EXISTS (SELECT 1 FROM public.linkstv WHERE revogadoem IS NULL));

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes',      v_cartoes,
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    'guia',         v_guia,
    -- Avisos (calculados na hora, sem rotina).
    'avisos', jsonb_build_object(
      -- VENDA DE ONTEM NÃO LANÇADA (29/09/2026): loja ativa que tinha meta
      -- ontem (a especial da data ou o modelo do dia da semana, com valor) e
      -- não tem lançamento de ontem. Loja que não abre tem meta zero naquele
      -- dia (ou uma especial com valor 0 no feriado) e não avisa. Só ontem:
      -- não acumula. Todas as lojas que a pessoa enxerga, com ou sem filtro.
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                       CROSS JOIN LATERAL (SELECT (public.meu_hoje()->>'hoje')::date - 1 AS dia) o
                      WHERE l.ativa
                        -- A MESMA regra da faixa do mês (dias_sem_lancamento).
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, o.dia, o.dia,
                                                                               public.meu_hoje()->>'fuso'))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE lojaid = ANY (v_lojas) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                          WHERE s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND (p_lojaid IS NULL OR EXISTS (
                                  SELECT 1 FROM public.funcionarioslojas fl
                                   WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
      'livro', (SELECT CASE WHEN r.resultado = 'ok' THEN 'ok'
                            WHEN r.detalhe ? 'diferencas' THEN 'diferenca' ELSE 'erro' END
                  FROM public.rotinasexecucoes r
                 WHERE r.rotina = 'conferencia_livro'
                 ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1)),
    -- Última geração da lista de hoje (para "rodou sozinha às 00:05 ✓").
    'rotina', (SELECT jsonb_build_object('quando', coalesce(r.terminadoem, r.iniciadoem),
                                         'resultado', r.resultado, 'origem', r.origem)
                 FROM public.rotinasexecucoes r
                WHERE r.rotina = 'lista_do_dia' AND r.referencia = v_hoje
                ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1));
END;
$function$;

-- painel_inicio_gerente: parte da versão viva (de 20260929268500_lojas_do_gerente_uma_vez.sql); só a janela de datas.
CREATE OR REPLACE FUNCTION public.painel_inicio_gerente(p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta     integer := public.conta_do_gerente();
  v_hoje      date;
  v_fuso      text;
  v_mes_ini   date;
  v_mes_fim   date;
  v_sem_ini   date;
  v_lojas     integer[];
  v_rs        integer[];   -- lojas com meta e R$
  v_agenda_l  integer[];
  v_solic_l   integer[];
  v_just_l    integer[];
  v_metas_l   integer[];
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje    := public.hoje_da_conta(v_conta);
  v_fuso    := public.fuso_da_conta(v_conta);
  v_mes_ini := date_trunc('month', v_hoje)::date;
  v_mes_fim := (date_trunc('month', v_hoje) + interval '1 month - 1 day')::date;
  v_sem_ini := (date_trunc('week', v_hoje) - interval '7 weeks')::date;

  SELECT coalesce(array_agg(l.lojaid ORDER BY l.lojaid), '{}') INTO v_lojas
    FROM public.lojas l
   WHERE l.contaid = v_conta AND l.ativa
     AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('inicio.ver'))::integer[])
     AND (p_lojaid IS NULL OR l.lojaid = p_lojaid);
  IF p_lojaid IS NOT NULL AND cardinality(v_lojas) = 0 THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_rs       := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x) AND public.pode('valores.ver_rs', x));
  v_metas_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x));
  v_agenda_l := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('agenda.ver', x));
  v_solic_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('solicitacoes.ver', x));
  v_just_l   := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('justificativas.ver', x));

  -- Tarefas de hoje: a mesma fila do tablet, do Quadro e da TV.
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_de_hoje(v_conta, l.lojaid) f;

  -- Meta do dia e do mês: só nas lojas com meta e R$.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.contaid = v_conta AND a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1, v_fuso)) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.contaid = v_conta AND mp.lojaid = ANY (v_rs) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                             AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas
   WHERE cardinality(v_rs) > 0;
  v_vendas := coalesce(v_vendas, '[]'::jsonb);

  -- Pontos por semana, pelo livro, só o que foi lançado nas lojas dele.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_no_fuso(mv.datamovimento, v_fuso))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.contaid = v_conta AND mv.lojaid = ANY (v_lojas)
       AND mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE v_fuso)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês.
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_no_fuso(e.dataaprovacao, v_fuso))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
    UNION ALL
    SELECT date_trunc('week', public.dia_no_fuso(e.datarecusa, v_fuso))::date, 'r'
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_no_fuso(e.datarecusa, v_fuso) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.datarecusa >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.datarecusa < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês nas lojas dele (pontos das entregas aprovadas ali).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint AS pontos, count(*)::bigint AS entregas
            FROM public.entregas e
            JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
           WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
             AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
           GROUP BY f.funcionarioid, f.nomecompleto
           ORDER BY 3 DESC, 2, 1
           LIMIT 5) r;

  -- Próximos agendamentos: só nas lojas em que ele vê a agenda.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid AND l.contaid = v_conta
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
       WHERE a.contaid = v_conta AND a.lojaid = ANY (v_agenda_l) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
        JOIN public.lojas l        ON l.lojaid = e.lojaid AND l.contaid = v_conta
       WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes', jsonb_build_object(
      'tarefas',      v_tarefas,
      'metadia',      v_metadia,
      'metames',      v_metames,
      'validar',      (SELECT count(*) FROM public.entregas
                        WHERE contaid = v_conta AND lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
      'agendahoje',   (SELECT count(*) FROM public.agendamentos
                        WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento <> 'Cancelado'
                          AND public.dia_no_fuso(dataevento, v_fuso) = v_hoje),
      'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                 'pessoas',     count(DISTINCT s.funcionarioid))
                         FROM public.documentosassinaturas s
                         JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                         JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                          AND public.pode_na_pessoa('comunicados.ver', v_conta, s.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                         JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE o.contaid = v_conta AND o.statusworkflow = 'Em andamento'
                          AND public.pode_na_pessoa('onboarding.ver', v_conta, o.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                        WHERE contaid = v_conta AND lojaid = ANY (v_solic_l) AND status IN ('Aberta', 'Em andamento')),
      'justificativas', (SELECT count(*) FROM public.justificativas
                          WHERE contaid = v_conta AND lojaid = ANY (v_just_l) AND status = 'Pendente')),
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    -- O guia de primeiros passos é da conta inteira: para o gerente, nada a
    -- mostrar (tudo "feito" esconde o guia).
    'guia', jsonb_build_object('loja', true, 'equipe', true, 'tarefas', true, 'meta', true, 'tv', true),
    'avisos', jsonb_build_object(
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                      WHERE l.contaid = v_conta AND l.ativa AND l.lojaid = ANY (v_metas_l)
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, v_hoje - 1, v_hoje - 1, v_fuso))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                          WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND public.pode_na_pessoa('comunicados.ver', v_conta, s.funcionarioid)
                            AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                         WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'livro', NULL),
    'rotina', NULL);
END;
$function$;

-- ranking_pontos: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); só a janela de datas.
CREATE OR REPLACE FUNCTION public.ranking_pontos(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
  FROM public.entregas e
  JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
  WHERE e.statusvalidacao = 'Aprovada'
    AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN p_de AND p_ate
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((p_de)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((p_ate)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
    AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  GROUP BY f.funcionarioid, f.nomecompleto
  ORDER BY 3 DESC, 2, 1
$function$;

-- tarefa_unica_ja_cumprida: parte da versão viva (de 20260928100200). A MESMA
-- pergunta, escrita para começar pelas cópias da tarefa (poucas, por índice) e
-- só então olhar as entregas delas; antes o banco lia as entregas da conta
-- inteira e cruzava com as cópias, a cada tarefa Única de cada lista.
CREATE OR REPLACE FUNCTION public.tarefa_unica_ja_cumprida(p_contaid integer, p_atribuicaoid integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.tarefasatribuidas c
     CROSS JOIN LATERAL (SELECT 1 FROM public.entregas e
                          WHERE e.atribuicaoid = c.atribuicaoid
                            AND e.contaid = p_contaid
                            AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          LIMIT 1) e
     WHERE c.contaid = p_contaid
       AND (c.atribuicaoid = p_atribuicaoid OR c.origematribuicaoid = p_atribuicaoid))
$function$;

-- ------------------------------------------------------------------------
-- 20260929276000_leituras_premios_extrato_ranking.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 2: Prêmios, Extrato e Ranking (30/09/2026).
--
-- As telas liam tabelas direto (e as regras das tabelas não deixam o gerente
-- ler nada), então vinham VAZIAS para ele. Agora:
--   * pessoas_para(permissão): a lista de pessoas de uma tela. O master
--     recebe o mesmo de antes; o gerente, as pessoas com uma loja em comum
--     com ele onde ele tem aquela permissão; qualquer outro, nada.
--   * Prêmios ("Prêmios: ver"): o catálogo (é da conta inteira, só leitura),
--     a taxa, e os resgates só das lojas dele (resgate sem loja: só o master).
--   * Extrato ("Extrato: ver"): só de quem tem TODAS as lojas dentro das dele
--     (a mesma regra do histórico da pessoa, parte 3).
--   * Ranking ("Ranking: ver"): só por loja dele; "todas as lojas" do mês
--     aberto soma só as lojas dele; o fechado e a nota do mês, só por loja.
-- Para o master nada muda: cada função desvia o gerente logo no começo e
-- segue pelo caminho de sempre. Nenhum dado é alterado.
-- Classificação: ACRESCENTA.

-- A lista de pessoas de uma tela.
CREATE OR REPLACE FUNCTION public.pessoas_para(p_codigo text)
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, ativo boolean,
              saldopontos integer, pontostotal integer, jornadaid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, f.ativo, f.saldopontos, f.pontostotal, f.jornadaid
    FROM public.funcionarios f
   WHERE public.sou_master() AND f.contaid = public.minha_conta()
  UNION ALL
  SELECT f.funcionarioid, f.nomecompleto, f.ativo, f.saldopontos, f.pontostotal, f.jornadaid
    FROM public.funcionarios f
   WHERE NOT public.sou_master()
     AND f.contaid = public.conta_do_gerente()
     AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
                    AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso(p_codigo))::integer[]))
   ORDER BY 2, 1
$$;
REVOKE ALL ON FUNCTION public.pessoas_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pessoas_para(text) TO authenticated;

-- O catálogo de prêmios: da conta inteira, só leitura.
CREATE OR REPLACE FUNCTION public.premios_do_catalogo()
RETURNS TABLE(produtoid integer, nome character varying, descricao text, custoempontos integer,
              estoquedisponivel integer, ativo boolean, sistema character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.produtoid, p.nome, p.descricao, p.custoempontos, p.estoquedisponivel, p.ativo, p.sistema
    FROM public.produtosloja p
   WHERE (public.sou_master() AND p.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND p.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('premios.ver'))::integer[]) > 0)
   ORDER BY p.custoempontos, p.nome, p.produtoid
$$;
REVOKE ALL ON FUNCTION public.premios_do_catalogo() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.premios_do_catalogo() TO authenticated;

-- A taxa de conversão, para o gerente que vê Prêmios ou Extrato.
CREATE OR REPLACE FUNCTION public.minha_taxa_gerente()
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gerente(); v_texto text; v_taxa numeric;
BEGIN
  IF v_conta IS NULL OR (cardinality(public.lojas_onde_posso('premios.ver')) = 0
                         AND cardinality(public.lojas_onde_posso('extrato.ver')) = 0) THEN
    RETURN NULL;
  END IF;
  SELECT valor INTO v_texto FROM public.configuracoes WHERE contaid = v_conta AND chave = 'TAXA_CONVERSAO_PONTO_REAL';
  BEGIN
    v_taxa := nullif(replace(btrim(coalesce(v_texto, '')), ',', '.'), '')::numeric;
  EXCEPTION WHEN others THEN
    v_taxa := NULL;
  END;
  RETURN CASE WHEN v_taxa > 0 THEN v_taxa END;
END;
$$;
REVOKE ALL ON FUNCTION public.minha_taxa_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.minha_taxa_gerente() TO authenticated;

-- minha_taxa: parte da versão viva (de 20260921140000_loja_resgates_extrato.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.minha_taxa()
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_texto text; v_taxa numeric;
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.minha_taxa_gerente();
  END IF;
  SELECT valor INTO v_texto FROM public.configuracoes WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL';
  BEGIN
    v_taxa := nullif(replace(btrim(coalesce(v_texto, '')), ',', '.'), '')::numeric;
  EXCEPTION WHEN others THEN
    v_taxa := NULL;
  END;
  RETURN CASE WHEN v_taxa > 0 THEN v_taxa END;
END;
$function$;

-- Os resgates que o gerente vê: só das lojas em que ele vê Prêmios.
CREATE OR REPLACE FUNCTION public.listar_trocas_gerente(p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         r.valorreais,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          ELSE p.nome END,
               'loja',               l.nome,
               -- De onde veio: "colaborador" quando foi pelo celular. Vazio
               -- nos resgates que o gestor registrou, inclusive os antigos.
               'origem',             r.origem) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid AND f.contaid = r.contaid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid AND p.contaid = r.contaid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid AND l.contaid = r.contaid
       WHERE r.contaid = public.conta_do_gerente()
         AND r.lojaid = ANY ((SELECT public.lojas_onde_posso('premios.ver'))::integer[])
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
$function$;
REVOKE ALL ON FUNCTION public.listar_trocas_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.listar_trocas_gerente(integer) TO authenticated;

-- listar_trocas: parte da versão viva (de 20260929101000_colaborador_pede_resgate.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.listar_trocas(p_limite integer DEFAULT 100)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.listar_trocas_gerente(p_limite);
  END IF;
  RETURN (
SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         r.valorreais,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          ELSE p.nome END,
               'loja',               l.nome,
               -- De onde veio: "colaborador" quando foi pelo celular. Vazio
               -- nos resgates que o gestor registrou, inclusive os antigos.
               'origem',             r.origem) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
  );
END;
$function$;

-- O extrato que o gerente vê: só de quem está INTEIRO nas lojas em que ele vê
-- o Extrato. O dia é o do fuso da conta (buscado uma vez).
CREATE OR REPLACE FUNCTION public.extrato_pontos_gerente(p_funcionarioid integer, p_de date, p_ate date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.conta_do_gerente();
  v_fuso    text;
  v_nome    text; v_saldo integer; v_inicial integer; v_periodo integer; v_soma integer; v_mov jsonb;
BEGIN
  IF v_conta IS NULL OR NOT coalesce(public.pode_na_pessoa('extrato.ver', v_conta, p_funcionarioid), false) THEN
    RETURN NULL;
  END IF;
  v_fuso := public.fuso_da_conta(v_conta);
  SELECT nomecompleto, saldopontos INTO v_nome, v_saldo
    FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT coalesce(sum(pontos), 0) INTO v_inicial FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND public.dia_no_fuso(datamovimento, v_fuso) < p_de;
  SELECT coalesce(sum(pontos), 0) INTO v_periodo FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND public.dia_no_fuso(datamovimento, v_fuso) BETWEEN p_de AND p_ate;
  SELECT coalesce(sum(pontos), 0) INTO v_soma FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid;
  WITH todos AS (
    SELECT m.*, sum(m.pontos) OVER (ORDER BY m.datamovimento, m.movimentoid) AS saldoapos
      FROM public.movimentospontos m
     WHERE m.contaid = v_conta AND m.funcionarioid = p_funcionarioid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'data', t.datamovimento, 'tipo', t.tipo, 'descricao', t.descricao,
           'loja', l.nome, 'pontos', t.pontos, 'saldoapos', t.saldoapos)
           ORDER BY t.datamovimento, t.movimentoid), '[]'::jsonb)
    INTO v_mov
    FROM todos t
    LEFT JOIN public.lojas l ON l.lojaid = t.lojaid AND l.contaid = v_conta
   WHERE public.dia_no_fuso(t.datamovimento, v_fuso) BETWEEN p_de AND p_ate;
  RETURN jsonb_build_object('nome', v_nome, 'saldoatual', v_saldo, 'saldoinicial', v_inicial,
                            'saldofinal', v_inicial + v_periodo, 'confere', v_soma = v_saldo,
                            'taxa', public.minha_taxa_gerente(), 'movimentos', v_mov);
END;
$$;
REVOKE ALL ON FUNCTION public.extrato_pontos_gerente(integer, date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.extrato_pontos_gerente(integer, date, date) TO authenticated;

-- extrato_pontos: parte da versão viva (de 20260921140000_loja_resgates_extrato.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.extrato_pontos(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_nome     text;
  v_conta    integer;
  v_saldo    integer;
  v_inicial  integer;
  v_periodo  integer;
  v_soma     integer;
  v_mov      jsonb;
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.extrato_pontos_gerente(p_funcionarioid, p_de, p_ate);
  END IF;
  SELECT nomecompleto, contaid, saldopontos INTO v_nome, v_conta, v_saldo
    FROM public.funcionarios WHERE funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT coalesce(sum(pontos), 0) INTO v_inicial FROM public.movimentospontos
   WHERE funcionarioid = p_funcionarioid AND public.dia_em_sao_paulo(datamovimento) < p_de;

  SELECT coalesce(sum(pontos), 0) INTO v_periodo FROM public.movimentospontos
   WHERE funcionarioid = p_funcionarioid AND public.dia_em_sao_paulo(datamovimento) BETWEEN p_de AND p_ate;

  SELECT coalesce(sum(pontos), 0) INTO v_soma FROM public.movimentospontos
   WHERE funcionarioid = p_funcionarioid;

  WITH todos AS (
    SELECT m.*, sum(m.pontos) OVER (ORDER BY m.datamovimento, m.movimentoid) AS saldoapos
      FROM public.movimentospontos m
     WHERE m.funcionarioid = p_funcionarioid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'data', t.datamovimento, 'tipo', t.tipo, 'descricao', t.descricao,
           'loja', l.nome, 'pontos', t.pontos, 'saldoapos', t.saldoapos)
           ORDER BY t.datamovimento, t.movimentoid), '[]'::jsonb)
    INTO v_mov
    FROM todos t
    LEFT JOIN public.lojas l ON l.lojaid = t.lojaid
   WHERE public.dia_em_sao_paulo(t.datamovimento) BETWEEN p_de AND p_ate;

  RETURN jsonb_build_object(
    'nome',         v_nome,
    'saldoatual',   v_saldo,
    'saldoinicial', v_inicial,
    'saldofinal',   v_inicial + v_periodo,
    'confere',      v_soma = v_saldo,
    'taxa',         public.minha_taxa(),
    'movimentos',   v_mov
  );
END;
$function$;

-- O ranking de pontos do gerente: só as lojas em que ele vê o Ranking (a
-- pedida, se for dele; "todas" = todas as dele). O dia no fuso da conta.
CREATE OR REPLACE FUNCTION public.ranking_pontos_gerente(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta,
           (SELECT public.lojas_onde_posso('ranking.ver'))::integer[] AS lojas,
           (p_de::timestamp AT TIME ZONE public.fuso_da_conta(public.conta_do_gerente())) AS ini,
           ((p_ate + 1)::timestamp AT TIME ZONE public.fuso_da_conta(public.conta_do_gerente())) AS fim
  )
  SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
    FROM ctx
    JOIN public.entregas e      ON e.contaid = ctx.conta
    JOIN public.funcionarios f  ON f.funcionarioid = e.funcionarioid AND f.contaid = ctx.conta
   WHERE e.statusvalidacao = 'Aprovada'
     AND e.dataaprovacao >= ctx.ini AND e.dataaprovacao < ctx.fim
     AND e.lojaid = ANY (ctx.lojas)
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
   GROUP BY f.funcionarioid, f.nomecompleto
   ORDER BY 3 DESC, 2, 1
$function$;
REVOKE ALL ON FUNCTION public.ranking_pontos_gerente(date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ranking_pontos_gerente(date, date, integer) TO authenticated;

-- ranking_pontos: parte da versão viva (de 20260929275000_fila_nao_cresce_com_os_dias.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.ranking_pontos(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.ranking_pontos_gerente(p_de, p_ate, p_lojaid);
    RETURN;
  END IF;
  RETURN QUERY
SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
  FROM public.entregas e
  JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
  WHERE e.statusvalidacao = 'Aprovada'
    AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN p_de AND p_ate
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((p_de)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((p_ate)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
    AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  GROUP BY f.funcionarioid, f.nomecompleto
  ORDER BY 3 DESC, 2, 1;
END;
$function$;

-- A nota do mês do gerente: só por loja em que ele vê o Ranking. Mês fechado:
-- o que foi congelado para aquela loja; aberto: ao vivo, até ontem.
CREATE OR REPLACE FUNCTION public.ranking_mensal_gerente(p_ano integer, p_mes integer, p_lojaid integer)
RETURNS TABLE (funcionarioid integer, nomecompleto varchar, pontosganhos integer, pontosregulares integer,
               pontospossiveis integer, confiabilidade numeric, esforco numeric, nota numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
  v_conta integer := public.conta_do_gerente();
  v_fech  integer;
BEGIN
  IF v_conta IS NULL OR p_lojaid IS NULL OR NOT public.pode('ranking.ver', p_lojaid) THEN
    RETURN;
  END IF;
  SELECT f.fechamentoid INTO v_fech FROM public.fechamentosmensais f
   WHERE f.contaid = v_conta AND f.ano = p_ano AND f.mes = p_mes AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC LIMIT 1;
  IF v_fech IS NOT NULL THEN
    RETURN QUERY
      SELECT h.funcionarioid, h.nomefuncionario, h.pontosganhos,
             coalesce(h.pontosregulares, 0), h.pontospossiveis,
             coalesce(h.confiabilidade, 0), coalesce(h.esforco, 0), coalesce(h.nota, 0)
        FROM public.historicoranking h
       WHERE h.contaid = v_conta AND h.fechamentoid = v_fech AND h.lojaid = p_lojaid
       ORDER BY h.posicao, h.historicoid;
  ELSE
    RETURN QUERY
      SELECT * FROM public.ranking_mensal_da_conta(v_conta, p_ano, p_mes, p_lojaid, public.hoje_da_conta(v_conta) - 1);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ranking_mensal_gerente(integer, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ranking_mensal_gerente(integer, integer, integer) TO authenticated;

-- ranking_mensal: parte da versão viva (de 20260928100300_ranking_le_o_fechamento.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.ranking_mensal(p_ano integer, p_mes integer, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontosganhos integer, pontosregulares integer, pontospossiveis integer, confiabilidade numeric, esforco numeric, nota numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fechamento integer := public.fechamento_valendo(p_ano, p_mes);
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.ranking_mensal_gerente(p_ano, p_mes, p_lojaid);
    RETURN;
  END IF;
  IF v_fechamento IS NOT NULL THEN
    -- Mês fechado: os números estão congelados. É a mesma fonte da tela
    -- "Meses fechados", então as duas nunca discordam.
    RETURN QUERY
      SELECT h.funcionarioid, h.nomefuncionario, h.pontosganhos,
             coalesce(h.pontosregulares, 0), h.pontospossiveis,
             coalesce(h.confiabilidade, 0), coalesce(h.esforco, 0), coalesce(h.nota, 0)
        FROM public.historicoranking h
       WHERE h.fechamentoid = v_fechamento
         AND h.lojaid IS NOT DISTINCT FROM p_lojaid
       ORDER BY h.posicao;
  ELSE
    -- Mês aberto: ao vivo, até ontem.
    RETURN QUERY
      SELECT * FROM public.ranking_mensal_da_conta(public.minha_conta(), p_ano, p_mes, p_lojaid,
                                                   public.dia_em_sao_paulo(now()) - 1);
  END IF;
END;
$function$;

-- Qual fechamento vale no mês: para o gerente que vê o Ranking em alguma loja.
CREATE OR REPLACE FUNCTION public.fechamento_valendo_gerente(p_ano integer, p_mes integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.fechamentoid
    FROM public.fechamentosmensais f
   WHERE f.contaid = public.conta_do_gerente()
     AND cardinality((SELECT public.lojas_onde_posso('ranking.ver'))::integer[]) > 0
     AND f.ano = p_ano AND f.mes = p_mes
     AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC
   LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.fechamento_valendo_gerente(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fechamento_valendo_gerente(integer, integer) TO authenticated;

-- fechamento_valendo: parte da versão viva (de 20260928100300_ranking_le_o_fechamento.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.fechamento_valendo(p_ano integer, p_mes integer)
 RETURNS integer

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fechamento_valendo_gerente(p_ano, p_mes);
  END IF;
  RETURN (
SELECT f.fechamentoid
    FROM public.fechamentosmensais f
   WHERE f.contaid = (select public.minha_conta())
     AND f.ano = p_ano AND f.mes = p_mes
     AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC
   LIMIT 1
  );
END;
$function$;

-- Meses fechados (a tela lia as tabelas direto). O master: os mesmos de
-- sempre. O gerente: a lista dos meses (se vê o Ranking em alguma loja) e o
-- ranking congelado só das lojas dele (nunca o da conta inteira).
CREATE OR REPLACE FUNCTION public.meses_fechados()
RETURNS TABLE(fechamentoid integer, ano integer, mes integer, versao integer, situacao character varying,
              origem character varying, motivo text, fechadoem timestamptz, definitivoem timestamptz, substituidoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.fechamentoid, f.ano, f.mes, f.versao, f.situacao, f.origem, f.motivo, f.fechadoem, f.definitivoem, f.substituidoem
    FROM public.fechamentosmensais f
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('ranking.ver'))::integer[]) > 0)
   ORDER BY f.ano DESC, f.mes DESC, f.versao DESC, f.fechamentoid DESC
$$;
REVOKE ALL ON FUNCTION public.meses_fechados() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.meses_fechados() TO authenticated;

CREATE OR REPLACE FUNCTION public.ranking_do_fechamento(p_fechamentoid integer, p_lojaid integer)
RETURNS TABLE(historicoid integer, posicao integer, nomefuncionario character varying, nota numeric,
              confiabilidade numeric, esforco numeric, pontosganhos integer, pontospossiveis integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.posicao, h.nomefuncionario, h.nota, h.confiabilidade, h.esforco, h.pontosganhos, h.pontospossiveis
    FROM public.historicoranking h
   WHERE h.fechamentoid = p_fechamentoid
     AND ((public.sou_master() AND h.contaid = public.minha_conta() AND h.lojaid IS NOT DISTINCT FROM p_lojaid)
       OR (NOT public.sou_master() AND h.contaid = public.conta_do_gerente()
           AND p_lojaid IS NOT NULL AND h.lojaid = p_lojaid AND public.pode('ranking.ver', p_lojaid)))
   ORDER BY h.posicao, h.historicoid
$$;
REVOKE ALL ON FUNCTION public.ranking_do_fechamento(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ranking_do_fechamento(integer, integer) TO authenticated;

-- ------------------------------------------------------------------------
-- 20260929277000_leituras_feedbacks_justificativas_solicitacoes.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 3: Feedbacks, Justificativas e
-- Solicitações (30/09/2026). As telas liam as tabelas direto e vinham vazias
-- para o gerente. Agora cada uma lê por uma função:
--   * o master recebe o mesmo de antes (a conta dele, na mesma ordem);
--   * o gerente: feedbacks de quem tem UMA loja em comum com ele onde ele vê
--     Feedbacks (é dia a dia, decisão 4); justificativas e solicitações pela
--     LOJA delas (onde ele vê a tela);
--   * qualquer outro login: nada.
-- Nenhum dado é alterado. Classificação: ACRESCENTA.

-- As pessoas de UMA loja (formulários de uma tela).
CREATE OR REPLACE FUNCTION public.pessoas_da_loja(p_lojaid integer, p_codigo text)
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, f.ativo
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.contaid = f.contaid
                                    AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente() AND public.pode(p_codigo, p_lojaid))
   ORDER BY f.nomecompleto, f.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.pessoas_da_loja(integer, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pessoas_da_loja(integer, text) TO authenticated;

-- Feedbacks de um período.
CREATE OR REPLACE FUNCTION public.feedbacks_do_periodo(p_de date, p_ate date, p_funcionarioid integer DEFAULT NULL)
RETURNS TABLE(feedbackid integer, funcionarioid integer, datafeedback date, notadia integer, comentario character varying,
              origem character varying, pontosbonus integer, anuladoem timestamptz, motivoanulacao text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fb.feedbackid, fb.funcionarioid, fb.datafeedback, fb.notadia, fb.comentario, fb.origem, fb.pontosbonus,
         fb.anuladoem, fb.motivoanulacao
    FROM public.feedbacks fb
   WHERE fb.datafeedback BETWEEN p_de AND p_ate
     AND (p_funcionarioid IS NULL OR fb.funcionarioid = p_funcionarioid)
     AND ((public.sou_master() AND fb.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND fb.contaid = public.conta_do_gerente()
           AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                        WHERE fl.contaid = fb.contaid AND fl.funcionarioid = fb.funcionarioid AND fl.ativo
                          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('feedbacks.ver'))::integer[]))))
   ORDER BY fb.datafeedback DESC, fb.feedbackid DESC
   LIMIT 500
$$;
REVOKE ALL ON FUNCTION public.feedbacks_do_periodo(date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.feedbacks_do_periodo(date, date, integer) TO authenticated;

-- As justificativas da tela, já com o nome da pessoa, da tarefa e da loja.
CREATE OR REPLACE FUNCTION public.justificativas_da_tela()
RETURNS TABLE(justificativaid integer, atribuicaoid integer, funcionarioid integer, lojaid integer, dia date,
              motivo text, status character varying, origem character varying, motivorecusa text,
              pessoa character varying, tarefa character varying, loja character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT j.justificativaid, j.atribuicaoid, j.funcionarioid, j.lojaid, j.dia, j.motivo, j.status, j.origem, j.motivorecusa,
         f.nomecompleto, t.titulo, l.nome
    FROM public.justificativas j
    LEFT JOIN public.funcionarios f       ON f.funcionarioid = j.funcionarioid AND f.contaid = j.contaid
    LEFT JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid AND ta.contaid = j.contaid
    LEFT JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = j.contaid
    LEFT JOIN public.lojas l              ON l.lojaid = j.lojaid AND l.contaid = j.contaid
   WHERE (public.sou_master() AND j.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente()
          AND j.lojaid = ANY ((SELECT public.lojas_onde_posso('justificativas.ver'))::integer[]))
   ORDER BY j.dia DESC, j.justificativaid DESC
   LIMIT 300
$$;
REVOKE ALL ON FUNCTION public.justificativas_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.justificativas_da_tela() TO authenticated;

-- As solicitações de uma loja, com o nome de quem pediu.
CREATE OR REPLACE FUNCTION public.solicitacoes_da_loja(p_lojaid integer)
RETURNS TABLE(solicitacaoid integer, tipo character varying, categoria character varying, descricao text, quantidade numeric,
              unidade character varying, status character varying, motivorecusa text, datasolicitacao timestamptz,
              funcionarioid integer, observacao text, nomecompleto character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.solicitacaoid, s.tipo, s.categoria, s.descricao, s.quantidade, s.unidade, s.status, s.motivorecusa,
         s.datasolicitacao, s.funcionarioid, s.observacao, f.nomecompleto
    FROM public.solicitacoesinternas s
    LEFT JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = s.contaid
   WHERE s.lojaid = p_lojaid
     AND ((public.sou_master() AND s.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente() AND public.pode('solicitacoes.ver', p_lojaid)))
   ORDER BY s.datasolicitacao DESC, s.solicitacaoid DESC
   LIMIT 300
$$;
REVOKE ALL ON FUNCTION public.solicitacoes_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.solicitacoes_da_loja(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.historico_das_solicitacoes(p_lojaid integer)
RETURNS TABLE(historicoid integer, solicitacaoid integer, statusanterior character varying, statusnovo character varying,
              observacao text, alteradoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.solicitacaoid, h.statusanterior, h.statusnovo, h.observacao, h.alteradoem
    FROM public.solicitacoeshistorico h
   WHERE h.lojaid = p_lojaid
     AND ((public.sou_master() AND h.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND h.contaid = public.conta_do_gerente() AND public.pode('solicitacoes.ver', p_lojaid)))
   ORDER BY h.historicoid
$$;
REVOKE ALL ON FUNCTION public.historico_das_solicitacoes(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_das_solicitacoes(integer) TO authenticated;

-- O que dá para justificar, para o gerente: só tarefas das lojas em que ele
-- registra justificativa. O dia é o do fuso da conta (buscado uma vez).
CREATE OR REPLACE FUNCTION public.justificaveis_gerente(p_funcionarioid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- O fuso, o dia de hoje e as lojas dele saem UMA vez.
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta,
           public.fuso_da_conta(public.conta_do_gerente()) AS fuso,
           public.hoje_da_conta(public.conta_do_gerente()) AS hoje,
           (SELECT public.lojas_onde_posso('justificativas.registrar'))::integer[] AS lojas
  ),
  pessoa AS (
    SELECT f.contaid, f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento
      FROM public.funcionarios f, ctx WHERE f.funcionarioid = p_funcionarioid AND f.contaid = ctx.conta
  ),
  congelado AS (
    SELECT p_dia < ctx.hoje
           AND EXISTS (SELECT 1 FROM public.diasgerados dg, pessoa
                        WHERE dg.contaid = pessoa.contaid AND dg.dia = p_dia) AS sim
      FROM ctx
  ),
  itens AS (
    -- Dia com lista congelada.
    SELECT i.atribuicaoid, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN pessoa ON pessoa.contaid = i.contaid
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid AND t.contaid = i.contaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid AND l.contaid = i.contaid
      CROSS JOIN congelado
      CROSS JOIN ctx
     WHERE congelado.sim
       AND i.lojaid = ANY (ctx.lojas)
       AND i.funcionarioid = p_funcionarioid AND i.dia = p_dia AND i.situacao = 'devida'
       AND NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, p_dia, false)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid AND e.contaid = ctx.conta
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_no_fuso(e.dataenvio, ctx.fuso) = p_dia))
    UNION ALL
    -- Hoje, ou dia sem lista: regra do cadastro.
    SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid AND t.contaid = ta.contaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid AND l.contaid = ta.contaid
      CROSS JOIN pessoa
      CROSS JOIN congelado
      CROSS JOIN ctx
     WHERE NOT congelado.sim
       AND ta.contaid = ctx.conta
       AND ta.lojaid = ANY (ctx.lojas)
       AND ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND p_dia <= ctx.hoje
       AND public.dia_de_trabalho(pessoa.diadefolga, pessoa.domingofolgamensal,
                                  pessoa.datainicioafastamento, pessoa.datafimafastamento, p_dia)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, p_dia, false)
       AND (
         (ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
          AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, p_dia)
          AND p_dia >= coalesce(public.dia_no_fuso(ta.dataatribuicao, ctx.fuso), p_dia)
          AND p_dia >= coalesce(ta.datainiciovigencia, p_dia)
          AND (ta.datafimvigencia IS NULL OR p_dia < ta.datafimvigencia)
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid AND e.contaid = ctx.conta
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                             AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = p_dia))
         OR
         (ta.tipofrequencia = 'Unica'
          AND ta.datafimvigencia IS NULL
          AND public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ctx.fuso) = p_dia
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid AND e.contaid = ctx.conta
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')))
       )
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('atribuicaoid', atribuicaoid, 'titulo', titulo,
                                               'pontos', pontos, 'loja', loja) ORDER BY titulo), '[]'::jsonb)
    FROM itens
$function$;
REVOKE ALL ON FUNCTION public.justificaveis_gerente(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.justificaveis_gerente(integer, date) TO authenticated;

-- justificaveis: parte da versão viva (de 20260924100000_rotinas_lista_do_dia.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.justificaveis(p_funcionarioid integer, p_dia date)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.justificaveis_gerente(p_funcionarioid, p_dia);
  END IF;
  RETURN (
  WITH pessoa AS (
    SELECT f.contaid, f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento
      FROM public.funcionarios f WHERE f.funcionarioid = p_funcionarioid
  ),
  congelado AS (
    SELECT p_dia < public.dia_em_sao_paulo(now())
           AND EXISTS (SELECT 1 FROM public.diasgerados dg, pessoa
                        WHERE dg.contaid = pessoa.contaid AND dg.dia = p_dia) AS sim
  ),
  itens AS (
    -- Dia com lista congelada.
    SELECT i.atribuicaoid, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN pessoa ON pessoa.contaid = i.contaid
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid
      CROSS JOIN congelado
     WHERE congelado.sim
       AND i.funcionarioid = p_funcionarioid AND i.dia = p_dia AND i.situacao = 'devida'
       AND NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, p_dia, false)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = p_dia))
    UNION ALL
    -- Hoje, ou dia sem lista: regra do cadastro.
    SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN pessoa
      CROSS JOIN congelado
     WHERE NOT congelado.sim
       AND ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND p_dia <= public.dia_em_sao_paulo(now())
       AND public.dia_de_trabalho(pessoa.diadefolga, pessoa.domingofolgamensal,
                                  pessoa.datainicioafastamento, pessoa.datafimafastamento, p_dia)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, p_dia, false)
       AND (
         (ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
          AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, p_dia)
          AND p_dia >= coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), p_dia)
          AND p_dia >= coalesce(ta.datainiciovigencia, p_dia)
          AND (ta.datafimvigencia IS NULL OR p_dia < ta.datafimvigencia)
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                             AND public.dia_em_sao_paulo(e.dataenvio) = p_dia))
         OR
         (ta.tipofrequencia = 'Unica'
          AND ta.datafimvigencia IS NULL
          AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) = p_dia
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')))
       )
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('atribuicaoid', atribuicaoid, 'titulo', titulo,
                                               'pontos', pontos, 'loja', loja) ORDER BY titulo), '[]'::jsonb)
    FROM itens
  );
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929278000_leituras_tarefas_metas.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 4: Tarefas e Metas (30/09/2026).
--
--   * Tarefas ("Tarefas: ver"): o catálogo mostra só tarefas que valem em
--     alguma loja dele, e a lista de lojas de cada uma vem cortada nas dele
--     (tarefa sem loja: só o master). Atribuições, tarefas e pessoas da
--     loja: só nas lojas em que ele vê Tarefas. O teto de pontos por ciência
--     (aparece ao editar a tarefa de rotina) também chega a ele.
--   * Metas: a meta da semana e as especiais são em R$: só com "Metas: ver"
--     E "Ver valores em R$" na loja. O histórico das vendas continua só do
--     master (é a conferência dele, decisão 5).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- As tarefas que valem numa loja (para atribuir e filtrar).
CREATE OR REPLACE FUNCTION public.tarefas_da_loja(p_lojaid integer)
RETURNS TABLE(tarefaid integer, titulo character varying, pontos integer, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.tarefaid, t.titulo, t.pontos, coalesce(t.ativa, true)
    FROM public.tarefaslojas tl
    JOIN public.tarefas t ON t.tarefaid = tl.tarefaid AND t.contaid = tl.contaid
   WHERE tl.lojaid = p_lojaid AND tl.ativo
     AND ((public.sou_master() AND tl.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND tl.contaid = public.conta_do_gerente() AND public.pode('tarefas.ver', p_lojaid)))
   ORDER BY t.titulo, t.tarefaid
$$;
REVOKE ALL ON FUNCTION public.tarefas_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tarefas_da_loja(integer) TO authenticated;

-- O teto de pontos por ciência da conta.
CREATE OR REPLACE FUNCTION public.teto_de_pontos_por_ciencia()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN c.valor ~ '^\s*[0-9]+\s*$' THEN btrim(c.valor)::integer END
    FROM public.configuracoes c
   WHERE c.chave = 'MAX_PONTOS_CIENCIA'
     AND ((public.sou_master() AND c.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
           AND cardinality((SELECT public.lojas_onde_posso('tarefas.ver'))::integer[]) > 0))
$$;
REVOKE ALL ON FUNCTION public.teto_de_pontos_por_ciencia() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.teto_de_pontos_por_ciencia() TO authenticated;

-- A meta de cada dia da semana de uma loja (R$).
CREATE OR REPLACE FUNCTION public.metas_da_semana(p_lojaid integer)
RETURNS TABLE(diasemanaid integer, valormeta numeric, pontospremio integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT m.diasemanaid, m.valormeta, m.pontospremio
    FROM public.metasdiariasmodelos m
   WHERE m.lojaid = p_lojaid
     AND ((public.sou_master() AND m.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND m.contaid = public.conta_do_gerente()
           AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)))
   ORDER BY m.diasemanaid
$$;
REVOKE ALL ON FUNCTION public.metas_da_semana(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_da_semana(integer) TO authenticated;

-- As metas especiais de uma loja (R$).
CREATE OR REPLACE FUNCTION public.metas_especiais_da_loja(p_lojaid integer)
RETURNS TABLE(metaespecialid integer, data date, descricao text, valormeta numeric, pontospremio integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT m.metaespecialid, m.data, m.descricao, m.valormeta, m.pontospremio
    FROM public.metasespeciais m
   WHERE m.lojaid = p_lojaid
     AND ((public.sou_master() AND m.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND m.contaid = public.conta_do_gerente()
           AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)))
   ORDER BY m.data DESC, m.metaespecialid DESC
   LIMIT 100
$$;
REVOKE ALL ON FUNCTION public.metas_especiais_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_especiais_da_loja(integer) TO authenticated;

-- O catálogo de tarefas do gerente.
CREATE OR REPLACE FUNCTION public.catalogo_de_tarefas_gerente(p_lojaid integer DEFAULT NULL::integer, p_inativas boolean DEFAULT false, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, (SELECT public.lojas_onde_posso('tarefas.ver'))::integer[] AS lojas
  ),
  escolhidas AS (
    SELECT t.tarefaid, t.titulo, t.descricao, t.pontos, t.setor, t.ativa, t.sistema, t.datacriacao
      FROM public.tarefas t, ctx
     WHERE t.contaid = ctx.conta
       AND (p_lojaid IS NULL OR p_lojaid = ANY (ctx.lojas))
       -- Só a tarefa que vale em alguma loja dele.
       AND EXISTS (SELECT 1 FROM public.tarefaslojas tl
                    WHERE tl.contaid = ctx.conta AND tl.tarefaid = t.tarefaid AND tl.ativo AND tl.lojaid = ANY (ctx.lojas))
       AND (coalesce(p_inativas, false) OR coalesce(t.ativa, true))
       -- "O nome contém o texto", sem diferenciar maiúscula. Sem LIKE: o que
       -- a pessoa digita é texto, nunca coringa.
       AND (nullif(btrim(coalesce(p_busca, '')), '') IS NULL
            OR strpos(lower(t.titulo), lower(btrim(p_busca))) > 0)
       AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.tarefaslojas tl
                                         WHERE tl.contaid = ctx.conta AND tl.tarefaid = t.tarefaid
                                           AND tl.lojaid = p_lojaid AND tl.ativo))
     ORDER BY t.datacriacao DESC NULLS LAST, t.tarefaid DESC
     OFFSET greatest(coalesce(p_offset, 0), 0)
     LIMIT least(greatest(coalesce(p_limite, 5), 1), 50) + 1
  ),
  numeradas AS (SELECT e.*, row_number() OVER (ORDER BY e.datacriacao DESC NULLS LAST, e.tarefaid DESC) AS n FROM escolhidas e)
  SELECT jsonb_build_object(
    'tarefas', coalesce((SELECT jsonb_agg(jsonb_build_object(
                 'tarefaid', x.tarefaid, 'titulo', x.titulo, 'descricao', x.descricao, 'pontos', x.pontos,
                 'setor', x.setor, 'ativa', x.ativa, 'sistema', x.sistema,
                 -- As lojas da tarefa, cortadas nas dele.
                 'lojas', coalesce((SELECT jsonb_agg(tl.lojaid ORDER BY tl.lojaid) FROM public.tarefaslojas tl, ctx
                                     WHERE tl.contaid = ctx.conta AND tl.tarefaid = x.tarefaid AND tl.ativo
                                       AND tl.lojaid = ANY (ctx.lojas)), '[]'::jsonb))
                 ORDER BY x.n)
                 FROM numeradas x WHERE x.n <= least(greatest(coalesce(p_limite, 5), 1), 50)), '[]'::jsonb),
    'temmais', (SELECT count(*) FROM numeradas) > least(greatest(coalesce(p_limite, 5), 1), 50))
$function$;
REVOKE ALL ON FUNCTION public.catalogo_de_tarefas_gerente(integer, boolean, text, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.catalogo_de_tarefas_gerente(integer, boolean, text, integer, integer) TO authenticated;

-- catalogo_de_tarefas: parte da versão viva (de 20260929236000_contadores_do_menu.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.catalogo_de_tarefas(p_lojaid integer DEFAULT NULL::integer, p_inativas boolean DEFAULT false, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.catalogo_de_tarefas_gerente(p_lojaid, p_inativas, p_busca, p_limite, p_offset);
  END IF;
  RETURN (
  WITH escolhidas AS (
    SELECT t.tarefaid, t.titulo, t.descricao, t.pontos, t.setor, t.ativa, t.sistema, t.datacriacao
      FROM public.tarefas t
     WHERE (coalesce(p_inativas, false) OR coalesce(t.ativa, true))
       -- "O nome contém o texto", sem diferenciar maiúscula. Sem LIKE: o que
       -- a pessoa digita é texto, nunca coringa.
       AND (nullif(btrim(coalesce(p_busca, '')), '') IS NULL
            OR strpos(lower(t.titulo), lower(btrim(p_busca))) > 0)
       AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.tarefaslojas tl
                                         WHERE tl.tarefaid = t.tarefaid AND tl.lojaid = p_lojaid AND tl.ativo))
     ORDER BY t.datacriacao DESC NULLS LAST, t.tarefaid DESC
     OFFSET greatest(coalesce(p_offset, 0), 0)
     LIMIT least(greatest(coalesce(p_limite, 5), 1), 50) + 1
  ),
  numeradas AS (SELECT e.*, row_number() OVER (ORDER BY e.datacriacao DESC NULLS LAST, e.tarefaid DESC) AS n FROM escolhidas e)
  SELECT jsonb_build_object(
    'tarefas', coalesce((SELECT jsonb_agg(jsonb_build_object(
                 'tarefaid', x.tarefaid, 'titulo', x.titulo, 'descricao', x.descricao, 'pontos', x.pontos,
                 'setor', x.setor, 'ativa', x.ativa, 'sistema', x.sistema,
                 'lojas', coalesce((SELECT jsonb_agg(tl.lojaid ORDER BY tl.lojaid) FROM public.tarefaslojas tl
                                     WHERE tl.tarefaid = x.tarefaid AND tl.ativo), '[]'::jsonb))
                 ORDER BY x.n)
                 FROM numeradas x WHERE x.n <= least(greatest(coalesce(p_limite, 5), 1), 50)), '[]'::jsonb),
    'temmais', (SELECT count(*) FROM numeradas) > least(greatest(coalesce(p_limite, 5), 1), 50))
  );
END;
$function$;

-- As atribuições de uma loja, para o gerente que vê Tarefas nela.
CREATE OR REPLACE FUNCTION public.atribuicoes_da_loja_gerente(p_lojaid integer, p_encerradas boolean DEFAULT false, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_tarefaid integer DEFAULT NULL::integer, p_funcionarioid integer DEFAULT NULL::integer, p_missao boolean DEFAULT false, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gerente();
  v_fuso   text := public.fuso_da_conta(public.conta_do_gerente());
  v_limite integer := least(greatest(coalesce(p_limite, 5), 1), 50);
  v_linhas jsonb;
  v_n      integer;
BEGIN
  IF v_conta IS NULL OR NOT public.pode('tarefas.ver', p_lojaid) THEN
    RETURN jsonb_build_object('linhas', '[]'::jsonb, 'temmais', false);
  END IF;
  IF (p_de IS NULL) <> (p_ate IS NULL) THEN
    RAISE EXCEPTION 'Escolha a data inicial e a final (ou nenhuma das duas).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_de > p_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_ate - p_de > 365 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 366 dias.' USING ERRCODE = 'check_violation';
  END IF;

  WITH filtradas AS (
    SELECT ta.*
      FROM public.tarefasatribuidas ta
     WHERE ta.contaid = v_conta AND ta.lojaid = p_lojaid
       AND (p_encerradas OR ta.datafimvigencia IS NULL)
       AND (p_tarefaid IS NULL OR ta.tarefaid = p_tarefaid)
       AND (NOT coalesce(p_missao, false) OR (ta.funcionarioid IS NULL AND NOT ta.compartilhada))
       AND (p_funcionarioid IS NULL
            OR ta.funcionarioid = p_funcionarioid
            OR (ta.compartilhada AND EXISTS (SELECT 1 FROM public.tarefascandidatos tc
                                              WHERE tc.atribuicaoid = ta.atribuicaoid
                                                AND tc.funcionarioid = p_funcionarioid)))
       AND (p_de IS NULL OR (ta.dataatribuicao >= (p_de::timestamp AT TIME ZONE v_fuso)
                             AND ta.dataatribuicao < ((p_ate + 1)::timestamp AT TIME ZONE v_fuso)))
  ),
  grupos AS (
    SELECT f.tarefaid,
           f.funcionarioid,
           f.tipofrequencia,
           f.datafimvigencia,
           array_agg(f.atribuicaoid ORDER BY f.atribuicaoid) AS ids,
           array_agg(f.valorfrequencia ORDER BY f.valorfrequencia) FILTER (WHERE f.valorfrequencia IS NOT NULL) AS dias,
           min(f.valorfrequencia) AS valor,
           min(f.dataagendamento) AS dataagendamento,
           min(f.disponivelapartir) AS disponivelapartir,
           bool_or(f.compartilhada) AS compartilhada,
           min(f.horariodisparo) AS horariodisparo,
           max(f.dataatribuicao) AS criadaem,
           max(f.atribuicaoid) AS ultimo
      FROM filtradas f
     GROUP BY f.tarefaid, coalesce(f.funcionarioid::text, 'c' || f.atribuicaoid), f.funcionarioid,
              f.tipofrequencia, f.datafimvigencia
  ),
  pagina AS (
    SELECT g.* FROM grupos g
     ORDER BY g.criadaem DESC NULLS LAST, g.ultimo DESC
     OFFSET greatest(coalesce(p_offset, 0), 0) LIMIT v_limite + 1
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ids', to_jsonb(p.ids),
           'tarefaid', p.tarefaid,
           'titulo', t.titulo,
           'funcionarioid', p.funcionarioid,
           'nome', fu.nomecompleto,
           'compartilhada', p.compartilhada,
           'candidatos', CASE WHEN p.compartilhada THEN
                           (SELECT coalesce(jsonb_agg(fc.nomecompleto ORDER BY fc.nomecompleto), '[]'::jsonb)
                              FROM public.tarefascandidatos tc
                              JOIN public.funcionarios fc ON fc.funcionarioid = tc.funcionarioid AND fc.contaid = v_conta
                             WHERE tc.atribuicaoid = p.ids[1]) END,
           'horariodisparo', p.horariodisparo,
           'tipofrequencia', p.tipofrequencia,
           'dias', coalesce(to_jsonb(p.dias), '[]'::jsonb),
           'valor', p.valor,
           'dataagendamento', p.dataagendamento,
           'disponivelapartir', p.disponivelapartir,
           'datafimvigencia', p.datafimvigencia,
           'criadaem', p.criadaem,
           -- O dia da criação já no fuso da conta, escrito dd/mm/aaaa.
           'criadaemdia', to_char(p.criadaem AT TIME ZONE v_fuso, 'DD/MM/YYYY'))
         ORDER BY p.criadaem DESC NULLS LAST, p.ultimo DESC),
         count(*)
    INTO v_linhas, v_n
    FROM pagina p
    LEFT JOIN public.tarefas t ON t.tarefaid = p.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios fu ON fu.funcionarioid = p.funcionarioid AND fu.contaid = v_conta;

  -- Veio uma a mais do que o limite: há mais para carregar.
  IF v_n > v_limite THEN
    v_linhas := v_linhas - v_limite;
  END IF;
  RETURN jsonb_build_object('linhas', coalesce(v_linhas, '[]'::jsonb), 'temmais', v_n > v_limite);
END;
$function$;

REVOKE ALL ON FUNCTION public.atribuicoes_da_loja_gerente(integer, boolean, date, date, integer, integer, boolean, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.atribuicoes_da_loja_gerente(integer, boolean, date, date, integer, integer, boolean, integer, integer) TO authenticated;

-- atribuicoes_da_loja: parte da versão viva (de 20260929220000_tarefas_comuns_e_atribuicoes.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.atribuicoes_da_loja(p_lojaid integer, p_encerradas boolean DEFAULT false, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_tarefaid integer DEFAULT NULL::integer, p_funcionarioid integer DEFAULT NULL::integer, p_missao boolean DEFAULT false, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fuso   text := public.meu_hoje()->>'fuso';
  v_limite integer := least(greatest(coalesce(p_limite, 5), 1), 50);
  v_linhas jsonb;
  v_n      integer;
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.atribuicoes_da_loja_gerente(p_lojaid, p_encerradas, p_de, p_ate, p_tarefaid, p_funcionarioid, p_missao, p_limite, p_offset);
  END IF;
  IF (p_de IS NULL) <> (p_ate IS NULL) THEN
    RAISE EXCEPTION 'Escolha a data inicial e a final (ou nenhuma das duas).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_de > p_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_ate - p_de > 365 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 366 dias.' USING ERRCODE = 'check_violation';
  END IF;

  WITH filtradas AS (
    SELECT ta.*
      FROM public.tarefasatribuidas ta
     WHERE ta.lojaid = p_lojaid
       AND (p_encerradas OR ta.datafimvigencia IS NULL)
       AND (p_tarefaid IS NULL OR ta.tarefaid = p_tarefaid)
       AND (NOT coalesce(p_missao, false) OR (ta.funcionarioid IS NULL AND NOT ta.compartilhada))
       AND (p_funcionarioid IS NULL
            OR ta.funcionarioid = p_funcionarioid
            OR (ta.compartilhada AND EXISTS (SELECT 1 FROM public.tarefascandidatos tc
                                              WHERE tc.atribuicaoid = ta.atribuicaoid
                                                AND tc.funcionarioid = p_funcionarioid)))
       AND (p_de IS NULL OR (ta.dataatribuicao >= (p_de::timestamp AT TIME ZONE v_fuso)
                             AND ta.dataatribuicao < ((p_ate + 1)::timestamp AT TIME ZONE v_fuso)))
  ),
  grupos AS (
    SELECT f.tarefaid,
           f.funcionarioid,
           f.tipofrequencia,
           f.datafimvigencia,
           array_agg(f.atribuicaoid ORDER BY f.atribuicaoid) AS ids,
           array_agg(f.valorfrequencia ORDER BY f.valorfrequencia) FILTER (WHERE f.valorfrequencia IS NOT NULL) AS dias,
           min(f.valorfrequencia) AS valor,
           min(f.dataagendamento) AS dataagendamento,
           min(f.disponivelapartir) AS disponivelapartir,
           bool_or(f.compartilhada) AS compartilhada,
           min(f.horariodisparo) AS horariodisparo,
           max(f.dataatribuicao) AS criadaem,
           max(f.atribuicaoid) AS ultimo
      FROM filtradas f
     GROUP BY f.tarefaid, coalesce(f.funcionarioid::text, 'c' || f.atribuicaoid), f.funcionarioid,
              f.tipofrequencia, f.datafimvigencia
  ),
  pagina AS (
    SELECT g.* FROM grupos g
     ORDER BY g.criadaem DESC NULLS LAST, g.ultimo DESC
     OFFSET greatest(coalesce(p_offset, 0), 0) LIMIT v_limite + 1
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ids', to_jsonb(p.ids),
           'tarefaid', p.tarefaid,
           'titulo', t.titulo,
           'funcionarioid', p.funcionarioid,
           'nome', fu.nomecompleto,
           'compartilhada', p.compartilhada,
           'candidatos', CASE WHEN p.compartilhada THEN
                           (SELECT coalesce(jsonb_agg(fc.nomecompleto ORDER BY fc.nomecompleto), '[]'::jsonb)
                              FROM public.tarefascandidatos tc
                              JOIN public.funcionarios fc ON fc.funcionarioid = tc.funcionarioid
                             WHERE tc.atribuicaoid = p.ids[1]) END,
           'horariodisparo', p.horariodisparo,
           'tipofrequencia', p.tipofrequencia,
           'dias', coalesce(to_jsonb(p.dias), '[]'::jsonb),
           'valor', p.valor,
           'dataagendamento', p.dataagendamento,
           'disponivelapartir', p.disponivelapartir,
           'datafimvigencia', p.datafimvigencia,
           'criadaem', p.criadaem,
           -- O dia da criação já no fuso da conta, escrito dd/mm/aaaa.
           'criadaemdia', to_char(p.criadaem AT TIME ZONE v_fuso, 'DD/MM/YYYY'))
         ORDER BY p.criadaem DESC NULLS LAST, p.ultimo DESC),
         count(*)
    INTO v_linhas, v_n
    FROM pagina p
    LEFT JOIN public.tarefas t ON t.tarefaid = p.tarefaid
    LEFT JOIN public.funcionarios fu ON fu.funcionarioid = p.funcionarioid;

  -- Veio uma a mais do que o limite: há mais para carregar.
  IF v_n > v_limite THEN
    v_linhas := v_linhas - v_limite;
  END IF;
  RETURN jsonb_build_object('linhas', coalesce(v_linhas, '[]'::jsonb), 'temmais', v_n > v_limite);
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929279000_leituras_agenda.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 5: Agenda (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Agora, com
-- "Agenda: ver" na loja: os agendamentos, os anexos (a lista; o arquivo já
-- abria desde a decisão 1), o histórico, os avisos de agendamento sem tarefa
-- e de horário apertado. O VALOR (R$) só com "Ver valores em R$" na loja:
-- sem ela, o valor vem vazio e o histórico de pagamento/edição também. Os
-- tipos de evento são o catálogo da conta (só leitura).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- Os tipos de evento (catálogo da conta).
CREATE OR REPLACE FUNCTION public.tipos_de_evento()
RETURNS TABLE(tipoeventoid integer, nome character varying, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.tipoeventoid, t.nome, t.ativo
    FROM public.tiposevento t
   WHERE (public.sou_master() AND t.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND t.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('agenda.ver'))::integer[]) > 0)
   ORDER BY t.nome, t.tipoeventoid
$$;
REVOKE ALL ON FUNCTION public.tipos_de_evento() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tipos_de_evento() TO authenticated;

-- Os agendamentos de uma loja.
CREATE OR REPLACE FUNCTION public.agendamentos_da_loja(p_lojaid integer)
RETURNS TABLE(agendamentoid integer, contaid integer, lojaid integer, nomecliente character varying, cpfcliente character varying,
              telefonecliente character varying, tipoevento character varying, tipoeventoid integer, dataevento timestamptz,
              statusagendamento character varying, statuspagamento character varying, valor numeric, funcionarioid integer,
              observacoes text, aceitawhatsapp boolean, motivocancelamento text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.agendamentoid, a.contaid, a.lojaid, a.nomecliente, a.cpfcliente, a.telefonecliente, a.tipoevento, a.tipoeventoid,
         a.dataevento, a.statusagendamento, a.statuspagamento,
         CASE WHEN public.sou_master() OR public.pode('valores.ver_rs', p_lojaid) THEN a.valor END,
         a.funcionarioid, a.observacoes, a.aceitawhatsapp, a.motivocancelamento
    FROM public.agendamentos a
   WHERE a.lojaid = p_lojaid
     AND ((public.sou_master() AND a.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND a.contaid = public.conta_do_gerente() AND public.pode('agenda.ver', p_lojaid)))
   ORDER BY a.dataevento, a.agendamentoid
   LIMIT 500
$$;
REVOKE ALL ON FUNCTION public.agendamentos_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.agendamentos_da_loja(integer) TO authenticated;

-- A loja de um agendamento em que a pessoa logada vê a Agenda (ou nada).
CREATE OR REPLACE FUNCTION public.loja_do_agendamento_visivel(p_agendamentoid integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.lojaid FROM public.agendamentos a
   WHERE a.agendamentoid = p_agendamentoid
     AND ((public.sou_master() AND a.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND a.contaid = public.conta_do_gerente() AND public.pode('agenda.ver', a.lojaid)))
$$;
REVOKE ALL ON FUNCTION public.loja_do_agendamento_visivel(integer) FROM public, anon, authenticated;

-- Os anexos de um agendamento (a lista).
CREATE OR REPLACE FUNCTION public.anexos_do_agendamento(p_agendamentoid integer)
RETURNS TABLE(anexoid integer, caminho text, nomearquivo character varying, tamanho integer, enviadoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT x.anexoid, x.caminho, x.nomearquivo, x.tamanho, x.enviadoem
    FROM public.agendamentosanexos x
   WHERE x.agendamentoid = p_agendamentoid AND x.removidoem IS NULL
     AND x.lojaid = public.loja_do_agendamento_visivel(p_agendamentoid)
     AND x.contaid = coalesce(public.minha_conta(), public.conta_do_gerente())
   ORDER BY x.enviadoem, x.anexoid
$$;
REVOKE ALL ON FUNCTION public.anexos_do_agendamento(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.anexos_do_agendamento(integer) TO authenticated;

-- O histórico de um agendamento. Sem "Ver valores em R$", o que é de
-- pagamento ou edição vem sem os valores.
CREATE OR REPLACE FUNCTION public.historico_do_agendamento(p_agendamentoid integer)
RETURNS TABLE(historicoid integer, acao character varying, valoranterior text, valornovo text, motivo text, alteradoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.acao,
         CASE WHEN public.sou_master() OR public.pode('valores.ver_rs', h.lojaid) OR h.acao NOT IN ('pagamento', 'editado', 'criado')
              THEN h.valoranterior END,
         CASE WHEN public.sou_master() OR public.pode('valores.ver_rs', h.lojaid) OR h.acao NOT IN ('pagamento', 'editado', 'criado')
              THEN h.valornovo END,
         h.motivo, h.alteradoem
    FROM public.agendamentoshistorico h
   WHERE h.agendamentoid = p_agendamentoid
     AND h.lojaid = public.loja_do_agendamento_visivel(p_agendamentoid)
     AND h.contaid = coalesce(public.minha_conta(), public.conta_do_gerente())
   ORDER BY h.historicoid
$$;
REVOKE ALL ON FUNCTION public.historico_do_agendamento(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_do_agendamento(integer) TO authenticated;

-- Agendamentos sem tarefa, para o gerente que vê a Agenda na loja.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa_gerente(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH dia AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, public.hoje_da_conta(public.conta_do_gerente()) AS hoje,
           public.fuso_da_conta(public.conta_do_gerente()) AS fuso
  ),
  futuros AS (
    SELECT a.*, dia.fuso FROM public.agendamentos a, dia
     WHERE a.contaid = dia.conta AND public.pode('agenda.ver', p_lojaid)
       AND a.lojaid = p_lojaid AND a.statusagendamento = 'Confirmado'
       AND (a.dataevento AT TIME ZONE dia.fuso)::date >= dia.hoje
  ),
  situacao AS (
    SELECT f.*,
           ta.atribuicaoid,
           ta.datafimvigencia AS datafimvigencia_ta,
           EXISTS (SELECT 1 FROM public.entregas e
                    WHERE e.atribuicaoid = ta.atribuicaoid AND e.contaid = f.contaid AND e.statusvalidacao IN ('Pendente', 'Aprovada')) AS entregue,
           t.ativa AS tarefaativa,
           EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                     JOIN public.funcionarios fu ON fu.contaid = fl.contaid AND fu.funcionarioid = fl.funcionarioid
                    WHERE fl.lojaid = f.lojaid AND fl.funcionarioid = ta.funcionarioid AND fl.ativo AND fu.ativo) AS respnaloja
      FROM futuros f
      -- A última tarefa do agendamento, em aberto ou não (a entregue e
      -- encerrada não é problema).
      LEFT JOIN LATERAL (SELECT x.* FROM public.tarefasatribuidas x
                          WHERE x.agendamentoid = f.agendamentoid AND x.contaid = f.contaid
                          ORDER BY x.atribuicaoid DESC LIMIT 1) ta ON true
      LEFT JOIN public.tarefas t ON t.contaid = ta.contaid AND t.tarefaid = ta.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'agendamentoid', s.agendamentoid,
           'quando', to_char(s.dataevento AT TIME ZONE s.fuso, 'DD/MM/YYYY HH24:MI'),
           'cliente', s.nomecliente,
           'responsavel', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = s.funcionarioid AND contaid = s.contaid),
           'motivo', CASE WHEN s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL THEN 'sem_tarefa'
                          WHEN NOT s.tarefaativa THEN 'tarefa_desativada'
                          ELSE 'responsavel_fora' END)
         ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
$function$;
REVOKE ALL ON FUNCTION public.agendamentos_sem_tarefa_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.agendamentos_sem_tarefa_gerente(integer) TO authenticated;

-- agendamentos_sem_tarefa: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa(p_lojaid integer)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.agendamentos_sem_tarefa_gerente(p_lojaid);
  END IF;
  RETURN (
  WITH dia AS (SELECT (public.meu_hoje()->>'hoje')::date AS hoje, public.meu_hoje()->>'fuso' AS fuso),
  futuros AS (
    SELECT a.*, dia.fuso FROM public.agendamentos a, dia
     WHERE a.lojaid = p_lojaid AND a.statusagendamento = 'Confirmado'
       AND (a.dataevento AT TIME ZONE dia.fuso)::date >= dia.hoje
  ),
  situacao AS (
    SELECT f.*,
           ta.atribuicaoid,
           ta.datafimvigencia AS datafimvigencia_ta,
           EXISTS (SELECT 1 FROM public.entregas e
                    WHERE e.atribuicaoid = ta.atribuicaoid AND e.statusvalidacao IN ('Pendente', 'Aprovada')) AS entregue,
           t.ativa AS tarefaativa,
           EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                     JOIN public.funcionarios fu ON fu.contaid = fl.contaid AND fu.funcionarioid = fl.funcionarioid
                    WHERE fl.lojaid = f.lojaid AND fl.funcionarioid = ta.funcionarioid AND fl.ativo AND fu.ativo) AS respnaloja
      FROM futuros f
      -- A última tarefa do agendamento, em aberto ou não (a entregue e
      -- encerrada não é problema).
      LEFT JOIN LATERAL (SELECT x.* FROM public.tarefasatribuidas x
                          WHERE x.agendamentoid = f.agendamentoid
                          ORDER BY x.atribuicaoid DESC LIMIT 1) ta ON true
      LEFT JOIN public.tarefas t ON t.contaid = ta.contaid AND t.tarefaid = ta.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'agendamentoid', s.agendamentoid,
           'quando', to_char(s.dataevento AT TIME ZONE s.fuso, 'DD/MM/YYYY HH24:MI'),
           'cliente', s.nomecliente,
           'responsavel', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = s.funcionarioid),
           'motivo', CASE WHEN s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL THEN 'sem_tarefa'
                          WHEN NOT s.tarefaativa THEN 'tarefa_desativada'
                          ELSE 'responsavel_fora' END)
         ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
  );
END;
$function$;

-- Horário apertado (2 horas antes ou depois), para o gerente que vê a Agenda na loja.
CREATE OR REPLACE FUNCTION public.conflitos_agendamento_gerente(p_lojaid integer, p_dataevento timestamp with time zone, p_ignorar integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object('quando', dataevento, 'tipo', tipoevento) ORDER BY dataevento, agendamentoid), '[]'::jsonb)
    FROM public.agendamentos
   WHERE contaid = public.conta_do_gerente() AND public.pode('agenda.ver', p_lojaid)
     AND lojaid = p_lojaid AND statusagendamento = 'Confirmado'
     AND (p_ignorar IS NULL OR agendamentoid <> p_ignorar)
     AND dataevento BETWEEN p_dataevento - interval '2 hours' AND p_dataevento + interval '2 hours'
$function$;
REVOKE ALL ON FUNCTION public.conflitos_agendamento_gerente(integer, timestamp with time zone, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conflitos_agendamento_gerente(integer, timestamp with time zone, integer) TO authenticated;

-- conflitos_agendamento: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.conflitos_agendamento(p_lojaid integer, p_dataevento timestamp with time zone, p_ignorar integer DEFAULT NULL::integer)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.conflitos_agendamento_gerente(p_lojaid, p_dataevento, p_ignorar);
  END IF;
  RETURN (
  SELECT coalesce(jsonb_agg(jsonb_build_object('quando', dataevento, 'tipo', tipoevento) ORDER BY dataevento, agendamentoid), '[]'::jsonb)
    FROM public.agendamentos
   WHERE lojaid = p_lojaid AND statusagendamento = 'Confirmado'
     AND (p_ignorar IS NULL OR agendamentoid <> p_ignorar)
     AND dataevento BETWEEN p_dataevento - interval '2 hours' AND p_dataevento + interval '2 hours'
  );
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929280000_leituras_conquistas.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 6: Conquistas (e as conquistas no
-- Relatório da pessoa) (30/09/2026).
--
-- As telas liam as tabelas direto e vinham vazias para o gerente. Agora:
--   * o catálogo de conquistas é da conta (só leitura) para quem vê
--     Conquistas ou Relatórios em alguma loja;
--   * a lista de conquistas ganhas ("Conquistas: ver"): de quem tem uma loja
--     em comum com ele (é dia a dia, como feedback);
--   * as conquistas de UMA pessoa, no Relatório ("Relatórios: ver"): só de
--     quem está INTEIRO nas lojas dele (a regra do histórico da pessoa).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.conquistas_do_catalogo()
RETURNS TABLE(conquistaid integer, nome character varying, descricao character varying, icone character varying,
              criteriotipo character varying, criteriovalor integer, criteriodias integer, pontosbonus integer,
              ativa boolean, contardesde timestamptz, criadoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.conquistaid, c.nome, c.descricao, c.icone, c.criteriotipo, c.criteriovalor, c.criteriodias, c.pontosbonus,
         c.ativa, c.contardesde, c.criadoem
    FROM public.conquistas c
   WHERE (public.sou_master() AND c.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
          AND (cardinality((SELECT public.lojas_onde_posso('conquistas.ver'))::integer[]) > 0
               OR cardinality((SELECT public.lojas_onde_posso('relatorios.ver'))::integer[]) > 0))
   ORDER BY c.criadoem, c.conquistaid
$$;
REVOKE ALL ON FUNCTION public.conquistas_do_catalogo() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conquistas_do_catalogo() TO authenticated;

-- As conquistas ganhas (a tela de Conquistas): as 200 mais recentes.
CREATE OR REPLACE FUNCTION public.conquistas_ganhas()
RETURNS TABLE(conquistafuncionarioid integer, funcionarioid integer, conquistaid integer, dataconquista timestamptz, pontosbonus integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT cf.conquistafuncionarioid, cf.funcionarioid, cf.conquistaid, cf.dataconquista, cf.pontosbonus
    FROM public.conquistasfuncionarios cf
   WHERE (public.sou_master() AND cf.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND cf.contaid = public.conta_do_gerente()
          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                       WHERE fl.contaid = cf.contaid AND fl.funcionarioid = cf.funcionarioid AND fl.ativo
                         AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('conquistas.ver'))::integer[])))
   ORDER BY cf.dataconquista DESC, cf.conquistafuncionarioid DESC
   LIMIT 200
$$;
REVOKE ALL ON FUNCTION public.conquistas_ganhas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conquistas_ganhas() TO authenticated;

-- As conquistas de uma pessoa (o Relatório da pessoa).
CREATE OR REPLACE FUNCTION public.conquistas_da_pessoa(p_funcionarioid integer)
RETURNS TABLE(conquistafuncionarioid integer, conquistaid integer, dataconquista timestamptz, pontosbonus integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT cf.conquistafuncionarioid, cf.conquistaid, cf.dataconquista, cf.pontosbonus
    FROM public.conquistasfuncionarios cf
   WHERE cf.funcionarioid = p_funcionarioid
     AND ((public.sou_master() AND cf.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND cf.contaid = public.conta_do_gerente()
           AND coalesce(public.pode_na_pessoa('relatorios.ver', cf.contaid, p_funcionarioid), false)))
   ORDER BY cf.dataconquista DESC, cf.conquistafuncionarioid DESC
$$;
REVOKE ALL ON FUNCTION public.conquistas_da_pessoa(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conquistas_da_pessoa(integer) TO authenticated;

-- As pessoas que o Relatório da pessoa pode abrir: o master, todas; o
-- gerente, só quem está INTEIRO nas lojas em que ele vê Relatórios (o mesmo
-- corte do histórico, das pendências e das conquistas da pessoa).
CREATE OR REPLACE FUNCTION public.pessoas_inteiras_para(p_codigo text)
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, ativo boolean,
              saldopontos integer, pontostotal integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, f.ativo, f.saldopontos, f.pontostotal
    FROM public.funcionarios f
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente()
          AND coalesce(public.pode_na_pessoa(p_codigo, f.contaid, f.funcionarioid), false))
   ORDER BY f.nomecompleto, f.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.pessoas_inteiras_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pessoas_inteiras_para(text) TO authenticated;

-- ------------------------------------------------------------------------
-- 20260929281000_leituras_comunicados.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 7: Comunicados (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Agora, com
-- "Comunicados: ver", ele vê o comunicado que chega às lojas dele:
--   * alvo "conta inteira": chega a todas as lojas, ele vê;
--   * alvo "lojas": se alguma das lojas escolhidas é dele;
--   * alvo "pessoas": só se TODA pessoa escolhida tem uma loja dele (se
--     alguma é só de outra loja, o comunicado não é dele).
-- As ciências: só de quem tem uma loja dele (nunca a situação de quem é só
-- de outra loja). O recibo de ciência, a lista de quem falta dar ciência e as
-- lojas e pessoas do formulário, pelas mesmas regras.
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- O comunicado chega às lojas do gerente? (interna: só as funções abaixo usam)
CREATE OR REPLACE FUNCTION public.comunicado_do_gerente(p_documentoid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, (SELECT public.lojas_onde_posso('comunicados.ver'))::integer[] AS lojas
  )
  SELECT coalesce((
    SELECT CASE d.alvo
             WHEN 'conta' THEN cardinality(ctx.lojas) > 0
             WHEN 'lojas' THEN EXISTS (SELECT 1 FROM public.documentoslojas dl
                                        WHERE dl.contaid = ctx.conta AND dl.documentoid = d.documentoid AND dl.lojaid = ANY (ctx.lojas))
             ELSE EXISTS (SELECT 1 FROM public.documentosassinaturas s WHERE s.contaid = ctx.conta AND s.documentoid = d.documentoid)
                  AND NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                                   WHERE s.contaid = ctx.conta AND s.documentoid = d.documentoid
                                     AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                                      WHERE fl.contaid = ctx.conta AND fl.funcionarioid = s.funcionarioid
                                                        AND fl.ativo AND fl.lojaid = ANY (ctx.lojas)))
           END
      FROM public.documentos d, ctx
     WHERE d.documentoid = p_documentoid AND d.contaid = ctx.conta), false)
$$;
REVOKE ALL ON FUNCTION public.comunicado_do_gerente(integer) FROM public, anon, authenticated;

-- A pessoa tem uma loja em que o gerente vê Comunicados? (interna)
CREATE OR REPLACE FUNCTION public.pessoa_nos_comunicados_do_gerente(p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = public.conta_do_gerente() AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                    AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[]))
$$;
REVOKE ALL ON FUNCTION public.pessoa_nos_comunicados_do_gerente(integer) FROM public, anon, authenticated;

-- Os comunicados da tela.
CREATE OR REPLACE FUNCTION public.comunicados_da_tela()
RETURNS TABLE(documentoid integer, titulo character varying, conteudo text, pontosporciencia integer, datacriacao timestamptz,
              status character varying, alvo character varying, primeiracienciaem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT d.documentoid, d.titulo, d.conteudo, d.pontosporciencia, d.datacriacao, d.status, d.alvo, d.primeiracienciaem
    FROM public.documentos d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente() AND public.comunicado_do_gerente(d.documentoid))
   ORDER BY d.datacriacao DESC, d.documentoid DESC
   LIMIT 300
$$;
REVOKE ALL ON FUNCTION public.comunicados_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.comunicados_da_tela() TO authenticated;

-- As ciências da tela.
CREATE OR REPLACE FUNCTION public.ciencias_da_tela()
RETURNS TABLE(assinaturaid integer, documentoid integer, funcionarioid integer, statusassinatura character varying,
              dataciencia timestamptz, origem character varying, pontospagos integer, motivodesfazer text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.assinaturaid, s.documentoid, s.funcionarioid, s.statusassinatura, s.dataciencia, s.origem, s.pontospagos, s.motivodesfazer
    FROM public.documentosassinaturas s
   WHERE (public.sou_master() AND s.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente()
          AND public.comunicado_do_gerente(s.documentoid) AND public.pessoa_nos_comunicados_do_gerente(s.funcionarioid))
   ORDER BY s.documentoid, s.assinaturaid
$$;
REVOKE ALL ON FUNCTION public.ciencias_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ciencias_da_tela() TO authenticated;

-- As lojas de um formulário: o master, todas da conta; o gerente, as dele
-- em que tem a permissão.
CREATE OR REPLACE FUNCTION public.lojas_para(p_codigo text)
RETURNS TABLE(lojaid integer, nome character varying, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.lojaid, l.nome, l.ativa
    FROM public.lojas l
   WHERE (public.sou_master() AND l.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND l.contaid = public.conta_do_gerente()
          AND l.lojaid = ANY ((SELECT public.lojas_onde_posso(p_codigo))::integer[]))
   ORDER BY l.nome, l.lojaid
$$;
REVOKE ALL ON FUNCTION public.lojas_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.lojas_para(text) TO authenticated;

-- Os pontos padrão da ciência (a tarefa de rotina "leitura").
CREATE OR REPLACE FUNCTION public.pontos_da_leitura()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.pontos FROM public.tarefas t
   WHERE t.sistema = 'leitura' AND t.ativa
     AND ((public.sou_master() AND t.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND t.contaid = public.conta_do_gerente()
           AND cardinality((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[]) > 0))
   LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.pontos_da_leitura() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pontos_da_leitura() TO authenticated;

-- Quem falta dar ciência, para o gerente: só quem tem uma loja dele.
CREATE OR REPLACE FUNCTION public.fora_do_comunicado_gerente(p_documentoid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gerente();
BEGIN
  IF v_conta IS NULL OR cardinality(public.lojas_onde_posso('comunicados.ver')) = 0
     OR NOT public.comunicado_do_gerente(p_documentoid) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                                    ORDER BY f.nomecompleto), '[]'::jsonb)
            FROM public.alcance_do_comunicado(p_documentoid) a(fid)
            JOIN public.funcionarios f ON f.funcionarioid = a.fid AND f.contaid = v_conta
           WHERE public.pessoa_nos_comunicados_do_gerente(a.fid)
             AND NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                              WHERE s.documentoid = p_documentoid AND s.funcionarioid = a.fid));
END;
$function$;

REVOKE ALL ON FUNCTION public.fora_do_comunicado_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fora_do_comunicado_gerente(integer) TO authenticated;

-- fora_do_comunicado: parte da versão viva (de 20260922400000_rh_comunicados_documentos_onboarding.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.fora_do_comunicado(p_documentoid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fora_do_comunicado_gerente(p_documentoid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                                    ORDER BY f.nomecompleto), '[]'::jsonb)
            FROM public.alcance_do_comunicado(p_documentoid) a(fid)
            JOIN public.funcionarios f ON f.funcionarioid = a.fid
           WHERE NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                              WHERE s.documentoid = p_documentoid AND s.funcionarioid = a.fid));
END;
$function$;

-- O recibo de ciência, para o gerente: comunicado dele e pessoa de loja dele.
CREATE OR REPLACE FUNCTION public.recibo_ciencia_gerente(p_assinaturaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
           'conta', c.nomefantasia, 'pessoa', f.nomecompleto, 'titulo', d.titulo, 'conteudo', d.conteudo,
           'publicadoem', d.datacriacao, 'ciencia', s.dataciencia, 'origem', s.origem,
           'protocolo', 'C-' || s.assinaturaid, 'pontos', s.pontospagos)
    FROM public.documentosassinaturas s
    JOIN public.documentos d    ON d.documentoid = s.documentoid AND d.contaid = s.contaid
    JOIN public.funcionarios f  ON f.funcionarioid = s.funcionarioid AND f.contaid = s.contaid
    JOIN public.contas c        ON c.contaid = s.contaid
   WHERE s.assinaturaid = p_assinaturaid AND s.statusassinatura = 'Ciente'
     AND s.contaid = public.conta_do_gerente()
     AND cardinality((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[]) > 0
     AND public.comunicado_do_gerente(s.documentoid) AND public.pessoa_nos_comunicados_do_gerente(s.funcionarioid)
$function$;
REVOKE ALL ON FUNCTION public.recibo_ciencia_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.recibo_ciencia_gerente(integer) TO authenticated;

-- recibo_ciencia: parte da versão viva (de 20260929160000_admin_clientes_e_redes.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.recibo_ciencia(p_assinaturaid integer)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.recibo_ciencia_gerente(p_assinaturaid);
  END IF;
  RETURN (
  SELECT jsonb_build_object(
           'conta', c.nomefantasia, 'pessoa', f.nomecompleto, 'titulo', d.titulo, 'conteudo', d.conteudo,
           'publicadoem', d.datacriacao, 'ciencia', s.dataciencia, 'origem', s.origem,
           'protocolo', 'C-' || s.assinaturaid, 'pontos', s.pontospagos)
    FROM public.documentosassinaturas s
    JOIN public.documentos d    ON d.documentoid = s.documentoid
    JOIN public.funcionarios f  ON f.funcionarioid = s.funcionarioid
    JOIN public.contas c        ON c.contaid = s.contaid
   WHERE s.assinaturaid = p_assinaturaid AND s.statusassinatura = 'Ciente'
  );
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929282000_leituras_onboarding.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 8: Onboarding (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Conduzir o
-- onboarding é cadastro: exige a pessoa INTEIRA nas lojas dele (parte 2).
-- Ver segue a mesma regra, com "Onboarding: ver": as pessoas, a situação e
-- as etapas de quem está inteiro nas lojas dele. As etapas do roteiro são o
-- catálogo da conta (só leitura). Os DOCUMENTOS PESSOAIS continuam só do
-- master (a tela só os lê para o master; nada aqui os entrega).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.etapas_de_onboarding()
RETURNS TABLE(etapaid integer, nome character varying, ordem integer, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT e.etapaid, e.nome, e.ordem, e.ativo
    FROM public.onboardingetapas e
   WHERE (public.sou_master() AND e.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND e.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('onboarding.ver'))::integer[]) > 0)
   ORDER BY e.ordem, e.nome, e.etapaid
$$;
REVOKE ALL ON FUNCTION public.etapas_de_onboarding() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.etapas_de_onboarding() TO authenticated;

CREATE OR REPLACE FUNCTION public.onboarding_status_da_tela()
RETURNS TABLE(funcionarioid integer, statusworkflow character varying, iniciadoem timestamptz, concluidoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.funcionarioid, s.statusworkflow, s.iniciadoem, s.concluidoem
    FROM public.onboardingstatus s
   WHERE (public.sou_master() AND s.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente()
          AND coalesce(public.pode_na_pessoa('onboarding.ver', s.contaid, s.funcionarioid), false))
   ORDER BY s.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.onboarding_status_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.onboarding_status_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.onboarding_itens_da_tela()
RETURNS TABLE(itemid integer, funcionarioid integer, etapaid integer, concluidoem timestamptz, observacao text, documentoid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT i.itemid, i.funcionarioid, i.etapaid, i.concluidoem, i.observacao,
         -- O documento ligado: só o número, e só para o master.
         CASE WHEN public.sou_master() THEN i.documentoid END
    FROM public.onboardingitens i
   WHERE (public.sou_master() AND i.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND i.contaid = public.conta_do_gerente()
          AND coalesce(public.pode_na_pessoa('onboarding.ver', i.contaid, i.funcionarioid), false))
   ORDER BY i.funcionarioid, i.itemid
$$;
REVOKE ALL ON FUNCTION public.onboarding_itens_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.onboarding_itens_da_tela() TO authenticated;

-- ------------------------------------------------------------------------
-- 20260929283000_leituras_equipe.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 9: Equipe (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Agora, com
-- "Equipe: ver":
--   * a lista: quem tem uma loja em comum com ele; CPF e telefone só de quem
--     está INTEIRO nas lojas dele (os dados da pessoa são cadastro);
--   * as lojas de cada pessoa: só as dele (não diz em que outra loja ela está);
--   * a situação do acesso e as travas do PIN: só de quem está inteiro nas
--     lojas dele (é o que ele pode mexer, decisões 2 e 4);
--   * as jornadas: o catálogo da conta, só leitura.
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.equipe_da_tela()
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, cpf character varying, cargo character varying,
              setor character varying, telefonewhatsapp character varying, diadefolga integer, saldopontos integer,
              ativo boolean, jornadaid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto,
         CASE WHEN public.sou_master() OR coalesce(public.pode_na_pessoa('equipe.ver', f.contaid, f.funcionarioid), false) THEN f.cpf END,
         f.cargo, f.setor,
         CASE WHEN public.sou_master() OR coalesce(public.pode_na_pessoa('equipe.ver', f.contaid, f.funcionarioid), false) THEN f.telefonewhatsapp END,
         f.diadefolga, f.saldopontos, f.ativo, f.jornadaid
    FROM public.funcionarios f
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente()
          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                       WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
                         AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('equipe.ver'))::integer[])))
   ORDER BY f.nomecompleto, f.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.equipe_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.equipe_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.vinculos_da_tela()
RETURNS TABLE(funcionarioid integer, lojaid integer, ativo boolean, validador boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fl.funcionarioid, fl.lojaid, fl.ativo, fl.validador
    FROM public.funcionarioslojas fl
   WHERE (public.sou_master() AND fl.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND fl.contaid = public.conta_do_gerente()
          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('equipe.ver'))::integer[]))
   ORDER BY fl.funcionarioid, fl.lojaid
$$;
REVOKE ALL ON FUNCTION public.vinculos_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.vinculos_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.jornadas_da_conta()
RETURNS TABLE(jornadaid integer, nome character varying, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT j.jornadaid, j.nome, j.ativa
    FROM public.jornadas j
   WHERE (public.sou_master() AND j.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente()
          AND (cardinality((SELECT public.lojas_onde_posso('equipe.ver'))::integer[]) > 0
               OR cardinality((SELECT public.lojas_onde_posso('jornada.ver'))::integer[]) > 0))
   ORDER BY j.nome, j.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_da_conta() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.jornadas_da_conta() TO authenticated;

-- A situação do acesso, para o gerente: só de quem está inteiro nas lojas dele.
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos_gerente()
 RETURNS TABLE(funcionarioid integer, temacesso boolean, nuncaentrou boolean, semsenha boolean, sempin boolean, codigopendente boolean, codigoexpiraem timestamp with time zone, redefinidoem timestamp with time zone, codigogeradoem timestamp with time zone, codigogeradopor text, codigoreimprimivel boolean, folhaemitidaem timestamp with time zone, folhaemitidapor text, folhas integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem,
         k.criadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = k.criadopor),
         k.codigocifrado IS NOT NULL,
         fa.emitidaem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = fa.emitidapor),
         coalesce(fa.total, 0)::integer
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem, criadoem, criadopor, codigocifrado FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC, x.folhaid DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.conta_do_gerente())
     AND coalesce(public.pode_na_pessoa('equipe.ver', f.contaid, f.funcionarioid), false)
   ORDER BY f.funcionarioid
$function$;

REVOKE ALL ON FUNCTION public.situacao_dos_acessos_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.situacao_dos_acessos_gerente() TO authenticated;

-- situacao_dos_acessos: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
 RETURNS TABLE(funcionarioid integer, temacesso boolean, nuncaentrou boolean, semsenha boolean, sempin boolean, codigopendente boolean, codigoexpiraem timestamp with time zone, redefinidoem timestamp with time zone, codigogeradoem timestamp with time zone, codigogeradopor text, codigoreimprimivel boolean, folhaemitidaem timestamp with time zone, folhaemitidapor text, folhas integer)

 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.situacao_dos_acessos_gerente();
    RETURN;
  END IF;
  RETURN QUERY
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem,
         k.criadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = k.criadopor),
         k.codigocifrado IS NOT NULL,
         fa.emitidaem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = fa.emitidapor),
         coalesce(fa.total, 0)::integer
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem, criadoem, criadopor, codigocifrado FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC, x.folhaid DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
   ORDER BY f.funcionarioid;
END;
$function$;

-- As travas do PIN, para o gerente: só de quem está inteiro nas lojas dele.
CREATE OR REPLACE FUNCTION public.travas_do_pin_gerente()
 RETURNS TABLE(funcionarioid integer, erros integer, minutosfaltam integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT t.funcionarioid, t.erros,
         CASE WHEN t.bloqueadoate > now()
              THEN greatest(1, ceil(extract(epoch FROM t.bloqueadoate - now()) / 60)::integer) ELSE 0 END
    FROM public.travaspin t
   WHERE t.contaid = public.conta_do_gerente()
     AND coalesce(public.pode_na_pessoa('equipe.ver', t.contaid, t.funcionarioid), false)
     AND (t.bloqueadoate > now() OR (t.erros > 0 AND t.ultimoerro > now() - interval '24 hours'))
$function$;
REVOKE ALL ON FUNCTION public.travas_do_pin_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.travas_do_pin_gerente() TO authenticated;

-- travas_do_pin: parte da versão viva (de 20260929246000_trava_do_pin_por_pessoa.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.travas_do_pin()
 RETURNS TABLE(funcionarioid integer, erros integer, minutosfaltam integer)

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.travas_do_pin_gerente();
    RETURN;
  END IF;
  RETURN QUERY
  SELECT t.funcionarioid, t.erros,
         CASE WHEN t.bloqueadoate > now()
              THEN greatest(1, ceil(extract(epoch FROM t.bloqueadoate - now()) / 60)::integer) ELSE 0 END
    FROM public.travaspin t
   WHERE t.contaid = public.minha_conta()
     AND (t.bloqueadoate > now() OR (t.erros > 0 AND t.ultimoerro > now() - interval '24 hours'));
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929284000_leituras_lojas_jornada.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 10: Lojas, Jornada e o nome da conta
-- no topo (30/09/2026).
--
-- As telas liam as tabelas direto e vinham vazias para o gerente. Agora:
--   * o topo mostra o NOME da conta para quem entra (master ou gerente);
--   * Lojas ("Lojas: ver"): as lojas dele, o resumo delas, as pessoas de cada
--     uma; os links de TV com "Lojas: TV"; o som do tablet com "Lojas: som do
--     tablet". Os dados de cadastro da conta (e-mail, telefone, limite de
--     lojas) continuam só do master;
--   * Jornada ("Jornada: ver"): o catálogo de jornadas da conta (só
--     leitura), as pessoas e os vínculos das lojas dele, e o MAPA: a própria
--     mapa_da_jornada passa a servir o gerente (é ela, e só ela, que lê o
--     intervalo de planejamento — a regra do CLAUDE.md continua valendo).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- O nome da conta, para o topo.
CREATE OR REPLACE FUNCTION public.nome_da_conta()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.nomefantasia::text FROM public.contas c
   WHERE c.contaid = CASE WHEN public.sou_master() THEN public.minha_conta() ELSE public.conta_do_gerente() END
$$;
REVOKE ALL ON FUNCTION public.nome_da_conta() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.nome_da_conta() TO authenticated;

-- A conta na tela de Lojas: o master, o cadastro todo; o gerente, só o nome.
CREATE OR REPLACE FUNCTION public.conta_da_gestao()
RETURNS TABLE(contaid integer, nome character varying, nomefantasia character varying, email character varying,
              telefone character varying, cidade character varying, limitelojas integer, status character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.contaid, c.nome, c.nomefantasia, c.email, c.telefone, c.cidade, c.limitelojas, c.status
    FROM public.contas c
   WHERE public.sou_master() AND c.contaid = public.minha_conta()
  UNION ALL
  SELECT c.contaid, c.nome, c.nomefantasia, NULL, NULL, NULL, NULL, NULL
    FROM public.contas c
   WHERE NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
     AND cardinality((SELECT public.lojas_onde_posso('lojas.ver'))::integer[]) > 0
$$;
REVOKE ALL ON FUNCTION public.conta_da_gestao() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_da_gestao() TO authenticated;

-- As lojas na tela de Lojas.
CREATE OR REPLACE FUNCTION public.lojas_da_gestao()
RETURNS TABLE(lojaid integer, nome character varying, cidade character varying, endereco character varying, ativa boolean,
              gestorid integer, responsavelagendamentosid integer, mostrarvalorestv boolean, tvblocos jsonb, tvsegundos integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.lojaid, l.nome, l.cidade, l.endereco, l.ativa, l.gestorid, l.responsavelagendamentosid, l.mostrarvalorestv,
         l.tvblocos, l.tvsegundos
    FROM public.lojas l
   WHERE (public.sou_master() AND l.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND l.contaid = public.conta_do_gerente()
          AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('lojas.ver'))::integer[]))
   ORDER BY l.nome, l.lojaid
$$;
REVOKE ALL ON FUNCTION public.lojas_da_gestao() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.lojas_da_gestao() TO authenticated;

-- Os links de TV.
CREATE OR REPLACE FUNCTION public.links_de_tv()
RETURNS TABLE(linktvid integer, lojaid integer, nome character varying, criadoem timestamptz, revogadoem timestamptz, ultimouso timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.linktvid, t.lojaid, t.nome, t.criadoem, t.revogadoem, t.ultimouso
    FROM public.linkstv t
   WHERE (public.sou_master() AND t.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND t.contaid = public.conta_do_gerente()
          AND t.lojaid = ANY ((SELECT public.lojas_onde_posso('lojas.tv'))::integer[]))
   ORDER BY t.criadoem DESC, t.linktvid DESC
$$;
REVOKE ALL ON FUNCTION public.links_de_tv() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.links_de_tv() TO authenticated;

-- O som do tablet de uma loja.
CREATE OR REPLACE FUNCTION public.som_da_loja(p_lojaid integer)
RETURNS TABLE(somtarefanova boolean, somvolume integer, somrepetirminutos integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.somtarefanova, l.somvolume, l.somrepetirminutos
    FROM public.lojas l
   WHERE l.lojaid = p_lojaid
     AND ((public.sou_master() AND l.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND l.contaid = public.conta_do_gerente() AND public.pode('lojas.tablet_som', p_lojaid)))
$$;
REVOKE ALL ON FUNCTION public.som_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.som_da_loja(integer) TO authenticated;

-- Os vínculos pessoa-loja de uma tela (o gerente: só com as lojas dele).
CREATE OR REPLACE FUNCTION public.vinculos_para(p_codigo text)
RETURNS TABLE(funcionarioid integer, lojaid integer, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fl.funcionarioid, fl.lojaid, fl.ativo
    FROM public.funcionarioslojas fl
   WHERE (public.sou_master() AND fl.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND fl.contaid = public.conta_do_gerente()
          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso(p_codigo))::integer[]))
   ORDER BY fl.funcionarioid, fl.lojaid
$$;
REVOKE ALL ON FUNCTION public.vinculos_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.vinculos_para(text) TO authenticated;

-- As jornadas com os horários (catálogo da conta, só leitura).
CREATE OR REPLACE FUNCTION public.jornadas_da_tela()
RETURNS TABLE(jornadaid integer, nome character varying, pausainicio time, pausafim time, observacao text, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT j.jornadaid, j.nome, j.pausainicio, j.pausafim, j.observacao, j.ativa
    FROM public.jornadas j
   WHERE (public.sou_master() AND j.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('jornada.ver'))::integer[]) > 0)
   ORDER BY j.nome, j.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.jornadas_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.dias_das_jornadas()
RETURNS TABLE(jornadaid integer, diasemana smallint, entrada time, saida time)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT d.jornadaid, d.diasemana, d.entrada, d.saida
    FROM public.jornadasdias d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('jornada.ver'))::integer[]) > 0)
   ORDER BY d.jornadaid, d.diasemana
$$;
REVOKE ALL ON FUNCTION public.dias_das_jornadas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dias_das_jornadas() TO authenticated;

-- O resumo das lojas, para o gerente: só as dele.
CREATE OR REPLACE FUNCTION public.resumo_das_lojas_gerente()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gerente();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
             jsonb_build_object(
               'lojaid',    l.lojaid,
               'nome',      l.nome,
               'progresso', p.painel->'progresso',
               'pendentes', p.painel->'pendentes',
               'lider',     p.painel->'podio'->0)
             ORDER BY l.nome), '[]'::jsonb)
      FROM public.lojas l
      CROSS JOIN LATERAL (SELECT public.montar_painel(v_conta, l.lojaid, false) AS painel) p
     WHERE l.contaid = v_conta AND l.ativa
       AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('lojas.ver'))::integer[])
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.resumo_das_lojas_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.resumo_das_lojas_gerente() TO authenticated;

-- resumo_das_lojas: parte da versão viva (de 20260921130000_painel_e_modo_tv.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.resumo_das_lojas()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.minha_conta();
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.resumo_das_lojas_gerente();
  END IF;
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
             jsonb_build_object(
               'lojaid',    l.lojaid,
               'nome',      l.nome,
               'progresso', p.painel->'progresso',
               'pendentes', p.painel->'pendentes',
               'lider',     p.painel->'podio'->0)
             ORDER BY l.nome), '[]'::jsonb)
      FROM public.lojas l
      CROSS JOIN LATERAL (SELECT public.montar_painel(v_conta, l.lojaid, false) AS painel) p
     WHERE l.contaid = v_conta AND l.ativa
  );
END;
$function$;

-- mapa_da_jornada: parte da versão viva (de 20260929233000_intervalo_do_mapa_por_dia.sql); serve também o gerente.
CREATE OR REPLACE FUNCTION public.mapa_da_jornada(p_lojaid integer, p_diasemana integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- A conta: a do master, ou a do gerente que vê a Jornada nesta loja. As
  -- regras das tabelas faziam esse corte para o master; agora é explícito.
  v_conta integer := CASE WHEN public.sou_master() THEN public.minha_conta()
                          WHEN public.conta_do_gerente() IS NOT NULL AND public.pode('jornada.ver', p_lojaid)
                          THEN public.conta_do_gerente() END;
  v_hoje date := CASE WHEN public.sou_master() THEN (public.meu_hoje()->>'hoje')::date
                      ELSE public.hoje_da_conta(public.conta_do_gerente()) END;
  v_dia  integer := coalesce(p_diasemana, extract(dow FROM v_hoje)::integer + 1);
  v_loja text;
BEGIN
  IF v_dia NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT l.nome INTO v_loja FROM public.lojas l WHERE l.lojaid = p_lojaid AND l.contaid = v_conta;

  RETURN jsonb_build_object(
    'diasemana', v_dia,
    'hoje', v_hoje,
    'loja', v_loja,
    'pessoas', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'funcionarioid', f.funcionarioid,
               'nome', f.nomecompleto,
               'cargo', f.cargo,
               -- A mesma ordem de dia_de_trabalho: afastamento e folga
               -- vencem o horário.
               'situacao', CASE
                 WHEN f.datainicioafastamento IS NOT NULL AND f.datafimafastamento IS NOT NULL
                      AND v_hoje BETWEEN f.datainicioafastamento AND f.datafimafastamento THEN 'afastado'
                 WHEN f.diadefolga = v_dia THEN 'folga'
                 WHEN f.jornadaid IS NULL THEN 'sem_jornada'
                 WHEN jd.entrada IS NULL THEN 'sem_horario'
                 ELSE 'trabalha' END,
               'afastadoate', f.datafimafastamento,
               -- Domingo de folga do mês (1º, 2º...): só avisa no mapa de domingo.
               'domingofolga', CASE WHEN v_dia = 1 AND coalesce(f.domingofolgamensal, 0) > 0
                                    THEN f.domingofolgamensal END,
               'entrada', to_char(jd.entrada, 'HH24:MI'),
               'saida', to_char(jd.saida, 'HH24:MI'),
               'intervaloinicio', to_char(im.inicio, 'HH24:MI'),
               'intervalofim', to_char(im.fim, 'HH24:MI'))
             ORDER BY jd.entrada NULLS LAST, f.nomecompleto)
        FROM public.funcionarioslojas fl
        JOIN public.funcionarios f
          ON f.contaid = fl.contaid AND f.funcionarioid = fl.funcionarioid AND f.ativo
        LEFT JOIN public.jornadasdias jd
          ON jd.contaid = f.contaid AND jd.jornadaid = f.jornadaid AND jd.diasemana = v_dia
        -- 29/09/2026: o intervalo é do DIA da semana escolhido.
        LEFT JOIN public.intervalosdomapa im
          ON im.contaid = f.contaid AND im.funcionarioid = f.funcionarioid AND im.diasemana = v_dia
       WHERE fl.contaid = v_conta AND fl.lojaid = p_lojaid AND fl.ativo), '[]'::jsonb));
END;
$function$;

-- mapa_da_semana: parte da versão viva (de 20260929233000_intervalo_do_mapa_por_dia.sql); o nome da loja, pela mesma regra.
CREATE OR REPLACE FUNCTION public.mapa_da_semana(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'loja', (SELECT l.nome FROM public.lojas l
              WHERE l.lojaid = p_lojaid
                AND l.contaid = CASE WHEN public.sou_master() THEN public.minha_conta()
                                     WHEN public.pode('jornada.ver', p_lojaid) THEN public.conta_do_gerente() END),
    'dias', jsonb_agg(public.mapa_da_jornada(p_lojaid, d) ORDER BY d))
    FROM generate_series(1, 7) d
$function$;

-- ------------------------------------------------------------------------
-- 20260929285000_codigo_e_valores_rs.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 11: o código da empresa e o filtro
-- "Ver valores em R$" que faltava (30/09/2026).
--
--   * O código da empresa (tela de Lojas, para configurar o tablet): o
--     master, e o gerente com "Lojas: acesso do tablet" ou "Equipe: criar
--     acesso" em alguma loja (é o código que vai na folha de acesso).
--   * R$ que ainda chegava ao gerente sem "Ver valores em R$": o valor do
--     resgate "abate na comanda" (lista e recibo) e a taxa de pontos para
--     reais no Extrato. Sem a permissão, vêm vazios ("Abate na comanda").
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.codigo_da_empresa()
RETURNS TABLE(codigo character varying, nomefantasia character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.codigo, c.nomefantasia
    FROM public.contas c
   WHERE (public.sou_master() AND c.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
          AND (cardinality((SELECT public.lojas_onde_posso('lojas.tablet_acesso'))::integer[]) > 0
               OR cardinality((SELECT public.lojas_onde_posso('equipe.criar_acesso'))::integer[]) > 0))
$$;
REVOKE ALL ON FUNCTION public.codigo_da_empresa() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.codigo_da_empresa() TO authenticated;

-- listar_trocas_gerente: parte da versão viva (de 20260929276000_leituras_premios_extrato_ranking.sql); o R$ só com a permissão.
CREATE OR REPLACE FUNCTION public.listar_trocas_gerente(p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         CASE WHEN public.pode('valores.ver_rs', r.lojaid) THEN r.valorreais END,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL AND public.pode('valores.ver_rs', r.lojaid)
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda'
                                          ELSE p.nome END,
               'loja',               l.nome,
               -- De onde veio: "colaborador" quando foi pelo celular. Vazio
               -- nos resgates que o gestor registrou, inclusive os antigos.
               'origem',             r.origem) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid AND f.contaid = r.contaid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid AND p.contaid = r.contaid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid AND l.contaid = r.contaid
       WHERE r.contaid = public.conta_do_gerente()
         AND r.lojaid = ANY ((SELECT public.lojas_onde_posso('premios.ver'))::integer[])
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
$function$;

-- recibo_resgate_gerente: parte da versão viva (de 20260929274000_arquivos_do_gerente.sql); o R$ só com a permissão.
CREATE OR REPLACE FUNCTION public.recibo_resgate_gerente(p_resgateid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nomefantasia AS conta
      FROM public.resgates r
      JOIN public.funcionarios f ON f.funcionarioid = r.funcionarioid
      JOIN public.produtosloja p ON p.produtoid = r.produtoid
      JOIN public.contas c       ON c.contaid = r.contaid
      LEFT JOIN public.lojas l   ON l.lojaid = r.lojaid
     WHERE r.resgateid = p_resgateid
       AND r.contaid = public.conta_do_gerente()
       AND r.lojaid IS NOT NULL AND public.pode('premios.ver', r.lojaid)
  ),
  mov AS (
    SELECT m.movimentoid, m.datamovimento, m.tipo, m.pontos, m.descricao,
           (SELECT coalesce(sum(x.pontos), 0) FROM public.movimentospontos x
             WHERE x.funcionarioid = m.funcionarioid AND x.movimentoid < m.movimentoid) AS saldoantes
      FROM public.movimentospontos m
     WHERE m.resgateid = p_resgateid AND m.contaid = public.conta_do_gerente()
  )
  SELECT jsonb_build_object(
           'conta', r.conta, 'loja', r.loja, 'pessoa', r.nomecompleto,
           'premio', CASE WHEN r.valorreais IS NOT NULL AND public.pode('valores.ver_rs', r.lojaid)
                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                          WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda'
                          ELSE r.premio END,
           'pontos', r.pontosgastos, 'situacao', r.status, 'solicitadoem', r.datasolicitacao,
           'entregueem', r.dataentrega, 'protocolo', 'R-' || r.resgateid,
           'movimentos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                             'data', datamovimento, 'tipo', tipo, 'pontos', pontos, 'descricao', descricao,
                             'saldoantes', saldoantes, 'saldodepois', saldoantes + pontos) ORDER BY movimentoid), '[]'::jsonb)
                            FROM mov))
    FROM r
$function$;

-- extrato_pontos_gerente: parte da versão viva (de 20260929276000_leituras_premios_extrato_ranking.sql); a taxa só com a permissão.
CREATE OR REPLACE FUNCTION public.extrato_pontos_gerente(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gerente();
  v_fuso    text;
  v_nome    text; v_saldo integer; v_inicial integer; v_periodo integer; v_soma integer; v_mov jsonb;
BEGIN
  IF v_conta IS NULL OR NOT coalesce(public.pode_na_pessoa('extrato.ver', v_conta, p_funcionarioid), false) THEN
    RETURN NULL;
  END IF;
  v_fuso := public.fuso_da_conta(v_conta);
  SELECT nomecompleto, saldopontos INTO v_nome, v_saldo
    FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT coalesce(sum(pontos), 0) INTO v_inicial FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND public.dia_no_fuso(datamovimento, v_fuso) < p_de;
  SELECT coalesce(sum(pontos), 0) INTO v_periodo FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND public.dia_no_fuso(datamovimento, v_fuso) BETWEEN p_de AND p_ate;
  SELECT coalesce(sum(pontos), 0) INTO v_soma FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid;
  WITH todos AS (
    SELECT m.*, sum(m.pontos) OVER (ORDER BY m.datamovimento, m.movimentoid) AS saldoapos
      FROM public.movimentospontos m
     WHERE m.contaid = v_conta AND m.funcionarioid = p_funcionarioid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'data', t.datamovimento, 'tipo', t.tipo, 'descricao', t.descricao,
           'loja', l.nome, 'pontos', t.pontos, 'saldoapos', t.saldoapos)
           ORDER BY t.datamovimento, t.movimentoid), '[]'::jsonb)
    INTO v_mov
    FROM todos t
    LEFT JOIN public.lojas l ON l.lojaid = t.lojaid AND l.contaid = v_conta
   WHERE public.dia_no_fuso(t.datamovimento, v_fuso) BETWEEN p_de AND p_ate;
  RETURN jsonb_build_object('nome', v_nome, 'saldoatual', v_saldo, 'saldoinicial', v_inicial,
                            'saldofinal', v_inicial + v_periodo, 'confere', v_soma = v_saldo,
                            -- A taxa é R$ por ponto: só com "Ver valores em R$" em alguma loja.
                            'taxa', CASE WHEN cardinality(public.lojas_onde_posso('valores.ver_rs')) > 0
                                         THEN public.minha_taxa_gerente() END,
                            'movimentos', v_mov);
END;
$function$;

-- minha_taxa_gerente: parte da versão viva (de 20260929276000_leituras_premios_extrato_ranking.sql); também pede "Ver valores em R$".
CREATE OR REPLACE FUNCTION public.minha_taxa_gerente()
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gerente(); v_texto text; v_taxa numeric;
BEGIN
  IF v_conta IS NULL OR cardinality(public.lojas_onde_posso('valores.ver_rs')) = 0
     OR (cardinality(public.lojas_onde_posso('premios.ver')) = 0
         AND cardinality(public.lojas_onde_posso('extrato.ver')) = 0) THEN
    RETURN NULL;
  END IF;
  SELECT valor INTO v_texto FROM public.configuracoes WHERE contaid = v_conta AND chave = 'TAXA_CONVERSAO_PONTO_REAL';
  BEGIN
    v_taxa := nullif(replace(btrim(coalesce(v_texto, '')), ',', '.'), '')::numeric;
  EXCEPTION WHEN others THEN
    v_taxa := NULL;
  END;
  RETURN CASE WHEN v_taxa > 0 THEN v_taxa END;
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929286000_comunicados_e_inicio_do_gerente_uma_vez.sql
-- ------------------------------------------------------------------------
-- Comunicados e Início do gerente: uma conta só por leitura (30/09/2026).
--
-- O teste de tempo com 12 meses de uso (com comunicados toda semana) pegou:
-- a tela de Comunicados do gerente em 5,9 s e o Início dele em 2,7 s. Os dois
-- decidiam "o comunicado chega às lojas dele?" e "a pessoa é dele?" de novo
-- para CADA linha. Agora o conjunto de comunicados e o de pessoas saem uma vez
-- por leitura, com as MESMAS regras. Para o master nada muda. Nenhum dado é
-- alterado. Classificação: ACRESCENTA.

-- Os comunicados que chegam às lojas do gerente, numa leitura só (as mesmas
-- regras de comunicado_do_gerente). Interna.
CREATE OR REPLACE FUNCTION public.comunicados_do_gerente_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, (SELECT public.lojas_onde_posso('comunicados.ver'))::integer[] AS lojas
  ),
  pessoas AS MATERIALIZED (
    SELECT DISTINCT fl.funcionarioid FROM public.funcionarioslojas fl, ctx
     WHERE fl.contaid = ctx.conta AND fl.ativo AND fl.lojaid = ANY (ctx.lojas)
  )
  SELECT d.documentoid
    FROM public.documentos d, ctx
   WHERE d.contaid = ctx.conta AND cardinality(ctx.lojas) > 0
     AND CASE d.alvo
           WHEN 'conta' THEN true
           WHEN 'lojas' THEN EXISTS (SELECT 1 FROM public.documentoslojas dl
                                      WHERE dl.contaid = ctx.conta AND dl.documentoid = d.documentoid AND dl.lojaid = ANY (ctx.lojas))
           ELSE EXISTS (SELECT 1 FROM public.documentosassinaturas s WHERE s.contaid = ctx.conta AND s.documentoid = d.documentoid)
                AND NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                                 WHERE s.contaid = ctx.conta AND s.documentoid = d.documentoid
                                   AND s.funcionarioid NOT IN (SELECT funcionarioid FROM pessoas))
         END
$$;
REVOKE ALL ON FUNCTION public.comunicados_do_gerente_ids() FROM public, anon, authenticated;

-- comunicados_da_tela: parte da versão viva (de 20260929281000_leituras_comunicados.sql); o conjunto sai uma vez.
CREATE OR REPLACE FUNCTION public.comunicados_da_tela()
 RETURNS TABLE(documentoid integer, titulo character varying, conteudo text, pontosporciencia integer, datacriacao timestamp with time zone, status character varying, alvo character varying, primeiracienciaem timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT d.documentoid, d.titulo, d.conteudo, d.pontosporciencia, d.datacriacao, d.status, d.alvo, d.primeiracienciaem
    FROM public.documentos d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente()
          AND d.documentoid IN (SELECT public.comunicados_do_gerente_ids()))
   ORDER BY d.datacriacao DESC, d.documentoid DESC
   LIMIT 300
$function$;

-- ciencias_da_tela: parte da versão viva (de 20260929281000_leituras_comunicados.sql); os conjuntos saem uma vez.
CREATE OR REPLACE FUNCTION public.ciencias_da_tela()
 RETURNS TABLE(assinaturaid integer, documentoid integer, funcionarioid integer, statusassinatura character varying, dataciencia timestamp with time zone, origem character varying, pontospagos integer, motivodesfazer text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT s.assinaturaid, s.documentoid, s.funcionarioid, s.statusassinatura, s.dataciencia, s.origem, s.pontospagos, s.motivodesfazer
    FROM public.documentosassinaturas s
   WHERE (public.sou_master() AND s.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente()
          AND s.documentoid IN (SELECT public.comunicados_do_gerente_ids())
          AND s.funcionarioid IN (SELECT fl.funcionarioid FROM public.funcionarioslojas fl
                                   WHERE fl.contaid = public.conta_do_gerente() AND fl.ativo
                                     AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[])))
   ORDER BY s.documentoid, s.assinaturaid
$function$;

-- painel_inicio_gerente: parte da versão viva (de 20260929275000_fila_nao_cresce_com_os_dias.sql); as pessoas dos comunicados saem uma vez.
CREATE OR REPLACE FUNCTION public.painel_inicio_gerente(p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_pessoas_com integer[];
  v_conta     integer := public.conta_do_gerente();
  v_hoje      date;
  v_fuso      text;
  v_mes_ini   date;
  v_mes_fim   date;
  v_sem_ini   date;
  v_lojas     integer[];
  v_rs        integer[];   -- lojas com meta e R$
  v_agenda_l  integer[];
  v_solic_l   integer[];
  v_just_l    integer[];
  v_metas_l   integer[];
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje    := public.hoje_da_conta(v_conta);
  v_fuso    := public.fuso_da_conta(v_conta);
  v_mes_ini := date_trunc('month', v_hoje)::date;
  v_mes_fim := (date_trunc('month', v_hoje) + interval '1 month - 1 day')::date;
  v_sem_ini := (date_trunc('week', v_hoje) - interval '7 weeks')::date;

  SELECT coalesce(array_agg(l.lojaid ORDER BY l.lojaid), '{}') INTO v_lojas
    FROM public.lojas l
   WHERE l.contaid = v_conta AND l.ativa
     AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('inicio.ver'))::integer[])
     AND (p_lojaid IS NULL OR l.lojaid = p_lojaid);
  IF p_lojaid IS NOT NULL AND cardinality(v_lojas) = 0 THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_rs       := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x) AND public.pode('valores.ver_rs', x));
  v_metas_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('metas.ver', x));
  v_agenda_l := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('agenda.ver', x));
  v_solic_l  := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('solicitacoes.ver', x));
  v_just_l   := ARRAY(SELECT x FROM unnest(v_lojas) x WHERE public.pode('justificativas.ver', x));

  -- Tarefas de hoje: a mesma fila do tablet, do Quadro e da TV.
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_de_hoje(v_conta, l.lojaid) f;

  -- Meta do dia e do mês: só nas lojas com meta e R$.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.contaid = v_conta AND a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1, v_fuso)) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.contaid = v_conta AND mp.lojaid = ANY (v_rs) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                             AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_rs) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas
   WHERE cardinality(v_rs) > 0;
  v_vendas := coalesce(v_vendas, '[]'::jsonb);

  -- Pontos por semana, pelo livro, só o que foi lançado nas lojas dele.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_no_fuso(mv.datamovimento, v_fuso))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.contaid = v_conta AND mv.lojaid = ANY (v_lojas)
       AND mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE v_fuso)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês.
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_no_fuso(e.dataaprovacao, v_fuso))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
    UNION ALL
    SELECT date_trunc('week', public.dia_no_fuso(e.datarecusa, v_fuso))::date, 'r'
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_no_fuso(e.datarecusa, v_fuso) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.datarecusa >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.datarecusa < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês nas lojas dele (pontos das entregas aprovadas ali).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint AS pontos, count(*)::bigint AS entregas
            FROM public.entregas e
            JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
           WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
             AND public.dia_no_fuso(e.dataaprovacao, v_fuso) BETWEEN v_mes_ini AND v_hoje
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((v_mes_ini)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((v_hoje)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
           GROUP BY f.funcionarioid, f.nomecompleto
           ORDER BY 3 DESC, 2, 1
           LIMIT 5) r;

  -- Próximos agendamentos: só nas lojas em que ele vê a agenda.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid AND l.contaid = v_conta
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
       WHERE a.contaid = v_conta AND a.lojaid = ANY (v_agenda_l) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
        JOIN public.lojas l        ON l.lojaid = e.lojaid AND l.contaid = v_conta
       WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  -- Quem está INTEIRO nas lojas em que ele vê Comunicados (a regra de
  -- pode_na_pessoa), calculado uma vez, e não para cada ciência pendente.
  SELECT coalesce(array_agg(x.funcionarioid), '{}') INTO v_pessoas_com
    FROM (SELECT fl.funcionarioid FROM public.funcionarioslojas fl
           WHERE fl.contaid = v_conta AND fl.ativo
           GROUP BY fl.funcionarioid
          HAVING bool_and(fl.lojaid = ANY (public.lojas_onde_posso('comunicados.ver')))) x;

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes', jsonb_build_object(
      'tarefas',      v_tarefas,
      'metadia',      v_metadia,
      'metames',      v_metames,
      'validar',      (SELECT count(*) FROM public.entregas
                        WHERE contaid = v_conta AND lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
      'agendahoje',   (SELECT count(*) FROM public.agendamentos
                        WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento <> 'Cancelado'
                          AND public.dia_no_fuso(dataevento, v_fuso) = v_hoje),
      'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                 'pessoas',     count(DISTINCT s.funcionarioid))
                         FROM public.documentosassinaturas s
                         JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                         JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                          AND s.funcionarioid = ANY (v_pessoas_com)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                         JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.contaid = v_conta AND f.ativo
                        WHERE o.contaid = v_conta AND o.statusworkflow = 'Em andamento'
                          AND public.pode_na_pessoa('onboarding.ver', v_conta, o.funcionarioid)
                          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                        WHERE contaid = v_conta AND lojaid = ANY (v_solic_l) AND status IN ('Aberta', 'Em andamento')),
      'justificativas', (SELECT count(*) FROM public.justificativas
                          WHERE contaid = v_conta AND lojaid = ANY (v_just_l) AND status = 'Pendente')),
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    -- O guia de primeiros passos é da conta inteira: para o gerente, nada a
    -- mostrar (tudo "feito" esconde o guia).
    'guia', jsonb_build_object('loja', true, 'equipe', true, 'tarefas', true, 'meta', true, 'tv', true),
    'avisos', jsonb_build_object(
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                      WHERE l.contaid = v_conta AND l.ativa AND l.lojaid = ANY (v_metas_l)
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, v_hoje - 1, v_hoje - 1, v_fuso))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE contaid = v_conta AND lojaid = ANY (v_agenda_l) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = v_conta AND f.ativo
                          WHERE s.contaid = v_conta AND s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND s.funcionarioid = ANY (v_pessoas_com)
                            AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                         WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = ANY (v_lojas) AND fl.ativo)),
      'livro', NULL),
    'rotina', NULL);
END;
$function$;

COMMIT;
