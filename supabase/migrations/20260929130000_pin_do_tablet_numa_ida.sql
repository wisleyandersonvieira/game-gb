-- O aceite e a entrega pelo tablet numa ida só ao banco (26/09/2026).
--
-- O que foi medido (Postgres 17 local, 60 contas, 6 mil pessoas, 200 mil
-- tentativas de PIN na semana):
--
--   * A TRAVA de tentativas levava ~70 ms por PIN digitado. Ela contava os
--     erros com `contaid IS NOT DISTINCT FROM`, que índice nenhum atende, e
--     comparava a coluna char(64) com text. Resultado: três varreduras da
--     tabela INTEIRA de tentativas, de todos os clientes. Piora com cada
--     cliente novo do STGame, não com o tamanho da loja.
--   * A busca do PIN tinha índice (`funcionarios_pin_unico_na_conta`), mas não
--     o usava: o parâmetro chegava como text e a coluna é char(64), então o
--     banco convertia a coluna de cada pessoa da conta e comparava uma a uma.
--   * O pior, porém, não era o banco: eram as IDAS. O servidor fazia seis
--     viagens em fila por aceite (quem é o tablet, de novo quem é o tablet,
--     abre a trava, confere o PIN, fecha a trava, pega a tarefa), e o tablet
--     ainda recarregava a fila depois, com mais cinco. Com o Supabase nos
--     EUA, ~150 ms cada.
--
-- O que muda:
--   1. A trava e a busca do PIN passam a usar índice (mesma regra, mesmo
--      resultado; só deixam de varrer).
--   2. `visao_tablet_do_usuario`: quem é este tablet, numa consulta só.
--   3. `visao_pegar_com_pin` e `visao_entregar_com_pin`: numa transação só,
--      abrem a trava, acham a pessoa, fecham a trava, fazem o aceite ou a
--      entrega (com o rodízio e todas as regras de sempre) e devolvem a fila
--      já atualizada. Ninguém se mete entre conferir o PIN e gravar.
--
-- O que NÃO muda:
--   * O PIN é conferido no servidor a cada ação. Nada fica guardado.
--   * A trava conta TODA tentativa. A tentativa é gravada antes de qualquer
--     outra coisa e nunca é desfeita: o erro de uma regra (rodízio, tarefa já
--     pega) é devolvido como resposta, e não como exceção, justamente para a
--     transação terminar gravada.
--   * As funções antigas (`visao_pegar`, `visao_entregar`,
--     `visao_pessoa_do_pin`) continuam: as novas as chamam por dentro, então
--     a regra de negócio segue num lugar só.

-- ---------------------------------------------------------------------------
-- 1. A trava de tentativas passa a usar índice
-- ---------------------------------------------------------------------------
-- Os índices antigos começam por `contaid`, que só serve para `contaid = X`.
-- A trava precisa aceitar conta vazia (tentativa de senha de e-mail que não
-- achou conta), por isso compara `coalesce(contaid, 0)`: nenhuma conta tem o
-- número 0. Os antigos ficam, porque outras consultas usam `contaid = X`.
CREATE INDEX IF NOT EXISTS tentativasacesso_conta0_chave_idx
  ON public.tentativasacesso ((coalesce(contaid, 0)), tipo, chave, em DESC);
CREATE INDEX IF NOT EXISTS tentativasacesso_conta0_origem_idx
  ON public.tentativasacesso ((coalesce(contaid, 0)), tipo, origem, em DESC);
-- A faxina de 7 dias roda a cada tentativa: sem isto, ela também varria.
CREATE INDEX IF NOT EXISTS tentativasacesso_em_idx
  ON public.tentativasacesso (em);

