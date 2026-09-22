-- Uma das duas conexoes: registra a ciencia e segura a transacao por 2 s.
SET ROLE authenticated;
SET teste.uid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN;
SELECT public.registrar_ciencia(9301);
SELECT pg_sleep(2);
COMMIT;
