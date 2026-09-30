-- Usuários gerenciais, PARTE 4, fatia 4: Tarefas e Metas (30/09/2026).
--
--   * Tarefas ("Tarefas: ver"): o catálogo mostra só tarefas que valem em
--     alguma loja dele, e a lista de lojas de cada uma vem cortada nas dele
--     (tarefa sem loja: só o master). Atribuições, tarefas e pessoas da
--     loja: só nas lojas em que ele vê Tarefas. O teto de pontos por ciência
--     (aparece ao editar a tarefa de rotina) também chega a ele.
--   * Metas: a meta da semana e as especiais são em R$: só com "Metas: ver"
--     E "Ver valores em R$" na loja. O histórico das vendas continua só do
--     master (é a conferência dele, decisão 5).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- As tarefas que valem numa loja (para atribuir e filtrar).
CREATE OR REPLACE FUNCTION public.tarefas_da_loja(p_lojaid integer)
RETURNS TABLE(tarefaid integer, titulo character varying, pontos integer, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.tarefaid, t.titulo, t.pontos, coalesce(t.ativa, true)
    FROM public.tarefaslojas tl
    JOIN public.tarefas t ON t.tarefaid = tl.tarefaid AND t.contaid = tl.contaid
   WHERE tl.lojaid = p_lojaid AND tl.ativo
     AND ((public.sou_master() AND tl.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND tl.contaid = public.conta_do_gerente() AND public.pode('tarefas.ver', p_lojaid)))
   ORDER BY t.titulo, t.tarefaid
$$;
REVOKE ALL ON FUNCTION public.tarefas_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tarefas_da_loja(integer) TO authenticated;

-- O teto de pontos por ciência da conta.
CREATE OR REPLACE FUNCTION public.teto_de_pontos_por_ciencia()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN c.valor ~ '^\s*[0-9]+\s*$' THEN btrim(c.valor)::integer END
    FROM public.configuracoes c
   WHERE c.chave = 'MAX_PONTOS_CIENCIA'
     AND ((public.sou_master() AND c.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
           AND cardinality((SELECT public.lojas_onde_posso('tarefas.ver'))::integer[]) > 0))
$$;
REVOKE ALL ON FUNCTION public.teto_de_pontos_por_ciencia() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.teto_de_pontos_por_ciencia() TO authenticated;

-- A meta de cada dia da semana de uma loja (R$).
CREATE OR REPLACE FUNCTION public.metas_da_semana(p_lojaid integer)
RETURNS TABLE(diasemanaid integer, valormeta numeric, pontospremio integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT m.diasemanaid, m.valormeta, m.pontospremio
    FROM public.metasdiariasmodelos m
   WHERE m.lojaid = p_lojaid
     AND ((public.sou_master() AND m.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND m.contaid = public.conta_do_gerente()
           AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)))
   ORDER BY m.diasemanaid
$$;
REVOKE ALL ON FUNCTION public.metas_da_semana(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_da_semana(integer) TO authenticated;

-- As metas especiais de uma loja (R$).
CREATE OR REPLACE FUNCTION public.metas_especiais_da_loja(p_lojaid integer)
RETURNS TABLE(metaespecialid integer, data date, descricao text, valormeta numeric, pontospremio integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT m.metaespecialid, m.data, m.descricao, m.valormeta, m.pontospremio
    FROM public.metasespeciais m
   WHERE m.lojaid = p_lojaid
     AND ((public.sou_master() AND m.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND m.contaid = public.conta_do_gerente()
           AND public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)))
   ORDER BY m.data DESC, m.metaespecialid DESC
   LIMIT 100
$$;
REVOKE ALL ON FUNCTION public.metas_especiais_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_especiais_da_loja(integer) TO authenticated;

-- O catálogo de tarefas do gerente.
CREATE OR REPLACE FUNCTION public.catalogo_de_tarefas_gerente(p_lojaid integer DEFAULT NULL::integer, p_inativas boolean DEFAULT false, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, (SELECT public.lojas_onde_posso('tarefas.ver'))::integer[] AS lojas
  ),
  escolhidas AS (
    SELECT t.tarefaid, t.titulo, t.descricao, t.pontos, t.setor, t.ativa, t.sistema, t.datacriacao
      FROM public.tarefas t, ctx
     WHERE t.contaid = ctx.conta
       AND (p_lojaid IS NULL OR p_lojaid = ANY (ctx.lojas))
       -- Só a tarefa que vale em alguma loja dele.
       AND EXISTS (SELECT 1 FROM public.tarefaslojas tl
                    WHERE tl.contaid = ctx.conta AND tl.tarefaid = t.tarefaid AND tl.ativo AND tl.lojaid = ANY (ctx.lojas))
       AND (coalesce(p_inativas, false) OR coalesce(t.ativa, true))
       -- "O nome contém o texto", sem diferenciar maiúscula. Sem LIKE: o que
       -- a pessoa digita é texto, nunca coringa.
       AND (nullif(btrim(coalesce(p_busca, '')), '') IS NULL
            OR strpos(lower(t.titulo), lower(btrim(p_busca))) > 0)
       AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.tarefaslojas tl
                                         WHERE tl.contaid = ctx.conta AND tl.tarefaid = t.tarefaid
                                           AND tl.lojaid = p_lojaid AND tl.ativo))
     ORDER BY t.datacriacao DESC NULLS LAST, t.tarefaid DESC
     OFFSET greatest(coalesce(p_offset, 0), 0)
     LIMIT least(greatest(coalesce(p_limite, 5), 1), 50) + 1
  ),
  numeradas AS (SELECT e.*, row_number() OVER (ORDER BY e.datacriacao DESC NULLS LAST, e.tarefaid DESC) AS n FROM escolhidas e)
  SELECT jsonb_build_object(
    'tarefas', coalesce((SELECT jsonb_agg(jsonb_build_object(
                 'tarefaid', x.tarefaid, 'titulo', x.titulo, 'descricao', x.descricao, 'pontos', x.pontos,
                 'setor', x.setor, 'ativa', x.ativa, 'sistema', x.sistema,
                 -- As lojas da tarefa, cortadas nas dele.
                 'lojas', coalesce((SELECT jsonb_agg(tl.lojaid ORDER BY tl.lojaid) FROM public.tarefaslojas tl, ctx
                                     WHERE tl.contaid = ctx.conta AND tl.tarefaid = x.tarefaid AND tl.ativo
                                       AND tl.lojaid = ANY (ctx.lojas)), '[]'::jsonb))
                 ORDER BY x.n)
                 FROM numeradas x WHERE x.n <= least(greatest(coalesce(p_limite, 5), 1), 50)), '[]'::jsonb),
    'temmais', (SELECT count(*) FROM numeradas) > least(greatest(coalesce(p_limite, 5), 1), 50))
