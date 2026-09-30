-- Usuários gerenciais, PARTE 4, fatia 3: Feedbacks, Justificativas e
-- Solicitações (30/09/2026). As telas liam as tabelas direto e vinham vazias
-- para o gerente. Agora cada uma lê por uma função:
--   * o master recebe o mesmo de antes (a conta dele, na mesma ordem);
--   * o gerente: feedbacks de quem tem UMA loja em comum com ele onde ele vê
--     Feedbacks (é dia a dia, decisão 4); justificativas e solicitações pela
--     LOJA delas (onde ele vê a tela);
--   * qualquer outro login: nada.
-- Nenhum dado é alterado. Classificação: ACRESCENTA.

-- As pessoas de UMA loja (formulários de uma tela).
CREATE OR REPLACE FUNCTION public.pessoas_da_loja(p_lojaid integer, p_codigo text)
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, f.ativo
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.contaid = f.contaid
                                    AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente() AND public.pode(p_codigo, p_lojaid))
   ORDER BY f.nomecompleto, f.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.pessoas_da_loja(integer, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pessoas_da_loja(integer, text) TO authenticated;

-- Feedbacks de um período.
CREATE OR REPLACE FUNCTION public.feedbacks_do_periodo(p_de date, p_ate date, p_funcionarioid integer DEFAULT NULL)
RETURNS TABLE(feedbackid integer, funcionarioid integer, datafeedback date, notadia integer, comentario character varying,
              origem character varying, pontosbonus integer, anuladoem timestamptz, motivoanulacao text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fb.feedbackid, fb.funcionarioid, fb.datafeedback, fb.notadia, fb.comentario, fb.origem, fb.pontosbonus,
         fb.anuladoem, fb.motivoanulacao
    FROM public.feedbacks fb
   WHERE fb.datafeedback BETWEEN p_de AND p_ate
     AND (p_funcionarioid IS NULL OR fb.funcionarioid = p_funcionarioid)
     AND ((public.sou_master() AND fb.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND fb.contaid = public.conta_do_gerente()
           AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                        WHERE fl.contaid = fb.contaid AND fl.funcionarioid = fb.funcionarioid AND fl.ativo
                          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('feedbacks.ver'))::integer[]))))
   ORDER BY fb.datafeedback DESC, fb.feedbackid DESC
   LIMIT 500
$$;
REVOKE ALL ON FUNCTION public.feedbacks_do_periodo(date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.feedbacks_do_periodo(date, date, integer) TO authenticated;

-- As justificativas da tela, já com o nome da pessoa, da tarefa e da loja.
CREATE OR REPLACE FUNCTION public.justificativas_da_tela()
RETURNS TABLE(justificativaid integer, atribuicaoid integer, funcionarioid integer, lojaid integer, dia date,
              motivo text, status character varying, origem character varying, motivorecusa text,
              pessoa character varying, tarefa character varying, loja character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT j.justificativaid, j.atribuicaoid, j.funcionarioid, j.lojaid, j.dia, j.motivo, j.status, j.origem, j.motivorecusa,
         f.nomecompleto, t.titulo, l.nome
    FROM public.justificativas j
    LEFT JOIN public.funcionarios f       ON f.funcionarioid = j.funcionarioid AND f.contaid = j.contaid
    LEFT JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid AND ta.contaid = j.contaid
    LEFT JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = j.contaid
    LEFT JOIN public.lojas l              ON l.lojaid = j.lojaid AND l.contaid = j.contaid
   WHERE (public.sou_master() AND j.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente()
          AND j.lojaid = ANY ((SELECT public.lojas_onde_posso('justificativas.ver'))::integer[]))
   ORDER BY j.dia DESC, j.justificativaid DESC
   LIMIT 300
$$;
REVOKE ALL ON FUNCTION public.justificativas_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.justificativas_da_tela() TO authenticated;

-- As solicitações de uma loja, com o nome de quem pediu.
CREATE OR REPLACE FUNCTION public.solicitacoes_da_loja(p_lojaid integer)
RETURNS TABLE(solicitacaoid integer, tipo character varying, categoria character varying, descricao text, quantidade numeric,
              unidade character varying, status character varying, motivorecusa text, datasolicitacao timestamptz,
              funcionarioid integer, observacao text, nomecompleto character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.solicitacaoid, s.tipo, s.categoria, s.descricao, s.quantidade, s.unidade, s.status, s.motivorecusa,
         s.datasolicitacao, s.funcionarioid, s.observacao, f.nomecompleto
    FROM public.solicitacoesinternas s
    LEFT JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.contaid = s.contaid
   WHERE s.lojaid = p_lojaid
     AND ((public.sou_master() AND s.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente() AND public.pode('solicitacoes.ver', p_lojaid)))
   ORDER BY s.datasolicitacao DESC, s.solicitacaoid DESC
   LIMIT 300
$$;
REVOKE ALL ON FUNCTION public.solicitacoes_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.solicitacoes_da_loja(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.historico_das_solicitacoes(p_lojaid integer)
RETURNS TABLE(historicoid integer, solicitacaoid integer, statusanterior character varying, statusnovo character varying,
              observacao text, alteradoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.solicitacaoid, h.statusanterior, h.statusnovo, h.observacao, h.alteradoem
    FROM public.solicitacoeshistorico h
   WHERE h.lojaid = p_lojaid
     AND ((public.sou_master() AND h.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND h.contaid = public.conta_do_gerente() AND public.pode('solicitacoes.ver', p_lojaid)))
   ORDER BY h.historicoid
$$;
REVOKE ALL ON FUNCTION public.historico_das_solicitacoes(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_das_solicitacoes(integer) TO authenticated;

-- O que dá para justificar, para o gerente: só tarefas das lojas em que ele
-- registra justificativa. O dia é o do fuso da conta (buscado uma vez).
CREATE OR REPLACE FUNCTION public.justificaveis_gerente(p_funcionarioid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- O fuso, o dia de hoje e as lojas dele saem UMA vez.
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta,
           public.fuso_da_conta(public.conta_do_gerente()) AS fuso,
           public.hoje_da_conta(public.conta_do_gerente()) AS hoje,
           (SELECT public.lojas_onde_posso('justificativas.registrar'))::integer[] AS lojas
  ),
  pessoa AS (
    SELECT f.contaid, f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento
      FROM public.funcionarios f, ctx WHERE f.funcionarioid = p_funcionarioid AND f.contaid = ctx.conta
  ),
  congelado AS (
    SELECT p_dia < ctx.hoje
           AND EXISTS (SELECT 1 FROM public.diasgerados dg, pessoa
                        WHERE dg.contaid = pessoa.contaid AND dg.dia = p_dia) AS sim
      FROM ctx
  ),
  itens AS (
    -- Dia com lista congelada.
    SELECT i.atribuicaoid, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN pessoa ON pessoa.contaid = i.contaid
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid AND t.contaid = i.contaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid AND l.contaid = i.contaid
      CROSS JOIN congelado
      CROSS JOIN ctx
     WHERE congelado.sim
       AND i.lojaid = ANY (ctx.lojas)
       AND i.funcionarioid = p_funcionarioid AND i.dia = p_dia AND i.situacao = 'devida'
       AND NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, p_dia, false)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid AND e.contaid = ctx.conta
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_no_fuso(e.dataenvio, ctx.fuso) = p_dia))
    UNION ALL
    -- Hoje, ou dia sem lista: regra do cadastro.
    SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid AND t.contaid = ta.contaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid AND l.contaid = ta.contaid
      CROSS JOIN pessoa
      CROSS JOIN congelado
      CROSS JOIN ctx
     WHERE NOT congelado.sim
       AND ta.contaid = ctx.conta
       AND ta.lojaid = ANY (ctx.lojas)
       AND ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND p_dia <= ctx.hoje
       AND public.dia_de_trabalho(pessoa.diadefolga, pessoa.domingofolgamensal,
                                  pessoa.datainicioafastamento, pessoa.datafimafastamento, p_dia)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, p_dia, false)
       AND (
         (ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
          AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, p_dia)
          AND p_dia >= coalesce(public.dia_no_fuso(ta.dataatribuicao, ctx.fuso), p_dia)
          AND p_dia >= coalesce(ta.datainiciovigencia, p_dia)
          AND (ta.datafimvigencia IS NULL OR p_dia < ta.datafimvigencia)
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid AND e.contaid = ctx.conta
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                             AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = p_dia))
         OR
         (ta.tipofrequencia = 'Unica'
          AND ta.datafimvigencia IS NULL
          AND public.dia_no_fuso(coalesce(ta.dataagendamento, ta.dataatribuicao), ctx.fuso) = p_dia
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid AND e.contaid = ctx.conta
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')))
       )
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('atribuicaoid', atribuicaoid, 'titulo', titulo,
                                               'pontos', pontos, 'loja', loja) ORDER BY titulo), '[]'::jsonb)
    FROM itens
