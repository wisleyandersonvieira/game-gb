-- =========================================================================
-- STGame — A foto da fila no fim do dia e o filtro por dia do Quadro.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-menu-e-catalogo.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929237000_foto_da_fila.sql
--
-- O QUE MUDA:
--   * a fila de hoje passa a sair da mesma função que tira a foto do dia
--     (a mesma fila: 331 itens comparados antes e depois, 0 diferenças);
--   * a rotina da madrugada tira a foto da fila do dia que acabou;
--   * a limpeza apaga as fotos fora do prazo (mês corrente, o anterior e
--     mais um de margem);
--   * a /saude avisa os dias sem foto.
-- Nenhum dado existente é alterado. Colunas novas: tarefasatribuidas.criadaem
-- e encerradaem, diasgerados.fotodafilaem. Tabela nova: fotosdafila.
-- =========================================================================


BEGIN;

-- A fila de um dia que passou: a FOTO do fim do dia (29/09/2026, decisão do
-- Wisley: "um lugar que observa o resultado vale mais que seis lugares que
-- avisam o que aconteceu").
--
-- O Quadro ganha um filtro por dia. O dia de hoje continua ao vivo. Um dia
-- que passou é lido da foto que a rotina da madrugada tira da fila logo
-- depois da meia-noite: o que estava para pegar, em andamento e feito quando
-- o dia acabou.
--
--   1. UMA função da fila (fila_no_dia): a de hoje e a foto saem dela, só
--      muda o dia. Tudo o que tem hora gravada é lido "como estava no fim do
--      dia": atribuição criada ou encerrada depois da meia-noite, aceite
--      revogado, entrega recusada ou estornada, justificativa registrada ou
--      recusada, tarefa passada. Para o dia de hoje isso é exatamente o que
--      a fila já fazia (a prova compara a fila antes e depois, item por item).
--   2. Para saber QUANDO uma atribuição foi criada e encerrada, o banco grava
--      as horas (criadaem, encerradaem). A data de encerramento
--      (datafimvigencia) vem da tela e não diz a hora; a de atribuição
--      (dataatribuicao) pode vir de fora.
--   3. A foto (fotosdafila), tirada por rotina_lista_do_dia — a mesma rotina
--      que já decide a virada do dia (e que a catraca do "São Paulo fixo"
--      conta). Só vale se for tirada até as 03:00 do dia seguinte, e nunca
--      de um dia cuja lista foi recuperada depois de uma parada.
--   4. A marca "registro completo" é a hora da foto, no registro dos dias
--      gerados (diasgerados.fotodafilaem). Sem marca, o Quadro mostra "não
--      registrado" no lugar do número.
--   5. A guarda: o alcance do filtro (mês corrente e anterior) e o prazo de
--      guarda (o alcance mais uma margem de um mês) saem de UMA regra
--      (fila_alcance). Quando a limpeza apaga um dia, a marca cai junto.
--   6. A /saude avisa os dias que ficaram sem foto.

-- ---------------------------------------------------------------------------
-- 1. A hora em que a atribuição foi criada e encerrada (o banco grava,
--    ninguém mais). As de antes desta migração ficam sem hora de criação:
--    valem como "criadas antes de qualquer dia".
-- ---------------------------------------------------------------------------
ALTER TABLE public.tarefasatribuidas ADD COLUMN IF NOT EXISTS criadaem timestamptz;
ALTER TABLE public.tarefasatribuidas ADD COLUMN IF NOT EXISTS encerradaem timestamptz;
COMMENT ON COLUMN public.tarefasatribuidas.criadaem IS
  'Quando a atribuição foi gravada. Gravada pelo banco; a foto da fila usa para saber se ela já existia no fim do dia.';
COMMENT ON COLUMN public.tarefasatribuidas.encerradaem IS
  'Quando a atribuição foi encerrada (datafimvigencia preenchida). Gravada pelo banco; a foto da fila usa para saber se ela ainda valia no fim do dia.';

CREATE OR REPLACE FUNCTION public.atribuicao_hora_do_encerramento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.criadaem := now();
  ELSE
    NEW.criadaem := OLD.criadaem;
  END IF;
  IF NEW.datafimvigencia IS NULL THEN
    NEW.encerradaem := NULL;
  ELSIF TG_OP = 'INSERT' OR OLD.datafimvigencia IS NULL THEN
    NEW.encerradaem := now();
  ELSE
    -- Já estava encerrada: a hora não muda, nem por quem tentar escrever nela.
    NEW.encerradaem := OLD.encerradaem;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.atribuicao_hora_do_encerramento() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS tarefasatribuidas_hora_do_encerramento ON public.tarefasatribuidas;
CREATE TRIGGER tarefasatribuidas_hora_do_encerramento
  BEFORE INSERT OR UPDATE ON public.tarefasatribuidas
  FOR EACH ROW EXECUTE FUNCTION public.atribuicao_hora_do_encerramento();

-- ---------------------------------------------------------------------------
-- 2. A fila de um dia — a de hoje e a da foto são esta mesma função
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente de fila_da_loja (20260929140000_hoje_da_conta.sql),
-- com o diff conferido. O que muda é só "como estava no fim do dia" (p_fim):
--   * a atribuição vale se foi criada antes do fim e não estava encerrada
--     (encerradaem depois do fim ainda vale; encerrada sem hora, de antes
--     desta migração, não vale — como hoje);
--   * o aceite vale se foi feito antes do fim e não foi revogado antes dele;
--   * a entrega vale se foi enviada antes do fim e não foi recusada nem
--     estornada antes dele (a situação mostrada é a daquele momento);
--   * a justificativa vale se foi registrada antes do fim e não foi recusada
--     antes dele (o mesmo que tem_justificativa, só que "no fim do dia");
--   * a tarefa passada de folga vale se foi passada antes do fim.
-- A fila de hoje passa p_fim = infinity (o dia ainda não acabou): cada uma
-- dessas condições vira EXATAMENTE a de antes, sem depender dos dados.
-- O resto (tarefa, loja e pessoa ativas, folga, afastamento, vínculo com a
-- loja) é o cadastro de agora: por isso a foto é tirada logo depois da
-- meia-noite, e só vale se tirada até as 03:00.
-- Interna: recebe a conta; ninguém de fora chama.
CREATE OR REPLACE FUNCTION public.fila_no_dia(p_contaid integer, p_lojaid integer, p_dia date, p_fim timestamptz)
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
  fuso           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (
    SELECT p_contaid AS conta,
           p_dia AS dia,
           public.fuso_da_conta(p_contaid) AS fuso,
           -- O fim do dia (a meia-noite seguinte), ou infinity para hoje.
           p_fim AS fim,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = p_contaid AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
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
           WHEN ta.tipofrequencia = 'Unica' AND unica.cumprida THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.dataenvio < ctx.fim
                           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                           AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         -- Atrasada é o que AINDA falta fazer. A Única entregue hoje, mesmo
         -- marcada para ontem, está em "Feitas hoje": não é atrasada.
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.dia
          AND NOT unica.cumprida),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_na_conta(ctx.conta, ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) = ctx.dia
                THEN ta.dataagendamento END,
           -- A hora de liberação também conta: o cronômetro de uma tarefa que
           -- abre às 18h começa às 18h, e não à meia-noite — senão ela nasceria
           -- vermelha, com 18 horas de "parada".
           lib.quando),
         (ctx.rodizio > 0 AND ta.funcionarioid IS NULL),
         now(),
         -- nome_curto(NULL) devolve texto VAZIO, nao nulo: sem este CASE a
         -- coluna vinha '' para toda tarefa sem entrega, e "sem nome" deixava
         -- de ser distinguivel de "nome vazio".
         CASE WHEN ent.funcionarioid IS NOT NULL THEN public.nome_curto(fez.nomecompleto) END,
         ent.dataenvio,
         ent.statusvalidacao,
         (lib.quando IS NULL OR lib.quando <= now()),
         lib.quando,
         ctx.dia,
         ctx.fuso
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.aceitoem < ctx.fim
                                      AND (a.revogadoem IS NULL OR a.revogadoem >= ctx.fim)
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- Única cumprida (a de tarefa_unica_ja_cumprida, no fim do dia): entregue
    -- por qualquer cópia, em qualquer dia até o fim deste.
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM public.entregas e
          JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = ctx.conta
         WHERE e.contaid = ctx.conta
           AND e.dataenvio < ctx.fim
           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
           AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)) AS cumprida
    ) unica ON true
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só do dia.
    -- A situação é a do fim do dia: recusada ou estornada DEPOIS dele, ainda
    -- estava pendente ou aprovada.
    LEFT JOIN LATERAL (
      SELECT e.funcionarioid, e.dataenvio,
             CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                  WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                  WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= ctx.fim THEN 'Pendente'
                  ELSE e.statusvalidacao END::varchar AS statusvalidacao
        FROM public.entregas e
       WHERE e.contaid = ctx.conta
         AND e.dataenvio < ctx.fim
         AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
              OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
              OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
         AND (
           (ta.tipofrequencia = 'Unica'
            AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                         WHERE c.contaid = ctx.conta AND c.atribuicaoid = e.atribuicaoid
                           AND (c.atribuicaoid = ta.atribuicaoid
                                OR c.origematribuicaoid = ta.atribuicaoid)))
           OR (e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
               AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia)
         )
       ORDER BY e.dataenvio DESC
       LIMIT 1
    ) ent ON true
    LEFT JOIN public.funcionarios fez  ON fez.funcionarioid = ent.funcionarioid AND fez.contaid = ctx.conta
    -- A hora de liberação, no fuso DA EMPRESA. A conversão é feita aqui, com
    -- o relógio do servidor: o tablet e o celular não opinam.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN ta.disponivelapartir IS NOT NULL
                  THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.disponivelapartir) END AS quando
    ) lib ON true
   WHERE ctx.conta IS NOT NULL
     -- Valia no fim do dia: criada antes dele e não encerrada antes dele.
     AND coalesce(ta.criadaem, '-infinity'::timestamptz) < ctx.fim
     AND (ta.datafimvigencia IS NULL OR ta.encerradaem >= ctx.fim)
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     -- tem_justificativa(..., false), no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.justificativas j
                      WHERE j.contaid = ctx.conta AND j.atribuicaoid = ta.atribuicaoid
                        AND (ta.tipofrequencia = 'Unica' OR j.dia = ctx.dia)
                        AND j.registradoem < ctx.fim
                        AND (j.status IN ('Aceita', 'Pendente')
                             OR (j.status = 'Recusada' AND j.decididoem >= ctx.fim)))
     -- passada_hoje, no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.tarefasdodia p
                      WHERE p.contaid = ctx.conta AND p.atribuicaoid = ta.atribuicaoid AND p.dia = ctx.dia
                        AND p.passadapara IS NOT NULL
                        AND coalesce(p.passadaem, '-infinity'::timestamptz) < ctx.fim)
     -- A Única entregue num dia ANTERIOR acabou: não volta na fila de hoje.
     -- Sem isto ela ficava para sempre em "Feitas hoje" (a regra de "feita"
     -- da Única vale para qualquer dia, porque ela só se faz uma vez), e
     -- ainda marcada como atrasada. A TV já tinha esta regra; a fila, não.
     AND NOT (ta.tipofrequencia = 'Unica'
              AND EXISTS (SELECT 1 FROM public.entregas e
                            JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid
                                                           AND c.contaid = ctx.conta
                           WHERE e.contaid = ctx.conta
                             AND e.dataenvio < ctx.fim
                             AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                  OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                             AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                             AND public.dia_no_fuso(e.dataenvio, ctx.fuso) < ctx.dia))
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3
$$;
REVOKE ALL ON FUNCTION public.fila_no_dia(integer, integer, date, timestamptz) FROM public, anon, authenticated;

