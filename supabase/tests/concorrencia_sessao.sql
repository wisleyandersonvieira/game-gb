-- Uma das duas conexoes. Resgata e segura a transacao aberta por 2 segundos,
-- para a outra conexao chegar enquanto esta ainda nao terminou.
SET ROLE authenticated;
SET teste.uid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN;
SELECT public.registrar_troca(900, 900, NULL, true);
SELECT pg_sleep(2);
COMMIT;
