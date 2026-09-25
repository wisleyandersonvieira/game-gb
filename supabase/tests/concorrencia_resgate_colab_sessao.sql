-- Uma das duas conexoes. Pede pelo CAMINHO DO COLABORADOR e segura a
-- transacao por 2 segundos, para a outra chegar antes de esta terminar.
--
-- :pessoa e :produto vem do rodar.sh.
BEGIN;
SELECT public.eu_pedir_resgate(11, :pessoa, :produto);
SELECT pg_sleep(2);
COMMIT;
