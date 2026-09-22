\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '39. duas aprovacoes pelo Telegram ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos WHERE entregaid = 13901 AND tipo = 'aprovacao') = 1,
                        'a entrega foi aprovada uma vez so (um movimento no livro)');
  PERFORM public.exigir((SELECT statusvalidacao FROM public.entregas WHERE entregaid = 13901) = 'Aprovada',
                        'a entrega ficou aprovada');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 1301) = 7,
                        'o saldo recebeu os pontos uma vez');
END $$;
