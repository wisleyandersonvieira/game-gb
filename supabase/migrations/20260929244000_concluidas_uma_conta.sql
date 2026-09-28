-- "Concluídas" com UMA conta, e o aviso da venda de ontem (29/09/2026,
-- pedidos do Wisley).
--
-- 1. A fração "X de N concluídas" conta SÓ as aprovadas, em toda tela (TV,
--    painel da loja, Gestão e Início). O que espera o gestor fica à parte.
--    A conta é escrita UMA vez, na agregação progresso_da_fila: a barra da
--    TV (montar_painel, que o painel da loja e a Gestão também leem) e o
--    cartão do Início somam por ela. Ela já devolve o percentual: nenhuma
--    tela divide sozinha.
-- 2. O Início avisa a loja que tinha meta ontem e ficou sem a venda lançada.

-- ---------------------------------------------------------------------------
-- 1. A conta, escrita uma vez
-- ---------------------------------------------------------------------------
-- Cada tarefa da fila cai em UM estado: aprovada, em validação, em
-- andamento, disponível (para fazer) ou ainda não liberada.
CREATE OR REPLACE FUNCTION public.progresso_da_fila_passo(s jsonb, p_situacao text, p_feitasituacao text, p_disponivel boolean)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'total',             (s->>'total')::integer + 1,
    'aprovadas',         (s->>'aprovadas')::integer
                           + CASE WHEN p_situacao = 'feita' AND p_feitasituacao = 'Aprovada' THEN 1 ELSE 0 END,
    'emvalidacao',       (s->>'emvalidacao')::integer
                           + CASE WHEN p_situacao = 'feita' AND p_feitasituacao = 'Pendente' THEN 1 ELSE 0 END,
    'emandamento',       (s->>'emandamento')::integer + CASE WHEN p_situacao = 'em_andamento' THEN 1 ELSE 0 END,
    'parafazer',         (s->>'parafazer')::integer + CASE WHEN p_disponivel THEN 1 ELSE 0 END,
    'aindanaoliberadas', (s->>'aindanaoliberadas')::integer
                           + CASE WHEN p_situacao = 'para_pegar' AND NOT p_disponivel THEN 1 ELSE 0 END)
$$;

-- "Concluídas" = aprovadas. O percentual sai daqui, arredondado, uma vez.
CREATE OR REPLACE FUNCTION public.progresso_da_fila_fim(s jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT s || jsonb_build_object(
    'percentual', CASE WHEN (s->>'total')::integer > 0
                       THEN round((s->>'aprovadas')::numeric * 100 / (s->>'total')::integer)::integer
                       ELSE 0 END)
$$;

CREATE OR REPLACE AGGREGATE public.progresso_da_fila(text, text, boolean) (
  SFUNC     = public.progresso_da_fila_passo,
  STYPE     = jsonb,
  FINALFUNC = public.progresso_da_fila_fim,
  INITCOND  = '{"total": 0, "aprovadas": 0, "emvalidacao": 0, "emandamento": 0, "parafazer": 0, "aindanaoliberadas": 0}'
);
-- Só conta: não lê tabela nenhuma. O Início (com a permissão de quem pede)
-- precisa poder usar.
REVOKE ALL ON FUNCTION public.progresso_da_fila_passo(jsonb, text, text, boolean) FROM public, anon;
REVOKE ALL ON FUNCTION public.progresso_da_fila_fim(jsonb) FROM public, anon;
REVOKE ALL ON FUNCTION public.progresso_da_fila(text, text, boolean) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.progresso_da_fila_passo(jsonb, text, text, boolean) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.progresso_da_fila_fim(jsonb) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.progresso_da_fila(text, text, boolean) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. A TV (e o painel da loja e a Gestão, que leem montar_painel)
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929240000_barra_da_fila.sql), com o diff
-- conferido: a barra vem de progresso_da_fila.
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
  v_parafazer  jsonb;
