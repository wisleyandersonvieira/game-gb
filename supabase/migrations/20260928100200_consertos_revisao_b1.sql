-- Etapa 1.12, parte B1 — consertos da revisão adversarial (24/09/2026).
--
-- Um segundo agente tentou quebrar a parte B1. Não achou vazamento entre
-- contas nem escalada de papel, mas achou cinco falhas reais. Estas são as
-- correções; cada uma ganhou prova no teste de isolamento.

-- ---------------------------------------------------------------------------
-- 1. CRÍTICO: a trava do PIN do tablet não travava nada
-- ---------------------------------------------------------------------------
-- O PIN digitado no tablet usava o tipo 'tablet', que foi criado na parte A
-- para a SENHA do tablet (14 caracteres sorteados pelo servidor) e por isso é
-- isento da trava por chave. Sobrava só a trava por origem, com dois furos:
--   (a) sem o cabeçalho de IP da hospedagem, a origem vira 'sem-ip' e a trava
--       por origem é pulada inteira — dava tentativas infinitas;
--   (b) a contagem por origem zera a cada ACERTO, e quem ataca é alguém que
--       sabe o próprio PIN: 4 chutes + 1 acerto, para sempre.
-- Provado pelo revisor: 200 chutes aceitos, 0 recusados.
--
-- Tipo novo 'pintablet', com três camadas:
--   * teto diário de ERROS por tablet, que o acerto NÃO zera (é o que fecha o
--     furo (b));
--   * a trava curta de 5 erros em 15 minutos, que o acerto zera (para quem
--     errou de dedo não ficar preso);
--   * a trava por origem, como já era.
-- A trava por chave vale mesmo sem IP (fecha o furo (a)). Travar a chave aqui
-- é aceitável — ao contrário da senha do tablet, quem chega no teclado do PIN
-- já está com o tablet na mão.
ALTER TABLE public.tentativasacesso DROP CONSTRAINT IF EXISTS tentativasacesso_tipo_check;
ALTER TABLE public.tentativasacesso ADD  CONSTRAINT tentativasacesso_tipo_check
  CHECK (tipo IN ('senha', 'pin', 'tablet', 'pintablet'));

