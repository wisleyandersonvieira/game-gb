-- A barra da TV conta exatamente o que a fila conta (29/09/2026, decisão do
-- Wisley: "a mesma fonte, pela quinta vez").
--
-- A barra "X de N tarefas concluídas hoje" tinha regra própria desde 21/09:
--   * NÃO contava missão nem compartilhada: alguém fazia, a barra não se
--     mexia, e a conclusão era que o esforço não conta;
--   * contava a tarefa de quem está de FOLGA: serviço que ninguém deveria
--     fazer enchia o total, e a loja parecia pior do que foi.
-- Agora a barra, o "Para fazer" e o "Em andamento" da TV (e do painel da
-- loja) saem de fila_de_hoje, a mesma fonte do tablet e do Quadro, numa
-- leitura só. A barra ganha as duas contas que faltavam para fechar:
--   total = aprovadas + em validação + em andamento + para fazer
--           + ainda não liberadas.

-- Parte da versão mais recente (20260929238000_disponivel_uma_fonte.sql), com
-- o diff conferido: saem a consulta própria do dia e a do "Em andamento".
CREATE OR REPLACE FUNCTION public.montar_painel(p_contaid integer, p_lojaid integer, p_tv boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje       date := public.hoje_da_conta(p_contaid);
  v_fuso       text := public.fuso_da_conta(p_contaid);
  v_loja       text;
  v_dia        jsonb;
  v_validacao  jsonb;
  v_pendentes  integer;
  v_podio      jsonb;
  v_atividade  jsonb;
  v_andamento  jsonb;
  v_podiomes   jsonb;
  v_parafazer  jsonb;
BEGIN
  SELECT nome INTO v_loja FROM public.lojas WHERE lojaid = p_lojaid AND contaid = p_contaid;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- A BARRA, o "Para fazer" e o "Em andamento" saem da MESMA fonte que o
  -- tablet e o Quadro (fila_de_hoje), numa leitura só (29/09/2026, decisão do
  -- Wisley). Antes a barra tinha regra própria: não contava missão nem
  -- compartilhada (alguém fazia e a barra não se mexia) e contava a tarefa
  -- de quem está de folga (a loja parecia pior do que foi).
  -- Toda tarefa da fila está em exatamente UM destes estados, então a conta
  -- fecha: total = aprovadas + em validação + em andamento + para fazer +
  -- ainda não liberadas (a trava da seção 19 confere).
  WITH f AS (
    SELECT q.*, d.nomecompleto AS dononome, p.nomecompleto AS quemnome,
           row_number() OVER () AS n
      FROM public.fila_de_hoje(p_contaid, p_lojaid) q
      LEFT JOIN public.funcionarios d ON d.funcionarioid = q.donoid AND d.contaid = p_contaid
      LEFT JOIN public.funcionarios p ON p.funcionarioid = q.quempegou AND p.contaid = p_contaid
  )
  SELECT jsonb_build_object(
           'total',             count(*),
           'aprovadas',         count(*) FILTER (WHERE situacao = 'feita' AND feitasituacao = 'Aprovada'),
           'emvalidacao',       count(*) FILTER (WHERE situacao = 'feita' AND feitasituacao = 'Pendente'),
           'emandamento',       count(*) FILTER (WHERE situacao = 'em_andamento'),
           'aindanaoliberadas', count(*) FILTER (WHERE situacao = 'para_pegar' AND NOT disponivel)),
         -- PARA FAZER: o que está DISPONÍVEL agora, na ordem da fila.
         coalesce(jsonb_agg(jsonb_build_object(
                    'titulo',   titulo,
                    'pessoa',   CASE WHEN aberta THEN 'a primeira que pegar leva'
                                     WHEN p_tv THEN public.nome_curto(dononome)
                                     ELSE dononome END,
                    'pontos',   pontos,
                    'atrasada', atrasada) ORDER BY n) FILTER (WHERE disponivel), '[]'::jsonb),
         -- EM ANDAMENTO: quem pegou e ainda não entregou, pela fila.
         coalesce(jsonb_agg(jsonb_build_object(
                    'titulo', titulo,
                    'pessoa', CASE WHEN p_tv THEN quempegounome ELSE quemnome END,
                    'pegaem', pegaem) ORDER BY pegaem, n) FILTER (WHERE situacao = 'em_andamento'), '[]'::jsonb)
    INTO v_dia, v_parafazer, v_andamento
    FROM f;

  -- Em validacao: todas as pendentes da loja, de qualquer dia.
  SELECT count(*) INTO v_pendentes
    FROM public.entregas
   WHERE contaid = p_contaid AND lojaid = p_lojaid AND statusvalidacao = 'Pendente';

  SELECT coalesce(jsonb_agg(
           jsonb_build_object('titulo', titulo, 'pessoa', pessoa, 'pontos', pontos,
                              'enviadaem', dataenvio, 'dehoje', dehoje)
           ORDER BY dataenvio), '[]'::jsonb)
    INTO v_validacao
    FROM (
      SELECT t.titulo, t.pontos, e.dataenvio,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje AS dehoje
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio
       LIMIT 50
    ) s;

  -- Podio do dia: pontos do TRABALHO FEITO HOJE (data da entrega), ja
  -- aprovado. Antes contava a data da aprovacao: a tarefa de ontem aprovada
  -- hoje entrava no podio de hoje. Na TV, "hoje" e trabalho feito hoje.
  -- (Nao bate, e nao e para bater, com o livro de pontos do dia: o livro
  -- lanca na aprovacao e tem bonus, resgates e estornos. Ver o plano.)
  SELECT coalesce(jsonb_agg(jsonb_build_object('pessoa', pessoa, 'pontos', pontos)
                            ORDER BY pontos DESC, pessoa), '[]'::jsonb)
    INTO v_podio
    FROM (
      SELECT CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             sum(e.pontosganhos)::integer AS pontos
        FROM public.entregas e
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
       GROUP BY f.funcionarioid, f.nomecompleto
       ORDER BY sum(e.pontosganhos) DESC, f.nomecompleto
       LIMIT 3
    ) s;

  -- Atividade recente: o trabalho FEITO HOJE (data da entrega) que ja foi
  -- aprovado, o aprovado por ultimo primeiro. Antes seguia a data da
  -- aprovacao, e a tarefa de ontem aprovada hoje aparecia como de hoje.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pontos', pontos, 'aprovadaem', dataaprovacao,
                                               'enviadaem', dataenvio)
                            ORDER BY dataaprovacao DESC), '[]'::jsonb)
    INTO v_atividade
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataaprovacao, e.dataenvio,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
       ORDER BY e.dataaprovacao DESC
       LIMIT 10
    ) s;

  -- PODIO DO MES: pontos aprovados no mes, nesta loja. O pódio de hoje ja
  -- existia; este e o outro bloco que a TV passou a poder mostrar.
  SELECT coalesce(jsonb_agg(jsonb_build_object('pessoa', pessoa, 'pontos', pontos)
                            ORDER BY pontos DESC, pessoa), '[]'::jsonb)
    INTO v_podiomes
    FROM (
      SELECT CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             sum(e.pontosganhos)::integer AS pontos
        FROM public.entregas e
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = p_contaid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataaprovacao, v_fuso)
             BETWEEN date_trunc('month', v_hoje)::date AND v_hoje
       GROUP BY 1
       ORDER BY 2 DESC
       LIMIT 5
    ) s;

  RETURN jsonb_build_object(
    'loja',         v_loja,
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'progresso',    v_dia,
    'parafazer',    v_parafazer,
    'emvalidacao',  v_validacao,
    'pendentes',    v_pendentes,
    'podio',        v_podio,
    'emandamento',  v_andamento,
    'podiomes',     v_podiomes,
    'atividade',    v_atividade,
    'meta',         public.meta_para_painel(p_contaid, p_lojaid, p_tv),
    'agenda',       public.agenda_para_painel(p_contaid, p_lojaid, p_tv)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.montar_painel(integer, integer, boolean) FROM public, anon, authenticated;
