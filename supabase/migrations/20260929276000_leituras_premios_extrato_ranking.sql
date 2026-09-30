-- Usuários gerenciais, PARTE 4, fatia 2: Prêmios, Extrato e Ranking (30/09/2026).
--
-- As telas liam tabelas direto (e as regras das tabelas não deixam o gerente
-- ler nada), então vinham VAZIAS para ele. Agora:
--   * pessoas_para(permissão): a lista de pessoas de uma tela. O master
--     recebe o mesmo de antes; o gerente, as pessoas com uma loja em comum
--     com ele onde ele tem aquela permissão; qualquer outro, nada.
--   * Prêmios ("Prêmios: ver"): o catálogo (é da conta inteira, só leitura),
--     a taxa, e os resgates só das lojas dele (resgate sem loja: só o master).
--   * Extrato ("Extrato: ver"): só de quem tem TODAS as lojas dentro das dele
--     (a mesma regra do histórico da pessoa, parte 3).
--   * Ranking ("Ranking: ver"): só por loja dele; "todas as lojas" do mês
--     aberto soma só as lojas dele; o fechado e a nota do mês, só por loja.
-- Para o master nada muda: cada função desvia o gerente logo no começo e
-- segue pelo caminho de sempre. Nenhum dado é alterado.
-- Classificação: ACRESCENTA.

-- A lista de pessoas de uma tela.
CREATE OR REPLACE FUNCTION public.pessoas_para(p_codigo text)
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, ativo boolean,
              saldopontos integer, pontostotal integer, jornadaid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, f.ativo, f.saldopontos, f.pontostotal, f.jornadaid
    FROM public.funcionarios f
   WHERE public.sou_master() AND f.contaid = public.minha_conta()
  UNION ALL
  SELECT f.funcionarioid, f.nomecompleto, f.ativo, f.saldopontos, f.pontostotal, f.jornadaid
    FROM public.funcionarios f
   WHERE NOT public.sou_master()
     AND f.contaid = public.conta_do_gerente()
     AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
                    AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso(p_codigo))::integer[]))
   ORDER BY 2, 1
$$;
REVOKE ALL ON FUNCTION public.pessoas_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pessoas_para(text) TO authenticated;

-- O catálogo de prêmios: da conta inteira, só leitura.
CREATE OR REPLACE FUNCTION public.premios_do_catalogo()
RETURNS TABLE(produtoid integer, nome character varying, descricao text, custoempontos integer,
              estoquedisponivel integer, ativo boolean, sistema character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.produtoid, p.nome, p.descricao, p.custoempontos, p.estoquedisponivel, p.ativo, p.sistema
    FROM public.produtosloja p
   WHERE (public.sou_master() AND p.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND p.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('premios.ver'))::integer[]) > 0)
   ORDER BY p.custoempontos, p.nome, p.produtoid
$$;
REVOKE ALL ON FUNCTION public.premios_do_catalogo() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.premios_do_catalogo() TO authenticated;

-- A taxa de conversão, para o gerente que vê Prêmios ou Extrato.
CREATE OR REPLACE FUNCTION public.minha_taxa_gerente()
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gerente(); v_texto text; v_taxa numeric;
BEGIN
  IF v_conta IS NULL OR (cardinality(public.lojas_onde_posso('premios.ver')) = 0
                         AND cardinality(public.lojas_onde_posso('extrato.ver')) = 0) THEN
    RETURN NULL;
  END IF;
  SELECT valor INTO v_texto FROM public.configuracoes WHERE contaid = v_conta AND chave = 'TAXA_CONVERSAO_PONTO_REAL';
  BEGIN
    v_taxa := nullif(replace(btrim(coalesce(v_texto, '')), ',', '.'), '')::numeric;
  EXCEPTION WHEN others THEN
    v_taxa := NULL;
  END;
  RETURN CASE WHEN v_taxa > 0 THEN v_taxa END;
