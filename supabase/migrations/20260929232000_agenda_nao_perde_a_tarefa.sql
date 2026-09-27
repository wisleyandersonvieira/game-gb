-- Agendamento que não perde a tarefa de atender (29/09/2026, pedido do Wisley).
--
-- A tarefa "Atender agendamento" do responsável podia sumir da lista do dia,
-- sem aviso, em três casos da operação normal:
--   * o responsável saiu da loja (ou foi desligado) depois de marcado;
--   * a tarefa "Atender agendamento" foi desativada depois de marcado;
--   * o agendamento nasceu sem a tarefa — e remarcar ou trocar o
--     responsável não a recriava.
-- Agora:
--   * remarcar e trocar o responsável RECRIAM a tarefa que faltar (se a
--     tarefa modelo estiver ativa e o responsável trabalhar na loja);
--   * agendamentos_sem_tarefa lista, para a Agenda, os agendamentos futuros
--     cuja tarefa não vai aparecer, com o motivo de cada um;
--   * recriar_tarefa_do_agendamento é o botão "Recriar tarefa" da Agenda.

-- ---------------------------------------------------------------------------
-- 1. Garantir a tarefa de um agendamento (interna)
-- ---------------------------------------------------------------------------
-- Devolve true se a tarefa existe (ou foi recriada). Não recria com a tarefa
-- modelo desativada (vira aviso, como em criar_agendamento), nem com o
-- responsável fora da loja (aí a saída é trocar o responsável).
CREATE OR REPLACE FUNCTION public.garantir_tarefa_do_agendamento(p_agendamentoid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE; v_modelo integer;
BEGIN
  SELECT * INTO a FROM public.agendamentos WHERE agendamentoid = p_agendamentoid;
  IF NOT FOUND OR a.statusagendamento <> 'Confirmado' THEN
    RETURN false;
  END IF;
  -- Já tem tarefa em aberto, ou a tarefa já foi entregue: nada a fazer.
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
              WHERE ta.agendamentoid = a.agendamentoid
                AND (ta.datafimvigencia IS NULL OR public.tarefa_da_agenda_entregue(ta.atribuicaoid))) THEN
    RETURN true;
  END IF;
  SELECT tarefaid INTO v_modelo FROM public.tarefas
   WHERE contaid = a.contaid AND sistema = 'modelo_agendamento' AND ativa;
  IF v_modelo IS NULL THEN
    INSERT INTO public.avisossistema (contaid, tipo, texto)
    VALUES (a.contaid, 'rotina_sem_tarefa', left(
      'Agenda: o agendamento de ' || a.nomecliente || ' (' ||
      to_char(a.dataevento AT TIME ZONE public.fuso_da_conta(a.contaid), 'DD/MM/YYYY HH24:MI') ||
      ') continua SEM a tarefa de atender, porque a tarefa "Atender agendamento" está desativada ou foi apagada. Reative-a no Catálogo de tarefas.', 300));
    RETURN false;
  END IF;
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, a.funcionarioid) THEN
    RETURN false;
  END IF;
  PERFORM set_config('gamegb.agenda', 'sim', true);
  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataagendamento,
                                        descricaooverride, agendamentoid)
  VALUES (a.contaid, v_modelo, a.funcionarioid, a.lojaid, 'Unica', a.dataevento,
          public.texto_da_tarefa_agenda(a.dataevento, a.tipoevento), a.agendamentoid);
  PERFORM set_config('gamegb.agenda', '', true);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garantir_tarefa_do_agendamento(integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Remarcar e trocar o responsável recriam a tarefa que faltar
-- ---------------------------------------------------------------------------
-- Partem das versões mais recentes (20260922300000_agenda.sql), com o diff
-- conferido: só a chamada a garantir_tarefa_do_agendamento.
CREATE OR REPLACE FUNCTION public.remarcar_agendamento(p_agendamentoid integer, p_novadata timestamptz, p_motivo text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE; t record;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para remarcar agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_novadata IS NULL OR public.dia_em_sao_paulo(p_novadata) < public.dia_em_sao_paulo(now()) THEN
    RAISE EXCEPTION 'A nova data não pode estar no passado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_novadata = a.dataevento THEN
    RETURN;
  END IF;

  UPDATE public.agendamentos SET dataevento = p_novadata WHERE agendamentoid = a.agendamentoid;

  -- A tarefa vai junto, se ainda nao foi entregue.
  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas
         SET dataagendamento = p_novadata,
             descricaooverride = public.texto_da_tarefa_agenda(p_novadata, a.tipoevento)
       WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);
  -- Sem tarefa (criado sem ela, ou ela sumiu): recria, se der (29/09/2026).
  PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'remarcado',
    to_char(a.dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    to_char(p_novadata AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), p_motivo);
END;
$$;

CREATE OR REPLACE FUNCTION public.trocar_responsavel_agendamento(p_agendamentoid integer, p_funcionarioid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE; t record; v_antes text; v_depois text;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para trocar o responsável de agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_funcionarioid = a.funcionarioid THEN
    -- Mesma pessoa: nada muda, mas a tarefa que faltar é recriada.
    PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);
    RETURN;
  END IF;
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, p_funcionarioid) THEN
    RAISE EXCEPTION 'O responsável precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT nomecompleto INTO v_antes FROM public.funcionarios WHERE funcionarioid = a.funcionarioid;
  SELECT nomecompleto INTO v_depois FROM public.funcionarios WHERE funcionarioid = p_funcionarioid;

  UPDATE public.agendamentos SET funcionarioid = p_funcionarioid WHERE agendamentoid = a.agendamentoid;

  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas SET funcionarioid = p_funcionarioid WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);
  -- Sem tarefa (criado sem ela, ou ela sumiu): recria, já com o novo
  -- responsável (29/09/2026).
  PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'responsavel', v_antes, v_depois, NULL);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. O botão "Recriar tarefa" da Agenda
