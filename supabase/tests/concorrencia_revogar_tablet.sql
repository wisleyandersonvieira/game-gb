-- Conexao 2: a pessoa entrega no tablet no mesmo instante.
SET ROLE service_role;
SELECT pg_sleep(0.3);
SELECT public.visao_entregar(16, 160, 1601, 16900, NULL, 'entreguei');
