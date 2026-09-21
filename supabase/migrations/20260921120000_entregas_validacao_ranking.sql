-- Fase 5, parte 2: entregas, validacao, estorno e ranking.
-- Decisoes do Wisley em 21/09/2026, registradas em docs/PLANO_MIGRACAO.md.

-- ===========================================================================
-- 0. Correcao de seguranca
--    cria_configuracoes_padrao e cria_tarefas_do_sistema rodam com poder total
--    e nao conferem quem chamou. O Supabase da EXECUTE a anon e authenticated
--    em toda funcao nova, e o REVOKE ... FROM public anterior nao tirava isso.
--    Resultado: qualquer um podia chama-las com o contaid de outro cliente.
--    Agora so o servidor (service_role) executa.
-- ===========================================================================

REVOKE EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cria_tarefas_do_sistema(integer)   FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) TO service_role;
GRANT  EXECUTE ON FUNCTION public.cria_tarefas_do_sistema(integer)   TO service_role;

-- ===========================================================================
-- 1. O dia de um instante, no fuso da loja.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.dia_em_sao_paulo(p_instante timestamptz)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT (p_instante AT TIME ZONE 'America/Sao_Paulo')::date
$$;

-- ===========================================================================
-- 2. Colunas novas em entregas
-- ===========================================================================

ALTER TABLE public.entregas
  ADD COLUMN observacao    text,
  ADD COLUMN dataaprovacao timestamptz,
  ADD COLUMN aprovadopor   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN datarecusa    timestamptz,
  ADD COLUMN recusadopor   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN dataestorno   timestamptz,
  ADD COLUMN estornadopor  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN motivoestorno text;

-- dataenvio passa a ser SEMPRE o envio de verdade. O sistema antigo a
-- sobrescrevia na aprovacao; agora a aprovacao tem coluna propria.
UPDATE public.entregas SET statusvalidacao = 'Pendente' WHERE statusvalidacao IS NULL;
UPDATE public.entregas SET dataenvio = now() WHERE dataenvio IS NULL;
ALTER TABLE public.entregas
  ALTER COLUMN statusvalidacao SET NOT NULL,
  ALTER COLUMN dataenvio SET NOT NULL;

ALTER TABLE public.entregas ADD CONSTRAINT entregas_status_valido
  CHECK (statusvalidacao IN ('Pendente', 'Aprovada', 'Recusada', 'Estornada'));

-- Recusa e estorno sem motivo sao recusados pelo proprio banco.
ALTER TABLE public.entregas ADD CONSTRAINT entregas_recusa_tem_motivo
  CHECK (statusvalidacao <> 'Recusada' OR length(btrim(coalesce(motivorecusa, ''))) > 0);
ALTER TABLE public.entregas ADD CONSTRAINT entregas_estorno_tem_motivo
  CHECK (statusvalidacao <> 'Estornada' OR length(btrim(coalesce(motivoestorno, ''))) > 0);

-- A entrega aponta para a atribuicao de que veio, e as duas tem de concordar
-- em tarefa, pessoa e loja. Entregas de bonus (sem atribuicao) nao entram.
ALTER TABLE public.tarefasatribuidas ADD CONSTRAINT tarefasatribuidas_alvo_da_entrega
  UNIQUE (atribuicaoid, tarefaid, funcionarioid, lojaid);
ALTER TABLE public.entregas ADD CONSTRAINT entregas_atribuicao_fk
  FOREIGN KEY (atribuicaoid, tarefaid, funcionarioid, lojaid)
  REFERENCES public.tarefasatribuidas (atribuicaoid, tarefaid, funcionarioid, lojaid)
  ON DELETE RESTRICT;

-- Sem entrega duplicada: no maximo UMA pendente ou aprovada por atribuicao
-- por dia (fuso de Sao Paulo). Recusada ou estornada libera outra.
CREATE UNIQUE INDEX entregas_uma_por_dia
  ON public.entregas (atribuicaoid, public.dia_em_sao_paulo(dataenvio))
  WHERE statusvalidacao IN ('Pendente', 'Aprovada');

