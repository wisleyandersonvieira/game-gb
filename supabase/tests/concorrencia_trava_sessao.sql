-- Uma das duas conexões: tenta abrir a tentativa e segura a transação 1 s.
SET ROLE service_role;
BEGIN;
SELECT coalesce(public.tentativa_abrir(15, 'pin', repeat('t', 64), :'origem')::text, 'TRAVADA') AS resultado,
       pg_sleep(1);
COMMIT;
