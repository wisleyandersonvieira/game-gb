-- =========================================================================
-- STGame — "Disponível agora": TV, tablet e Quadro com a mesma lista.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-foto-da-fila.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova: a tela nova do
-- tablet e do Quadro lê a coluna "disponivel", que nasce aqui.
--
-- Este arquivo é UMA migração só:
--   20260929238000_disponivel_uma_fonte.sql
--
-- O QUE MUDA: o "Para fazer" da TV passa a ser a mesma lista do "Para pegar"
-- do tablet e do Quadro. A barra de progresso da TV não muda. Nenhum dado é
-- alterado.
-- =========================================================================


BEGIN;

-- "Disponível agora": UMA fonte para a TV, o tablet e o Quadro (29/09/2026,
-- pedido do Wisley).
--
-- A TV mostrava em "Para fazer" todas as tarefas do dia, inclusive as que só
-- liberam mais tarde. O motivo: a TV (montar_painel) nasceu em 21/09, antes
-- da fila da loja existir, com uma consulta própria — e a fila, que o tablet
-- e o Quadro usam, foi ganhando regras (missões, compartilhadas, folga,
-- afastamento, hora de liberação) que a TV nunca recebeu. E mesmo no tablet
-- e no Quadro a pergunta "está disponível?" era respondida na TELA
-- (situacao = 'para_pegar' E liberada), em três lugares do código.
--
-- Agora "disponível" é decidido UMA vez, no banco, em fila_de_hoje, e as três
-- telas perguntam para ela:
--   * fila_de_hoje(conta, loja): a fila de hoje (fila_no_dia) com a coluna
--     disponivel = para pegar E já liberada, pelo relógio do servidor;
--   * fila_da_loja (Quadro, e o tablet por visao_fila) passa a ser ela;
--   * montar_painel (TV e painel da loja) tira o "Para fazer" dela.
-- A barra de progresso da TV NÃO muda (decisão do Wisley: ela conta o dia
-- inteiro, inclusive o que libera mais tarde).