-- A fila de hoje: a mesma função, com o dia de hoje da conta de quem pede e
-- sem fim (infinity) — o dia ainda não acabou.
-- Parte da versão mais recente (20260929140000_hoje_da_conta.sql): mesmas
-- colunas, mesma ordem, mesmas permissões.
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
  disponiveldesde timestamptz,
  rodizio        boolean,
  agora          timestamptz,
  feitapor       text,
  feitaem        timestamptz,
  feitasituacao  text,
  liberada       boolean,
  liberaas       timestamptz,
  hoje           date,
  fuso           text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.*
    FROM (SELECT x.conta, public.hoje_da_conta(x.conta) AS dia
            FROM (SELECT public.minha_conta() AS conta) x
           WHERE x.conta IS NOT NULL) c
    CROSS JOIN LATERAL public.fila_no_dia(c.conta, p_lojaid, c.dia, 'infinity'::timestamptz) f
   -- A mesma ordem de antes; o número da atribuição desempata títulos iguais
   -- (antes a ordem entre eles não era definida).
   ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid
$$;
REVOKE ALL ON FUNCTION public.fila_da_loja(integer)     FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.fila_da_loja(integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. O alcance do filtro e o prazo de guarda: UMA regra
-- ---------------------------------------------------------------------------
-- O filtro alcança o mês corrente e o anterior. A foto fica guardada desde
-- um mês antes disso (a margem). Mudar o alcance aqui muda a guarda junto.
CREATE OR REPLACE FUNCTION public.fila_alcance(p_hoje date)
RETURNS TABLE (primeirodia date, guardardesde date)
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT a.primeiro, (a.primeiro - interval '1 month')::date
    FROM (SELECT (date_trunc('month', p_hoje) - interval '1 month')::date AS primeiro) a
$$;
REVOKE ALL ON FUNCTION public.fila_alcance(date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fila_alcance(date) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. A foto e a marca
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fotosdafila (
  contaid        integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  lojaid         integer NOT NULL,
  dia            date    NOT NULL,
  atribuicaoid   integer NOT NULL,
  entregarid     integer,
  titulo         varchar(255) NOT NULL,
  pontos         integer NOT NULL,
  tipofrequencia varchar(20) NOT NULL,
  aberta         boolean NOT NULL,
  donoid         integer,
  quempegou      integer,
  quempegounome  text,
  pegaem         timestamptz,
  situacao       varchar(12) NOT NULL CHECK (situacao IN ('para_pegar', 'em_andamento', 'feita')),
  atrasada       boolean NOT NULL DEFAULT false,
  feitapor       text,
  feitaem        timestamptz,
  feitasituacao  varchar(20),
  tiradaem       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contaid, dia, atribuicaoid),
  CONSTRAINT fotosdafila_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS fotosdafila_loja_dia_idx ON public.fotosdafila (contaid, lojaid, dia);
ALTER TABLE public.fotosdafila ENABLE ROW LEVEL SECURITY;
-- Só leitura para quem está logado; só a rotina escreve. (No Supabase a
-- tabela nova nasce com tudo liberado; a regra de acesso já barraria, e aqui
-- nem a permissão existe.)
REVOKE ALL ON public.fotosdafila FROM anon, authenticated;
GRANT SELECT ON public.fotosdafila TO authenticated;
GRANT ALL ON public.fotosdafila TO service_role;
DROP POLICY IF EXISTS fotosdafila_sel ON public.fotosdafila;
CREATE POLICY fotosdafila_sel ON public.fotosdafila FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));
COMMENT ON TABLE public.fotosdafila IS
  'A fila de cada loja como estava no fim de cada dia (foto tirada pela rotina da madrugada). Guardada pelo prazo de fila_alcance.';

