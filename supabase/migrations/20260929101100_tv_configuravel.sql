-- A TV passa a ser configurável por loja, e ganha dois blocos novos.
--
-- O gestor marca o que cada TV mostra: duas faixas (barra de tarefas, meta do
-- dia) e seis colunas (para fazer, em andamento, esperando o gestor, atividade
-- recente, pódio de hoje, pódio do mês).
--
-- DAS OITO, DUAS NÃO EXISTIAM prontas para a TV buscar: "em andamento" (só
-- existia na fila do tablet, que o visitante sem login não alcança) e "pódio
-- do mês" (havia só o de hoje). As duas entram em `montar_painel`, que é a
-- MESMA consulta que a TV já faz — ela continua fazendo UMA ida, não oito.
--
-- A configuração também vai na mesma resposta, pelo mesmo motivo.
--
-- COMPATIBILIDADE: as lojas que já existem começam com o conjunto que a TV
-- mostra hoje, então nada muda sem o gestor mandar.

-- ---------------------------------------------------------------------------
-- 1. O que cada loja mostra
-- ---------------------------------------------------------------------------
ALTER TABLE public.lojas
  ADD COLUMN IF NOT EXISTS tvblocos   jsonb,
  ADD COLUMN IF NOT EXISTS tvsegundos integer NOT NULL DEFAULT 60;

ALTER TABLE public.lojas DROP CONSTRAINT IF EXISTS lojas_tvsegundos_valido;
ALTER TABLE public.lojas ADD  CONSTRAINT lojas_tvsegundos_valido
  CHECK (tvsegundos IN (30, 60, 120));

COMMENT ON COLUMN public.lojas.tvblocos IS
  'Quais blocos a TV desta loja mostra. Vazio = o conjunto padrão (o que a TV mostrava antes de 25/09/2026).';

-- O conjunto padrão é EXATAMENTE o que a TV mostrava até aqui: as duas faixas,
-- e as colunas "para fazer", "esperando o gestor" e "pódio de hoje".
CREATE OR REPLACE FUNCTION public.tv_blocos_padrao()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT '{"barra": true, "meta": true,
           "parafazer": true, "emandamento": false, "emvalidacao": true,
           "atividade": false, "podiohoje": true, "podiomes": false}'::jsonb
$$;

REVOKE ALL ON FUNCTION public.tv_blocos_padrao() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.tv_blocos_padrao() TO authenticated, service_role;

