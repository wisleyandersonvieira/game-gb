-- =========================================================================
-- STGame — SIMULAR O RODÍZIO sem esperar o tempo passar
--
-- Só para testar. Supabase -> SQL Editor -> New query -> colar -> Run.
-- Não muda regra nenhuma: só empurra para trás a hora dos aceites de hoje
-- daquela loja, como se o tempo já tivesse passado.
--
-- Antes de rodar, troque o nome da loja na linha marcada.
-- =========================================================================

DO $$
DECLARE
  -- >>> TROQUE PELO NOME DA SUA LOJA <<<
  v_loja text := 'Loja Centro';

  v_conta   integer;
  v_lojaid  integer;
  v_achadas integer;
  v_quantos integer;
BEGIN
  -- O SQL Editor roda como dono do banco, então achamos a loja pelo nome.
  SELECT count(*) INTO v_achadas
    FROM public.lojas WHERE lower(nome) = lower(btrim(v_loja));
  IF v_achadas = 0 THEN
    RAISE EXCEPTION 'Não achei a loja "%". Confira o nome em Lojas e links da TV.', v_loja;
  END IF;
  IF v_achadas > 1 THEN
    RAISE EXCEPTION 'Existe mais de uma loja chamada "%". Renomeie uma delas ou me avise.', v_loja;
  END IF;

  SELECT contaid, lojaid INTO v_conta, v_lojaid
    FROM public.lojas WHERE lower(nome) = lower(btrim(v_loja));

  UPDATE public.missoesaceites a
     SET aceitoem = a.aceitoem - interval '2 hours'
    FROM public.tarefasatribuidas ta
   WHERE ta.contaid = a.contaid AND ta.atribuicaoid = a.atribuicaoid
     AND a.contaid = v_conta
     AND ta.lojaid = v_lojaid
     AND a.dia = public.dia_em_sao_paulo(now())
     AND a.revogadoem IS NULL;
  GET DIAGNOSTICS v_quantos = ROW_COUNT;

  IF v_quantos = 0 THEN
    RAISE NOTICE 'Nenhum aceite de hoje nesta loja. Peça para alguém pegar uma tarefa no tablet e rode de novo.';
  ELSE
    RAISE NOTICE 'Pronto: % aceite(s) de hoje na loja "%" foram empurrados 2 horas para tras. A espera do rodizio acabou.',
                 v_quantos, v_loja;
  END IF;
END $$;