CREATE OR REPLACE FUNCTION public.tentativa_abrir(p_contaid integer, p_tipo text,
                                                  p_chave text, p_origem text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_janela interval := CASE WHEN p_tipo = 'pin' THEN interval '1 minute' ELSE interval '15 minutes' END;
  v_chave  text     := left(coalesce(p_chave, ''), 64);
  v_origem text     := left(coalesce(p_origem, 'sem-ip'), 40);
  v_erros  integer;
  v_id     bigint;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre tentativa de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_tipo NOT IN ('senha', 'pin', 'tablet', 'pintablet') THEN
    RAISE EXCEPTION 'Tipo de tentativa inválido.' USING ERRCODE = 'check_violation';
  END IF;

  -- Duas trancas, SEMPRE nesta ordem (chave e depois origem), para duas
  -- tentativas nunca contarem ao mesmo tempo. A ordem fixa evita travar uma na
  -- outra.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.chave:' || p_tipo || ':' || v_chave, 0));
  IF v_origem <> 'sem-ip' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('stgame.origem:' || p_tipo || ':' || v_origem, 0));
  END IF;

  -- PIN no celular da pessoa: teto de 30 no dia contando TODA tentativa
  -- (acerto inclusive). Ali o resultado comum é acerto, e quem tenta já está
  -- logado como a própria pessoa: só gasta a própria cota.
  IF p_tipo = 'pin' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pin' AND t.chave = v_chave
       AND t.em > now() - interval '1 day';
    IF v_erros >= 30 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- PIN no tablet: teto de 20 ERROS no dia por tablet, que o acerto NÃO zera.
  -- Aqui contar só erro é o certo (o uso normal acerta o tempo todo), e não
  -- zerar no acerto é o que impede usar o próprio PIN para limpar o contador.
  IF p_tipo = 'pintablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = 'pintablet' AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - interval '1 day';
    IF v_erros >= 20 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta chave, desde o último acerto dela (o acerto zera).
  -- NÃO vale para a senha do tablet: ela é sorteada pelo servidor (impossível
  -- de adivinhar) e travá-la por e-mail só deixaria a loja sem sistema.
  IF p_tipo <> 'tablet' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.chave = v_chave
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.chave = v_chave AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Erros seguidos desta origem: é o eixo que o atacante controla e a vítima
  -- não. Vale para todos, inclusive para o tablet.
  IF v_origem <> 'sem-ip' THEN
    SELECT count(*) INTO v_erros FROM public.tentativasacesso t
     WHERE t.contaid IS NOT DISTINCT FROM p_contaid AND t.tipo = p_tipo AND t.origem = v_origem
       AND NOT t.sucesso AND t.em > now() - v_janela
       AND t.em > coalesce((SELECT max(s.em) FROM public.tentativasacesso s
                             WHERE s.contaid IS NOT DISTINCT FROM p_contaid AND s.tipo = p_tipo
                               AND s.origem = v_origem AND s.sucesso), '-infinity'::timestamptz);
    IF v_erros >= 5 THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso)
  VALUES (p_contaid, p_tipo, v_chave, v_origem, false)
  RETURNING tentativaid INTO v_id;

  DELETE FROM public.tentativasacesso WHERE em < now() - interval '7 days';
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.tentativa_abrir(integer, text, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tentativa_abrir(integer, text, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. SÉRIO: tarefa compartilhada Única voltava para a fila no dia seguinte
-- ---------------------------------------------------------------------------
-- A fila procurava a entrega em coalesce(aceite de HOJE, a própria tarefa).
-- Numa tarefa sem dono a entrega vive na CÓPIA de quem pegou — e a cópia de
-- ONTEM o coalesce nunca alcançava. Resultado: a tarefa Única já entregue e
-- aprovada reaparecia em "Para pegar" todo dia, e pagava de novo todo dia.
-- Agora, na tarefa sem dono, "já foi feita" olha QUALQUER cópia dela.
CREATE OR REPLACE FUNCTION public.tarefa_unica_ja_cumprida(p_contaid integer, p_atribuicaoid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.entregas e
      JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = p_contaid
     WHERE e.contaid = p_contaid
       AND e.statusvalidacao IN ('Pendente', 'Aprovada')
       AND (c.atribuicaoid = p_atribuicaoid OR c.origematribuicaoid = p_atribuicaoid))
$$;
REVOKE ALL ON FUNCTION public.tarefa_unica_ja_cumprida(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tarefa_unica_ja_cumprida(integer, integer) TO service_role;

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
  atrasada       boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.minha_conta() AS conta, public.dia_em_sao_paulo(now()) AS dia)
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
          AND public.dia_em_sao_paulo(ta.dataagendamento) < ctx.dia)
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.revogadoem IS NULL
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
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

CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL)
RETURNS TABLE (
  atribuicaoid integer,
  lojaid       integer,
  loja         varchar,
  titulo       varchar,
  pontos       integer,
  atribuidos   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.minha_conta() AS conta, public.dia_em_sao_paulo(now()) AS dia)
  SELECT ta.atribuicaoid, ta.lojaid, l.nome, t.titulo, t.pontos,
         coalesce((SELECT string_agg(public.nome_curto(f.nomecompleto), ', ' ORDER BY f.nomecompleto)
                     FROM public.tarefascandidatos c
                     JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = ctx.conta
                    WHERE c.contaid = ctx.conta AND c.atribuicaoid = ta.atribuicaoid),
                  'toda a equipe da loja')
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.funcionarioid IS NULL
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
   WHERE ctx.conta IS NOT NULL
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo
$$;

