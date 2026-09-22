-- Etapa 1.7, parte 2 (antiga Fase 7): conquistas, nota do ranking mensal,
-- relatorios, configuracoes e nomes neutros para as funcoes da loja.
-- Decisoes do Wisley em 21/09/2026, registradas em docs/PLANO_MIGRACAO.md.

-- ===========================================================================
-- 0. Nomes neutros para as funcoes da loja de premios.
--    Bloqueadores de anuncio cortam enderecos por palavra-chave. Nenhuma das
--    8 listas testadas barra os nomes atuais, mas a troca e uma precaucao
--    pedida pelo Wisley. RENAME mantem as permissoes.
-- ===========================================================================

ALTER FUNCTION public.registrar_resgate(integer, integer, integer, boolean)       RENAME TO registrar_troca;
ALTER FUNCTION public.registrar_abate_comanda(integer, numeric, integer, boolean) RENAME TO registrar_troca_por_valor;
ALTER FUNCTION public.entregar_resgate(integer)                                   RENAME TO concluir_troca;
ALTER FUNCTION public.cancelar_resgate(integer, text)                            RENAME TO cancelar_troca;
ALTER FUNCTION public.estornar_resgate(integer, text)                            RENAME TO estornar_troca;

-- A lista de trocas passa a vir por funcao: assim nenhum endereco que o
-- navegador acessa leva o nome da tabela "resgates".
CREATE OR REPLACE FUNCTION public.listar_trocas(p_limite integer DEFAULT 100)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         r.valorreais,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          ELSE p.nome END,
               'loja',               l.nome) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
$$;

