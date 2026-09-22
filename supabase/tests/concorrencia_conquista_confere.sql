\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '29. duas aprovacoes ao mesmo tempo, uma conquista';
  PERFORM public.exigir((SELECT count(*) FROM public.entregas WHERE funcionarioid = 901 AND statusvalidacao = 'Aprovada') = 2,
                        'as duas entregas foram aprovadas');
  PERFORM public.exigir((SELECT count(*) FROM public.conquistasfuncionarios WHERE funcionarioid = 901) = 1,
                        'a conquista foi concedida uma vez so');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos WHERE funcionarioid = 901 AND tipo = 'bonus') = 1,
                        'o bonus saiu uma vez so');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 901) = 2 + 3 + 50,
                        'saldo = 2 + 3 de tarefas + 50 de bonus');
  PERFORM public.exigir((SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 901) = 55,
                        'e o extrato continua batendo com o saldo');
END $$;
