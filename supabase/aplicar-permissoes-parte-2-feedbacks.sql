-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 3: Feedbacks.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-premios.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929252000_feedbacks_permissoes.sql
--
-- O QUE MUDA: dar e anular feedback conferem a permissão sobre a pessoa; o
-- feedback anulado entra na lista de estornos. Para o master nada muda.
-- Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 3: Feedbacks (29/09/2026).
--
-- O feedback é sobre uma PESSOA (não tem loja) e dá pontos. O gerente só dá
-- ou anula feedback de quem está INTEIRAMENTE dentro das lojas em que ele tem
-- a permissão (a mesma borda do "desativar pessoa"; decisão mais restritiva,
-- anotada para o Wisley), e nunca de si mesmo. Anular entra na lista de
-- estornos do master. Para o master nada muda.

-- ---------------------------------------------------------------------------
-- 1. pode_na_pessoa: a permissão sobre uma pessoa (não sobre uma loja)
-- ---------------------------------------------------------------------------
-- Master: pode() da conta (como sempre). Gerente: a pessoa tem pelo menos uma
-- loja ativa, e em TODAS elas ele tem a permissão. Interna.
CREATE OR REPLACE FUNCTION public.pode_na_pessoa(p_codigo text, p_contaid integer, p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN public.sou_master() THEN public.pode(p_codigo)
    ELSE EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid AND fl.ativo)
     AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                      WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                        AND NOT public.pode(p_codigo, fl.lojaid))
  END
$$;
REVOKE ALL ON FUNCTION public.pode_na_pessoa(text, integer, integer) FROM public, anon, authenticated;

