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
