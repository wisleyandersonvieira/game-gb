-- Etapa 1.12, parte A — consertos da QUARTA revisão adversarial (23/09/2026).
--
-- Três defeitos que os meus próprios consertos criaram, e a decisão do Wisley
-- sobre o tablet.
--
-- 1) O adivinhador de PIN voltou. Ao fazer o teto do dia contar só ERRO (para
--    ninguém trancar a conta de outro), esqueci que no adivinhador o resultado
--    comum é ACERTO: o número livre é aceito, e acerto não contava nem para o
--    teto — e ainda zerava a janela.
--    → No PIN o teto conta TODA tentativa, como era antes. Ali isso não tranca
--      ninguém: quem tenta já está logado como a própria pessoa, então só
--      gasta a própria cota. No login continua contando só erro.
--
-- 2) Desativar e reativar alguém deixava a pessoa sem entrar para sempre: a
--    desativação sorteava uma senha que ninguém guardava.
--    → A reativação devolve a senha interna (quem faz isso é o servidor).
--      Aqui fica só a marca de que a pessoa precisa disso.
--
-- 3) O expurgo passou a apagar foto DENTRO do prazo: bastava outra entrega
--    apontar para o mesmo arquivo.
--    → Volta a marcar só entrega que venceu de verdade.
--
-- 4) Decisão do Wisley: a trava por e-mail não pode derrubar o tablet da loja
--    num horário de pico. Como a senha do tablet é sorteada pelo servidor (14
--    caracteres, 70 bits), adivinhar é impossível na prática, e a trava por
--    chave só transferia o prejuízo do atacante para a loja.
--    → Para o tablet vale só a trava por ORIGEM (que é quem realmente segura o
--      atacante). Isso NÃO vale para gestor e colaborador, que têm senha
--      escolhida por pessoa.

-- ---------------------------------------------------------------------------
-- 1. Tipo novo de tentativa: o tablet
-- ---------------------------------------------------------------------------
ALTER TABLE public.tentativasacesso DROP CONSTRAINT tentativasacesso_tipo_check;
ALTER TABLE public.tentativasacesso ADD CONSTRAINT tentativasacesso_tipo_check
  CHECK (tipo IN ('senha', 'pin', 'tablet'));
COMMENT ON COLUMN public.tentativasacesso.tipo IS
  'senha (gestor e colaborador), pin (tablet) ou tablet (login do próprio tablet, sem trava por chave).';

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
  IF p_tipo NOT IN ('senha', 'pin', 'tablet') THEN
    RAISE EXCEPTION 'Tipo de tentativa inválido.' USING ERRCODE = 'check_violation';
  END IF;

  -- Duas trancas, SEMPRE nesta ordem (chave e depois origem), para duas
  -- tentativas nunca contarem ao mesmo tempo. A ordem fixa evita travar uma na
  -- outra.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- PIN: teto de 30 no dia contando TODA tentativa (acerto inclusive). É o que
  -- impede usar a tela do PIN como adivinhador: ali o resultado comum é
  -- acerto. E não tranca ninguém de fora, porque quem tenta já está logado
  -- como a própria pessoa: só gasta a própria cota.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela (o acerto zera).
  -- NÃO vale para o tablet: a senha dele é sorteada pelo servidor (impossível
  -- de adivinhar) e travá-la por e-mail só deixaria a loja sem sistema.
  IF p_tipo <> 'tablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta origem: é o eixo que o atacante controla e a vítima
  -- não. Vale para todos, inclusive para o tablet.
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
-- 2. O login por e-mail: quem não tem papel nenhum não entra
-- ---------------------------------------------------------------------------
-- Antes, um login sem vínculo (convite pela metade, cadastro órfão) passava
-- pela conferência por causa da lógica de três valores do SQL — e ainda era
-- rotulado como "admin".
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
  SELECT au.id AS userid, s.senhahashapp, cu.contaid, coalesce(cu.papel, '') AS papel,
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
                            'papel', CASE WHEN u.papel = '' THEN 'admin' ELSE u.papel END);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Expurgo: marcar só o que venceu de verdade
-- ---------------------------------------------------------------------------
-- O conserto anterior passou a marcar toda entrega que dividisse o caminho com
-- uma vencida — e apagava foto de entrega recente, possivelmente ainda em
-- discussão de validação.
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

    -- Marca as entregas VENCIDAS cujo arquivo está na fila. O prazo entra aqui
    -- também: sem ele, uma entrega recente que dividisse o caminho com uma
    -- vencida perdia a foto junto.
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM public.fotosexpurgo f
     WHERE e.contaid = p_contaid AND f.contaid = p_contaid
       AND e.pathfotoevidencia = f.caminho
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias);
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
