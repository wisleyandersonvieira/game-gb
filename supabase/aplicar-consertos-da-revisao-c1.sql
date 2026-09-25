-- =========================================================================
-- STGame — consertos da revisão adversarial da parte C1, e a /saude passando
-- a conferir a ASSINATURA das funções (nome + parâmetros).
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique a parte A, a B1, a C e o "quem fez no tablet" antes desta.
--
-- Este arquivo junta TRÊS migrações, nesta ordem:
--   20260929100100_consertos_revisao_c1.sql
--   20260929100300_saude_confere_assinatura.sql
--   20260929100400_conta_cancelada_e_limite_da_foto.sql
-- =========================================================================

BEGIN;

-- =========================================================================
-- 20260929100100_consertos_revisao_c1.sql
-- =========================================================================
-- Etapa 1.12, parte C1 — consertos da revisão adversarial (25/09/2026).
--
-- Um segundo agente tentou quebrar o celular do colaborador. Não achou
-- vazamento entre contas nem leitura de dado de colega. Achou o que segue,
-- tudo dentro da própria conta — e a maior parte é a mesma falha que o tablet
-- já tinha corrigido em 20260928100200: CONFIAR NO NÚMERO QUE O NAVEGADOR
-- MANDA.
--
-- 1. eu_entregar não conferia se a tarefa ainda vale hoje. Provado: tarefa
--    desativada pelo gestor, loja desativada, dia de folga e vínculo com a
--    loja desligado — o tablet recusava os quatro, o celular aceitava os
--    quatro, e o gestor aprovava e pagava.
-- 2. eu_tarefas mostrava tarefa de loja desativada, de dia de folga e de
--    vínculo desligado.
-- 3. Só eu_inicio conferia se a pessoa continua ativa. As outras três
--    dependiam de uma tranca única, fora do banco.
-- 4. O tablet nem mandava a impressão digital da imagem: por ali a mesma foto
--    provava duas tarefas.
--
-- A conferência da foto (impressão digital e hora) saiu do navegador e foi
-- para o servidor; isso está em src/servidor/fotodaentrega.ts.

-- ---------------------------------------------------------------------------
-- Quem pode usar a visão do celular: existe, é da conta e está ativa.
-- Uma regra, um lugar só — as quatro funções passam por aqui.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eu_confere_pessoa(p_contaid integer, p_funcionarioid integer)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                  WHERE f.contaid = p_contaid AND f.funcionarioid = p_funcionarioid AND f.ativo) THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.eu_confere_pessoa(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_confere_pessoa(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- eu_tarefas: as mesmas condições da fila do tablet, para a lista não mostrar
-- o que a entrega vai recusar.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eu_tarefas(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', x.atribuicaoid,
             'titulo',       x.titulo,
             'pontos',       x.pontos,
             'loja',         x.loja,
             'pegaem',       x.pegaem,
             'situacao',     x.situacao) ORDER BY x.pegaem NULLS LAST, x.titulo), '[]'::jsonb)
      FROM (
        SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome AS loja, a.aceitoem AS pegaem,
               CASE WHEN e.entregaid IS NULL THEN 'a_fazer'
                    WHEN e.statusvalidacao = 'Pendente'  THEN 'esperando'
                    WHEN e.statusvalidacao = 'Aprovada'  THEN 'aprovada'
                    ELSE 'recusada' END AS situacao
          FROM public.tarefasatribuidas ta
          JOIN public.tarefas t  ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
                                AND coalesce(t.ativa, true)
          -- Loja desativada não gera mais tarefa: era LEFT JOIN e passava.
          JOIN public.lojas l    ON l.lojaid = ta.lojaid AND l.contaid = p_contaid AND l.ativa
          JOIN public.funcionarios fu ON fu.funcionarioid = p_funcionarioid AND fu.contaid = p_contaid
          LEFT JOIN public.missoesaceites a
                 ON a.contaid = p_contaid AND a.novaatribuicaoid = ta.atribuicaoid AND a.revogadoem IS NULL
          LEFT JOIN LATERAL (
            SELECT e2.entregaid, e2.statusvalidacao FROM public.entregas e2
             WHERE e2.contaid = p_contaid AND e2.atribuicaoid = ta.atribuicaoid
               AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e2.dataenvio) = v_hoje)
             ORDER BY e2.dataenvio DESC LIMIT 1) e ON true
         WHERE ta.contaid = p_contaid
           AND ta.funcionarioid = p_funcionarioid
           AND ta.datafimvigencia IS NULL
           AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje)
           AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
           AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
           -- Folga, afastamento e vínculo com a loja: as mesmas condições da
           -- fila do tablet.
           AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                      fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
           AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                        WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid
                          AND fl.lojaid = ta.lojaid AND fl.ativo)
      ) x);
