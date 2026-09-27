-- =========================================================================
-- STGame — primeiro acesso "tudo ou nada" e "hoje" na TV é trabalho feito
-- hoje.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes. E aplique ESTE ARQUIVO ANTES de
-- publicar a versão nova: a tela de primeiro acesso usa as funções daqui.
--
-- Este arquivo é UMA migração só:
--   20260929180000_primeiro_acesso_e_tv.sql
--
-- O QUE MUDA PARA QUEM JÁ USA:
--   * Nada nos dados.
--   * Na TV (e no Painel da loja, que é a mesma tela), o Pódio de hoje e a
--     Atividade recente passam a contar o trabalho FEITO hoje, e não o
--     aprovado hoje. O Pódio do mês, o ranking e o fechamento não mudam.
-- =========================================================================


BEGIN;

-- Primeiro acesso "tudo ou nada", e "hoje" na TV é trabalho feito hoje
-- (27/09/2026).

-- ---------------------------------------------------------------------------
-- 1. Primeiro acesso: senha, PIN e consumo do código JUNTOS
-- ---------------------------------------------------------------------------
-- Antes o código era consumido no primeiro passo (CPF + código), ANTES de a
-- pessoa criar a senha. Quem fechasse a tela e perdesse a sessão (outro
-- aparelho, navegador limpo) ficava trancada: sem código e sem senha.
--
-- Agora o primeiro passo só CONFERE o código (sem consumir), e o segundo faz
-- tudo numa transação: grava a senha, grava o PIN e só então marca o código
-- como usado. PIN repetido, pessoa desativada, código vencido: nada é
-- gravado, e o código continua valendo.

