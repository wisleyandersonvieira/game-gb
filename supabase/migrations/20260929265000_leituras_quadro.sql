-- Usuários gerenciais, PARTE 3, fatia 2: o Quadro por loja (29/09/2026).
--
-- As leituras do Quadro ganham o ramo do gerente: validação (pendentes e
-- histórico), a lista para registrar entrega, a fila de um dia que passou, e as
-- tarefas de quem está de folga. O master segue pelo caminho de sempre (as
-- mesmas linhas); o gerente é desviado, no começo, para uma versão que lê SÓ a
-- loja pedida e só se ele pode (Quadro: ver; registrar entrega; passar folga).
-- As versões do gerente usam o "hoje" da conta (hoje_da_conta), nunca o relógio
-- de São Paulo escrito à mão.

-- ---------------------------------------------------------------------------
-- 1. Validação (pendentes e histórico)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.quadro_validacao_gerente(p_lojaid integer, p_de date, p_ate date, p_offset integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.conta_do_gerente();
  v_hoje  date;
  v_fuso  text;
  v_ate   date;
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  IF v_conta IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje := public.hoje_da_conta(v_conta);
  v_fuso := public.fuso_da_conta(v_conta);
  v_ate  := coalesce(p_ate, v_hoje - 1);
  v_de   := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$$;
REVOKE ALL ON FUNCTION public.quadro_validacao_gerente(integer, date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.quadro_validacao_gerente(integer, date, date, integer) TO authenticated;

-- quadro_validacao: parte da versão viva; muda só o desvio do gerente no começo.
CREATE OR REPLACE FUNCTION public.quadro_validacao(p_lojaid integer, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_dia   jsonb   := public.meu_hoje();
  v_hoje  date    := (v_dia->>'hoje')::date;
  v_fuso  text    := v_dia->>'fuso';
  v_ate   date    := coalesce(p_ate, (v_dia->>'hoje')::date - 1);
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.quadro_validacao_gerente(p_lojaid, p_de, p_ate, p_offset);
  END IF;
  v_de := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 -- Foto vencida (na fila para apagar) não aparece (29/09/2026).
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  -- O histórico não leva "sem hora da foto": a decisão já foi tomada.
  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    -- Pediu 51 para saber se tem mais; devolve 50.
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. A lista para registrar entrega em nome de alguém
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar_gerente(p_lojaid integer)
RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer,
              nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_da_conta(ctx.conta, ta.dataagendamento) < public.hoje_da_conta(ctx.conta)) AS atrasada
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid AND f.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND public.pode('quadro.registrar_entrega', p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.funcionarioid IS NOT NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, public.hoje_da_conta(ctx.conta), public.fuso_da_conta(ctx.conta))
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, public.hoje_da_conta(ctx.conta), false)
     AND NOT public.passada_hoje(ta.atribuicaoid, public.hoje_da_conta(ctx.conta))
     AND NOT EXISTS (
       SELECT 1 FROM public.entregas e
        WHERE e.contaid = ctx.conta AND e.atribuicaoid = ta.atribuicaoid
          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
          AND (ta.tipofrequencia = 'Unica' OR public.dia_da_conta(ctx.conta, e.dataenvio) = public.hoje_da_conta(ctx.conta)))
   ORDER BY f.nomecompleto, t.titulo
$$;
REVOKE ALL ON FUNCTION public.atribuicoes_para_entregar_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.atribuicoes_para_entregar_gerente(integer) TO authenticated;

-- atribuicoes_para_entregar: parte da versão viva; o gerente sai pela versão dele.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < hoje.dia) AS atrasada
  FROM public.tarefasatribuidas ta
  CROSS JOIN hoje
  JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
  JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
  WHERE ta.lojaid = p_lojaid
    AND ta.datafimvigencia IS NULL
    AND ta.funcionarioid IS NOT NULL
    AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, hoje.dia)
    AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, hoje.dia, false)
    AND NOT public.passada_hoje(ta.atribuicaoid, hoje.dia)
    AND NOT EXISTS (
      SELECT 1 FROM public.entregas e
      WHERE e.atribuicaoid = ta.atribuicaoid
        AND e.statusvalidacao IN ('Pendente', 'Aprovada')
        AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)
    )
    -- Ramo do gerente (parte 3): este caminho é o de sempre; o gerente vai
    -- para a versão dele, que lê só a loja pedida.
    AND NOT (public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL)
  UNION ALL
  SELECT g.* FROM public.atribuicoes_para_entregar_gerente(p_lojaid) g
   WHERE public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
  ORDER BY 5, 2
