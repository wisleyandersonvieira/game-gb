-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 10: Conquistas.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-comunicados.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929259000_conquistas_permissoes.sql
--
-- O QUE MUDA: o catálogo de conquistas é só do master: criar, editar e ativar
-- por função; a gravação direta fecha. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 10: Conquistas (29/09/2026).
--
-- O catálogo de conquistas é da conta inteira, sem loja: pela régua do
-- alcance, só o master mexe nele. Criar já conferia a conta; agora reconhece o
-- gerente e o barra pelo sou_master. Editar e ativar/desativar, que a tela
-- fazia direto na tabela, viram funções só do master, e a gravação direta fecha.
-- Para o master nada muda. Nenhum dado é alterado.

-- criar_conquista: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.criar_conquista(p_nome text, p_descricao text, p_icone text, p_tipo text, p_valor integer, p_dias integer, p_bonus integer, p_retroativa boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_id     integer;
  v_novas  integer := 0;
  f        record;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Catálogo da conta, sem loja: só o master (régua do alcance, parte 2).
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à conquista.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_retroativa IS NULL THEN
    RAISE EXCEPTION 'Escolha se a conquista vale para o histórico ou só a partir de hoje.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.conquistas (contaid, nome, descricao, icone, criteriotipo, criteriovalor, criteriodias,
                                 pontosbonus, contardesde)
  VALUES (v_conta, btrim(p_nome), coalesce(nullif(btrim(p_descricao), ''), btrim(p_nome)),
          nullif(btrim(coalesce(p_icone, '')), ''), p_tipo, p_valor,
          CASE WHEN p_tipo = 'tarefas_aprovadas_periodo' THEN p_dias END,
          coalesce(p_bonus, 0),
          CASE WHEN p_retroativa THEN NULL ELSE now() END)
  RETURNING conquistaid INTO v_id;

  IF p_retroativa AND public.criterio_disponivel(p_tipo) THEN
    FOR f IN SELECT funcionarioid FROM public.funcionarios WHERE contaid = v_conta ORDER BY funcionarioid LOOP
      v_novas := v_novas + public.avaliar_conquistas(v_conta, f.funcionarioid);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('conquistaid', v_id, 'concedidas', v_novas);
END;
$function$;

CREATE OR REPLACE FUNCTION public.editar_conquista(p_conquistaid integer, p_nome text, p_descricao text,
                                                   p_icone text, p_bonus integer)
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
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à conquista.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_bonus IS NULL OR p_bonus < 0 THEN
    RAISE EXCEPTION 'Bônus precisa ser 0 ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.conquistas
     SET nome = btrim(p_nome), descricao = coalesce(nullif(btrim(coalesce(p_descricao, '')), ''), btrim(p_nome)),
         icone = nullif(btrim(coalesce(p_icone, '')), ''), pontosbonus = p_bonus
   WHERE contaid = v_conta AND conquistaid = p_conquistaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conquista não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.editar_conquista(integer, text, text, text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.editar_conquista(integer, text, text, text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.ativar_conquista(p_conquistaid integer, p_ativa boolean)
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
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta mexe no catálogo de conquistas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.conquistas SET ativa = coalesce(p_ativa, true) WHERE contaid = v_conta AND conquistaid = p_conquistaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conquista não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_conquista(integer, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_conquista(integer, boolean) TO authenticated;

-- A gravação direta no catálogo fecha (as funções acima fazem o mesmo).
REVOKE INSERT, UPDATE, DELETE ON public.conquistas FROM authenticated;
REVOKE UPDATE (ativa, descricao, icone, nome, pontosbonus) ON public.conquistas FROM authenticated;


COMMIT;