-- registrar_feedback: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.registrar_feedback(p_funcionarioid integer, p_dia date, p_nota integer, p_comentario text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_hoje   date    := public.dia_em_sao_paulo(now());
  v_func   public.funcionarios%ROWTYPE;
  v_bonus  integer;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode_na_pessoa('feedbacks.registrar', v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Seu cargo não permite dar feedback a esta pessoa (ela precisa estar só nas suas lojas).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém dá feedback de si mesmo (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém dá feedback de si mesmo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_func.ativo THEN
    RAISE EXCEPTION 'Esta pessoa está inativa.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia IS NULL OR p_dia NOT IN (v_hoje, v_hoje - 1) THEN
    RAISE EXCEPTION 'O feedback só pode ser de hoje ou de ontem.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 0 AND 10 THEN
    RAISE EXCEPTION 'A nota vai de 0 a 10.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT CASE WHEN valor ~ '^[0-9]+$' THEN valor::integer ELSE 0 END INTO v_bonus
    FROM public.configuracoes WHERE contaid = v_conta AND chave = 'PONTOS_BONUS_FEEDBACK_DIARIO';
  v_bonus := coalesce(v_bonus, 0);

  BEGIN
    INSERT INTO public.feedbacks (contaid, funcionarioid, datafeedback, notadia, comentario, origem, registradopor, pontosbonus)
    VALUES (v_conta, p_funcionarioid, p_dia, p_nota, nullif(btrim(coalesce(p_comentario, '')), ''), public.origem_da_acao('bot'), auth.uid(), v_bonus)
    RETURNING feedbackid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION '% já tem feedback de %.', v_func.nomecompleto, to_char(p_dia, 'DD/MM/YYYY')
      USING ERRCODE = 'unique_violation';
  END;

  IF v_bonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, p_funcionarioid, 'bonus', v_bonus,
            'Feedback do dia ' || to_char(p_dia, 'DD/MM/YYYY'), v_id, auth.uid());
  END IF;

  PERFORM public.avaliar_conquistas(v_conta, p_funcionarioid);
  RETURN v_id;
END;
$function$;

-- anular_feedback: parte da versão viva no banco
CREATE OR REPLACE FUNCTION public.anular_feedback(p_feedbackid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_fb    public.feedbacks%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_fb FROM public.feedbacks WHERE feedbackid = p_feedbackid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Feedback não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode_na_pessoa('feedbacks.anular', v_conta, v_fb.funcionarioid) THEN
    RAISE EXCEPTION 'Seu cargo não permite anular feedback desta pessoa (ela precisa estar só nas suas lojas).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém anula feedback de si mesmo (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_fb.funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém anula feedback de si mesmo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_fb.anuladoem IS NOT NULL THEN
    RAISE EXCEPTION 'Este feedback já foi anulado.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.feedbacks
     SET anuladoem = now(), anuladopor = auth.uid(), motivoanulacao = btrim(p_motivo)
   WHERE feedbackid = p_feedbackid;

  IF v_fb.pontosbonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, v_fb.funcionarioid, 'estorno_bonus', -v_fb.pontosbonus,
            'Feedback do dia ' || to_char(v_fb.datafeedback, 'DD/MM/YYYY') || ' anulado: ' || btrim(p_motivo),
            p_feedbackid, auth.uid());
  END IF;
END;
$function$;

-- estornos_da_conta: parte de 20260929251000_premios_permissoes.sql (entram os feedbacks anulados)
CREATE OR REPLACE FUNCTION public.estornos_da_conta(p_lojaid integer DEFAULT NULL)
RETURNS TABLE (tipo text, quando timestamptz, lojaid integer, loja text, pessoa text,
               descricao text, pontos integer, motivo text, quem text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta vê a lista de estornos.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT 'entrega'::text, e.dataestorno, e.lojaid, l.nome::text, f.nomecompleto::text,
         t.titulo::text, -coalesce(e.pontosganhos, 0), e.motivoestorno::text,
         coalesce(public.autor_em(e.estornadopor, e.dataestorno), 'desconhecido')
    FROM public.entregas e
    JOIN public.lojas l ON l.contaid = e.contaid AND l.lojaid = e.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = e.contaid AND f.funcionarioid = e.funcionarioid
    LEFT JOIN public.tarefas t ON t.contaid = e.contaid AND t.tarefaid = e.tarefaid
   WHERE e.contaid = v_conta AND e.statusvalidacao = 'Estornada'
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  UNION ALL
  -- Resgates cancelados (antes de entregar) e estornados (depois): os pontos
  -- voltam para a pessoa. Resgate registrado sem loja só aparece na lista de
  -- todas as lojas (p_lojaid vazio).
  SELECT CASE r.status WHEN 'Cancelado' THEN 'resgate cancelado' ELSE 'resgate estornado' END,
         CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END,
         r.lojaid, l.nome::text, f.nomecompleto::text,
         CASE WHEN r.valorreais IS NOT NULL THEN 'abate na comanda de ' || public.reais(r.valorreais) ELSE p.nome::text END,
         r.pontosgastos,
         (CASE r.status WHEN 'Cancelado' THEN r.motivocancelamento ELSE r.motivoestorno END)::text,
         coalesce(public.autor_em(CASE r.status WHEN 'Cancelado' THEN r.canceladopor ELSE r.estornadopor END,
                                  CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END), 'desconhecido')
    FROM public.resgates r
    LEFT JOIN public.lojas l ON l.contaid = r.contaid AND l.lojaid = r.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = r.contaid AND f.funcionarioid = r.funcionarioid
    LEFT JOIN public.produtosloja p ON p.contaid = r.contaid AND p.produtoid = r.produtoid
   WHERE r.contaid = v_conta AND r.status IN ('Cancelado', 'Estornado')
     AND (p_lojaid IS NULL OR r.lojaid = p_lojaid)
  UNION ALL
  -- Feedbacks anulados: o bônus sai de volta da pessoa. Feedback não tem
  -- loja: aparece na lista de todas as lojas e na de cada loja da pessoa.
  SELECT 'feedback anulado', fb.anuladoem, NULL::integer, NULL::text, f.nomecompleto::text,
         'Feedback de ' || to_char(fb.datafeedback, 'DD/MM/YYYY') || ' (nota ' || fb.notadia || ')',
         -coalesce(fb.pontosbonus, 0), fb.motivoanulacao::text,
         coalesce(public.autor_em(fb.anuladopor, fb.anuladoem), 'desconhecido')
    FROM public.feedbacks fb
    LEFT JOIN public.funcionarios f ON f.contaid = fb.contaid AND f.funcionarioid = fb.funcionarioid
   WHERE fb.contaid = v_conta AND fb.anuladoem IS NOT NULL
     AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.contaid = fb.contaid AND fl.funcionarioid = fb.funcionarioid AND fl.lojaid = p_lojaid))
   -- Desempate fixo: dois estornos no mesmo instante saem sempre na mesma ordem.
   ORDER BY 2 DESC, 1, 6, 5, 9, 8
   LIMIT 500;
END;
$$;

COMMIT;
