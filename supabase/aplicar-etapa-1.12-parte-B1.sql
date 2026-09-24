-- =========================================================================
-- STGame — Etapa 1.12, parte B1: tarefa compartilhada, pegar, revogar, o
-- tablet do balcão e o Ranking lendo o fechamento.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado (roda tudo junto ou nada): me mande a mensagem.
-- Pode rodar duas vezes sem problema: tudo aqui confere antes de criar.
--
-- ATENÇÃO: aplique a parte A antes desta (supabase/aplicar-etapa-1.12-parte-A.sql).
--
-- Este arquivo é a junção destas migrações, na ordem:
--   20260928100000_tarefa_compartilhada_e_aceite.sql
--   20260928100100_visao_do_tablet.sql
--   20260928100200_consertos_revisao_b1.sql
--   20260928100300_ranking_le_o_fechamento.sql
-- =========================================================================

BEGIN;

-- =========================================================================
-- 20260928100000_tarefa_compartilhada_e_aceite.sql
-- =========================================================================

-- Etapa 1.12, parte B1a — tarefa compartilhada e o registro de "pegar".
--
-- Regra definida pelo Wisley em 24/09/2026:
--  * Atribuída a UMA pessoa: só ela pega; não pegar continua pesando na nota
--    dela, como sempre foi (decisão de 24/09/2026).
--  * Atribuída a VÁRIAS: a tarefa é UMA só. Qualquer uma das atribuídas pode
--    pegar, e a primeira que digitar o PIN fica com ela. Some da lista das
--    outras. Quem não pegou fica neutro na nota.
--  * Missão da equipe: aberta a qualquer pessoa da loja que trabalha hoje.
--  * Quem pega ASSUME: a tarefa passa a pesar nos pontos possíveis dela
--    (antes a missão era bônus sem risco).
--  * Tarefa que ninguém pegou não entra na nota de ninguém, mas aparece para
--    o gestor (cartão no Início e lista no Quadro).
--  * O gestor pode revogar o aceite, com motivo, e a tarefa volta a ficar
--    disponível. Se já houver entrega, recusa a entrega primeiro.
--
-- Nada do que já está cadastrado muda: toda atribuição de hoje tem um dono.

-- ---------------------------------------------------------------------------
-- 1. O canal 'tablet'
-- ---------------------------------------------------------------------------
-- entrar_na_visao (parte A) marca o canal como 'tablet' ou 'colaborador'. As
-- colunas de canal só aceitavam 'app' e 'telegram', e 'colaborador' nem cabe
-- em varchar(10): a primeira entrega feita no tablet quebraria. O celular do
-- colaborador É o app; o tablet do balcão vira um canal próprio, porque saber
-- que a entrega saiu do balcão é informação útil.
CREATE OR REPLACE FUNCTION public.canal_atual()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
           WHEN NOT public.bot_contexto_confiavel() THEN 'app'
           WHEN nullif(current_setting('stgame.bot_canal', true), '') IS NULL THEN 'app'
           WHEN current_setting('stgame.bot_canal', true) = 'colaborador' THEN 'app'
           ELSE current_setting('stgame.bot_canal', true)
         END
$$;

ALTER TABLE public.entregas DROP CONSTRAINT IF EXISTS entregas_canalenvio_check;
ALTER TABLE public.entregas ADD  CONSTRAINT entregas_canalenvio_check
  CHECK (canalenvio IN ('app', 'telegram', 'tablet'));
ALTER TABLE public.entregas DROP CONSTRAINT IF EXISTS entregas_canalvalidacao_check;
ALTER TABLE public.entregas ADD  CONSTRAINT entregas_canalvalidacao_check
  CHECK (canalvalidacao IN ('app', 'telegram', 'tablet'));
ALTER TABLE public.documentosacessos DROP CONSTRAINT IF EXISTS documentosacessos_canal_check;
ALTER TABLE public.documentosacessos ADD  CONSTRAINT documentosacessos_canal_check
  CHECK (canal IN ('app', 'telegram', 'tablet'));
