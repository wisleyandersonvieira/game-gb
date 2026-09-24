-- Etapa 1.12, parte B1 — o gestor pode digitar a senha do tablet (24/09/2026).
--
-- A PARTE DELICADA, que o Wisley pediu para não pular:
--
-- Na parte A, a trava por e-mail do login da LOJA foi desligada de propósito.
-- Motivo: a senha era sempre sorteada pelo servidor (14 caracteres, ~70 bits —
-- impossível de adivinhar), então travar não comprava segurança nenhuma e
-- permitia a um engraçadinho deixar o balcão sem sistema por 15 minutos, só
-- errando a senha de propósito. Ficou anotado: "se um dia alguém puder digitar
-- a senha do tablet, a trava volta junto".
--
-- Agora a senha pode ser digitada, e as duas coisas NÃO cabem juntas do jeito
-- antigo: bloquear no 5º erro devolve exatamente o problema que fez a trava ser
-- desligada — quem ataca não perde nada, e a loja fica sem sistema.
--
-- A saída é o ATRASO PROGRESSIVO (a melhoria que estava reservada para a Etapa
-- 1.14, trazida para cá porque agora ela é necessária):
--   * cada erro faz a tentativa seguinte daquele login esperar mais: 0,5 s, 1 s,
--     2 s, 4 s, 8 s, até o teto de 10 s;
--   * um ACERTO zera o atraso na hora. E só zera quem sabe a senha — quem está
--     adivinhando não consegue zerar nada;
--   * NÃO existe estado "trancado": a loja nunca fica sem sistema. No pior caso,
--     quem está no balcão espera alguns segundos;
--   * o atraso vale também por origem, porque bloquear a origem derrubaria a
--     própria loja quando o engraçadinho estivesse no wi-fi dela.
--
-- A conta: com teto de 10 s, saem no máximo ~8.600 tentativas por dia. Uma
-- senha de 10 caracteres tem muito mais combinações do que isso em qualquer
-- vida útil do sistema. E o gestor vê os erros na ficha da loja.
--
-- Se a senha voltar a ser sorteada ("Gerar nova senha"), a marca sai e o login
-- daquela loja volta ao comportamento antigo, sem atraso nenhum.

-- ---------------------------------------------------------------------------
-- 1. A marca: esta senha foi digitada por uma pessoa
-- ---------------------------------------------------------------------------
ALTER TABLE public.senhasgestor ADD COLUMN IF NOT EXISTS definidaamao boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.senhasgestor.definidaamao IS
  'true quando a senha foi DIGITADA por uma pessoa (e não sorteada pelo servidor). Só nesse caso o login passa pelo atraso progressivo.';

CREATE OR REPLACE FUNCTION public.marcar_senha_amao(p_userid uuid, p_contaid integer, p_amao boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor marca a senha.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.senhasgestor SET definidaamao = coalesce(p_amao, false)
   WHERE userid = p_userid AND contaid IS NOT DISTINCT FROM p_contaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há senha guardada para marcar.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. O login precisa saber se a senha é digitada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.acesso_por_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE u record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura acesso por e-mail.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT au.id AS userid, s.senhahashapp, coalesce(s.definidaamao, false) AS amao,
         cu.contaid, coalesce(cu.papel, '') AS papel,
         coalesce(c.status, 'ativa') AS statusconta, l.ativa AS lojaativa,
         coalesce(lower(au.email) = 'wisley_anderson@hotmail.com', false) AS ehadmin
    INTO u
    FROM auth.users au
    LEFT JOIN public.senhasgestor s ON s.userid = au.id
    LEFT JOIN public.contasusuarios cu ON cu.userid = au.id
    LEFT JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
   WHERE lower(au.email) = lower(btrim(coalesce(p_email, '')));
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Esta porta é do gestor, do administrador geral e do tablet. O colaborador
  -- entra pelo CPF, com as conferências dele. Sem papel, ninguém entra.
  IF NOT (u.ehadmin OR u.papel IN ('master', 'gerente', 'loja')) THEN
    RETURN NULL;
  END IF;
  IF u.papel <> '' AND u.statusconta = 'cancelada' THEN
    RETURN NULL;
  END IF;
  IF u.papel = 'loja' AND coalesce(u.lojaativa, false) = false THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid,
                            'papel', CASE WHEN u.papel = '' THEN 'admin' ELSE u.papel END,
                            'senhamanual', u.amao);
