-- Uma das duas conexões: pega a missão para uma pessoa e segura a transação 1 s.
SELECT set_config('teste.uid', '14141414-1414-1414-1414-141414141414', false);
SET ROLE authenticated;
SELECT public.pegar_tarefa(14900, :usuario), pg_sleep(1);
