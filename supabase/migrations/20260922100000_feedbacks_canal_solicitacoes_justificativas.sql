-- Etapa 1.7, parte 3 (antiga Fase 7): feedbacks, canal confidencial,
-- solicitacoes internas e justificativas ("nao se aplica").
-- Decisoes do Wisley em 22/09/2026, registradas em docs/PLANO_MIGRACAO.md.

-- ===========================================================================
-- 1. Livro de pontos: estorno de bonus (feedback anulado)
-- ===========================================================================

ALTER TABLE public.movimentospontos DROP CONSTRAINT movimentospontos_tipo_check;
ALTER TABLE public.movimentospontos ADD CONSTRAINT movimentospontos_tipo_check CHECK (tipo IN (
  'aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus',
  'resgate', 'cancelamento_resgate', 'estorno_resgate',
  'ajuste_abertura'));

CREATE OR REPLACE FUNCTION public.aplica_movimento_no_saldo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_linhas integer;
BEGIN
  PERFORM set_config('gamegb.aplicando_movimento', 'sim', true);

  UPDATE public.funcionarios
     SET saldopontos = saldopontos + NEW.pontos,
         pontostotal = coalesce(pontostotal, 0)
                       + CASE WHEN NEW.tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')
                              THEN NEW.pontos ELSE 0 END
   WHERE funcionarioid = NEW.funcionarioid AND contaid = NEW.contaid;
  -- Guardado antes do PERFORM seguinte, que sobrescreveria o FOUND.
  GET DIAGNOSTICS v_linhas = ROW_COUNT;

  PERFORM set_config('gamegb.aplicando_movimento', 'nao', true);

  IF v_linhas = 0 THEN
    RAISE EXCEPTION 'Funcionário do movimento não encontrado.' USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- ===========================================================================
-- 2. Feedback diario: nota 0 a 10, um por pessoa por dia, bonus pelo livro.
--    A nota nao se altera; se foi erro, o gestor anula com motivo e o bonus
--    e estornado (a conquista fica).
-- ===========================================================================

ALTER TABLE public.feedbacks
  ADD COLUMN origem          varchar(10) NOT NULL DEFAULT 'gestor',
  ADD COLUMN registradopor   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN criadoem        timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN pontosbonus     integer NOT NULL DEFAULT 0,
  ADD COLUMN anuladoem       timestamptz,
  ADD COLUMN anuladopor      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN motivoanulacao  text;

ALTER TABLE public.feedbacks ADD CONSTRAINT feedbacks_nota_0_a_10 CHECK (notadia BETWEEN 0 AND 10);
ALTER TABLE public.feedbacks ADD CONSTRAINT feedbacks_origem_valida CHECK (origem IN ('gestor', 'bot'));
ALTER TABLE public.feedbacks ADD CONSTRAINT feedbacks_anulacao_com_motivo CHECK (
  anuladoem IS NULL OR length(btrim(coalesce(motivoanulacao, ''))) > 0);

-- Um por pessoa por dia, sem contar os anulados (anulado por erro libera o
-- dia para o lancamento certo; o bonus do anulado ja foi estornado).
DROP INDEX public.feedbacks_um_por_dia;
CREATE UNIQUE INDEX feedbacks_um_por_dia ON public.feedbacks (funcionarioid, datafeedback) WHERE anuladoem IS NULL;

CREATE OR REPLACE FUNCTION public.protege_feedback()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Feedback não se apaga. Se foi lançado errado, anule com motivo.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.notadia IS DISTINCT FROM OLD.notadia OR NEW.comentario IS DISTINCT FROM OLD.comentario
     OR NEW.datafeedback IS DISTINCT FROM OLD.datafeedback OR NEW.funcionarioid IS DISTINCT FROM OLD.funcionarioid
     OR NEW.contaid IS DISTINCT FROM OLD.contaid OR NEW.pontosbonus IS DISTINCT FROM OLD.pontosbonus
     OR NEW.origem IS DISTINCT FROM OLD.origem OR NEW.criadoem IS DISTINCT FROM OLD.criadoem
     OR (OLD.anuladoem IS NOT NULL AND (NEW.anuladoem IS DISTINCT FROM OLD.anuladoem
                                        OR NEW.motivoanulacao IS DISTINCT FROM OLD.motivoanulacao)) THEN
    RAISE EXCEPTION 'A nota do feedback não se altera. Se foi lançada errado, anule com motivo.' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER feedbacks_protege
  BEFORE UPDATE OR DELETE ON public.feedbacks
  FOR EACH ROW EXECUTE FUNCTION public.protege_feedback();

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.feedbacks FROM anon, authenticated;

-- O bonus do feedback aponta para ele no livro.
ALTER TABLE public.movimentospontos ADD COLUMN feedbackid integer;
ALTER TABLE public.movimentospontos ADD CONSTRAINT movimentospontos_feedback_fk
  FOREIGN KEY (contaid, feedbackid) REFERENCES public.feedbacks (contaid, feedbackid) ON DELETE RESTRICT;

