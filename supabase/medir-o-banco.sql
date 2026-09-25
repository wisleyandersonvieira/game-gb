-- =========================================================================
-- STGame — MEDIR O BANCO (24/09/2026)
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Só LÊ. Não altera nada. Pode rodar quantas vezes quiser.
--
-- Se a primeira consulta disser que pg_stat_statements não está ligada, ligue
-- em Database -> Extensions -> pg_stat_statements, use o sistema por um dia e
-- rode de novo (ela só conta o que aconteceu depois de ligada).
-- =========================================================================

-- 1. A extensão está ligada?
SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
            THEN 'ligada: pode seguir'
            ELSE 'DESLIGADA: ligue em Database -> Extensions -> pg_stat_statements'
       END AS "pg_stat_statements";

-- 2. As 15 consultas que MAIS TEMPO consomem no total (o que pesa de verdade:
--    uma consulta de 50 ms chamada 1.000 vezes pesa mais que uma de 2 s).
SELECT round(total_exec_time)::text || ' ms'            AS "tempo total",
       calls                                            AS "chamadas",
       round(mean_exec_time, 1)::text || ' ms'          AS "media",
       round(max_exec_time)::text || ' ms'              AS "pior",
       round(rows::numeric / greatest(calls, 1), 1)     AS "linhas por chamada",
       left(regexp_replace(query, '\s+', ' ', 'g'), 110) AS "consulta"
  FROM pg_stat_statements
 WHERE query NOT ILIKE '%pg_stat_statements%'
 ORDER BY total_exec_time DESC
 LIMIT 15;

-- 3. As 15 MAIS CHAMADAS (candidatas a cache no navegador).
SELECT calls                                            AS "chamadas",
       round(mean_exec_time, 1)::text || ' ms'          AS "media",
       round(total_exec_time)::text || ' ms'            AS "tempo total",
       left(regexp_replace(query, '\s+', ' ', 'g'), 110) AS "consulta"
  FROM pg_stat_statements
 WHERE query NOT ILIKE '%pg_stat_statements%'
 ORDER BY calls DESC
 LIMIT 15;

-- 4. As 10 mais LENTAS por chamada (pelo menos 20 chamadas, para não pegar
--    consulta que rodou uma vez só).
SELECT round(mean_exec_time, 1)::text || ' ms'          AS "media",
       calls                                            AS "chamadas",
       round(max_exec_time)::text || ' ms'              AS "pior",
       left(regexp_replace(query, '\s+', ' ', 'g'), 110) AS "consulta"
  FROM pg_stat_statements
 WHERE calls >= 20 AND query NOT ILIKE '%pg_stat_statements%'
 ORDER BY mean_exec_time DESC
 LIMIT 10;

-- 5. Tabelas onde o banco está lendo TUDO (varredura) em vez de usar índice.
--    Só preocupa quando a tabela tem muitas linhas.
SELECT relname                                   AS "tabela",
       n_live_tup                                AS "linhas",
       seq_scan                                  AS "varreduras inteiras",
       idx_scan                                  AS "buscas por indice",
       CASE WHEN seq_scan + coalesce(idx_scan, 0) = 0 THEN '—'
            ELSE round(100.0 * seq_scan / (seq_scan + coalesce(idx_scan, 0)))::text || '%'
       END                                       AS "% varredura"
  FROM pg_stat_user_tables
 WHERE schemaname = 'public' AND n_live_tup > 500
 ORDER BY seq_scan DESC
 LIMIT 15;

-- 6. Índices que nunca foram usados (ocupam espaço e atrasam a gravação).
SELECT relname AS "tabela", indexrelname AS "indice",
       pg_size_pretty(pg_relation_size(indexrelid)) AS "tamanho"
  FROM pg_stat_user_indexes
 WHERE schemaname = 'public' AND idx_scan = 0
 ORDER BY pg_relation_size(indexrelid) DESC
 LIMIT 15;

-- 7. Tamanho das maiores tabelas (para saber onde falta paginação).
SELECT relname AS "tabela", n_live_tup AS "linhas",
       pg_size_pretty(pg_total_relation_size(relid)) AS "tamanho"
  FROM pg_stat_user_tables
 WHERE schemaname = 'public'
 ORDER BY n_live_tup DESC
 LIMIT 15;