-- ---------------------------------------------------------------------------
-- 3. SÉRIO: corrida "revogar o aceite" x "entregar"
-- ---------------------------------------------------------------------------
-- revogar_aceite conferia "não existe entrega" e encerrava a cópia, mas não
-- trancava a cópia; registrar_entrega lia a atribuição sem FOR UPDATE. As duas
-- transações não colidiam em lock nenhum, e o revisor provou o resultado: uma
-- entrega Pendente numa cópia já revogada, aprovada depois, e a mesma tarefa
-- paga duas vezes no mesmo dia.
--
-- Agora as duas trancam a mesma linha: uma espera a outra, e a conferência
-- volta a valer.
CREATE OR REPLACE FUNCTION public.revogar_aceite(p_atribuicaoid integer, p_dia date, p_motivo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.minha_conta_editavel();
  v_motivo text    := nullif(btrim(coalesce(p_motivo, '')), '');
  a        public.missoesaceites%ROWTYPE;
  v_alvo   integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_motivo IS NULL THEN
    RAISE EXCEPTION 'Diga o motivo da revogação.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO a FROM public.missoesaceites
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = p_dia AND revogadoem IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não há aceite ativo para revogar.' USING ERRCODE = 'no_data_found';
  END IF;

  v_alvo := coalesce(a.novaatribuicaoid, a.atribuicaoid);

  -- Tranca a atribuição em que a entrega entraria, ANTES de conferir. Sem
  -- isto, uma entrega no mesmo instante passava pela conferência.
  PERFORM 1 FROM public.tarefasatribuidas
   WHERE contaid = v_conta AND atribuicaoid = v_alvo FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.entregas e
              WHERE e.contaid = v_conta AND e.atribuicaoid = v_alvo
                AND e.statusvalidacao IN ('Pendente', 'Aprovada')) THEN
    RAISE EXCEPTION 'Já existe entrega desta tarefa. Recuse a entrega antes de revogar o aceite.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.missoesaceites
     SET revogadoem = now(), revogadopor = auth.uid(), motivorevogacao = v_motivo
   WHERE aceiteid = a.aceiteid;

  IF a.novaatribuicaoid IS NOT NULL THEN
    UPDATE public.tarefasatribuidas SET datafimvigencia = p_dia
     WHERE contaid = v_conta AND atribuicaoid = a.novaatribuicaoid;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Entregar: tranca a atribuição e não aceita foto já usada
