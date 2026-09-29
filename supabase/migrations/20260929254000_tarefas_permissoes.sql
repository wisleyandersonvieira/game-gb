-- Usuários gerenciais, PARTE 2, fatia 5: Tarefas (29/09/2026).
--
-- 1. Atribuir e mudar a hora conferem a permissão NA LOJA da atribuição;
--    encerrar atribuição também (vira função: a tela gravava direto).
-- 2. O CATÁLOGO (criar, editar, ativar/desativar e as lojas da tarefa) segue
--    a régua do alcance: o gerente só mexe em tarefa cujas lojas, antes E
--    depois da mudança, estão todas dentro das lojas em que ele tem a
--    permissão. Tarefa sem loja nenhuma: só o master. Vira UMA função (antes
--    eram três gravações separadas da tela).
-- 3. As três tabelas (tarefas, tarefaslojas, tarefasatribuidas) fecham para
--    gravação direta. Para o master nada muda.

-- ---------------------------------------------------------------------------
-- 1. O catálogo de tarefas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_tarefa(p_titulo text, p_pontos integer, p_lojas integer[],
                                                p_tarefaid integer DEFAULT NULL, p_descricao text DEFAULT NULL,
                                                p_setor text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_lojas integer[] := coalesce(p_lojas, ARRAY[]::integer[]);
  v_antes integer[];
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tarefaid IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = v_conta AND tarefaid = p_tarefaid) THEN
      RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    SELECT coalesce(array_agg(lojaid), ARRAY[]::integer[]) INTO v_antes
      FROM public.tarefaslojas WHERE contaid = v_conta AND tarefaid = p_tarefaid AND ativo;
  ELSE
    v_antes := ARRAY[]::integer[];
  END IF;
  -- A régua do alcance: todas as lojas de antes e de depois, com a permissão.
  -- Sem loja nenhuma, pode() da conta: só o master.
  IF (cardinality(v_antes || v_lojas) = 0 AND NOT public.pode('tarefas.catalogo'))
     OR EXISTS (SELECT 1 FROM unnest(v_antes || v_lojas) l WHERE NOT public.pode('tarefas.catalogo', l)) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer nesta tarefa: ela vale (ou passaria a valer) em loja fora das suas.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_tarefaid IS NULL THEN
    INSERT INTO public.tarefas (contaid, titulo, descricao, pontos, setor)
    VALUES (v_conta, p_titulo, p_descricao, p_pontos, p_setor)
    RETURNING tarefaid INTO v_id;
  ELSE
    UPDATE public.tarefas SET titulo = p_titulo, descricao = p_descricao, pontos = p_pontos, setor = p_setor
     WHERE contaid = v_conta AND tarefaid = p_tarefaid;
    v_id := p_tarefaid;
  END IF;

  -- As lojas, como a tela fazia: as escolhidas ativas, as outras desligadas.
  INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid, ativo)
  SELECT v_conta, v_id, l, true FROM unnest(v_lojas) l
  ON CONFLICT (tarefaid, lojaid) DO UPDATE SET ativo = true;
  UPDATE public.tarefaslojas SET ativo = false
   WHERE contaid = v_conta AND tarefaid = v_id AND NOT (lojaid = ANY (v_lojas));
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_tarefa(text, integer, integer[], integer, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_tarefa(text, integer, integer[], integer, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_tarefa(p_tarefaid integer, p_ativa boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_lojas integer[];
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = v_conta AND tarefaid = p_tarefaid) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT coalesce(array_agg(lojaid), ARRAY[]::integer[]) INTO v_lojas
    FROM public.tarefaslojas WHERE contaid = v_conta AND tarefaid = p_tarefaid AND ativo;
  IF (cardinality(v_lojas) = 0 AND NOT public.pode('tarefas.catalogo'))
     OR EXISTS (SELECT 1 FROM unnest(v_lojas) l WHERE NOT public.pode('tarefas.catalogo', l)) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer nesta tarefa: ela vale em loja fora das suas.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tarefas SET ativa = p_ativa WHERE contaid = v_conta AND tarefaid = p_tarefaid;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_tarefa(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_tarefa(integer, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Encerrar atribuições (a tela gravava direto, com o dia do APARELHO; agora
--    é o dia da conta, pelo servidor)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.encerrar_atribuicoes(p_ids integer[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Todas as atribuições pedidas, na loja em que ele pode: ou todas, ou nenhuma.
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
              WHERE ta.contaid = v_conta AND ta.atribuicaoid = ANY (coalesce(p_ids, ARRAY[]::integer[]))
                AND NOT public.pode('tarefas.encerrar_atribuicao', ta.lojaid)) THEN
    RAISE EXCEPTION 'Seu cargo não permite encerrar atribuições nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.tarefasatribuidas SET datafimvigencia = public.hoje_da_conta(v_conta)
   WHERE contaid = v_conta AND atribuicaoid = ANY (coalesce(p_ids, ARRAY[]::integer[]));
END;
$$;
REVOKE ALL ON FUNCTION public.encerrar_atribuicoes(integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.encerrar_atribuicoes(integer[]) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.tarefas, public.tarefaslojas, public.tarefasatribuidas FROM authenticated;

-- ---------------------------------------------------------------------------
-- 3. Atribuir e mudar a hora, partindo da versão VIVA no banco
-- ---------------------------------------------------------------------------
-- atribuir_tarefa: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.atribuir_tarefa(p_tarefaid integer, p_lojaid integer, p_funcionarios integer[], p_tipofrequencia text, p_valorfrequencia integer DEFAULT NULL::integer, p_dataagendamento timestamp with time zone DEFAULT NULL::timestamp with time zone, p_horariodisparo time without time zone DEFAULT NULL::time without time zone, p_disponivelapartir time without time zone DEFAULT NULL::time without time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.conta_do_gestor_editavel();
  v_gente   integer[] := coalesce(p_funcionarios, ARRAY[]::integer[]);
  v_quantos integer;
  v_id      integer;
  v_fid     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT count(DISTINCT x) INTO v_quantos FROM unnest(v_gente) x WHERE x IS NOT NULL;

  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE tarefaid = p_tarefaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Tarefas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('tarefas.atribuir', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite atribuir tarefas nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_quantos = 0 AND p_horariodisparo IS NULL THEN
    RAISE EXCEPTION 'Escolha quem faz a tarefa, ou a hora em que a missão vai para o grupo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Todo mundo escolhido precisa estar ativo e ligado a esta loja.
  IF v_quantos > 0 AND EXISTS (
       SELECT 1 FROM unnest(v_gente) g
        WHERE g IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.funcionarios f
                            JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid
                                                            AND fl.contaid = v_conta AND fl.ativo
                           WHERE f.funcionarioid = g AND f.contaid = v_conta AND f.ativo
                             AND fl.lojaid = p_lojaid)) THEN
    RAISE EXCEPTION 'Escolha só pessoas ativas desta loja.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        valorfrequencia, dataagendamento, horariodisparo, compartilhada,
                                        disponivelapartir)
  VALUES (v_conta, p_tarefaid,
          CASE WHEN v_quantos = 1 THEN (SELECT x FROM unnest(v_gente) x WHERE x IS NOT NULL LIMIT 1) END,
          p_lojaid, p_tipofrequencia, p_valorfrequencia, p_dataagendamento,
          CASE WHEN v_quantos = 0 THEN p_horariodisparo END,
          v_quantos > 1,
          p_disponivelapartir)
  RETURNING atribuicaoid INTO v_id;

  IF v_quantos > 1 THEN
    FOREACH v_fid IN ARRAY v_gente LOOP
      IF v_fid IS NOT NULL THEN
        INSERT INTO public.tarefascandidatos (contaid, atribuicaoid, funcionarioid)
        VALUES (v_conta, v_id, v_fid) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN v_id;
END;
$function$;

-- alterar_hora_da_atribuicao: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.alterar_hora_da_atribuicao(p_atribuicaoid integer, p_hora time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Tarefas).
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas
              WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta
                AND NOT public.pode('tarefas.atribuir', lojaid)) THEN
    RAISE EXCEPTION 'Seu cargo não permite mudar a hora nesta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.tarefasatribuidas
     SET disponivelapartir = p_hora
   WHERE atribuicaoid = p_atribuicaoid
     AND contaid = v_conta
     AND datafimvigencia IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada ou já encerrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$function$;