-- Confere sem consumir. As mesmas condições de usar_codigo_acesso.
CREATE OR REPLACE FUNCTION public.conferir_codigo_acesso(p_contaid integer, p_cpf text, p_codigohash text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.bot_contexto_confiavel() AND EXISTS (
    SELECT 1
      FROM public.codigosacesso k
      JOIN public.funcionarios f ON f.contaid = k.contaid AND f.funcionarioid = k.funcionarioid AND f.ativo
     WHERE k.contaid = p_contaid
       AND k.codigohash = left(p_codigohash, 64)
       AND k.usadoem IS NULL AND k.canceladoem IS NULL
       AND k.expiraem > now()
       AND f.cpf = regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g')
       AND f.senhahashapp IS NULL AND f.pinhash IS NULL)
$$;
REVOKE ALL ON FUNCTION public.conferir_codigo_acesso(integer, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conferir_codigo_acesso(integer, text, text) TO service_role;

-- Tudo ou nada: é uma função só, então é uma transação só.
CREATE OR REPLACE FUNCTION public.concluir_primeiro_acesso(p_contaid integer, p_cpf text, p_codigohash text,
                                                           p_senhahash text, p_pinhash text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE c record; v_user uuid;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor conclui o primeiro acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF coalesce(p_senhahash, '') = '' OR coalesce(p_pinhash, '') = '' THEN
    RAISE EXCEPTION 'Crie a senha e o PIN.' USING ERRCODE = 'check_violation';
  END IF;

  -- O código travado até o fim: dois toques ao mesmo tempo não usam o mesmo.
  SELECT k.codigoid, k.funcionarioid INTO c
    FROM public.codigosacesso k
    JOIN public.funcionarios f ON f.contaid = k.contaid AND f.funcionarioid = k.funcionarioid AND f.ativo
   WHERE k.contaid = p_contaid
     AND k.codigohash = left(p_codigohash, 64)
     AND k.usadoem IS NULL AND k.canceladoem IS NULL
     AND k.expiraem > now()
     AND f.cpf = regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g')
     AND f.senhahashapp IS NULL AND f.pinhash IS NULL
     FOR UPDATE OF k;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT userid INTO v_user FROM public.contasusuarios
   WHERE contaid = p_contaid AND funcionarioid = c.funcionarioid AND papel = 'colaborador';
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Esta pessoa ainda não tem acesso. Peça ao gestor.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.definir_senha_app(p_contaid, c.funcionarioid, p_senhahash);
  -- PIN repetido levanta "Escolha outro número" e desfaz TUDO, inclusive a
  -- senha: o código continua valendo.
  PERFORM public.definir_pin(p_contaid, c.funcionarioid, p_pinhash, false);
  UPDATE public.codigosacesso SET usadoem = now() WHERE codigoid = c.codigoid;

  RETURN jsonb_build_object('funcionarioid', c.funcionarioid, 'userid', v_user);
END;
$$;
REVOKE ALL ON FUNCTION public.concluir_primeiro_acesso(integer, text, text, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.concluir_primeiro_acesso(integer, text, text, text, text) TO service_role;

-- Para quem JÁ está logado e ainda não tem senha ou PIN (quem consumiu o
-- código pelo caminho antigo): grava o que falta, junto, numa transação. Só
-- preenche o que está VAZIO — trocar senha existente continua exigindo a
-- atual (trocarMinhaSenha).
CREATE OR REPLACE FUNCTION public.completar_senha_e_pin(p_contaid integer, p_funcionarioid integer,
                                                        p_senhahash text, p_pinhash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE f record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor grava senha e PIN.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT senhahashapp IS NULL AS semsenha, pinhash IS NULL AS sempin INTO f
    FROM public.funcionarios WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo
     FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF f.semsenha AND coalesce(p_senhahash, '') = '' THEN
    RAISE EXCEPTION 'Crie a senha.' USING ERRCODE = 'check_violation';
  END IF;
  IF f.sempin AND coalesce(p_pinhash, '') = '' THEN
    RAISE EXCEPTION 'Escolha o PIN.' USING ERRCODE = 'check_violation';
  END IF;
  IF f.semsenha THEN PERFORM public.definir_senha_app(p_contaid, p_funcionarioid, p_senhahash); END IF;
  IF f.sempin THEN PERFORM public.definir_pin(p_contaid, p_funcionarioid, p_pinhash, false); END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.completar_senha_e_pin(integer, integer, text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.completar_senha_e_pin(integer, integer, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. TV: "hoje" é trabalho feito hoje
-- ---------------------------------------------------------------------------
-- O pódio de hoje e a atividade recente passam a seguir a data da ENTREGA
-- (quando o serviço foi feito), como a barra de tarefas já seguia. O pódio do
-- mês continua pela data da aprovação, igual ao ranking mensal e ao
-- fechamento, que não mudam.
-- Parte da versão mais recente (20260929140000), com o diff conferido.
CREATE OR REPLACE FUNCTION public.montar_painel(p_contaid integer, p_lojaid integer, p_tv boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje       date := public.hoje_da_conta(p_contaid);
  v_fuso       text := public.fuso_da_conta(p_contaid);
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
            AND public.dia_no_fuso(ta.dataagendamento, v_fuso) < v_hoje) AS atrasada,
           (SELECT e.statusvalidacao
              FROM public.entregas e
             WHERE e.atribuicaoid = ta.atribuicaoid
               AND e.statusvalidacao IN ('Pendente', 'Aprovada')
               AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
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
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje, v_fuso)
       -- Justificada como "nao se aplica" (pendente ou aceita) nao e tarefa de hoje.
       AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
       -- Passada hoje para quem está trabalhando: sai da lista de quem está de folga.
       AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
       -- Unica entregue num dia anterior ja nao e tarefa de hoje.
       AND NOT (ta.tipofrequencia = 'Unica' AND EXISTS (
             SELECT 1 FROM public.entregas e2
              WHERE e2.atribuicaoid = ta.atribuicaoid
                AND e2.statusvalidacao IN ('Pendente', 'Aprovada')
                AND public.dia_no_fuso(e2.dataenvio, v_fuso) < v_hoje))
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
             public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje AS dehoje
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio
       LIMIT 50
    ) s;

  -- Podio do dia: pontos do TRABALHO FEITO HOJE (data da entrega), ja
  -- aprovado. Antes contava a data da aprovacao: a tarefa de ontem aprovada
  -- hoje entrava no podio de hoje. Na TV, "hoje" e trabalho feito hoje.
  -- (Nao bate, e nao e para bater, com o livro de pontos do dia: o livro
  -- lanca na aprovacao e tem bonus, resgates e estornos. Ver o plano.)
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
         AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
       GROUP BY f.funcionarioid, f.nomecompleto
       ORDER BY sum(e.pontosganhos) DESC, f.nomecompleto
       LIMIT 3
    ) s;

  -- Atividade recente: o trabalho FEITO HOJE (data da entrega) que ja foi
  -- aprovado, o aprovado por ultimo primeiro. Antes seguia a data da
  -- aprovacao, e a tarefa de ontem aprovada hoje aparecia como de hoje.
  SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', titulo, 'pessoa', pessoa,
                                               'pontos', pontos, 'aprovadaem', dataaprovacao,
                                               'enviadaem', dataenvio)
                            ORDER BY dataaprovacao DESC), '[]'::jsonb)
    INTO v_atividade
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataaprovacao, e.dataenvio,
             CASE WHEN p_tv THEN public.nome_curto(f.nomecompleto) ELSE f.nomecompleto END AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
       WHERE e.contaid = p_contaid AND e.lojaid = p_lojaid
         AND e.statusvalidacao = 'Aprovada'
         AND public.dia_no_fuso(e.dataenvio, v_fuso) = v_hoje
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
         AND public.dia_no_fuso(e.dataaprovacao, v_fuso)
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


COMMIT;
