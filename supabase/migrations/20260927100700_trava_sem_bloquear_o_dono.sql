-- Etapa 1.12, parte A — consertos da TERCEIRA revisão adversarial (23/09/2026).
--
-- 1) DEFEITO NOVO, criado pelo conserto anterior: com 5 tentativas erradas,
--    qualquer pessoa (sem login nenhum) travava a conta de qualquer outra por
--    15 minutos — e, com 50, por um dia inteiro. Travar o e-mail do tablet
--    deixaria a loja sem sistema no balcão.
--    → O teto do dia conta só ERRO, e sai do login: ele fica só onde não dá
--      para outra pessoa gastar a cota (escolher o PIN, que exige estar
--      logado). No login sobram os 5 erros em 15 minutos, e um acerto zera.
--      O pior caso vira 15 minutos, não um dia.
--
-- 2) O login por e-mail (gestor, administrador e tablet) não conferia papel,
--    pessoa ativa, loja ativa nem situação da conta.
--    → Agora confere, no banco, antes de devolver o resumo da senha.
--
-- 3) A senha guardada do gestor/tablet nunca era apagada: desativar a loja não
--    tirava a senha do tablet.
--    → Desativar a loja apaga a senha do tablet; redefinir também.
--
-- 4) A corrida sobrevivia na contagem por ORIGEM (mesma origem, CPFs
--    diferentes): "espalhar uma senha comum por vários CPFs" não era contido.
--    → A tranca passa a valer também para a origem.
--
-- 5) O expurgo passou a marcar de menos quando duas entregas apontam para o
--    mesmo arquivo.

-- ---------------------------------------------------------------------------
-- 1. Trava que segura o atacante sem trancar o dono
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave  text     := left(coalesce(p_chave, ''), 64);
  v_origem text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros  integer;
  v_id     bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Duas trancas, SEMPRE nesta ordem (chave e depois origem), para duas
  -- tentativas nunca contarem ao mesmo tempo — nem a mesma pessoa, nem o mesmo
  -- aparelho tentando pessoas diferentes. A ordem fixa evita travar uma na
  -- outra.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- Teto do dia: SÓ para o PIN, e contando só erro. No PIN quem tenta já está
  -- logado como a própria pessoa, então ninguém gasta a cota de outro. No
  -- login não existe teto de dia: senão bastava errar 50 vezes o e-mail de
  -- alguém para deixar essa pessoa sem sistema até o dia seguinte.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela (o acerto zera).
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
     AND NOT t.sucesso AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN NULL;
  END IF;

  -- E erros seguidos desta origem (o mesmo aparelho tentando vários CPFs).
  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. O login por e-mail confere papel, pessoa ativa, loja ativa e conta
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
  SELECT au.id AS userid, s.senhahashapp, cu.contaid, cu.papel,
         c.status AS statusconta, l.ativa AS lojaativa,
         lower(au.email) = 'wisley_anderson@hotmail.com' AS ehadmin
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
  -- entra pelo CPF, com as conferências dele.
  IF NOT (u.ehadmin OR u.papel IN ('master', 'gerente', 'loja')) THEN
    RETURN NULL;
  END IF;
  -- Conta cancelada e loja desativada perdem o acesso no LOGIN, não só depois.
  IF u.papel IS NOT NULL AND coalesce(u.statusconta, 'ativa') = 'cancelada' THEN
    RETURN NULL;
  END IF;
  IF u.papel = 'loja' AND coalesce(u.lojaativa, false) = false THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid, 'papel', coalesce(u.papel, 'admin'));
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. A senha guardada do tablet some quando a loja é desativada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.limpa_senha_do_tablet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativa AND NOT NEW.ativa THEN
    DELETE FROM public.senhasgestor s
     USING public.contasusuarios cu
     WHERE cu.contaid = NEW.contaid AND cu.lojaid = NEW.lojaid AND cu.papel = 'loja'
       AND s.userid = cu.userid;
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER lojas_limpa_senha_do_tablet
  AFTER UPDATE OF ativa ON public.lojas
  FOR EACH ROW EXECUTE FUNCTION public.limpa_senha_do_tablet();

-- Apagar a senha guardada de um acesso (usada ao desativar pelo servidor).
CREATE OR REPLACE FUNCTION public.limpar_senha_gestor(p_userid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor apaga senha guardada.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.senhasgestor WHERE userid = p_userid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Expurgo: marcar pelo caminho que está na fila (não só pelo que acabou de
--    entrar), senão duas entregas com o mesmo arquivo deixam uma para trás
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    -- Põe na fila o que venceu (um caminho só entra uma vez)...
    INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
    SELECT p_contaid, e.entregaid, e.pathfotoevidencia
      FROM public.entregas e
     WHERE e.contaid = p_contaid
       AND e.pathfotoevidencia IS NOT NULL
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias)
     ORDER BY e.dataenvio
     LIMIT 2000
    ON CONFLICT (contaid, caminho) DO NOTHING;

    -- ...e marca TODA entrega cujo arquivo está na fila (duas entregas podem
    -- apontar para a mesma foto: nenhuma pode ficar para trás).
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM public.fotosexpurgo f
     WHERE e.contaid = p_contaid AND f.contaid = p_contaid
       AND e.pathfotoevidencia = f.caminho
       AND e.fotoexpiradaem IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    SELECT count(*) INTO v_presas FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5;
    IF v_presas > 0 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso',
             v_presas || ' foto(s) marcada(s) como apagada(s) continuam no armazenamento: a remoção falhou 5 vezes.'
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas),
                                      v_presas || ' foto(s) não saíram do armazenamento');
      RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias, 'presas', v_presas);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('fotos', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('fotos', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Senha do app pelo número da pessoa (não pelo CPF, que pode estar vazio)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.senha_app_do_funcionario(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE f record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor confere senha.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT fu.senhahashapp INTO f FROM public.funcionarios fu
   WHERE fu.contaid = p_contaid AND fu.funcionarioid = p_funcionarioid AND fu.ativo;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('senhahash', f.senhahashapp);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.limpar_senha_gestor(uuid)',
    'public.senha_app_do_funcionario(integer, integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;
