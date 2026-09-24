-- Conexao 1: o gestor revoga e segura a transacao 1 s.
SET ROLE service_role;
BEGIN;
SELECT set_config('stgame.bot_conta', '16', true);
SELECT public.revogar_aceite(16900, public.dia_em_sao_paulo(now()), 'troquei quem faz');
SELECT pg_sleep(1);
COMMIT;
