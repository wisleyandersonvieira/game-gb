-- Uma das duas conexoes. Aprova uma entrega (:entrega) e segura a transacao
-- aberta por 2 segundos, para a outra aprovar enquanto esta nao terminou.
SET ROLE authenticated;
SET teste.uid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN;
SELECT public.aprovar_entrega(:entrega);
SELECT pg_sleep(2);
COMMIT;