-- ===========================================================================
-- 1. Dia de trabalho da pessoa: mesma regra para a nota do mes e para a
--    sequencia de dias das conquistas. Nao trabalha na folga semanal
--    (1 = domingo ... 7 = sabado; 0 = sem folga), no N-esimo domingo de folga
--    do mes, nem no periodo de afastamento (ferias/atestado).
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.dia_de_trabalho(
  p_diadefolga   integer,
  p_domingofolga integer,
  p_inicioafast  date,
  p_fimafast     date,
  p_dia          date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT NOT (
       (coalesce(p_diadefolga, 0) BETWEEN 1 AND 7
        AND p_diadefolga = extract(dow FROM p_dia)::integer + 1)
    OR (coalesce(p_domingofolga, 0) > 0
        AND extract(dow FROM p_dia) = 0
        AND (extract(day FROM p_dia)::integer - 1) / 7 + 1 = p_domingofolga)
    OR (p_inicioafast IS NOT NULL AND p_fimafast IS NOT NULL
        AND p_dia BETWEEN p_inicioafast AND p_fimafast)
  )
$$;

-- ===========================================================================
-- 2. Nota hibrida do ranking mensal: 50% confiabilidade + 50% esforco.
--
--    confiabilidade = pontos das tarefas atribuidas, pelo DIA DO ENVIO
--                     / pontos possiveis, travado em 100% (sem bonus);
--    possiveis      = cada dia em que a tarefa cai (tarefa_cai_no_dia),
--                     dentro da vigencia, em dia de trabalho da pessoa;
--                     Unica conta uma vez, no dia marcado;
--    esforco        = pontos aprovados / os de quem mais fez, em cima de 100;
--    janela         = do dia 1 ate ontem (mes corrente) ou o mes inteiro.
--    Bonus de conquista nao entra (ranking mede tarefas).
--    Roda com a RLS de quem chama.
-- ===========================================================================

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
-- 3. Conquistas
-- ===========================================================================

ALTER TABLE public.conquistas
  ADD COLUMN ativa        boolean     NOT NULL DEFAULT true,
  ADD COLUMN criteriodias integer,
  ADD COLUMN contardesde  timestamptz,
  ADD COLUMN criadoem     timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.conquistas ADD CONSTRAINT conquistas_tipo_valido CHECK (criteriotipo IN (
  'total_tarefas_aprovadas', 'tarefas_aprovadas_periodo', 'sequencia_dias_tarefas',
  'sequencia_feedback_diario', 'total_comunicados_cientes', 'tarefas_grupo_competitivo_aceitas'));
ALTER TABLE public.conquistas ADD CONSTRAINT conquistas_valor_positivo CHECK (criteriovalor > 0);
ALTER TABLE public.conquistas ADD CONSTRAINT conquistas_bonus_valido CHECK (coalesce(pontosbonus, 0) >= 0);
-- "N tarefas em X dias": X so existe (e e obrigatorio) nesse tipo.
ALTER TABLE public.conquistas ADD CONSTRAINT conquistas_dias_do_periodo CHECK (
  (criteriotipo = 'tarefas_aprovadas_periodo') = (criteriodias IS NOT NULL)
  AND (criteriodias IS NULL OR criteriodias BETWEEN 1 AND 366));

-- A regra e a escolha "historico / so a partir de hoje" nao mudam depois de
-- criada: mudar mudaria quem ja ganhou. Para outra regra, outra conquista.
CREATE OR REPLACE FUNCTION public.protege_regra_da_conquista()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.criteriotipo  IS DISTINCT FROM OLD.criteriotipo
  OR NEW.criteriovalor IS DISTINCT FROM OLD.criteriovalor
  OR NEW.criteriodias  IS DISTINCT FROM OLD.criteriodias
  OR NEW.contardesde   IS DISTINCT FROM OLD.contardesde THEN
    RAISE EXCEPTION 'A regra de uma conquista não muda depois de criada. Crie outra conquista.'
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER conquistas_protege_regra
  BEFORE UPDATE ON public.conquistas
  FOR EACH ROW EXECUTE FUNCTION public.protege_regra_da_conquista();

REVOKE INSERT, UPDATE ON public.conquistas FROM anon, authenticated;
GRANT UPDATE (nome, descricao, icone, pontosbonus, ativa) ON public.conquistas TO authenticated;

-- Uma por pessoa, garantido pelo banco. O navegador so le.
ALTER TABLE public.conquistasfuncionarios ADD COLUMN pontosbonus integer NOT NULL DEFAULT 0;
ALTER TABLE public.conquistasfuncionarios
  ADD CONSTRAINT conquistasfuncionarios_uma_por_pessoa UNIQUE (funcionarioid, conquistaid);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.conquistasfuncionarios FROM anon, authenticated;

-- O bonus de conquista aponta para ela no livro de pontos.
ALTER TABLE public.movimentospontos ADD COLUMN conquistafuncionarioid integer;
ALTER TABLE public.movimentospontos ADD CONSTRAINT movimentospontos_conquista_fk
  FOREIGN KEY (contaid, conquistafuncionarioid)
  REFERENCES public.conquistasfuncionarios (contaid, conquistafuncionarioid) ON DELETE RESTRICT;

-- Regras que ja podem ser avaliadas. As demais ficam cadastradas, mas o
-- banco nao as avalia ate o modulo existir.
CREATE OR REPLACE FUNCTION public.criterio_disponivel(p_tipo text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT p_tipo IN ('total_tarefas_aprovadas', 'tarefas_aprovadas_periodo', 'sequencia_dias_tarefas')
$$;

-- A pessoa cumpre a regra? Conta so tarefas atribuidas e aprovadas (bonus
-- nao conta), pelo dia do envio, e so depois de "contardesde" quando a
-- conquista foi criada "so a partir de hoje". Interna.
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
    -- Maior sequencia de dias seguidos com tarefa entregue. Dia em que a
    -- pessoa nao trabalha (folga, domingo de folga, afastamento) nao quebra a
    -- sequencia nem conta; se ela entregou mesmo assim, conta. Dia de
    -- trabalho sem entrega quebra.
    WITH com_entrega AS (
      SELECT DISTINCT public.dia_em_sao_paulo(dataenvio) AS d
        FROM public.entregas
       WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
         AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
         AND dataenvio >= v_desde
    ),
    calendario AS (
      SELECT g::date AS d
        FROM (SELECT min(d) AS ini, max(d) AS fim FROM com_entrega) lim,
             generate_series(lim.ini, lim.fim, interval '1 day') g
    ),
    contados AS (
      SELECT cal.d, EXISTS (SELECT 1 FROM com_entrega ce WHERE ce.d = cal.d) AS fez
        FROM calendario cal
    ),
    considerados AS (
      SELECT d, fez FROM contados
       WHERE fez OR public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                           f.datainicioafastamento, f.datafimafastamento, d)
    ),
    numerados AS (
      SELECT d, fez, row_number() OVER (ORDER BY d) AS rn FROM considerados
    ),
    ilhas AS (
      SELECT rn - row_number() OVER (ORDER BY d) AS grupo FROM numerados WHERE fez
    )
    SELECT coalesce(max(qtd), 0) INTO n
      FROM (SELECT count(*) AS qtd FROM ilhas GROUP BY grupo) x;
    RETURN n >= c.criteriovalor;
  END IF;

  RETURN false;
END;
$$;

-- Concede o que a pessoa passou a cumprir. A unicidade (pessoa, conquista)
-- garante uma vez so, mesmo com aprovacoes simultaneas; so quem de fato
-- gravou a conquista gera o bonus, que entra pelo livro de pontos. Interna.
CREATE OR REPLACE FUNCTION public.avaliar_conquistas(p_contaid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c        record;
  v_id     integer;
  v_novas  integer := 0;
BEGIN
  -- Uma avaliacao por pessoa de cada vez: a segunda espera a primeira terminar
  -- e ja enxerga o que ela gravou. NO KEY UPDATE e o mesmo nivel que o gatilho
  -- do saldo usa; FOR UPDATE brigaria com a trava leve da chave estrangeira do
  -- livro de pontos e causaria deadlock em aprovacoes simultaneas.
  PERFORM 1 FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = p_contaid FOR NO KEY UPDATE;

  FOR c IN
    SELECT q.* FROM public.conquistas q
     WHERE q.contaid = p_contaid AND q.ativa AND public.criterio_disponivel(q.criteriotipo)
       AND NOT EXISTS (SELECT 1 FROM public.conquistasfuncionarios cf
                        WHERE cf.funcionarioid = p_funcionarioid AND cf.conquistaid = q.conquistaid)
     ORDER BY q.conquistaid
  LOOP
    IF public.pessoa_cumpre_conquista(p_contaid, p_funcionarioid, c.conquistaid) THEN
      v_id := NULL;
      INSERT INTO public.conquistasfuncionarios (contaid, funcionarioid, conquistaid, dataconquista, pontosbonus)
      VALUES (p_contaid, p_funcionarioid, c.conquistaid, now(), coalesce(c.pontosbonus, 0))
      ON CONFLICT (funcionarioid, conquistaid) DO NOTHING
      RETURNING conquistafuncionarioid INTO v_id;

      IF v_id IS NOT NULL THEN
        v_novas := v_novas + 1;
        IF coalesce(c.pontosbonus, 0) > 0 THEN
          INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, conquistafuncionarioid, criadopor)
          VALUES (p_contaid, p_funcionarioid, 'bonus', c.pontosbonus,
                  'Conquista: ' || coalesce(c.icone || ' ', '') || c.nome, v_id, auth.uid());
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN v_novas;
END;
$$;

-- O gancho que ja existia desde a Etapa 1.5: agora avalia as conquistas.
CREATE OR REPLACE FUNCTION public.apos_aprovar_entrega(p_entregaid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer; v_func integer;
BEGIN
  SELECT contaid, funcionarioid INTO v_conta, v_func FROM public.entregas WHERE entregaid = p_entregaid;
  IF FOUND THEN
    PERFORM public.avaliar_conquistas(v_conta, v_func);
  END IF;
END;
$$;

-- Cria a conquista. "Vale para o historico": concede agora a quem ja cumpre.
-- "So a partir de hoje": so contam as tarefas enviadas depois de agora.
CREATE OR REPLACE FUNCTION public.criar_conquista(
  p_nome        text,
  p_descricao   text,
  p_icone       text,
  p_tipo        text,
  p_valor       integer,
  p_dias        integer,
  p_bonus       integer,
  p_retroativa  boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.minha_conta_editavel();
  v_id     integer;
  v_novas  integer := 0;
  f        record;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_nome, ''))) = 0 THEN
    RAISE EXCEPTION 'Dê um nome à conquista.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_retroativa IS NULL THEN
    RAISE EXCEPTION 'Escolha se a conquista vale para o histórico ou só a partir de hoje.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.conquistas (contaid, nome, descricao, icone, criteriotipo, criteriovalor, criteriodias,
                                 pontosbonus, contardesde)
  VALUES (v_conta, btrim(p_nome), coalesce(nullif(btrim(p_descricao), ''), btrim(p_nome)),
          nullif(btrim(coalesce(p_icone, '')), ''), p_tipo, p_valor,
          CASE WHEN p_tipo = 'tarefas_aprovadas_periodo' THEN p_dias END,
          coalesce(p_bonus, 0),
          CASE WHEN p_retroativa THEN NULL ELSE now() END)
  RETURNING conquistaid INTO v_id;

  IF p_retroativa AND public.criterio_disponivel(p_tipo) THEN
    FOR f IN SELECT funcionarioid FROM public.funcionarios WHERE contaid = v_conta ORDER BY funcionarioid LOOP
      v_novas := v_novas + public.avaliar_conquistas(v_conta, f.funcionarioid);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('conquistaid', v_id, 'concedidas', v_novas);