-- Enquanto nao ha bot, o gestor registra (origem 'gestor'). So hoje ou ontem.
CREATE OR REPLACE FUNCTION public.registrar_feedback(
  p_funcionarioid integer,
  p_dia           date,
  p_nota          integer,
  p_comentario    text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.minha_conta_editavel();
  v_hoje   date    := public.dia_em_sao_paulo(now());
  v_func   public.funcionarios%ROWTYPE;
  v_bonus  integer;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT v_func.ativo THEN
    RAISE EXCEPTION 'Esta pessoa está inativa.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia IS NULL OR p_dia NOT IN (v_hoje, v_hoje - 1) THEN
    RAISE EXCEPTION 'O feedback só pode ser de hoje ou de ontem.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 0 AND 10 THEN
    RAISE EXCEPTION 'A nota vai de 0 a 10.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT CASE WHEN valor ~ '^[0-9]+$' THEN valor::integer ELSE 0 END INTO v_bonus
    FROM public.configuracoes WHERE contaid = v_conta AND chave = 'PONTOS_BONUS_FEEDBACK_DIARIO';
  v_bonus := coalesce(v_bonus, 0);

  BEGIN
    INSERT INTO public.feedbacks (contaid, funcionarioid, datafeedback, notadia, comentario, origem, registradopor, pontosbonus)
    VALUES (v_conta, p_funcionarioid, p_dia, p_nota, nullif(btrim(coalesce(p_comentario, '')), ''), 'gestor', auth.uid(), v_bonus)
    RETURNING feedbackid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION '% já tem feedback de %.', v_func.nomecompleto, to_char(p_dia, 'DD/MM/YYYY')
      USING ERRCODE = 'unique_violation';
  END;

  IF v_bonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, p_funcionarioid, 'bonus', v_bonus,
            'Feedback do dia ' || to_char(p_dia, 'DD/MM/YYYY'), v_id, auth.uid());
  END IF;

  PERFORM public.avaliar_conquistas(v_conta, p_funcionarioid);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.anular_feedback(p_feedbackid integer, p_motivo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_fb    public.feedbacks%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_fb FROM public.feedbacks WHERE feedbackid = p_feedbackid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Feedback não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_fb.anuladoem IS NOT NULL THEN
    RAISE EXCEPTION 'Este feedback já foi anulado.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.feedbacks
     SET anuladoem = now(), anuladopor = auth.uid(), motivoanulacao = btrim(p_motivo)
   WHERE feedbackid = p_feedbackid;

  IF v_fb.pontosbonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, v_fb.funcionarioid, 'estorno_bonus', -v_fb.pontosbonus,
            'Feedback do dia ' || to_char(v_fb.datafeedback, 'DD/MM/YYYY') || ' anulado: ' || btrim(p_motivo),
            p_feedbackid, auth.uid());
  END IF;
END;
$$;

-- ===========================================================================
-- 3. Justificativas ("nao se aplica"), nivel loja.
--    Aceita: sai das pendencias, dos pontos possiveis da nota do mes e vira
--    dia neutro na sequencia de dias. Pendente ou recusada: conta normal.
-- ===========================================================================

CREATE TABLE public.justificativas (
  justificativaid integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid         integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  lojaid          integer NOT NULL,
  atribuicaoid    integer NOT NULL,
  funcionarioid   integer NOT NULL,
  dia             date    NOT NULL,
  motivo          text    NOT NULL CHECK (length(btrim(motivo)) > 0),
  status          varchar(10) NOT NULL DEFAULT 'Pendente' CHECK (status IN ('Pendente', 'Aceita', 'Recusada')),
  origem          varchar(10) NOT NULL DEFAULT 'gestor' CHECK (origem IN ('gestor', 'bot')),
  registradopor   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  registradoem    timestamptz NOT NULL DEFAULT now(),
  decididopor     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decididoem      timestamptz,
  motivorecusa    text,
  CONSTRAINT justificativas_conta_unico UNIQUE (contaid, justificativaid),
  CONSTRAINT justificativas_loja_fk FOREIGN KEY (contaid, lojaid)
    REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT,
  CONSTRAINT justificativas_atribuicao_fk FOREIGN KEY (contaid, atribuicaoid)
    REFERENCES public.tarefasatribuidas (contaid, atribuicaoid) ON DELETE RESTRICT,
  CONSTRAINT justificativas_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT justificativas_recusa_com_motivo CHECK (status <> 'Recusada' OR length(btrim(coalesce(motivorecusa, ''))) > 0)
);
-- Uma so por tarefa e dia enquanto vale (pendente ou aceita).
CREATE UNIQUE INDEX justificativas_uma_por_dia ON public.justificativas (atribuicaoid, dia)
  WHERE status IN ('Pendente', 'Aceita');
CREATE INDEX justificativas_contaid_idx ON public.justificativas (contaid, status);
CREATE INDEX justificativas_funcionario_idx ON public.justificativas (funcionarioid, dia);

ALTER TABLE public.justificativas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.justificativas FROM anon, authenticated;
GRANT SELECT ON public.justificativas TO authenticated;
GRANT ALL ON public.justificativas TO service_role;
CREATE POLICY justificativas_sel ON public.justificativas FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

CREATE OR REPLACE FUNCTION public.protege_justificativa()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Justificativa não se apaga.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF OLD.status <> 'Pendente'
     OR NEW.atribuicaoid IS DISTINCT FROM OLD.atribuicaoid OR NEW.dia IS DISTINCT FROM OLD.dia
     OR NEW.motivo IS DISTINCT FROM OLD.motivo OR NEW.funcionarioid IS DISTINCT FROM OLD.funcionarioid
     OR NEW.lojaid IS DISTINCT FROM OLD.lojaid OR NEW.contaid IS DISTINCT FROM OLD.contaid THEN
    RAISE EXCEPTION 'Justificativa decidida não muda.' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER justificativas_protege
  BEFORE UPDATE OR DELETE ON public.justificativas
  FOR EACH ROW EXECUTE FUNCTION public.protege_justificativa();

-- A tarefa esta justificada naquele dia? Unica vale para qualquer dia.
-- p_so_aceita = true: so as aceitas (nota, pendencias, sequencia).
-- p_so_aceita = false: pendentes tambem (o que ainda pode ser entregue).
CREATE OR REPLACE FUNCTION public.tem_justificativa(p_atribuicaoid integer, p_tipo varchar, p_dia date, p_so_aceita boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.justificativas j
     WHERE j.atribuicaoid = p_atribuicaoid
       AND (p_tipo = 'Unica' OR j.dia = p_dia)
       AND (j.status = 'Aceita' OR (NOT p_so_aceita AND j.status = 'Pendente')))
