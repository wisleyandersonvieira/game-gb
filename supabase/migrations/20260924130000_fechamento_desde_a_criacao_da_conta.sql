-- Etapa 1.11 (ajuste): o fechamento mensal não fecha meses anteriores à
-- criação da conta. Para conta nova, o primeiro mês fechado é o mês em que
-- ela foi criada. Fechamentos já feitos (ex.: agosto na conta de teste) ficam.

CREATE OR REPLACE FUNCTION public.rotina_fechamento_mensal(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_ref    date;
  v_ano    integer;
  v_mes    integer;
  v_inicio timestamptz := clock_timestamp();
  f        public.fechamentosmensais%ROWTYPE;
  v_linhas integer;
  v_acao   text;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  v_ref := (date_trunc('month', v_hoje) - interval '1 day')::date;   -- último dia do mês anterior
  v_ano := extract(year FROM v_ref)::integer;
  v_mes := extract(month FROM v_ref)::integer;

  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_FECHAMENTO_MENSAL', '08:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    -- Mês anterior à criação da conta não é fechado: o primeiro mês fechado é
    -- o mês em que a conta foi criada.
    IF make_date(v_ano, v_mes, 1) < (SELECT date_trunc('month', public.dia_em_sao_paulo(c.criadoem))::date
                                       FROM public.contas c WHERE c.contaid = p_contaid) THEN
      RETURN jsonb_build_object('acao', 'mes anterior a criacao da conta');
    END IF;
    -- Já rodou hoje?
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'fechamento_mensal' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    PERFORM pg_advisory_xact_lock(7312, p_contaid);
    SELECT * INTO f FROM public.fechamentosmensais
     WHERE contaid = p_contaid AND ano = v_ano AND mes = v_mes AND situacao <> 'substituido'
     FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.fechamentosmensais (contaid, ano, mes, versao, situacao, origem, definitivoem)
      VALUES (p_contaid, v_ano, v_mes, 1,
              CASE WHEN extract(day FROM v_hoje) <= 7 THEN 'provisorio' ELSE 'definitivo' END, 'rotina',
              CASE WHEN extract(day FROM v_hoje) > 7 THEN now() END)
      RETURNING * INTO f;
      -- Criado já definitivo quando a rotina ficou parada do dia 1 ao 7:
      -- as linhas novas entram uma vez (o gatilho só impede mudar ou apagar).
      v_acao := CASE WHEN f.situacao = 'provisorio' THEN 'criado provisorio' ELSE 'criado definitivo' END;
    ELSIF f.situacao = 'provisorio' THEN
      v_acao := CASE WHEN extract(day FROM v_hoje) <= 7 THEN 'refeito provisorio' ELSE 'refeito e definitivo' END;
    ELSE
      -- Mês já definitivo: nada a fazer (e nada a registrar).
      RETURN jsonb_build_object('acao', 'ja definitivo');
    END IF;

    v_linhas := public.fechamento_calcular(p_contaid, f.fechamentoid);
    IF extract(day FROM v_hoje) > 7 AND f.situacao = 'provisorio' THEN
      UPDATE public.fechamentosmensais SET situacao = 'definitivo', definitivoem = now()
       WHERE fechamentoid = f.fechamentoid;
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'fechamento_mensal', v_hoje, 'agendada', v_inicio, 'ok',
      jsonb_build_object('mes', to_char(v_ref, 'MM/YYYY'), 'acao', v_acao, 'linhas', v_linhas,
                         'fechamentoid', f.fechamentoid), NULL);
    RETURN jsonb_build_object('acao', v_acao, 'linhas', v_linhas);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'fechamento_mensal', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.rotina_fechamento_mensal(integer, timestamptz) FROM public, anon, authenticated;
