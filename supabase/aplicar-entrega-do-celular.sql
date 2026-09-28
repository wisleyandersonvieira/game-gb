-- =========================================================================
-- STGame — A entrega pelo celular igual à do tablet.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-entrega-da-copia.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova: o celular passa a
-- entregar pelas funções novas.
--
-- Este arquivo é UMA migração só:
--   20260929235000_entrega_do_celular_numa_ida.sql
--
-- O QUE MUDA: só a velocidade. Duas funções novas, que o servidor chama:
-- quem é a pessoa numa ida (com as mesmas recusas de antes) e a entrega que
-- já devolve a lista. Nenhuma regra de entrega muda.
-- =========================================================================


BEGIN;

-- A entrega pelo celular igual à do tablet (29/09/2026, pedido do Wisley).
--
-- O celular ficou de fora das melhorias do tablet. Do lado do banco, cada
-- entrega fazia, em fila: meu_acesso + o vínculo (quem é a pessoa, 2 idas)
-- na autorização da foto, mais a tarefa (1 ida); de novo meu_acesso + o
-- vínculo (2 idas) na entrega, a tolerância da foto (1 ida, depois do
-- download) e a entrega (1 ida); e depois a recarga da lista (mais 3 idas).
--
-- Agora, como no tablet:
--   * eu_pessoa_do_usuario: quem é a pessoa numa ida só — com as MESMAS
--     recusas de antes (não é colaborador, desligado, primeiro acesso
--     pendente) — e, se vier a tarefa, a loja dela (a autorização da foto
--     numa ida);
--   * eu_entregar_e_listar: grava a entrega (eu_entregar, sem mudar nada) e
--     devolve a lista já atualizada, na mesma ida — a tela não pergunta de
--     novo.
-- Nenhuma regra muda: a entrega continua passando por eu_entregar e
-- registrar_entrega, e a conferência da foto (bilhete e impressão digital)
-- continua no servidor.

-- ---------------------------------------------------------------------------
-- 1. Quem é a pessoa, numa ida (só o servidor chama)
-- ---------------------------------------------------------------------------
-- As recusas são as mesmas que o servidor fazia com meu_acesso (a seção 79 do
-- teste de isolamento compara as duas, pessoa por pessoa).
CREATE OR REPLACE FUNCTION public.eu_pessoa_do_usuario(p_userid uuid, p_atribuicaoid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a record; v_loja integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT cu.papel, cu.contaid, cu.funcionarioid, c.status AS statusconta,
         f.ativo AS pessoaativa, f.senhahashapp IS NULL AS semsenha, f.pinhash IS NULL AS sempin
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = p_userid;

  IF NOT FOUND OR a.papel IS DISTINCT FROM 'colaborador' THEN
    RETURN jsonb_build_object('erro', 'naocolaborador');
  END IF;
  IF a.statusconta = 'cancelada' OR NOT coalesce(a.pessoaativa, false) THEN
    RETURN jsonb_build_object('erro', 'desligado');
  END IF;
  -- O primeiro acesso é uma PORTA: sem senha, sem PIN ou sem a ciência da
  -- política de uso, nada de entregar nem de ler o extrato.
  IF coalesce(a.semsenha, false) OR coalesce(a.sempin, false)
     OR public.politica_pendente(a.contaid, a.funcionarioid) THEN
    RETURN jsonb_build_object('erro', 'primeiroacesso');
  END IF;

  IF p_atribuicaoid IS NOT NULL THEN
    -- A loja sai da TAREFA, e a tarefa tem de ser dela.
    SELECT ta.lojaid INTO v_loja FROM public.tarefasatribuidas ta
     WHERE ta.contaid = a.contaid AND ta.atribuicaoid = p_atribuicaoid AND ta.funcionarioid = a.funcionarioid;
  END IF;

  RETURN jsonb_build_object('contaid', a.contaid, 'funcionarioid', a.funcionarioid, 'lojadatarefa', v_loja);
END;
$$;
REVOKE ALL ON FUNCTION public.eu_pessoa_do_usuario(uuid, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_pessoa_do_usuario(uuid, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Entregar e já devolver a lista, numa ida (só o servidor chama)
-- ---------------------------------------------------------------------------
-- A entrega é a de sempre (eu_entregar). Recusada, nada fica gravado (a
-- subtransação desfaz) e volta {erro}; o servidor apaga a foto da tentativa.
CREATE OR REPLACE FUNCTION public.eu_entregar_e_listar(p_contaid integer, p_funcionarioid integer,
                                                       p_atribuicaoid integer, p_caminho text,
                                                       p_observacao text, p_fotoidunico text,
                                                       p_semhorafoto boolean)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  t0 timestamptz := clock_timestamp();
  t1 timestamptz;
  v_id integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  BEGIN
    v_id := public.eu_entregar(p_contaid, p_funcionarioid, p_atribuicaoid, p_caminho,
                               p_observacao, p_fotoidunico, coalesce(p_semhorafoto, false));
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
  t1 := clock_timestamp();

  RETURN jsonb_build_object(
    'entregaid', v_id,
    'tarefas', public.eu_tarefas(p_contaid, p_funcionarioid),
    'tempos', jsonb_build_object('acao', public.ms_entre(t0, t1),
                                 'fila', public.ms_entre(t1, clock_timestamp())));
END;
$$;
REVOKE ALL ON FUNCTION public.eu_entregar_e_listar(integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_entregar_e_listar(integer, integer, integer, text, text, text, boolean)
  TO service_role;

COMMIT;
