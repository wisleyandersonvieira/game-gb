\set ON_ERROR_STOP on
DO $$
DECLARE v_hoje integer;
BEGIN
  RAISE NOTICE '42. duas tentativas no mesmo instante, no limite da trava';
  SELECT count(*) INTO v_hoje FROM public.tentativasacesso
   WHERE contaid = 15 AND tipo = 'pin' AND chave = repeat('t', 64) AND em > now() - interval '1 day';
  -- 29 do preparo + no maximo 1 das duas conexoes.
  PERFORM public.exigir(v_hoje = 30,
    'com duas tentativas no mesmo instante, so uma passa (o teto do dia vale mesmo em rajada); registradas: ' || v_hoje);
END $$;
DELETE FROM public.tentativasacesso WHERE contaid = 15;
DELETE FROM public.configuracoes WHERE contaid = 15;
DELETE FROM public.contas WHERE contaid = 15;