ALTER TABLE public.missoesaceites DROP CONSTRAINT IF EXISTS missoesaceites_canal_check;
ALTER TABLE public.missoesaceites ADD  CONSTRAINT missoesaceites_canal_check
  CHECK (canal IN ('app', 'telegram', 'tablet'));

-- ---------------------------------------------------------------------------
-- 2. Tarefa compartilhada: uma atribuição sem dono, com lista de quem pode pegar
-- ---------------------------------------------------------------------------
ALTER TABLE public.tarefasatribuidas
  ADD COLUMN IF NOT EXISTS compartilhada boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.tarefasatribuidas.compartilhada IS
  'Tarefa única atribuída a várias pessoas: sem dono, quem pegar primeiro leva. A lista de quem pode pegar está em tarefascandidatos.';

-- A regra antiga exigia dono, agendamento ou horário de disparo. A tarefa
-- compartilhada não tem nenhum dos três.
ALTER TABLE public.tarefasatribuidas DROP CONSTRAINT IF EXISTS tarefasatribuidas_missao_tem_horario;
ALTER TABLE public.tarefasatribuidas ADD  CONSTRAINT tarefasatribuidas_missao_tem_horario
  CHECK (funcionarioid IS NOT NULL OR agendamentoid IS NOT NULL
         OR horariodisparo IS NOT NULL OR compartilhada);

CREATE TABLE IF NOT EXISTS public.tarefascandidatos (
  contaid       integer NOT NULL REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  atribuicaoid  integer NOT NULL,
  funcionarioid integer NOT NULL,
  PRIMARY KEY (contaid, atribuicaoid, funcionarioid),
  CONSTRAINT tarefascandidatos_atribuicao_fk FOREIGN KEY (contaid, atribuicaoid)
    REFERENCES public.tarefasatribuidas (contaid, atribuicaoid) ON DELETE CASCADE,
  CONSTRAINT tarefascandidatos_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT
);
ALTER TABLE public.tarefascandidatos ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.tarefascandidatos TO authenticated;
GRANT ALL    ON public.tarefascandidatos TO service_role;
DROP POLICY IF EXISTS tarefascandidatos_sel ON public.tarefascandidatos;
CREATE POLICY tarefascandidatos_sel ON public.tarefascandidatos FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));
COMMENT ON TABLE public.tarefascandidatos IS
  'Quem pode pegar uma tarefa compartilhada. Sem linhas na missão da equipe: ali qualquer pessoa da loja pode pegar.';

-- ---------------------------------------------------------------------------
-- 3. Aceites: agora valem para toda tarefa, e podem ser revogados
-- ---------------------------------------------------------------------------
ALTER TABLE public.missoesaceites ADD COLUMN IF NOT EXISTS revogadoem      timestamptz;
ALTER TABLE public.missoesaceites ADD COLUMN IF NOT EXISTS revogadopor     uuid REFERENCES auth.users (id) ON DELETE SET NULL;
ALTER TABLE public.missoesaceites ADD COLUMN IF NOT EXISTS motivorevogacao text;
ALTER TABLE public.missoesaceites DROP CONSTRAINT IF EXISTS missoesaceites_revogacao_tem_motivo;
ALTER TABLE public.missoesaceites ADD  CONSTRAINT missoesaceites_revogacao_tem_motivo
  CHECK (revogadoem IS NULL OR btrim(coalesce(motivorevogacao, '')) <> '');

