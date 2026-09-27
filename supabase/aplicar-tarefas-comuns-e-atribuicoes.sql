-- =========================================================================
-- STGame — Tarefas "do sistema" viram comuns; Atribuições da loja com filtro.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes (inclusive
-- aplicar-mapa-da-jornada.sql). Aplique ESTE ARQUIVO ANTES de publicar a
-- versão nova: a aba Atribuições lê por uma função nova (atribuicoes_da_loja).
--
-- Este arquivo é UMA migração só:
--   20260929220000_tarefas_comuns_e_atribuicoes.sql
--
-- O QUE MUDA PARA QUEM JÁ USA:
--   * As 6 tarefas criadas pelo sistema passam a se atribuir à mão e a se
--     desativar como qualquer outra. Nenhuma é recriada: mesmo código interno.
--   * Agenda sem "Atender agendamento" ativa e comunicado sem "Leitura de
--     comunicado" ativa passam a deixar aviso (antes, a Agenda ficava calada).
--   * Com as tarefas ativas, nada muda: provado com 12 combinações de pontos
--     dos comunicados, 0 diferenças.
-- =========================================================================


BEGIN;

-- Tarefas "do sistema" viram tarefas comuns; Atribuições da loja com filtro
-- (28/09/2026, pedidos do Wisley).
--
-- 1. As 6 tarefas que o sistema cria para cada conta (Feedback diário,
--    Leitura de comunicado, Pontos da meta diária, Envio de nota fiscal,
--    Atender agendamento, Guardar mercadoria) passam a ser tarefas comuns:
--    editáveis, desativáveis, apagáveis e atribuíveis à mão. Elas continuam
--    com o MESMO código interno (tarefas.sistema), que nunca muda — é por ele
--    que as rotinas as acham, nunca pelo nome.
--
--    Quem usa essas tarefas hoje (conferido no banco, função por função):
--      * criar_agendamento  -> "Atender agendamento" (sistema = 'modelo_agendamento')
--      * publicar_comunicado -> "Leitura de comunicado" (código em configuracoes,
--                              chave TAREFA_ID_LEITURA): só o PADRÃO de pontos
--                              por ciência dos comunicados novos.
--      As outras quatro não são usadas por rotina nenhuma hoje.
--
--    Rotina que não acha a tarefa (desativada ou apagada) não falha em
--    silêncio: grava um aviso (avisossistema, tipo 'rotina_sem_tarefa'), que
--    aparece no Início e na Saúde.
--
-- 2. atribuicoes_da_loja: a lista da aba "Atribuições da loja" numa consulta
--    só, já agrupada, com filtro e 50 por vez.

-- ---------------------------------------------------------------------------
-- 1a. Saem as duas travas que faziam delas tarefas especiais
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS tarefas_protege_sistema ON public.tarefas;
DROP FUNCTION IF EXISTS public.protege_tarefa_do_sistema();
DROP TRIGGER IF EXISTS tarefasatribuidas_sem_bonus ON public.tarefasatribuidas;
DROP FUNCTION IF EXISTS public.bloqueia_atribuicao_de_bonus();

-- ---------------------------------------------------------------------------
-- 1b. O código interno não muda nunca, e o navegador não inventa código
-- ---------------------------------------------------------------------------
-- As rotinas acham a tarefa pelo código. Se ele pudesse ser trocado ou
-- copiado para outra tarefa, a rotina passaria a achar a tarefa errada.
-- Quem cria as tarefas com código é cria_tarefas_do_sistema, que roda como
-- dono do banco (e não como o usuário logado).
CREATE OR REPLACE FUNCTION public.protege_codigo_da_tarefa()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.sistema IS DISTINCT FROM OLD.sistema THEN
    RAISE EXCEPTION 'O código interno da tarefa não muda: é por ele que as rotinas a encontram.'
      USING ERRCODE = 'restrict_violation';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.sistema IS NOT NULL AND current_user IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'Tarefa nova não recebe código interno.' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.protege_codigo_da_tarefa() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS tarefas_protege_codigo ON public.tarefas;
