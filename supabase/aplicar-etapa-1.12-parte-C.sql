-- =========================================================================
-- STGame — Etapa 1.12, parte C1: o celular do colaborador.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado (roda tudo junto ou nada): me mande a mensagem.
-- Pode rodar duas vezes sem problema: tudo aqui confere antes de criar.
--
-- ATENÇÃO: aplique a parte A e a parte B1 antes desta.
--
-- Este arquivo é UMA migração só:
--   20260929100000_visao_do_colaborador.sql
-- =========================================================================

BEGIN;

-- -------------------------------------------------------------------------
-- Preparo: registrar_entrega GANHOU DOIS PARÂMETROS nesta etapa. O Postgres
-- trataria a versão nova como outra função e as duas ficariam no banco — e aí
-- ninguém sabe qual roda. Apagar a antiga antes resolve; a nova é criada
-- logo abaixo, dentro desta mesma transação.
-- -------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.registrar_entrega(integer, text, text, boolean);

-- =========================================================================
-- 20260929100000_visao_do_colaborador.sql
-- =========================================================================

-- Etapa 1.12, parte C1 — o celular do colaborador (26/09/2026).
--
-- O celular NÃO fala com o banco: para o colaborador `minha_conta()` responde
-- vazio e as regras de acesso negam tudo. Tudo passa pelas funções `eu_*`
-- abaixo, que recebem conta e pessoa e por isso só o SERVIDOR chama — ele já
-- descobriu quem é pelo token.
--
-- ACEITAR tarefa continua sendo só no tablet da loja. O celular entrega,
-- consulta e pede.
--
-- A FOTO no celular (decisão do Wisley, 26/09/2026):
--   * janela de 10 minutos entre abrir a entrega e enviar — igual ao bot;
--   * a mesma imagem não vale duas vezes (impressão digital do arquivo);
--   * "foto encaminhada" não existe no navegador. O substituto é a hora em
--     que a foto foi tirada, que fica dentro do arquivo: quando existe, tem
--     de ser recente; quando NÃO existe (muitos celulares apagam), a entrega
--     entra marcada e o Quadro avisa. Quem decide é o gestor, na aprovação.
--
-- SALDO NUNCA EM REAIS para o colaborador: ponto é reconhecimento, não
-- salário (política de uso). O valor em dinheiro só aparece no abate.

-- ---------------------------------------------------------------------------
-- 1. A marca "sem hora da foto"
-- ---------------------------------------------------------------------------
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS semhorafoto boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.entregas.semhorafoto IS
  'true quando o arquivo da foto não trazia a hora em que ela foi tirada. A entrega vale; o Quadro avisa para o gestor decidir.';
CREATE INDEX IF NOT EXISTS entregas_semhorafoto_idx
  ON public.entregas (contaid, lojaid) WHERE semhorafoto;

-- ---------------------------------------------------------------------------
-- 2. Entregar passa a aceitar a impressão digital e a marca
-- ---------------------------------------------------------------------------
-- A versão de 4 parâmetros sai de cena: com as duas novas tendo padrão, uma
-- chamada de 4 ficaria ambígua entre as duas funções.

CREATE OR REPLACE FUNCTION public.registrar_entrega(
  p_atribuicaoid integer,
  p_observacao   text    DEFAULT NULL,
  p_pathfoto     text    DEFAULT NULL,
  p_aprovar      boolean DEFAULT false,
  -- Impressão digital da imagem: a mesma foto não prova duas tarefas, nem
  -- que o arquivo mude de nome. O Telegram já usava este campo com o id dele.
  p_fotoidunico  text    DEFAULT NULL,
  -- true quando o arquivo não trazia a hora em que a foto foi tirada. A
  -- entrega entra assim mesmo e o Quadro avisa: o gestor decide na aprovação.
  p_semhorafoto  boolean DEFAULT false
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

  -- A mesma foto não prova duas tarefas: pelo caminho e pela imagem em si.
  IF v_foto IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                     WHERE e.contaid = v_conta AND e.pathfotoevidencia = v_foto) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;
  IF p_fotoidunico IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                            WHERE e.contaid = v_conta AND e.fotoidunico = p_fotoidunico) THEN
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
      dataenvio, pathfotoevidencia, observacao, statusvalidacao,
      fotoidunico, semhorafoto
    ) VALUES (
      v_conta, v_atr.tarefaid, v_atr.funcionarioid, v_atr.lojaid, p_atribuicaoid,
      now(), v_foto, nullif(btrim(coalesce(p_observacao, '')), ''), 'Pendente',
      nullif(btrim(coalesce(p_fotoidunico, '')), ''), coalesce(p_semhorafoto, false)
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

REVOKE ALL ON FUNCTION public.registrar_entrega(integer, text, text, boolean, text, boolean)
  FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.registrar_entrega(integer, text, text, boolean, text, boolean)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. O Início do celular
-- ---------------------------------------------------------------------------
-- Tudo o que a primeira tela precisa, num pedido só: nome, saldo EM PONTOS,
-- nota do mês, tarefas de hoje e os dois avisos (feedback de ontem e
-- comunicado sem ciência). Nada de valor em reais.
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

-- ---------------------------------------------------------------------------
-- 4. Minhas tarefas de hoje
-- ---------------------------------------------------------------------------
-- Só o que É da pessoa: a tarefa com dono dela e a cópia do que ela pegou no
-- tablet. `pegaem` é a hora do aceite, para a tela dizer "aceita às 14h02".
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
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

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
          LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid AND l.contaid = p_contaid
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
      ) x);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Entregar pelo celular
