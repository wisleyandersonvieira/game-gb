-- =========================================================================
-- STGame — Tablet: "quem pode aceitar" em cada cartão.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-disponivel-uma-fonte.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929239000_quem_pode_aceitar.sql
--
-- O QUE MUDA: a regra de quem pode pegar uma tarefa vira uma função só, que
-- o aceite e a janela nova do tablet usam. O aceite não muda (30.776 casos
-- comparados antes e depois, 0 diferenças). Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Quem pode aceitar: a janela do tablet e o aceite com a MESMA regra
-- (29/09/2026, pedido do Wisley).
--
-- No tablet, cada cartão ganha um ícone que abre "quem pode aceitar" esta
-- tarefa. A lista não é uma cópia da regra do aceite escrita na tela: a regra
-- saiu de dentro de pegar_tarefa para uma função própria, e as duas coisas
-- perguntam para ela.
--
--   * quem_pode_pegar(conta, tarefa, dia): quem trabalha hoje nesta loja
--     (ativo, ligado à loja, fora de folga e de afastamento) e, dessas, quem
--     PODE pegar (o dono; ou quem está na lista da compartilhada; ou todo
--     mundo, na missão da equipe). Antes esta regra estava escrita dentro de
--     pegar_tarefa, e uma cópia parcial dela em elegiveis_da_tarefa.
--   * rodizio_ultimo(conta, loja): quem pegou a última tarefa disputada da
--     loja — o coração do rodízio, antes dentro de rodizio_espera.
--   * pegar_tarefa, elegiveis_da_tarefa e rodizio_espera passam a usar as duas.
--     Nenhum comportamento muda (a prova compara cada pessoa x cada tarefa,
--     antes e depois).
--   * quem_pode_aceitar(conta, tarefa): o que a janela mostra — os nomes (só
--     o primeiro nome e a inicial), ou "qualquer pessoa da loja" na missão, e
--     quem está esperando o rodízio, com os minutos que faltam.
--   * visao_fila: cada tarefa para pegar já vem com a lista, na MESMA resposta
--     que o tablet já carrega. Nenhuma pergunta a mais ao banco.

-- ---------------------------------------------------------------------------
-- 1. A regra de quem pode pegar
-- ---------------------------------------------------------------------------
-- Uma linha por pessoa que TRABALHA HOJE na loja da tarefa; "pode" diz se
-- ela pode pegar esta tarefa. Interna: recebe a conta.
CREATE OR REPLACE FUNCTION public.quem_pode_pegar(p_contaid integer, p_atribuicaoid integer, p_dia date)
RETURNS TABLE (funcionarioid integer, nome text, pode boolean)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH t AS (
    SELECT ta.lojaid, ta.funcionarioid AS dono,
           EXISTS (SELECT 1 FROM public.tarefascandidatos c
                    WHERE c.contaid = p_contaid AND c.atribuicaoid = ta.atribuicaoid) AS temlista
      FROM public.tarefasatribuidas ta
     WHERE ta.contaid = p_contaid AND ta.atribuicaoid = p_atribuicaoid
  )
  SELECT f.funcionarioid,
         public.nome_curto(f.nomecompleto),
         CASE WHEN t.dono IS NOT NULL THEN t.dono = f.funcionarioid
              WHEN t.temlista THEN EXISTS (SELECT 1 FROM public.tarefascandidatos c
                                            WHERE c.contaid = p_contaid AND c.atribuicaoid = p_atribuicaoid
                                              AND c.funcionarioid = f.funcionarioid)
              ELSE true END
    FROM t
    JOIN public.funcionarioslojas fl ON fl.contaid = p_contaid AND fl.lojaid = t.lojaid AND fl.ativo
    JOIN public.funcionarios f       ON f.contaid = p_contaid AND f.funcionarioid = fl.funcionarioid AND f.ativo
   WHERE public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, p_dia)
$$;
REVOKE ALL ON FUNCTION public.quem_pode_pegar(integer, integer, date) FROM public, anon, authenticated;

-- Quem pegou a última tarefa disputada desta loja. Aceite revogado não conta.
CREATE OR REPLACE FUNCTION public.rodizio_ultimo(p_contaid integer, p_lojaid integer)
RETURNS TABLE (funcionarioid integer, aceitoem timestamptz)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT a.funcionarioid, a.aceitoem
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.contaid = a.contaid AND ta.atribuicaoid = a.atribuicaoid
   WHERE a.contaid = p_contaid AND ta.lojaid = p_lojaid
     AND a.revogadoem IS NULL AND ta.funcionarioid IS NULL
   ORDER BY a.aceitoem DESC, a.aceiteid DESC
   LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.rodizio_ultimo(integer, integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. O aceite, a contagem e o rodízio perguntam para elas
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260928100700_rodizio_no_aceite.sql). Conta
-- quem pode pegar (a tranca do rodízio nunca deixa a loja parada). O dia é o
-- da conta (o lugar único), não mais São Paulo fixo.
CREATE OR REPLACE FUNCTION public.elegiveis_da_tarefa(p_contaid integer, p_atribuicaoid integer)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::integer
    FROM public.quem_pode_pegar(p_contaid, p_atribuicaoid, public.hoje_da_conta(p_contaid)) q
   WHERE q.pode
