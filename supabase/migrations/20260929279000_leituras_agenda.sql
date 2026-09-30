-- Usuários gerenciais, PARTE 4, fatia 5: Agenda (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Agora, com
-- "Agenda: ver" na loja: os agendamentos, os anexos (a lista; o arquivo já
-- abria desde a decisão 1), o histórico, os avisos de agendamento sem tarefa
-- e de horário apertado. O VALOR (R$) só com "Ver valores em R$" na loja:
-- sem ela, o valor vem vazio e o histórico de pagamento/edição também. Os
-- tipos de evento são o catálogo da conta (só leitura).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- Os tipos de evento (catálogo da conta).
CREATE OR REPLACE FUNCTION public.tipos_de_evento()
RETURNS TABLE(tipoeventoid integer, nome character varying, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.tipoeventoid, t.nome, t.ativo
    FROM public.tiposevento t
   WHERE (public.sou_master() AND t.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND t.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('agenda.ver'))::integer[]) > 0)
   ORDER BY t.nome, t.tipoeventoid
$$;
REVOKE ALL ON FUNCTION public.tipos_de_evento() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tipos_de_evento() TO authenticated;

-- Os agendamentos de uma loja.
CREATE OR REPLACE FUNCTION public.agendamentos_da_loja(p_lojaid integer)
RETURNS TABLE(agendamentoid integer, contaid integer, lojaid integer, nomecliente character varying, cpfcliente character varying,
              telefonecliente character varying, tipoevento character varying, tipoeventoid integer, dataevento timestamptz,
              statusagendamento character varying, statuspagamento character varying, valor numeric, funcionarioid integer,
              observacoes text, aceitawhatsapp boolean, motivocancelamento text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.agendamentoid, a.contaid, a.lojaid, a.nomecliente, a.cpfcliente, a.telefonecliente, a.tipoevento, a.tipoeventoid,
         a.dataevento, a.statusagendamento, a.statuspagamento,
         CASE WHEN public.sou_master() OR public.pode('valores.ver_rs', p_lojaid) THEN a.valor END,
         a.funcionarioid, a.observacoes, a.aceitawhatsapp, a.motivocancelamento
    FROM public.agendamentos a
   WHERE a.lojaid = p_lojaid
     AND ((public.sou_master() AND a.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND a.contaid = public.conta_do_gerente() AND public.pode('agenda.ver', p_lojaid)))
   ORDER BY a.dataevento, a.agendamentoid
   LIMIT 500
$$;
REVOKE ALL ON FUNCTION public.agendamentos_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.agendamentos_da_loja(integer) TO authenticated;

-- A loja de um agendamento em que a pessoa logada vê a Agenda (ou nada).
CREATE OR REPLACE FUNCTION public.loja_do_agendamento_visivel(p_agendamentoid integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.lojaid FROM public.agendamentos a
   WHERE a.agendamentoid = p_agendamentoid
     AND ((public.sou_master() AND a.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND a.contaid = public.conta_do_gerente() AND public.pode('agenda.ver', a.lojaid)))
$$;
REVOKE ALL ON FUNCTION public.loja_do_agendamento_visivel(integer) FROM public, anon, authenticated;

-- Os anexos de um agendamento (a lista).
CREATE OR REPLACE FUNCTION public.anexos_do_agendamento(p_agendamentoid integer)
RETURNS TABLE(anexoid integer, caminho text, nomearquivo character varying, tamanho integer, enviadoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT x.anexoid, x.caminho, x.nomearquivo, x.tamanho, x.enviadoem
    FROM public.agendamentosanexos x
   WHERE x.agendamentoid = p_agendamentoid AND x.removidoem IS NULL
     AND x.lojaid = public.loja_do_agendamento_visivel(p_agendamentoid)
     AND x.contaid = coalesce(public.minha_conta(), public.conta_do_gerente())
   ORDER BY x.enviadoem, x.anexoid
$$;
REVOKE ALL ON FUNCTION public.anexos_do_agendamento(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.anexos_do_agendamento(integer) TO authenticated;

-- O histórico de um agendamento. Sem "Ver valores em R$", o que é de
-- pagamento ou edição vem sem os valores.
CREATE OR REPLACE FUNCTION public.historico_do_agendamento(p_agendamentoid integer)
RETURNS TABLE(historicoid integer, acao character varying, valoranterior text, valornovo text, motivo text, alteradoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.acao,
         CASE WHEN public.sou_master() OR public.pode('valores.ver_rs', h.lojaid) OR h.acao NOT IN ('pagamento', 'editado', 'criado')
              THEN h.valoranterior END,
         CASE WHEN public.sou_master() OR public.pode('valores.ver_rs', h.lojaid) OR h.acao NOT IN ('pagamento', 'editado', 'criado')
              THEN h.valornovo END,
         h.motivo, h.alteradoem
    FROM public.agendamentoshistorico h
   WHERE h.agendamentoid = p_agendamentoid
     AND h.lojaid = public.loja_do_agendamento_visivel(p_agendamentoid)
     AND h.contaid = coalesce(public.minha_conta(), public.conta_do_gerente())
   ORDER BY h.historicoid
$$;
REVOKE ALL ON FUNCTION public.historico_do_agendamento(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_do_agendamento(integer) TO authenticated;

-- Agendamentos sem tarefa, para o gerente que vê a Agenda na loja.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa_gerente(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH dia AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, public.hoje_da_conta(public.conta_do_gerente()) AS hoje,
           public.fuso_da_conta(public.conta_do_gerente()) AS fuso
  ),
  futuros AS (
    SELECT a.*, dia.fuso FROM public.agendamentos a, dia
     WHERE a.contaid = dia.conta AND public.pode('agenda.ver', p_lojaid)
       AND a.lojaid = p_lojaid AND a.statusagendamento = 'Confirmado'
       AND (a.dataevento AT TIME ZONE dia.fuso)::date >= dia.hoje
  ),
  situacao AS (
    SELECT f.*,
           ta.atribuicaoid,
           ta.datafimvigencia AS datafimvigencia_ta,
           EXISTS (SELECT 1 FROM public.entregas e
                    WHERE e.atribuicaoid = ta.atribuicaoid AND e.contaid = f.contaid AND e.statusvalidacao IN ('Pendente', 'Aprovada')) AS entregue,
           t.ativa AS tarefaativa,
           EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                     JOIN public.funcionarios fu ON fu.contaid = fl.contaid AND fu.funcionarioid = fl.funcionarioid
                    WHERE fl.lojaid = f.lojaid AND fl.funcionarioid = ta.funcionarioid AND fl.ativo AND fu.ativo) AS respnaloja
      FROM futuros f
      -- A última tarefa do agendamento, em aberto ou não (a entregue e
      -- encerrada não é problema).
      LEFT JOIN LATERAL (SELECT x.* FROM public.tarefasatribuidas x
                          WHERE x.agendamentoid = f.agendamentoid AND x.contaid = f.contaid
                          ORDER BY x.atribuicaoid DESC LIMIT 1) ta ON true
      LEFT JOIN public.tarefas t ON t.contaid = ta.contaid AND t.tarefaid = ta.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'agendamentoid', s.agendamentoid,
           'quando', to_char(s.dataevento AT TIME ZONE s.fuso, 'DD/MM/YYYY HH24:MI'),
           'cliente', s.nomecliente,
           'responsavel', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = s.funcionarioid AND contaid = s.contaid),
           'motivo', CASE WHEN s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL THEN 'sem_tarefa'
                          WHEN NOT s.tarefaativa THEN 'tarefa_desativada'
                          ELSE 'responsavel_fora' END)
         ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
$function$;
REVOKE ALL ON FUNCTION public.agendamentos_sem_tarefa_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.agendamentos_sem_tarefa_gerente(integer) TO authenticated;

-- agendamentos_sem_tarefa: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa(p_lojaid integer)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.agendamentos_sem_tarefa_gerente(p_lojaid);
  END IF;
  RETURN (
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
         ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
  );
END;
$function$;

-- Horário apertado (2 horas antes ou depois), para o gerente que vê a Agenda na loja.
CREATE OR REPLACE FUNCTION public.conflitos_agendamento_gerente(p_lojaid integer, p_dataevento timestamp with time zone, p_ignorar integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object('quando', dataevento, 'tipo', tipoevento) ORDER BY dataevento, agendamentoid), '[]'::jsonb)
    FROM public.agendamentos
   WHERE contaid = public.conta_do_gerente() AND public.pode('agenda.ver', p_lojaid)
     AND lojaid = p_lojaid AND statusagendamento = 'Confirmado'
     AND (p_ignorar IS NULL OR agendamentoid <> p_ignorar)
     AND dataevento BETWEEN p_dataevento - interval '2 hours' AND p_dataevento + interval '2 hours'
$function$;
REVOKE ALL ON FUNCTION public.conflitos_agendamento_gerente(integer, timestamp with time zone, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conflitos_agendamento_gerente(integer, timestamp with time zone, integer) TO authenticated;

-- conflitos_agendamento: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.conflitos_agendamento(p_lojaid integer, p_dataevento timestamp with time zone, p_ignorar integer DEFAULT NULL::integer)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.conflitos_agendamento_gerente(p_lojaid, p_dataevento, p_ignorar);
  END IF;
  RETURN (
  SELECT coalesce(jsonb_agg(jsonb_build_object('quando', dataevento, 'tipo', tipoevento) ORDER BY dataevento, agendamentoid), '[]'::jsonb)
    FROM public.agendamentos
   WHERE lojaid = p_lojaid AND statusagendamento = 'Confirmado'
     AND (p_ignorar IS NULL OR agendamentoid <> p_ignorar)
     AND dataevento BETWEEN p_dataevento - interval '2 hours' AND p_dataevento + interval '2 hours'
  );
END;
$function$;
