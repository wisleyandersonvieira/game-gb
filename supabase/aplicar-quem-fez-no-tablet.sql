-- =========================================================================
-- STGame — ajuste do tablet: a faixa "Feitas hoje" passa a dizer QUEM fez.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique a parte A, a parte B1 e a parte C antes desta.
--
-- Este arquivo é UMA migração só:
--   20260929100200_quem_fez_no_tablet.sql
-- =========================================================================

BEGIN;

-- Etapa 1.12 — o tablet passa a dizer QUEM fez, na faixa "Feitas hoje".
--
-- Pedido do Wisley (25/09/2026): a faixa mostrava só o título e os pontos, no
-- mesmo dia em que as outras duas já diziam "com Maria S. há 20 min". A equipe
-- não via o que tinha rolado no dia nem quem tinha feito.
--
-- O nome sai da ENTREGA, não do aceite. Tarefa com dono único não passa por
-- missoesaceites, então quempegounome vem vazio nela — usar o aceite deixaria
-- justamente as tarefas com dono sem nome nenhum.
--
-- Nada de novo é exposto: quem lê a fila é o tablet da loja, que já mostra
-- "com Fulana" nas outras duas faixas, e o nome continua no formato curto
-- ("Teste U."), nunca o nome completo.

-- A função MUDA DE FORMATO (três colunas novas), e CREATE OR REPLACE não
-- consegue trocar o que uma função devolve. Apagar antes é o caminho.
DROP FUNCTION IF EXISTS public.fila_da_loja(integer);

CREATE OR REPLACE FUNCTION public.fila_da_loja(p_lojaid integer)
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
  -- Desde quando a tarefa está disponível HOJE. O cronômetro do tablet conta
  -- a partir daqui, e não de quando a tela abriu: dois tablets mostram o
  -- mesmo número.
  disponiveldesde timestamptz,
  -- true quando o rodízio está ligado e esta tarefa é disputada (aviso do cartão).
  rodizio        boolean,
  -- O relógio do servidor, para os aparelhos acertarem o deles.
  agora          timestamptz,
  -- Quem entregou, quando e em que pé está a entrega. A faixa "Feitas hoje"
  -- do tablet mostrava só o título e os pontos: a equipe não via quem fez.
  -- Sai da ENTREGA, não do aceite, porque tarefa com dono não passa por
  -- missoesaceites e ficaria sem nome.
  feitapor       text,
  feitaem        timestamptz,
  feitasituacao  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (
    SELECT public.minha_conta() AS conta,
           public.dia_em_sao_paulo(now()) AS dia,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = public.minha_conta() AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
  )
  SELECT ta.atribuicaoid,
         CASE WHEN a.aceiteid IS NOT NULL THEN coalesce(a.novaatribuicaoid, ta.atribuicaoid) END,
         t.titulo,
         t.pontos,
         ta.tipofrequencia,
         (ta.funcionarioid IS NULL),
         ta.funcionarioid,
         a.funcionarioid,
         public.nome_curto(qp.nomecompleto),
         a.aceitoem,
         CASE
           -- Tarefa Única: entregue num dia, acabou (vale para a tarefa com
           -- dono e para qualquer cópia da compartilhada).
           WHEN ta.tipofrequencia = 'Unica'
                AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid) THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                           AND public.dia_em_sao_paulo(e.dataenvio) = ctx.dia) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < ctx.dia),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_local(ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_local(ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_em_sao_paulo(ta.dataagendamento) = ctx.dia
                THEN ta.dataagendamento END),
         (ctx.rodizio > 0 AND ta.funcionarioid IS NULL),
         now(),
         -- nome_curto(NULL) devolve texto VAZIO, nao nulo: sem este CASE a
         -- coluna vinha '' para toda tarefa sem entrega, e "sem nome" deixava
         -- de ser distinguivel de "nome vazio".
         CASE WHEN ent.funcionarioid IS NOT NULL THEN public.nome_curto(fez.nomecompleto) END,
         ent.dataenvio,
         ent.statusvalidacao
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.revogadoem IS NULL
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só de hoje.
    -- Busca mais ampla que a regra faz a tarefa ainda POR FAZER aparecer com
    -- o nome de quem a entregou ontem, ou de quem teve o aceite revogado.
    LEFT JOIN LATERAL (
      SELECT e.funcionarioid, e.dataenvio, e.statusvalidacao
        FROM public.entregas e
       WHERE e.contaid = ctx.conta
         AND e.statusvalidacao IN ('Pendente', 'Aprovada')
         AND (
           (ta.tipofrequencia = 'Unica'
            AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                         WHERE c.contaid = ctx.conta AND c.atribuicaoid = e.atribuicaoid
                           AND (c.atribuicaoid = ta.atribuicaoid
                                OR c.origematribuicaoid = ta.atribuicaoid)))
           OR (e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
               AND public.dia_em_sao_paulo(e.dataenvio) = ctx.dia)
         )
       ORDER BY e.dataenvio DESC
       LIMIT 1
    ) ent ON true
    LEFT JOIN public.funcionarios fez  ON fez.funcionarioid = ent.funcionarioid AND fez.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT public.passada_hoje(ta.atribuicaoid, ctx.dia)
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3
$$;


REVOKE ALL ON FUNCTION public.fila_da_loja(integer)     FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.fila_da_loja(integer) TO authenticated, service_role;

-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.parameters
                  WHERE specific_schema = 'public' AND parameter_name = 'feitapor') THEN
    RAISE EXCEPTION 'A fila da loja não ganhou a coluna "feitapor".';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.parameters
                  WHERE specific_schema = 'public' AND parameter_name = 'feitasituacao') THEN
    RAISE EXCEPTION 'A fila da loja não ganhou a coluna "feitasituacao".';
  END IF;
  -- Tem de ter ficado UMA só: a versão nova.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'fila_da_loja') <> 1 THEN
    RAISE EXCEPTION 'fila_da_loja ficou duplicada: sobrou a versão antiga.';
  END IF;

  RAISE NOTICE 'tudo certo: o tablet passa a dizer quem fez.';
END $verifica$;

COMMIT;
