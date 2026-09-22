\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '34. dois lancamentos da meta ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.metasdiariasapuracoes WHERE lojaid = 90) = 1,
                        'um lancamento so para o dia');
  PERFORM public.exigir((SELECT count(*) FROM public.metaspremiacoes WHERE lojaid = 90) = 1,
                        'o premio da meta saiu uma vez so');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos WHERE funcionarioid = 901 AND premiacaoid IS NOT NULL) = 1,
                        'Davi recebeu os pontos da meta uma vez so');
  PERFORM public.exigir((SELECT count(*) FROM public.metashistorico WHERE lojaid = 90) = 2,
                        'o historico tem o lancamento e a correcao');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 901)
                        = (SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 901),
                        'e o saldo bate com o livro');
END $$;