-- A marca "registro completo": a hora da foto. Vazia = "não registrado".
ALTER TABLE public.diasgerados ADD COLUMN IF NOT EXISTS fotodafilaem timestamptz;
COMMENT ON COLUMN public.diasgerados.fotodafilaem IS
  'Quando a foto da fila deste dia foi tirada. Vazia: o Quadro mostra "não registrado" em "para pegar".';

-- Apagou linhas da foto de um dia, por qualquer caminho: a marca daquele dia
-- cai junto, na mesma operação. (A limpeza também derruba a marca de dia
-- sem nenhuma linha — uma loja sem nada na fila.)
CREATE OR REPLACE FUNCTION public.foto_apagada_derruba_marca()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.diasgerados dg
     SET fotodafilaem = NULL
    FROM (SELECT DISTINCT contaid, dia FROM apagadas) x
   WHERE dg.contaid = x.contaid AND dg.dia = x.dia AND dg.fotodafilaem IS NOT NULL;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.foto_apagada_derruba_marca() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS fotosdafila_derruba_marca ON public.fotosdafila;
CREATE TRIGGER fotosdafila_derruba_marca
  AFTER DELETE ON public.fotosdafila
  REFERENCING OLD TABLE AS apagadas
  FOR EACH STATEMENT EXECUTE FUNCTION public.foto_apagada_derruba_marca();

