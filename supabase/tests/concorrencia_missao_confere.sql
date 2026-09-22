\set ON_ERROR_STOP on
DO $$
BEGIN
  RAISE NOTICE '41. dois cliques em "Eu aceito" ao mesmo tempo';
  PERFORM public.exigir((SELECT count(*) FROM public.missoesaceites WHERE contaid = 14 AND atribuicaoid = 14900) = 1,
                        'a missao foi aceita uma vez so');
  PERFORM public.exigir((SELECT count(*) FROM public.tarefasatribuidas
                          WHERE contaid = 14 AND origematribuicaoid = 14900) = 1,
                        'so uma tarefa de hoje foi criada');
  PERFORM public.exigir((SELECT funcionarioid FROM public.tarefasatribuidas
                          WHERE contaid = 14 AND origematribuicaoid = 14900)
                        = (SELECT funcionarioid FROM public.missoesaceites WHERE contaid = 14 AND atribuicaoid = 14900),
                        'a tarefa ficou com quem clicou primeiro');
END $$;