-- ---------------------------------------------------------------------------
-- A conta sai do login (agendamento_para_mudar confere que o agendamento é
-- da conta de quem pede e que a conta pode alterar dados).
CREATE OR REPLACE FUNCTION public.recriar_tarefa_do_agendamento(p_agendamentoid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, a.funcionarioid) THEN
    RAISE EXCEPTION 'O responsável deste agendamento não trabalha mais na loja: troque o responsável (a tarefa é recriada junto).'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = a.contaid AND sistema = 'modelo_agendamento' AND ativa) THEN
    RAISE EXCEPTION 'A tarefa "Atender agendamento" está desativada ou foi apagada: reative-a no Catálogo de tarefas.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN public.garantir_tarefa_do_agendamento(a.agendamentoid);
END;
$$;
REVOKE ALL ON FUNCTION public.recriar_tarefa_do_agendamento(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.recriar_tarefa_do_agendamento(integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Quais agendamentos futuros estão sem tarefa, e por quê
-- ---------------------------------------------------------------------------
-- SECURITY INVOKER: cada conta só enxerga os dela. Motivos:
--   'sem_tarefa'        — não há tarefa em aberto (nem entregue);
--   'tarefa_desativada' — há, mas "Atender agendamento" está desativada;
--   'responsavel_fora'  — há, mas o responsável não trabalha mais na loja.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH dia AS (SELECT (public.meu_hoje()->>'hoje')::date AS hoje, public.meu_hoje()->>'fuso' AS fuso),
  futuros AS (
    SELECT a.*, dia.fuso FROM public.agendamentos a, dia
     WHERE a.lojaid = p_lojaid AND a.statusagendamento = 'Confirmado'
       AND (a.dataevento AT TIME ZONE dia.fuso)::date >= dia.hoje
  ),
  situacao AS (
    SELECT f.*,
           ta.atribuicaoid,
           ta.datafimvigencia AS datafimvigencia_ta,
           EXISTS (SELECT 1 FROM public.entregas e
                    WHERE e.atribuicaoid = ta.atribuicaoid AND e.statusvalidacao IN ('Pendente', 'Aprovada')) AS entregue,
           t.ativa AS tarefaativa,
           EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                     JOIN public.funcionarios fu ON fu.contaid = fl.contaid AND fu.funcionarioid = fl.funcionarioid
                    WHERE fl.lojaid = f.lojaid AND fl.funcionarioid = ta.funcionarioid AND fl.ativo AND fu.ativo) AS respnaloja
      FROM futuros f
      -- A última tarefa do agendamento, em aberto ou não (a entregue e
      -- encerrada não é problema).
      LEFT JOIN LATERAL (SELECT x.* FROM public.tarefasatribuidas x
                          WHERE x.agendamentoid = f.agendamentoid
                          ORDER BY x.atribuicaoid DESC LIMIT 1) ta ON true
      LEFT JOIN public.tarefas t ON t.contaid = ta.contaid AND t.tarefaid = ta.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'agendamentoid', s.agendamentoid,
           'quando', to_char(s.dataevento AT TIME ZONE s.fuso, 'DD/MM/YYYY HH24:MI'),
           'cliente', s.nomecliente,
           'responsavel', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = s.funcionarioid),
           'motivo', CASE WHEN s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL THEN 'sem_tarefa'
                          WHEN NOT s.tarefaativa THEN 'tarefa_desativada'
                          ELSE 'responsavel_fora' END)
         ORDER BY s.dataevento), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
$$;
REVOKE ALL ON FUNCTION public.agendamentos_sem_tarefa(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.agendamentos_sem_tarefa(integer) TO authenticated;
