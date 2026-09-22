-- Etapa 1.12, parte A — consertos da SEGUNDA revisão adversarial (23/09/2026).
--
-- O que a segunda rodada achou e o que muda aqui:
--
-- 1) A trava não era atômica: conferir e registrar eram duas idas ao banco, e
--    uma rajada de pedidos simultâneos passava toda de uma vez (o teto de 30
--    por dia virava 30 POR RAJADA, e o adivinhador de PIN voltava).
--    → Agora é UMA função só, que tranca a chave, conta e registra na mesma
--      transação. Duas tentativas da mesma pessoa entram em fila.
--
-- 2) A porta do Supabase continuava aberta para o MASTER e para o TABLET: dava
--    para falar direto com o Supabase e pular a nossa trava.
--    → A senha deles passa a ser conferida por nós também, como a do
--      colaborador. Quem ainda não tem senha guardada por nós entra uma última
--      vez pela senha antiga, e nesse momento ela é convertida (ninguém fica
--      trancado do lado de fora).
--
-- 3) Defeitos que eu mesmo introduzi na leva anterior:
--    - situacao_dos_acessos ficou sem permissão e quebrava a tela Equipe;
--    - o gatilho que cancela códigos não era security definer e quebrava a
--      desativação pelo navegador;
--    - o expurgo, ao encontrar uma foto presa, parava de chamar a remoção das
--      outras, para sempre;
--    - trocar o CPF de pessoa inativa ficou impossível por qualquer caminho.