-- ---------------------------------------------------------------------------
-- A tarefa tem de ser DELA. O resto das regras é o registrar_entrega de
-- sempre, com a impressão digital da imagem e a marca da hora da foto.
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
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ta.lojaid INTO v_lojaid
    FROM public.tarefasatribuidas ta
   WHERE ta.atribuicaoid = p_atribuicaoid AND ta.contaid = p_contaid
     AND ta.funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa não é sua.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, v_lojaid, 'colaborador');
  RETURN public.registrar_entrega(p_atribuicaoid, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Meu extrato — o livro de pontos, sem conversão em dinheiro
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
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

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

-- ---------------------------------------------------------------------------
-- 7. Permissões: todas recebem conta e pessoa, então só o servidor as chama.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.eu_inicio(integer, integer)            FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.eu_tarefas(integer, integer)           FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.eu_extrato(integer, integer, date, date) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
                                                                     FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eu_inicio(integer, integer)            TO service_role;
GRANT EXECUTE ON FUNCTION public.eu_tarefas(integer, integer)           TO service_role;
GRANT EXECUTE ON FUNCTION public.eu_extrato(integer, integer, date, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
                                                                        TO service_role;

-- ---------------------------------------------------------------------------
-- O diagnostico (/saude) passa a cobrar tambem as funcoes do celular.
-- Partiu da versao mais recente (20260928100800), com o diff conferido: a
-- unica mudanca e a linha das quatro funcoes eu_*.
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
    'eu_inicio', 'eu_tarefas', 'eu_entregar', 'eu_extrato'
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
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
DECLARE v_falta text[];
BEGIN
  SELECT array_agg(f) INTO v_falta
    FROM unnest(ARRAY['eu_inicio', 'eu_tarefas', 'eu_entregar', 'eu_extrato']) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);
  IF array_length(v_falta, 1) > 0 THEN
    RAISE EXCEPTION 'Faltou criar: %', array_to_string(v_falta, ', ');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'entregas'
                    AND column_name = 'semhorafoto') THEN
    RAISE EXCEPTION 'Faltou a coluna entregas.semhorafoto.';
  END IF;

  -- registrar_entrega tem de ter ficado UMA só, com os seis parâmetros.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'registrar_entrega') <> 1 THEN
    RAISE EXCEPTION 'registrar_entrega ficou duplicada: sobrou a versão antiga.';
  END IF;

  -- Nenhuma função eu_* pode estar liberada para o usuário logado: quem fala
  -- com elas é só o servidor.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname LIKE 'eu\_%'
                AND has_function_privilege('authenticated', p.oid, 'EXECUTE')) THEN
    RAISE EXCEPTION 'Alguma função eu_* ficou liberada para o usuário logado.';
  END IF;

  -- E o /saude tem de saber cobrar as quatro.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'diagnostico_do_sistema'
                    AND p.prosrc LIKE '%eu_extrato%') THEN
    RAISE EXCEPTION 'O diagnóstico do /saude ficou na versão antiga.';
  END IF;

  RAISE NOTICE 'tudo certo: a parte C1 foi aplicada.';
END $verifica$;

COMMIT;
