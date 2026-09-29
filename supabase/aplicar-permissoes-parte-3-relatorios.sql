-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 3, fatia 5: Relatórios.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-3-inicio.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929267000_leituras_relatorios.sql
--
-- O QUE MUDA: análise de tarefas só das lojas do gerente; relatórios de uma pessoa
-- só de quem está inteiro nas lojas dele, e só o que aconteceu nelas. Para o
-- master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 3, fatia 4: Relatórios por loja (29/09/2026).
--
-- Análise de tarefas: só as lojas em que o gerente pode ver os relatórios.
-- Relatórios de UMA pessoa (histórico, pendências, tarefas pegas): só de quem
-- está INTEIRO nas lojas dele (a mesma régua das ações sobre a pessoa), e só o
-- que aconteceu nessas lojas. O master segue pelo caminho de sempre.

-- ---------------------------------------------------------------------------
-- Análise de tarefas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.analise_de_tarefas_gerente(p_de date, p_ate date, p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta, public.fuso_da_conta(public.conta_do_gerente()) AS fuso,
                      ARRAY(SELECT x FROM unnest(public.lojas_onde_posso('relatorios.ver')) x
                             WHERE p_lojaid IS NULL OR x = p_lojaid) AS lojas),
  ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM ctx JOIN public.entregas e ON e.contaid = ctx.conta AND e.lojaid = ANY (ctx.lojas)
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_no_fuso(e.dataenvio, ctx.fuso) BETWEEN p_de AND p_ate
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM ctx
      JOIN public.justificativas j     ON j.contaid = ctx.conta AND j.lojaid = ANY (ctx.lojas)
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid AND ta.contaid = ctx.conta
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo, t.tarefaid), '[]'::jsonb)
    FROM juntos j
    JOIN ctx ON true
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid AND t.contaid = ctx.conta
$$;
REVOKE ALL ON FUNCTION public.analise_de_tarefas_gerente(date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.analise_de_tarefas_gerente(date, date, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- Histórico da pessoa
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.historico_da_pessoa_gerente(p_funcionarioid integer, p_limite integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta, public.lojas_onde_posso('relatorios.ver') AS lojas)
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT e.dataenvio AS ds, e.entregaid AS id,
             jsonb_build_object('titulo', t.titulo, 'loja', l.nome, 'enviadaem', e.dataenvio,
                                'status', e.statusvalidacao, 'pontos', e.pontosganhos,
                                'motivo', coalesce(e.motivorecusa, e.motivoestorno)) AS x
        FROM ctx
        JOIN public.entregas e   ON e.contaid = ctx.conta AND e.funcionarioid = p_funcionarioid
                                AND e.lojaid = ANY (ctx.lojas)
        JOIN public.tarefas t    ON t.tarefaid = e.tarefaid AND t.contaid = ctx.conta
        LEFT JOIN public.lojas l ON l.lojaid = e.lojaid AND l.contaid = ctx.conta
       WHERE ctx.conta IS NOT NULL AND e.atribuicaoid IS NOT NULL
         AND public.pode_na_pessoa('relatorios.ver', ctx.conta, p_funcionarioid)
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 500))
    ) s
$$;
REVOKE ALL ON FUNCTION public.historico_da_pessoa_gerente(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_da_pessoa_gerente(integer, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- Pendências da pessoa (o que era devido e não foi entregue nem justificado)
-- ---------------------------------------------------------------------------
-- A mesma regra da versão de sempre, com a conta escrita em cada tabela, o dia
-- da conta (nunca o relógio de São Paulo à mão) e só as lojas dele.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa_gerente(p_funcionarioid integer, p_de date, p_ate date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta, public.fuso_da_conta(public.conta_do_gerente()) AS fuso,
                      public.lojas_onde_posso('relatorios.ver') AS lojas),
  ok AS (SELECT ctx.* FROM ctx
          WHERE ctx.conta IS NOT NULL AND public.pode_na_pessoa('relatorios.ver', ctx.conta, p_funcionarioid)),
  lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.hoje_da_conta(ok.conta) - 1) AS fim
      FROM ok
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, lim, ok
     WHERE dg.contaid = ok.conta AND dg.dia BETWEEN lim.ini AND lim.fim
  ),
  itens AS (
    SELECT i.dia, i.atribuicaoid, i.tipofrequencia, t.titulo, i.pontos, l.nome AS loja
      FROM ok
      JOIN public.tarefasdodia i ON i.contaid = ok.conta AND i.lojaid = ANY (ok.lojas)
      JOIN gerados g             ON g.dia = i.dia
      JOIN public.tarefas t      ON t.tarefaid = i.tarefaid AND t.contaid = ok.conta
      LEFT JOIN public.lojas l   ON l.lojaid = i.lojaid AND l.contaid = ok.conta
     WHERE i.funcionarioid = p_funcionarioid
       AND i.situacao = 'devida'
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.contaid = ok.conta AND e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_no_fuso(e.dataenvio, ok.fuso) = i.dia))
    UNION ALL
    SELECT g.d::date, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM ok
      JOIN public.tarefasatribuidas ta ON ta.contaid = ok.conta AND ta.lojaid = ANY (ok.lojas)
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid AND t.contaid = ok.conta
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid AND f.contaid = ok.conta
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid AND l.contaid = ok.conta
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_no_fuso(ta.dataatribuicao, ok.fuso), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date, ok.fuso)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.contaid = ok.conta AND e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_no_fuso(e.dataenvio, ok.fuso) = g.d::date)
    UNION ALL
    SELECT public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ok.fuso), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM ok
      JOIN public.tarefasatribuidas ta ON ta.contaid = ok.conta AND ta.lojaid = ANY (ok.lojas)
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid AND t.contaid = ok.conta
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid AND l.contaid = ok.conta
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ok.fuso) BETWEEN lim.ini AND lim.fim
       AND public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ok.fuso) NOT IN (SELECT dia FROM gerados)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.contaid = ok.conta AND e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo, i.atribuicaoid), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
