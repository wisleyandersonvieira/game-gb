-- Etapa 1.10B: tela "Início" do gestor.
--
-- painel_inicio(p_lojaid) devolve, num só JSON, os números da tela Início:
-- cartões, gráficos, listas e o guia de primeiros passos.
--
-- Segurança:
--   * SECURITY INVOKER: roda com a permissão de quem chamou, então a RLS de
--     cada tabela filtra a conta (contaid = minha_conta()). Não há como ler
--     outra conta, nem passando a loja de outra conta (vira "Loja não
--     encontrada").
--   * Nada de CPF, telefone, cliente final ou documento pessoal.
--   * "Hoje", "semana" e "mês" sempre no fuso America/Sao_Paulo.
--   * Só leitura: não muda regra, saldo nem tabela.

-- Índices para a tela abrir rápido mesmo com anos de histórico.
CREATE INDEX IF NOT EXISTS entregas_pendentes_idx
  ON public.entregas (contaid, lojaid, dataenvio) WHERE statusvalidacao = 'Pendente';
CREATE INDEX IF NOT EXISTS entregas_recusa_idx
  ON public.entregas (contaid, datarecusa) WHERE statusvalidacao = 'Recusada';
CREATE INDEX IF NOT EXISTS movimentospontos_conta_data_idx
  ON public.movimentospontos (contaid, datamovimento);
CREATE INDEX IF NOT EXISTS agendamentos_conta_data_idx
  ON public.agendamentos (contaid, dataevento);
CREATE INDEX IF NOT EXISTS documentosassinaturas_pendentes_idx
  ON public.documentosassinaturas (contaid, documentoid) WHERE statusassinatura = 'Pendente';

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

  -- Tarefas de hoje (mesma regra do painel da loja).
  WITH dia AS (
    SELECT (SELECT e.statusvalidacao
              FROM public.entregas e
             WHERE e.atribuicaoid = ta.atribuicaoid
               AND e.statusvalidacao IN ('Pendente', 'Aprovada')
               AND public.dia_em_sao_paulo(e.dataenvio) = v_hoje
             ORDER BY e.entregaid DESC
             LIMIT 1) AS situacao
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid
      JOIN public.funcionarioslojas fl ON fl.funcionarioid = ta.funcionarioid AND fl.lojaid = ta.lojaid
     WHERE ta.lojaid = ANY (v_lojas)
       AND ta.datafimvigencia IS NULL
       AND f.ativo AND fl.ativo AND coalesce(t.ativa, true)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
       AND NOT (ta.tipofrequencia = 'Unica' AND EXISTS (
             SELECT 1 FROM public.entregas e2
              WHERE e2.atribuicaoid = ta.atribuicaoid
                AND e2.statusvalidacao IN ('Pendente', 'Aprovada')
                AND public.dia_em_sao_paulo(e2.dataenvio) < v_hoje))
  )
  SELECT jsonb_build_object(
           'total',       count(*),
           'feitas',      count(*) FILTER (WHERE situacao IS NOT NULL),
           'aprovadas',   count(*) FILTER (WHERE situacao = 'Aprovada'),
           'emvalidacao', count(*) FILTER (WHERE situacao = 'Pendente'))
    INTO v_tarefas
    FROM dia;

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
    'guia',         v_guia);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.painel_inicio(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.painel_inicio(integer) TO authenticated;