-- Tirar a foto de um dia que acabou, de todas as lojas ativas da conta.
-- Interna: quem decide o dia é rotina_lista_do_dia.
CREATE OR REPLACE FUNCTION public.fila_foto_tirar(p_contaid integer, p_dia date, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_itens integer; v_pegar integer;
BEGIN
  IF p_agora < public.instante_na_conta(p_contaid, p_dia + 1, '00:00'::time) THEN
    RAISE EXCEPTION 'A foto é do dia que acabou.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = p_contaid AND dia = p_dia) THEN
    RAISE EXCEPTION 'O dia % não tem lista gerada.', p_dia USING ERRCODE = 'no_data_found';
  END IF;

  DELETE FROM public.fotosdafila WHERE contaid = p_contaid AND dia = p_dia;
  INSERT INTO public.fotosdafila (contaid, lojaid, dia, atribuicaoid, entregarid, titulo, pontos, tipofrequencia,
                                  aberta, donoid, quempegou, quempegounome, pegaem, situacao, atrasada,
                                  feitapor, feitaem, feitasituacao, tiradaem)
  SELECT p_contaid, l.lojaid, p_dia, f.atribuicaoid, f.entregarid, f.titulo, f.pontos, f.tipofrequencia,
         f.aberta, f.donoid, f.quempegou, f.quempegounome, f.pegaem, f.situacao, f.atrasada,
         f.feitapor, f.feitaem, f.feitasituacao, p_agora
    FROM public.lojas l
    CROSS JOIN LATERAL public.fila_no_dia(p_contaid, l.lojaid, p_dia,
                                          public.instante_na_conta(p_contaid, p_dia + 1, '00:00'::time)) f
   WHERE l.contaid = p_contaid AND l.ativa;
  GET DIAGNOSTICS v_itens = ROW_COUNT;

  UPDATE public.diasgerados SET fotodafilaem = p_agora WHERE contaid = p_contaid AND dia = p_dia;

  SELECT count(*) INTO v_pegar FROM public.fotosdafila
   WHERE contaid = p_contaid AND dia = p_dia AND situacao = 'para_pegar';
  RETURN jsonb_build_object('dia', p_dia, 'itens', v_itens, 'parapegar', v_pegar);
END;
$$;
REVOKE ALL ON FUNCTION public.fila_foto_tirar(integer, date, timestamptz) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. A rotina tira a foto do dia que acabou
-- ---------------------------------------------------------------------------
ALTER TABLE public.rotinasexecucoes DROP CONSTRAINT IF EXISTS rotinasexecucoes_rotina_check;
ALTER TABLE public.rotinasexecucoes ADD CONSTRAINT rotinasexecucoes_rotina_check
  CHECK (rotina IN ('lista_do_dia', 'fechamento_mensal', 'conferencia_livro', 'limpeza', 'mensagens',
                    'expurgo_fotos', 'foto_da_fila'));

-- Parte da versão mais recente (20260924100000_rotinas_lista_do_dia.sql),
-- com o diff conferido: entra só o bloco da foto, entre os dias recuperados
-- e a lista de hoje. A virada do dia continua sendo a desta rotina (v_hoje).
CREATE OR REPLACE FUNCTION public.rotina_lista_do_dia(p_contaid integer, p_agora timestamptz, p_origem text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje     date;
  v_hora     time;
  v_primeiro date;
  v_ja       boolean;
  v_inicio   timestamptz;
  v_res      jsonb;
  v_hoje_res jsonb;
  v_recup    integer := 0;
  d          date;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;

  -- Dias perdidos: só depois da primeira geração da conta, no máximo 7 para trás.
  SELECT min(dia) INTO v_primeiro FROM public.diasgerados WHERE contaid = p_contaid;
  IF v_primeiro IS NOT NULL THEN
    FOR d IN
      SELECT g::date FROM generate_series(greatest(v_primeiro, v_hoje - 7), v_hoje - 1, interval '1 day') g
       WHERE NOT EXISTS (SELECT 1 FROM public.diasgerados dg WHERE dg.contaid = p_contaid AND dg.dia = g::date)
       ORDER BY 1
    LOOP
      v_inicio := clock_timestamp();
      BEGIN
        v_res := public.lista_do_dia_gerar(p_contaid, d, v_hoje, true);
        PERFORM public.rotina_registrar(p_contaid, 'lista_do_dia', d, p_origem, v_inicio, 'ok', v_res, NULL, true);
        v_recup := v_recup + 1;
      EXCEPTION WHEN OTHERS THEN
        PERFORM public.rotina_registrar(p_contaid, 'lista_do_dia', d, p_origem, v_inicio, 'erro', NULL, SQLERRM, true);
      END;
    END LOOP;
  END IF;

  -- A foto da fila de ONTEM (o dia que acabou), logo depois da meia-noite.
  -- Só vale até as 03:00: depois disso o cadastro de hoje já pode ter mudado
  -- (pessoa desligada, tarefa desativada) e a foto deixaria de ser a do fim
  -- do dia. Dia com lista recuperada depois de uma parada não ganha foto.
  -- Sem foto, o dia fica "não registrado" e a /saude avisa.
  IF p_agora < public.instante_na_conta(p_contaid, v_hoje, '03:00'::time)
     AND EXISTS (SELECT 1 FROM public.diasgerados dg
                  WHERE dg.contaid = p_contaid AND dg.dia = v_hoje - 1
                    AND NOT dg.recuperado AND dg.fotodafilaem IS NULL) THEN
    v_inicio := clock_timestamp();
    BEGIN
      v_res := public.fila_foto_tirar(p_contaid, v_hoje - 1, p_agora);
      PERFORM public.rotina_registrar(p_contaid, 'foto_da_fila', v_hoje - 1, p_origem, v_inicio, 'ok', v_res, NULL, false);
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.rotina_registrar(p_contaid, 'foto_da_fila', v_hoje - 1, p_origem, v_inicio, 'erro', NULL, SQLERRM, false);
    END;
  END IF;

  -- Hoje.
  v_inicio := clock_timestamp();
  BEGIN
    v_ja := EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = p_contaid AND dia = v_hoje);
    IF p_origem = 'manual' OR v_ja
       OR v_hora >= public.rotina_horario(p_contaid, 'HORARIO_GERACAO_TAREFAS', '00:05') THEN
      v_hoje_res := public.lista_do_dia_gerar(p_contaid, v_hoje, v_hoje, false);
      -- Registra a primeira geração do dia, a rodada manual e qualquer ajuste.
      IF NOT v_ja OR p_origem = 'manual'
         OR (v_hoje_res->>'novos')::integer + (v_hoje_res->>'cancelados')::integer
            + (v_hoje_res->>'ajustados')::integer > 0 THEN
        PERFORM public.rotina_registrar(p_contaid, 'lista_do_dia', v_hoje, p_origem, v_inicio, 'ok',
                                        v_hoje_res || jsonb_build_object('ajuste', v_ja), NULL, false);
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'lista_do_dia', v_hoje, p_origem, v_inicio, 'erro', NULL, SQLERRM, false);
    v_hoje_res := jsonb_build_object('erro', SQLERRM);
  END;

  RETURN jsonb_build_object('recuperados', v_recup, 'hoje', v_hoje_res);