$function$;
REVOKE ALL ON FUNCTION public.justificaveis_gerente(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.justificaveis_gerente(integer, date) TO authenticated;

-- justificaveis: parte da versão viva (de 20260924100000_rotinas_lista_do_dia.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.justificaveis(p_funcionarioid integer, p_dia date)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.justificaveis_gerente(p_funcionarioid, p_dia);
  END IF;
  RETURN (
  WITH pessoa AS (
    SELECT f.contaid, f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento
      FROM public.funcionarios f WHERE f.funcionarioid = p_funcionarioid
  ),
  congelado AS (
    SELECT p_dia < public.dia_em_sao_paulo(now())
           AND EXISTS (SELECT 1 FROM public.diasgerados dg, pessoa
                        WHERE dg.contaid = pessoa.contaid AND dg.dia = p_dia) AS sim
  ),
  itens AS (
    -- Dia com lista congelada.
    SELECT i.atribuicaoid, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN pessoa ON pessoa.contaid = i.contaid
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid
      CROSS JOIN congelado
     WHERE congelado.sim
       AND i.funcionarioid = p_funcionarioid AND i.dia = p_dia AND i.situacao = 'devida'
       AND NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, p_dia, false)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = p_dia))
    UNION ALL
    -- Hoje, ou dia sem lista: regra do cadastro.
    SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN pessoa
      CROSS JOIN congelado
     WHERE NOT congelado.sim
       AND ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND p_dia <= public.dia_em_sao_paulo(now())
       AND public.dia_de_trabalho(pessoa.diadefolga, pessoa.domingofolgamensal,
                                  pessoa.datainicioafastamento, pessoa.datafimafastamento, p_dia)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, p_dia, false)
       AND (
         (ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
          AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, p_dia)
          AND p_dia >= coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), p_dia)
          AND p_dia >= coalesce(ta.datainiciovigencia, p_dia)
          AND (ta.datafimvigencia IS NULL OR p_dia < ta.datafimvigencia)
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                             AND public.dia_em_sao_paulo(e.dataenvio) = p_dia))
         OR
         (ta.tipofrequencia = 'Unica'
          AND ta.datafimvigencia IS NULL
          AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) = p_dia
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')))
       )
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('atribuicaoid', atribuicaoid, 'titulo', titulo,
                                               'pontos', pontos, 'loja', loja) ORDER BY titulo), '[]'::jsonb)
    FROM itens
  );
END;
$function$;