-- ---------------------------------------------------------------------------
-- Duas correções da revisão:
--  * FOR UPDATE na atribuição (a outra ponta da corrida do item 3);
--  * a mesma foto não vale para duas entregas. O caminho do Telegram já tinha
--    essa proteção (fotoidunico); o do app e do tablet não tinha, e "provar" a
--    tarefa com a foto de ontem era trivial no balcão.
CREATE OR REPLACE FUNCTION public.registrar_entrega(
  p_atribuicaoid integer,
  p_observacao   text    DEFAULT NULL,
  p_pathfoto     text    DEFAULT NULL,
  p_aprovar      boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_hoje  date    := public.dia_em_sao_paulo(now());
  v_foto  text    := nullif(btrim(coalesce(p_pathfoto, '')), '');
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_atr FROM public.tarefasatribuidas
  WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_atr.datafimvigencia IS NOT NULL THEN
    RAISE EXCEPTION 'Esta atribuição foi encerrada.' USING ERRCODE = 'check_violation';
  END IF;

  IF v_atr.funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Atribuição sem funcionário não recebe entrega.' USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.tarefa_cai_no_dia(v_atr.tipofrequencia, v_atr.valorfrequencia, v_atr.dataagendamento, v_hoje) THEN
    RAISE EXCEPTION 'Esta tarefa não cai hoje.' USING ERRCODE = 'check_violation';
  END IF;

  -- Unica: depois de entregue (pendente ou aprovada) em qualquer dia, acabou.
  -- Na compartilhada, vale para qualquer cópia: senão a tarefa voltava todo
  -- dia e pagava de novo.
  IF v_atr.tipofrequencia = 'Unica'
     AND public.tarefa_unica_ja_cumprida(v_conta, coalesce(v_atr.origematribuicaoid, p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF v_foto IS NOT NULL AND v_foto NOT LIKE v_conta || '/' || v_atr.lojaid || '/%' THEN
    RAISE EXCEPTION 'A foto precisa estar na pasta da própria loja.' USING ERRCODE = 'check_violation';
  END IF;

  -- A mesma foto não prova duas tarefas.
  IF v_foto IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                     WHERE e.contaid = v_conta AND e.pathfotoevidencia = v_foto) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Entregar vale como aceite (tarefa com dono; a cópia da compartilhada já
  -- nasceu de um aceite).
  IF v_atr.origematribuicaoid IS NULL THEN
    INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
    VALUES (v_conta, p_atribuicaoid, v_hoje, v_atr.funcionarioid, public.canal_atual())
    ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  END IF;

  BEGIN
    INSERT INTO public.entregas (
      contaid, tarefaid, funcionarioid, lojaid, atribuicaoid,
      dataenvio, pathfotoevidencia, observacao, statusvalidacao
    ) VALUES (
      v_conta, v_atr.tarefaid, v_atr.funcionarioid, v_atr.lojaid, p_atribuicaoid,
      now(), v_foto, nullif(btrim(coalesce(p_observacao, '')), ''), 'Pendente'
    )
    RETURNING entregaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Já existe uma entrega desta atribuição hoje, pendente ou aprovada.'
      USING ERRCODE = 'unique_violation';
  END;

  IF p_aprovar THEN
    PERFORM public.aprovar_entrega(v_id);
  END IF;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Pegar: a tarefa Única já cumprida não volta para a fila
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pegar_tarefa(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.dia_em_sao_paulo(now());
  m       public.tarefasatribuidas%ROWTYPE;
  v_lista boolean;
  v_nova  integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Sem pessoa para pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND datafimvigencia IS NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF m.origematribuicaoid IS NOT NULL THEN
    RAISE EXCEPTION 'Esta tarefa já está no nome de alguém.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje) THEN
    RAISE EXCEPTION 'Esta tarefa não vale para hoje.' USING ERRCODE = 'check_violation';
  END IF;
  IF m.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(v_conta, p_atribuicaoid) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = m.lojaid
                                                   AND fl.ativo AND fl.contaid = v_conta
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = v_conta AND f.ativo
                    AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                               f.datafimafastamento, v_hoje)) THEN
    RAISE EXCEPTION 'Só quem trabalha hoje nesta loja pode pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    IF m.funcionarioid <> p_funcionarioid THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                    WHERE c.contaid = v_conta AND c.atribuicaoid = p_atribuicaoid) INTO v_lista;
    IF v_lista AND NOT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                                WHERE c.contaid = v_conta AND c.atribuicaoid = p_atribuicaoid
                                  AND c.funcionarioid = p_funcionarioid) THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
  VALUES (v_conta, p_atribuicaoid, v_hoje, p_funcionarioid, public.canal_atual())
  ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa já foi pega hoje.' USING ERRCODE = 'unique_violation';
  END IF;

  IF m.funcionarioid IS NOT NULL THEN
    RETURN p_atribuicaoid;
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        dataatribuicao, dataagendamento, origematribuicaoid)
  VALUES (v_conta, m.tarefaid, p_funcionarioid, m.lojaid, 'Unica', now(), now(), p_atribuicaoid)
  RETURNING atribuicaoid INTO v_nova;

  UPDATE public.missoesaceites SET novaatribuicaoid = v_nova
   WHERE contaid = v_conta AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
  RETURN v_nova;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. MÉDIO: o tablet mandava o atribuicaoid que quisesse