$$;

-- Quem ja justificou nao entrega a mesma tarefa naquele dia.
CREATE OR REPLACE FUNCTION public.entrega_nao_justificada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_tipo varchar;
BEGIN
  IF NEW.atribuicaoid IS NOT NULL THEN
    SELECT tipofrequencia INTO v_tipo FROM public.tarefasatribuidas WHERE atribuicaoid = NEW.atribuicaoid;
    IF public.tem_justificativa(NEW.atribuicaoid, v_tipo, public.dia_em_sao_paulo(coalesce(NEW.dataenvio, now())), false) THEN
      RAISE EXCEPTION 'Esta tarefa foi justificada como "não se aplica" neste dia.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER entregas_nao_justificada
  BEFORE INSERT ON public.entregas
  FOR EACH ROW EXECUTE FUNCTION public.entrega_nao_justificada();

-- O que pode ser justificado: tarefas que caiam naquele dia de trabalho da
-- pessoa e nao foram entregues nem justificadas. Unica: so no dia marcado.
CREATE OR REPLACE FUNCTION public.justificaveis(p_funcionarioid integer, p_dia date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH itens AS (
    SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome AS loja
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid
     WHERE ta.funcionarioid = p_funcionarioid
       AND p_dia <= public.dia_em_sao_paulo(now())
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, p_dia)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, p_dia, false)
       AND (
         (ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
          AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, p_dia)
          AND p_dia >= coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), p_dia)
          AND p_dia >= coalesce(ta.datainiciovigencia, p_dia)
          AND (ta.datafimvigencia IS NULL OR p_dia < ta.datafimvigencia)
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                             AND public.dia_em_sao_paulo(e.dataenvio) = p_dia))
         OR
         (ta.tipofrequencia = 'Unica'
          AND ta.datafimvigencia IS NULL
          AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) = p_dia
          AND NOT EXISTS (SELECT 1 FROM public.entregas e
                           WHERE e.atribuicaoid = ta.atribuicaoid
                             AND e.statusvalidacao IN ('Pendente', 'Aprovada')))
       )
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('atribuicaoid', atribuicaoid, 'titulo', titulo,
                                               'pontos', pontos, 'loja', loja) ORDER BY titulo), '[]'::jsonb)
    FROM itens
$$;

