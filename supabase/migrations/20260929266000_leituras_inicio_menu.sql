-- Usuários gerenciais, PARTE 3, fatia 3: o Início e as bolinhas do menu por
-- loja (29/09/2026).
--
-- O master segue pelo caminho de sempre. O gerente é desviado, no começo, para
-- versões que leem só as lojas em que ele pode ver o Início (inicio.ver), e
-- cada cartão ainda pede a permissão da tela dele:
--   meta, vendas (R$) ....... metas.ver + valores.ver_rs
--   agenda .................. agenda.ver
--   solicitações ............ solicitacoes.ver
--   justificativas .......... justificativas.ver
--   comunicados, onboarding . comunicados.ver / onboarding.ver, contando só
--                             quem está INTEIRO nas lojas dele
-- O que é da conta inteira (guia de primeiros passos, conferência do livro,
-- rotina da lista) não vai para o gerente. Bolinhas do menu: cada uma conta só
-- o que ele pode abrir, nas lojas dele (regra 4).

CREATE OR REPLACE FUNCTION public.painel_inicio_gerente(p_lojaid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
     AND l.lojaid = ANY (public.lojas_onde_posso('inicio.ver'))
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
    UNION ALL
    SELECT date_trunc('week', public.dia_no_fuso(e.datarecusa, v_fuso))::date, 'r'
      FROM public.entregas e
     WHERE e.contaid = v_conta AND e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_no_fuso(e.datarecusa, v_fuso) BETWEEN v_mes_ini AND v_hoje
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
$$;
REVOKE ALL ON FUNCTION public.painel_inicio_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.painel_inicio_gerente(integer) TO authenticated;

-- painel_inicio: parte da versão viva; muda só o desvio do gerente.
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

-- tarefas_nao_pegas: parte da versão viva; o gerente lê só as lojas dele.
CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(atribuicaoid integer, lojaid integer, loja character varying, titulo character varying, pontos integer, atribuidos text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Ramo do gerente (parte 3): sem conta de master, a conta do gerente, e só
  -- as lojas em que ele pode ver o Início.
  WITH ctx AS (SELECT coalesce(public.minha_conta(), public.conta_do_gerente()) AS conta,
                      public.hoje_da_conta(coalesce(public.minha_conta(), public.conta_do_gerente())) AS dia,
                      public.fuso_da_conta(coalesce(public.minha_conta(), public.conta_do_gerente())) AS fuso,
                      public.minha_conta() IS NULL AS gerente)
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
     AND (NOT ctx.gerente OR ta.lojaid = ANY (public.lojas_onde_posso('inicio.ver')))
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo, ta.atribuicaoid
$function$;

-- As bolinhas do menu do gerente: cada uma conta só o que ele pode abrir,
-- nas lojas dele. Resgate sem loja não conta (é da conta inteira).
CREATE OR REPLACE FUNCTION public.contagem_do_menu_gerente()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT jsonb_build_object(
    'entregas', (SELECT count(*) FROM public.entregas e
                   JOIN public.lojas l ON l.lojaid = e.lojaid AND l.contaid = ctx.conta AND l.ativa
                  WHERE e.contaid = ctx.conta AND e.statusvalidacao = 'Pendente'
                    AND e.lojaid = ANY (public.lojas_onde_posso('quadro.ver'))),
    'resgates', (SELECT count(*) FROM public.resgates r
                  WHERE r.contaid = ctx.conta AND r.status = 'Pendente'
                    AND r.lojaid = ANY (public.lojas_onde_posso('premios.ver'))),
    'solicitacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('loja', c.loja, 'situacao', c.situacao, 'quantos', c.quantos))
                                FROM (SELECT s.lojaid AS loja, s.status::text AS situacao, count(*)::integer AS quantos
                                        FROM public.solicitacoesinternas s
                                        JOIN public.lojas l ON l.lojaid = s.lojaid AND l.contaid = ctx.conta AND l.ativa
                                       WHERE s.contaid = ctx.conta AND s.status IN ('Aberta', 'Em andamento')
                                         AND s.lojaid = ANY (public.lojas_onde_posso('solicitacoes.ver'))
                                       GROUP BY s.lojaid, s.status) c), '[]'::jsonb))
    FROM ctx
   WHERE ctx.conta IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.contagem_do_menu_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.contagem_do_menu_gerente() TO authenticated;

-- contagem_do_menu: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.contagem_do_menu()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.contagem_do_menu_gerente()
           ELSE (
  SELECT jsonb_build_object(
    -- Quadro: entregas esperando aprovação, nas lojas ativas.
    'entregas', (SELECT count(*) FROM public.entregas e
                   JOIN public.lojas l ON l.lojaid = e.lojaid AND l.ativa
                  WHERE e.statusvalidacao = 'Pendente'),
    -- Prêmios: pedidos de resgate esperando o gestor (a mesma conta de antes).
    'resgates', (SELECT count(*) FROM public.resgates r WHERE r.status = 'Pendente'),
    -- Solicitações: por loja e situação (o menu soma; as abas usam por loja).
    'solicitacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('loja', c.loja, 'situacao', c.situacao, 'quantos', c.quantos))
                                FROM public.contagem_solicitacoes() c), '[]'::jsonb))
           ) END
$function$;