END;
$$;

-- ===========================================================================
-- 4. Relatorios (rodam com a RLS de quem chama)
-- ===========================================================================

-- Tarefas que caiam e nao foram entregues, dia a dia, ate ontem. So dias de
-- trabalho da pessoa e so atribuicoes vigentes naquele dia.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
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
    SELECT g.d::date AS dia, t.titulo, t.pontos, l.nome AS loja
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
    SELECT public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)), t.titulo, t.pontos, l.nome
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
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'titulo', titulo, 'pontos', pontos, 'loja', loja)
                            ORDER BY dia DESC, titulo), '[]'::jsonb)
    FROM itens
$$;

-- As ultimas entregas da pessoa, em qualquer situacao.
CREATE OR REPLACE FUNCTION public.historico_da_pessoa(p_funcionarioid integer, p_limite integer DEFAULT 100)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT e.dataenvio AS ds, e.entregaid AS id,
             jsonb_build_object('titulo', t.titulo, 'loja', l.nome, 'enviadaem', e.dataenvio,
                                'status', e.statusvalidacao, 'pontos', e.pontosganhos,
                                'motivo', coalesce(e.motivorecusa, e.motivoestorno)) AS x
        FROM public.entregas e
        JOIN public.tarefas t    ON t.tarefaid = e.tarefaid
        LEFT JOIN public.lojas l ON l.lojaid = e.lojaid
       WHERE e.funcionarioid = p_funcionarioid AND e.atribuicaoid IS NOT NULL
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 500))
    ) s