CREATE OR REPLACE FUNCTION public.registrar_justificativa(
  p_atribuicaoid integer,
  p_dia          date,
  p_motivo       text,
  p_aceitar      boolean
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_aceitar IS NULL THEN
    RAISE EXCEPTION 'Escolha se já aceita ou se fica para decidir.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_atr FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND funcionarioid IS NOT NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa atribuída não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.justificaveis(v_atr.funcionarioid, p_dia)) x
                  WHERE (x->>'atribuicaoid')::integer = p_atribuicaoid) THEN
    RAISE EXCEPTION 'Nesse dia a tarefa não caía para a pessoa, ou já foi entregue ou justificada, ou era folga.'
      USING ERRCODE = 'check_violation';
  END IF;

  BEGIN
    INSERT INTO public.justificativas (contaid, lojaid, atribuicaoid, funcionarioid, dia, motivo, status,
                                       origem, registradopor, decididopor, decididoem)
    VALUES (v_conta, v_atr.lojaid, p_atribuicaoid, v_atr.funcionarioid, p_dia, btrim(p_motivo),
            CASE WHEN p_aceitar THEN 'Aceita' ELSE 'Pendente' END,
            'gestor', auth.uid(),
            CASE WHEN p_aceitar THEN auth.uid() END,
            CASE WHEN p_aceitar THEN now() END)
    RETURNING justificativaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Esta tarefa já tem justificativa neste dia.' USING ERRCODE = 'unique_violation';
  END;

  IF p_aceitar THEN
    PERFORM public.avaliar_conquistas(v_conta, v_atr.funcionarioid);
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decidir_justificativa(p_justificativaid integer, p_aceitar boolean, p_motivo text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_j     public.justificativas%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_j FROM public.justificativas
   WHERE justificativaid = p_justificativaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Justificativa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_j.status <> 'Pendente' THEN
    RAISE EXCEPTION 'Esta justificativa já foi decidida.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_aceitar IS NULL THEN
    RAISE EXCEPTION 'Escolha aceitar ou recusar.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT p_aceitar AND length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Para recusar, informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.justificativas
     SET status = CASE WHEN p_aceitar THEN 'Aceita' ELSE 'Recusada' END,
         decididopor = auth.uid(), decididoem = now(),
         motivorecusa = CASE WHEN p_aceitar THEN NULL ELSE btrim(p_motivo) END
   WHERE justificativaid = p_justificativaid;

  IF p_aceitar THEN
    PERFORM public.avaliar_conquistas(v_conta, v_j.funcionarioid);
  END IF;
END;
$$;

-- ===========================================================================
-- 4. Conquistas: sequencia de feedback passa a valer; justificativa aceita e
--    dia neutro na sequencia de tarefas (como a folga: nao quebra nem soma).
-- ===========================================================================

-- Maior sequencia de dias feitos. Dia fora do trabalho (folga, domingo de
-- folga, afastamento) ou marcado como neutro nao quebra nem conta; se foi
-- feito mesmo assim, conta. Dia de trabalho sem nada quebra.
CREATE OR REPLACE FUNCTION public.maior_sequencia(
  p_feitos        date[],
  p_neutros       date[],
  p_diadefolga    integer,
  p_domingofolga  integer,
  p_inicioafast   date,
  p_fimafast      date
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  WITH calendario AS (
    SELECT g::date AS d
      FROM (SELECT min(x) AS ini, max(x) AS fim FROM unnest(p_feitos) x) lim,
           generate_series(lim.ini, lim.fim, interval '1 day') g
  ),
  considerados AS (
    SELECT d, d = ANY(p_feitos) AS fez
      FROM calendario
     WHERE d = ANY(p_feitos)
        OR (public.dia_de_trabalho(p_diadefolga, p_domingofolga, p_inicioafast, p_fimafast, d)
            AND NOT d = ANY(coalesce(p_neutros, '{}'::date[])))
  ),
  numerados AS (
    SELECT d, fez, row_number() OVER (ORDER BY d) AS rn FROM considerados
  ),
  ilhas AS (
    SELECT rn - row_number() OVER (ORDER BY d) AS grupo FROM numerados WHERE fez
  )
  SELECT coalesce(max(qtd), 0)::integer
    FROM (SELECT count(*) AS qtd FROM ilhas GROUP BY grupo) x
$$;

CREATE OR REPLACE FUNCTION public.criterio_disponivel(p_tipo text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT p_tipo IN ('total_tarefas_aprovadas', 'tarefas_aprovadas_periodo', 'sequencia_dias_tarefas',
                    'sequencia_feedback_diario')
$$;

CREATE OR REPLACE FUNCTION public.pessoa_cumpre_conquista(p_contaid integer, p_funcionarioid integer, p_conquistaid integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c       public.conquistas%ROWTYPE;
  f       public.funcionarios%ROWTYPE;
  v_desde timestamptz;
  n       integer;
BEGIN
  SELECT * INTO c FROM public.conquistas WHERE conquistaid = p_conquistaid AND contaid = p_contaid;
  IF NOT FOUND OR NOT c.ativa OR NOT public.criterio_disponivel(c.criteriotipo) THEN
    RETURN false;
  END IF;
  SELECT * INTO f FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = p_contaid;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  v_desde := coalesce(c.contardesde, '-infinity'::timestamptz);

  IF c.criteriotipo = 'total_tarefas_aprovadas' THEN
    SELECT count(*) INTO n
      FROM public.entregas
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
       AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
       AND dataenvio >= v_desde;
    RETURN n >= c.criteriovalor;

  ELSIF c.criteriotipo = 'tarefas_aprovadas_periodo' THEN
    -- Alguma janela de X dias seguidos com pelo menos N tarefas.
    RETURN EXISTS (
      WITH dias AS (
        SELECT public.dia_em_sao_paulo(dataenvio) AS d
          FROM public.entregas
         WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
           AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
           AND dataenvio >= v_desde
      )
      SELECT 1
        FROM (SELECT DISTINCT d FROM dias) inicio
       WHERE (SELECT count(*) FROM dias x
               WHERE x.d BETWEEN inicio.d AND inicio.d + c.criteriodias - 1) >= c.criteriovalor
    );

  ELSIF c.criteriotipo = 'sequencia_dias_tarefas' THEN
    -- Folga, domingo de folga, afastamento e justificativa aceita sao dias
    -- neutros: nao quebram nem somam.
    n := public.maior_sequencia(
           ARRAY(SELECT DISTINCT public.dia_em_sao_paulo(dataenvio)
                   FROM public.entregas
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                    AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
                    AND dataenvio >= v_desde),
           ARRAY(SELECT DISTINCT dia FROM public.justificativas
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND status = 'Aceita'),
           f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento);
    RETURN n >= c.criteriovalor;

  ELSIF c.criteriotipo = 'sequencia_feedback_diario' THEN
    -- Dias seguidos com feedback (anulado nao conta). Folga, domingo de folga
    -- e afastamento sao neutros.
    n := public.maior_sequencia(
           ARRAY(SELECT DISTINCT datafeedback FROM public.feedbacks
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                    AND anuladoem IS NULL AND criadoem >= v_desde),
           NULL,
           f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento);
    RETURN n >= c.criteriovalor;
  END IF;

  RETURN false;
END;
$$;

-- ===========================================================================
-- 5. Canal confidencial (denunciasanonimas): anonimato real.
--    - Nenhuma coluna aponta para quem enviou; guarda so o DIA (sem hora);
--    - protocolo aleatorio: o banco guarda so a impressao digital (sha256);
--    - sem loja (numa loja pequena, a loja ja entrega quem foi);
--    - so o master da conta le; ninguem grava pelo navegador. A entrada e so
--      pelo servidor (bot, Etapa 1.13), sem identificar quem envia.
-- ===========================================================================

ALTER TABLE public.denunciasanonimas ALTER COLUMN dataregistro DROP DEFAULT;
ALTER TABLE public.denunciasanonimas
  ALTER COLUMN dataregistro TYPE date USING (dataregistro AT TIME ZONE 'America/Sao_Paulo')::date;
ALTER TABLE public.denunciasanonimas ALTER COLUMN dataregistro SET DEFAULT public.dia_em_sao_paulo(now());
ALTER TABLE public.denunciasanonimas ALTER COLUMN dataregistro SET NOT NULL;

UPDATE public.denunciasanonimas SET status = 'Nova' WHERE status = 'Pendente' OR status IS NULL;
ALTER TABLE public.denunciasanonimas ALTER COLUMN status SET DEFAULT 'Nova';
ALTER TABLE public.denunciasanonimas ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.denunciasanonimas ADD CONSTRAINT denunciasanonimas_status_valido
  CHECK (status IN ('Nova', 'Em análise', 'Tratada'));
ALTER TABLE public.denunciasanonimas ADD CONSTRAINT denunciasanonimas_mensagem_tamanho
  CHECK (length(btrim(mensagem)) BETWEEN 1 AND 4000);

ALTER TABLE public.denunciasanonimas
  ADD COLUMN protocolohash char(64),
  ADD COLUMN resposta      text,
  ADD COLUMN respondidoem  date,
  ADD COLUMN tratadopor    uuid,
  ADD COLUMN tratadoem     timestamptz;
CREATE UNIQUE INDEX denunciasanonimas_protocolo ON public.denunciasanonimas (protocolohash);

-- Quem le: so o master. Nenhum papel futuro (gerente, lider) tera acesso.
CREATE OR REPLACE FUNCTION public.sou_master()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.contasusuarios WHERE userid = auth.uid() AND papel = 'master')
$$;

DROP POLICY IF EXISTS denunciasanonimas_sel ON public.denunciasanonimas;
DROP POLICY IF EXISTS denunciasanonimas_ins ON public.denunciasanonimas;
DROP POLICY IF EXISTS denunciasanonimas_upd ON public.denunciasanonimas;
DROP POLICY IF EXISTS denunciasanonimas_del ON public.denunciasanonimas;
REVOKE ALL ON public.denunciasanonimas FROM anon, authenticated;
GRANT SELECT ON public.denunciasanonimas TO authenticated;
GRANT ALL ON public.denunciasanonimas TO service_role;
CREATE POLICY denunciasanonimas_master_le ON public.denunciasanonimas FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()) AND (select public.sou_master()));

-- O texto, o dia e o protocolo nunca mudam; nada se apaga.
CREATE OR REPLACE FUNCTION public.protege_relato()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Relato do canal confidencial não se apaga.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.mensagem IS DISTINCT FROM OLD.mensagem OR NEW.dataregistro IS DISTINCT FROM OLD.dataregistro
     OR NEW.protocolohash IS DISTINCT FROM OLD.protocolohash OR NEW.contaid IS DISTINCT FROM OLD.contaid THEN
    RAISE EXCEPTION 'O relato não se altera.' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER denunciasanonimas_protege
  BEFORE UPDATE OR DELETE ON public.denunciasanonimas
  FOR EACH ROW EXECUTE FUNCTION public.protege_relato();

-- Entrada: SO o servidor (bot). Nao recebe nada de quem envia; devolve o
-- protocolo uma unica vez. Nao escreve em log. Interna (recebe contaid).
CREATE OR REPLACE FUNCTION public.registrar_relato(p_contaid integer, p_mensagem text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ023456789';
  v_bytes    bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  v_codigo   text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.contas WHERE contaid = p_contaid AND status = 'ativa') THEN
    RAISE EXCEPTION 'Conta indisponível.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  FOR i IN 0..11 LOOP
    v_codigo := v_codigo || substr(v_alfabeto, (get_byte(v_bytes, i) % 32) + 1, 1);
    IF i IN (3, 7) THEN v_codigo := v_codigo || '-'; END IF;
  END LOOP;

  INSERT INTO public.denunciasanonimas (contaid, mensagem, protocolohash)
  VALUES (p_contaid, btrim(p_mensagem), encode(sha256(convert_to(v_codigo, 'UTF8')), 'hex'));
  RETURN v_codigo;
END;
$$;

-- Consulta pelo protocolo (quem enviou acompanha a resposta sem se
-- identificar). So o servidor. Interna.
CREATE OR REPLACE FUNCTION public.consultar_relato(p_contaid integer, p_protocolo text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('status', status, 'resposta', resposta, 'respondidoem', respondidoem)
    FROM public.denunciasanonimas
   WHERE contaid = p_contaid
     AND protocolohash = encode(sha256(convert_to(upper(btrim(p_protocolo)), 'UTF8')), 'hex')
$$;

-- O master trata e responde.
CREATE OR REPLACE FUNCTION public.tratar_relato(p_denunciaid integer, p_status text, p_resposta text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_atual public.denunciasanonimas%ROWTYPE;
  v_resp  text := nullif(btrim(coalesce(p_resposta, '')), '');
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta acessa o canal confidencial.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_status NOT IN ('Em análise', 'Tratada') THEN
    RAISE EXCEPTION 'Situação inválida.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_atual FROM public.denunciasanonimas
   WHERE denunciaid = p_denunciaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relato não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.denunciasanonimas
     SET status       = p_status,
         resposta     = coalesce(v_resp, resposta),
         respondidoem = CASE WHEN v_resp IS NOT NULL AND v_resp IS DISTINCT FROM resposta
                             THEN public.dia_em_sao_paulo(now()) ELSE respondidoem END,
         tratadopor   = auth.uid(),
         tratadoem    = now()
   WHERE denunciaid = p_denunciaid;
END;
$$;

-- ===========================================================================
-- 6. Solicitacoes internas (compras e manutencao), nivel loja.
--    Aberta -> Em andamento -> Concluida; Aberta/Em andamento -> Recusada
--    (com motivo). Cada mudanca fica no historico, que nunca muda.
-- ===========================================================================

UPDATE public.solicitacoesinternas SET status = 'Aberta' WHERE status = 'Pendente' OR status IS NULL;
UPDATE public.solicitacoesinternas SET status = 'Concluída' WHERE status = 'Aprovado';
UPDATE public.solicitacoesinternas SET status = 'Recusada', motivorecusa = coalesce(nullif(motivorecusa, ''), 'Recusada')
 WHERE status = 'Recusado';
ALTER TABLE public.solicitacoesinternas ALTER COLUMN status SET DEFAULT 'Aberta';
ALTER TABLE public.solicitacoesinternas ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.solicitacoesinternas ALTER COLUMN datasolicitacao SET NOT NULL;
ALTER TABLE public.solicitacoesinternas
  ADD COLUMN unidade       varchar(20),
  ADD COLUMN registradopor uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN atualizadoem  timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_status_valido
  CHECK (status IN ('Aberta', 'Em andamento', 'Concluída', 'Recusada'));
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_tipo_valido
  CHECK (tipo IN ('Compra', 'Manutencao'));
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_recusa_com_motivo
  CHECK (status <> 'Recusada' OR length(btrim(coalesce(motivorecusa, ''))) > 0);
ALTER TABLE public.solicitacoesinternas ADD CONSTRAINT solicitacoesinternas_quantidade_positiva
  CHECK (quantidade IS NULL OR quantidade > 0);

CREATE TABLE public.solicitacoeshistorico (
  historicoid     integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid         integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  lojaid          integer NOT NULL,
  solicitacaoid   integer NOT NULL,
  statusanterior  varchar(20),
  statusnovo      varchar(20) NOT NULL,
  observacao      text,
  alteradopor     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  alteradoem      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT solicitacoeshistorico_loja_fk FOREIGN KEY (contaid, lojaid)
    REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT,
  CONSTRAINT solicitacoeshistorico_solicitacao_fk FOREIGN KEY (contaid, solicitacaoid)
    REFERENCES public.solicitacoesinternas (contaid, solicitacaoid) ON DELETE RESTRICT
);
CREATE INDEX solicitacoeshistorico_solicitacao_idx ON public.solicitacoeshistorico (solicitacaoid, alteradoem);

ALTER TABLE public.solicitacoeshistorico ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.solicitacoeshistorico FROM anon, authenticated;
GRANT SELECT ON public.solicitacoeshistorico TO authenticated;
GRANT ALL ON public.solicitacoeshistorico TO service_role;
CREATE POLICY solicitacoeshistorico_sel ON public.solicitacoeshistorico FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

CREATE OR REPLACE FUNCTION public.historico_imutavel()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'O histórico não se altera nem se apaga.' USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER solicitacoeshistorico_imutavel
  BEFORE UPDATE OR DELETE ON public.solicitacoeshistorico
  FOR EACH ROW EXECUTE FUNCTION public.historico_imutavel();

-- Transicoes permitidas e campos que nao mudam, para qualquer caminho.
CREATE OR REPLACE FUNCTION public.valida_solicitacao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Solicitação não se apaga; recuse com motivo.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'Aberta' THEN
      RAISE EXCEPTION 'Solicitação nasce aberta.' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.tipo IS DISTINCT FROM OLD.tipo OR NEW.descricao IS DISTINCT FROM OLD.descricao
     OR NEW.funcionarioid IS DISTINCT FROM OLD.funcionarioid OR NEW.lojaid IS DISTINCT FROM OLD.lojaid
     OR NEW.contaid IS DISTINCT FROM OLD.contaid OR NEW.datasolicitacao IS DISTINCT FROM OLD.datasolicitacao
     OR NEW.categoria IS DISTINCT FROM OLD.categoria OR NEW.quantidade IS DISTINCT FROM OLD.quantidade
     OR NEW.unidade IS DISTINCT FROM OLD.unidade THEN
    RAISE EXCEPTION 'O pedido não se altera; só a situação.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status = 'Aberta'       AND NEW.status IN ('Em andamento', 'Concluída', 'Recusada'))
    OR (OLD.status = 'Em andamento' AND NEW.status IN ('Concluída', 'Recusada'))) THEN
    RAISE EXCEPTION 'Não é possível passar de "%" para "%".', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IN ('Concluída', 'Recusada') AND NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.dataconclusao := now();
  END IF;
  NEW.atualizadoem := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER solicitacoesinternas_valida
  BEFORE INSERT OR UPDATE OR DELETE ON public.solicitacoesinternas
  FOR EACH ROW EXECUTE FUNCTION public.valida_solicitacao();

-- Quem mudou e quando: gravado por gatilho, em toda abertura e mudanca.
CREATE OR REPLACE FUNCTION public.registra_mudanca_solicitacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.solicitacoeshistorico (contaid, lojaid, solicitacaoid, statusanterior, statusnovo, observacao, alteradopor)
    VALUES (NEW.contaid, NEW.lojaid, NEW.solicitacaoid,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END, NEW.status,
            nullif(current_setting('gamegb.observacao', true), ''), auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER solicitacoesinternas_historico
  AFTER INSERT OR UPDATE ON public.solicitacoesinternas
  FOR EACH ROW EXECUTE FUNCTION public.registra_mudanca_solicitacao();

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.solicitacoesinternas FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.abrir_solicitacao(
  p_lojaid        integer,
  p_funcionarioid integer,
  p_tipo          text,
  p_categoria     text,
  p_descricao     text,
  p_quantidade    numeric DEFAULT NULL,
  p_unidade       text    DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarioslojas
                  WHERE funcionarioid = p_funcionarioid AND lojaid = p_lojaid AND contaid = v_conta AND ativo) THEN
    RAISE EXCEPTION 'Quem pediu precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_descricao, ''))) = 0 THEN
    RAISE EXCEPTION 'Descreva o pedido.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_tipo NOT IN ('Compra', 'Manutencao') THEN
    RAISE EXCEPTION 'Tipo inválido.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM set_config('gamegb.observacao', '', true);
  INSERT INTO public.solicitacoesinternas (contaid, lojaid, funcionarioid, tipo, categoria, descricao,
                                           quantidade, unidade, registradopor)
  VALUES (v_conta, p_lojaid, p_funcionarioid, p_tipo, nullif(btrim(coalesce(p_categoria, '')), ''),
          btrim(p_descricao), CASE WHEN p_tipo = 'Compra' THEN p_quantidade END,
          CASE WHEN p_tipo = 'Compra' THEN nullif(btrim(coalesce(p_unidade, '')), '') END, auth.uid())
  RETURNING solicitacaoid INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mudar_situacao_solicitacao(p_solicitacaoid integer, p_status text, p_observacao text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_obs   text := nullif(btrim(coalesce(p_observacao, '')), '');
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_status = 'Recusada' AND v_obs IS NULL THEN
    RAISE EXCEPTION 'Para recusar, informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM 1 FROM public.solicitacoesinternas WHERE solicitacaoid = p_solicitacaoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitação não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM set_config('gamegb.observacao', coalesce(v_obs, ''), true);
  UPDATE public.solicitacoesinternas
     SET status = p_status,
         motivorecusa = CASE WHEN p_status = 'Recusada' THEN v_obs ELSE motivorecusa END
   WHERE solicitacaoid = p_solicitacaoid;
  PERFORM set_config('gamegb.observacao', '', true);
END;
$$;

-- ===========================================================================
-- 7. Relatorios: pendencias sem as aceitas (com a situacao da justificativa)
--    e a analise por tarefa com a coluna "nao se aplica".
-- ===========================================================================

DROP FUNCTION public.pendencias_da_pessoa(integer, date, date);
CREATE FUNCTION public.pendencias_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.dia_em_sao_paulo(now()) - 1) AS fim
  ),
  itens AS (
    SELECT g.d::date AS dia, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome AS loja
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_em_sao_paulo(e.dataenvio) = g.d::date)
    UNION ALL
    SELECT public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN lim.ini AND lim.fim
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
$$;

CREATE OR REPLACE FUNCTION public.analise_de_tarefas(p_de date, p_ate date, p_lojaid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM public.entregas e
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM public.justificativas j
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR j.lojaid = p_lojaid)
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo), '[]'::jsonb)
    FROM juntos j
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid
$$;