-- Parte da versão mais recente (20260929100800), com o diff conferido: só
-- mudam a comparação da conta e o tipo da chave.
CREATE OR REPLACE FUNCTION public.tentativa_abrir_ex(p_contaid integer, p_tipo text,
                                                     p_chave text, p_origem text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_minutos integer;
  v_janela  interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave   text     := left(coalesce(p_chave, ''), 64);
  -- Do MESMO tipo das colunas. Comparar a coluna char(64) com text obriga o
  -- banco a converter a coluna linha a linha, e com `IS NOT DISTINCT FROM` a
  -- conta também não entra no índice: a trava varria as tentativas de TODAS
  -- as contas, três vezes por PIN digitado (medido em 26/09/2026: 70 ms com
  -- 200 mil tentativas na semana, crescendo com o número de clientes).
  v_chavefixa char(64) := left(coalesce(p_chave, ''), 64);
  v_conta0    integer  := coalesce(p_contaid, 0);
  v_origem  text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros   integer;
  v_outros  integer;
  v_esperar integer  := 0;
  v_id      bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tipo NOT IN ('senha', 'pin', 'tablet', 'pintablet', 'lojamanual', 'tvcodigo') THEN
    RAISE EXCEPTION 'Tipo de tentativa inválido.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- ---- Login da loja com senha DIGITADA: atraso, nunca bloqueio ----------
  -- Bloquear devolveria o problema que fez a trava ser desligada na parte A:
  -- o engraçadinho erra de propósito e a loja fica sem sistema. O atraso
  -- castiga quem adivinha e não tira a loja do ar.
  IF p_tipo = 'lojamanual' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = 'lojamanual' AND t.chave = v_chavefixa
       AND NOT t.sucesso AND t.em > now() - interval '15 minutes'
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE coalesce(s.contaid, 0) = v_conta0 AND s.tipo = 'lojamanual'
                               AND s.chave = v_chavefixa AND s.sucesso), '-infinity'::timestamptz);
    v_outros := 0;
    IF v_origem <> 'sem-ip' THEN
      SELECT count(*) INTO v_outros FROM public.tentativasacesso t
       WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = 'lojamanual' AND t.origem = v_origem
         AND NOT t.sucesso AND t.em > now() - interval '15 minutes'
         AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                               WHERE coalesce(s.contaid, 0) = v_conta0 AND s.tipo = 'lojamanual'
                                 AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    END IF;
    v_erros := greatest(v_erros, v_outros);
    IF v_erros > 0 THEN
      v_esperar := least(500 * (2 ^ least(v_erros - 1, 10))::integer, 10000);
    END IF;

    INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
    VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
    RETURNING tentativaid INTO v_id;
    DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
    RETURN jsonb_build_object('tentativaid', v_id, 'esperar', v_esperar);
  END IF;

  -- ---- Os outros tipos, como já eram --------------------------------------
  -- Quando a trava fecha, ela diz QUANTOS MINUTOS faltam: no balcao, "espere
  -- um pouco" nao ajuda ninguem. O tempo e ate a tentativa mais antiga sair
  -- da janela de 24 horas.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = 'pin' AND t.chave = v_chavefixa
       AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      SELECT greatest(1, ceil(extract(epoch FROM (min(t.em) + interval '1 day') - now()) / 60)::integer)
        INTO v_minutos
        FROM public.tentativasacesso t
       WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = 'pin' AND t.chave = v_chavefixa
         AND t.em > now() - interval '1 day';
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0, 'minutos', v_minutos);
    END IF;
  END IF;

  IF p_tipo = 'pintablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = 'pintablet' AND t.chave = v_chavefixa
       AND NOT t.sucesso AND t.em > now() - interval '1 day';
    IF v_erros >= 20 THEN
      SELECT greatest(1, ceil(extract(epoch FROM (min(t.em) + interval '1 day') - now()) / 60)::integer)
        INTO v_minutos
        FROM public.tentativasacesso t
       WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = 'pintablet' AND t.chave = v_chavefixa
         AND NOT t.sucesso AND t.em > now() - interval '1 day';
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0, 'minutos', v_minutos);
    END IF;
  END IF;

  IF p_tipo <> 'tablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = p_tipo AND t.chave = v_chavefixa
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE coalesce(s.contaid, 0) = v_conta0 AND s.tipo = p_tipo
                               AND s.chave = v_chavefixa AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE coalesce(t.contaid, 0) = v_conta0 AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE coalesce(s.contaid, 0) = v_conta0 AND s.tipo = p_tipo
                               AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN jsonb_build_object('tentativaid', v_id, 'esperar', 0);