CREATE TRIGGER tarefas_protege_codigo
  BEFORE INSERT OR UPDATE OF sistema ON public.tarefas
  FOR EACH ROW EXECUTE FUNCTION public.protege_codigo_da_tarefa();

-- ---------------------------------------------------------------------------
-- 1c. "Atender agendamento" pode ser atribuída à mão
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260922300000_agenda.sql), com o diff
-- conferido: sai só a recusa pelo código da tarefa.
CREATE OR REPLACE FUNCTION public.protege_tarefa_da_agenda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF coalesce(current_setting('gamegb.agenda', true), '') = 'sim' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- 28/09/2026: "Atender agendamento" virou tarefa comum e pode ser
    -- atribuída à mão. O que continua só pela Agenda é a atribuição PRESA a
    -- um agendamento.
    IF NEW.agendamentoid IS NOT NULL THEN
      RAISE EXCEPTION 'A tarefa presa a um agendamento nasce sozinha, ao criar o agendamento.' USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.agendamentoid IS NOT NULL OR (TG_OP = 'UPDATE' AND NEW.agendamentoid IS DISTINCT FROM OLD.agendamentoid) THEN
    RAISE EXCEPTION 'Esta tarefa acompanha um agendamento: mude pela Agenda.' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1d. Agenda: sem a tarefa, avisa em vez de calar
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260922300000_agenda.sql), com o diff
-- conferido: muda só a busca da tarefa (agora exige ativa) e o aviso.
CREATE OR REPLACE FUNCTION public.criar_agendamento(
  p_lojaid         integer,
  p_tipoeventoid   integer,
  p_dataevento     timestamptz,
  p_nomecliente    text,
  p_cpf            text    DEFAULT NULL,
  p_telefone       text    DEFAULT NULL,
  p_observacoes    text    DEFAULT NULL,
  p_valor          numeric DEFAULT NULL,
  p_pagamento      text    DEFAULT 'Pendente',
  p_responsavelid  integer DEFAULT NULL,
  p_aceitawhatsapp boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.minha_conta_editavel();
  v_loja   public.lojas%ROWTYPE;
  v_tipo   text;
  v_resp   integer;
  v_cpf    text := public.so_digitos(p_cpf);
  v_tel    text := public.so_digitos(p_telefone);
  v_modelo integer;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_loja FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT nome INTO v_tipo FROM public.tiposevento WHERE tipoeventoid = p_tipoeventoid AND contaid = v_conta AND ativo;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'Escolha o tipo de evento.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(coalesce(p_nomecliente, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o nome do cliente.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dataevento IS NULL OR public.dia_em_sao_paulo(p_dataevento) < public.dia_em_sao_paulo(now()) THEN
    RAISE EXCEPTION 'A data do evento não pode estar no passado.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_cpf IS NOT NULL AND length(v_cpf) <> 11 THEN
    RAISE EXCEPTION 'O CPF precisa ter 11 números.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_tel IS NOT NULL AND length(v_tel) NOT BETWEEN 10 AND 13 THEN
    RAISE EXCEPTION 'Telefone inválido: use DDD e número.' USING ERRCODE = 'check_violation';
  END IF;
  v_resp := coalesce(p_responsavelid, v_loja.responsavelagendamentosid);
  IF v_resp IS NULL THEN
    RAISE EXCEPTION 'Escolha o responsável (a loja não tem responsável pelos agendamentos definido).' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT public.responsavel_valido(v_conta, p_lojaid, v_resp) THEN
    RAISE EXCEPTION 'O responsável precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.agendamentos (contaid, lojaid, nomecliente, cpfcliente, telefonecliente, tipoevento, tipoeventoid,
                                   dataevento, statuspagamento, valor, funcionarioid, observacoes, aceitawhatsapp, registradopor)
  VALUES (v_conta, p_lojaid, btrim(p_nomecliente), v_cpf, v_tel, v_tipo, p_tipoeventoid, p_dataevento,
          coalesce(p_pagamento, 'Pendente'), p_valor, v_resp, nullif(btrim(coalesce(p_observacoes, '')), ''),
          coalesce(p_aceitawhatsapp, false), auth.uid())
  RETURNING agendamentoid INTO v_id;

  -- A tarefa "Atender agendamento" para o responsavel, no dia do evento.
  -- Achada pelo CODIGO interno (nunca pelo nome: renomear nao quebra nada).
  -- Desativada ou apagada: o agendamento nasce sem ela, e isso NAO fica em
  -- silencio (28/09/2026) — vira aviso no Inicio e na Saude.
  SELECT tarefaid INTO v_modelo FROM public.tarefas
   WHERE contaid = v_conta AND sistema = 'modelo_agendamento' AND ativa;
  IF v_modelo IS NULL THEN
    INSERT INTO public.avisossistema (contaid, tipo, texto)
    VALUES (v_conta, 'rotina_sem_tarefa', left(
      'Agenda: o agendamento de ' || btrim(p_nomecliente) || ' (' ||
      to_char(p_dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') ||
      ') foi criado SEM a tarefa de atender, porque a tarefa "Atender agendamento" está desativada ou foi apagada. Reative-a no Catálogo de tarefas.', 300));
  ELSE
    PERFORM set_config('gamegb.agenda', 'sim', true);
    INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataagendamento,
                                          descricaooverride, agendamentoid)
    VALUES (v_conta, v_modelo, v_resp, p_lojaid, 'Unica', p_dataevento,
            public.texto_da_tarefa_agenda(p_dataevento, v_tipo), v_id);
    PERFORM set_config('gamegb.agenda', '', true);
  END IF;

  PERFORM public.registra_agenda(v_conta, p_lojaid, v_id, 'criado', NULL,
                                 to_char(p_dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ' — ' || v_tipo, NULL);
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1e. Comunicados: sem a tarefa de leitura, avisa em vez de calar
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260922400000_rh_comunicados_...), com o
-- diff conferido: muda só o cálculo do padrão de pontos.
CREATE OR REPLACE FUNCTION public.publicar_comunicado(
  p_titulo       text,
  p_conteudo     text,
  p_pontos       integer,
  p_alvo         text,
  p_lojas        integer[] DEFAULT NULL,
  p_funcionarios integer[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_id    integer;
  v_pontos integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_titulo, ''))) = 0 OR length(btrim(coalesce(p_conteudo, ''))) = 0 THEN
    RAISE EXCEPTION 'Preencha o título e o texto.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo NOT IN ('conta', 'lojas', 'funcionarios') THEN
    RAISE EXCEPTION 'Escolha para quem é o comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  -- Pontos: os do comunicado, ou o padrao da tarefa "Leitura de comunicado"
  -- (achada pelo CODIGO guardado em configuracoes, nunca pelo nome). Com a
  -- tarefa desativada ou apagada, o padrao e 0 e isso vira aviso (28/09/2026).
  v_pontos := p_pontos;
  IF v_pontos IS NULL THEN
    SELECT t.pontos INTO v_pontos FROM public.configuracoes c
      JOIN public.tarefas t ON t.tarefaid = nullif(c.valor, '')::integer AND t.contaid = c.contaid
     WHERE c.contaid = v_conta AND c.chave = 'TAREFA_ID_LEITURA' AND t.ativa;
    IF NOT FOUND THEN
      v_pontos := 0;
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      VALUES (v_conta, 'rotina_sem_tarefa', left(
        'Comunicados: "' || btrim(coalesce(p_titulo, '')) || '" foi publicado com 0 ponto por ciência, porque a tarefa "Leitura de comunicado" (que dá o padrão) está desativada ou foi apagada.', 300));
    END IF;
  END IF;
  IF v_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'lojas' AND (coalesce(array_length(p_lojas, 1), 0) = 0
       OR EXISTS (SELECT 1 FROM unnest(p_lojas) x(l)
                   WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = x.l AND contaid = v_conta AND ativa))) THEN
    RAISE EXCEPTION 'Escolha lojas ativas da sua conta.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'funcionarios' AND coalesce(array_length(p_funcionarios, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Escolha pelo menos uma pessoa.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.documentos (contaid, titulo, conteudo, pontosporciencia, alvo, criadopor)
  VALUES (v_conta, btrim(p_titulo), btrim(p_conteudo), v_pontos, p_alvo, auth.uid())
  RETURNING documentoid INTO v_id;

  IF p_alvo = 'lojas' THEN
    INSERT INTO public.documentoslojas (contaid, documentoid, lojaid)
    SELECT DISTINCT v_conta, v_id, x FROM unnest(p_lojas) x;
  END IF;

  -- Destinatarios fixados agora (so ativos).
  IF p_alvo = 'funcionarios' THEN
    PERFORM public.incluir_destinatarios(v_id, p_funcionarios);
  ELSE
    INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
    SELECT v_conta, v_id, fid, now() FROM public.alcance_do_comunicado(v_id) fid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas WHERE documentoid = v_id) THEN
    RAISE EXCEPTION 'Nenhum funcionário ativo recebe este comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. A lista da aba "Atribuições da loja", numa consulta só