END;
$$;
REVOKE ALL ON FUNCTION public.rotina_lista_do_dia(integer, timestamptz, text) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. A limpeza apaga as fotos fora do prazo, e a marca cai junto
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260924120000_rotinas_conferencia_e_agendamento.sql),
-- com o diff conferido: entram as fotos, com o prazo de fila_alcance.
CREATE OR REPLACE FUNCTION public.rotina_limpeza(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_n      integer;
  v_fotos  integer;
  v_desde  date;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'limpeza' AND referencia = v_hoje AND resultado = 'ok') THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;
    DELETE FROM public.rotinasexecucoes
     WHERE contaid = p_contaid AND iniciadoem < p_agora - interval '180 days';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- A foto da fila: guardada desde fila_alcance (o alcance do filtro mais
    -- a margem). A marca dos dias apagados cai junto — também a de dia sem
    -- nenhuma linha, que o gatilho da tabela não vê.
    SELECT a.guardardesde INTO v_desde FROM public.fila_alcance(v_hoje) a;
    DELETE FROM public.fotosdafila WHERE contaid = p_contaid AND dia < v_desde;
    GET DIAGNOSTICS v_fotos = ROW_COUNT;
    UPDATE public.diasgerados SET fotodafilaem = NULL
     WHERE contaid = p_contaid AND dia < v_desde AND fotodafilaem IS NOT NULL;

    PERFORM public.rotina_registrar(p_contaid, 'limpeza', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('apagados', v_n, 'fotosdafila', v_fotos), NULL);
    RETURN jsonb_build_object('apagados', v_n, 'fotosdafila', v_fotos);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'limpeza', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;