-- ---------------------------------------------------------------------------
-- 1. A fonte: a fila de hoje com "disponível"
-- ---------------------------------------------------------------------------
-- Interna: recebe a conta. O dia é o de hoje da conta, e o dia ainda não
-- acabou (fim = infinity), como na fila de sempre.
CREATE OR REPLACE FUNCTION public.fila_de_hoje(p_contaid integer, p_lojaid integer)
RETURNS TABLE (
  atribuicaoid   integer,
  entregarid     integer,
  titulo         varchar,
  pontos         integer,
  tipofrequencia varchar,
  aberta         boolean,
  donoid         integer,
  quempegou      integer,
  quempegounome  text,
  pegaem         timestamptz,
  situacao       text,
  atrasada       boolean,
  disponiveldesde timestamptz,
  rodizio        boolean,
  agora          timestamptz,
  feitapor       text,
  feitaem        timestamptz,
  feitasituacao  text,
  liberada       boolean,
  liberaas       timestamptz,
  hoje           date,
  fuso           text,
  -- DISPONÍVEL AGORA: ninguém pegou, ninguém fez, e já passou da hora de
  -- liberação. É o "Para pegar" do tablet e do Quadro e o "Para fazer" da
  -- TV. Nenhuma tela decide isto sozinha.
  disponivel     boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.*, (f.situacao = 'para_pegar' AND f.liberada)
    FROM (SELECT p_contaid AS conta WHERE p_contaid IS NOT NULL) c
    CROSS JOIN LATERAL public.fila_no_dia(c.conta, p_lojaid, public.hoje_da_conta(c.conta), 'infinity'::timestamptz) f
   ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid
$$;
REVOKE ALL ON FUNCTION public.fila_de_hoje(integer, integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. A fila do Quadro e do tablet é a mesma, com a coluna nova
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929237000_foto_da_fila.sql). Ganha uma
-- coluna, então precisa sair e voltar (o Postgres não troca as colunas de
-- uma função no lugar). As permissões voltam iguais.
DROP FUNCTION IF EXISTS public.fila_da_loja(integer);
CREATE FUNCTION public.fila_da_loja(p_lojaid integer)
RETURNS TABLE (
  atribuicaoid   integer,
  entregarid     integer,
  titulo         varchar,
  pontos         integer,
  tipofrequencia varchar,
  aberta         boolean,
  donoid         integer,
  quempegou      integer,
  quempegounome  text,
  pegaem         timestamptz,
  situacao       text,
  atrasada       boolean,
  disponiveldesde timestamptz,
  rodizio        boolean,
  agora          timestamptz,
  feitapor       text,
  feitaem        timestamptz,
  feitasituacao  text,
  liberada       boolean,
  liberaas       timestamptz,
  hoje           date,
  fuso           text,
  disponivel     boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.*
    FROM public.fila_de_hoje(public.minha_conta(), p_lojaid) f
   ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid
$$;
REVOKE ALL ON FUNCTION public.fila_da_loja(integer)     FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.fila_da_loja(integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. A TV (e o painel da loja): "Para fazer" = disponível, da mesma fonte
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929180000_primeiro_acesso_e_tv.sql),
-- com o diff conferido: muda só de onde sai o "parafazer".
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

  -- Tarefas do dia e a situacao de cada uma hoje.
  WITH dia AS (
    SELECT t.titulo,
           t.pontos,
           CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
           (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
            AND public.dia_no_fuso(ta.dataagendamento, v_fuso) < v_hoje) AS atrasada,
           (SELECT e.statusvalidacao
              FROM public.entregas e
             WHERE e.atribuicaoid = ta.atribuicaoid
               AND e.statusvalidacao IN ('Pendente', 'Aprovada')
               AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
             ORDER BY e.entregaid DESC
             LIMIT 1) AS situacao
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid
      JOIN public.funcionarioslojas fl ON fl.funcionarioid = ta.funcionarioid AND fl.lojaid = ta.lojaid
     WHERE ta.contaid = p_contaid
       AND ta.lojaid = p_lojaid
       AND ta.datafimvigencia IS NULL
       AND f.ativo AND fl.ativo AND coalesce(t.ativa, true)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje, v_fuso)
       -- Justificada como "nao se aplica" (pendente ou aceita) nao e tarefa de hoje.
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
       -- Passada hoje para quem está trabalhando: sai da lista de quem está de folga.
       AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
       -- Unica entregue num dia anterior ja nao e tarefa de hoje.
       AND NOT (ta.tipofrequencia = 'Unica' AND EXISTS (
             SELECT 1 FROM public.entregas e2
              WHERE e2.atribuicaoid = ta.atribuicaoid
                AND e2.statusvalidacao IN ('Pendente', 'Aprovada')
                AND public.dia_no_fuso(e2.dataenvio, v_fuso) < v_hoje))
  )
  SELECT jsonb_build_object(
           'total',       count(*),
           'aprovadas',   count(*) FILTER (WHERE situacao = 'Aprovada'),
           'emvalidacao', count(*) FILTER (WHERE situacao = 'Pendente'))
    INTO v_dia
    FROM dia;

  -- PARA FAZER (29/09/2026): as tarefas DISPONÍVEIS agora — a MESMA lista do
  -- "Para pegar" do tablet e do Quadro, perguntada à mesma fonte
  -- (fila_de_hoje.disponivel). Antes a TV tinha regra própria: mostrava a
  -- tarefa que só libera mais tarde, deixava de fora as missões e as
  -- compartilhadas, e repetia em "Para fazer" quem já estava em andamento.
  -- A barra de progresso (acima) NÃO mudou: a tarefa que libera às 16h é
  -- trabalho de hoje e continua no total do dia.
  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'titulo',   f.titulo,
             'pessoa',   CASE WHEN f.aberta THEN 'a primeira que pegar leva'
                              WHEN p_tv THEN public.nome_curto(d.nomecompleto)
                              ELSE d.nomecompleto END,
             'pontos',   f.pontos,
             'atrasada', f.atrasada)
           ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid), '[]'::jsonb)
    INTO v_parafazer
    FROM public.fila_de_hoje(p_contaid, p_lojaid) f
    LEFT JOIN public.funcionarios d ON d.funcionarioid = f.donoid AND d.contaid = p_contaid
   WHERE f.disponivel;

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

  -- EM ANDAMENTO: quem pegou e ainda nao entregou. A TV precisa disto para a
  -- coluna do mesmo nome; antes so existia na fila do tablet, que o visitante
  -- sem login nao alcanca.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pegaem', pegaem)
                            ORDER BY pegaem), '[]'::jsonb)
    INTO v_andamento
    FROM (
      SELECT t.titulo, a.aceitoem AS pegaem,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.missoesaceites a
        JOIN public.tarefasatribuidas ta ON ta.contaid = a.contaid AND ta.atribuicaoid = a.atribuicaoid
        JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
        JOIN public.funcionarios f       ON f.funcionarioid = a.funcionarioid AND f.contaid = p_contaid
       WHERE a.contaid = p_contaid AND ta.lojaid = p_lojaid
         AND a.dia = v_hoje AND a.revogadoem IS NULL
         -- Ja entregue sai daqui: vira "esperando o gestor" ou "feita".
         AND NOT EXISTS (SELECT 1 FROM public.entregas e
                          WHERE e.contaid = p_contaid
                            AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                            AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
       ORDER BY a.aceitoem
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
    'progresso',    jsonb_build_object('total',       v_dia->'total',
                                       'aprovadas',   v_dia->'aprovadas',
                                       'emvalidacao', v_dia->'emvalidacao'),
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

COMMIT;