CREATE INDEX entregas_ranking_idx
  ON public.entregas (contaid, lojaid, dataaprovacao)
  WHERE statusvalidacao = 'Aprovada';

-- ===========================================================================
-- 3. Pontos e status so mudam pelas funcoes.
--    O navegador continua LENDO entregas e funcionarios, mas nao grava direto
--    em entregas, nem mexe em saldopontos/pontostotal. Toda mudanca de pontos
--    passa por uma funcao atomica, como manda o CLAUDE.md.
-- ===========================================================================

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.entregas FROM anon, authenticated;

REVOKE INSERT, UPDATE ON public.funcionarios FROM anon, authenticated;
GRANT INSERT (
  funcionarioid, nomecompleto, chatidtelegram, cargo, horarionotificacao, diadefolga,
  verificadorcpf, senhahash, isgestor, nivelacesso, cpf, telefonewhatsapp, setor,
  domingofolgamensal, datainicioafastamento, datafimafastamento, ativo
) ON public.funcionarios TO authenticated;
GRANT UPDATE (
  nomecompleto, chatidtelegram, cargo, horarionotificacao, diadefolga,
  verificadorcpf, senhahash, isgestor, nivelacesso, cpf, telefonewhatsapp, setor,
  domingofolgamensal, datainicioafastamento, datafimafastamento, ativo
) ON public.funcionarios TO authenticated;