END;
$$;

REVOKE ALL ON FUNCTION public.acesso_por_email(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.acesso_por_email(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. A trava com atraso progressivo
-- ---------------------------------------------------------------------------
ALTER TABLE public.tentativasacesso DROP CONSTRAINT IF EXISTS tentativasacesso_tipo_check;
ALTER TABLE public.tentativasacesso ADD  CONSTRAINT tentativasacesso_tipo_check
  CHECK (tipo IN ('senha', 'pin', 'tablet', 'pintablet', 'lojamanual'));

-- Devolve {tentativaid, esperar}: quanto o SERVIDOR tem de esperar antes de
-- responder. O cálculo é feito aqui dentro, sob a mesma tranca que conta as
-- tentativas — senão uma rajada simultânea leria todo mundo o mesmo número e
-- passaria junto (foi assim que a trava furou na revisão de 23/09/2026).
CREATE OR REPLACE FUNCTION public.tentativa_abrir_ex(p_contaid integer, p_tipo text,
                                                     p_chave text, p_origem text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela  interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave   text     := left(coalesce(p_chave, ''), 64);
  v_origem  text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros   integer;
  v_outros  integer;
  v_esperar integer  := 0;
  v_id      bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tipo NOT IN ('senha', 'pin', 'tablet', 'pintablet', 'lojamanual') THEN
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
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'lojamanual' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '15 minutes'
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = 'lojamanual'
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    v_outros := 0;
    IF v_origem <> 'sem-ip' THEN
      SELECT count(*) INTO v_outros FROM public.tentativasacesso t
       WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'lojamanual' AND t.origem = v_origem
         AND NOT t.sucesso AND t.em > now() - interval '15 minutes'
         AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                               WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = 'lojamanual'
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
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  IF p_tipo = 'pintablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pintablet' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '1 day';
    IF v_erros >= 20 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  IF p_tipo <> 'tablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN jsonb_build_object('tentativaid', NULL, 'esperar', 0);
    END IF;
  END IF;

  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
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

-- Quem já chamava tentativa_abrir continua chamando: ela vira um atalho.
CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (public.tentativa_abrir_ex(p_contaid, p_tipo, p_chave, p_origem) ->> 'tentativaid')::bigint
$$;

REVOKE ALL ON FUNCTION public.tentativa_abrir_ex(integer, text, text, text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.tentativa_abrir(integer, text, text, text)    FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tentativa_abrir_ex(integer, text, text, text) TO service_role;
GRANT  EXECUTE ON FUNCTION public.tentativa_abrir(integer, text, text, text)    TO service_role;

-- ---------------------------------------------------------------------------
-- 4. Histórico: senha digitada é diferente de senha sorteada
-- ---------------------------------------------------------------------------
ALTER TABLE public.acessoslojaeventos DROP CONSTRAINT IF EXISTS acessoslojaeventos_evento_check;
ALTER TABLE public.acessoslojaeventos ADD  CONSTRAINT acessoslojaeventos_evento_check
  CHECK (evento IN ('criado', 'senha_nova', 'senha_amao'));

-- ---------------------------------------------------------------------------
-- 5. A ficha mostra a marca e os erros de senha do dia
-- ---------------------------------------------------------------------------
-- Os erros na ficha são a defesa visível: se alguém estiver tentando adivinhar
-- a senha do balcão, o gestor vê o número subir.
CREATE OR REPLACE FUNCTION public.ficha_dos_tablets(p_contaid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sessoes jsonb := '{}'::jsonb;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor lê a ficha do tablet.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF to_regclass('auth.sessions') IS NOT NULL THEN
    EXECUTE $q$
      SELECT coalesce(jsonb_object_agg(user_id::text, n), '{}'::jsonb)
        FROM (SELECT user_id, count(*) AS n FROM auth.sessions
               WHERE not_after IS NULL OR not_after > now()
               GROUP BY user_id) s
    $q$ INTO v_sessoes;
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'lojaid',       l.lojaid,
             'loja',         l.nome,
             'usuario',      u.email,
             'ultimoacesso', u.last_sign_in_at,
             'aparelhos',    coalesce((v_sessoes ->> cu.userid::text)::integer, 0),
             'senhamanual',  coalesce(sg.definidaamao, false),
             'historico',    coalesce((
               SELECT jsonb_agg(jsonb_build_object('evento', e.evento, 'em', e.em, 'quem', q.email)
                                ORDER BY e.em DESC, e.eventoid DESC)
                 FROM public.acessoslojaeventos e
                 LEFT JOIN auth.users q ON q.id = e.userid
                WHERE e.contaid = p_contaid AND e.lojaid = l.lojaid), '[]'::jsonb))
           ORDER BY l.nome), '[]'::jsonb)
      FROM public.contasusuarios cu
      JOIN public.lojas l    ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
      LEFT JOIN auth.users u ON u.id = cu.userid
      LEFT JOIN public.senhasgestor sg ON sg.userid = cu.userid
     WHERE cu.contaid = p_contaid AND cu.papel = 'loja' AND cu.lojaid IS NOT NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.ficha_dos_tablets(integer) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.marcar_senha_amao(uuid, integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ficha_dos_tablets(integer)            TO service_role;
GRANT  EXECUTE ON FUNCTION public.marcar_senha_amao(uuid, integer, boolean) TO service_role;

-- Erros de senha das ultimas 24 horas, por chave de trava. A chave e feita
-- pelo SERVIDOR (HMAC com a chave dele), entao o banco nao sabe montá-la: quem
-- pergunta manda as chaves que quer contar.
CREATE OR REPLACE FUNCTION public.erros_de_login(p_chaves text[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor conta as tentativas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN (
    SELECT coalesce(jsonb_object_agg(c, n), '{}'::jsonb)
      FROM (SELECT k AS c, (SELECT count(*) FROM public.tentativasacesso t
                             WHERE t.chave = k AND NOT t.sucesso
                               AND t.tipo IN ('senha', 'tablet', 'lojamanual')
                               AND t.em > now() - interval '1 day') AS n
              FROM unnest(coalesce(p_chaves, ARRAY[]::text[])) k) x);
END;
$$;

REVOKE ALL ON FUNCTION public.erros_de_login(text[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.erros_de_login(text[]) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. O diagnóstico (/saude) conhece as funções desta parte
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_abrir_ex', 'tentativa_fechar', 'acesso_por_email',
    'definir_senha_gestor', 'marcar_senha_amao', 'erros_de_login',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado',
    -- Etapa 1.12, partes B1a e B1b
    'pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
    'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa', 'tarefa_unica_ja_cumprida',
    'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar',
    'fechamento_valendo', 'ficha_dos_tablets', 'registrar_evento_acesso_loja'
  ];
  v_faltando text[];
  v_tabelas  text[];
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pede o diagnóstico.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_faltando
    FROM unnest(v_esperadas) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);

  SELECT coalesce(array_agg(t ORDER BY t), ARRAY[]::text[]) INTO v_tabelas
    FROM unnest(ARRAY['codigosacesso', 'tentativasacesso', 'senhasgestor', 'fotosexpurgo',
                      'tarefascandidatos', 'acessoslojaeventos']) t
   WHERE to_regclass('public.' || t) IS NULL;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;
