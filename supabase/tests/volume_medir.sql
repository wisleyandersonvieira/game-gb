-- =========================================================================
-- Tempo das telas com volume de loja real (pedido do Wisley, 29/09/2026).
--
-- Cada tela é o que ela pede ao banco ao abrir. Medida 7 vezes para o master
-- e para o gerente da conta sintética 900 (volume_semear.sql). REPROVA se:
--   * a mediana de uma tela passa de 1,5 s (1500 ms), para qualquer um dos dois;
--   * a lista principal da tela vem VAZIA (uma tela vazia é rápida à toa).
-- A única exceção à segunda regra é a lista fechada de telas do gerente que a
-- parte 4 ainda vai cobrir: ela só pode diminuir, e uma tela dela que passe a
-- devolver linhas também reprova (para sair da lista na mesma entrega).
-- =========================================================================
CREATE TEMP TABLE medidas (quem text, tela text, ms numeric, linhas integer);

-- Quantas linhas a resposta trouxe: todo item de toda lista dentro dela.
CREATE OR REPLACE FUNCTION pg_temp.linhas(t text) RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE j jsonb; n integer;
BEGIN
  IF t IS NULL THEN RETURN 0; END IF;
  BEGIN j := t::jsonb; EXCEPTION WHEN OTHERS THEN RETURN 1; END;
  WITH RECURSIVE r(x) AS (
    SELECT j
    UNION ALL
    SELECT z.e FROM r, LATERAL (
      SELECT v FROM jsonb_array_elements(CASE WHEN jsonb_typeof(r.x) = 'array' THEN r.x ELSE '[]'::jsonb END) v
      UNION ALL
      SELECT v FROM jsonb_each(CASE WHEN jsonb_typeof(r.x) = 'object' THEN r.x ELSE '{}'::jsonb END) kv(k, v)) z(e))
  SELECT coalesce(sum(jsonb_array_length(x)), 0) INTO n FROM r WHERE jsonb_typeof(x) = 'array';
  RETURN n;
END $f$;

-- Uma tela: todas as chamadas dela, cronometradas juntas. As linhas contadas
-- são as da PRIMEIRA chamada (a lista principal), fora do cronômetro.
CREATE OR REPLACE FUNCTION pg_temp.tela(p_quem text, p_uid uuid, p_tela text, p_sqls text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i integer; s text; t0 timestamptz; v text; principal text; ms numeric;
BEGIN
  FOR i IN 1..7 LOOP
    PERFORM set_config('teste.uid', p_uid::text, true);
    SET LOCAL ROLE authenticated;
    ms := 0; principal := NULL;
    FOREACH s IN ARRAY p_sqls LOOP
      t0 := clock_timestamp();
      EXECUTE 'SELECT (' || s || ')::text' INTO v;
      ms := ms + extract(epoch FROM clock_timestamp() - t0) * 1000;
      IF principal IS NULL THEN principal := coalesce(v, ''); END IF;
    END LOOP;
    SET LOCAL ROLE NONE;
    INSERT INTO medidas VALUES (p_quem, p_tela, ms, pg_temp.linhas(nullif(principal, '')));
  END LOOP;
END $$;

DO $$
DECLARE q record; h date := public.hoje_da_conta(900); m date := date_trunc('month', public.hoje_da_conta(900))::date;
  -- Uma pessoa só da loja 9001 (o extrato do gerente é de quem está inteiro nas lojas dele).
  pe integer := (SELECT min(fl.funcionarioid) FROM public.funcionarioslojas fl
                  WHERE fl.contaid = 900 AND fl.lojaid = 9001 AND fl.ativo
                    AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas o
                                     WHERE o.funcionarioid = fl.funcionarioid AND o.lojaid <> 9001 AND o.ativo));
