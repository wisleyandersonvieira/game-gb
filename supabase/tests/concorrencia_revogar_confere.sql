\set ON_ERROR_STOP on
DO $$
DECLARE v_revogado boolean; v_entregas integer; v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  RAISE NOTICE '47. revogar o aceite e entregar no mesmo instante';
  SELECT EXISTS (SELECT 1 FROM public.missoesaceites
                  WHERE contaid = 16 AND atribuicaoid = 16900 AND dia = v_hoje AND revogadoem IS NOT NULL)
    INTO v_revogado;
  SELECT count(*) INTO v_entregas
    FROM public.entregas e
    JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = 16
   WHERE e.contaid = 16 AND c.origematribuicaoid = 16900
     AND e.statusvalidacao IN ('Pendente', 'Aprovada');

  -- A regra: ou a revogacao valeu (e nao existe entrega), ou a entrega valeu
  -- (e a revogacao foi recusada). As duas juntas e que nao pode.
  PERFORM public.exigir(NOT (v_revogado AND v_entregas > 0),
                        'nunca fica revogado COM entrega: uma das duas espera a outra');
  PERFORM public.exigir(v_entregas <= 1, 'a tarefa nao e entregue duas vezes');
  PERFORM public.exigir(v_revogado OR v_entregas = 1, 'uma das duas passou (nenhuma se perdeu)');
END $$;
