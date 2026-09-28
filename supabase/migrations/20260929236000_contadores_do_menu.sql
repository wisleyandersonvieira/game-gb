-- Os contadores do menu numa consulta só; o Catálogo de tarefas numa consulta só
-- (29/09/2026, pedidos do Wisley).
--
-- O menu lateral tinha dois contadores (Prêmios e Solicitações), cada um com a
-- sua consulta; com o do Quadro (entregas esperando aprovação) seriam três
-- perguntas ao banco a cada vez que o cache de 30 segundos vence. Agora é uma.
--
-- SECURITY INVOKER: a regra de cada tabela vale aqui dentro — cada gestor só
-- conta o que enxerga, de todas as lojas dele. Só números (count), nunca
-- linha.
CREATE OR REPLACE FUNCTION public.contagem_do_menu()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    -- Quadro: entregas esperando aprovação, nas lojas ativas.
    'entregas', (SELECT count(*) FROM public.entregas e
                   JOIN public.lojas l ON l.lojaid = e.lojaid AND l.ativa
                  WHERE e.statusvalidacao = 'Pendente'),
    -- Prêmios: pedidos de resgate esperando o gestor (a mesma conta de antes).
    'resgates', (SELECT count(*) FROM public.resgates r WHERE r.status = 'Pendente'),
    -- Solicitações: por loja e situação (o menu soma; as abas usam por loja).
    'solicitacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('loja', c.loja, 'situacao', c.situacao, 'quantos', c.quantos))
                                FROM public.contagem_solicitacoes() c), '[]'::jsonb))
$$;
REVOKE ALL ON FUNCTION public.contagem_do_menu() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.contagem_do_menu() TO authenticated;

-- ---------------------------------------------------------------------------
-- O Catálogo de tarefas numa consulta só, com filtro, busca e 50 por vez
-- (29/09/2026). Antes a tela trazia TODAS as tarefas e TODOS os vínculos com
-- loja (duas consultas) e filtrava no aparelho.
-- ---------------------------------------------------------------------------
-- SECURITY INVOKER: cada conta só enxerga as dela. Filtros (todos opcionais):
--   p_lojaid    : só as tarefas que valem nesta loja (vazio = todas as lojas);
--   p_inativas  : inclui as desativadas;
--   p_busca     : pedaço do nome (sem diferenciar maiúscula).
-- Mais recente primeiro; p_limite (até 50) por vez, a partir de p_offset.
CREATE OR REPLACE FUNCTION public.catalogo_de_tarefas(p_lojaid integer DEFAULT NULL, p_inativas boolean DEFAULT false,
                                                      p_busca text DEFAULT NULL, p_limite integer DEFAULT 5,
                                                      p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
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
$$;
REVOKE ALL ON FUNCTION public.catalogo_de_tarefas(integer, boolean, text, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.catalogo_de_tarefas(integer, boolean, text, integer, integer) TO authenticated;