END;
$$;

REVOKE ALL ON FUNCTION public.eu_tarefas(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_tarefas(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- eu_entregar: a tarefa tem de ESTAR NA FILA DE HOJE, como no tablet.
--
-- A fila devolve a atribuição ORIGINAL; quando a pessoa pegou uma tarefa
-- compartilhada, quem entrega é a CÓPIA dela, que aparece na fila como
-- `entregarid`. Por isso os dois lados são aceitos.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eu_entregar(p_contaid integer, p_funcionarioid integer,
                                              p_atribuicaoid integer, p_caminho text,
                                              p_observacao text, p_fotoidunico text,
                                              p_semhorafoto boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_lojaid integer;
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT ta.lojaid INTO v_lojaid
    FROM public.tarefasatribuidas ta
   WHERE ta.atribuicaoid = p_atribuicaoid AND ta.contaid = p_contaid
     AND ta.funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa não é sua.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, v_lojaid, 'colaborador');

  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(v_lojaid) f
                  WHERE (f.atribuicaoid = p_atribuicaoid OR f.entregarid = p_atribuicaoid)
                    AND f.situacao <> 'feita') THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN public.registrar_entrega(p_atribuicaoid, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

REVOKE ALL ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
  TO service_role;

-- ---------------------------------------------------------------------------
-- eu_extrato: passa a conferir a pessoa como as outras. Antes, o extrato de
-- quem foi desligado ainda abria se a tranca de fora falhasse.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eu_extrato(p_contaid integer, p_funcionarioid integer,
                                             p_de date, p_ate date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN jsonb_build_object(
    'saldo', (SELECT saldopontos FROM public.funcionarios
               WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid),
    'linhas', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'quando', m.datamovimento,
               'pontos', m.pontos,
               'tipo',   m.tipo,
               'descricao', m.descricao) ORDER BY m.datamovimento DESC, m.movimentoid DESC), '[]'::jsonb)
        FROM public.movimentospontos m
       WHERE m.contaid = p_contaid AND m.funcionarioid = p_funcionarioid
         AND public.dia_em_sao_paulo(m.datamovimento) BETWEEN p_de AND p_ate));
END;
$$;

