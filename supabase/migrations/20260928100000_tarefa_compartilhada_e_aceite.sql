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