-- ---------------------------------------------------------------------------
-- 1. Trava atômica: conferir e registrar viram uma coisa só
-- ---------------------------------------------------------------------------
-- Abre a tentativa: tranca a chave (quem chegar junto espera), confere os
-- limites e JÁ registra a tentativa. Devolve o número dela, ou nada se estiver
-- travado. O resultado (deu certo ou não) entra depois, em tentativa_fechar.
CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER   -- grava na tabela de tentativas, que e fechada para todos
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_teto   integer  := CASE WHEN p_tipo = 'pin' THEN 30 ELSE 50 END;
  v_chave  text     := left(coalesce(p_chave, ''), 64);
  v_origem text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros  integer;
  v_id     bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Duas tentativas da mesma chave nunca contam ao mesmo tempo: a segunda
  -- espera a primeira terminar. É isto que faz o teto valer de verdade.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.acesso:' || p_tipo || ':' || v_chave, 0));

  -- Teto do dia por chave (o que mata o adivinhador de PIN).
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
     AND t.em > now() - interval '1 day';
  IF v_erros >= v_teto THEN
    RETURN NULL;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela.
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
     AND NOT t.sucesso AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN NULL;
  END IF;

  -- E erros seguidos desta origem (mesmo aparelho tentando vários CPFs).
  SELECT count(*) INTO v_erros FROM public.tentativasacesso t
   WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
     AND v_origem <> 'sem-ip' AND NOT t.sucesso AND t.em > now() - v_janela
     AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                           WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                             AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
  IF v_erros >= 5 THEN
    RETURN NULL;
  END IF;

  -- Registra JÁ (como erro): quem não voltar para fechar conta como tentativa.
  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.tentativa_fechar(p_tentativaid bigint, p_sucesso boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor fecha tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tentativasacesso SET sucesso = coalesce(p_sucesso, false)
   WHERE tentativaid = p_tentativaid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. A senha do gestor e a do tablet também passam a ser nossas
-- ---------------------------------------------------------------------------
-- O colaborador guarda o resumo da senha em funcionarios.senhahashapp. O master
-- e o tablet não têm cadastro de funcionário: ficam aqui.
CREATE TABLE public.senhasgestor (
  userid       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Vazio no administrador geral, que não pertence a conta nenhuma.
  contaid      integer REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  senhahashapp text NOT NULL,
  atualizadoem timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.senhasgestor IS
  'Resumo da senha do master, do administrador geral e do tablet (PBKDF2 calculado no servidor). Sem isto, a senha ficaria só no Supabase e daria para tentar direto lá, pulando a nossa trava.';

ALTER TABLE public.senhasgestor ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.senhasgestor FROM anon, authenticated;
GRANT ALL ON public.senhasgestor TO service_role;

-- Quem é este e-mail, e qual o resumo da senha dele.
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
  SELECT au.id AS userid, s.senhahashapp, cu.contaid, cu.papel
    INTO u
    FROM auth.users au
    LEFT JOIN public.senhasgestor s ON s.userid = au.id
    LEFT JOIN public.contasusuarios cu ON cu.userid = au.id
   WHERE lower(au.email) = lower(btrim(coalesce(p_email, '')));
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid, 'papel', u.papel);
END;
$$;

CREATE OR REPLACE FUNCTION public.definir_senha_gestor(p_userid uuid, p_contaid integer, p_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor define senha de gestor.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.senhasgestor (userid, contaid, senhahashapp)
  VALUES (p_userid, p_contaid, p_hash)
  ON CONFLICT (userid) DO UPDATE SET senhahashapp = excluded.senhahashapp,
                                     contaid = excluded.contaid,
                                     atualizadoem = now();
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Consertos dos defeitos que entraram na leva anterior
-- ---------------------------------------------------------------------------

-- (a) A tela Equipe precisa desta função: ela tinha perdido a permissão no
--     DROP/CREATE anterior.
GRANT EXECUTE ON FUNCTION public.situacao_dos_acessos() TO authenticated;

-- (b) Os gatilhos da desativação mexem em tabela fechada ao navegador: sem
--     security definer, desativar alguém pela tela falharia.
CREATE OR REPLACE FUNCTION public.cancela_codigos_ao_desativar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativo AND NOT NEW.ativo THEN
    UPDATE public.codigosacesso SET canceladoem = now()
     WHERE contaid = NEW.contaid AND funcionarioid = NEW.funcionarioid
       AND usadoem IS NULL AND canceladoem IS NULL;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.limpa_acesso_ao_desativar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.ativo AND NOT NEW.ativo THEN
    NEW.pinhash := NULL;
    NEW.senhahashapp := NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- (c) Trocar o CPF de quem está inativo passa a ser possível (pelo servidor):
--     antes ficava um beco sem saída para corrigir cadastro de ex-funcionário.
CREATE OR REPLACE FUNCTION public.trocar_cpf(p_contaid integer, p_funcionarioid integer, p_cpf text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor troca o CPF de quem tem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.funcionarios SET cpf = p_cpf
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- (d) Expurgo: a foto presa vira aviso, mas NÃO pode parar a remoção das
--     outras. Antes, a partir do primeiro arquivo preso, nenhuma foto nova era
--     apagada de verdade — e o banco dizia que estavam apagadas.
--     Também: só marca como expirada a entrega cujo caminho entrou mesmo na
--     fila de remoção.
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

    WITH vencidas AS (
      SELECT e.entregaid, e.pathfotoevidencia
        FROM public.entregas e
       WHERE e.contaid = p_contaid
         AND e.pathfotoevidencia IS NOT NULL
         AND e.fotoexpiradaem IS NULL
         AND e.dataenvio < p_agora - make_interval(days => v_dias)
       ORDER BY e.dataenvio
       LIMIT 2000
    ), na_fila AS (
      INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
      SELECT p_contaid, v.entregaid, v.pathfotoevidencia FROM vencidas v
      ON CONFLICT (contaid, caminho) DO NOTHING
      RETURNING entregaid
    )
    -- Só some da entrega o que realmente entrou na fila de remoção.
    UPDATE public.entregas e
       SET fotoexpiradaem = p_agora, pathfotoevidencia = NULL
      FROM na_fila f
     WHERE e.contaid = p_contaid AND e.entregaid = f.entregaid;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Chama a remoção SEMPRE que houver fila, inclusive quando já existe
    -- arquivo preso: o problema de um não pode travar o dos outros.
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
-- 4. Permissões
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.tentativa_abrir(integer, text, text, text)',
    'public.tentativa_fechar(bigint, boolean)',
    'public.acesso_por_email(text)',
    'public.definir_senha_gestor(uuid, integer, text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;

-- A função antiga de conferir trava sai de cena: quem confere agora registra
-- na mesma operação (era esse o furo).
DROP FUNCTION IF EXISTS public.acesso_travado(integer, text, text, text);
DROP FUNCTION IF EXISTS public.registrar_tentativa(integer, text, text, text, boolean);