BEGIN
  FOR q IN SELECT * FROM (VALUES ('master', '99999999-9999-9999-9999-999999999999'::uuid),
                                 ('gerente', '90909090-9090-9090-9090-909090909090'::uuid)) x(quem, uid) LOOP
    PERFORM pg_temp.tela(q.quem, q.uid, 'Início', ARRAY['public.painel_inicio(NULL)',
      '(SELECT jsonb_agg(t) FROM public.tarefas_nao_pegas(NULL) t)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Quadro', ARRAY[
      'public.quadro_validacao(9001)', '(SELECT jsonb_agg(f) FROM public.fila_da_loja(9001) f)',
      '(SELECT jsonb_agg(a) FROM public.atribuicoes_para_entregar(9001) a)', 'public.contagem_do_menu()', 'public.alcance_da_fila()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Metas', ARRAY[format('public.metas_do_mes(9001, %L::date)', m),
      '(SELECT jsonb_agg(x) FROM public.metas_da_semana(9001) x)', '(SELECT jsonb_agg(x) FROM public.metas_especiais_da_loja(9001) x)',
      'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Relatórios', ARRAY[format('public.analise_de_tarefas(%L::date, %L::date)', h - 30, h),
      'public.historico_da_pessoa(90001)', format('public.pendencias_da_pessoa(90001, %L::date, %L::date)', h - 30, h),
      format('(SELECT jsonb_agg(t) FROM public.tarefas_pegas_da_pessoa(90001, %L::date, %L::date) t)', h - 30, h)]);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Prêmios', ARRAY['public.listar_trocas(100)', '(SELECT jsonb_agg(p) FROM public.pessoas_para(''premios.ver'') p)',
      '(SELECT jsonb_agg(p) FROM public.premios_do_catalogo() p)', 'public.minha_taxa()', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Extrato', ARRAY[format('public.extrato_pontos(%s, %L::date, %L::date)', pe, h - 30, h),
      '(SELECT jsonb_agg(p) FROM public.pessoas_para(''extrato.ver'') p)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Feedbacks', ARRAY[format('(SELECT jsonb_agg(f) FROM public.feedbacks_do_periodo(%L::date, %L::date) f)', h - 30, h),
      '(SELECT jsonb_agg(p) FROM public.pessoas_para(''feedbacks.ver'') p)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Justificativas', ARRAY['(SELECT jsonb_agg(j) FROM public.justificativas_da_tela() j)',
      '(SELECT jsonb_agg(p) FROM public.pessoas_para(''justificativas.registrar'') p)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Solicitações', ARRAY['(SELECT jsonb_agg(s) FROM public.solicitacoes_da_loja(9001) s)',
      '(SELECT jsonb_agg(h) FROM public.historico_das_solicitacoes(9001) h)',
      '(SELECT jsonb_agg(p) FROM public.pessoas_da_loja(9001, ''solicitacoes.abrir'') p)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Tarefas', ARRAY['public.catalogo_de_tarefas(NULL, false, NULL, 5, 0)',
      'public.atribuicoes_da_loja(9001)', '(SELECT jsonb_agg(x) FROM public.tarefas_da_loja(9001) x)',
      '(SELECT jsonb_agg(p) FROM public.pessoas_da_loja(9001, ''tarefas.atribuir'') p)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Agenda', ARRAY['(SELECT jsonb_agg(x) FROM public.agendamentos_da_loja(9001) x)',
      'public.agendamentos_sem_tarefa(9001)', '(SELECT jsonb_agg(x) FROM public.tipos_de_evento() x)',
      '(SELECT jsonb_agg(p) FROM public.pessoas_da_loja(9001, ''agenda.ver'') p)', '(SELECT jsonb_agg(p) FROM public.pessoas_para(''agenda.ver'') p)',
      'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Conquistas', ARRAY['(SELECT jsonb_agg(x) FROM public.conquistas_do_catalogo() x)',
      '(SELECT jsonb_agg(x) FROM public.conquistas_ganhas() x)', '(SELECT jsonb_agg(p) FROM public.pessoas_para(''conquistas.ver'') p)',
      'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Comunicados', ARRAY['(SELECT jsonb_agg(x) FROM public.comunicados_da_tela() x)',
      '(SELECT jsonb_agg(x) FROM public.ciencias_da_tela() x)', '(SELECT jsonb_agg(p) FROM public.pessoas_para(''comunicados.ver'') p)',
      '(SELECT jsonb_agg(x) FROM public.lojas_para(''comunicados.publicar'') x)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Equipe', ARRAY['(SELECT jsonb_agg(x) FROM public.equipe_da_tela() x)',
      '(SELECT jsonb_agg(x) FROM public.vinculos_da_tela() x)', '(SELECT jsonb_agg(x) FROM public.situacao_dos_acessos() x)',
      '(SELECT jsonb_agg(x) FROM public.travas_do_pin() x)', '(SELECT jsonb_agg(x) FROM public.jornadas_da_conta() x)',
      'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Onboarding', ARRAY['(SELECT jsonb_agg(x) FROM public.pessoas_inteiras_para(''onboarding.ver'') x)',
      '(SELECT jsonb_agg(x) FROM public.onboarding_status_da_tela() x)', '(SELECT jsonb_agg(x) FROM public.onboarding_itens_da_tela() x)',
      '(SELECT jsonb_agg(x) FROM public.etapas_de_onboarding() x)', 'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Lojas', ARRAY['(SELECT jsonb_agg(x) FROM public.lojas_da_gestao() x)',
      'public.resumo_das_lojas()', '(SELECT jsonb_agg(x) FROM public.links_de_tv() x)', '(SELECT jsonb_agg(x) FROM public.conta_da_gestao() x)',
      'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Jornada', ARRAY['public.mapa_da_jornada(9001)',
      '(SELECT jsonb_agg(x) FROM public.jornadas_da_tela() x)', '(SELECT jsonb_agg(x) FROM public.dias_das_jornadas() x)',
      '(SELECT jsonb_agg(x) FROM public.pessoas_para(''jornada.ver'') x)', '(SELECT jsonb_agg(x) FROM public.vinculos_para(''jornada.ver'') x)',
      'public.contagem_do_menu()']);
    PERFORM pg_temp.tela(q.quem, q.uid, 'Ranking', ARRAY[format('(SELECT jsonb_agg(r) FROM public.ranking_pontos(%L::date, %L::date, 9001) r)', m, h),
      format('(SELECT jsonb_agg(r) FROM public.ranking_mensal(%s, %s, 9001) r)', extract(year FROM m), extract(month FROM m)),
      '(SELECT jsonb_agg(f) FROM public.meses_fechados() f)', 'public.contagem_do_menu()']);
  END LOOP;
END $$;

-- O relatório de cada rodada: tela, quem, mediana, pior e linhas.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tela, quem, round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric) AS mediana,
                  round(max(ms)) AS pior, max(linhas) AS linhas
             FROM medidas GROUP BY 1, 2 ORDER BY 1, 2 LOOP
    RAISE NOTICE '    %  %  mediana % ms (pior %), % linhas', rpad(r.tela, 11), rpad(r.quem, 8), lpad(r.mediana::text, 5), r.pior, r.linhas;
  END LOOP;
END $$;

DO $$
DECLARE
  -- Telas do gerente que a parte 4 ainda vai cobrir (lista fechada: só diminui).
  pendentes constant text[] := ARRAY[]::text[];
  lentas text; vazias text; saiu text;
BEGIN
  SELECT string_agg(tela || '/' || quem || ' ' || mediana || ' ms', ', ') INTO lentas
    FROM (SELECT tela, quem, round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric) AS mediana
            FROM medidas GROUP BY 1, 2) x WHERE mediana > 1500;
  SELECT string_agg(tela || '/' || quem, ', ') INTO vazias
    FROM (SELECT tela, quem, max(linhas) AS linhas FROM medidas GROUP BY 1, 2) x
   WHERE linhas = 0 AND NOT (quem = 'gerente' AND tela = ANY (pendentes));
  SELECT string_agg(tela, ', ') INTO saiu
    FROM (SELECT tela, max(linhas) AS linhas FROM medidas WHERE quem = 'gerente' GROUP BY 1) x
   WHERE tela = ANY (pendentes) AND linhas > 0;
  IF lentas IS NOT NULL THEN RAISE EXCEPTION 'FALHOU: tela acima de 1,5 s com volume de loja real: %', lentas; END IF;
  IF vazias IS NOT NULL THEN RAISE EXCEPTION 'FALHOU: tela VAZIA com volume de loja real (lista principal sem linhas): %', vazias; END IF;
  IF saiu IS NOT NULL THEN RAISE EXCEPTION 'FALHOU: a tela % do gerente passou a ter linhas: tire-a da lista de pendentes', saiu; END IF;
  RAISE NOTICE '  ok  todas as telas abaixo de 1,5 s e com linhas, para o master e o gerente (pendentes do gerente: %)',
    coalesce(array_to_string(pendentes, ', '), 'nenhuma');
END $$;
