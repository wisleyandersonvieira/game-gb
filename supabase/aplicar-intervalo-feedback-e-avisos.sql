-- =========================================================================
-- STGame — Sem o intervalo da jornada e o feedback de ontem; o X dos avisos.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-tirar-telegram.sql (e os anteriores).
--
-- Este arquivo tem UMA migração:
--   20261005100000_intervalo_feedback_e_x_dos_avisos.sql
--
-- CLASSIFICAÇÃO: TIRA (o salvar_jornada perde os dois parâmetros do intervalo, que a versão no ar manda ao salvar uma jornada; o aplicativo no ar só deixa de mostrar o aviso do feedback. APLIQUE E PUBLIQUE JUNTOS, COM AS LOJAS FECHADAS: entre o SQL e a publicação, salvar jornada no site antigo dá erro)
--
-- O QUE MUDA: o intervalo da jornada some (o do Mapa fica); o aplicativo não pede mais o feedback de ontem; as 9 configurações do bot ficam, marcadas como obsoletas (nada se apaga); os avisos do Início ganham o X.
-- =========================================================================


BEGIN;

-- ======== 20261005100000_intervalo_feedback_e_x_dos_avisos.sql ========
-- CLASSIFICAÇÃO: TIRA
-- (o salvar_jornada perde os dois parâmetros do intervalo, que a versão no ar
-- manda ao salvar uma jornada. Aplica e publica JUNTOS, com as lojas fechadas.
-- O resto só acrescenta: a tabela e as funções dos avisos dispensados.)
--
-- 05/10/2026, decisões do Wisley (as respostas do Telegram e o X dos avisos):
--
-- A2. O intervalo da JORNADA sai ("intervalo em que o sistema não envia
--     nada"): sem o bot, ele não fazia nada, e campo que não faz nada é pior
--     que campo nenhum. As colunas saem, e com elas os parâmetros e as
--     saídas das funções. O intervalo do MAPA (intervalosdomapa) FICA:
--     nunca teve a ver com o bot.
-- A3. O aviso "Você tem um feedback de ontem para responder", no aplicativo
--     do colaborador, sai (não há onde responder). Com ele sai a última
--     função do bot que o aplicativo usava, bot_falta_feedback_ontem.
-- A4. As configurações que só o bot lia FICAM, e o histórico delas NÃO se
--     apaga (auditoria). Só a DESCRIÇÃO delas muda, para quem ler o banco
--     saber que estão obsoletas (o valor fica; o histórico não registra
--     descrição, só valor).
-- B.  Os avisos do topo do Início ganham um X. Fechar é por FATO (aquele aviso:
--     a loja e o dia a que ele se refere), por PESSOA e fica no BANCO
--     (avisosdispensados). A tela manda a chave do fato; o banco guarda só a
--     chave, de quem dispensou. Nada some sem volta: reexibir_avisos.

-- ---------------------------------------------------------------------------
-- A2. O intervalo da jornada
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.salvar_jornada(integer, text, jsonb, time, time, text, boolean, integer[]);
CREATE OR REPLACE FUNCTION public.salvar_jornada(p_jornadaid integer, p_nome text, p_dias jsonb,
                                                 p_observacao text, p_ativa boolean, p_lojas integer[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
  v_id     integer;
  v_lojas  integer[];
  v_antes  integer[];
  v_falta  text;
  d        jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_master AND cardinality((SELECT public.lojas_onde_posso('jornada.editar'))::integer[]) = 0 THEN
    RAISE EXCEPTION 'Criar e editar jornada não está liberado para o seu cargo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF btrim(coalesce(p_nome, '')) = '' THEN
    RAISE EXCEPTION 'Dê um nome à jornada.' USING ERRCODE = 'check_violation';
  END IF;
  IF jsonb_typeof(p_dias) IS DISTINCT FROM 'array' OR jsonb_array_length(p_dias) = 0 THEN
    RAISE EXCEPTION 'Preencha a entrada e a saída de pelo menos um dia.' USING ERRCODE = 'check_violation';
  END IF;

  -- As lojas pedidas: da conta, pelo menos uma; o gerente, só as dele.
  IF p_lojas IS NOT NULL THEN
    SELECT array_agg(DISTINCT x ORDER BY x) INTO v_lojas FROM unnest(p_lojas) x WHERE x IS NOT NULL;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Marque pelo menos uma loja em que a jornada vale.' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_lojas) x
                WHERE NOT EXISTS (SELECT 1 FROM public.lojas l WHERE l.contaid = v_conta AND l.lojaid = x)) THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    IF NOT v_master AND EXISTS (SELECT 1 FROM unnest(v_lojas) x WHERE NOT public.pode('jornada.editar', x)) THEN
      RAISE EXCEPTION 'Você só pode marcar as lojas em que o seu cargo cria e edita jornada.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF p_jornadaid IS NULL THEN
    IF v_lojas IS NULL THEN
      IF NOT v_master THEN
        RAISE EXCEPTION 'Marque as lojas em que a jornada vale.' USING ERRCODE = 'check_violation';
      END IF;
      SELECT array_agg(l.lojaid ORDER BY l.lojaid) INTO v_lojas FROM public.lojas l WHERE l.contaid = v_conta;
    END IF;
    INSERT INTO public.jornadas (contaid, nome, observacao, ativa)
    VALUES (v_conta, btrim(p_nome), nullif(btrim(coalesce(p_observacao, '')), ''),
            coalesce(p_ativa, true))
    RETURNING jornadaid INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid) THEN
      RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    SELECT array_agg(jl.lojaid ORDER BY jl.lojaid) INTO v_antes
      FROM public.jornadaslojas jl WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid;
    -- O gerente só mexe se a jornada INTEIRA couber nas lojas dele (nem o nome).
    IF NOT v_master AND (v_antes IS NULL OR EXISTS (SELECT 1 FROM unnest(v_antes) x WHERE NOT public.pode('jornada.editar', x))) THEN
      RAISE EXCEPTION 'Esta jornada vale também para lojas que não são suas: só quem cuida de todas elas pode alterá-la.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Tirar loja com gente vinculada dela: a mensagem diz quantas e de qual.
    IF v_lojas IS NOT NULL THEN
      SELECT string_agg(l.nome || ' (' || x.n || ' pessoa' || CASE WHEN x.n = 1 THEN '' ELSE 's' END || ')', ', ' ORDER BY l.nome)
        INTO v_falta
        FROM (SELECT fl.lojaid, count(DISTINCT f.funcionarioid) AS n
                FROM public.funcionarios f
                JOIN public.funcionarioslojas fl ON fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
               WHERE f.contaid = v_conta AND f.jornadaid = p_jornadaid AND f.ativo
                 AND fl.lojaid = ANY (coalesce(v_antes, '{}'::integer[])) AND NOT fl.lojaid = ANY (v_lojas)
               GROUP BY fl.lojaid) x
        JOIN public.lojas l ON l.contaid = v_conta AND l.lojaid = x.lojaid;
      IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Não dá para tirar da jornada a(s) loja(s) %: há gente dessa(s) loja(s) vinculada a ela. Mude a jornada dessas pessoas em Equipe antes.', v_falta
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    UPDATE public.jornadas
       SET nome = btrim(p_nome),
           observacao = nullif(btrim(coalesce(p_observacao, '')), ''), ativa = coalesce(p_ativa, true)
     WHERE contaid = v_conta AND jornadaid = p_jornadaid
    RETURNING jornadaid INTO v_id;
    DELETE FROM public.jornadasdias WHERE contaid = v_conta AND jornadaid = v_id;
  END IF;

  FOR d IN SELECT * FROM jsonb_array_elements(p_dias) LOOP
    IF (d->>'dia')::integer NOT BETWEEN 1 AND 7 THEN
      RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
    END IF;
    IF (d->>'entrada')::time = (d->>'saida')::time THEN
      RAISE EXCEPTION 'Entrada e saída iguais no mesmo dia.' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO public.jornadasdias (contaid, jornadaid, diasemana, entrada, saida)
    VALUES (v_conta, v_id, (d->>'dia')::smallint, (d->>'entrada')::time, (d->>'saida')::time);
  END LOOP;

  -- As lojas: só quando vieram (sem elas, numa edição, ficam como estão).
  IF v_lojas IS NOT NULL THEN
    DELETE FROM public.jornadaslojas
     WHERE contaid = v_conta AND jornadaid = v_id AND NOT lojaid = ANY (v_lojas);
    INSERT INTO public.jornadaslojas (contaid, jornadaid, lojaid)
    SELECT v_conta, v_id, x FROM unnest(v_lojas) x
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Já existe uma jornada com esse nome (ou o mesmo dia apareceu duas vezes).' USING ERRCODE = 'unique_violation';
END;
$$;

REVOKE ALL ON FUNCTION public.salvar_jornada(integer, text, jsonb, text, boolean, integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_jornada(integer, text, jsonb, text, boolean, integer[]) TO authenticated;

DROP FUNCTION IF EXISTS public.jornadas_da_tela();
CREATE FUNCTION public.jornadas_da_tela()
RETURNS TABLE(jornadaid integer, nome character varying, observacao text,
              ativa boolean, lojas integer[], outraslojas integer, editavel boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ver AS (SELECT (SELECT public.lojas_onde_posso('jornada.ver'))::integer[] AS l),
       edita AS (SELECT (SELECT public.lojas_onde_posso('jornada.editar'))::integer[] AS l),
       todas AS (
    SELECT j.*, coalesce((SELECT array_agg(jl.lojaid ORDER BY jl.lojaid) FROM public.jornadaslojas jl
                           WHERE jl.contaid = j.contaid AND jl.jornadaid = j.jornadaid), '{}'::integer[]) AS alcance
      FROM public.jornadas j
     WHERE (public.sou_master() AND j.contaid = public.minha_conta())
        OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente())
  )
  SELECT t.jornadaid, t.nome, t.observacao, t.ativa,
         CASE WHEN public.sou_master() THEN t.alcance
              ELSE ARRAY(SELECT x FROM unnest(t.alcance) x WHERE x = ANY ((SELECT l FROM ver)::integer[]) ORDER BY x) END,
         CASE WHEN public.sou_master() THEN 0
              ELSE (SELECT count(*)::integer FROM unnest(t.alcance) x WHERE NOT x = ANY ((SELECT l FROM ver)::integer[])) END,
         public.sou_master()
           OR (cardinality(t.alcance) > 0 AND t.alcance <@ (SELECT l FROM edita))
    FROM todas t
   WHERE public.sou_master() OR t.alcance && (SELECT l FROM ver)
   ORDER BY t.nome, t.jornadaid
$$;

REVOKE ALL ON FUNCTION public.jornadas_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.jornadas_da_tela() TO authenticated;

DROP FUNCTION IF EXISTS public.jornada_da_pessoa(integer, integer, date);
CREATE OR REPLACE FUNCTION public.jornada_da_pessoa(p_contaid integer, p_funcionarioid integer, p_dia date)
RETURNS TABLE (trabalha boolean, temhorario boolean, inicio timestamptz, fim timestamptz)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, p_dia),
         jd.entrada IS NOT NULL,
         public.instante_local(p_dia, jd.entrada),
         public.instante_local(p_dia, jd.entrada)
           + CASE WHEN jd.saida > jd.entrada THEN jd.saida - jd.entrada
                  ELSE jd.saida - jd.entrada + interval '24 hours' END
    FROM public.funcionarios f
    LEFT JOIN public.jornadasdias jd  ON jd.contaid = f.contaid AND jd.jornadaid = f.jornadaid
                                     AND jd.diasemana = extract(dow FROM p_dia)::integer + 1
   WHERE f.contaid = p_contaid AND f.funcionarioid = p_funcionarioid AND f.ativo
$$;

REVOKE ALL ON FUNCTION public.jornada_da_pessoa(integer, integer, date) FROM public, anon, authenticated;

ALTER TABLE public.jornadas DROP CONSTRAINT IF EXISTS jornadas_pausa_completa;
ALTER TABLE public.jornadas DROP CONSTRAINT IF EXISTS jornadas_pausa_valida;
ALTER TABLE public.jornadas DROP COLUMN IF EXISTS pausainicio, DROP COLUMN IF EXISTS pausafim;

-- ---------------------------------------------------------------------------
-- A3. O aviso do feedback de ontem, no aplicativo do colaborador
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eu_inicio(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.hoje_da_conta(p_contaid);
  f      record;
  v_nota numeric;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Uma porta só para as quatro funções: pessoa ativa E conta não cancelada.
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT nomecompleto, saldopontos INTO f
    FROM public.funcionarios
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT r.nota INTO v_nota
    FROM public.ranking_mensal_da_conta(p_contaid,
           extract(year FROM v_hoje)::integer, extract(month FROM v_hoje)::integer,
           NULL, v_hoje - 1) r
   WHERE r.funcionarioid = p_funcionarioid;

  RETURN jsonb_build_object(
    'nome',   public.nome_curto(f.nomecompleto),
    -- Saldo só em pontos. Nunca convertido em dinheiro nesta visão.
    'saldo',  f.saldopontos,
    'nota',   v_nota,
    'comunicados', (SELECT count(*) FROM public.documentosassinaturas s
                     WHERE s.contaid = p_contaid AND s.funcionarioid = p_funcionarioid
                       AND s.statusassinatura = 'Pendente'));
END;
$$;

DROP FUNCTION IF EXISTS public.bot_falta_feedback_ontem(integer, integer);

-- ---------------------------------------------------------------------------
-- A4. As 9 configurações que só o bot lia: marcadas como obsoletas
-- ---------------------------------------------------------------------------
UPDATE public.configuracoes
   SET descricao = 'OBSOLETA desde 04/10/2026 (o Telegram saiu): nada no sistema lê esta configuração. Fica pelo histórico de quem a mudou; não apague.'
 WHERE chave IN ('HORARIO_DELEGACAO_FOLGA', 'HORARIO_LEMBRETE_COMUNICADOS', 'HORARIO_LEMBRETE_DIARIO_AMANHA',
                 'HORARIO_LEMBRETE_HOJE', 'HORARIO_LEMBRETE_SEMANAL', 'HORARIO_SILENCIO_FIM',
                 'HORARIO_SILENCIO_INICIO', 'MAX_MENSAGENS_AUTOMATICAS_DIA', 'MAX_TAREFAS_FOLGA_POR_PESSOA')
   AND descricao IS DISTINCT FROM 'OBSOLETA desde 04/10/2026 (o Telegram saiu): nada no sistema lê esta configuração. Fica pelo histórico de quem a mudou; não apague.';

-- ---------------------------------------------------------------------------
-- B. Os avisos dispensados (o X do Início)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.avisosdispensados (
  dispensaid    integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  -- Apagar o login apaga os avisos que ele dispensou (não é ato de ninguém).
  userid        uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  chave         text NOT NULL,
  dispensadoem  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT avisosdispensados_chave_valida CHECK (chave ~ '^[a-z]+(\|[A-Za-z0-9:,._-]+)+$' AND length(chave) <= 200),
  CONSTRAINT avisosdispensados_um_por_fato UNIQUE (contaid, userid, chave)
);
COMMENT ON TABLE public.avisosdispensados IS
  'Os avisos do Início que cada pessoa fechou no X (05/10/2026). Por fato (a chave diz o tipo, a loja e o dia), por pessoa. Grava só pelas funções dispensar_avisos e reexibir_avisos.';
ALTER TABLE public.avisosdispensados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.avisosdispensados FROM anon, authenticated;
GRANT SELECT ON public.avisosdispensados TO authenticated;
GRANT ALL ON public.avisosdispensados TO service_role;
DROP POLICY IF EXISTS avisosdispensados_sel ON public.avisosdispensados;
CREATE POLICY avisosdispensados_sel ON public.avisosdispensados FOR SELECT TO authenticated
  USING (contaid = (SELECT public.minha_conta()) AND userid = auth.uid());

-- Fecha os avisos (os fatos) pedidos, para QUEM está logado. Aproveita para
-- jogar fora os que ele fechou há mais de 60 dias (o fato já passou).
CREATE OR REPLACE FUNCTION public.dispensar_avisos(p_chaves text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); n integer;
BEGIN
  IF v_conta IS NULL OR auth.uid() IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_chaves IS NULL OR cardinality(p_chaves) = 0 OR cardinality(p_chaves) > 50 THEN
    RAISE EXCEPTION 'Nada para fechar.' USING ERRCODE = 'check_violation';
  END IF;
  DELETE FROM public.avisosdispensados
   WHERE contaid = v_conta AND userid = auth.uid() AND dispensadoem < now() - interval '60 days';
  INSERT INTO public.avisosdispensados (contaid, userid, chave)
  SELECT DISTINCT v_conta, auth.uid(), c FROM unnest(p_chaves) c
  ON CONFLICT (contaid, userid, chave) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.dispensar_avisos(text[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dispensar_avisos(text[]) TO authenticated;

-- "Mostrar": os avisos pedidos voltam, só para quem está logado.
CREATE OR REPLACE FUNCTION public.reexibir_avisos(p_chaves text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); n integer;
BEGIN
  IF v_conta IS NULL OR auth.uid() IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.avisosdispensados
   WHERE contaid = v_conta AND userid = auth.uid() AND chave = ANY (coalesce(p_chaves, '{}'::text[]));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.reexibir_avisos(text[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.reexibir_avisos(text[]) TO authenticated;

-- Os fatos que QUEM está logado fechou (as chaves, mais nada).
CREATE OR REPLACE FUNCTION public.avisos_dispensados()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(array_agg(d.chave ORDER BY d.chave), '{}'::text[])
    FROM public.avisosdispensados d
   WHERE d.userid = auth.uid() AND d.contaid = public.conta_do_gestor_editavel()
$$;
REVOKE ALL ON FUNCTION public.avisos_dispensados() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.avisos_dispensados() TO authenticated;

COMMIT;
