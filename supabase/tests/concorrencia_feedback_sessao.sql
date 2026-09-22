-- Uma das duas conexoes: registra o feedback e segura a transacao por 2 s.
SET ROLE authenticated;
SET teste.uid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN;
SELECT public.registrar_feedback(901, public.dia_em_sao_paulo(now()), 7);
SELECT pg_sleep(2);
COMMIT;