END;
$$;
REVOKE ALL ON FUNCTION public.tentativa_abrir_ex(integer, text, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tentativa_abrir_ex(integer, text, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. A busca do PIN passa a usar o índice que já existia
-- ---------------------------------------------------------------------------
-- Parte da única versão (20260928100100). Só muda `p_pinhash::bpchar`: com o
-- mesmo tipo da coluna, o banco vai direto ao índice (contaid, pinhash), numa
-- comparação só, e o tempo não cresce com o número de pessoas da conta.
CREATE OR REPLACE FUNCTION public.visao_pessoa_do_pin(p_contaid integer, p_lojaid integer, p_pinhash text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  f      record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT fu.funcionarioid, fu.nomecompleto INTO f
    FROM public.funcionarios fu
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = fu.funcionarioid AND fl.contaid = p_contaid
                                    AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE fu.contaid = p_contaid AND fu.ativo
     AND fu.pinhash = p_pinhash::bpchar
     AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
   LIMIT 1;

  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('funcionarioid', f.funcionarioid,
                            'nome', public.nome_curto(f.nomecompleto));
END;
$$;
REVOKE ALL ON FUNCTION public.visao_pessoa_do_pin(integer, integer, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_pessoa_do_pin(integer, integer, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Quem é este tablet, numa consulta só
-- ---------------------------------------------------------------------------
-- Antes eram duas idas: `meu_acesso` com o token e depois `contasusuarios`.
-- O usuário vem do token, conferido pelo servidor (assinatura e validade)
-- antes de chegar aqui. As regras de "desligado na hora" são as mesmas do
-- `meu_acesso` para o papel loja: loja desativada ou conta cancelada caem
-- aqui, na hora.
CREATE OR REPLACE FUNCTION public.visao_tablet_do_usuario(p_userid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT cu.contaid, cu.lojaid, l.nome AS loja INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
   WHERE cu.userid = p_userid
     AND cu.papel = 'loja'
     AND l.ativa
     AND c.status <> 'cancelada';

  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('contaid', a.contaid, 'lojaid', a.lojaid, 'loja', a.loja);
END;
$$;
REVOKE ALL ON FUNCTION public.visao_tablet_do_usuario(uuid) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_tablet_do_usuario(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. Conferir o PIN com a trava, numa transação
-- ---------------------------------------------------------------------------
-- Abre a tentativa, procura a pessoa e fecha a tentativa. É o mesmo que o
-- servidor fazia em três idas. Devolve a pessoa, ou {travado, minutos}, ou
-- {pinerrado}: nunca diz se o PIN existe e a pessoa é que não pode.
--
-- Serve para o pedido e o mural (que só conferem o PIN) e é chamada por
-- dentro das duas funções abaixo.
CREATE OR REPLACE FUNCTION public.visao_conferir_pin(p_contaid integer, p_lojaid integer,
                                                     p_pinhash text, p_chave text, p_origem text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_trava  jsonb;
  v_id     bigint;
  v_pessoa jsonb;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- A tentativa é gravada ANTES de olhar o PIN, como sempre foi.
  v_trava := public.tentativa_abrir_ex(p_contaid, 'pintablet', p_chave, p_origem);
  v_id := (v_trava->>'tentativaid')::bigint;
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('travado', true, 'minutos', v_trava->'minutos');
  END IF;

  v_pessoa := public.visao_pessoa_do_pin(p_contaid, p_lojaid, p_pinhash);
  PERFORM public.tentativa_fechar(v_id, v_pessoa IS NOT NULL);

  IF v_pessoa IS NULL THEN
    RETURN jsonb_build_object('pinerrado', true);
  END IF;
  RETURN v_pessoa;
END;
$$;
REVOKE ALL ON FUNCTION public.visao_conferir_pin(integer, integer, text, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_conferir_pin(integer, integer, text, text, text) TO service_role;

-- Milissegundos entre dois instantes, com uma casa. Só para a medição.
CREATE OR REPLACE FUNCTION public.ms_entre(p_de timestamptz, p_ate timestamptz)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$ SELECT round((extract(epoch FROM p_ate - p_de) * 1000)::numeric, 1) $$;
REVOKE ALL ON FUNCTION public.ms_entre(timestamptz, timestamptz) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ms_entre(timestamptz, timestamptz) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Aceitar pelo tablet: tudo numa ida
-- ---------------------------------------------------------------------------
-- Os tempos por etapa (PIN, aceite, fila) só voltam quando dá CERTO. No erro
-- não volta número nenhum: a resposta de "PIN não reconhecido" não pode
-- contar, pelo tempo, se o PIN existe.
CREATE OR REPLACE FUNCTION public.visao_pegar_com_pin(p_contaid integer, p_lojaid integer,
                                                      p_pinhash text, p_chave text, p_origem text,
                                                      p_atribuicaoid integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  t0 timestamptz := clock_timestamp();
  t1 timestamptz;
  t2 timestamptz;
  v_quem jsonb;
  v_fila jsonb;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_quem := public.visao_conferir_pin(p_contaid, p_lojaid, p_pinhash, p_chave, p_origem);
  IF v_quem ? 'travado' OR v_quem ? 'pinerrado' THEN
    RETURN v_quem;
  END IF;
  t1 := clock_timestamp();

  -- O erro de uma regra (rodízio, já foi pega, não é da fila de hoje) volta
  -- como resposta. Se virasse exceção, desfaria também a tentativa gravada.
  BEGIN
    PERFORM public.visao_pegar(p_contaid, p_lojaid, (v_quem->>'funcionarioid')::integer, p_atribuicaoid);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
  t2 := clock_timestamp();

  v_fila := public.visao_fila(p_contaid, p_lojaid);
  RETURN jsonb_build_object(
    'nome', v_quem->'nome',
    'fila', v_fila,
    'tempos', jsonb_build_object('pin',  public.ms_entre(t0, t1),
                                 'acao', public.ms_entre(t1, t2),
                                 'fila', public.ms_entre(t2, clock_timestamp())));
END;
$$;
REVOKE ALL ON FUNCTION public.visao_pegar_com_pin(integer, integer, text, text, text, integer)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_pegar_com_pin(integer, integer, text, text, text, integer)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 6. Entregar pelo tablet: tudo numa ida
-- ---------------------------------------------------------------------------
-- A foto já foi conferida pelo servidor (hash e hora) antes de chegar aqui.
CREATE OR REPLACE FUNCTION public.visao_entregar_com_pin(p_contaid integer, p_lojaid integer,
                                                         p_pinhash text, p_chave text, p_origem text,
                                                         p_atribuicaoid integer,
                                                         p_caminho text, p_observacao text,
                                                         p_fotoidunico text, p_semhorafoto boolean)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  t0 timestamptz := clock_timestamp();
  t1 timestamptz;
  t2 timestamptz;
  v_quem jsonb;
  v_fila jsonb;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_quem := public.visao_conferir_pin(p_contaid, p_lojaid, p_pinhash, p_chave, p_origem);
  IF v_quem ? 'travado' OR v_quem ? 'pinerrado' THEN
    RETURN v_quem;
  END IF;
  t1 := clock_timestamp();

  BEGIN
    PERFORM public.visao_entregar(p_contaid, p_lojaid, (v_quem->>'funcionarioid')::integer,
                                  p_atribuicaoid, p_caminho, p_observacao,
                                  p_fotoidunico, coalesce(p_semhorafoto, false));
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
  t2 := clock_timestamp();

  v_fila := public.visao_fila(p_contaid, p_lojaid);
  RETURN jsonb_build_object(
    'nome', v_quem->'nome',
    'fila', v_fila,
    'tempos', jsonb_build_object('pin',  public.ms_entre(t0, t1),
                                 'acao', public.ms_entre(t1, t2),
                                 'fila', public.ms_entre(t2, clock_timestamp())));
END;
$$;
REVOKE ALL ON FUNCTION public.visao_entregar_com_pin(integer, integer, text, text, text, integer,
                                                     text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_entregar_com_pin(integer, integer, text, text, text, integer,
                                                         text, text, text, boolean)
  TO service_role;