$$;
REVOKE ALL ON FUNCTION public.pendencias_da_pessoa_gerente(integer, date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pendencias_da_pessoa_gerente(integer, date, date) TO authenticated;

-- analise_de_tarefas: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.analise_de_tarefas(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.analise_de_tarefas_gerente(p_de, p_ate, p_lojaid)
           ELSE (
  WITH ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM public.entregas e
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM public.justificativas j
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR j.lojaid = p_lojaid)
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo, t.tarefaid), '[]'::jsonb)
    FROM juntos j
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid
           ) END
$function$;

-- historico_da_pessoa: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.historico_da_pessoa(p_funcionarioid integer, p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.historico_da_pessoa_gerente(p_funcionarioid, p_limite)
           ELSE (
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT e.dataenvio AS ds, e.entregaid AS id,
             jsonb_build_object('titulo', t.titulo, 'loja', l.nome, 'enviadaem', e.dataenvio,
                                'status', e.statusvalidacao, 'pontos', e.pontosganhos,
                                'motivo', coalesce(e.motivorecusa, e.motivoestorno)) AS x
        FROM public.entregas e
        JOIN public.tarefas t    ON t.tarefaid = e.tarefaid
        LEFT JOIN public.lojas l ON l.lojaid = e.lojaid
       WHERE e.funcionarioid = p_funcionarioid AND e.atribuicaoid IS NOT NULL
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 500))
    ) s
           ) END
$function$;

-- pendencias_da_pessoa: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.pendencias_da_pessoa_gerente(p_funcionarioid, p_de, p_ate)
           ELSE (
  WITH lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.dia_em_sao_paulo(now()) - 1) AS fim
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, lim
     WHERE dg.contaid = public.minha_conta() AND dg.dia BETWEEN lim.ini AND lim.fim
  ),
  itens AS (
    -- Dias com lista congelada.
    SELECT i.dia, i.atribuicaoid, i.tipofrequencia, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN gerados g           ON g.dia = i.dia
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid
     WHERE i.funcionarioid = p_funcionarioid
       AND i.situacao = 'devida'
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = i.dia))
    UNION ALL
    -- Dias sem lista: regra do cadastro.
    SELECT g.d::date, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_em_sao_paulo(e.dataenvio) = g.d::date)
    UNION ALL
    SELECT public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN lim.ini AND lim.fim
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) NOT IN (SELECT dia FROM gerados)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo, i.atribuicaoid), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
           ) END
$function$;

-- tarefas_pegas_da_pessoa: parte da versão viva; o gerente lê só as lojas dele.
CREATE OR REPLACE FUNCTION public.tarefas_pegas_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS TABLE(dia date, titulo character varying, pontos integer, loja character varying, entregue boolean, revogadoem timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Ramo do gerente (parte 3): a conta dele, só de quem está inteiro nas lojas
  -- dele, e só as tarefas dessas lojas.
  WITH ctx AS (SELECT coalesce(public.minha_conta(), public.conta_do_gerente()) AS conta,
                      public.minha_conta() IS NULL AS gerente)
  SELECT a.dia, t.titulo, t.pontos, l.nome,
         EXISTS (SELECT 1 FROM public.entregas e
                  WHERE e.contaid = ctx.conta AND e.atribuicaoid = a.novaatribuicaoid
                    AND e.statusvalidacao IN ('Pendente', 'Aprovada')),
         a.revogadoem
    FROM ctx
    JOIN public.missoesaceites a     ON a.contaid = ctx.conta AND a.funcionarioid = p_funcionarioid
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.atribuicaoid = a.novaatribuicaoid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    LEFT JOIN public.lojas l         ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND (NOT ctx.gerente OR (public.pode_na_pessoa('relatorios.ver', ctx.conta, p_funcionarioid)
                              AND ta.lojaid = ANY (public.lojas_onde_posso('relatorios.ver'))))
     AND a.novaatribuicaoid IS NOT NULL
     AND a.dia BETWEEN p_de AND p_ate
   ORDER BY a.dia DESC, t.titulo, a.aceiteid
$function$;

COMMIT;
