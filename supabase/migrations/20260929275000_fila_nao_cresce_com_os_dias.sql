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
