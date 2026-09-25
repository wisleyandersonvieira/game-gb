-- O que tem de ser verdade depois das duas corridas.
DO $$
DECLARE v_n integer; v_saldo integer; v_soma integer;
BEGIN
  -- (a) DOIS TOQUES RAPIDOS: com 30 pontos e premio de 30, so UM pedido entra.
  SELECT count(*) INTO v_n FROM public.resgates
   WHERE contaid = 11 AND funcionarioid = 910 AND produtoid = 910;
  PERFORM public.exigir(v_n = 1, 'dois toques rapidos criam UM resgate so (foram ' || v_n || ')');

  -- E os pontos sairam uma vez so.
  SELECT count(*) INTO v_n FROM public.movimentospontos
   WHERE contaid = 11 AND funcionarioid = 910 AND tipo = 'resgate';
  PERFORM public.exigir(v_n = 1, 'e os pontos saem uma vez so');

  -- (b) ESTOQUE 1, dois pedidos ao mesmo tempo: so um passa.
  SELECT count(*) INTO v_n FROM public.resgates
   WHERE contaid = 11 AND produtoid = 911;
  PERFORM public.exigir(v_n = 1, 'com estoque 1, so um pedido passa (foram ' || v_n || ')');
  SELECT estoquedisponivel INTO v_n FROM public.produtosloja WHERE produtoid = 911;
  PERFORM public.exigir(v_n = 0, 'e o estoque fica em zero, nunca negativo');

  -- O livro fecha para as duas pessoas: soma dos movimentos = saldo.
  FOR v_n IN SELECT unnest(ARRAY[910, 912, 913]) LOOP
    SELECT saldopontos INTO v_saldo FROM public.funcionarios WHERE funcionarioid = v_n;
    SELECT coalesce(sum(pontos), 0) INTO v_soma FROM public.movimentospontos
     WHERE contaid = 11 AND funcionarioid = v_n;
    PERFORM public.exigir(v_saldo = v_soma,
                          'o extrato fecha com o saldo de ' || v_n || ' depois da corrida');
  END LOOP;
END $$;