REVOKE ALL ON FUNCTION public.eu_extrato(integer, integer, date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_extrato(integer, integer, date, date) TO service_role;

-- ---------------------------------------------------------------------------
-- O MESMO buraco da foto existia no tablet: visao_entregar não recebia a
-- impressão digital, então a mesma foto provava duas tarefas por ali. Agora os
-- dois caminhos passam a prova que o servidor tirou do arquivo.
--
-- Partiu da versão mais recente (20260928100200), com o diff conferido: só
-- entram os dois parâmetros novos, repassados ao registrar_entrega.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.visao_entregar(integer, integer, integer, integer, text, text);

CREATE OR REPLACE FUNCTION public.visao_entregar(p_contaid integer, p_lojaid integer,
                                                 p_funcionarioid integer, p_atribuicaoid integer,
                                                 p_caminho text, p_observacao text,
                                                 p_fotoidunico text DEFAULT NULL,
                                                 p_semhorafoto boolean DEFAULT false)
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

  RETURN public.registrar_entrega(v_alvo, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

REVOKE ALL ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text, text, boolean)
  TO service_role;

-- ---------------------------------------------------------------------------
-- O /saude passa a cobrar também a função nova. Partiu da versão mais recente
-- (20260929100000), com o diff conferido.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_abrir_ex', 'tentativa_fechar', 'acesso_por_email',
    'definir_senha_gestor', 'marcar_senha_amao', 'erros_de_login',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado',
    'pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
    'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa', 'tarefa_unica_ja_cumprida',
    'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar',
    'fechamento_valendo', 'ficha_dos_tablets', 'registrar_evento_acesso_loja',
    'rodizio_espera', 'elegiveis_da_tarefa',
    -- Etapa 1.12 C1: o celular do colaborador.
    'eu_inicio', 'eu_tarefas', 'eu_entregar', 'eu_extrato', 'eu_confere_pessoa'
  ];
  v_faltando text[];
  v_tabelas  text[];
  v_chaves   text[];
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
                      'tarefascandidatos', 'acessoslojaeventos']) t
   WHERE to_regclass('public.' || t) IS NULL;

  -- Configuração que não chegou em alguma conta: foi assim que a seção
  -- "Aceite de tarefas" apareceu vazia em 25/09/2026.
  SELECT coalesce(array_agg(DISTINCT k ORDER BY k), ARRAY[]::text[]) INTO v_chaves
    FROM public.contas c
    CROSS JOIN unnest(ARRAY['MINUTOS_RODIZIO_ACEITE', 'MINUTOS_TAREFA_PARADA',
                            'DIAS_GUARDAR_FOTO_ENTREGA', 'CONTATO_PRIVACIDADE']) k
   WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                      WHERE g.contaid = c.contaid AND g.chave = k);

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'configuracoesfaltando', to_jsonb(v_chaves),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;

-- =========================================================================
-- 20260929100300_saude_confere_assinatura.sql
-- =========================================================================
-- A /saude passa a conferir a ASSINATURA das funções, não só o nome.
--
-- Pedido do Wisley (25/09/2026): "a /saude já confere nome e lista exata de
-- parâmetros de todas as funções que o aplicativo chama?" Não conferia — e foi
-- exatamente esse tipo de diferença que quebrou a entrega no tablet, e que ele
-- só descobriu testando na loja.
--
-- Quem sabe o que o aplicativo espera é o aplicativo. Então ele MANDA a lista
-- (src/integrations/supabase/contrato.ts, gerada dos tipos do banco) e o banco
-- responde o que não bate. Assim a lista não envelhece dentro de uma migração.

CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema(p_esperado jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_abrir_ex', 'tentativa_fechar', 'acesso_por_email',
    'definir_senha_gestor', 'marcar_senha_amao', 'erros_de_login',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado',
    'pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
    'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa', 'tarefa_unica_ja_cumprida',
    'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar',
    'fechamento_valendo', 'ficha_dos_tablets', 'registrar_evento_acesso_loja',
    'rodizio_espera', 'elegiveis_da_tarefa',
    -- Etapa 1.12 C1: o celular do colaborador.
    'eu_inicio', 'eu_tarefas', 'eu_entregar', 'eu_extrato', 'eu_confere_pessoa'
  ];
  v_faltando text[];
  v_tabelas  text[];
  v_chaves   text[];
  v_assinaturas text[];
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
                      'tarefascandidatos', 'acessoslojaeventos']) t
   WHERE to_regclass('public.' || t) IS NULL;

  -- Configuração que não chegou em alguma conta: foi assim que a seção
  -- "Aceite de tarefas" apareceu vazia em 25/09/2026.
  SELECT coalesce(array_agg(DISTINCT k ORDER BY k), ARRAY[]::text[]) INTO v_chaves
    FROM public.contas c
    CROSS JOIN unnest(ARRAY['MINUTOS_RODIZIO_ACEITE', 'MINUTOS_TAREFA_PARADA',
                            'DIAS_GUARDAR_FOTO_ENTREGA', 'CONTATO_PRIVACIDADE']) k
   WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                      WHERE g.contaid = c.contaid AND g.chave = k);

  -- ASSINATURAS: o aplicativo manda, para cada funcao que ele chama, os
  -- parametros que espera encontrar. Aqui comparamos com o que o banco tem de
  -- verdade. Conferir so o NOME nao bastava: em 25/09/2026 a entrega quebrou
  -- porque uma funcao tinha mudado de parametros, e o /saude dizia "tudo
  -- certo".
  --
  -- So os parametros p_*: numa funcao que devolve tabela, proargnames traz
  -- tambem o nome das COLUNAS, que nao sao parametro de ninguem.
  WITH doBanco AS (
    SELECT p.proname AS nome,
           coalesce((SELECT array_agg(a ORDER BY a) FROM unnest(coalesce(p.proargnames, ARRAY[]::text[])) a
                      WHERE a LIKE 'p\_%'), ARRAY[]::text[]) AS params
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
  ), doApp AS (
    SELECT j.k AS nome,
           coalesce((SELECT array_agg(x ORDER BY x) FROM jsonb_array_elements_text(j.val) x),
                    ARRAY[]::text[]) AS params
      FROM jsonb_each(coalesce(p_esperado, '{}'::jsonb)) AS j(k, val)
  )
  SELECT coalesce(array_agg(msg ORDER BY msg), ARRAY[]::text[]) INTO v_assinaturas
    FROM (
      SELECT CASE
               WHEN NOT EXISTS (SELECT 1 FROM doBanco b WHERE b.nome = e.nome)
                 THEN e.nome || ' (nao existe no banco)'
               ELSE e.nome || ' (o app espera: ' || array_to_string(e.params, ', ')
                           || '; o banco tem: '
                           || (SELECT string_agg(array_to_string(b.params, ', '), ' / ')
                                 FROM doBanco b WHERE b.nome = e.nome) || ')'
             END AS msg
        FROM doApp e
       WHERE NOT EXISTS (SELECT 1 FROM doBanco b
                          WHERE b.nome = e.nome AND b.params = e.params)
    ) q;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'assinaturasdiferentes', to_jsonb(v_assinaturas),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'configuracoesfaltando', to_jsonb(v_chaves),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

-- A versao sem parametro some: senao ficariam as duas no banco e ninguem
-- saberia qual roda.
DROP FUNCTION IF EXISTS public.diagnostico_do_sistema();

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema(jsonb) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema(jsonb) TO service_role;

-- =========================================================================
-- 20260929100400_conta_cancelada_e_limite_da_foto.sql
-- =========================================================================
-- Dois consertos da revisão adversarial de 25/09/2026.
--
-- 1. CONTA CANCELADA fechava só a escrita, não a leitura. eu_confere_pessoa
--    conferia apenas funcionarios.ativo, então o Início, as tarefas e o
--    extrato abriam numa conta cancelada. Não era furo (nada chega às eu_*
--    sem passar pelo servidor, que confere meu_acesso), mas era exatamente a
--    "tranca única fora do banco" que esta mesma etapa existiu para eliminar.
--
-- 2. O BUCKET DAS FOTOS ficou sem limite de tamanho e sem lista de tipos.
--    Os outros dois buckets ganharam 10 MB e tipos permitidos; entregas não.
--    E agora o servidor BAIXA o arquivo inteiro para tirar a impressão
--    digital, então o tamanho deixou de ser só uma questão de espaço.

