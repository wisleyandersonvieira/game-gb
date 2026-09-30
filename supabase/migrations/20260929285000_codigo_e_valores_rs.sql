-- Usuários gerenciais, PARTE 4, fatia 11: o código da empresa e o filtro
-- "Ver valores em R$" que faltava (30/09/2026).
--
--   * O código da empresa (tela de Lojas, para configurar o tablet): o
--     master, e o gerente com "Lojas: acesso do tablet" ou "Equipe: criar
--     acesso" em alguma loja (é o código que vai na folha de acesso).
--   * R$ que ainda chegava ao gerente sem "Ver valores em R$": o valor do
--     resgate "abate na comanda" (lista e recibo) e a taxa de pontos para
--     reais no Extrato. Sem a permissão, vêm vazios ("Abate na comanda").
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.codigo_da_empresa()
RETURNS TABLE(codigo character varying, nomefantasia character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.codigo, c.nomefantasia
    FROM public.contas c
   WHERE (public.sou_master() AND c.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
          AND (cardinality((SELECT public.lojas_onde_posso('lojas.tablet_acesso'))::integer[]) > 0
               OR cardinality((SELECT public.lojas_onde_posso('equipe.criar_acesso'))::integer[]) > 0))
$$;
REVOKE ALL ON FUNCTION public.codigo_da_empresa() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.codigo_da_empresa() TO authenticated;

-- listar_trocas_gerente: parte da versão viva (de 20260929276000_leituras_premios_extrato_ranking.sql); o R$ só com a permissão.
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
               'valorreais',         CASE WHEN public.pode('valores.ver_rs', r.lojaid) THEN r.valorreais END,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL AND public.pode('valores.ver_rs', r.lojaid)
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda'
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

-- recibo_resgate_gerente: parte da versão viva (de 20260929274000_arquivos_do_gerente.sql); o R$ só com a permissão.
CREATE OR REPLACE FUNCTION public.recibo_resgate_gerente(p_resgateid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nomefantasia AS conta
      FROM public.resgates r
      JOIN public.funcionarios f ON f.funcionarioid = r.funcionarioid
      JOIN public.produtosloja p ON p.produtoid = r.produtoid
      JOIN public.contas c       ON c.contaid = r.contaid
      LEFT JOIN public.lojas l   ON l.lojaid = r.lojaid
     WHERE r.resgateid = p_resgateid
       AND r.contaid = public.conta_do_gerente()
       AND r.lojaid IS NOT NULL AND public.pode('premios.ver', r.lojaid)
  ),
  mov AS (
    SELECT m.movimentoid, m.datamovimento, m.tipo, m.pontos, m.descricao,
           (SELECT coalesce(sum(x.pontos), 0) FROM public.movimentospontos x
             WHERE x.funcionarioid = m.funcionarioid AND x.movimentoid < m.movimentoid) AS saldoantes
      FROM public.movimentospontos m
     WHERE m.resgateid = p_resgateid AND m.contaid = public.conta_do_gerente()
  )
  SELECT jsonb_build_object(
           'conta', r.conta, 'loja', r.loja, 'pessoa', r.nomecompleto,
           'premio', CASE WHEN r.valorreais IS NOT NULL AND public.pode('valores.ver_rs', r.lojaid)
                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                          WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda'
                          ELSE r.premio END,
           'pontos', r.pontosgastos, 'situacao', r.status, 'solicitadoem', r.datasolicitacao,
           'entregueem', r.dataentrega, 'protocolo', 'R-' || r.resgateid,
           'movimentos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                             'data', datamovimento, 'tipo', tipo, 'pontos', pontos, 'descricao', descricao,
                             'saldoantes', saldoantes, 'saldodepois', saldoantes + pontos) ORDER BY movimentoid), '[]'::jsonb)
                            FROM mov))
    FROM r
$function$;

-- extrato_pontos_gerente: parte da versão viva (de 20260929276000_leituras_premios_extrato_ranking.sql); a taxa só com a permissão.
CREATE OR REPLACE FUNCTION public.extrato_pontos_gerente(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                            -- A taxa é R$ por ponto: só com "Ver valores em R$" em alguma loja.
                            'taxa', CASE WHEN cardinality(public.lojas_onde_posso('valores.ver_rs')) > 0
                                         THEN public.minha_taxa_gerente() END,
                            'movimentos', v_mov);
END;
$function$;

-- minha_taxa_gerente: parte da versão viva (de 20260929276000_leituras_premios_extrato_ranking.sql); também pede "Ver valores em R$".
CREATE OR REPLACE FUNCTION public.minha_taxa_gerente()
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gerente(); v_texto text; v_taxa numeric;
BEGIN
  IF v_conta IS NULL OR cardinality(public.lojas_onde_posso('valores.ver_rs')) = 0
     OR (cardinality(public.lojas_onde_posso('premios.ver')) = 0
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
$function$;