-- ===========================================================================
-- 8. O que ja existia passa a respeitar a justificativa: o painel da loja e
--    a lista do que entregar hoje escondem a tarefa justificada; a nota do
--    mes tira a aceita dos pontos possiveis. (Copias das versoes anteriores
--    com uma linha a mais cada.)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.montar_painel(p_contaid integer, p_lojaid integer, p_tv boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje       date := public.dia_em_sao_paulo(now());
  v_loja       text;
  v_dia        jsonb;
  v_validacao  jsonb;
  v_pendentes  integer;
  v_podio      jsonb;
  v_atividade  jsonb;
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
            AND public.dia_em_sao_paulo(ta.dataagendamento) < v_hoje) AS atrasada,
           (SELECT e.statusvalidacao
              FROM public.entregas e
             WHERE e.atribuicaoid = ta.atribuicaoid
               AND e.statusvalidacao IN ('Pendente', 'Aprovada')
               AND public.dia_em_sao_paulo(e.dataenvio) = v_hoje
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
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje)
       -- Justificada como "nao se aplica" (pendente ou aceita) nao e tarefa de hoje.
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
       -- Unica entregue num dia anterior ja nao e tarefa de hoje.
       AND NOT (ta.tipofrequencia = 'Unica' AND EXISTS (
             SELECT 1 FROM public.entregas e2
              WHERE e2.atribuicaoid = ta.atribuicaoid
                AND e2.statusvalidacao IN ('Pendente', 'Aprovada')
                AND public.dia_em_sao_paulo(e2.dataenvio) < v_hoje))
  )
  SELECT jsonb_build_object(
           'total',       count(*),
           'aprovadas',   count(*) FILTER (WHERE situacao = 'Aprovada'),
           'emvalidacao', count(*) FILTER (WHERE situacao = 'Pendente'),
           'parafazer',   coalesce(
                            jsonb_agg(
                              jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                                 'pontos', pontos, 'atrasada', atrasada)
                              ORDER BY atrasada DESC, pessoa, titulo
                            ) FILTER (WHERE situacao IS NULL),
                            '[]'::jsonb))
    INTO v_dia
    FROM dia;

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
             public.dia_em_sao_paulo(e.dataenvio) = v_hoje AS dehoje
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio
       LIMIT 50
    ) s;

  -- Podio do dia: pontos aprovados hoje na loja.
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
         AND public.dia_em_sao_paulo(e.dataaprovacao) = v_hoje
       GROUP BY f.funcionarioid, f.nomecompleto
       ORDER BY sum(e.pontosganhos) DESC, f.nomecompleto
       LIMIT 3
    ) s;

  -- Atividade recente: as ultimas aprovacoes do dia.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pontos', pontos, 'aprovadaem', dataaprovacao)
                            ORDER BY dataaprovacao DESC), '[]'::jsonb)
    INTO v_atividade
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataaprovacao,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_em_sao_paulo(e.dataaprovacao) = v_hoje
       ORDER BY e.dataaprovacao DESC
       LIMIT 10
    ) s;

  RETURN jsonb_build_object(
    'loja',         v_loja,
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'progresso',    jsonb_build_object('total',       v_dia->'total',
                                       'aprovadas',   v_dia->'aprovadas',
                                       'emvalidacao', v_dia->'emvalidacao'),
    'parafazer',    v_dia->'parafazer',
    'emvalidacao',  v_validacao,
    'pendentes',    v_pendentes,
    'podio',        v_podio,
    'atividade',    v_atividade
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar(p_lojaid integer)
RETURNS TABLE (
  atribuicaoid    integer,
  titulo          varchar,
  pontos          integer,
  funcionarioid   integer,
  nomecompleto    varchar,
  tipofrequencia  varchar,
  atrasada        boolean
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < hoje.dia) AS atrasada
  FROM public.tarefasatribuidas ta
  CROSS JOIN hoje
  JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
  JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
  WHERE ta.lojaid = p_lojaid
    AND ta.datafimvigencia IS NULL
    AND ta.funcionarioid IS NOT NULL
    AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, hoje.dia)
    AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, hoje.dia, false)
    AND NOT EXISTS (
      SELECT 1 FROM public.entregas e
      WHERE e.atribuicaoid = ta.atribuicaoid
        AND e.statusvalidacao IN ('Pendente', 'Aprovada')
        AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)
    )
  ORDER BY f.nomecompleto, t.titulo