-- A chave era (conta, atribuição, dia) para sempre: depois de revogar, o dia
-- ficava travado. Passa a ser "um aceite ATIVO por tarefa por dia", e o
-- revogado continua guardado.
ALTER TABLE public.missoesaceites ADD COLUMN IF NOT EXISTS aceiteid integer GENERATED BY DEFAULT AS IDENTITY;
ALTER TABLE public.missoesaceites DROP CONSTRAINT IF EXISTS missoesaceites_pkey;
ALTER TABLE public.missoesaceites ADD  CONSTRAINT missoesaceites_pkey PRIMARY KEY (aceiteid);
CREATE UNIQUE INDEX IF NOT EXISTS missoesaceites_ativo_unico
  ON public.missoesaceites (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL;
CREATE INDEX IF NOT EXISTS missoesaceites_pessoa_idx
  ON public.missoesaceites (contaid, funcionarioid, dia) WHERE revogadoem IS NULL;
CREATE INDEX IF NOT EXISTS missoesaceites_nova_idx
  ON public.missoesaceites (contaid, novaatribuicaoid) WHERE revogadoem IS NULL;
COMMENT ON TABLE public.missoesaceites IS
  'Quem pegou cada tarefa, em que dia e por onde. Vale para missão, tarefa compartilhada e tarefa com dono (entregar vale como aceite). O gestor pode revogar, com motivo.';

-- ---------------------------------------------------------------------------
-- 4. Pegar a tarefa
-- ---------------------------------------------------------------------------
-- Devolve a atribuição em que a entrega vai entrar: a própria (tarefa com
-- dono) ou a cópia no nome de quem pegou (compartilhada e missão).
-- Dois toques no mesmo instante: a linha da tarefa é trancada e o índice
-- "um aceite ativo por dia" garante que só um passa.
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

  -- Só quem está ativo, ligado à loja e trabalha hoje.
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

  -- Tarefa com dono: a entrega entra nela mesma.
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

-- O bot continua chamando pegar_missao: vira um atalho para a função acima.
CREATE OR REPLACE FUNCTION public.pegar_missao(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.pegar_tarefa(p_atribuicaoid, p_funcionarioid)
$$;

-- ---------------------------------------------------------------------------
-- 5. Revogar o aceite (só o gestor, com motivo)
-- ---------------------------------------------------------------------------
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
  IF EXISTS (SELECT 1 FROM public.entregas e
              WHERE e.contaid = v_conta AND e.atribuicaoid = v_alvo
                AND e.statusvalidacao IN ('Pendente', 'Aprovada')) THEN
    RAISE EXCEPTION 'Já existe entrega desta tarefa. Recuse a entrega antes de revogar o aceite.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.missoesaceites
     SET revogadoem = now(), revogadopor = auth.uid(), motivorevogacao = v_motivo
   WHERE aceiteid = a.aceiteid;

  -- A cópia no nome de quem tinha pegado sai de cena (não conta na nota nem
  -- aparece para entregar). O registro do aceite revogado fica.
  IF a.novaatribuicaoid IS NOT NULL THEN
    UPDATE public.tarefasatribuidas SET datafimvigencia = p_dia
     WHERE contaid = v_conta AND atribuicaoid = a.novaatribuicaoid;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Entregar sem ter pegado vale como aceite
-- ---------------------------------------------------------------------------
-- Mesma função de antes, com um bloco a mais: a entrega numa tarefa com dono
-- registra o aceite do dia, se ainda não houver. Assim "pegou" e "entregou"
-- contam do mesmo jeito na nota.
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
  WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta;

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
  IF v_atr.tipofrequencia = 'Unica' AND EXISTS (
       SELECT 1 FROM public.entregas
       WHERE atribuicaoid = p_atribuicaoid AND statusvalidacao IN ('Pendente', 'Aprovada')) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF v_foto IS NOT NULL AND v_foto NOT LIKE v_conta || '/' || v_atr.lojaid || '/%' THEN
    RAISE EXCEPTION 'A foto precisa estar na pasta da própria loja.' USING ERRCODE = 'check_violation';
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
-- 7. Atribuir: uma pessoa, várias pessoas, ou missão da equipe
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.atribuir_tarefa(
  p_tarefaid        integer,
  p_lojaid          integer,
  p_funcionarios    integer[],
  p_tipofrequencia  text,
  p_valorfrequencia integer     DEFAULT NULL,
  p_dataagendamento timestamptz DEFAULT NULL,
  p_horariodisparo  time        DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.minha_conta_editavel();
  v_gente   integer[] := coalesce(p_funcionarios, ARRAY[]::integer[]);
  v_quantos integer;
  v_id      integer;
  v_fid     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT count(DISTINCT x) INTO v_quantos FROM unnest(v_gente) x WHERE x IS NOT NULL;

  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE tarefaid = p_tarefaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_quantos = 0 AND p_horariodisparo IS NULL THEN
    RAISE EXCEPTION 'Escolha quem faz a tarefa, ou a hora em que a missão vai para o grupo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Todo mundo escolhido precisa estar ativo e ligado a esta loja.
  IF v_quantos > 0 AND EXISTS (
       SELECT 1 FROM unnest(v_gente) g
        WHERE g IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.funcionarios f
                            JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid
                                                            AND fl.contaid = v_conta AND fl.ativo
                           WHERE f.funcionarioid = g AND f.contaid = v_conta AND f.ativo
                             AND fl.lojaid = p_lojaid)) THEN
    RAISE EXCEPTION 'Escolha só pessoas ativas desta loja.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                        valorfrequencia, dataagendamento, horariodisparo, compartilhada)
  VALUES (v_conta, p_tarefaid,
          CASE WHEN v_quantos = 1 THEN (SELECT x FROM unnest(v_gente) x WHERE x IS NOT NULL LIMIT 1) END,
          p_lojaid, p_tipofrequencia, p_valorfrequencia, p_dataagendamento,
          CASE WHEN v_quantos = 0 THEN p_horariodisparo END,
          v_quantos > 1)
  RETURNING atribuicaoid INTO v_id;

  IF v_quantos > 1 THEN
    FOREACH v_fid IN ARRAY v_gente LOOP
      IF v_fid IS NOT NULL THEN
        INSERT INTO public.tarefascandidatos (contaid, atribuicaoid, funcionarioid)
        VALUES (v_conta, v_id, v_fid) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. A fila do dia de uma loja (Quadro hoje, tablet na parte B1b)
-- ---------------------------------------------------------------------------
-- Três faixas: para_pegar, em_andamento e feita. Uma só fonte da verdade para
-- a tela do gestor e para o tablet.
-- Tarefa de quem está de folga NÃO entra: continua no repasse manual do Quadro.
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
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                           AND (ta.tipofrequencia = 'Unica'
                                OR public.dia_em_sao_paulo(e.dataenvio) = ctx.dia)) THEN 'feita'
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
     -- tarefa com dono: só entra se o dono está ativo, na loja e trabalha hoje
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3
$$;

-- As tarefas compartilhadas e missões que ninguém pegou hoje, com quem estava
-- atribuído. Alimenta o cartão do Início e a lista do Quadro.
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
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo
$$;

-- ---------------------------------------------------------------------------
-- 9. A nota do mês: quem pega, assume
-- ---------------------------------------------------------------------------
-- Mudou só o tratamento da tarefa sem dono (compartilhada e missão):
--   * antes: nunca entrava nos pontos possíveis de ninguém, e a entrega
--     contava só como esforço. Pegar era bônus sem risco.
--   * agora: entra nos pontos possíveis de QUEM PEGOU, e a entrega aprovada
--     conta na confiabilidade dela. Quem não pegou fica neutro, e o que
--     ninguém pegou não entra na nota de ninguém.
-- Tarefa com dono continua como sempre foi: é dela, feita ou não.
-- Tarefa recebida de quem está de folga continua sendo extra (não tem aceite).
CREATE OR REPLACE FUNCTION public.ranking_mensal_da_conta(
  p_contaid integer, p_ano integer, p_mes integer, p_lojaid integer, p_fim date
)
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
           least((make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date, p_fim) AS fim
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, janela j
     WHERE dg.contaid = p_contaid AND dg.dia BETWEEN j.ini AND j.fim
  ),
  -- Aceites válidos de tarefa SEM dono: a cópia no nome de quem pegou.
  aceites AS (
    SELECT a.funcionarioid AS fid, a.novaatribuicaoid AS atr, t.pontos
      FROM public.missoesaceites a
      JOIN public.tarefasatribuidas nova ON nova.atribuicaoid = a.novaatribuicaoid AND nova.contaid = p_contaid
      JOIN public.tarefas t ON t.tarefaid = nova.tarefaid AND t.contaid = p_contaid
      CROSS JOIN janela j
     WHERE a.contaid = p_contaid
       AND a.revogadoem IS NULL
       AND a.novaatribuicaoid IS NOT NULL
       AND a.dia BETWEEN j.ini AND j.fim
       AND (p_lojaid IS NULL OR nova.lojaid = p_lojaid)
  ),
  pegas AS (
    SELECT fid, sum(pontos)::integer AS pts FROM aceites GROUP BY fid
  ),
  lista AS (
    SELECT i.funcionarioid AS fid, sum(i.pontos)::integer AS pts
      FROM public.tarefasdodia i
      JOIN gerados g ON g.dia = i.dia
     WHERE i.contaid = p_contaid
       AND i.situacao = 'devida'
       AND (p_lojaid IS NULL OR i.lojaid = p_lojaid)
       AND NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
     GROUP BY i.funcionarioid
  ),
  recorrentes AS (
    SELECT ta.funcionarioid AS fid, sum(t.pontos)::integer AS pts
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid AND f.contaid = p_contaid
      CROSS JOIN janela j
      CROSS JOIN LATERAL generate_series(
        greatest(j.ini,
                 coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), j.ini),
                 coalesce(ta.datainiciovigencia, j.ini)),
        least(j.fim, coalesce(ta.datafimvigencia - 1, j.fim)),
        interval '1 day') AS g(d)
     WHERE ta.contaid = p_contaid
       AND ta.funcionarioid IS NOT NULL
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, g.d::date, true)
     GROUP BY ta.funcionarioid
  ),
  unicas AS (
    SELECT ta.funcionarioid AS fid, sum(t.pontos)::integer AS pts
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
      CROSS JOIN janela j
     WHERE ta.contaid = p_contaid
       AND ta.funcionarioid IS NOT NULL
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN j.ini AND j.fim
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) NOT IN (SELECT dia FROM gerados)
       AND (ta.datafimvigencia IS NULL
            OR ta.datafimvigencia > public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)))
       AND NOT public.tem_justificativa(ta.atribuicaoid, 'Unica', NULL, true)
     GROUP BY ta.funcionarioid
  ),
  regulares AS (
    SELECT e.funcionarioid AS fid, sum(e.pontosganhos)::integer AS pts
      FROM public.entregas e
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = e.atribuicaoid AND ta.contaid = p_contaid
      CROSS JOIN janela j
     WHERE e.contaid = p_contaid
       AND e.statusvalidacao = 'Aprovada'
       AND (ta.origematribuicaoid IS NULL
            OR EXISTS (SELECT 1 FROM aceites ac WHERE ac.atr = ta.atribuicaoid))
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN j.ini AND j.fim
     GROUP BY e.funcionarioid
  ),
  ganhos AS (
    SELECT e.funcionarioid AS fid, sum(e.pontosganhos)::integer AS pts
      FROM public.entregas e
      CROSS JOIN janela j
     WHERE e.contaid = p_contaid
       AND e.statusvalidacao = 'Aprovada'
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
       AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN j.ini AND j.fim
     GROUP BY e.funcionarioid
  ),
  pessoas AS (
    SELECT fid FROM lista UNION SELECT fid FROM recorrentes UNION SELECT fid FROM unicas
    UNION SELECT fid FROM regulares UNION SELECT fid FROM ganhos UNION SELECT fid FROM pegas
  ),
  base AS (
    SELECT p.fid,
           f.nomecompleto AS nome,
           coalesce(g.pts, 0)                                        AS ganhos,
           coalesce(r.pts, 0)                                        AS regulares,
           coalesce(li.pts, 0) + coalesce(rc.pts, 0) + coalesce(u.pts, 0) + coalesce(pg.pts, 0) AS possiveis
      FROM pessoas p
      JOIN public.funcionarios f ON f.funcionarioid = p.fid AND f.contaid = p_contaid
      LEFT JOIN ganhos g       ON g.fid = p.fid
      LEFT JOIN regulares r    ON r.fid = p.fid
      LEFT JOIN lista li       ON li.fid = p.fid
      LEFT JOIN recorrentes rc ON rc.fid = p.fid
      LEFT JOIN unicas u       ON u.fid = p.fid
      LEFT JOIN pegas pg       ON pg.fid = p.fid
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

-- ---------------------------------------------------------------------------
-- 10. Permissões (negadas por padrão desde a Etapa 1.6)
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.pegar_tarefa(integer, integer)          FROM public, anon;
REVOKE ALL ON FUNCTION public.revogar_aceite(integer, date, text)     FROM public, anon;
REVOKE ALL ON FUNCTION public.fila_da_loja(integer)                   FROM public, anon;
REVOKE ALL ON FUNCTION public.tarefas_nao_pegas(integer)              FROM public, anon;
REVOKE ALL ON FUNCTION public.atribuir_tarefa(integer, integer, integer[], text, integer, timestamptz, time)
                                                                      FROM public, anon;
GRANT EXECUTE ON FUNCTION public.pegar_tarefa(integer, integer)       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revogar_aceite(integer, date, text)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fila_da_loja(integer)                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tarefas_nao_pegas(integer)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.atribuir_tarefa(integer, integer, integer[], text, integer, timestamptz, time)
                                                                      TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. Revogar precisa liberar o dia de novo
-- ---------------------------------------------------------------------------
-- O índice "tarefasatribuidas_passada_uma_vez" garante uma cópia por tarefa
-- por dia. Com a revogação, a cópia antiga fica encerrada e outra pessoa tem
-- de conseguir pegar no mesmo dia: a cópia encerrada sai do índice.
DROP INDEX IF EXISTS public.tarefasatribuidas_passada_uma_vez;
CREATE UNIQUE INDEX tarefasatribuidas_passada_uma_vez
  ON public.tarefasatribuidas (contaid, origematribuicaoid, public.dia_em_sao_paulo(dataagendamento))
  WHERE origematribuicaoid IS NOT NULL AND datafimvigencia IS NULL;

-- ---------------------------------------------------------------------------
-- 12. Relatório por pessoa: o que ela PEGOU, separado do que era dela
-- ---------------------------------------------------------------------------
-- As tarefas atribuídas a ela já aparecem nas pendências. Esta lista mostra o
-- outro lado: as tarefas abertas que ela assumiu no período (e que, por isso,
-- passaram a pesar na nota dela).
CREATE OR REPLACE FUNCTION public.tarefas_pegas_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
RETURNS TABLE (
  dia        date,
  titulo     varchar,
  pontos     integer,
  loja       varchar,
  entregue   boolean,
  revogadoem timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS (SELECT public.minha_conta() AS conta)
  SELECT a.dia, t.titulo, t.pontos, l.nome,
         EXISTS (SELECT 1 FROM public.entregas e
                  WHERE e.contaid = ctx.conta AND e.atribuicaoid = a.novaatribuicaoid
                    AND e.statusvalidacao IN ('Pendente', 'Aprovada')),
         a.revogadoem
    FROM ctx
    JOIN public.missoesaceites a     ON a.contaid = ctx.conta AND a.funcionarioid = p_funcionarioid
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.atribuicaoid = a.novaatribuicaoid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    LEFT JOIN public.lojas l         ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND a.novaatribuicaoid IS NOT NULL
     AND a.dia BETWEEN p_de AND p_ate
   ORDER BY a.dia DESC, t.titulo
$$;

REVOKE ALL ON FUNCTION public.tarefas_pegas_da_pessoa(integer, date, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tarefas_pegas_da_pessoa(integer, date, date) TO authenticated;

-- =========================================================================
-- 20260928100100_visao_do_tablet.sql
-- =========================================================================

-- Etapa 1.12, parte B1b — o que o tablet da loja pode pedir ao banco.
--
-- O tablet entra como a LOJA, e para ele `minha_conta()` responde vazio: as
-- ~200 regras de acesso que já existiam negam tudo. Estas funções são a única
-- porta, e só o SERVIDOR as chama (elas recebem conta e loja, então nunca são
-- liberadas para quem está logado — regra da Etapa 1.6).
--
-- Cada uma liga o contexto da visão e faz o trabalho na MESMA transação: o
-- contexto é local à transação, então não dá para ligá-lo numa chamada e usá-lo
-- na seguinte.

-- ---------------------------------------------------------------------------
-- 1. A fila do dia
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.visao_fila(p_contaid integer, p_lojaid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, NULL, p_lojaid, 'tablet');
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) FROM public.fila_da_loja(p_lojaid) f);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Quem é o PIN
-- ---------------------------------------------------------------------------
-- O resumo do PIN é feito pelo SERVIDOR (HMAC com a chave que só ele tem), do
-- mesmo jeito da parte A: quem tiver só o banco não consegue testar número
-- nenhum. Aqui é busca direta pelo índice, sem comparar uma pessoa por vez.
-- Só encontra quem está ativo, ligado a ESTA loja e trabalhando hoje.
CREATE OR REPLACE FUNCTION public.visao_pessoa_do_pin(p_contaid integer, p_lojaid integer, p_pinhash text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  f      record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT fu.funcionarioid, fu.nomecompleto INTO f
    FROM public.funcionarios fu
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = fu.funcionarioid AND fl.contaid = p_contaid
                                    AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE fu.contaid = p_contaid AND fu.ativo
     AND fu.pinhash = p_pinhash
     AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
   LIMIT 1;

  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('funcionarioid', f.funcionarioid,
                            'nome', public.nome_curto(f.nomecompleto));
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Pegar
-- ---------------------------------------------------------------------------
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
  IF NOT EXISTS (SELECT 1 FROM public.tarefasatribuidas
                  WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');
  RETURN public.pegar_tarefa(p_atribuicaoid, p_funcionarioid);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Entregar
-- ---------------------------------------------------------------------------
-- Recebe sempre a tarefa de origem; a função descobre onde a entrega entra.
-- Entregar sem ter pegado vale como aceite. O PIN de outra pessoa é recusado.
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

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  IF m.funcionarioid IS NULL THEN
    SELECT novaatribuicaoid, funcionarioid INTO v_alvo, v_dono
      FROM public.missoesaceites
     WHERE contaid = p_contaid AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
    IF v_alvo IS NULL THEN
      -- Ninguém pegou ainda: entregar vale como aceite.
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
-- 5. Permissões: só o servidor. Recebem conta e loja, então nunca são
--    liberadas para quem está logado (regra da Etapa 1.6).
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.visao_fila(integer, integer)                        FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_pessoa_do_pin(integer, integer, text)         FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_pegar(integer, integer, integer, integer)     FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text)
                                                                                  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.visao_fila(integer, integer)                     TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_pessoa_do_pin(integer, integer, text)      TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_pegar(integer, integer, integer, integer)  TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. O diagnóstico (/saude) passa a conhecer as funções desta parte
-- ---------------------------------------------------------------------------
-- Sem isto, um banco sem a B1a/B1b daria "não foi possível" na tela do tablet
-- sem dizer o motivo — foi o que aconteceu em 23/09/2026 com a parte A.
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_fechar', 'acesso_por_email', 'definir_senha_gestor',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado',
    -- Etapa 1.12, partes B1a e B1b
    'pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
    'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa',
    'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar'
  ];
  v_faltando text[];
  v_tabelas  text[];
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pede o diagnóstico.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_faltando
    FROM unnest(v_esperadas) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);

  SELECT coalesce(array_agg(t ORDER BY t), ARRAY[]::text[]) INTO v_tabelas
    FROM unnest(ARRAY['codigosacesso', 'tentativasacesso', 'senhasgestor', 'fotosexpurgo',
                      'tarefascandidatos']) t
   WHERE to_regclass('public.' || t) IS NULL;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;