$$;
REVOKE ALL ON FUNCTION public.elegiveis_da_tarefa(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.elegiveis_da_tarefa(integer, integer) TO service_role;

-- Parte da versão mais recente (20260928100700_rodizio_no_aceite.sql), com o
-- diff conferido: "quem pegou a última" vem de rodizio_ultimo.
CREATE OR REPLACE FUNCTION public.rodizio_espera(p_contaid integer, p_lojaid integer,
                                                 p_funcionarioid integer, p_atribuicaoid integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_min    integer;
  v_dono   integer;
  v_ultimo record;
  v_falta  integer;
BEGIN
  SELECT coalesce(nullif(btrim(valor), '')::integer, 0) INTO v_min
    FROM public.configuracoes
   WHERE contaid = p_contaid AND chave = 'MINUTOS_RODIZIO_ACEITE';
  IF coalesce(v_min, 0) <= 0 THEN
    RETURN 0;                                   -- rodízio desligado
  END IF;

  SELECT ta.funcionarioid INTO v_dono
    FROM public.tarefasatribuidas ta
   WHERE ta.atribuicaoid = p_atribuicaoid AND ta.contaid = p_contaid;
  IF NOT FOUND OR v_dono IS NOT NULL THEN
    RETURN 0;                                   -- tarefa com dono único: não se aplica
  END IF;

  -- Quem pegou a última tarefa disputada desta loja. Aceite revogado não
  -- conta: quem teve o aceite desfeito não "pegou".
  SELECT u.funcionarioid, u.aceitoem INTO v_ultimo FROM public.rodizio_ultimo(p_contaid, p_lojaid) u;

  IF NOT FOUND OR v_ultimo.funcionarioid IS DISTINCT FROM p_funcionarioid THEN
    RETURN 0;                                   -- não é a última pessoa
  END IF;

  v_falta := ceil(extract(epoch FROM (v_ultimo.aceitoem + make_interval(mins => v_min)) - now()))::integer;
  IF v_falta <= 0 THEN
    RETURN 0;                                   -- o tempo já passou
  END IF;

  -- A trava nunca deixa a loja parada: sozinha, ela pega na hora.
  IF public.elegiveis_da_tarefa(p_contaid, p_atribuicaoid) <= 1 THEN
    RETURN 0;
  END IF;

  RETURN v_falta;
END;
$$;
REVOKE ALL ON FUNCTION public.rodizio_espera(integer, integer, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.rodizio_espera(integer, integer, integer, integer) TO service_role;

-- Parte da versão mais recente (20260929140000_hoje_da_conta.sql), com o diff
-- conferido: as duas verificações de pessoa viram uma pergunta a
-- quem_pode_pegar, com as MESMAS mensagens e na mesma ordem.
CREATE OR REPLACE FUNCTION public.pegar_tarefa(p_atribuicaoid integer, p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_quem text;
  v_conta integer := public.minha_conta_editavel();
  v_hoje  date    := public.hoje_da_conta(v_conta);
  m       public.tarefasatribuidas%ROWTYPE;
  v_pode  boolean;
  v_nova  integer;
  v_espera integer;
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
  IF NOT public.tarefa_cai_no_dia(m.tipofrequencia, m.valorfrequencia, m.dataagendamento, v_hoje, public.fuso_da_conta(v_conta)) THEN
    RAISE EXCEPTION 'Esta tarefa não vale para hoje.' USING ERRCODE = 'check_violation';
  END IF;
  -- Antes da hora combinada ninguém pega. A hora é a da EMPRESA, convertida
  -- aqui no banco: o tablet não opina sobre que horas são.
  IF m.disponivelapartir IS NOT NULL
     AND public.instante_na_conta(v_conta, v_hoje, m.disponivelapartir) > now() THEN
    RAISE EXCEPTION 'Esta tarefa libera às %.', to_char(m.disponivelapartir, 'HH24"h"MI')
      USING ERRCODE = 'check_violation';
  END IF;
  IF m.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(v_conta, p_atribuicaoid) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  -- QUEM PODE PEGAR: a regra mora em quem_pode_pegar (29/09/2026). A janela
  -- "quem pode aceitar" do tablet pergunta para a mesma função.
  SELECT q.pode INTO v_pode
    FROM public.quem_pode_pegar(v_conta, p_atribuicaoid, v_hoje) q
   WHERE q.funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Só quem trabalha hoje nesta loja pode pegar a tarefa.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT v_pode THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Rodízio: quem pegou a última tarefa disputada desta loja espera um pouco
  -- antes de pegar outra. Só vale para tarefa sem dono, e nunca deixa a loja
  -- parada (ver rodizio_espera).
  v_espera := public.rodizio_espera(v_conta, m.lojaid, p_funcionarioid, p_atribuicaoid);
  IF v_espera > 0 THEN
    RAISE EXCEPTION 'Você pegou a última tarefa. Esta libera para você em % min.',
      greatest(1, ceil(v_espera / 60.0)::integer) USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
  VALUES (v_conta, p_atribuicaoid, v_hoje, p_funcionarioid, public.canal_atual())
  ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  IF NOT FOUND THEN
    -- Com o NOME: no balcao, "ja foi pega" sem dizer por quem deixa a pessoa
    -- procurando o que nao existe.
    SELECT public.nome_curto(f.nomecompleto) INTO v_quem
      FROM public.missoesaceites a
      JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid AND f.contaid = v_conta
     WHERE a.contaid = v_conta AND a.atribuicaoid = p_atribuicaoid AND a.dia = v_hoje
       AND a.revogadoem IS NULL;
    RAISE EXCEPTION 'Esta tarefa já foi pega hoje por %.', coalesce(v_quem, 'outra pessoa')
      USING ERRCODE = 'unique_violation';
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
REVOKE ALL ON FUNCTION public.pegar_tarefa(integer, integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.pegar_tarefa(integer, integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. O que a janela do tablet mostra
-- ---------------------------------------------------------------------------
-- { "todos": true se é missão da equipe (qualquer pessoa da loja),
--    "pessoas": [{ "nome": "Ana C.", "esperamin": 0 }] em ordem alfabética
--               (vazio na missão da equipe),
--    "esperando": [{ "nome": "Ana C.", "esperamin": 6 }] — quem está no
--               rodízio, com os minutos que faltam }
-- Só o primeiro nome e a inicial. Interna: recebe a conta.
CREATE OR REPLACE FUNCTION public.quem_pode_aceitar(p_contaid integer, p_atribuicaoid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_loja   integer;
  v_dono   integer;
  v_todos  boolean;
  v_podem  jsonb;
  v_quem   integer;
  v_espera integer := 0;
  v_min    integer;
BEGIN
  SELECT ta.lojaid, ta.funcionarioid,
         ta.funcionarioid IS NULL AND NOT EXISTS (SELECT 1 FROM public.tarefascandidatos c
                                                   WHERE c.contaid = p_contaid AND c.atribuicaoid = ta.atribuicaoid)
    INTO v_loja, v_dono, v_todos
    FROM public.tarefasatribuidas ta
   WHERE ta.contaid = p_contaid AND ta.atribuicaoid = p_atribuicaoid;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- A regra, perguntada UMA vez.
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', q.funcionarioid, 'nome', q.nome)
                            ORDER BY q.nome, q.funcionarioid), '[]'::jsonb)
    INTO v_podem
    FROM public.quem_pode_pegar(p_contaid, p_atribuicaoid, public.hoje_da_conta(p_contaid)) q
   WHERE q.pode;

  -- O rodízio só pode segurar UMA pessoa: a que pegou a última tarefa
  -- disputada. Pergunta a rodizio_espera, a mesma função que o aceite usa.
  IF v_dono IS NULL THEN
    SELECT u.funcionarioid INTO v_quem FROM public.rodizio_ultimo(p_contaid, v_loja) u;
    IF v_quem IS NOT NULL AND v_podem @> jsonb_build_array(jsonb_build_object('id', v_quem)) THEN
      v_espera := public.rodizio_espera(p_contaid, v_loja, v_quem, p_atribuicaoid);
    END IF;
  END IF;
  v_min := CASE WHEN v_espera > 0 THEN greatest(1, ceil(v_espera / 60.0)::integer) ELSE 0 END;

  -- Sem o número da pessoa: o tablet recebe só o nome curto.
  RETURN jsonb_build_object(
    'todos', v_todos,
    'pessoas', CASE WHEN v_todos THEN '[]'::jsonb ELSE (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'nome', e->>'nome',
               'esperamin', CASE WHEN (e->>'id')::integer = v_quem THEN v_min ELSE 0 END) ORDER BY n), '[]'::jsonb)
        FROM jsonb_array_elements(v_podem) WITH ORDINALITY x(e, n)) END,
    'esperando', CASE WHEN v_min > 0 THEN (
      SELECT jsonb_agg(jsonb_build_object('nome', e->>'nome', 'esperamin', v_min))
        FROM jsonb_array_elements(v_podem) e WHERE (e->>'id')::integer = v_quem) ELSE '[]'::jsonb END);
END;
$$;
REVOKE ALL ON FUNCTION public.quem_pode_aceitar(integer, integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. A fila do tablet já traz a lista, na mesma resposta
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260928100100_visao_do_tablet.sql), com o
-- diff conferido: cada tarefa "para pegar" ganha "podem". Todos os caminhos
-- do tablet (abrir, pegar, entregar) devolvem a fila por aqui.
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
  RETURN (SELECT coalesce(jsonb_agg(
                   to_jsonb(f) || CASE WHEN f.situacao = 'para_pegar'
                                       THEN jsonb_build_object('podem', public.quem_pode_aceitar(p_contaid, f.atribuicaoid))
                                       ELSE '{}'::jsonb END), '[]'::jsonb)
            FROM public.fila_da_loja(p_lojaid) f);
END;
$$;
REVOKE ALL ON FUNCTION public.visao_fila(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_fila(integer, integer) TO service_role;

COMMIT;
