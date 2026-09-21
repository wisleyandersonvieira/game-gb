\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '22. dois resgates ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.resgates WHERE funcionarioid = 900) = 1,
                        'duas conexoes ao mesmo tempo: so um resgate passou');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 900) = 0,
                        'o saldo nao ficou negativo (10 - 10 = 0)');
  PERFORM public.exigir((SELECT estoquedisponivel FROM public.produtosloja WHERE produtoid = 900) = 4,
                        'o estoque saiu uma vez so');
  PERFORM public.exigir((SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 900) = 0,
                        'e o extrato continua batendo com o saldo');
END $$;
