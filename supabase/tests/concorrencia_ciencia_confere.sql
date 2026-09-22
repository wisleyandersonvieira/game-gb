\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '37. duas ciencias ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos WHERE assinaturaid = 9301) = 1,
                        'os pontos da ciencia sairam uma vez so');
  PERFORM public.exigir((SELECT statusassinatura FROM public.documentosassinaturas WHERE assinaturaid = 9301) = 'Ciente',
                        'a ciencia ficou registrada');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 901)
                        = (SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 901),
                        'e o saldo bate com o livro');
END $$;
