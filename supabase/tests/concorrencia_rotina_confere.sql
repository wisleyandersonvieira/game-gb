\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '38. rotinas ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.diasgerados WHERE contaid = 12) = 1,
                        'duas rodadas simultaneas geram o dia uma vez so');
  PERFORM public.exigir(NOT EXISTS (SELECT dia, atribuicaoid FROM public.tarefasdodia WHERE contaid = 12
                                     GROUP BY dia, atribuicaoid HAVING count(*) > 1)
                        AND (SELECT count(*) FROM public.tarefasdodia WHERE contaid = 12) = 3,
                        'a lista do dia nao duplica com rodadas simultaneas');
  PERFORM public.exigir((SELECT count(*) FROM public.tarefasatribuidas WHERE origematribuicaoid = 1220) = 1,
                        'a mesma tarefa passada ao mesmo tempo por duas pessoas: so uma vez');
  PERFORM public.exigir((SELECT passadapara FROM public.tarefasdodia WHERE atribuicaoid = 1220)
                        = (SELECT funcionarioid FROM public.tarefasatribuidas WHERE origematribuicaoid = 1220),
                        'a lista mostra para quem ficou');
END $$;