-- =========================================================================
-- 20260928100200_consertos_revisao_b1.sql
-- =========================================================================

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

-- =========================================================================
-- 20260928100300_ranking_le_o_fechamento.sql
-- =========================================================================

-- Etapa 1.12, parte B1 — a tela Ranking passa a ler o fechamento (24/09/2026).
--
-- Decisão do Wisley: mês já fechado vem do fechamento; mês aberto continua
-- sendo calculado ao vivo. Antes, a tela Ranking recalculava qualquer mês, e
-- uma mudança de regra (como "quem pega assume", da parte B1a) mexia em meses
-- antigos — a tela Ranking e a tela "Meses fechados" podiam mostrar números
-- diferentes para o mesmo mês.

-- Qual fechamento vale para este mês, na conta de quem está perguntando.
-- Nada de SECURITY DEFINER: a RLS de fechamentosmensais já filtra a conta, e
-- o filtro está explícito de novo aqui.
CREATE OR REPLACE FUNCTION public.fechamento_valendo(p_ano integer, p_mes integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT f.fechamentoid
    FROM public.fechamentosmensais f
   WHERE f.contaid = (select public.minha_conta())
     AND f.ano = p_ano AND f.mes = p_mes
     AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC
   LIMIT 1
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
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fechamento integer := public.fechamento_valendo(p_ano, p_mes);
BEGIN
  IF v_fechamento IS NOT NULL THEN
    -- Mês fechado: os números estão congelados. É a mesma fonte da tela
    -- "Meses fechados", então as duas nunca discordam.
    RETURN QUERY
      SELECT h.funcionarioid, h.nomefuncionario, h.pontosganhos,
             coalesce(h.pontosregulares, 0), h.pontospossiveis,
             coalesce(h.confiabilidade, 0), coalesce(h.esforco, 0), coalesce(h.nota, 0)
        FROM public.historicoranking h
       WHERE h.fechamentoid = v_fechamento
         AND h.lojaid IS NOT DISTINCT FROM p_lojaid
       ORDER BY h.posicao;
  ELSE
    -- Mês aberto: ao vivo, até ontem.
    RETURN QUERY
      SELECT * FROM public.ranking_mensal_da_conta(public.minha_conta(), p_ano, p_mes, p_lojaid,
                                                   public.dia_em_sao_paulo(now()) - 1);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fechamento_valendo(integer, integer)      FROM public, anon;
REVOKE ALL ON FUNCTION public.ranking_mensal(integer, integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fechamento_valendo(integer, integer)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.ranking_mensal(integer, integer, integer) TO authenticated;

-- =========================================================================
-- Conferência final: se chegou aqui, está tudo no lugar.
-- =========================================================================
DO $verifica$
DECLARE v_falta text[];
BEGIN
  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_falta
    FROM unnest(ARRAY['pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
                      'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa', 'tarefa_unica_ja_cumprida',
                      'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar',
                      'fechamento_valendo']) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);
  IF array_length(v_falta, 1) > 0 THEN
    RAISE EXCEPTION 'Faltou criar: %', array_to_string(v_falta, ', ');
  END IF;
  IF to_regclass('public.tarefascandidatos') IS NULL THEN
    RAISE EXCEPTION 'Faltou criar a tabela tarefascandidatos.';
  END IF;
  RAISE NOTICE 'tudo certo: a parte B1 foi aplicada.';
END $verifica$;

COMMIT;