-- ---------------------------------------------------------------------------
-- visao_pegar e visao_entregar só conferiam conta e loja. A fila já exclui
-- tarefa desativada, justificada ou passada hoje — mas nada disso era
-- reconferido, e o id vem do navegador do tablet. Agora as duas exigem que a
-- tarefa esteja na fila de hoje daquela loja: a mesma fonte da verdade que a
-- tela usa.
CREATE OR REPLACE FUNCTION public.visao_pegar(p_contaid integer, p_lojaid integer,
                                              p_funcionarioid integer, p_atribuicaoid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');
  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(p_lojaid) f
                  WHERE f.atribuicaoid = p_atribuicaoid AND f.situacao <> 'feita') THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN public.pegar_tarefa(p_atribuicaoid, p_funcionarioid);
END;
$$;

CREATE OR REPLACE FUNCTION public.visao_entregar(p_contaid integer, p_lojaid integer,
                                                 p_funcionarioid integer, p_atribuicaoid integer,
                                                 p_caminho text, p_observacao text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  m      public.tarefasatribuidas%ROWTYPE;
  v_hoje date := public.dia_em_sao_paulo(now());
  v_alvo integer;
  v_dono integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(p_lojaid) f
                  WHERE f.atribuicaoid = p_atribuicaoid AND f.situacao <> 'feita') THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF m.funcionarioid IS NULL THEN
    SELECT novaatribuicaoid, funcionarioid INTO v_alvo, v_dono
      FROM public.missoesaceites
     WHERE contaid = p_contaid AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
    IF v_alvo IS NULL THEN
      v_alvo := public.pegar_tarefa(p_atribuicaoid, p_funcionarioid);
    ELSIF v_dono <> p_funcionarioid THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF m.funcionarioid <> p_funcionarioid THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  ELSE
    v_alvo := p_atribuicaoid;
  END IF;

  RETURN public.registrar_entrega(v_alvo, p_observacao, p_caminho, false);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. PEQUENO: a missão do dia não voltava ao grupo depois de revogada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bot_texto_rotina(p_tipo text, p_contaid integer, p_funcionarioid integer,
                                                   p_referencia integer)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date := public.dia_em_sao_paulo(now());
  v_nome   text;
  v_itens  jsonb;
  v_lista  jsonb;
  v_bot    jsonb := '[]'::jsonb;
  v_texto  text;
  v_hora   time := (now() AT TIME ZONE 'America/Sao_Paulo')::time;
  r        record;
  v_n      integer;