END;
$$;
REVOKE ALL ON FUNCTION public.minha_taxa_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.minha_taxa_gerente() TO authenticated;

-- minha_taxa: parte da versão viva (de 20260921140000_loja_resgates_extrato.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.minha_taxa()
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_texto text; v_taxa numeric;
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.minha_taxa_gerente();
  END IF;
  SELECT valor INTO v_texto FROM public.configuracoes WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL';
  BEGIN
    v_taxa := nullif(replace(btrim(coalesce(v_texto, '')), ',', '.'), '')::numeric;
  EXCEPTION WHEN others THEN
    v_taxa := NULL;
  END;
  RETURN CASE WHEN v_taxa > 0 THEN v_taxa END;
END;
$function$;

-- Os resgates que o gerente vê: só das lojas em que ele vê Prêmios.
CREATE OR REPLACE FUNCTION public.listar_trocas_gerente(p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         r.valorreais,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          ELSE p.nome END,
               'loja',               l.nome,
               -- De onde veio: "colaborador" quando foi pelo celular. Vazio
               -- nos resgates que o gestor registrou, inclusive os antigos.
               'origem',             r.origem) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid AND f.contaid = r.contaid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid AND p.contaid = r.contaid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid AND l.contaid = r.contaid
       WHERE r.contaid = public.conta_do_gerente()
         AND r.lojaid = ANY ((SELECT public.lojas_onde_posso('premios.ver'))::integer[])
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
$function$;
REVOKE ALL ON FUNCTION public.listar_trocas_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.listar_trocas_gerente(integer) TO authenticated;

-- listar_trocas: parte da versão viva (de 20260929101000_colaborador_pede_resgate.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.listar_trocas(p_limite integer DEFAULT 100)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.listar_trocas_gerente(p_limite);
  END IF;
  RETURN (
SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         r.valorreais,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          ELSE p.nome END,
               'loja',               l.nome,
               -- De onde veio: "colaborador" quando foi pelo celular. Vazio
               -- nos resgates que o gestor registrou, inclusive os antigos.
               'origem',             r.origem) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
  );
END;
$function$;

-- O extrato que o gerente vê: só de quem está INTEIRO nas lojas em que ele vê
-- o Extrato. O dia é o do fuso da conta (buscado uma vez).
CREATE OR REPLACE FUNCTION public.extrato_pontos_gerente(p_funcionarioid integer, p_de date, p_ate date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.conta_do_gerente();
  v_fuso    text;
  v_nome    text; v_saldo integer; v_inicial integer; v_periodo integer; v_soma integer; v_mov jsonb;
BEGIN
  IF v_conta IS NULL OR NOT coalesce(public.pode_na_pessoa('extrato.ver', v_conta, p_funcionarioid), false) THEN
    RETURN NULL;
  END IF;
  v_fuso := public.fuso_da_conta(v_conta);
  SELECT nomecompleto, saldopontos INTO v_nome, v_saldo
    FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT coalesce(sum(pontos), 0) INTO v_inicial FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND public.dia_no_fuso(datamovimento, v_fuso) < p_de;
  SELECT coalesce(sum(pontos), 0) INTO v_periodo FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND public.dia_no_fuso(datamovimento, v_fuso) BETWEEN p_de AND p_ate;
  SELECT coalesce(sum(pontos), 0) INTO v_soma FROM public.movimentospontos
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid;
  WITH todos AS (
    SELECT m.*, sum(m.pontos) OVER (ORDER BY m.datamovimento, m.movimentoid) AS saldoapos
      FROM public.movimentospontos m
     WHERE m.contaid = v_conta AND m.funcionarioid = p_funcionarioid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'data', t.datamovimento, 'tipo', t.tipo, 'descricao', t.descricao,
           'loja', l.nome, 'pontos', t.pontos, 'saldoapos', t.saldoapos)
           ORDER BY t.datamovimento, t.movimentoid), '[]'::jsonb)
    INTO v_mov
    FROM todos t
    LEFT JOIN public.lojas l ON l.lojaid = t.lojaid AND l.contaid = v_conta
   WHERE public.dia_no_fuso(t.datamovimento, v_fuso) BETWEEN p_de AND p_ate;
  RETURN jsonb_build_object('nome', v_nome, 'saldoatual', v_saldo, 'saldoinicial', v_inicial,
                            'saldofinal', v_inicial + v_periodo, 'confere', v_soma = v_saldo,
                            'taxa', public.minha_taxa_gerente(), 'movimentos', v_mov);