-- ---------------------------------------------------------------------------
-- 1. Conta cancelada fecha as leituras também
-- ---------------------------------------------------------------------------
-- Parte da versão de 20260929100100, com uma conferência a mais.
CREATE OR REPLACE FUNCTION public.eu_confere_pessoa(p_contaid integer, p_funcionarioid integer)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                  WHERE f.contaid = p_contaid AND f.funcionarioid = p_funcionarioid AND f.ativo) THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Conta cancelada: a mesma mensagem, para não revelar o motivo a quem está
  -- do lado de fora.
  IF NOT EXISTS (SELECT 1 FROM public.contas c
                  WHERE c.contaid = p_contaid AND c.status <> 'cancelada') THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.eu_confere_pessoa(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_confere_pessoa(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 1b. eu_inicio passa a usar a MESMA conferência das outras três
-- ---------------------------------------------------------------------------
-- Ela tinha a dela, por dentro (só funcionarios.ativo), e por isso continuava
-- abrindo com a conta cancelada mesmo depois do conserto acima. Quem achou
-- foi o teste: com a conta ativa o Início abria (controle), com a conta
-- cancelada ele continuava abrindo.
--
-- Parte da versão de 20260929100000, trocando só o bloco da conferência.
CREATE OR REPLACE FUNCTION public.eu_inicio(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  f      record;
  v_nota numeric;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Uma porta só para as quatro funções: pessoa ativa E conta não cancelada.
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT nomecompleto, saldopontos INTO f
    FROM public.funcionarios
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT r.nota INTO v_nota
    FROM public.ranking_mensal_da_conta(p_contaid,
           extract(year FROM v_hoje)::integer, extract(month FROM v_hoje)::integer,
           NULL, v_hoje - 1) r
   WHERE r.funcionarioid = p_funcionarioid;

  RETURN jsonb_build_object(
    'nome',   public.nome_curto(f.nomecompleto),
    -- Saldo só em pontos. Nunca convertido em dinheiro nesta visão.
    'saldo',  f.saldopontos,
    'nota',   v_nota,
    'feedbackpendente', public.bot_falta_feedback_ontem(p_contaid, p_funcionarioid),
    'comunicados', (SELECT count(*) FROM public.documentosassinaturas s
                     WHERE s.contaid = p_contaid AND s.funcionarioid = p_funcionarioid
                       AND s.statusassinatura = 'Pendente'));
END;
$$;

REVOKE ALL ON FUNCTION public.eu_inicio(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_inicio(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Limite de tamanho e de tipo no bucket das fotos de entrega
-- ---------------------------------------------------------------------------
-- Em DO porque o Storage do Supabase é que traz a tabela storage.buckets: no
-- Postgres de teste ela pode não existir, e a migração não pode quebrar ali.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'storage' AND table_name = 'buckets'
                AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets
                  SET file_size_limit = 10485760,
                      allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
                WHERE id = 'entregas'$q$;
  END IF;
END $$;


-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
DECLARE v_falta text[];
BEGIN
  SELECT array_agg(f) INTO v_falta
    FROM unnest(ARRAY['eu_confere_pessoa', 'eu_inicio', 'eu_tarefas', 'eu_entregar', 'eu_extrato']) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);
  IF array_length(v_falta, 1) > 0 THEN
    RAISE EXCEPTION 'Faltou criar: %', array_to_string(v_falta, ', ');
  END IF;

  -- O diagnóstico tem de aceitar a lista do aplicativo, e tem de ter ficado
  -- UMA só: a versão sem parâmetro sai.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'diagnostico_do_sistema') <> 1 THEN
    RAISE EXCEPTION 'diagnostico_do_sistema ficou duplicada: sobrou a versão antiga.';
  END IF;
  IF jsonb_array_length(
       public.diagnostico_do_sistema('{"funcao_que_nunca_existiu": []}'::jsonb)
         -> 'assinaturasdiferentes') <> 1 THEN
    RAISE EXCEPTION 'A /saude não está conferindo a assinatura das funções.';
  END IF;

  -- Nenhuma função eu_* pode estar liberada para o usuário logado.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname LIKE 'eu\_%'
                AND has_function_privilege('authenticated', p.oid, 'EXECUTE')) THEN
    RAISE EXCEPTION 'Alguma função eu_* ficou liberada para o usuário logado.';
  END IF;

  -- Conta cancelada tem de fechar tambem as LEITURAS do celular.
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'eu_confere_pessoa') NOT LIKE '%cancelada%' THEN
    RAISE EXCEPTION 'A conta cancelada ainda abriria o aplicativo do colaborador.';
  END IF;
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'eu_inicio') NOT LIKE '%eu_confere_pessoa%' THEN
    RAISE EXCEPTION 'O Início do colaborador não passa pela conferência única.';
  END IF;

  RAISE NOTICE 'tudo certo: consertos aplicados e a /saude confere assinatura.';
END $verifica$;

COMMIT;