BEGIN
  SELECT public.nome_curto(nomecompleto) INTO v_nome FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = p_contaid;

  IF p_tipo IN ('inicio_jornada', 'lembrete3', 'lembrete6') THEN
    v_itens := public.bot_abertas_da_pessoa(p_contaid, p_funcionarioid);
    IF p_tipo <> 'inicio_jornada' AND jsonb_array_length(v_itens) = 0 THEN
      RETURN NULL;                                   -- já fez tudo: lembrete não sai
    END IF;
    v_lista := public.bot_lista_tarefas(v_itens);
    IF p_tipo = 'inicio_jornada' THEN
      v_texto := CASE WHEN v_hora < '12:00' THEN '☀️ Bom dia' WHEN v_hora < '18:00' THEN '🌤️ Boa tarde' ELSE '🌙 Boa noite' END
                 || ', <b>' || public.bot_html(v_nome) || '</b>!';
      v_texto := v_texto || CASE WHEN jsonb_array_length(v_itens) = 0
                                 THEN E'\n\nVocê não tem tarefas hoje. Bom trabalho! ✨'
                                 ELSE E'\n\n<b>Suas tarefas de hoje</b>' || (v_lista->>'texto') END;
      IF public.bot_falta_feedback_ontem(p_contaid, p_funcionarioid) THEN
        v_texto := v_texto || E'\n\n⭐ Você não avaliou o dia de ontem.';
        v_bot := jsonb_build_array(jsonb_build_array(jsonb_build_object('text', '⭐ Avaliar ontem', 'callback_data', 'fbm:ontem')));
      END IF;
    ELSE
      v_texto := '👋 <b>' || public.bot_html(v_nome) || '</b>, ainda em aberto:' || (v_lista->>'texto');
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage', 'texto', v_texto,
                              'botoes', (v_lista->'botoes') || v_bot);

  ELSIF p_tipo = 'fim_jornada' THEN
    SELECT count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada') AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente') AS pendentes
      INTO r
      FROM public.entregas e
     WHERE e.contaid = p_contaid AND e.funcionarioid = p_funcionarioid
       AND public.dia_em_sao_paulo(e.dataenvio) = v_hoje;
    SELECT coalesce(sum(pontos), 0) INTO v_n FROM public.movimentospontos
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
       AND public.dia_em_sao_paulo(datamovimento) = v_hoje AND pontos > 0;
    v_itens := public.bot_abertas_da_pessoa(p_contaid, p_funcionarioid);
    v_texto := '🌆 Fim de expediente, <b>' || public.bot_html(v_nome) || E'</b>!\n\n'
               || '✅ ' || r.aprovadas || ' aprovadas · ⏳ ' || r.pendentes || ' em validação · 🎯 +' || v_n || ' pontos hoje';
    IF jsonb_array_length(v_itens) > 0 THEN
      v_texto := v_texto || E'\n\nFicou pendente:' || (public.bot_lista_tarefas(v_itens)->>'texto');
    ELSE
      v_texto := v_texto || E'\n\nVocê fechou o dia sem pendências. Trabalho incrível! 🏆';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.feedbacks WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                     AND datafeedback = v_hoje AND anuladoem IS NULL) THEN
      v_texto := v_texto || E'\n\nComo foi o seu dia?';
      v_bot := jsonb_build_array(jsonb_build_array(jsonb_build_object('text', '⭐ Avaliar meu dia', 'callback_data', 'fbm:hoje')));
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage', 'texto', v_texto, 'botoes', v_bot);

  ELSIF p_tipo IN ('comunicado_novo', 'comunicado_lembrete') THEN
    SELECT d.titulo, left(d.conteudo, 2500) AS conteudo, d.pontosporciencia AS pontos INTO r
      FROM public.documentosassinaturas s
      JOIN public.documentos d ON d.documentoid = s.documentoid AND d.contaid = p_contaid AND d.status = 'Publicado'
     WHERE s.assinaturaid = p_referencia AND s.contaid = p_contaid AND s.statusassinatura = 'Pendente';
    IF NOT FOUND THEN
      RETURN NULL;                                   -- já deu ciência ou o comunicado saiu do ar
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage',
      'texto', CASE WHEN p_tipo = 'comunicado_novo' THEN '📢 <b>' ELSE '⏰ Ainda sem a sua ciência: <b>' END
               || public.bot_html(r.titulo) || E'</b>\n\n' || public.bot_html(r.conteudo)
               || CASE WHEN coalesce(r.pontos, 0) > 0 THEN E'\n\n🎁 +' || r.pontos || ' pontos ao confirmar.' ELSE '' END,
      'botoes', jsonb_build_array(jsonb_build_array(
                  jsonb_build_object('text', '✅ Estou ciente', 'callback_data', 'ci:' || p_referencia))));

  ELSIF p_tipo = 'folga_drop' THEN
    SELECT jsonb_agg(jsonb_build_object('atribuicaoid', x.atribuicaoid, 'titulo', x.titulo, 'pontos', x.pontos,
                                        'pessoa', public.nome_curto(x.nomecompleto), 'motivo', x.situacao)
                     ORDER BY x.titulo) INTO v_itens
      FROM (SELECT c.atribuicaoid, t.titulo, c.pontos, f.nomecompleto, c.situacao
              FROM public.lista_candidatos(p_contaid, v_hoje) c
              JOIN public.tarefas t      ON t.tarefaid = c.tarefaid AND t.contaid = p_contaid
              JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = p_contaid
             WHERE c.lojaid = p_referencia AND c.situacao IN ('folga', 'afastamento')
               AND NOT public.passada_hoje(c.atribuicaoid, v_hoje)
               AND NOT public.tem_justificativa(c.atribuicaoid, c.tipofrequencia, v_hoje, false)
               AND NOT EXISTS (SELECT 1 FROM public.entregas e
                                WHERE e.atribuicaoid = c.atribuicaoid AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  AND (c.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = v_hoje))
             LIMIT 10) x;
    IF v_itens IS NULL THEN
      RETURN NULL;
    END IF;
    SELECT string_agg('• <b>' || public.bot_html(e->>'titulo') || '</b> · ' || (e->>'pontos') || ' pts · '
                      || CASE WHEN e->>'motivo' = 'afastamento' THEN '🌴 ' ELSE '🏠 ' END || public.bot_html(e->>'pessoa'), E'\n'),
           jsonb_agg(jsonb_build_array(jsonb_build_object('text', '🚀 Pegar: ' || left(e->>'titulo', 25),
                                                          'callback_data', 'fg:' || (e->>'atribuicaoid'))))
      INTO v_texto, v_bot
      FROM jsonb_array_elements(v_itens) e;
    RETURN jsonb_build_object('metodo', 'sendMessage',
      'texto', E'⚡ <b>Tarefas de quem está de folga hoje</b>\nQuem pegar, faz e ganha os pontos:\n' || v_texto,
      'botoes', v_bot);

  ELSIF p_tipo = 'missao' THEN
    SELECT t.titulo, t.pontos, l.nome AS loja INTO r
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
      JOIN public.lojas l   ON l.lojaid = ta.lojaid AND l.contaid = p_contaid
     WHERE ta.atribuicaoid = p_referencia AND ta.contaid = p_contaid AND ta.datafimvigencia IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.missoesaceites m
                        WHERE m.contaid = p_contaid AND m.atribuicaoid = p_referencia AND m.dia = v_hoje
                          AND m.revogadoem IS NULL);
    IF NOT FOUND THEN
      RETURN NULL;
    END IF;
    RETURN jsonb_build_object('metodo', 'sendMessage',
      'texto', E'🚨 <b>Missão da equipe!</b>\n\n📝 ' || public.bot_html(r.titulo) || E'\n💰 ' || r.pontos
               || E' pontos\n\nO primeiro que aceitar fica com ela hoje.',
      'botoes', jsonb_build_array(jsonb_build_array(
                  jsonb_build_object('text', '🙋 Eu aceito!', 'callback_data', 'ms:' || p_referencia))));

  ELSIF p_tipo = 'resumo_ausencia' THEN
    RETURN public.bot_resumo_ausencia(p_contaid, p_funcionarioid);
  END IF;
  RETURN NULL;
END;
$$;
-- ---------------------------------------------------------------------------
-- 8. PEQUENO: contaid com o padrão da casa
-- ---------------------------------------------------------------------------
ALTER TABLE public.tarefascandidatos ALTER COLUMN contaid SET DEFAULT public.minha_conta();

-- ---------------------------------------------------------------------------
-- 9. Permissões
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fila_da_loja(integer)                   FROM public, anon;
REVOKE ALL ON FUNCTION public.tarefas_nao_pegas(integer)              FROM public, anon;
REVOKE ALL ON FUNCTION public.pegar_tarefa(integer, integer)          FROM public, anon;
REVOKE ALL ON FUNCTION public.revogar_aceite(integer, date, text)     FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fila_da_loja(integer)                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tarefas_nao_pegas(integer)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.pegar_tarefa(integer, integer)       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revogar_aceite(integer, date, text)  TO authenticated;
REVOKE ALL ON FUNCTION public.visao_pegar(integer, integer, integer, integer)     FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text)
                                                                                  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.visao_pegar(integer, integer, integer, integer)  TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.registrar_entrega(integer, text, text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.registrar_entrega(integer, text, text, boolean) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.bot_texto_rotina(text, integer, integer, integer) FROM public, anon, authenticated;