$function$;

-- ---------------------------------------------------------------------------
-- 3. A fila de um dia que passou
-- ---------------------------------------------------------------------------
-- Versão do gerente: a mesma leitura, com a conta dele escrita em cada tabela.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia_gerente(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_conta    integer := public.conta_do_gerente();
  v_hoje     date  := public.hoje_da_conta(public.conta_do_gerente());
  v_fuso     text  := public.fuso_da_conta(public.conta_do_gerente());
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
BEGIN
  IF v_conta IS NULL OR v_hoje IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid AND ta.contaid = v_conta
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid AND p.contaid = v_conta
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$$;
REVOKE ALL ON FUNCTION public.fila_de_um_dia_gerente(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fila_de_um_dia_gerente(integer, date) TO authenticated;

-- fila_de_um_dia: parte da versão viva; muda só o desvio do gerente.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_h        jsonb := public.meu_hoje();
  v_hoje     date  := (v_h->>'hoje')::date;
  v_fuso     text  := v_h->>'fuso';
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
  v_conta    integer := public.minha_conta();
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF v_conta IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fila_de_um_dia_gerente(p_lojaid, p_dia);
  END IF;
  IF v_conta IS NULL OR v_hoje IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$function$;

-- alcance_da_fila: parte da versão viva; responde também ao gerente (só datas).
CREATE OR REPLACE FUNCTION public.alcance_da_fila()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object('hoje', h.hoje, 'primeirodia', a.primeirodia)
    FROM (SELECT (public.meu_hoje()->>'hoje')::date AS hoje) h
    CROSS JOIN LATERAL public.fila_alcance(h.hoje) a
   WHERE (public.minha_conta() IS NOT NULL OR public.conta_do_gerente() IS NOT NULL) AND h.hoje IS NOT NULL
$function$;

-- ---------------------------------------------------------------------------
-- 4. Tarefas de quem está de folga (para passar a outra pessoa)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje_gerente(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta),
  hoje AS (SELECT public.hoje_da_conta(ctx.conta) AS dia, ctx.conta FROM ctx
            WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara, hoje.conta, hoje.dia
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(hoje.conta, hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia AND i.contaid = hoje.conta
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e
                                    WHERE e.contaid = it.conta AND e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_da_conta(it.conta, e.dataenvio) = it.dia)))
           ORDER BY f.nomecompleto, t.titulo), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid AND t.contaid = it.conta
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid AND f.contaid = it.conta
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara AND p.contaid = it.conta
$$;
REVOKE ALL ON FUNCTION public.tarefas_de_folga_hoje_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tarefas_de_folga_hoje_gerente(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje_gerente(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto), '[]'::jsonb)
    FROM ctx
    JOIN public.funcionarios f       ON f.contaid = ctx.conta AND f.ativo
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
                                    AND fl.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.hoje_da_conta(ctx.conta))
$$;
REVOKE ALL ON FUNCTION public.quem_trabalha_hoje_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.quem_trabalha_hoje_gerente(integer) TO authenticated;

-- tarefas_de_folga_hoje e quem_trabalha_hoje: partem das versões vivas; o
-- caminho de sempre fica dentro do ELSE, igual.
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.tarefas_de_folga_hoje_gerente(p_lojaid)
           ELSE (
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(public.minha_conta(), hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e, hoje
                                    WHERE e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)))
           ORDER BY f.nomecompleto, t.titulo), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara
           ) END
$function$;

CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.quem_trabalha_hoje_gerente(p_lojaid)
           ELSE (
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto), '[]'::jsonb)
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE f.ativo
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.dia_em_sao_paulo(now()))
           ) END
$function$;