BEGIN
  SELECT nome INTO v_loja FROM public.lojas WHERE lojaid = p_lojaid AND contaid = p_contaid;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- A BARRA, o "Para fazer" e o "Em andamento" saem da MESMA fonte que o
  -- tablet e o Quadro (fila_de_hoje), numa leitura só (29/09/2026, decisão do
  -- Wisley). Antes a barra tinha regra própria: não contava missão nem
  -- compartilhada (alguém fazia e a barra não se mexia) e contava a tarefa
  -- de quem está de folga (a loja parecia pior do que foi).
  -- Toda tarefa da fila está em exatamente UM destes estados, então a conta
  -- fecha: total = aprovadas + em validação + em andamento + para fazer +
  -- ainda não liberadas (a trava da seção 19 confere).
  WITH f AS (
    SELECT q.*, d.nomecompleto AS dononome, p.nomecompleto AS quemnome,
           row_number() OVER () AS n
      FROM public.fila_de_hoje(p_contaid, p_lojaid) q
      LEFT JOIN public.funcionarios d ON d.funcionarioid = q.donoid AND d.contaid = p_contaid
      LEFT JOIN public.funcionarios p ON p.funcionarioid = q.quempegou AND p.contaid = p_contaid
  )
  -- A conta da barra: progresso_da_fila, a MESMA que o Início usa.
  SELECT public.progresso_da_fila(situacao, feitasituacao, disponivel),
         -- PARA FAZER: o que está DISPONÍVEL agora, na ordem da fila.
         coalesce(jsonb_agg(jsonb_build_object(
                    'titulo',   titulo,
                    'pessoa',   CASE WHEN aberta THEN 'a primeira que pegar leva'
                                     WHEN p_tv THEN public.nome_curto(dononome)
                                     ELSE dononome END,
                    'pontos',   pontos,
                    'atrasada', atrasada) ORDER BY n) FILTER (WHERE disponivel), '[]'::jsonb),
         -- EM ANDAMENTO: quem pegou e ainda não entregou, pela fila.
         coalesce(jsonb_agg(jsonb_build_object(
                    'titulo', titulo,
                    'pessoa', CASE WHEN p_tv THEN quempegounome ELSE quemnome END,
                    'pegaem', pegaem) ORDER BY pegaem, n) FILTER (WHERE situacao = 'em_andamento'), '[]'::jsonb)
    INTO v_dia, v_parafazer, v_andamento
    FROM f;

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

  -- Podio do dia: pontos do TRABALHO FEITO HOJE (data da entrega), ja
  -- aprovado. Antes contava a data da aprovacao: a tarefa de ontem aprovada
  -- hoje entrava no podio de hoje. Na TV, "hoje" e trabalho feito hoje.
  -- (Nao bate, e nao e para bater, com o livro de pontos do dia: o livro
  -- lanca na aprovacao e tem bonus, resgates e estornos. Ver o plano.)
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
         AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
       GROUP BY f.funcionarioid, f.nomecompleto
       ORDER BY sum(e.pontosganhos) DESC, f.nomecompleto
       LIMIT 3
    ) s;

  -- Atividade recente: o trabalho FEITO HOJE (data da entrega) que ja foi
  -- aprovado, o aprovado por ultimo primeiro. Antes seguia a data da
  -- aprovacao, e a tarefa de ontem aprovada hoje aparecia como de hoje.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pontos', pontos, 'aprovadaem', dataaprovacao,
                                               'enviadaem', dataenvio)
                            ORDER BY dataaprovacao DESC), '[]'::jsonb)
    INTO v_atividade
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataaprovacao, e.dataenvio,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
       ORDER BY e.dataaprovacao DESC
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
    'progresso',    v_dia,
    'parafazer',    v_parafazer,
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
REVOKE ALL ON FUNCTION public.montar_painel(integer, integer, boolean) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. O Início: a mesma conta, e o aviso da venda de ontem
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929242000_inicio_da_fila.sql), com o
-- diff conferido: o cartão soma por progresso_da_fila (sem 'feitas'), e os
-- avisos ganham 'vendaontem'.
CREATE OR REPLACE FUNCTION public.painel_inicio(p_lojaid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
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
             WHERE a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido
      FROM public.metasprincipais mp
     WHERE mp.lojaid = ANY (v_lojas) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*))
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
    UNION ALL
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.datarecusa))::date, 'r'
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_em_sao_paulo(e.datarecusa) BETWEEN v_mes_ini AND v_hoje
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
                            ORDER BY r.pontos DESC, r.nomecompleto), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT * FROM public.ranking_pontos(v_mes_ini, v_hoje, p_lojaid) LIMIT 5) r;

  -- Próximos agendamentos: hora, tipo e responsável (sem dados do cliente).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid
       WHERE a.lojaid = ANY (v_lojas) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
        JOIN public.lojas l        ON l.lojaid = e.lojaid
       WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC
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
                                               ORDER BY l.nome), '[]'::jsonb)
                       FROM public.lojas l
                       CROSS JOIN LATERAL (SELECT (public.meu_hoje()->>'hoje')::date - 1 AS dia) o
                       CROSS JOIN LATERAL public.meta_do_dia(l.lojaid, o.dia) md
                      WHERE l.ativa
                        AND l.criadoem < ((o.dia + 1)::timestamp AT TIME ZONE (public.meu_hoje()->>'fuso'))
                        AND coalesce(md.valormeta, 0) > 0
                        AND NOT EXISTS (SELECT 1 FROM public.metasdiariasapuracoes a
                                         WHERE a.lojaid = l.lojaid AND a.dataapuracao = o.dia)),
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
                 ORDER BY r.iniciadoem DESC LIMIT 1)),
    -- Última geração da lista de hoje (para "rodou sozinha às 00:05 ✓").
    'rotina', (SELECT jsonb_build_object('quando', coalesce(r.terminadoem, r.iniciadoem),
                                         'resultado', r.resultado, 'origem', r.origem)
                 FROM public.rotinasexecucoes r
                WHERE r.rotina = 'lista_do_dia' AND r.referencia = v_hoje
                ORDER BY r.iniciadoem DESC LIMIT 1));
END;
$$;
REVOKE ALL ON FUNCTION public.painel_inicio(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.painel_inicio(integer) TO authenticated;