-- O que a loja mostra, já resolvido: nunca devolve vazio.
--
-- Se alguém desmarcar tudo, a TV volta ao conjunto padrão em vez de ficar em
-- branco — uma TV apagada no salão é pior do que uma TV mostrando o básico.
CREATE OR REPLACE FUNCTION public.tv_blocos_da_loja(p_contaid integer, p_lojaid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_blocos jsonb;
  v_valores boolean;
  v_algum  boolean;
BEGIN
  SELECT tvblocos, mostrarvalorestv INTO v_blocos, v_valores
    FROM public.lojas WHERE lojaid = p_lojaid AND contaid = p_contaid;

  -- Alguma coluna marcada? Só as faixas não fazem uma tela.
  SELECT coalesce(bool_or((v_blocos->>k)::boolean), false) INTO v_algum
    FROM unnest(ARRAY['parafazer', 'emandamento', 'emvalidacao',
                      'atividade', 'podiohoje', 'podiomes']) k;

  IF v_blocos IS NULL OR NOT v_algum THEN
    v_blocos := public.tv_blocos_padrao();
  END IF;

  -- "Mostrar valores em R$" mora aqui agora, e só faz sentido com a meta.
  RETURN v_blocos || jsonb_build_object(
    'valores', coalesce(v_valores, false) AND coalesce((v_blocos->>'meta')::boolean, false));
END;
$$;

REVOKE ALL ON FUNCTION public.tv_blocos_da_loja(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.tv_blocos_da_loja(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. O gestor salva o que a TV mostra
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_tv_da_loja(
  p_lojaid   integer,
  p_blocos   jsonb,
  p_segundos integer,
  p_valores  boolean
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_limpo jsonb   := '{}'::jsonb;
  k       text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF coalesce(p_segundos, 60) NOT IN (30, 60, 120) THEN
    RAISE EXCEPTION 'O tempo da troca é 30, 60 ou 120 segundos.' USING ERRCODE = 'check_violation';
  END IF;

  -- Só as chaves que a gente conhece entram: o navegador não inventa bloco.
  FOREACH k IN ARRAY ARRAY['barra', 'meta', 'parafazer', 'emandamento',
                           'emvalidacao', 'atividade', 'podiohoje', 'podiomes'] LOOP
    v_limpo := v_limpo || jsonb_build_object(k, coalesce((p_blocos->>k)::boolean, false));
  END LOOP;

  UPDATE public.lojas
     SET tvblocos = v_limpo,
         tvsegundos = coalesce(p_segundos, 60),
         mostrarvalorestv = coalesce(p_valores, false)
   WHERE lojaid = p_lojaid AND contaid = v_conta;
END;
$$;

REVOKE ALL ON FUNCTION public.salvar_tv_da_loja(integer, jsonb, integer, boolean) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.salvar_tv_da_loja(integer, jsonb, integer, boolean) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Os dois blocos que faltavam, na MESMA consulta
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260924100000), com o diff conferido.
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
  v_andamento  jsonb;
  v_podiomes   jsonb;
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
       -- Passada hoje para quem está trabalhando: sai da lista de quem está de folga.
       AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
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

  -- EM ANDAMENTO: quem pegou e ainda nao entregou. A TV precisa disto para a
  -- coluna do mesmo nome; antes so existia na fila do tablet, que o visitante
  -- sem login nao alcanca.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pegaem', pegaem)
                            ORDER BY pegaem), '[]'::jsonb)
    INTO v_andamento
    FROM (
      SELECT t.titulo, a.aceitoem AS pegaem,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.missoesaceites a
        JOIN public.tarefasatribuidas ta ON ta.contaid = a.contaid AND ta.atribuicaoid = a.atribuicaoid
        JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
        JOIN public.funcionarios f       ON f.funcionarioid = a.funcionarioid AND f.contaid = p_contaid
       WHERE a.contaid = p_contaid AND ta.lojaid = p_lojaid
         AND a.dia = v_hoje AND a.revogadoem IS NULL
         -- Ja entregue sai daqui: vira "esperando o gestor" ou "feita".
         AND NOT EXISTS (SELECT 1 FROM public.entregas e
                          WHERE e.contaid = p_contaid
                            AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                            AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
       ORDER BY a.aceitoem
       LIMIT 10
    ) s;

  -- PODIO DO MES: pontos aprovados no mes, nesta loja. O pódio de hoje ja
  -- existia; este e o outro bloco que a TV passou a poder mostrar.
  SELECT coalesce(jsonb_agg(jsonb_build_object('pessoa', pessoa, 'pontos', pontos)
                            ORDER BY pontos DESC, pessoa), '[]'::jsonb)
    INTO v_podiomes
    FROM (
      SELECT CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa,
             sum(e.pontosganhos)::integer AS pontos
        FROM public.entregas e
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = p_contaid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_em_sao_paulo(e.dataaprovacao)
             BETWEEN date_trunc('month', v_hoje)::date AND v_hoje
       GROUP BY 1
       ORDER BY 2 DESC
       LIMIT 5
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
    'emandamento',  v_andamento,
    'podiomes',     v_podiomes,
    'atividade',    v_atividade,
    'meta',         public.meta_para_painel(p_contaid, p_lojaid, p_tv),
    'agenda',       public.agenda_para_painel(p_contaid, p_lojaid, p_tv)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. A TV recebe a configuração junto com os dados
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260921130000), com o diff conferido.
CREATE OR REPLACE FUNCTION public.painel_da_tv(p_codigo text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_link public.linkstv%ROWTYPE;
BEGIN
  IF p_codigo IS NULL OR length(p_codigo) <> 64 THEN
    RETURN jsonb_build_object('disponivel', false);
  END IF;

  SELECT k.* INTO v_link
    FROM public.linkstv k
    JOIN public.lojas  l ON l.lojaid = k.lojaid AND l.contaid = k.contaid
    JOIN public.contas c ON c.contaid = k.contaid
   WHERE k.tokenhash = encode(sha256(convert_to(p_codigo, 'UTF8')), 'hex')
     AND k.revogadoem IS NULL
     AND l.ativa
     AND c.status = 'ativa';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('disponivel', false);
  END IF;

  UPDATE public.linkstv
     SET ultimouso = now()
   WHERE linktvid = v_link.linktvid
     AND (ultimouso IS NULL OR ultimouso < now() - interval '1 minute');

  -- A CONFIGURACAO VAI JUNTO, na mesma resposta: a TV nao faz uma segunda ida
  -- so para saber o que mostrar, e reflete a mudanca do gestor na atualizacao
  -- seguinte, sem ninguem tocar nela.
  RETURN public.montar_painel(v_link.contaid, v_link.lojaid, true)
         || jsonb_build_object(
              'disponivel', true,
              'config', jsonb_build_object(
                'blocos',   public.tv_blocos_da_loja(v_link.contaid, v_link.lojaid),
                'segundos', coalesce((SELECT tvsegundos FROM public.lojas
                                       WHERE lojaid = v_link.lojaid
                                         AND contaid = v_link.contaid), 60)));
END;
$$;

REVOKE ALL ON FUNCTION public.painel_da_tv(text) FROM public, authenticated;
GRANT  EXECUTE ON FUNCTION public.painel_da_tv(text) TO anon, authenticated, service_role;