$$;

CREATE OR REPLACE FUNCTION public.ranking_mensal(p_ano integer, p_mes integer, p_lojaid integer DEFAULT NULL)
RETURNS TABLE (
  funcionarioid   integer,
  nomecompleto    varchar,
  pontosganhos    integer,
  pontosregulares integer,
  pontospossiveis integer,
  confiabilidade  numeric,
  esforco         numeric,
  nota            numeric
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH janela AS (
    SELECT make_date(p_ano, p_mes, 1) AS ini,
           least((make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date,
                 public.dia_em_sao_paulo(now()) - 1) AS fim
  ),
  recorrentes AS (
    SELECT ta.funcionarioid AS fid, sum(t.pontos)::integer AS pts
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      CROSS JOIN janela j
      CROSS JOIN LATERAL generate_series(
        greatest(j.ini,
                 coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), j.ini),
                 coalesce(ta.datainiciovigencia, j.ini)),
        least(j.fim, coalesce(ta.datafimvigencia - 1, j.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid IS NOT NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       -- Justificativa aceita: o dia nao conta nos possiveis.
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, g.d::date, true)
     GROUP BY ta.funcionarioid
  ),
  unicas AS (
    SELECT ta.funcionarioid AS fid, sum(t.pontos)::integer AS pts
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
      CROSS JOIN janela j
     WHERE ta.funcionarioid IS NOT NULL
       AND ta.tipofrequencia = 'Unica'
       AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN j.ini AND j.fim
       AND (ta.datafimvigencia IS NULL
            OR ta.datafimvigencia > public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)))
       AND NOT public.tem_justificativa(ta.atribuicaoid, 'Unica', NULL, true)
     GROUP BY ta.funcionarioid
  ),
  regulares AS (
    SELECT e.funcionarioid AS fid, sum(e.pontosganhos)::integer AS pts
      FROM public.entregas e
      CROSS JOIN janela j
     WHERE e.statusvalidacao = 'Aprovada'
       AND e.atribuicaoid IS NOT NULL
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN j.ini AND j.fim
     GROUP BY e.funcionarioid
  ),
  ganhos AS (
    SELECT e.funcionarioid AS fid, sum(e.pontosganhos)::integer AS pts
      FROM public.entregas e
      CROSS JOIN janela j
     WHERE e.statusvalidacao = 'Aprovada'
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
       AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN j.ini AND j.fim
     GROUP BY e.funcionarioid
  ),
  pessoas AS (
    SELECT fid FROM recorrentes UNION SELECT fid FROM unicas
    UNION SELECT fid FROM regulares UNION SELECT fid FROM ganhos
  ),
  base AS (
    SELECT p.fid,
           f.nomecompleto AS nome,
           coalesce(g.pts, 0)                      AS ganhos,
           coalesce(r.pts, 0)                      AS regulares,
           coalesce(rc.pts, 0) + coalesce(u.pts, 0) AS possiveis
      FROM pessoas p
      JOIN public.funcionarios f ON f.funcionarioid = p.fid
      LEFT JOIN ganhos g       ON g.fid = p.fid
      LEFT JOIN regulares r    ON r.fid = p.fid
      LEFT JOIN recorrentes rc ON rc.fid = p.fid
      LEFT JOIN unicas u       ON u.fid = p.fid
  ),
  calc AS (
    SELECT b.*,
           CASE WHEN b.possiveis > 0 THEN least(100, round(b.regulares * 100.0 / b.possiveis, 2)) ELSE 0 END AS conf,
           CASE WHEN max(b.ganhos) OVER () > 0 THEN round(b.ganhos * 100.0 / max(b.ganhos) OVER (), 2) ELSE 0 END AS esf
      FROM base b
  )
  SELECT c.fid, c.nome, c.ganhos, c.regulares, c.possiveis, c.conf, c.esf,
         round(c.conf * 0.5 + c.esf * 0.5, 2)
    FROM calc c
   ORDER BY 8 DESC, 3 DESC, 2
