-- =========================================================================
-- STGame — MEDIR O BANCO
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Só LÊ. Não altera nada. Pode rodar quantas vezes quiser.
--
-- O editor mostra o resultado da ÚLTIMA consulta. Para ver as outras,
-- selecione o bloco que quiser (do "-- N." até o ";") e clique em Run.
--
-- A ordem é de propósito: as partes 1 a 4 funcionam sempre. As partes 5 a 7
-- dependem da extensão pg_stat_statements; se ela estiver desligada, o editor
-- vai parar ali com "relation pg_stat_statements does not exist" — e o que veio
-- antes já é útil. Para ligar: Database -> Extensions -> pg_stat_statements,
-- usar o sistema por um dia e rodar de novo (ela só conta o que acontece
-- depois de ligada).
-- =========================================================================

-- No Supabase as extensões moram no esquema "extensions".
SET search_path = public, extensions;

-- -------------------------------------------------------------------------
-- 1. A extensão de estatísticas está ligada?
-- -------------------------------------------------------------------------
SELECT CASE WHEN e.extname IS NULL
            THEN 'DESLIGADA - as partes 5, 6 e 7 nao vao rodar. Ligue em Database -> Extensions -> pg_stat_statements'
            ELSE 'ligada, no esquema ' || n.nspname || ' - pode seguir ate o fim'
       END AS "pg_stat_statements"
  FROM (SELECT 1) x
  LEFT JOIN pg_extension e ON e.extname = 'pg_stat_statements'
  LEFT JOIN pg_namespace n ON n.oid = e.extnamespace;

-- -------------------------------------------------------------------------
-- 2. Tamanho das maiores tabelas (onde pode faltar paginação)
-- -------------------------------------------------------------------------
SELECT relname                                       AS "tabela",
       n_live_tup                                    AS "linhas",
       pg_size_pretty(pg_total_relation_size(relid)) AS "tamanho"
  FROM pg_stat_user_tables
 WHERE schemaname = 'public'
 ORDER BY n_live_tup DESC
 LIMIT 15;

-- -------------------------------------------------------------------------
-- 3. Tabelas sendo lidas INTEIRAS em vez de por índice
--    (só preocupa quando a tabela já tem muitas linhas)
-- -------------------------------------------------------------------------
SELECT relname                           AS "tabela",
       n_live_tup                        AS "linhas",
       coalesce(seq_scan, 0)             AS "leituras inteiras",
       coalesce(idx_scan, 0)             AS "buscas por indice",
       CASE WHEN coalesce(seq_scan, 0) + coalesce(idx_scan, 0) = 0 THEN '-'
            ELSE round(100.0 * coalesce(seq_scan, 0)
                       / (coalesce(seq_scan, 0) + coalesce(idx_scan, 0)))::text || '%'
       END                               AS "% inteiras"
  FROM pg_stat_user_tables
 WHERE schemaname = 'public' AND n_live_tup > 500
 ORDER BY seq_scan DESC NULLS LAST
 LIMIT 15;

-- -------------------------------------------------------------------------
-- 4. Índices que nunca foram usados (ocupam espaço e atrasam a gravação)
-- -------------------------------------------------------------------------
SELECT relname                                      AS "tabela",
       indexrelname                                 AS "indice",
       pg_size_pretty(pg_relation_size(indexrelid)) AS "tamanho"
  FROM pg_stat_user_indexes
 WHERE schemaname = 'public' AND coalesce(idx_scan, 0) = 0
 ORDER BY pg_relation_size(indexrelid) DESC
 LIMIT 15;

-- =========================================================================
-- Daqui para baixo precisa da extensão pg_stat_statements.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 5. As 15 consultas que MAIS TEMPO consomem no total
--    (é o que pesa de verdade: uma de 50 ms chamada 1.000 vezes pesa mais
--     que uma de 2 s chamada uma vez)
-- -------------------------------------------------------------------------
SELECT round(total_exec_time::numeric)::text || ' ms'    AS "tempo total",
       calls                                             AS "chamadas",
       round(mean_exec_time::numeric, 1)::text || ' ms'  AS "media",
       round(max_exec_time::numeric)::text || ' ms'      AS "pior",
       round(rows::numeric / greatest(calls, 1), 1)      AS "linhas por chamada",
       left(regexp_replace(query, '\s+', ' ', 'g'), 110)  AS "consulta"
  FROM pg_stat_statements
 WHERE query NOT ILIKE '%pg_stat_statements%'
 ORDER BY total_exec_time DESC
 LIMIT 15;

-- -------------------------------------------------------------------------
-- 6. As 15 MAIS CHAMADAS (candidatas a guardar no navegador)
-- -------------------------------------------------------------------------
SELECT calls                                             AS "chamadas",
       round(mean_exec_time::numeric, 1)::text || ' ms'  AS "media",
       round(total_exec_time::numeric)::text || ' ms'    AS "tempo total",
       left(regexp_replace(query, '\s+', ' ', 'g'), 110)  AS "consulta"
  FROM pg_stat_statements
 WHERE query NOT ILIKE '%pg_stat_statements%'
 ORDER BY calls DESC
 LIMIT 15;

-- -------------------------------------------------------------------------
-- 7. As 10 mais LENTAS por chamada (com pelo menos 20 chamadas, para não
--    pegar consulta que rodou uma vez só)
-- -------------------------------------------------------------------------
SELECT round(mean_exec_time::numeric, 1)::text || ' ms'  AS "media",
       calls                                             AS "chamadas",
       round(max_exec_time::numeric)::text || ' ms'      AS "pior",
       left(regexp_replace(query, '\s+', ' ', 'g'), 110)  AS "consulta"
  FROM pg_stat_statements
 WHERE calls >= 20 AND query NOT ILIKE '%pg_stat_statements%'
 ORDER BY mean_exec_time DESC
 LIMIT 10;
