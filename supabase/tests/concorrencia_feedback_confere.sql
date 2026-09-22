\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '30. dois feedbacks do mesmo dia ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.feedbacks WHERE funcionarioid = 901) = 1,
                        'so um feedback entrou');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos WHERE funcionarioid = 901 AND feedbackid IS NOT NULL) = 1,
                        'o bonus saiu uma vez so');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 901)
                        = (SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 901),
                        'e o saldo bate com o livro');
END $$;