REVOKE ALL ON FUNCTION public.rotina_limpeza(integer, timestamptz) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. O Quadro lê um dia que passou
-- ---------------------------------------------------------------------------
-- Com a permissão de quem chama (a RLS vale). Só dias que passaram, dentro
-- do alcance do filtro. Com foto: a fila do fim do dia, inteira. Sem foto:
-- "não registrado" — sem número em "para pegar" — e o que foi feito e o que
-- estava em andamento, que ficam gravados (entregas e aceites, com hora).
CREATE OR REPLACE FUNCTION public.fila_de_um_dia(p_lojaid integer, p_dia date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
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
$$;
REVOKE ALL ON FUNCTION public.fila_de_um_dia(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fila_de_um_dia(integer, date) TO authenticated;

-- O alcance do filtro, para a tela (o primeiro dia que dá para escolher).
CREATE OR REPLACE FUNCTION public.alcance_da_fila()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('hoje', h.hoje, 'primeirodia', a.primeirodia)
    FROM (SELECT (public.meu_hoje()->>'hoje')::date AS hoje) h
    CROSS JOIN LATERAL public.fila_alcance(h.hoje) a
   WHERE public.minha_conta() IS NOT NULL AND h.hoje IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.alcance_da_fila() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.alcance_da_fila() TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. A /saude avisa os dias sem foto
-- ---------------------------------------------------------------------------
-- Dias (dos últimos 30) sem foto da fila, desde que a foto começou a ser
-- tirada nesta conta. Ontem só conta depois das 03:00 de hoje (antes disso a
-- rotina ainda pode tirar). Interna: recebe a conta.
CREATE OR REPLACE FUNCTION public.fila_dias_sem_foto(p_contaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH h AS (SELECT public.hoje_da_conta(p_contaid) AS hoje),
  inicio AS (
    SELECT min(r.referencia) AS dia FROM public.rotinasexecucoes r
     WHERE r.contaid = p_contaid AND r.rotina = 'foto_da_fila'
  ),
  faltam AS (
    SELECT g::date AS dia
      FROM h, inicio,
           generate_series(greatest(inicio.dia, h.hoje - 30),
                           h.hoje - CASE WHEN now() >= public.instante_na_conta(p_contaid, h.hoje, '03:00'::time)
                                         THEN 1 ELSE 2 END,
                           interval '1 day') g
     WHERE inicio.dia IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.diasgerados dg
                        WHERE dg.contaid = p_contaid AND dg.dia = g::date AND dg.fotodafilaem IS NOT NULL)
  )
  SELECT jsonb_build_object('dias', count(*), 'ultimo', max(dia)) FROM faltam
$$;
REVOKE ALL ON FUNCTION public.fila_dias_sem_foto(integer) FROM public, anon, authenticated;

-- Parte da versão mais recente (20260929231000_fotos_de_verdade_e_saude.sql),
-- com o diff conferido: entra 'fila'.
CREATE OR REPLACE FUNCTION public.saude_da_minha_conta()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object(
    'fotos', public.fotos_vencidas_da_conta(v_conta),
    'mensagensfalhadas', (SELECT count(*) FROM public.mensagensfila
                           WHERE contaid = v_conta AND status = 'falhou' AND criadoem >= now() - interval '24 hours'),
    'fila', public.fila_dias_sem_foto(v_conta));
END;
$$;
REVOKE ALL ON FUNCTION public.saude_da_minha_conta() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.saude_da_minha_conta() TO authenticated;

-- Parte da versão mais recente (20260929231000_fotos_de_verdade_e_saude.sql),
-- com o diff conferido: entra 'fila' (todas as contas ativas somadas).
CREATE OR REPLACE FUNCTION public.saude_das_rotinas()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_segredos jsonb := '{}'::jsonb;
  v_jobs     jsonb := '[]'::jsonb;
  v_nome     text;
  v_existe   boolean;
  v_fotos    jsonb;
  v_fila     jsonb;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    FOREACH v_nome IN ARRAY ARRAY['stgame_funcoes_url', 'stgame_fila_segredo', 'stgame_expurgo_segredo'] LOOP
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = $1 AND coalesce(decrypted_secret, '''') <> '''')'
        INTO v_existe USING v_nome;
      v_segredos := v_segredos || jsonb_build_object(v_nome, v_existe);
    END LOOP;
  END IF;

  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE $q$
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'nome', n.nome,
               'existe', j.jobid IS NOT NULL,
               'ativo', coalesce(j.active, false),
               'ultimaexecucao', r.end_time,
               'ultimostatus', r.status) ORDER BY n.nome), '[]'::jsonb)
        FROM unnest(ARRAY['gamegb-rotinas', 'stgame-telegram-fila']) n(nome)
        LEFT JOIN cron.job j ON j.jobname = n.nome
        LEFT JOIN LATERAL (SELECT d.end_time, d.status FROM cron.job_run_details d
                            WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1) r ON true
    $q$ INTO v_jobs;
  END IF;

  SELECT jsonb_build_object(
           'vencidas', coalesce(sum((f->>'vencidas')::integer), 0),
           'diasdeatraso', coalesce(max((f->>'diasdeatraso')::integer), 0),
           'presas', coalesce(sum((f->>'presas')::integer), 0))
    INTO v_fotos
    FROM (SELECT public.fotos_vencidas_da_conta(c.contaid) f FROM public.contas c) x;

  -- Dias sem foto da fila: quantos, em quantas contas, e o mais recente.
  SELECT jsonb_build_object(
           'dias', coalesce(sum((f->>'dias')::integer), 0),
           'contas', count(*) FILTER (WHERE (f->>'dias')::integer > 0),
           'ultimo', max((f->>'ultimo')::date))
    INTO v_fila
    FROM (SELECT public.fila_dias_sem_foto(c.contaid) f FROM public.contas c WHERE c.status = 'ativa') x;

  RETURN jsonb_build_object(
    'cofre', to_regclass('vault.decrypted_secrets') IS NOT NULL,
    'pgnet', to_regproc('net.http_post') IS NOT NULL,
    'segredos', v_segredos,
    'agendador', to_regclass('cron.job') IS NOT NULL,
    'jobs', v_jobs,
    'mensagensfalhadas', (SELECT count(*) FROM public.mensagensfila
                           WHERE status = 'falhou' AND criadoem >= now() - interval '24 hours'),
    'fotos', v_fotos,
    'fila', v_fila);
END;
$$;
REVOKE ALL ON FUNCTION public.saude_das_rotinas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.saude_das_rotinas() TO service_role;

COMMIT;