-- ---------------------------------------------------------------------------
-- SECURITY INVOKER: a regra de cada tabela vale aqui dentro (conta B não vê
-- nada de A). Uma LINHA é o que a tela mostra: a Semanal com vários dias é
-- uma atribuição por dia no banco e uma linha só aqui (mesma tarefa, mesma
-- pessoa, mesma frequência e mesmo fim) — a mesma regra que a tela usava.
--
-- Filtros (todos opcionais):
--   p_de / p_ate    : dia (no fuso da conta) em que a atribuição foi CRIADA;
--                     início depois do fim é recusado; no máximo 366 dias.
--   p_tarefaid      : uma tarefa.
--   p_funcionarioid : uma pessoa — a dona, ou uma das que podem pegar a
--                     tarefa compartilhada.
--   p_missao        : só missões da equipe.
--   p_encerradas    : inclui as encerradas (a caixinha da tela).
-- Mais recente primeiro; p_limite (até 50) por vez, a partir de p_offset.
CREATE INDEX IF NOT EXISTS tarefasatribuidas_loja_criacao_idx
  ON public.tarefasatribuidas (lojaid, dataatribuicao DESC);

CREATE OR REPLACE FUNCTION public.atribuicoes_da_loja(
  p_lojaid        integer,
  p_encerradas    boolean DEFAULT false,
  p_de            date    DEFAULT NULL,
  p_ate           date    DEFAULT NULL,
  p_tarefaid      integer DEFAULT NULL,
  p_funcionarioid integer DEFAULT NULL,
  p_missao        boolean DEFAULT false,
  p_limite        integer DEFAULT 5,
  p_offset        integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fuso   text := public.meu_hoje()->>'fuso';
  v_limite integer := least(greatest(coalesce(p_limite, 5), 1), 50);
  v_linhas jsonb;
  v_n      integer;
BEGIN
  IF (p_de IS NULL) <> (p_ate IS NULL) THEN
    RAISE EXCEPTION 'Escolha a data inicial e a final (ou nenhuma das duas).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_de > p_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_ate - p_de > 365 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 366 dias.' USING ERRCODE = 'check_violation';
  END IF;

  WITH filtradas AS (
    SELECT ta.*
      FROM public.tarefasatribuidas ta
     WHERE ta.lojaid = p_lojaid
       AND (p_encerradas OR ta.datafimvigencia IS NULL)
       AND (p_tarefaid IS NULL OR ta.tarefaid = p_tarefaid)
       AND (NOT coalesce(p_missao, false) OR (ta.funcionarioid IS NULL AND NOT ta.compartilhada))
       AND (p_funcionarioid IS NULL
            OR ta.funcionarioid = p_funcionarioid
            OR (ta.compartilhada AND EXISTS (SELECT 1 FROM public.tarefascandidatos tc
                                              WHERE tc.atribuicaoid = ta.atribuicaoid
                                                AND tc.funcionarioid = p_funcionarioid)))
       AND (p_de IS NULL OR (ta.dataatribuicao >= (p_de::timestamp AT TIME ZONE v_fuso)
                             AND ta.dataatribuicao < ((p_ate + 1)::timestamp AT TIME ZONE v_fuso)))
  ),
  grupos AS (
    SELECT f.tarefaid,
           f.funcionarioid,
           f.tipofrequencia,
           f.datafimvigencia,
           array_agg(f.atribuicaoid ORDER BY f.atribuicaoid) AS ids,
           array_agg(f.valorfrequencia ORDER BY f.valorfrequencia) FILTER (WHERE f.valorfrequencia IS NOT NULL) AS dias,
           min(f.valorfrequencia) AS valor,
           min(f.dataagendamento) AS dataagendamento,
           min(f.disponivelapartir) AS disponivelapartir,
           bool_or(f.compartilhada) AS compartilhada,
           min(f.horariodisparo) AS horariodisparo,
           max(f.dataatribuicao) AS criadaem,
           max(f.atribuicaoid) AS ultimo
      FROM filtradas f
     GROUP BY f.tarefaid, coalesce(f.funcionarioid::text, 'c' || f.atribuicaoid), f.funcionarioid,
              f.tipofrequencia, f.datafimvigencia
  ),
  pagina AS (
    SELECT g.* FROM grupos g
     ORDER BY g.criadaem DESC NULLS LAST, g.ultimo DESC
     OFFSET greatest(coalesce(p_offset, 0), 0) LIMIT v_limite + 1
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ids', to_jsonb(p.ids),
           'tarefaid', p.tarefaid,
           'titulo', t.titulo,
           'funcionarioid', p.funcionarioid,
           'nome', fu.nomecompleto,
           'compartilhada', p.compartilhada,
           'candidatos', CASE WHEN p.compartilhada THEN
                           (SELECT coalesce(jsonb_agg(fc.nomecompleto ORDER BY fc.nomecompleto), '[]'::jsonb)
                              FROM public.tarefascandidatos tc
                              JOIN public.funcionarios fc ON fc.funcionarioid = tc.funcionarioid
                             WHERE tc.atribuicaoid = p.ids[1]) END,
           'horariodisparo', p.horariodisparo,
           'tipofrequencia', p.tipofrequencia,
           'dias', coalesce(to_jsonb(p.dias), '[]'::jsonb),
           'valor', p.valor,
           'dataagendamento', p.dataagendamento,
           'disponivelapartir', p.disponivelapartir,
           'datafimvigencia', p.datafimvigencia,
           'criadaem', p.criadaem,
           -- O dia da criação já no fuso da conta, escrito dd/mm/aaaa.
           'criadaemdia', to_char(p.criadaem AT TIME ZONE v_fuso, 'DD/MM/YYYY'))
         ORDER BY p.criadaem DESC NULLS LAST, p.ultimo DESC),
         count(*)
    INTO v_linhas, v_n
    FROM pagina p
    LEFT JOIN public.tarefas t ON t.tarefaid = p.tarefaid
    LEFT JOIN public.funcionarios fu ON fu.funcionarioid = p.funcionarioid;

  -- Veio uma a mais do que o limite: há mais para carregar.
  IF v_n > v_limite THEN
    v_linhas := v_linhas - v_limite;
  END IF;
  RETURN jsonb_build_object('linhas', coalesce(v_linhas, '[]'::jsonb), 'temmais', v_n > v_limite);
END;
$$;
REVOKE ALL ON FUNCTION public.atribuicoes_da_loja(integer, boolean, date, date, integer, integer, boolean, integer, integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.atribuicoes_da_loja(integer, boolean, date, date, integer, integer, boolean, integer, integer) TO authenticated;

COMMIT;
