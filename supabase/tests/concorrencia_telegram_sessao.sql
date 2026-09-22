-- Uma das duas conexões: aprova pelo grupo de gestão e segura a transação 1 s.
SET ROLE service_role;
SELECT public.bot_validar(-13001, :usuario, 13901, true), pg_sleep(1);