$$;

-- ===========================================================================
-- 9. Permissoes (negadas por padrao).
-- ===========================================================================

-- Internas: registrar_relato e consultar_relato recebem contaid e so o
-- servidor (bot) chama.
REVOKE EXECUTE ON FUNCTION
  public.registrar_relato(integer, text),
  public.consultar_relato(integer, text),
  public.pessoa_cumpre_conquista(integer, integer, integer),
  public.montar_painel(integer, integer, boolean)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.registrar_feedback(integer, date, integer, text),
  public.anular_feedback(integer, text),
  public.tem_justificativa(integer, varchar, date, boolean),
  public.justificaveis(integer, date),
  public.registrar_justificativa(integer, date, text, boolean),
  public.decidir_justificativa(integer, boolean, text),
  public.maior_sequencia(date[], date[], integer, integer, date, date),
  public.criterio_disponivel(text),
  public.sou_master(),
  public.tratar_relato(integer, text, text),
  public.abrir_solicitacao(integer, integer, text, text, text, numeric, text),
  public.mudar_situacao_solicitacao(integer, text, text),
  public.pendencias_da_pessoa(integer, date, date),
  public.analise_de_tarefas(date, date, integer),
  public.atribuicoes_para_entregar(integer),
  public.ranking_mensal(integer, integer, integer)
TO authenticated;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;