-- ===========================================================================
-- 4. Gancho das conquistas (Fase 7). Hoje nao concede nada.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.apos_aprovar_entrega(p_entregaid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Fase 7: conferir e conceder conquistas do funcionario desta entrega.
  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.apos_aprovar_entrega(integer) FROM public, anon, authenticated;

-- ===========================================================================
-- 5. Aprovar
--    Atomica. So aprova entrega Pendente: a linha fica travada durante a
--    operacao, entao dois cliques simultaneos nao creditam duas vezes.
--    Os pontos sao os da tarefa NA HORA da aprovacao (regra do sistema antigo).
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.aprovar_entrega(p_entregaid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.minha_conta_editavel();
  v_entrega public.entregas%ROWTYPE;
  v_pontos  integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_entrega FROM public.entregas
  WHERE entregaid = p_entregaid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_entrega.statusvalidacao <> 'Pendente' THEN
    RAISE EXCEPTION 'Só uma entrega pendente pode ser aprovada. Esta está: %.', v_entrega.statusvalidacao
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT pontos INTO v_pontos FROM public.tarefas
  WHERE tarefaid = v_entrega.tarefaid AND contaid = v_conta;

  UPDATE public.entregas
  SET statusvalidacao = 'Aprovada',
      pontosganhos    = v_pontos,
      dataaprovacao   = now(),
      aprovadopor     = auth.uid()
  WHERE entregaid = p_entregaid;

  UPDATE public.funcionarios
  SET saldopontos = saldopontos + v_pontos,
      pontostotal = coalesce(pontostotal, 0) + v_pontos
  WHERE funcionarioid = v_entrega.funcionarioid AND contaid = v_conta;

  PERFORM public.apos_aprovar_entrega(p_entregaid);

  RETURN v_pontos;
END;
$$;

-- ===========================================================================
-- 6. Recusar — motivo obrigatorio. A tarefa volta a aparecer para a pessoa.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.recusar_entrega(p_entregaid integer, p_motivo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.minha_conta_editavel();
  v_entrega public.entregas%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo da recusa.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_entrega FROM public.entregas
  WHERE entregaid = p_entregaid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_entrega.statusvalidacao <> 'Pendente' THEN
    RAISE EXCEPTION 'Só uma entrega pendente pode ser recusada. Esta está: %.', v_entrega.statusvalidacao
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.entregas
  SET statusvalidacao = 'Recusada',
      motivorecusa    = btrim(p_motivo),
      datarecusa      = now(),
      recusadopor     = auth.uid()
  WHERE entregaid = p_entregaid;
END;
$$;

-- ===========================================================================
-- 7. Estornar — desfaz uma aprovacao. Motivo obrigatorio.
--    Desconta de saldopontos e de pontostotal. O saldo PODE ficar negativo
--    (a pessoa ja trocou os pontos por um premio, por exemplo). Devolve o
--    saldo novo, para a tela avisar quando ficar negativo.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.estornar_entrega(p_entregaid integer, p_motivo text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta   integer := public.minha_conta_editavel();
  v_entrega public.entregas%ROWTYPE;
  v_saldo   integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo do estorno.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_entrega FROM public.entregas
  WHERE entregaid = p_entregaid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entrega não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_entrega.statusvalidacao <> 'Aprovada' THEN
    RAISE EXCEPTION 'Só uma entrega aprovada pode ser estornada. Esta está: %.', v_entrega.statusvalidacao
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.entregas
  SET statusvalidacao = 'Estornada',
      motivoestorno   = btrim(p_motivo),
      dataestorno     = now(),
      estornadopor    = auth.uid()
  WHERE entregaid = p_entregaid;

  UPDATE public.funcionarios
  SET saldopontos = saldopontos - coalesce(v_entrega.pontosganhos, 0),
      pontostotal = coalesce(pontostotal, 0) - coalesce(v_entrega.pontosganhos, 0)
  WHERE funcionarioid = v_entrega.funcionarioid AND contaid = v_conta
  RETURNING saldopontos INTO v_saldo;

  RETURN v_saldo;
END;
$$;

-- ===========================================================================
-- 8. Registrar entrega (enquanto nao existe o bot)
--    So para atribuicao ativa, de uma pessoa, que cai hoje ou esta atrasada.
--    A foto, se houver, precisa estar na pasta <contaid>/<lojaid>/ da propria
--    atribuicao. "Ja aprovada" registra e aprova na mesma transacao.
-- ===========================================================================

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

-- ===========================================================================
-- 9. O que pode ser entregue hoje numa loja (alimenta a tela "Registrar").
--    Roda com a RLS de quem chamou: cada um so ve o proprio.
-- ===========================================================================

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
    AND NOT EXISTS (
      SELECT 1 FROM public.entregas e
      WHERE e.atribuicaoid = ta.atribuicaoid
        AND e.statusvalidacao IN ('Pendente', 'Aprovada')
        AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)
    )
  ORDER BY f.nomecompleto, t.titulo
$$;

-- ===========================================================================
-- 10. Ranking: soma dos pontos aprovados no periodo, pela DATA DA APROVACAO.
--     Sem loja = geral da conta. Os bonus contam (como no podio antigo).
--     A nota hibrida do sistema antigo fica para a Fase 7.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ranking_pontos(p_de date, p_ate date, p_lojaid integer DEFAULT NULL)
RETURNS TABLE (funcionarioid integer, nomecompleto varchar, pontos bigint, entregas bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
  FROM public.entregas e
  JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
  WHERE e.statusvalidacao = 'Aprovada'
    AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN p_de AND p_ate
    AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  GROUP BY f.funcionarioid, f.nomecompleto
  ORDER BY 3 DESC, 2
$$;

-- Permissoes das funcoes novas: so quem esta logado.
REVOKE EXECUTE ON FUNCTION public.registrar_entrega(integer, text, text, boolean) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.aprovar_entrega(integer)            FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.recusar_entrega(integer, text)      FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.estornar_entrega(integer, text)     FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.atribuicoes_para_entregar(integer)  FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.ranking_pontos(date, date, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.registrar_entrega(integer, text, text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.aprovar_entrega(integer)            TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recusar_entrega(integer, text)      TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.estornar_entrega(integer, text)     TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.atribuicoes_para_entregar(integer)  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ranking_pontos(date, date, integer) TO authenticated, service_role;

-- ===========================================================================
-- 11. Gestor da loja e responsavel pelos agendamentos.
--     Substituem as chaves soltas ID_GESTOR_PADRAO e RESPONSAVEL_AGENDAMENTOS_ID.
--     A chave composta (pessoa, loja) garante que a pessoa trabalha ali.
-- ===========================================================================

ALTER TABLE public.lojas
  ADD COLUMN gestorid                  integer,
  ADD COLUMN responsavelagendamentosid integer;

ALTER TABLE public.lojas ADD CONSTRAINT lojas_gestor_trabalha_na_loja
  FOREIGN KEY (gestorid, lojaid)
  REFERENCES public.funcionarioslojas (funcionarioid, lojaid) ON DELETE RESTRICT;

ALTER TABLE public.lojas ADD CONSTRAINT lojas_responsavel_trabalha_na_loja
  FOREIGN KEY (responsavelagendamentosid, lojaid)
  REFERENCES public.funcionarioslojas (funcionarioid, lojaid) ON DELETE RESTRICT;

DELETE FROM public.configuracoes WHERE chave IN ('ID_GESTOR_PADRAO', 'RESPONSAVEL_AGENDAMENTOS_ID');

-- Conta nova deixa de receber as duas chaves.
CREATE OR REPLACE FUNCTION public.cria_configuracoes_padrao(p_contaid integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  INSERT INTO public.configuracoes (contaid, chave, valor, descricao) VALUES
    (p_contaid, 'TAXA_CONVERSAO_PONTO_REAL',     '0.03',  'Quanto vale 1 ponto em reais.'),
    (p_contaid, 'PONTOS_BONUS_FEEDBACK_DIARIO',  '5',     'Pontos de bonus por enviar o feedback do dia.'),
    (p_contaid, 'PONTOS_BONUS_NOTA_FISCAL',      '10',    'Pontos de bonus por enviar uma nota fiscal.'),
    (p_contaid, 'MAX_DIFERENCA_FOTO_SEGUNDOS',   '120',   'Tolerancia, em segundos, entre a hora da foto (EXIF) e o envio.'),
    (p_contaid, 'HORARIO_FECHAMENTO_MENSAL',     '08:00', 'Hora do fechamento mensal do ranking (executa no dia 1).'),
    (p_contaid, 'HORARIO_DELEGACAO_FOLGA',       '09:05', 'Hora da delegacao automatica das tarefas de quem esta de folga.'),
    (p_contaid, 'HORARIO_LEMBRETE_COMUNICADOS',  '09:00', 'Hora do lembrete de comunicados pendentes de leitura.'),
    (p_contaid, 'HORARIO_LEMBRETE_HOJE',         '08:00', 'Hora do lembrete dos agendamentos de hoje.'),
    (p_contaid, 'HORARIO_LEMBRETE_DIARIO_AMANHA','09:00', 'Hora do lembrete dos agendamentos de amanha.'),
    (p_contaid, 'HORARIO_LEMBRETE_SEMANAL',      '08:00', 'Hora do lembrete semanal de agendamentos.'),
    (p_contaid, 'TAREFA_ID_FEEDBACK_DIARIO',           '', 'ID da tarefa de feedback diario. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_ID_LEITURA',                   '', 'ID da tarefa de leitura de comunicado. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_MODELO_AGENDAMENTO_ID',        '', 'ID da tarefa modelo usada ao criar um agendamento.'),
    (p_contaid, 'TAREFA_ID_PONTOS_META',               '', 'ID da tarefa que credita os pontos da meta diaria.'),
    (p_contaid, 'TAREFA_ID_NOTA_FISCAL',               '', 'ID da tarefa de envio de nota fiscal.'),
    (p_contaid, 'TAREFA_ID_GUARDAR_MERCADORIA_MODELO', '', 'ID da tarefa modelo de guardar mercadoria.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

-- O CREATE OR REPLACE mantem as permissoes, mas reforcamos.
REVOKE EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) TO service_role;