END;
$$;
REVOKE ALL ON FUNCTION public.extrato_pontos_gerente(integer, date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.extrato_pontos_gerente(integer, date, date) TO authenticated;

-- extrato_pontos: parte da versão viva (de 20260921140000_loja_resgates_extrato.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.extrato_pontos(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_nome     text;
  v_conta    integer;
  v_saldo    integer;
  v_inicial  integer;
  v_periodo  integer;
  v_soma     integer;
  v_mov      jsonb;
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.extrato_pontos_gerente(p_funcionarioid, p_de, p_ate);
  END IF;
  SELECT nomecompleto, contaid, saldopontos INTO v_nome, v_conta, v_saldo
    FROM public.funcionarios WHERE funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT coalesce(sum(pontos), 0) INTO v_inicial FROM public.movimentospontos
   WHERE funcionarioid = p_funcionarioid AND public.dia_em_sao_paulo(datamovimento) < p_de;

  SELECT coalesce(sum(pontos), 0) INTO v_periodo FROM public.movimentospontos
   WHERE funcionarioid = p_funcionarioid AND public.dia_em_sao_paulo(datamovimento) BETWEEN p_de AND p_ate;

  SELECT coalesce(sum(pontos), 0) INTO v_soma FROM public.movimentospontos
   WHERE funcionarioid = p_funcionarioid;

  WITH todos AS (
    SELECT m.*, sum(m.pontos) OVER (ORDER BY m.datamovimento, m.movimentoid) AS saldoapos
      FROM public.movimentospontos m
     WHERE m.funcionarioid = p_funcionarioid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'data', t.datamovimento, 'tipo', t.tipo, 'descricao', t.descricao,
           'loja', l.nome, 'pontos', t.pontos, 'saldoapos', t.saldoapos)
           ORDER BY t.datamovimento, t.movimentoid), '[]'::jsonb)
    INTO v_mov
    FROM todos t
    LEFT JOIN public.lojas l ON l.lojaid = t.lojaid
   WHERE public.dia_em_sao_paulo(t.datamovimento) BETWEEN p_de AND p_ate;

  RETURN jsonb_build_object(
    'nome',         v_nome,
    'saldoatual',   v_saldo,
    'saldoinicial', v_inicial,
    'saldofinal',   v_inicial + v_periodo,
    'confere',      v_soma = v_saldo,
    'taxa',         public.minha_taxa(),
    'movimentos',   v_mov
  );
END;
$function$;

-- O ranking de pontos do gerente: só as lojas em que ele vê o Ranking (a
-- pedida, se for dele; "todas" = todas as dele). O dia no fuso da conta.
CREATE OR REPLACE FUNCTION public.ranking_pontos_gerente(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta,
           (SELECT public.lojas_onde_posso('ranking.ver'))::integer[] AS lojas,
           (p_de::timestamp AT TIME ZONE public.fuso_da_conta(public.conta_do_gerente())) AS ini,
           ((p_ate + 1)::timestamp AT TIME ZONE public.fuso_da_conta(public.conta_do_gerente())) AS fim
  )
  SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
    FROM ctx
    JOIN public.entregas e      ON e.contaid = ctx.conta
    JOIN public.funcionarios f  ON f.funcionarioid = e.funcionarioid AND f.contaid = ctx.conta
   WHERE e.statusvalidacao = 'Aprovada'
     AND e.dataaprovacao >= ctx.ini AND e.dataaprovacao < ctx.fim
     AND e.lojaid = ANY (ctx.lojas)
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
   GROUP BY f.funcionarioid, f.nomecompleto
   ORDER BY 3 DESC, 2, 1
$function$;
REVOKE ALL ON FUNCTION public.ranking_pontos_gerente(date, date, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ranking_pontos_gerente(date, date, integer) TO authenticated;

-- ranking_pontos: parte da versão viva (de 20260929275000_fila_nao_cresce_com_os_dias.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.ranking_pontos(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.ranking_pontos_gerente(p_de, p_ate, p_lojaid);
    RETURN;
  END IF;
  RETURN QUERY
SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
  FROM public.entregas e
  JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
  WHERE e.statusvalidacao = 'Aprovada'
    AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN p_de AND p_ate
       -- Janela um pouco MAIOR, só para o índice achar o mês (a regra é a linha de cima).
       AND e.dataaprovacao >= ((p_de)::timestamp - interval '2 days') AT TIME ZONE 'UTC' AND e.dataaprovacao < ((p_ate)::timestamp + interval '3 days') AT TIME ZONE 'UTC'
    AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  GROUP BY f.funcionarioid, f.nomecompleto
  ORDER BY 3 DESC, 2, 1;
END;
$function$;

-- A nota do mês do gerente: só por loja em que ele vê o Ranking. Mês fechado:
-- o que foi congelado para aquela loja; aberto: ao vivo, até ontem.
CREATE OR REPLACE FUNCTION public.ranking_mensal_gerente(p_ano integer, p_mes integer, p_lojaid integer)
RETURNS TABLE (funcionarioid integer, nomecompleto varchar, pontosganhos integer, pontosregulares integer,
               pontospossiveis integer, confiabilidade numeric, esforco numeric, nota numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
  v_conta integer := public.conta_do_gerente();
  v_fech  integer;
BEGIN
  IF v_conta IS NULL OR p_lojaid IS NULL OR NOT public.pode('ranking.ver', p_lojaid) THEN
    RETURN;
  END IF;
  SELECT f.fechamentoid INTO v_fech FROM public.fechamentosmensais f
   WHERE f.contaid = v_conta AND f.ano = p_ano AND f.mes = p_mes AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC LIMIT 1;
  IF v_fech IS NOT NULL THEN
    RETURN QUERY
      SELECT h.funcionarioid, h.nomefuncionario, h.pontosganhos,
             coalesce(h.pontosregulares, 0), h.pontospossiveis,
             coalesce(h.confiabilidade, 0), coalesce(h.esforco, 0), coalesce(h.nota, 0)
        FROM public.historicoranking h
       WHERE h.contaid = v_conta AND h.fechamentoid = v_fech AND h.lojaid = p_lojaid
       ORDER BY h.posicao, h.historicoid;
  ELSE
    RETURN QUERY
      SELECT * FROM public.ranking_mensal_da_conta(v_conta, p_ano, p_mes, p_lojaid, public.hoje_da_conta(v_conta) - 1);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.ranking_mensal_gerente(integer, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ranking_mensal_gerente(integer, integer, integer) TO authenticated;

-- ranking_mensal: parte da versão viva (de 20260928100300_ranking_le_o_fechamento.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.ranking_mensal(p_ano integer, p_mes integer, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontosganhos integer, pontosregulares integer, pontospossiveis integer, confiabilidade numeric, esforco numeric, nota numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fechamento integer := public.fechamento_valendo(p_ano, p_mes);
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.ranking_mensal_gerente(p_ano, p_mes, p_lojaid);
    RETURN;
  END IF;
  IF v_fechamento IS NOT NULL THEN
    -- Mês fechado: os números estão congelados. É a mesma fonte da tela
    -- "Meses fechados", então as duas nunca discordam.
    RETURN QUERY
      SELECT h.funcionarioid, h.nomefuncionario, h.pontosganhos,
             coalesce(h.pontosregulares, 0), h.pontospossiveis,
             coalesce(h.confiabilidade, 0), coalesce(h.esforco, 0), coalesce(h.nota, 0)
        FROM public.historicoranking h
       WHERE h.fechamentoid = v_fechamento
         AND h.lojaid IS NOT DISTINCT FROM p_lojaid
       ORDER BY h.posicao;
  ELSE
    -- Mês aberto: ao vivo, até ontem.
    RETURN QUERY
      SELECT * FROM public.ranking_mensal_da_conta(public.minha_conta(), p_ano, p_mes, p_lojaid,
                                                   public.dia_em_sao_paulo(now()) - 1);
  END IF;
END;
$function$;

-- Qual fechamento vale no mês: para o gerente que vê o Ranking em alguma loja.
CREATE OR REPLACE FUNCTION public.fechamento_valendo_gerente(p_ano integer, p_mes integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.fechamentoid
    FROM public.fechamentosmensais f
   WHERE f.contaid = public.conta_do_gerente()
     AND cardinality((SELECT public.lojas_onde_posso('ranking.ver'))::integer[]) > 0
     AND f.ano = p_ano AND f.mes = p_mes
     AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC
   LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.fechamento_valendo_gerente(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fechamento_valendo_gerente(integer, integer) TO authenticated;

-- fechamento_valendo: parte da versão viva (de 20260928100300_ranking_le_o_fechamento.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.fechamento_valendo(p_ano integer, p_mes integer)
 RETURNS integer

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fechamento_valendo_gerente(p_ano, p_mes);
  END IF;
  RETURN (
SELECT f.fechamentoid
    FROM public.fechamentosmensais f
   WHERE f.contaid = (select public.minha_conta())
     AND f.ano = p_ano AND f.mes = p_mes
     AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC
   LIMIT 1
  );
END;
$function$;

-- Meses fechados (a tela lia as tabelas direto). O master: os mesmos de
-- sempre. O gerente: a lista dos meses (se vê o Ranking em alguma loja) e o
-- ranking congelado só das lojas dele (nunca o da conta inteira).
CREATE OR REPLACE FUNCTION public.meses_fechados()
RETURNS TABLE(fechamentoid integer, ano integer, mes integer, versao integer, situacao character varying,
              origem character varying, motivo text, fechadoem timestamptz, definitivoem timestamptz, substituidoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.fechamentoid, f.ano, f.mes, f.versao, f.situacao, f.origem, f.motivo, f.fechadoem, f.definitivoem, f.substituidoem
    FROM public.fechamentosmensais f
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('ranking.ver'))::integer[]) > 0)
   ORDER BY f.ano DESC, f.mes DESC, f.versao DESC, f.fechamentoid DESC
$$;
REVOKE ALL ON FUNCTION public.meses_fechados() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.meses_fechados() TO authenticated;

CREATE OR REPLACE FUNCTION public.ranking_do_fechamento(p_fechamentoid integer, p_lojaid integer)
RETURNS TABLE(historicoid integer, posicao integer, nomefuncionario character varying, nota numeric,
              confiabilidade numeric, esforco numeric, pontosganhos integer, pontospossiveis integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.posicao, h.nomefuncionario, h.nota, h.confiabilidade, h.esforco, h.pontosganhos, h.pontospossiveis
    FROM public.historicoranking h
   WHERE h.fechamentoid = p_fechamentoid
     AND ((public.sou_master() AND h.contaid = public.minha_conta() AND h.lojaid IS NOT DISTINCT FROM p_lojaid)
       OR (NOT public.sou_master() AND h.contaid = public.conta_do_gerente()
           AND p_lojaid IS NOT NULL AND h.lojaid = p_lojaid AND public.pode('ranking.ver', p_lojaid)))
   ORDER BY h.posicao, h.historicoid
$$;
REVOKE ALL ON FUNCTION public.ranking_do_fechamento(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ranking_do_fechamento(integer, integer) TO authenticated;
