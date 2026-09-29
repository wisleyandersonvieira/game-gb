-- Usuários gerenciais, PARTE 3, fatia 5: Metas por loja (29/09/2026).
--
-- O mês da meta tem R$ em toda linha: o gerente só lê com "Metas: ver" E "Ver
-- valores em R$" naquela loja (mais restritivo; a parte 4 decide o que mostrar
-- em percentual). Sem as duas, vem vazio. O master segue pelo caminho de sempre.
-- (Tudo aqui é lido pela LOJA, que já prende a conta.)

CREATE OR REPLACE FUNCTION public.metas_do_mes_gerente(p_lojaid integer, p_mes date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ok AS (SELECT 1 WHERE public.conta_do_gerente() IS NOT NULL
                        AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)),
  lim AS (
    SELECT date_trunc('month', p_mes)::date AS ini,
           (date_trunc('month', p_mes) + interval '1 month - 1 day')::date AS fim
  ),
  dias AS (
    SELECT g::date AS d FROM lim, generate_series(lim.ini, lim.fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d AS dia,
           a.apuracaoid, a.valordia,
           coalesce(a.valormetadia, md.valormeta) AS valormeta,
           CASE WHEN a.apuracaoid IS NOT NULL THEN a.pontosmetadia ELSE md.pontospremio END AS pontos,
           coalesce(a.origemmeta, md.origem) AS origem,
           coalesce(a.descricaometa, md.descricao) AS descricao,
           (SELECT count(*) FROM public.movimentospontos mv
              JOIN public.metaspremiacoes p ON p.premiacaoid = mv.premiacaoid
             WHERE p.apuracaoid = a.apuracaoid AND p.tipo = 'dia' AND p.estornadoem IS NULL
               AND mv.tipo = 'bonus') AS premiados
      FROM dias d
      JOIN ok ON true
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = p_lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(p_lojaid, d.d) md ON true
  ),
  mes AS (
    SELECT m.metaprincipalid, m.nomemeta, m.valormetatotal, m.pontospremio,
           EXISTS (SELECT 1 FROM public.metaspremiacoes p
                    WHERE p.metaprincipalid = m.metaprincipalid AND p.tipo = 'mes' AND p.estornadoem IS NULL) AS premiado
      FROM public.metasprincipais m, lim, ok
     WHERE m.lojaid = p_lojaid AND m.datainicio = lim.ini
  )
  SELECT CASE WHEN EXISTS (SELECT 1 FROM ok) THEN jsonb_build_object(
    'mes',       (SELECT to_jsonb(mes) FROM mes),
    'vendido',   (SELECT coalesce(sum(valordia), 0) FROM linhas),
    'somametas', (SELECT coalesce(sum(valormeta), 0) FROM linhas),
    'diaslancados', (SELECT count(*) FROM linhas WHERE apuracaoid IS NOT NULL),
    'dias',      (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'dia', dia, 'apuracaoid', apuracaoid, 'vendido', valordia, 'meta', valormeta,
                    'pontos', pontos, 'origem', origem, 'descricao', descricao,
                    'bateu', valordia IS NOT NULL AND coalesce(valormeta, 0) > 0 AND valordia >= valormeta,
                    'premiados', premiados) ORDER BY dia), '[]'::jsonb) FROM linhas),
    'primeirodiaeditavel', public.primeiro_dia_editavel_meta()
  ) END
$$;
REVOKE ALL ON FUNCTION public.metas_do_mes_gerente(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_do_mes_gerente(integer, date) TO authenticated;

-- metas_do_mes: parte da versão viva; o caminho de sempre fica no ELSE.
CREATE OR REPLACE FUNCTION public.metas_do_mes(p_lojaid integer, p_mes date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só as lojas dele.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.metas_do_mes_gerente(p_lojaid, p_mes)
           ELSE (
  WITH lim AS (
    SELECT date_trunc('month', p_mes)::date AS ini,
           (date_trunc('month', p_mes) + interval '1 month - 1 day')::date AS fim
  ),
  dias AS (
    SELECT g::date AS d FROM lim, generate_series(lim.ini, lim.fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d AS dia,
           a.apuracaoid, a.valordia,
           coalesce(a.valormetadia, md.valormeta) AS valormeta,
           CASE WHEN a.apuracaoid IS NOT NULL THEN a.pontosmetadia ELSE md.pontospremio END AS pontos,
           coalesce(a.origemmeta, md.origem) AS origem,
           coalesce(a.descricaometa, md.descricao) AS descricao,
           (SELECT count(*) FROM public.movimentospontos mv
              JOIN public.metaspremiacoes p ON p.premiacaoid = mv.premiacaoid
             WHERE p.apuracaoid = a.apuracaoid AND p.tipo = 'dia' AND p.estornadoem IS NULL
               AND mv.tipo = 'bonus') AS premiados
      FROM dias d
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = p_lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(p_lojaid, d.d) md ON true
  ),
  mes AS (
    SELECT m.metaprincipalid, m.nomemeta, m.valormetatotal, m.pontospremio,
           EXISTS (SELECT 1 FROM public.metaspremiacoes p
                    WHERE p.metaprincipalid = m.metaprincipalid AND p.tipo = 'mes' AND p.estornadoem IS NULL) AS premiado
      FROM public.metasprincipais m, lim
     WHERE m.lojaid = p_lojaid AND m.datainicio = lim.ini
  )
  SELECT jsonb_build_object(
    'mes',       (SELECT to_jsonb(mes) FROM mes),
    'vendido',   (SELECT coalesce(sum(valordia), 0) FROM linhas),
    'somametas', (SELECT coalesce(sum(valormeta), 0) FROM linhas),
    'diaslancados', (SELECT count(*) FROM linhas WHERE apuracaoid IS NOT NULL),
    'dias',      (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'dia', dia, 'apuracaoid', apuracaoid, 'vendido', valordia, 'meta', valormeta,
                    'pontos', pontos, 'origem', origem, 'descricao', descricao,
                    'bateu', valordia IS NOT NULL AND coalesce(valormeta, 0) > 0 AND valordia >= valormeta,
                    'premiados', premiados) ORDER BY dia), '[]'::jsonb) FROM linhas),
    'primeirodiaeditavel', public.primeiro_dia_editavel_meta()
  )
           ) END
$function$;
