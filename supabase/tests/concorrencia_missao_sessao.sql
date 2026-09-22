-- Uma das duas conexões: aceita a missão e segura a transação 1 s.
SET ROLE service_role;
SELECT public.bot_pegar_missao(-14001, :usuario, 14900), pg_sleep(1);