$function$;
REVOKE ALL ON FUNCTION public.catalogo_de_tarefas_gerente(integer, boolean, text, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.catalogo_de_tarefas_gerente(integer, boolean, text, integer, integer) TO authenticated;

-- catalogo_de_tarefas: parte da versão viva (de 20260929236000_contadores_do_menu.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.catalogo_de_tarefas(p_lojaid integer DEFAULT NULL::integer, p_inativas boolean DEFAULT false, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.catalogo_de_tarefas_gerente(p_lojaid, p_inativas, p_busca, p_limite, p_offset);
  END IF;
  RETURN (
  WITH escolhidas AS (
    SELECT t.tarefaid, t.titulo, t.descricao, t.pontos, t.setor, t.ativa, t.sistema, t.datacriacao
      FROM public.tarefas t
     WHERE (coalesce(p_inativas, false) OR coalesce(t.ativa, true))
       -- "O nome contém o texto", sem diferenciar maiúscula. Sem LIKE: o que
       -- a pessoa digita é texto, nunca coringa.
       AND (nullif(btrim(coalesce(p_busca, '')), '') IS NULL
            OR strpos(lower(t.titulo), lower(btrim(p_busca))) > 0)
       AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.tarefaslojas tl
                                         WHERE tl.tarefaid = t.tarefaid AND tl.lojaid = p_lojaid AND tl.ativo))
     ORDER BY t.datacriacao DESC NULLS LAST, t.tarefaid DESC
     OFFSET greatest(coalesce(p_offset, 0), 0)
     LIMIT least(greatest(coalesce(p_limite, 5), 1), 50) + 1
  ),
  numeradas AS (SELECT e.*, row_number() OVER (ORDER BY e.datacriacao DESC NULLS LAST, e.tarefaid DESC) AS n FROM escolhidas e)
  SELECT jsonb_build_object(
    'tarefas', coalesce((SELECT jsonb_agg(jsonb_build_object(
                 'tarefaid', x.tarefaid, 'titulo', x.titulo, 'descricao', x.descricao, 'pontos', x.pontos,
                 'setor', x.setor, 'ativa', x.ativa, 'sistema', x.sistema,
                 'lojas', coalesce((SELECT jsonb_agg(tl.lojaid ORDER BY tl.lojaid) FROM public.tarefaslojas tl
                                     WHERE tl.tarefaid = x.tarefaid AND tl.ativo), '[]'::jsonb))
                 ORDER BY x.n)
                 FROM numeradas x WHERE x.n <= least(greatest(coalesce(p_limite, 5), 1), 50)), '[]'::jsonb),
    'temmais', (SELECT count(*) FROM numeradas) > least(greatest(coalesce(p_limite, 5), 1), 50))
  );
END;
$function$;

-- As atribuições de uma loja, para o gerente que vê Tarefas nela.
CREATE OR REPLACE FUNCTION public.atribuicoes_da_loja_gerente(p_lojaid integer, p_encerradas boolean DEFAULT false, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_tarefaid integer DEFAULT NULL::integer, p_funcionarioid integer DEFAULT NULL::integer, p_missao boolean DEFAULT false, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gerente();
  v_fuso   text := public.fuso_da_conta(public.conta_do_gerente());
  v_limite integer := least(greatest(coalesce(p_limite, 5), 1), 50);
  v_linhas jsonb;
  v_n      integer;
BEGIN
  IF v_conta IS NULL OR NOT public.pode('tarefas.ver', p_lojaid) THEN
    RETURN jsonb_build_object('linhas', '[]'::jsonb, 'temmais', false);
  END IF;
  IF (p_de IS NULL) <> (p_ate IS NULL) THEN
    RAISE EXCEPTION 'Escolha a data inicial e a final (ou nenhuma das duas).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_de > p_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_ate - p_de > 365 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 366 dias.' USING ERRCODE = 'check_violation';
  END IF;

  WITH filtradas AS (
    SELECT ta.*
      FROM public.tarefasatribuidas ta
     WHERE ta.contaid = v_conta AND ta.lojaid = p_lojaid
       AND (p_encerradas OR ta.datafimvigencia IS NULL)
       AND (p_tarefaid IS NULL OR ta.tarefaid = p_tarefaid)
       AND (NOT coalesce(p_missao, false) OR (ta.funcionarioid IS NULL AND NOT ta.compartilhada))
       AND (p_funcionarioid IS NULL
            OR ta.funcionarioid = p_funcionarioid
            OR (ta.compartilhada AND EXISTS (SELECT 1 FROM public.tarefascandidatos tc
                                              WHERE tc.atribuicaoid = ta.atribuicaoid
                                                AND tc.funcionarioid = p_funcionarioid)))
       AND (p_de IS NULL OR (ta.dataatribuicao >= (p_de::timestamp AT TIME ZONE v_fuso)
                             AND ta.dataatribuicao < ((p_ate + 1)::timestamp AT TIME ZONE v_fuso)))
  ),
  grupos AS (
    SELECT f.tarefaid,
           f.funcionarioid,
           f.tipofrequencia,
           f.datafimvigencia,
           array_agg(f.atribuicaoid ORDER BY f.atribuicaoid) AS ids,
           array_agg(f.valorfrequencia ORDER BY f.valorfrequencia) FILTER (WHERE f.valorfrequencia IS NOT NULL) AS dias,
           min(f.valorfrequencia) AS valor,
           min(f.dataagendamento) AS dataagendamento,
           min(f.disponivelapartir) AS disponivelapartir,
           bool_or(f.compartilhada) AS compartilhada,
           min(f.horariodisparo) AS horariodisparo,
           max(f.dataatribuicao) AS criadaem,
           max(f.atribuicaoid) AS ultimo
      FROM filtradas f
     GROUP BY f.tarefaid, coalesce(f.funcionarioid::text, 'c' || f.atribuicaoid), f.funcionarioid,
              f.tipofrequencia, f.datafimvigencia
  ),
  pagina AS (
    SELECT g.* FROM grupos g
     ORDER BY g.criadaem DESC NULLS LAST, g.ultimo DESC
     OFFSET greatest(coalesce(p_offset, 0), 0) LIMIT v_limite + 1
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ids', to_jsonb(p.ids),
           'tarefaid', p.tarefaid,
           'titulo', t.titulo,
           'funcionarioid', p.funcionarioid,
           'nome', fu.nomecompleto,
           'compartilhada', p.compartilhada,
           'candidatos', CASE WHEN p.compartilhada THEN
                           (SELECT coalesce(jsonb_agg(fc.nomecompleto ORDER BY fc.nomecompleto), '[]'::jsonb)
                              FROM public.tarefascandidatos tc
                              JOIN public.funcionarios fc ON fc.funcionarioid = tc.funcionarioid AND fc.contaid = v_conta
                             WHERE tc.atribuicaoid = p.ids[1]) END,
           'horariodisparo', p.horariodisparo,
           'tipofrequencia', p.tipofrequencia,
           'dias', coalesce(to_jsonb(p.dias), '[]'::jsonb),
           'valor', p.valor,
           'dataagendamento', p.dataagendamento,
           'disponivelapartir', p.disponivelapartir,
           'datafimvigencia', p.datafimvigencia,
           'criadaem', p.criadaem,
           -- O dia da criação já no fuso da conta, escrito dd/mm/aaaa.
           'criadaemdia', to_char(p.criadaem AT TIME ZONE v_fuso, 'DD/MM/YYYY'))
         ORDER BY p.criadaem DESC NULLS LAST, p.ultimo DESC),
         count(*)
    INTO v_linhas, v_n
    FROM pagina p
    LEFT JOIN public.tarefas t ON t.tarefaid = p.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios fu ON fu.funcionarioid = p.funcionarioid AND fu.contaid = v_conta;

  -- Veio uma a mais do que o limite: há mais para carregar.
  IF v_n > v_limite THEN
    v_linhas := v_linhas - v_limite;
  END IF;
  RETURN jsonb_build_object('linhas', coalesce(v_linhas, '[]'::jsonb), 'temmais', v_n > v_limite);
END;
$function$;

REVOKE ALL ON FUNCTION public.atribuicoes_da_loja_gerente(integer, boolean, date, date, integer, integer, boolean, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.atribuicoes_da_loja_gerente(integer, boolean, date, date, integer, integer, boolean, integer, integer) TO authenticated;

-- atribuicoes_da_loja: parte da versão viva (de 20260929220000_tarefas_comuns_e_atribuicoes.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.atribuicoes_da_loja(p_lojaid integer, p_encerradas boolean DEFAULT false, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_tarefaid integer DEFAULT NULL::integer, p_funcionarioid integer DEFAULT NULL::integer, p_missao boolean DEFAULT false, p_limite integer DEFAULT 5, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fuso   text := public.meu_hoje()->>'fuso';
  v_limite integer := least(greatest(coalesce(p_limite, 5), 1), 50);
  v_linhas jsonb;
  v_n      integer;
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.atribuicoes_da_loja_gerente(p_lojaid, p_encerradas, p_de, p_ate, p_tarefaid, p_funcionarioid, p_missao, p_limite, p_offset);
  END IF;
  IF (p_de IS NULL) <> (p_ate IS NULL) THEN
    RAISE EXCEPTION 'Escolha a data inicial e a final (ou nenhuma das duas).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_de > p_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_ate - p_de > 365 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 366 dias.' USING ERRCODE = 'check_violation';
  END IF;

  WITH filtradas AS (
    SELECT ta.*
      FROM public.tarefasatribuidas ta
     WHERE ta.lojaid = p_lojaid
       AND (p_encerradas OR ta.datafimvigencia IS NULL)
       AND (p_tarefaid IS NULL OR ta.tarefaid = p_tarefaid)
       AND (NOT coalesce(p_missao, false) OR (ta.funcionarioid IS NULL AND NOT ta.compartilhada))
       AND (p_funcionarioid IS NULL
            OR ta.funcionarioid = p_funcionarioid
            OR (ta.compartilhada AND EXISTS (SELECT 1 FROM public.tarefascandidatos tc
                                              WHERE tc.atribuicaoid = ta.atribuicaoid
                                                AND tc.funcionarioid = p_funcionarioid)))
       AND (p_de IS NULL OR (ta.dataatribuicao >= (p_de::timestamp AT TIME ZONE v_fuso)
                             AND ta.dataatribuicao < ((p_ate + 1)::timestamp AT TIME ZONE v_fuso)))
  ),
  grupos AS (
    SELECT f.tarefaid,
           f.funcionarioid,
           f.tipofrequencia,
           f.datafimvigencia,
           array_agg(f.atribuicaoid ORDER BY f.atribuicaoid) AS ids,
           array_agg(f.valorfrequencia ORDER BY f.valorfrequencia) FILTER (WHERE f.valorfrequencia IS NOT NULL) AS dias,
           min(f.valorfrequencia) AS valor,
           min(f.dataagendamento) AS dataagendamento,
           min(f.disponivelapartir) AS disponivelapartir,
           bool_or(f.compartilhada) AS compartilhada,
           min(f.horariodisparo) AS horariodisparo,
           max(f.dataatribuicao) AS criadaem,
           max(f.atribuicaoid) AS ultimo
      FROM filtradas f
     GROUP BY f.tarefaid, coalesce(f.funcionarioid::text, 'c' || f.atribuicaoid), f.funcionarioid,
              f.tipofrequencia, f.datafimvigencia
  ),
  pagina AS (
    SELECT g.* FROM grupos g
     ORDER BY g.criadaem DESC NULLS LAST, g.ultimo DESC
     OFFSET greatest(coalesce(p_offset, 0), 0) LIMIT v_limite + 1
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ids', to_jsonb(p.ids),
           'tarefaid', p.tarefaid,
           'titulo', t.titulo,
           'funcionarioid', p.funcionarioid,
           'nome', fu.nomecompleto,
           'compartilhada', p.compartilhada,
           'candidatos', CASE WHEN p.compartilhada THEN
                           (SELECT coalesce(jsonb_agg(fc.nomecompleto ORDER BY fc.nomecompleto), '[]'::jsonb)
                              FROM public.tarefascandidatos tc
                              JOIN public.funcionarios fc ON fc.funcionarioid = tc.funcionarioid
                             WHERE tc.atribuicaoid = p.ids[1]) END,
           'horariodisparo', p.horariodisparo,
           'tipofrequencia', p.tipofrequencia,
           'dias', coalesce(to_jsonb(p.dias), '[]'::jsonb),
           'valor', p.valor,
           'dataagendamento', p.dataagendamento,
           'disponivelapartir', p.disponivelapartir,
           'datafimvigencia', p.datafimvigencia,
           'criadaem', p.criadaem,
           -- O dia da criação já no fuso da conta, escrito dd/mm/aaaa.
           'criadaemdia', to_char(p.criadaem AT TIME ZONE v_fuso, 'DD/MM/YYYY'))
         ORDER BY p.criadaem DESC NULLS LAST, p.ultimo DESC),
         count(*)
    INTO v_linhas, v_n
    FROM pagina p
    LEFT JOIN public.tarefas t ON t.tarefaid = p.tarefaid
    LEFT JOIN public.funcionarios fu ON fu.funcionarioid = p.funcionarioid;

  -- Veio uma a mais do que o limite: há mais para carregar.
  IF v_n > v_limite THEN
    v_linhas := v_linhas - v_limite;
  END IF;
  RETURN jsonb_build_object('linhas', coalesce(v_linhas, '[]'::jsonb), 'temmais', v_n > v_limite);
END;
$function$;