$$;

-- Por tarefa: aprovadas, recusadas e estornadas no periodo (tarefa mal
-- explicada aparece no topo).
CREATE OR REPLACE FUNCTION public.analise_de_tarefas(p_de date, p_ate date, p_lojaid integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', titulo, 'aprovadas', aprovadas, 'recusadas', recusadas,
           'estornadas', estornadas, 'pendentes', pendentes)
           ORDER BY recusadas + estornadas DESC, titulo), '[]'::jsonb)
    FROM (
      SELECT t.titulo,
             count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
             count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
             count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
             count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
        FROM public.entregas e
        JOIN public.tarefas t ON t.tarefaid = e.tarefaid
       WHERE e.atribuicaoid IS NOT NULL
         AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN p_de AND p_ate
         AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
       GROUP BY t.tarefaid, t.titulo
    ) s
$$;

-- ===========================================================================
-- 5. Configuracoes: validacao e historico de mudancas, em gatilhos, para
--    nenhum caminho escapar. O navegador altera so por alterar_configuracao.
-- ===========================================================================

CREATE TABLE public.configuracoeshistorico (
  historicoid   integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  chave         varchar(100) NOT NULL,
  valoranterior text,
  valornovo     text,
  alteradopor   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  alteradoem    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT configuracoeshistorico_config_fk FOREIGN KEY (contaid, chave)
    REFERENCES public.configuracoes (contaid, chave) ON DELETE RESTRICT
);
CREATE INDEX configuracoeshistorico_contaid_idx ON public.configuracoeshistorico (contaid, alteradoem DESC);

ALTER TABLE public.configuracoeshistorico ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.configuracoeshistorico FROM anon, authenticated;
GRANT SELECT ON public.configuracoeshistorico TO authenticated;
GRANT ALL ON public.configuracoeshistorico TO service_role;
CREATE POLICY configuracoeshistorico_sel ON public.configuracoeshistorico FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

CREATE OR REPLACE FUNCTION public.valida_configuracao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_texto text := btrim(coalesce(NEW.valor, ''));
  v_num   numeric;
BEGIN
  IF NEW.chave = 'TAXA_CONVERSAO_PONTO_REAL' THEN
    BEGIN
      v_num := replace(v_texto, ',', '.')::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'A taxa precisa ser um número, como 0,03.' USING ERRCODE = 'check_violation';
    END;
    IF v_num IS NULL OR v_num <= 0 OR v_num > 10 THEN
      RAISE EXCEPTION 'A taxa precisa ser maior que zero e no máximo R$ 10 por ponto.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_num::text;

  ELSIF NEW.chave LIKE 'PONTOS_BONUS_%' OR NEW.chave = 'MAX_DIFERENCA_FOTO_SEGUNDOS' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro, sem vírgula.' USING ERRCODE = 'check_violation';
    END IF;
    v_num := CASE WHEN NEW.chave LIKE 'PONTOS_BONUS_%' THEN 10000 ELSE 86400 END;
    IF v_texto::numeric > v_num THEN
      RAISE EXCEPTION 'Valor alto demais para %.', NEW.chave USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave LIKE 'HORARIO_%' THEN
    IF v_texto !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
      RAISE EXCEPTION 'O horário precisa estar no formato HH:MM, entre 00:00 e 23:59.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave LIKE 'TAREFA_%' THEN
    IF v_texto <> '' AND v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'ID de tarefa inválido.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.atualizadoem := now();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER configuracoes_valida
  BEFORE INSERT OR UPDATE ON public.configuracoes
  FOR EACH ROW EXECUTE FUNCTION public.valida_configuracao();

CREATE OR REPLACE FUNCTION public.registra_mudanca_configuracao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Os IDs das tarefas do sistema sao preenchidos pelo proprio sistema.
  IF NEW.valor IS DISTINCT FROM OLD.valor AND NEW.chave NOT LIKE 'TAREFA_%' THEN
    INSERT INTO public.configuracoeshistorico (contaid, chave, valoranterior, valornovo, alteradopor)
    VALUES (NEW.contaid, NEW.chave, OLD.valor, NEW.valor, auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER configuracoes_historico
  AFTER UPDATE ON public.configuracoes
  FOR EACH ROW EXECUTE FUNCTION public.registra_mudanca_configuracao();

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.configuracoes FROM anon, authenticated;

-- So o master da conta altera, e nunca os IDs do sistema.
CREATE OR REPLACE FUNCTION public.alterar_configuracao(p_chave text, p_valor text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_novo  text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.contasusuarios
                  WHERE userid = auth.uid() AND contaid = v_conta AND papel = 'master') THEN
    RAISE EXCEPTION 'Só o responsável pela conta altera as configurações.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_chave LIKE 'TAREFA_%' THEN
    RAISE EXCEPTION 'Esta configuração é mantida pelo sistema.' USING ERRCODE = 'restrict_violation';
  END IF;

  UPDATE public.configuracoes SET valor = p_valor
   WHERE contaid = v_conta AND chave = p_chave
  RETURNING valor INTO v_novo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Configuração não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN v_novo;
END;
$$;

-- ===========================================================================
-- 6. Permissoes (negadas por padrao).
-- ===========================================================================

REVOKE EXECUTE ON FUNCTION
  public.pessoa_cumpre_conquista(integer, integer, integer),
  public.avaliar_conquistas(integer, integer),
  public.apos_aprovar_entrega(integer)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.listar_trocas(integer),
  public.dia_de_trabalho(integer, integer, date, date, date),
  public.ranking_mensal(integer, integer, integer),
  public.criterio_disponivel(text),
  public.criar_conquista(text, text, text, text, integer, integer, integer, boolean),
  public.pendencias_da_pessoa(integer, date, date),
  public.historico_da_pessoa(integer, integer),
  public.analise_de_tarefas(date, date, integer),
  public.alterar_configuracao(text, text)
TO authenticated;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;
