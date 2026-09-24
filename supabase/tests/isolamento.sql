-- ===========================================================================
-- TESTE DE ISOLAMENTO ENTRE CONTAS
-- Cria duas contas (A e B) e prova que A nao le, nao altera e nao apaga nada
-- de B. Roda num Postgres descartavel, depois de _ambiente_local.sql e de
-- todas as migracoes. Qualquer falha aborta com erro.
--
-- Uso: bash supabase/tests/rodar.sh
-- ===========================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION public.exigir(condicao boolean, descricao text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF condicao IS NOT TRUE THEN
    RAISE EXCEPTION 'FALHOU: %', descricao;
  END IF;
  RAISE NOTICE '  ok  %', descricao;
END $$;
-- Funcao nova nasce sem permissao (negada por padrao): libera so esta, de teste.
GRANT EXECUTE ON FUNCTION public.exigir(boolean, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Preparacao (como dono do banco: a RLS nao se aplica aqui)
-- ---------------------------------------------------------------------------

INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'master.a@exemplo.com',        now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'master.b@exemplo.com',        now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'wisley_anderson@hotmail.com', now()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'sem.conta@exemplo.com',       now()),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'master.suspensa@exemplo.com', now());

INSERT INTO public.contas (contaid, nome, email, limitelojas, status) OVERRIDING SYSTEM VALUE VALUES
  (1, 'Empresa A',        'a@exemplo.com', 2, 'ativa'),
  (2, 'Empresa B',        'b@exemplo.com', 2, 'ativa'),
  (3, 'Empresa Suspensa', 's@exemplo.com', 2, 'suspensa');

INSERT INTO public.contasusuarios (contaid, userid) VALUES
  (1, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (2, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  (3, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');

-- ---------------------------------------------------------------------------
-- Cada conta monta os proprios dados, ja como usuario logado
-- ---------------------------------------------------------------------------

SET ROLE authenticated;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
INSERT INTO public.lojas (lojaid, nome) OVERRIDING SYSTEM VALUE VALUES (10, 'Loja A1'), (11, 'Loja A2');
INSERT INTO public.funcionarios (funcionarioid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES (100, 'Ana da conta A');
INSERT INTO public.tarefas (tarefaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (1000, 'Tarefa A', 5);
INSERT INTO public.funcionarioslojas (funcionarioid, lojaid) VALUES (100, 10);
INSERT INTO public.tarefaslojas (tarefaid, lojaid) VALUES (1000, 10);
INSERT INTO public.tarefasatribuidas (atribuicaoid, tarefaid, funcionarioid, lojaid) OVERRIDING SYSTEM VALUE VALUES (5000, 1000, 100, 10);
DO $$ BEGIN PERFORM public.registrar_entrega(5000); END $$;
INSERT INTO public.grupos (grupoid, nomegrupo, lojaid) OVERRIDING SYSTEM VALUE VALUES (200, 'Cozinha', 10);
INSERT INTO storage.objects (bucket_id, name) VALUES ('entregas', '1/10/foto-a.jpg');

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.lojas (lojaid, nome) OVERRIDING SYSTEM VALUE VALUES (20, 'Loja B1');
INSERT INTO public.funcionarios (funcionarioid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES (200, 'Bruno da conta B');
INSERT INTO public.tarefas (tarefaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (2000, 'Tarefa B', 7);
INSERT INTO public.funcionarioslojas (funcionarioid, lojaid) VALUES (200, 20);
INSERT INTO public.tarefaslojas (tarefaid, lojaid) VALUES (2000, 20);
INSERT INTO public.tarefasatribuidas (atribuicaoid, tarefaid, funcionarioid, lojaid) OVERRIDING SYSTEM VALUE VALUES (6000, 2000, 200, 20);
DO $$ BEGIN PERFORM public.registrar_entrega(6000); END $$;
INSERT INTO public.grupos (grupoid, nomegrupo, lojaid) OVERRIDING SYSTEM VALUE VALUES (300, 'Cozinha', 20);
INSERT INTO storage.objects (bucket_id, name) VALUES ('entregas', '2/20/foto-b.jpg');

RESET ROLE;
-- Configuracoes so mudam por alterar_configuracao (Etapa 1.7): aqui, como
-- dono do banco, gravamos uma para cada conta.
INSERT INTO public.configuracoes (contaid, chave, valor) VALUES
  (1, 'TAXA_CONVERSAO_PONTO_REAL', '0.03'),
  (2, 'TAXA_CONVERSAO_PONTO_REAL', '0.05');
DO $$ BEGIN RAISE NOTICE '--- dados criados: conta A e conta B ---'; END $$;

-- ===========================================================================
-- 1. A conta A nao enxerga NADA da conta B
-- ===========================================================================

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DO $$
DECLARE r record; n bigint; total bigint := 0;
BEGIN
  RAISE NOTICE '1. leitura: nenhuma linha de outra conta aparece';
  FOR r IN
    SELECT c.table_name AS t
    FROM information_schema.columns c
    JOIN information_schema.tables x
      ON x.table_schema = c.table_schema AND x.table_name = c.table_name
    WHERE c.table_schema = 'public' AND c.column_name = 'contaid'
      AND x.table_type = 'BASE TABLE'
      -- Tabela sem permissão nenhuma de leitura já está fechada (ex.: fila do bot).
      AND has_table_privilege('authenticated', format('%I.%I', c.table_schema, c.table_name), 'SELECT')
    ORDER BY 1
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE contaid <> 1', r.t) INTO n;
    total := total + n;
    IF n > 0 THEN
      RAISE EXCEPTION 'FALHOU: a conta A enxergou % linha(s) de outra conta em %', n, r.t;
    END IF;
  END LOOP;
  PERFORM public.exigir(total = 0, 'nenhuma linha de outra conta visivel em nenhuma tabela');
END $$;

DO $$
BEGIN
  RAISE NOTICE '2. os dados da propria conta continuam visiveis';
  PERFORM public.exigir((SELECT count(*) FROM public.funcionarios) = 1, 'A ve o proprio funcionario');
  PERFORM public.exigir((SELECT count(*) FROM public.lojas) = 2,        'A ve as proprias 2 lojas');
  PERFORM public.exigir((SELECT count(*) FROM public.tarefas) = 1,      'A ve a propria tarefa');
  PERFORM public.exigir((SELECT count(*) FROM public.entregas) = 1,     'A ve a propria entrega');
  PERFORM public.exigir((SELECT valor FROM public.configuracoes WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL') = '0.03',
                        'A ve a propria configuracao, nao a de B');
END $$;

-- ===========================================================================
-- 3. A conta A nao ALTERA nem APAGA nada da conta B
-- ===========================================================================

DO $$
DECLARE afetadas integer;
BEGIN
  RAISE NOTICE '3. escrita sobre dados alheios nao tem efeito';

  UPDATE public.funcionarios SET nomecompleto = 'INVADIDO' WHERE funcionarioid = 200;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'A nao altera funcionario de B');

  UPDATE public.lojas SET nome = 'INVADIDA' WHERE lojaid = 20;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'A nao altera loja de B');

  DELETE FROM public.funcionarios WHERE funcionarioid = 200;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'A nao apaga funcionario de B');

  BEGIN
    DELETE FROM public.entregas WHERE lojaid = 20;
    GET DIAGNOSTICS afetadas = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN
    afetadas := 0;
  END;
  PERFORM public.exigir(afetadas = 0, 'A nao apaga entrega de B');

  BEGIN
    DELETE FROM public.configuracoes WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL' AND valor = '0.05';
    GET DIAGNOSTICS afetadas = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN
    afetadas := 0;
  END;
  PERFORM public.exigir(afetadas = 0, 'A nao apaga configuracao de B');
END $$;

-- ===========================================================================
-- 4. A conta A nao consegue GRAVAR dentro da conta B, nem forjando o contaid
-- ===========================================================================

DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '4. o contaid vindo do navegador nao e acreditado';

  BEGIN
    INSERT INTO public.funcionarios (contaid, nomecompleto) VALUES (2, 'Infiltrado');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'A nao cria funcionario dentro da conta B (contaid forjado)');

  BEGIN
    INSERT INTO public.lojas (contaid, nome) VALUES (2, 'Loja infiltrada');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'A nao cria loja dentro da conta B');
END $$;

-- ===========================================================================
-- 5. Um funcionario so se liga a lojas da propria conta
-- ===========================================================================

DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '5. vinculos nao atravessam contas';

  BEGIN
    INSERT INTO public.funcionarioslojas (funcionarioid, lojaid) VALUES (100, 20);
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'funcionario de A nao entra em loja de B');

  BEGIN
    INSERT INTO public.tarefaslojas (tarefaid, lojaid) VALUES (1000, 20);
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'tarefa de A nao vale em loja de B');

  BEGIN
    INSERT INTO public.entregas (tarefaid, funcionarioid, lojaid) VALUES (1000, 200, 10);
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'entrega nao mistura funcionario de B com loja de A');
END $$;

-- ===========================================================================
-- 6. So se atribui tarefa a quem trabalha numa loja onde a tarefa vale
-- ===========================================================================

DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '6. regra de atribuicao garantida pelo banco';

  BEGIN
    -- Ana (100) nao trabalha na Loja A2 (11)
    INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid) VALUES (1000, 100, 11);
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'nao atribui a funcionario que nao trabalha naquela loja');

  BEGIN
    -- a tarefa 1000 nao vale na Loja A2 (11)
    INSERT INTO public.funcionarioslojas (funcionarioid, lojaid) VALUES (100, 11);
    INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid) VALUES (1000, 100, 11);
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'nao atribui tarefa que nao vale naquela loja');
END $$;

-- ===========================================================================
-- 7. O vinculo se desativa, nunca se apaga (historico preservado)
-- ===========================================================================

DO $$
DECLARE deu_erro boolean; afetadas integer;
BEGIN
  RAISE NOTICE '7. tirar alguem da loja = desativar o vinculo';

  BEGIN
    DELETE FROM public.funcionarioslojas WHERE funcionarioid = 100 AND lojaid = 10;
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'nao apaga vinculo que ja tem historico (ON DELETE RESTRICT)');

  UPDATE public.funcionarioslojas SET ativo = false WHERE funcionarioid = 100 AND lojaid = 10;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 1, 'desativar o vinculo funciona');
  PERFORM public.exigir((SELECT count(*) FROM public.tarefasatribuidas WHERE atribuicaoid = 5000) = 1,
                        'o historico de atribuicoes continua intacto');

  UPDATE public.funcionarioslojas SET ativo = true WHERE funcionarioid = 100 AND lojaid = 10;
END $$;

-- ===========================================================================
-- 8. Storage: arquivo so entra na pasta da propria conta
-- ===========================================================================

DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '8. pastas do Storage separadas por conta';

  PERFORM public.exigir((SELECT count(*) FROM storage.objects) = 1, 'A so ve o proprio arquivo');

  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('entregas', '2/20/invasao.jpg');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'A nao grava na pasta da conta B');
END $$;

-- ===========================================================================
-- 9. Limite de lojas contratado
-- ===========================================================================

DO $$
DECLARE deu_erro boolean; nova integer; afetadas integer;
BEGIN
  RAISE NOTICE '9. limite de lojas da conta (limite 2, ja usa 2)';

  BEGIN
    INSERT INTO public.lojas (nome) VALUES ('Loja A3 (acima do limite)');
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'conta com limite 2 nao cria a terceira loja ativa');

  -- Loja desativada nao ocupa vaga.
  UPDATE public.lojas SET ativa = false WHERE lojaid = 11;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 1, 'desativar loja sempre e permitido, mesmo no limite');

  INSERT INTO public.lojas (nome) VALUES ('Loja A3') RETURNING lojaid INTO nova;
  PERFORM public.exigir(nova IS NOT NULL, 'com uma loja desativada, a vaga liberada permite criar outra');

  -- Reativar tambem passa pela conferencia do limite.
  BEGIN
    UPDATE public.lojas SET ativa = true WHERE lojaid = 11;
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'reativar loja acima do limite e recusado');

  -- Desativar nao apaga nada: o historico da loja continua inteiro.
  UPDATE public.lojas SET ativa = false WHERE lojaid = 10;
  PERFORM public.exigir((SELECT count(*) FROM public.tarefasatribuidas WHERE lojaid = 10) = 1,
                        'atribuicoes da loja desativada continuam la');
  PERFORM public.exigir((SELECT count(*) FROM public.entregas WHERE lojaid = 10) = 1,
                        'entregas da loja desativada continuam la');
  PERFORM public.exigir((SELECT count(*) FROM public.lojas WHERE lojaid = 10) = 1,
                        'a propria loja desativada continua acessivel');

  -- Devolve o cenario ao estado anterior para as checagens seguintes.
  DELETE FROM public.lojas WHERE lojaid = nova;
  UPDATE public.lojas SET ativa = true WHERE lojaid IN (10, 11);
  PERFORM public.exigir((SELECT count(*) FROM public.lojas WHERE ativa) = 2, 'cenario restaurado: 2 lojas ativas');
END $$;

-- ===========================================================================
-- 9b. Lojas de outro cliente nao existem para mim
-- ===========================================================================

DO $$
DECLARE deu_erro boolean; afetadas integer;
BEGIN
  RAISE NOTICE '9b. lojas de outro cliente';

  PERFORM public.exigir((SELECT count(*) FROM public.lojas WHERE lojaid = 20) = 0, 'A nao ve a loja de B');

  UPDATE public.lojas SET ativa = false WHERE lojaid = 20;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'A nao desativa a loja de B');

  BEGIN
    INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid) VALUES (1000, 100, 20);
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'A nao usa a loja de B numa atribuicao');
END $$;

-- ===========================================================================
-- 10. Conta suspensa fica somente leitura
-- ===========================================================================

SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '10. conta suspensa: le, mas nao escreve';
  PERFORM public.exigir((SELECT public.minha_conta()) = 3,          'a conta suspensa continua identificada');
  PERFORM public.exigir((SELECT public.minha_conta_editavel()) IS NULL, 'a conta suspensa nao e editavel');
  BEGIN
    INSERT INTO public.funcionarios (nomecompleto) VALUES ('Novo em conta suspensa');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR not_null_violation OR check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao cadastra funcionario');

  BEGIN
    INSERT INTO public.lojas (nome) VALUES ('Loja em conta suspensa');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR not_null_violation OR check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao cria loja');
END $$;

-- A conta suspensa continua enxergando o que e dela (so leitura de verdade).
-- A loja e criada fora da RLS, como se tivesse sido cadastrada antes de a
-- conta ser suspensa.
RESET ROLE;
INSERT INTO public.lojas (lojaid, contaid, nome) OVERRIDING SYSTEM VALUE
  VALUES (30, 3, 'Loja da suspensa');
SET ROLE authenticated;
SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

DO $$
DECLARE afetadas integer;
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.lojas WHERE lojaid = 30) = 1,
                        'conta suspensa continua lendo a propria loja');
  UPDATE public.lojas SET nome = 'Tentativa' WHERE lojaid = 30;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'conta suspensa nao altera a propria loja');
  DELETE FROM public.lojas WHERE lojaid = 30;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'conta suspensa nao apaga a propria loja');
END $$;

-- ===========================================================================
-- 11. Login sem conta nenhuma nao ve nada
-- ===========================================================================

SET teste.uid = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

DO $$
BEGIN
  RAISE NOTICE '11. login sem conta';
  PERFORM public.exigir((SELECT public.minha_conta()) IS NULL,       'login sem conta nao tem conta');
  PERFORM public.exigir((SELECT count(*) FROM public.funcionarios) = 0, 'login sem conta nao ve funcionarios');
  PERFORM public.exigir((SELECT count(*) FROM public.lojas) = 0,        'login sem conta nao ve lojas');
  PERFORM public.exigir((SELECT count(*) FROM public.contas) = 0,       'login sem conta nao ve contas');
END $$;

-- ===========================================================================
-- 12. Administrador geral: cuida das contas, nao dos dados dos clientes
-- ===========================================================================

SET teste.uid = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

DO $$
BEGIN
  RAISE NOTICE '12. administrador geral';
  PERFORM public.exigir((SELECT public.eh_admin_geral()),       'o e-mail do Wisley e reconhecido como admin geral');
  PERFORM public.exigir((SELECT count(*) FROM public.contas) = 3,  'o admin ve as 3 contas');
  PERFORM public.exigir((SELECT count(*) FROM public.lojas) = 4,   'o admin conta as lojas de todos (2 de A, 1 de B, 1 da suspensa)');
  PERFORM public.exigir((SELECT count(*) FROM public.funcionarios) = 0, 'o admin NAO ve funcionarios dos clientes');
  PERFORM public.exigir((SELECT count(*) FROM public.entregas) = 0,     'o admin NAO ve entregas dos clientes');
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE afetadas integer; deu_erro boolean;
BEGIN
  RAISE NOTICE '13. um master nao vira admin geral nem mexe no proprio contrato';
  PERFORM public.exigir(NOT (SELECT public.eh_admin_geral()), 'master comum nao e admin geral');
  PERFORM public.exigir((SELECT count(*) FROM public.contas) = 1, 'master so enxerga a propria conta');
  PERFORM public.exigir((SELECT count(*) FROM public.contas WHERE contaid = 2) = 0, 'master nao le a conta de outro cliente');

  -- O limite de lojas e o status sao contratuais: so o admin geral muda.
  UPDATE public.contas SET limitelojas = 99 WHERE contaid = 1;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'master NAO aumenta o proprio limite de lojas');
  PERFORM public.exigir((SELECT limitelojas FROM public.contas WHERE contaid = 1) = 2, 'o limite continua o contratado');

  UPDATE public.contas SET status = 'ativa' WHERE contaid = 3;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'master nao reativa conta suspensa');

  UPDATE public.contas SET nome = 'INVADIDA' WHERE contaid = 2;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'master nao altera a conta de outro cliente');

  DELETE FROM public.contas WHERE contaid = 2;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'master nao apaga a conta de outro cliente');

  BEGIN
    INSERT INTO public.contas (nome, email) VALUES ('Conta pirata', 'pirata@exemplo.com');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'master nao cria conta nova (so o admin geral)');

  -- Nem se auto-inscreve na conta alheia para enxerga-la depois.
  PERFORM public.exigir((SELECT count(*) FROM public.contasusuarios WHERE contaid = 2) = 0,
                        'master nao le os usuarios de outro cliente');
  BEGIN
    INSERT INTO public.contasusuarios (contaid, userid)
    VALUES (2, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR unique_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'master nao se adiciona a conta de outro cliente');
END $$;

-- ===========================================================================
-- 15. Tarefas do sistema
-- ===========================================================================

RESET ROLE;
SELECT public.cria_configuracoes_padrao(1);
SELECT public.cria_tarefas_do_sistema(1);
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DO $$
DECLARE deu_erro boolean; vazias integer;
BEGIN
  RAISE NOTICE '15. tarefas do sistema';

  PERFORM public.exigir((SELECT count(*) FROM public.tarefas WHERE sistema IS NOT NULL) = 6,
                        'as 6 tarefas do sistema foram criadas');

  SELECT count(*) INTO vazias FROM public.configuracoes
  WHERE chave IN ('TAREFA_ID_FEEDBACK_DIARIO','TAREFA_ID_LEITURA','TAREFA_ID_PONTOS_META',
                  'TAREFA_ID_NOTA_FISCAL','TAREFA_MODELO_AGENDAMENTO_ID',
                  'TAREFA_ID_GUARDAR_MERCADORIA_MODELO')
    AND coalesce(valor, '') = '';
  PERFORM public.exigir(vazias = 0, 'os 6 IDs foram gravados em configuracoes');

  PERFORM public.exigir(
    (SELECT count(*) FROM public.tarefaslojas tl
      JOIN public.tarefas t ON t.tarefaid = tl.tarefaid
     WHERE t.sistema IS NOT NULL AND tl.lojaid = 10) = 6,
    'as tarefas do sistema valem nas lojas que ja existiam');

  -- Nao se apaga.
  BEGIN
    DELETE FROM public.tarefas WHERE sistema = 'feedback_diario';
    deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'tarefa do sistema nao pode ser apagada');

  -- Mas pode ser editada.
  UPDATE public.tarefas SET titulo = 'Feedback do dia' WHERE sistema = 'feedback_diario';
  PERFORM public.exigir(
    (SELECT titulo FROM public.tarefas WHERE sistema = 'feedback_diario') = 'Feedback do dia',
    'tarefa do sistema pode ter o titulo editado');

  -- As 4 de bonus nunca viram atribuicao.
  BEGIN
    INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid)
    SELECT tarefaid, 100, 10 FROM public.tarefas WHERE sistema = 'feedback_diario';
    deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'tarefa de bonus nao se atribui a ninguem');

  -- As 2 de modelo continuam podendo virar atribuicao (pelos fluxos delas).
  INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid, tipofrequencia)
  SELECT tarefaid, 100, 10, 'Unica' FROM public.tarefas WHERE sistema = 'guardar_mercadoria';
  PERFORM public.exigir(true, 'tarefa de modelo pode virar atribuicao');
END $$;

-- Loja nova ja nasce com as tarefas do sistema ligadas.
DO $$
DECLARE nova integer;
BEGIN
  UPDATE public.lojas SET ativa = false WHERE lojaid = 11;
  INSERT INTO public.lojas (nome) VALUES ('Loja A4') RETURNING lojaid INTO nova;
  PERFORM public.exigir(
    (SELECT count(*) FROM public.tarefaslojas tl
      JOIN public.tarefas t ON t.tarefaid = tl.tarefaid
     WHERE t.sistema IS NOT NULL AND tl.lojaid = nova) = 6,
    'loja nova ja nasce com as 6 tarefas do sistema');
  DELETE FROM public.tarefaslojas WHERE lojaid = nova;
  DELETE FROM public.lojas WHERE lojaid = nova;
  UPDATE public.lojas SET ativa = true WHERE lojaid = 11;
END $$;

-- Tarefas de outro cliente nao existem para mim.
DO $$
DECLARE afetadas integer;
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.tarefas WHERE tarefaid = 2000) = 0,
                        'A nao ve a tarefa de B');
  UPDATE public.tarefas SET titulo = 'INVADIDA' WHERE tarefaid = 2000;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'A nao altera a tarefa de B');
  PERFORM public.exigir((SELECT count(*) FROM public.tarefaslojas WHERE tarefaid = 2000) = 0,
                        'A nao ve em quais lojas a tarefa de B vale');
END $$;

-- ===========================================================================
-- 16. Quando a tarefa recorrente cai
-- ===========================================================================

DO $$
BEGIN
  RAISE NOTICE '16. regra de quando a tarefa cai no dia';

  -- Mensal: dia que nao existe no mes cai no ultimo dia.
  PERFORM public.exigir(public.tarefa_cai_no_dia('Mensal', 31, NULL, DATE '2026-04-30'),
                        'Mensal dia 31 cai em 30 de abril');
  PERFORM public.exigir(NOT public.tarefa_cai_no_dia('Mensal', 31, NULL, DATE '2026-04-29'),
                        'Mensal dia 31 nao cai em 29 de abril');
  PERFORM public.exigir(public.tarefa_cai_no_dia('Mensal', 30, NULL, DATE '2026-02-28'),
                        'Mensal dia 30 cai em 28 de fevereiro');
  PERFORM public.exigir(public.tarefa_cai_no_dia('Mensal', 15, NULL, DATE '2026-04-15'),
                        'Mensal dia 15 cai no dia 15');
  PERFORM public.exigir(NOT public.tarefa_cai_no_dia('Mensal', 15, NULL, DATE '2026-04-30'),
                        'Mensal dia 15 nao cai no fim do mes');

  -- Semanal: 1 = domingo ... 7 = sabado.
  PERFORM public.exigir(public.tarefa_cai_no_dia('Semanal', 1, NULL, DATE '2026-04-05'),
                        'Semanal 1 cai no domingo');
  PERFORM public.exigir(public.tarefa_cai_no_dia('Semanal', 2, NULL, DATE '2026-04-06'),
                        'Semanal 2 cai na segunda');
  PERFORM public.exigir(NOT public.tarefa_cai_no_dia('Semanal', 2, NULL, DATE '2026-04-07'),
                        'Semanal 2 nao cai na terca');

  -- Diaria e Unica.
  PERFORM public.exigir(public.tarefa_cai_no_dia('Diaria', NULL, NULL, DATE '2026-04-07'),
                        'Diaria cai todo dia');
  PERFORM public.exigir(public.tarefa_cai_no_dia('Unica', NULL, TIMESTAMPTZ '2026-04-01 10:00-03', DATE '2026-04-10'),
                        'Unica atrasada continua aparecendo (acumula)');
  PERFORM public.exigir(NOT public.tarefa_cai_no_dia('Unica', NULL, TIMESTAMPTZ '2026-04-10 10:00-03', DATE '2026-04-01'),
                        'Unica nao aparece antes da data marcada');
END $$;

-- ===========================================================================
-- 17. Entregas: registrar, aprovar, recusar e estornar
-- ===========================================================================

RESET ROLE;
DO $$
BEGIN
  PERFORM set_config('teste.entrega_a', (SELECT entregaid::text FROM public.entregas WHERE atribuicaoid = 5000), false);
  PERFORM set_config('teste.entrega_b', (SELECT entregaid::text FROM public.entregas WHERE atribuicaoid = 6000), false);
END $$;
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DO $$
DECLARE
  ea integer := current_setting('teste.entrega_a')::integer;
  deu_erro boolean;
  creditou integer;
  saldo integer;
BEGIN
  RAISE NOTICE '17. aprovar, recusar e estornar';

  -- Pontos e status so mudam pelas funcoes.
  BEGIN
    UPDATE public.entregas SET statusvalidacao = 'Aprovada' WHERE entregaid = ea;
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem aprova direto na tabela, so pela funcao');

  BEGIN
    UPDATE public.funcionarios SET saldopontos = 999 WHERE funcionarioid = 100;
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem mexe no saldo direto na tabela');

  BEGIN
    INSERT INTO public.funcionarios (nomecompleto, saldopontos) VALUES ('Rico', 1000);
    deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem cadastra funcionario ja com saldo');

  -- Recusar sem motivo.
  BEGIN
    PERFORM public.recusar_entrega(ea, '   ');
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'recusar sem motivo e recusado pelo banco');

  -- Aprovar uma vez, e tentar de novo.
  creditou := public.aprovar_entrega(ea);
  PERFORM public.exigir(creditou = 5, 'aprovar credita os pontos da tarefa (5)');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 5
                    AND (SELECT pontostotal FROM public.funcionarios WHERE funcionarioid = 100) = 5,
                        'saldo e total sobem juntos');
  PERFORM public.exigir((SELECT dataaprovacao IS NOT NULL AND dataenvio IS NOT NULL
                         FROM public.entregas WHERE entregaid = ea),
                        'a aprovacao tem data propria e a data de envio continua la');

  BEGIN
    PERFORM public.aprovar_entrega(ea);
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'aprovar de novo e recusado');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 5,
                        'aprovar duas vezes NAO credita em dobro');

  -- Estornar.
  BEGIN
    PERFORM public.estornar_entrega(ea, '');
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'estornar sem motivo e recusado');

  saldo := public.estornar_entrega(ea, 'Foto de outro dia');
  PERFORM public.exigir(saldo = 0, 'estornar desconta os pontos do saldo');
  PERFORM public.exigir((SELECT pontostotal FROM public.funcionarios WHERE funcionarioid = 100) = 0,
                        'estornar desconta do total tambem');
  PERFORM public.exigir((SELECT estornadopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid
                                AND dataestorno IS NOT NULL AND motivoestorno = 'Foto de outro dia'
                         FROM public.entregas WHERE entregaid = ea),
                        'o estorno registra quem, quando e por que');

  BEGIN
    PERFORM public.estornar_entrega(ea, 'de novo');
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'estornar de novo e recusado');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 0,
                        'estornar duas vezes NAO desconta em dobro');

  -- Foto fora da pasta da propria loja.
  BEGIN
    PERFORM public.registrar_entrega(5000, NULL, '2/20/foto.jpg');
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'foto fora da pasta da propria loja e recusada');
END $$;

DO $$
DECLARE deu_erro boolean; atr integer; e1 integer; e2 integer;
BEGIN
  RAISE NOTICE '17b. sem entrega duplicada no mesmo dia';

  INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid, tipofrequencia)
  VALUES (1000, 100, 10, 'Diaria') RETURNING atribuicaoid INTO atr;

  e1 := public.registrar_entrega(atr, 'Feito', NULL, false);
  BEGIN
    PERFORM public.registrar_entrega(atr);
    deu_erro := false;
  EXCEPTION WHEN unique_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'segunda entrega da mesma atribuicao no mesmo dia e recusada');

  PERFORM public.recusar_entrega(e1, 'Sem foto');
  e2 := public.registrar_entrega(atr, NULL, NULL, true);
  PERFORM public.exigir((SELECT statusvalidacao FROM public.entregas WHERE entregaid = e2) = 'Aprovada',
                        'depois de uma recusa, nova entrega no mesmo dia e aceita');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 5,
                        '"registrar ja aprovada" credita na hora');

  PERFORM public.estornar_entrega(e2, 'Teste');
  PERFORM set_config('teste.entrega_c', public.registrar_entrega(atr)::text, false);
  PERFORM public.exigir(true, 'depois de um estorno, nova entrega no mesmo dia e aceita');

  PERFORM public.exigir(
    (SELECT count(*) FROM public.atribuicoes_para_entregar(10) WHERE atribuicaoid = atr) = 0,
    'atribuicao ja entregue hoje some da lista de "registrar"');
END $$;

DO $$
DECLARE eb integer := current_setting('teste.entrega_b')::integer; deu_erro boolean;
BEGIN
  RAISE NOTICE '17c. entregas de outro cliente';

  BEGIN PERFORM public.aprovar_entrega(eb); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao aprova entrega de B');

  BEGIN PERFORM public.recusar_entrega(eb, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao recusa entrega de B');

  BEGIN PERFORM public.estornar_entrega(eb, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao estorna entrega de B');

  BEGIN PERFORM public.registrar_entrega(6000); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao registra entrega em atribuicao de B');

  PERFORM public.exigir((SELECT count(*) FROM storage.objects WHERE name LIKE '2/%') = 0,
                        'A nao ve nenhuma foto de B');
  PERFORM public.exigir((SELECT count(*) FROM public.atribuicoes_para_entregar(20)) = 0,
                        'A nao ve o que B tem para entregar');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.ranking_pontos('2000-01-01', '2100-01-01')
                                    WHERE funcionarioid = 200),
                        'o ranking de A nao mostra ninguem de B');
END $$;

-- Saldo pode ficar negativo no estorno (a pessoa ja gastou os pontos num premio).
DO $$
DECLARE saldo integer; premio integer;
BEGIN
  PERFORM public.aprovar_entrega(current_setting('teste.entrega_c')::integer);
  INSERT INTO public.produtosloja (nome, custoempontos) VALUES ('Brinde de teste', 3) RETURNING produtoid INTO premio;
  PERFORM public.registrar_troca(100, premio, 10, true);
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 2,
                        'resgate de 3 pontos deixa o saldo em 2');
  saldo := public.estornar_entrega(current_setting('teste.entrega_c')::integer, 'Ja tinha trocado por premio');
  PERFORM public.exigir(saldo = -3, 'o estorno pode deixar o saldo negativo (2 - 5 = -3)');
END $$;

-- Nada de B foi tocado.
RESET ROLE;
DO $$
BEGIN
  PERFORM public.exigir((SELECT statusvalidacao FROM public.entregas
                         WHERE entregaid = current_setting('teste.entrega_b')::integer) = 'Pendente',
                        'a entrega de B continua pendente');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 200) = 0,
                        'o saldo de B continua intacto');
END $$;
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 18. Gestor e responsavel pelos agendamentos da loja
-- ===========================================================================

INSERT INTO public.funcionarios (funcionarioid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES (101, 'Sem loja');

DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '18. gestor e responsavel pelos agendamentos';

  UPDATE public.lojas SET gestorid = 100, responsavelagendamentosid = 100 WHERE lojaid = 10;
  PERFORM public.exigir((SELECT gestorid FROM public.lojas WHERE lojaid = 10) = 100,
                        'quem trabalha na loja pode ser o gestor dela');

  BEGIN
    UPDATE public.lojas SET gestorid = 101 WHERE lojaid = 10;
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'quem nao trabalha na loja nao pode ser o gestor');

  BEGIN
    UPDATE public.lojas SET responsavelagendamentosid = 200 WHERE lojaid = 10;
    deu_erro := false;
  EXCEPTION WHEN foreign_key_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'funcionario de outro cliente nao pode ser o responsavel');

  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.configuracoes
                                    WHERE chave IN ('ID_GESTOR_PADRAO', 'RESPONSAVEL_AGENDAMENTOS_ID')),
                        'as duas chaves soltas sairam das configuracoes');
END $$;

-- ===========================================================================
-- 19. Painel da loja, resumo e links de TV
-- ===========================================================================

DO $$
DECLARE p jsonb; deu_erro boolean;
BEGIN
  RAISE NOTICE '19. painel da loja e resumo';

  p := public.painel_da_loja(10);
  PERFORM public.exigir(p->>'loja' = 'Loja A1', 'A ve o painel da propria loja');
  PERFORM public.exigir(
    (p->'progresso'->>'total')::integer =
      (p->'progresso'->>'aprovadas')::integer + (p->'progresso'->>'emvalidacao')::integer
      + jsonb_array_length(p->'parafazer'),
    'a barra fecha: total = aprovadas + em validacao + para fazer');
  PERFORM public.exigir(p::text NOT LIKE '%id"%', 'o painel nao expoe nenhum id');

  BEGIN PERFORM public.painel_da_loja(20); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao ve o painel da loja de B');

  PERFORM public.exigir(public.resumo_das_lojas()::text NOT LIKE '%Loja B1%', 'o resumo de A nao tem lojas de B');
  PERFORM public.exigir(jsonb_array_length(public.resumo_das_lojas()) = (SELECT count(*) FROM public.lojas WHERE ativa),
                        'o resumo tem um cartao por loja ativa');

  PERFORM set_config('teste.tv_a',  public.criar_link_tv(10, 'TV do balcao'),  false);
  PERFORM set_config('teste.tv_a2', public.criar_link_tv(11, 'TV da cozinha'), false);
  PERFORM public.exigir(length(current_setting('teste.tv_a')) = 64, 'o codigo do link tem 64 caracteres');

  BEGIN PERFORM tokenhash FROM public.linkstv; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono le a impressao digital do link');

  BEGIN INSERT INTO public.linkstv (lojaid, nome, tokenhash) VALUES (10, 'pirata', repeat('a', 64)); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'link so nasce pela funcao');

  BEGIN PERFORM public.criar_link_tv(20, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao cria link de TV para a loja de B');
END $$;

RESET ROLE;
DO $$ BEGIN
  PERFORM set_config('teste.id_tv_a', (SELECT linktvid::text FROM public.linkstv WHERE nome = 'TV do balcao'), false);
END $$;
SET ROLE authenticated;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM set_config('teste.tv_b', public.criar_link_tv(20, 'TV de B'), false);

  BEGIN PERFORM public.painel_da_loja(10); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao ve o painel da loja de A');

  PERFORM public.exigir((SELECT count(*) FROM public.linkstv) = 1, 'B so ve o proprio link de TV');

  BEGIN PERFORM public.revogar_link_tv(current_setting('teste.id_tv_a')::integer); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao revoga o link de TV de A');
END $$;

-- Como um visitante sem login (a TV).
RESET ROLE;
SET ROLE anon;
SET teste.uid = '';
DO $$
BEGIN
  PERFORM set_config('teste.r_a',     public.painel_da_tv(current_setting('teste.tv_a'))::text, false);
  PERFORM set_config('teste.r_b',     public.painel_da_tv(current_setting('teste.tv_b'))::text, false);
  PERFORM set_config('teste.r_inv',   public.painel_da_tv(repeat('0', 64))::text, false);
  PERFORM set_config('teste.r_nulo',  public.painel_da_tv(NULL)::text, false);
  PERFORM set_config('teste.r_curto', public.painel_da_tv('abc')::text, false);

  BEGIN PERFORM 1 FROM public.lojas LIMIT 1; PERFORM set_config('teste.anon_tabela', 'leu', false);
  EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('teste.anon_tabela', 'barrado', false); END;

  BEGIN PERFORM public.painel_da_loja(10); PERFORM set_config('teste.anon_painel', 'chamou', false);
  EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('teste.anon_painel', 'barrado', false); END;

  BEGIN PERFORM public.minha_conta(); PERFORM set_config('teste.anon_funcao', 'chamou', false);
  EXCEPTION WHEN insufficient_privilege THEN PERFORM set_config('teste.anon_funcao', 'barrado', false); END;
END $$;
RESET ROLE;

DO $$
DECLARE r jsonb := current_setting('teste.r_a')::jsonb;
BEGIN
  RAISE NOTICE '19b. modo TV';
  PERFORM public.exigir((r->>'disponivel')::boolean AND r->>'loja' = 'Loja A1', 'o link da loja A1 mostra a loja A1');
  PERFORM public.exigir(r::text NOT LIKE '%Loja B1%' AND r::text NOT LIKE '%Bruno%', 'o link de A nao mostra nada de B');
  PERFORM public.exigir(r::text NOT LIKE '%Loja A2%', 'o link da loja A1 nao mostra a outra loja do mesmo cliente');
  PERFORM public.exigir(r::text LIKE '%Ana A.%' AND r::text NOT LIKE '%Ana da conta A%', 'a TV mostra so "Nome I."');
  PERFORM public.exigir(r::text NOT LIKE '%.jpg%' AND r::text NOT LIKE '%observacao%'
                    AND r::text NOT LIKE '%Feito%' AND r::text NOT LIKE '%cpf%' AND r::text NOT LIKE '%telefone%',
                        'a TV nao recebe foto, observacao, CPF nem telefone');
  PERFORM public.exigir(r::text NOT LIKE '%id"%', 'a TV nao recebe nenhum id');
  PERFORM public.exigir(current_setting('teste.r_b')::jsonb->>'loja' = 'Loja B1', 'o link de B mostra so a loja de B');

  PERFORM public.exigir(current_setting('teste.r_inv')::jsonb   = '{"disponivel": false}'::jsonb, 'codigo inventado nao devolve nada');
  PERFORM public.exigir(current_setting('teste.r_nulo')::jsonb  = '{"disponivel": false}'::jsonb, 'codigo vazio nao devolve nada');
  PERFORM public.exigir(current_setting('teste.r_curto')::jsonb = '{"disponivel": false}'::jsonb, 'codigo curto nao devolve nada');

  PERFORM public.exigir(current_setting('teste.anon_tabela') = 'barrado', 'visitante sem login nao le tabela nenhuma');
  PERFORM public.exigir(current_setting('teste.anon_painel') = 'barrado', 'visitante sem login nao chama o painel logado');
  PERFORM public.exigir(current_setting('teste.anon_funcao') = 'barrado', 'visitante sem login nao chama outras funcoes');

  PERFORM public.exigir((SELECT ultimouso IS NOT NULL FROM public.linkstv WHERE nome = 'TV do balcao'),
                        'o link registra a data do ultimo uso');
END $$;

-- Revogado, loja desativada, conta suspensa.
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$ BEGIN
  PERFORM public.revogar_link_tv((SELECT linktvid FROM public.linkstv WHERE nome = 'TV da cozinha'));
  PERFORM set_config('teste.tv_a3', public.criar_link_tv(11, 'TV da vitrine'), false);
END $$;
UPDATE public.lojas SET ativa = false WHERE lojaid = 11;
RESET ROLE;
UPDATE public.contas SET status = 'suspensa' WHERE contaid = 2;

SET ROLE anon;
SET teste.uid = '';
DO $$ BEGIN
  PERFORM set_config('teste.r_revogado',   public.painel_da_tv(current_setting('teste.tv_a2'))::text, false);
  PERFORM set_config('teste.r_desativada', public.painel_da_tv(current_setting('teste.tv_a3'))::text, false);
  PERFORM set_config('teste.r_suspensa',   public.painel_da_tv(current_setting('teste.tv_b'))::text, false);
  PERFORM set_config('teste.r_a_segue',    public.painel_da_tv(current_setting('teste.tv_a'))::text, false);
END $$;
RESET ROLE;
UPDATE public.contas SET status = 'ativa' WHERE contaid = 2;
UPDATE public.lojas SET ativa = true WHERE lojaid = 11;

DO $$
BEGIN
  PERFORM public.exigir(current_setting('teste.r_revogado')::jsonb   = '{"disponivel": false}'::jsonb, 'link revogado para de funcionar');
  PERFORM public.exigir(current_setting('teste.r_desativada')::jsonb = '{"disponivel": false}'::jsonb, 'link de loja desativada para de funcionar');
  PERFORM public.exigir(current_setting('teste.r_suspensa')::jsonb   = '{"disponivel": false}'::jsonb, 'link de conta suspensa para de funcionar');
  PERFORM public.exigir((current_setting('teste.r_a_segue')::jsonb->>'disponivel')::boolean,
                        'suspender o cliente B nao derruba a TV do cliente A');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 20. Loja de premios, resgates, abate na comanda e extrato
-- ===========================================================================

RESET ROLE;
DO $$ BEGIN
  PERFORM public.cria_produtos_do_sistema(1);
  PERFORM public.cria_produtos_do_sistema(2);
END $$;
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DO $$
DECLARE
  deu_erro boolean; bombom integer; camiseta integer; caneca integer; r integer; t integer; atr integer;
  saldo integer;
BEGIN
  RAISE NOTICE '20. loja de premios e resgates';

  INSERT INTO public.produtosloja (nome, custoempontos, estoquedisponivel) VALUES ('Bombom', 10, 1)   RETURNING produtoid INTO bombom;
  INSERT INTO public.produtosloja (nome, custoempontos)                    VALUES ('Camiseta', 1000)  RETURNING produtoid INTO camiseta;
  INSERT INTO public.produtosloja (nome, custoempontos, estoquedisponivel) VALUES ('Caneca', 1, 0)    RETURNING produtoid INTO caneca;
  PERFORM set_config('teste.bombom', bombom::text, false);

  BEGIN PERFORM public.registrar_troca(100, bombom); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'com saldo negativo (-3) nao se resgata nada');

  INSERT INTO public.tarefas (titulo, pontos) VALUES ('Tarefa grande', 30) RETURNING tarefaid INTO t;
  INSERT INTO public.tarefaslojas (tarefaid, lojaid) VALUES (t, 10);
  INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid, tipofrequencia)
       VALUES (t, 100, 10, 'Diaria') RETURNING atribuicaoid INTO atr;
  PERFORM public.registrar_entrega(atr, NULL, NULL, true);
  SELECT saldopontos INTO saldo FROM public.funcionarios WHERE funcionarioid = 100;
  PERFORM public.exigir(saldo = 27, 'aprovar 30 pontos leva o saldo de -3 a 27');

  BEGIN PERFORM public.registrar_troca(100, caneca); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'premio com estoque 0 (esgotado) nao se resgata');

  BEGIN PERFORM public.registrar_troca(100, camiseta); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'resgatar sem saldo suficiente e recusado');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 27,
                        'tentativas recusadas nao mexem no saldo');

  r := public.registrar_troca(100, bombom, 10, true);
  PERFORM set_config('teste.resgate_a', r::text, false);
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 17
                    AND (SELECT estoquedisponivel FROM public.produtosloja WHERE produtoid = bombom) = 0
                    AND (SELECT status FROM public.resgates WHERE resgateid = r) = 'Entregue',
                        'resgatar desconta saldo e estoque de uma vez (e ja entrega)');

  BEGIN PERFORM public.registrar_troca(100, bombom); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o estoque acabou: o segundo bombom e recusado');

  BEGIN PERFORM public.cancelar_troca(r, 'desistiu'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'resgate ja entregue nao se cancela (se estorna)');

  BEGIN PERFORM public.estornar_troca(r, '  '); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'estornar resgate sem motivo e recusado');

  PERFORM public.estornar_troca(r, 'Veio estragado');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 27
                    AND (SELECT estoquedisponivel FROM public.produtosloja WHERE produtoid = bombom) = 1
                    AND (SELECT status FROM public.resgates WHERE resgateid = r) = 'Estornado',
                        'estornar devolve os pontos e o estoque');

  BEGIN PERFORM public.estornar_troca(r, 'de novo'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro AND (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 27,
                        'estornar duas vezes NAO devolve em dobro');

  r := public.registrar_troca(100, bombom, NULL, false);
  PERFORM public.exigir((SELECT status FROM public.resgates WHERE resgateid = r) = 'Pendente'
                    AND (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 17
                    AND (SELECT estoquedisponivel FROM public.produtosloja WHERE produtoid = bombom) = 0,
                        '"entregar depois": pontos e estoque ja ficam reservados');
  PERFORM public.cancelar_troca(r, 'Desistiu');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 27
                    AND (SELECT estoquedisponivel FROM public.produtosloja WHERE produtoid = bombom) = 1,
                        'cancelar devolve os pontos e o estoque');
  BEGIN PERFORM public.cancelar_troca(r, 'de novo'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro AND (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 27,
                        'cancelar duas vezes NAO devolve em dobro');

  r := public.registrar_troca(100, bombom, NULL, false);
  PERFORM public.concluir_troca(r);
  PERFORM public.exigir((SELECT status FROM public.resgates WHERE resgateid = r) = 'Entregue'
                    AND (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 17,
                        'entregar um pendente nao cobra de novo');
  BEGIN PERFORM public.concluir_troca(r); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'entregar duas vezes e recusado');

  BEGIN UPDATE public.resgates SET status = 'Cancelado' WHERE resgateid = r; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'resgate so muda pelas funcoes');
END $$;

DO $$
DECLARE deu_erro boolean; r integer; r2 integer; linha record;
BEGIN
  RAISE NOTICE '20b. abate na comanda';
  PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.03');

  r := public.registrar_troca_por_valor(100, 0.31, 10);
  SELECT pontosgastos, valorreais, taxaconversao INTO linha FROM public.resgates WHERE resgateid = r;
  PERFORM public.exigir(linha.pontosgastos = 11 AND linha.valorreais = 0.31 AND linha.taxaconversao = 0.03,
                        'R$ 0,31 a 0,03 custa 11 pontos (10,33 arredondado para cima)');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 6,
                        'a comanda desconta os pontos');

  BEGIN PERFORM public.registrar_troca_por_valor(100, 15.50); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'comanda acima do saldo e recusada pelo banco');

  BEGIN PERFORM public.registrar_troca_por_valor(100, 0); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'comanda de valor zero e recusada');

  PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.05');
  r2 := public.registrar_troca_por_valor(100, 0.30);
  PERFORM public.exigir((SELECT pontosgastos FROM public.resgates WHERE resgateid = r2) = 6,
                        'taxa nova (0,05) vale para a comanda nova: R$ 0,30 = 6 pontos');
  SELECT pontosgastos, valorreais, taxaconversao INTO linha FROM public.resgates WHERE resgateid = r;
  PERFORM public.exigir(linha.pontosgastos = 11 AND linha.valorreais = 0.31 AND linha.taxaconversao = 0.03,
                        'a comanda antiga mantem o valor, os pontos e a taxa que registrou');

  BEGIN PERFORM public.registrar_troca(100, (SELECT produtoid FROM public.produtosloja WHERE sistema = 'abate_comanda'));
        deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o premio do sistema nao sai pelo catalogo');

  BEGIN DELETE FROM public.produtosloja WHERE sistema = 'abate_comanda'; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o premio do sistema nao pode ser apagado');

  BEGIN UPDATE public.produtosloja SET sistema = 'abate_comanda' WHERE nome = 'Camiseta'; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem marca um premio comum como do sistema');

  PERFORM public.estornar_troca(r, 'Lancado errado');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 100) = 11,
                        'estornar a comanda devolve os 11 pontos');

  PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.03');
END $$;

DO $$
DECLARE x jsonb; deu_erro boolean; hoje date := public.dia_em_sao_paulo(now());
BEGIN
  RAISE NOTICE '20c. extrato de pontos';
  x := public.extrato_pontos(100, DATE '2000-01-01', DATE '2100-01-01');
  PERFORM public.exigir((x->>'confere')::boolean, 'o saldo bate com a soma do extrato');
  PERFORM public.exigir((x->>'saldofinal')::integer = (x->>'saldoatual')::integer,
                        'saldo final do periodo inteiro = saldo atual');
  PERFORM public.exigir(((x->'movimentos'->-1)->>'saldoapos')::integer = (x->>'saldoatual')::integer,
                        'o ultimo "saldo apos" e o saldo atual');
  PERFORM public.exigir(x::text LIKE '%Tarefa aprovada%' AND x::text LIKE '%Estorno:%'
                    AND x::text LIKE '%Resgate: Bombom%' AND x::text LIKE '%Resgate cancelado%'
                    AND x::text LIKE '%Resgate estornado%' AND x::text LIKE '%Abate na comanda: R$ 0,31%',
                        'o extrato mostra aprovacoes, estornos, resgates, cancelamentos e comandas');
  PERFORM public.exigir((x->>'taxa')::numeric = 0.03, 'o extrato traz a taxa atual, para mostrar em R$');

  x := public.extrato_pontos(100, hoje + 1, hoje + 1);
  PERFORM public.exigir((x->>'saldoinicial')::integer = (x->>'saldoatual')::integer
                    AND jsonb_array_length(x->'movimentos') = 0,
                        'periodo futuro: saldo inicial = saldo atual, sem movimentos');

  BEGIN PERFORM public.extrato_pontos(200, DATE '2000-01-01', DATE '2100-01-01'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao ve o extrato de ninguem de B');

  BEGIN INSERT INTO public.movimentospontos (funcionarioid, tipo, pontos, descricao) VALUES (100, 'bonus', 1000, 'presente');
        deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o navegador nao grava movimento de pontos');
END $$;

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean; pb integer;
BEGIN
  RAISE NOTICE '20d. premios e resgates de outro cliente';
  INSERT INTO public.produtosloja (nome, custoempontos) VALUES ('Premio de B', 5) RETURNING produtoid INTO pb;
  PERFORM set_config('teste.premio_b', pb::text, false);

  PERFORM public.exigir((SELECT count(*) FROM public.produtosloja WHERE nome IN ('Bombom', 'Camiseta')) = 0,
                        'B nao ve os premios de A');
  PERFORM public.exigir((SELECT count(*) FROM public.resgates) = 0, 'B nao ve os resgates de A');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos) = 0, 'B nao ve os movimentos de A');

  BEGIN PERFORM public.registrar_troca(100, pb); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao resgata para um funcionario de A');

  BEGIN PERFORM public.estornar_troca(current_setting('teste.resgate_a')::integer, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao estorna resgate de A');

  BEGIN PERFORM public.registrar_troca_por_valor(100, 1); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao faz comanda para funcionario de A');
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.registrar_troca(100, current_setting('teste.premio_b')::integer); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao resgata um premio de B');
END $$;

-- ===========================================================================
-- 23. Dia de trabalho: folga semanal, domingo de folga e afastamento
-- ===========================================================================

DO $$
BEGIN
  RAISE NOTICE '23. dia de trabalho (mesma regra da nota e da sequencia)';
  -- setembro de 2026: dia 13 e o 2o domingo, dia 14 e segunda-feira
  PERFORM public.exigir(NOT public.dia_de_trabalho(1, 0, NULL, NULL, '2026-09-13'), 'folga no domingo: domingo nao conta');
  PERFORM public.exigir(NOT public.dia_de_trabalho(2, 0, NULL, NULL, '2026-09-14'), 'folga na segunda: segunda nao conta');
  PERFORM public.exigir(public.dia_de_trabalho(2, 0, NULL, NULL, '2026-09-15'),     'folga na segunda: terca conta');
  PERFORM public.exigir(NOT public.dia_de_trabalho(0, 2, NULL, NULL, '2026-09-13'), '2o domingo de folga: dia 13 nao conta');
  PERFORM public.exigir(public.dia_de_trabalho(0, 2, NULL, NULL, '2026-09-20'),     '2o domingo de folga: dia 20 conta');
  PERFORM public.exigir(NOT public.dia_de_trabalho(0, 0, '2026-09-10', '2026-09-12', '2026-09-12'), 'ultimo dia de afastamento nao conta');
  PERFORM public.exigir(public.dia_de_trabalho(0, 0, '2026-09-10', '2026-09-12', '2026-09-13'),     'dia seguinte ao afastamento conta');
END $$;

-- ===========================================================================
-- 24. Conquistas
-- ===========================================================================

RESET ROLE;
-- Carla (110) na Loja A1, com uma tarefa diaria. Entregas de dias passados
-- (hoje-10, hoje-9 e hoje-7), com afastamento no dia hoje-8.
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, datainicioafastamento, datafimafastamento)
  OVERRIDING SYSTEM VALUE
  VALUES (110, 1, 'Carla da conta A', public.dia_em_sao_paulo(now()) - 8, public.dia_em_sao_paulo(now()) - 8);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (1100, 1, 'Abrir o caixa', 3);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (1, 110, 10);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (1, 1100, 10);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
  OVERRIDING SYSTEM VALUE VALUES (5100, 1, 1100, 110, 10, 'Diaria', now() - interval '30 days');
INSERT INTO public.entregas (entregaid, contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio)
  OVERRIDING SYSTEM VALUE
  SELECT 7100 + d, 1, 1100, 110, 10, 5100,
         ((public.dia_em_sao_paulo(now()) - d)::timestamp + time '12:00') AT TIME ZONE 'America/Sao_Paulo'
    FROM unnest(ARRAY[10, 9, 7]) d;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DO $$
DECLARE r jsonb; k1 integer; k2 integer; k3 integer; k4 integer; k5 integer; k6 integer; k7 integer;
        deu_erro boolean; x jsonb; e integer; hoje date := public.dia_em_sao_paulo(now());
BEGIN
  RAISE NOTICE '24. conquistas';

  -- "So a partir de hoje", criada ANTES das aprovacoes das entregas antigas.
  k1 := (public.criar_conquista('Estreia', NULL, '🌟', 'total_tarefas_aprovadas', 1, NULL, 7, false))->>'conquistaid';
  PERFORM public.aprovar_entrega(7110);
  PERFORM public.aprovar_entrega(7109);
  PERFORM public.aprovar_entrega(7107);
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k1),
                        '"so a partir de hoje" ignora tarefas enviadas antes da criacao');

  r  := public.criar_conquista('Tres tarefas', 'Fez 3 tarefas', '🥉', 'total_tarefas_aprovadas', 3, NULL, 10, true);
  k2 := r->>'conquistaid';
  PERFORM public.exigir((r->>'concedidas')::integer >= 1, 'retroativa concede na hora a quem ja cumpre');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k2),
                        'Carla ganhou "3 tarefas" pelo historico');

  k3 := (public.criar_conquista('Ritmo', NULL, NULL, 'tarefas_aprovadas_periodo', 3, 4, 0, true))->>'conquistaid';
  k4 := (public.criar_conquista('Ritmo forte', NULL, NULL, 'tarefas_aprovadas_periodo', 3, 3, 0, true))->>'conquistaid';
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k3),
                        '3 tarefas em 4 dias: concedida');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k4),
                        '3 tarefas em 3 dias: nao concedida');

  k5 := (public.criar_conquista('Sequencia de 3', NULL, '🔥', 'sequencia_dias_tarefas', 3, NULL, 5, true))->>'conquistaid';
  k6 := (public.criar_conquista('Sequencia de 4', NULL, NULL, 'sequencia_dias_tarefas', 4, NULL, 5, true))->>'conquistaid';
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k5),
                        'o dia de afastamento nao quebra a sequencia (3 dias)');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k6),
                        'nem conta como dia feito (4 dias nao fecha)');
  PERFORM set_config('teste.k5', k5::text, false);

  k7 := (public.criar_conquista('Feedback em dia', NULL, NULL, 'sequencia_feedback_diario', 1, NULL, 5, true))->>'conquistaid';
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE conquistaid = k7),
                        'conquista de modulo que ainda nao existe fica cadastrada, sem conceder');

  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 110) = 24,
                        'bonus entrou no saldo: 3 tarefas x 3 + 10 + 5 = 24');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos
                          WHERE funcionarioid = 110 AND tipo = 'bonus' AND conquistafuncionarioid IS NOT NULL) = 2,
                        'cada bonus e um movimento do livro ligado a conquista');
  x := public.extrato_pontos(110, hoje - 30, hoje);
  PERFORM public.exigir((x->>'confere')::boolean
                        AND EXISTS (SELECT 1 FROM jsonb_array_elements(x->'movimentos') m
                                     WHERE m->>'descricao' LIKE 'Conquista:%Tres tarefas' AND (m->>'pontos')::integer = 10),
                        'o bonus aparece no extrato, e o extrato bate com o saldo');

  -- Entrega de hoje: agora a "so a partir de hoje" vale; as outras nao repetem.
  e := public.registrar_entrega(5100, NULL, NULL, true);
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k1),
                        '"so a partir de hoje" conta a tarefa enviada depois da criacao');
  PERFORM public.exigir((SELECT count(*) FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k2) = 1,
                        'a mesma conquista nao e concedida duas vezes');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 110) = 34,
                        'saldo 24 + tarefa 3 + bonus 7 = 34');

  PERFORM public.estornar_entrega(e, 'Teste de estorno');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 110 AND conquistaid = k1),
                        'estorno nao retira a conquista');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 110) = 31,
                        'o estorno tira so os pontos da tarefa (34 - 3 = 31)');

  -- A regra nao muda depois de criada; nome, bonus e ativa podem mudar.
  BEGIN UPDATE public.conquistas SET criteriovalor = 1 WHERE conquistaid = k2; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege OR restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'a regra da conquista nao muda depois de criada');
  UPDATE public.conquistas SET nome = 'Tres tarefas!', pontosbonus = 12 WHERE conquistaid = k2;
  PERFORM public.exigir((SELECT nome FROM public.conquistas WHERE conquistaid = k2) = 'Tres tarefas!', 'o nome e o bonus podem mudar');

  BEGIN INSERT INTO public.conquistasfuncionarios (funcionarioid, conquistaid) VALUES (100, k6); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem concede conquista na mao');

  BEGIN INSERT INTO public.conquistas (nome, descricao, criteriotipo, criteriovalor) VALUES ('X', 'X', 'total_tarefas_aprovadas', 1);
        deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'conquista so e criada pela funcao (que decide o historico)');

  BEGIN PERFORM public.criar_conquista('X', NULL, NULL, 'tipo_inventado', 1, NULL, 0, true); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'tipo de regra desconhecido e recusado');
  BEGIN PERFORM public.criar_conquista('X', NULL, NULL, 'tarefas_aprovadas_periodo', 3, NULL, 0, true); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, '"N tarefas em X dias" exige o X');
  BEGIN PERFORM public.criar_conquista('X', NULL, NULL, 'total_tarefas_aprovadas', 0, NULL, 0, true); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'meta zero e recusada');
END $$;

RESET ROLE;
DO $$
DECLARE deu_erro boolean; k5 integer := current_setting('teste.k5')::integer;
BEGIN
  BEGIN UPDATE public.conquistas SET criteriovalor = 1 WHERE conquistaid = k5; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco muda a regra de uma conquista');

  PERFORM public.exigir(public.avaliar_conquistas(1, 110) = 0, 'avaliar de novo nao concede nada repetido');

  UPDATE public.funcionarios SET datainicioafastamento = NULL, datafimafastamento = NULL WHERE funcionarioid = 110;
  PERFORM public.exigir(NOT public.pessoa_cumpre_conquista(1, 110, k5),
                        'sem o afastamento, o dia vazio quebraria a sequencia');
END $$;

-- ===========================================================================
-- 25. Nota do ranking mensal e relatorios (mes passado, Loja A2)
-- ===========================================================================

-- Duda (120): sem folga, tarefa diaria de 2 pontos o mes todo + uma unica;
--   entrega so nos 5 primeiros dias.
-- Edu  (121): mesma tarefa, afastado do dia 6 ao fim do mes; entrega nos 5.
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, datainicioafastamento, datafimafastamento)
  OVERRIDING SYSTEM VALUE VALUES
  (120, 1, 'Duda da conta A', NULL, NULL),
  (121, 1, 'Edu da conta A',
   (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 month')::date + 5,
   (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 day')::date);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (1200, 1, 'Repor gelo', 2);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (1, 120, 11), (1, 121, 11);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (1, 1200, 11);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao, dataagendamento)
  OVERRIDING SYSTEM VALUE
  SELECT a.id, 1, 1200, a.f, 11, a.tipo, ini::timestamp AT TIME ZONE 'America/Sao_Paulo', a.agenda
    FROM (SELECT (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 month')::date AS ini) m,
         LATERAL (VALUES (5200, 120, 'Diaria', NULL::timestamptz),
                         (5201, 121, 'Diaria', NULL::timestamptz),
                         (5202, 120, 'Unica', ((m.ini + 2)::timestamp + time '10:00') AT TIME ZONE 'America/Sao_Paulo')) a(id, f, tipo, agenda);
INSERT INTO public.entregas (entregaid, contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio)
  OVERRIDING SYSTEM VALUE
  SELECT 7200 + p.i * 10 + d, 1, 1200, p.f, 11, p.a,
         ((m.ini + d)::timestamp + time '12:00') AT TIME ZONE 'America/Sao_Paulo'
    FROM (SELECT (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 month')::date AS ini) m,
         (VALUES (0, 120, 5200), (1, 121, 5201)) p(i, f, a),
         generate_series(0, 4) d;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE e record;
BEGIN
  FOR e IN SELECT entregaid FROM public.entregas WHERE entregaid BETWEEN 7200 AND 7219 ORDER BY 1 LOOP
    PERFORM public.aprovar_entrega(e.entregaid);
  END LOOP;
END $$;
RESET ROLE;
UPDATE public.entregas SET dataaprovacao = dataenvio WHERE entregaid BETWEEN 7200 AND 7219;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE
  ini date := (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 month')::date;
  fim date := (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 day')::date;
  dias integer;
  duda record; edu record; atual record; n integer; x jsonb;
BEGIN
  RAISE NOTICE '25. nota do ranking mensal e relatorios';
  dias := fim - ini + 1;

  SELECT * INTO duda FROM public.ranking_mensal(extract(year FROM ini)::integer, extract(month FROM ini)::integer, 11) WHERE funcionarioid = 120;
  SELECT * INTO edu  FROM public.ranking_mensal(extract(year FROM ini)::integer, extract(month FROM ini)::integer, 11) WHERE funcionarioid = 121;

  PERFORM public.exigir(duda.pontospossiveis = dias * 2 + 2,
                        'possiveis da Duda: todo dia do mes + a tarefa unica (' || duda.pontospossiveis || ')');
  PERFORM public.exigir(edu.pontospossiveis = 10, 'possiveis do Edu: so os 5 dias antes do afastamento');
  PERFORM public.exigir(edu.confiabilidade = 100 AND edu.esforco = 100 AND edu.nota = 100,
                        'Edu fez tudo o que podia: nota 100');
  PERFORM public.exigir(duda.confiabilidade = round(10 * 100.0 / (dias * 2 + 2), 2)
                        AND duda.nota = round(duda.confiabilidade * 0.5 + 50, 2),
                        'Duda: confiabilidade baixa, esforco igual, nota ' || duda.nota);
  PERFORM public.exigir(duda.pontosganhos = 10,
                        'bonus de conquista nao entra no ranking (Duda ganhou bonus, mas conta 10)');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.movimentospontos WHERE funcionarioid = 120 AND tipo = 'bonus'),
                        '(e ela de fato recebeu bonus de conquista)');
  PERFORM public.exigir((SELECT funcionarioid FROM public.ranking_mensal(extract(year FROM ini)::integer, extract(month FROM ini)::integer, 11) LIMIT 1) = 121,
                        'Edu fica na frente da Duda');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.ranking_mensal(extract(year FROM ini)::integer, extract(month FROM ini)::integer, 11)
                                     WHERE funcionarioid NOT IN (120, 121)),
                        'o filtro de loja deixa so quem tem tarefa na Loja A2');

  -- Mes corrente: conta ate ontem.
  IF extract(day FROM public.dia_em_sao_paulo(now())) > 1 THEN
    SELECT * INTO atual FROM public.ranking_mensal(extract(year FROM now())::integer,
                                                   extract(month FROM public.dia_em_sao_paulo(now()))::integer, 11)
     WHERE funcionarioid = 120;
    PERFORM public.exigir(atual.pontospossiveis = (extract(day FROM public.dia_em_sao_paulo(now()))::integer - 1) * 2,
                          'no mes corrente a nota vai ate ontem');
  END IF;

  x := public.pendencias_da_pessoa(120, ini, fim);
  PERFORM public.exigir(jsonb_array_length(x) = dias - 5 + 1,
                        'pendencias da Duda: dias sem entrega + a tarefa unica (' || jsonb_array_length(x) || ')');
  PERFORM public.exigir(jsonb_array_length(public.pendencias_da_pessoa(121, ini, fim)) = 0,
                        'afastamento nao gera pendencia');
  PERFORM public.exigir(jsonb_array_length(public.historico_da_pessoa(120)) = 5, 'historico da Duda: 5 entregas');
  x := public.analise_de_tarefas(ini, fim, 11);
  PERFORM public.exigir((x->0->>'titulo') = 'Repor gelo' AND (x->0->>'aprovadas')::integer = 10,
                        'analise por tarefa: 10 aprovadas de "Repor gelo"');
END $$;

-- ===========================================================================
-- 26. Configuracoes: validadas, so o master altera, com historico
-- ===========================================================================

RESET ROLE;
INSERT INTO auth.users (id, email, email_confirmed_at)
  VALUES ('12121212-1212-1212-1212-121212121212', 'gerente.a@exemplo.com', now());
INSERT INTO public.contasusuarios (contaid, userid, papel) VALUES (1, '12121212-1212-1212-1212-121212121212', 'gerente');
SELECT public.cria_configuracoes_padrao(2);

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean; h record; v text;
BEGIN
  RAISE NOTICE '26. configuracoes';

  BEGIN PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'taxa zero e recusada');
  BEGIN PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '-0.01'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'taxa negativa e recusada');
  BEGIN PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', 'abc'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'taxa que nao e numero e recusada');

  v := public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0,04');
  PERFORM public.exigir(v = '0.04', 'taxa com virgula e aceita (0,04)');
  SELECT * INTO h FROM public.configuracoeshistorico ORDER BY historicoid DESC LIMIT 1;
  PERFORM public.exigir(h.chave = 'TAXA_CONVERSAO_PONTO_REAL' AND h.valoranterior = '0.03' AND h.valornovo = '0.04'
                        AND h.alteradopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND h.alteradoem IS NOT NULL,
                        'a mudanca fica registrada: quem, quando, valor antigo e novo');
  PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.03');

  BEGIN PERFORM public.alterar_configuracao('HORARIO_FECHAMENTO_MENSAL', '25:00'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'horario invalido e recusado');
  PERFORM public.exigir(public.alterar_configuracao('HORARIO_FECHAMENTO_MENSAL', '07:30') = '07:30', 'horario valido e aceito');

  BEGIN PERFORM public.alterar_configuracao('PONTOS_BONUS_NOTA_FISCAL', '-5'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'pontos de bonus negativos sao recusados');
  BEGIN PERFORM public.alterar_configuracao('PONTOS_BONUS_NOTA_FISCAL', '2.5'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'pontos de bonus quebrados sao recusados');
  PERFORM public.exigir(public.alterar_configuracao('PONTOS_BONUS_NOTA_FISCAL', '15') = '15', 'pontos de bonus validos sao aceitos');

  BEGIN PERFORM public.alterar_configuracao('TAREFA_ID_LEITURA', '1'); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'os IDs do sistema nao se alteram pela tela');
  BEGIN PERFORM public.alterar_configuracao('CHAVE_INVENTADA', '1'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'chave que nao existe e recusada');

  BEGIN UPDATE public.configuracoes SET valor = '9' WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL'; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem altera a tabela direto (so pela funcao, que registra)');
  BEGIN INSERT INTO public.configuracoes (chave, valor) VALUES ('NOVA', '1'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem cria chave nova');
END $$;

SET teste.uid = '12121212-1212-1212-1212-121212121212';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.05'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'gerente nao altera configuracao (so o master)');
END $$;

SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.05'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao altera configuracao');
END $$;

-- ===========================================================================
-- 27. Conquistas, relatorios e configuracoes de outro cliente
-- ===========================================================================

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE afetadas integer; ini date := (date_trunc('month', public.dia_em_sao_paulo(now())) - interval '1 month')::date;
BEGIN
  RAISE NOTICE '27. conquistas, relatorios e configuracoes de outro cliente';
  PERFORM public.exigir((SELECT count(*) FROM public.conquistas) = 0, 'B nao ve as conquistas de A');
  PERFORM public.exigir((SELECT count(*) FROM public.conquistasfuncionarios) = 0, 'B nao ve quem ganhou conquista em A');
  PERFORM public.exigir((SELECT count(*) FROM public.configuracoeshistorico) = 0, 'B nao ve o historico de configuracoes de A');
  UPDATE public.conquistas SET nome = 'INVADIDA';
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'B nao altera conquista de A');

  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.ranking_mensal(extract(year FROM ini)::integer, extract(month FROM ini)::integer)),
                        'o ranking mensal de B nao mostra ninguem de A');
  PERFORM public.exigir(public.pendencias_da_pessoa(120, ini, ini + 27) = '[]'::jsonb, 'B nao ve pendencias de funcionario de A');
  PERFORM public.exigir(public.historico_da_pessoa(120) = '[]'::jsonb, 'B nao ve historico de funcionario de A');
  PERFORM public.exigir(public.analise_de_tarefas(ini, ini + 27) = '[]'::jsonb, 'B nao ve analise de tarefas de A');
  PERFORM public.exigir(public.listar_trocas() = '[]'::jsonb OR NOT EXISTS (
                          SELECT 1 FROM jsonb_array_elements(public.listar_trocas()) t WHERE (t->>'funcionarioid')::integer = 100),
                        'B nao ve as trocas de A');

  PERFORM public.alterar_configuracao('TAXA_CONVERSAO_PONTO_REAL', '0.09');
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
BEGIN
  PERFORM public.exigir((SELECT valor FROM public.configuracoes WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL') = '0.03',
                        'B mudar a propria taxa nao mexe na taxa de A');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.configuracoeshistorico WHERE valornovo = '0.09'),
                        'A nao ve o historico de B');
  PERFORM public.exigir(jsonb_array_length(public.listar_trocas()) > 0, 'A ve as proprias trocas');
END $$;

-- ===========================================================================
-- 28. Feedback diario
-- ===========================================================================

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE
  hoje date := public.dia_em_sao_paulo(now());
  s0 integer; f1 integer; f2 integer; deu_erro boolean; x jsonb;
  k7 integer := (SELECT conquistaid FROM public.conquistas WHERE nome = 'Feedback em dia');
BEGIN
  RAISE NOTICE '28. feedback diario';
  s0 := (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 120);

  f1 := public.registrar_feedback(120, hoje, 8, 'Dia bom');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.movimentospontos
                                 WHERE feedbackid = f1 AND tipo = 'bonus' AND pontos = 5),
                        'o bonus do feedback (5) entra pelo livro, ligado ao feedback');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 120 AND conquistaid = k7),
                        'a conquista de sequencia de feedback passou a valer');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 120) = s0 + 5 + 5,
                        'saldo: + 5 do feedback + 5 da conquista');
  PERFORM public.exigir((SELECT origem FROM public.feedbacks WHERE feedbackid = f1) = 'gestor',
                        'marcado como registrado pelo gestor');
  x := public.extrato_pontos(120, hoje, hoje);
  PERFORM public.exigir((x->>'confere')::boolean AND EXISTS (
                          SELECT 1 FROM jsonb_array_elements(x->'movimentos') m WHERE m->>'descricao' LIKE 'Feedback do dia%'),
                        'o bonus do feedback aparece no extrato, e o extrato bate');

  BEGIN PERFORM public.registrar_feedback(120, hoje, 3); deu_erro := false;
  EXCEPTION WHEN unique_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'feedback duplicado no mesmo dia e recusado');
  BEGIN PERFORM public.registrar_feedback(120, hoje - 2, 5); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'so hoje ou ontem (anteontem e recusado)');
  BEGIN PERFORM public.registrar_feedback(120, hoje + 1, 5); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'amanha tambem e recusado');
  BEGIN PERFORM public.registrar_feedback(120, hoje - 1, 11); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nota fora de 0 a 10 e recusada');

  BEGIN UPDATE public.feedbacks SET notadia = 10 WHERE feedbackid = f1; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'a nota nao se altera pelo navegador');
  BEGIN INSERT INTO public.feedbacks (funcionarioid, datafeedback, notadia) VALUES (120, hoje - 1, 5); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'feedback so entra pela funcao (que paga o bonus pelo livro)');

  BEGIN PERFORM public.anular_feedback(f1, ''); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'anular exige motivo');
  PERFORM public.anular_feedback(f1, 'Lancado na pessoa errada');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.movimentospontos
                                 WHERE feedbackid = f1 AND tipo = 'estorno_bonus' AND pontos = -5),
                        'anular estorna o bonus pelo livro');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 120) = s0 + 5,
                        'saldo volta (so fica o bonus da conquista)');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 120 AND conquistaid = k7),
                        'a conquista fica');
  BEGIN PERFORM public.anular_feedback(f1, 'de novo'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nao se anula duas vezes (o bonus nao sai em dobro)');

  f2 := public.registrar_feedback(120, hoje, 9);
  PERFORM public.exigir(f2 IS NOT NULL, 'depois de anular, o lancamento certo do dia e aceito');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.ranking_pontos(hoje, hoje, NULL) WHERE funcionarioid = 120),
                        'bonus de feedback nao entra no ranking');
END $$;

SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.registrar_feedback(120, public.dia_em_sao_paulo(now()), 5); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao registra feedback');
END $$;

-- Sequencia de feedback: a folga nao quebra. Edu (121) deu feedback em
-- hoje-5, hoje-4 e hoje-2; hoje-3 e a folga semanal dele.
RESET ROLE;
UPDATE public.funcionarios
   SET diadefolga = extract(dow FROM public.dia_em_sao_paulo(now()) - 3)::integer + 1,
       datainicioafastamento = NULL, datafimafastamento = NULL
 WHERE funcionarioid = 121;
INSERT INTO public.feedbacks (contaid, funcionarioid, datafeedback, notadia)
SELECT 1, 121, public.dia_em_sao_paulo(now()) - d, 7 FROM unnest(ARRAY[5, 4, 2]) d;

DO $$
DECLARE deu_erro boolean; f integer := (SELECT min(feedbackid) FROM public.feedbacks WHERE funcionarioid = 121);
BEGIN
  BEGIN UPDATE public.feedbacks SET notadia = 0 WHERE feedbackid = f; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco altera a nota');
  BEGIN DELETE FROM public.feedbacks WHERE feedbackid = f; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem apaga feedback');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE k integer;
BEGIN
  k := (public.criar_conquista('3 dias de feedback', NULL, NULL, 'sequencia_feedback_diario', 3, NULL, 0, true))->>'conquistaid';
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 121 AND conquistaid = k),
                        'sequencia de feedback: a folga nao quebra (3 dias)');
  PERFORM set_config('teste.kfb', k::text, false);
END $$;

RESET ROLE;
UPDATE public.funcionarios SET diadefolga = 0 WHERE funcionarioid = 121;
DO $$
BEGIN
  PERFORM public.exigir(NOT public.pessoa_cumpre_conquista(1, 121, current_setting('teste.kfb')::integer),
                        'sem a folga, o dia sem feedback quebraria a sequencia');
END $$;

-- ===========================================================================
-- 29. Justificativas ("nao se aplica")
-- ===========================================================================

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE
  hoje date := public.dia_em_sao_paulo(now());
  ontem date := public.dia_em_sao_paulo(now()) - 1;
  j1 integer; j3 integer; deu_erro boolean; x jsonb; antes integer; depois integer;
BEGIN
  RAISE NOTICE '29. justificativas';
  -- Carla (110): tarefa diaria 5100; ontem nao entregou.
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(public.justificaveis(110, ontem)) t
                                 WHERE (t->>'atribuicaoid')::integer = 5100),
                        'a tarefa de ontem nao entregue pode ser justificada');
  SELECT pontospossiveis INTO antes FROM public.ranking_mensal(extract(year FROM ontem)::integer, extract(month FROM ontem)::integer)
   WHERE funcionarioid = 110;

  j1 := public.registrar_justificativa(5100, ontem, 'Faltou energia', false);
  x := public.pendencias_da_pessoa(110, ontem, ontem);
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(x) p WHERE p->>'justificativa' = 'Pendente'),
                        'pendente: continua nas pendencias, marcada como justificativa pendente');

  BEGIN PERFORM public.registrar_justificativa(5100, ontem, 'de novo', true); deu_erro := false;
  EXCEPTION WHEN check_violation OR unique_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'uma justificativa so por tarefa e dia');
  BEGIN PERFORM public.decidir_justificativa(j1, false, NULL); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'recusar exige motivo');

  PERFORM public.decidir_justificativa(j1, true);
  PERFORM public.exigir(public.pendencias_da_pessoa(110, ontem, ontem) = '[]'::jsonb,
                        'aceita: sai das pendencias');
  SELECT pontospossiveis INTO depois FROM public.ranking_mensal(extract(year FROM ontem)::integer, extract(month FROM ontem)::integer)
   WHERE funcionarioid = 110;
  PERFORM public.exigir(depois = antes - 3,
                        'aceita: sai dos pontos possiveis da nota do mes (' || antes || ' -> ' || depois || ')');
  BEGIN PERFORM public.decidir_justificativa(j1, false, 'mudei de ideia'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'justificativa decidida nao muda');

  -- Recusada: continua pendencia e conta na nota.
  j3 := public.registrar_justificativa(5100, hoje - 2, 'Esqueci', false);
  PERFORM public.decidir_justificativa(j3, false, 'Nao e motivo');
  x := public.pendencias_da_pessoa(110, hoje - 2, hoje - 2);
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(x) p WHERE p->>'justificativa' = 'Recusada'),
                        'recusada: continua nas pendencias');

  -- Hoje, ja aceita: some da lista de entregas e a entrega e recusada.
  PERFORM public.registrar_justificativa(5100, hoje, 'Loja fechada hoje', true);
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.atribuicoes_para_entregar(10) WHERE atribuicaoid = 5100),
                        'justificada hoje: sai da lista do que entregar');
  BEGIN PERFORM public.registrar_entrega(5100); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'e nao da para entregar a tarefa justificada no mesmo dia');

  BEGIN PERFORM public.registrar_justificativa(5100, hoje + 1, 'amanha', true); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'dia futuro nao se justifica');
  BEGIN PERFORM public.registrar_justificativa(5100, ontem, '', true); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'justificativa exige motivo');
  BEGIN INSERT INTO public.justificativas (lojaid, atribuicaoid, funcionarioid, dia, motivo, status)
        VALUES (10, 5100, 110, hoje - 3, 'na mao', 'Aceita'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'justificativa so entra pela funcao');

  x := public.analise_de_tarefas(hoje - 10, hoje, 10);
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(x) t
                                 WHERE t->>'titulo' = 'Abrir o caixa' AND (t->>'naoseaplica')::integer = 2),
                        'analise por tarefa mostra as 2 aceitas como "nao se aplica"');
END $$;

-- Sequencia de tarefas: justificativa aceita e dia neutro. Carla entregou em
-- hoje-10, hoje-9 e hoje-7 (sem afastamento, a sequencia maxima e 2).
RESET ROLE;
DO $$
BEGIN
  PERFORM public.exigir(NOT public.pessoa_cumpre_conquista(1, 110, current_setting('teste.k5')::integer),
                        'antes: hoje-8 sem entrega quebra a sequencia de 3');
END $$;
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$ BEGIN PERFORM public.registrar_justificativa(5100, public.dia_em_sao_paulo(now()) - 8, 'Inventario', true); END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM public.exigir(public.pessoa_cumpre_conquista(1, 110, current_setting('teste.k5')::integer),
                        'justificativa aceita em hoje-8 e dia neutro: a sequencia de 3 fecha');
  PERFORM public.exigir(public.maior_sequencia(
                          ARRAY[date '2026-09-01', date '2026-09-02', date '2026-09-04'],
                          ARRAY[date '2026-09-03'], 0, 0, NULL, NULL) = 3,
                        'dia neutro nao soma: 1, 2, (3 neutro), 4 = 3 dias');
END $$;

-- ===========================================================================
-- 30. Solicitacoes internas
-- ===========================================================================

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE s1 integer; s2 integer; deu_erro boolean; h text;
BEGIN
  RAISE NOTICE '30. solicitacoes internas';
  s1 := public.abrir_solicitacao(10, 100, 'Compra', 'Limpeza', 'Detergente', 5, 'litros');
  PERFORM public.exigir((SELECT status FROM public.solicitacoesinternas WHERE solicitacaoid = s1) = 'Aberta',
                        'nasce aberta');
  BEGIN PERFORM public.abrir_solicitacao(10, 120, 'Compra', NULL, 'Papel'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'quem pediu precisa trabalhar na loja');

  PERFORM public.mudar_situacao_solicitacao(s1, 'Em andamento');
  BEGIN PERFORM public.mudar_situacao_solicitacao(s1, 'Aberta'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nao volta para aberta');
  BEGIN PERFORM public.mudar_situacao_solicitacao(s1, 'Recusada'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'recusar exige motivo');
  PERFORM public.mudar_situacao_solicitacao(s1, 'Concluída', 'Comprado no atacado');
  BEGIN PERFORM public.mudar_situacao_solicitacao(s1, 'Em andamento'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'concluida e final');

  SELECT string_agg(coalesce(statusanterior, '-') || '>' || statusnovo, ' ' ORDER BY historicoid) INTO h
    FROM public.solicitacoeshistorico WHERE solicitacaoid = s1;
  PERFORM public.exigir(h = '->Aberta Aberta>Em andamento Em andamento>Concluída', 'historico: ' || h);
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.solicitacoeshistorico
                                     WHERE solicitacaoid = s1 AND alteradopor IS DISTINCT FROM 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
                        'historico registra quem mudou');
  PERFORM public.exigir((SELECT observacao FROM public.solicitacoeshistorico WHERE solicitacaoid = s1 AND statusnovo = 'Concluída')
                        = 'Comprado no atacado', 'historico guarda a observacao');

  s2 := public.abrir_solicitacao(10, 100, 'Manutencao', 'Predial', 'Pia vazando');
  PERFORM public.mudar_situacao_solicitacao(s2, 'Recusada', 'Ja consertada');
  PERFORM public.exigir((SELECT motivorecusa = 'Ja consertada' AND dataconclusao IS NOT NULL
                           FROM public.solicitacoesinternas WHERE solicitacaoid = s2),
                        'recusada guarda o motivo e a data');

  BEGIN UPDATE public.solicitacoesinternas SET status = 'Aberta' WHERE solicitacaoid = s1; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'situacao so muda pela funcao');
  BEGIN UPDATE public.solicitacoeshistorico SET observacao = 'x'; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'historico nao se altera pelo navegador');
  PERFORM set_config('teste.s1', s1::text, false);
END $$;

RESET ROLE;
DO $$
DECLARE deu_erro boolean; s1 integer := current_setting('teste.s1')::integer;
BEGIN
  BEGIN UPDATE public.solicitacoeshistorico SET observacao = 'x' WHERE solicitacaoid = s1; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco altera o historico');
  BEGIN UPDATE public.solicitacoesinternas SET status = 'Aberta' WHERE solicitacaoid = s1; deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem pula a regra das situacoes');
END $$;

-- ===========================================================================
-- 31. Canal confidencial: anonimato real
-- ===========================================================================

DO $$
DECLARE p text; p2 text; sobra text;
BEGIN
  RAISE NOTICE '31. canal confidencial';
  -- A entrada e so pelo servidor (aqui, o dono do banco faz o papel do bot).
  p  := public.registrar_relato(1, 'O caixa da tarde sai mais cedo todo dia');
  p2 := public.registrar_relato(2, 'Relato da conta B');
  PERFORM set_config('teste.protocolo', p, false);
  PERFORM public.exigir(p ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$', 'protocolo aleatorio no formato XXXX-XXXX-XXXX');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.denunciasanonimas WHERE protocolohash = p OR mensagem LIKE '%' || p || '%'),
                        'o protocolo nao fica guardado em claro');
  PERFORM public.exigir((public.consultar_relato(1, lower(p))->>'status') = 'Nova', 'o protocolo consulta o relato');
  PERFORM public.exigir(public.consultar_relato(2, p) IS NULL, 'o protocolo nao abre relato de outra conta');

  SELECT string_agg(column_name, ',' ORDER BY column_name) INTO sobra
    FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'denunciasanonimas';
  PERFORM public.exigir(sobra = 'contaid,dataregistro,denunciaid,mensagem,protocolohash,respondidoem,resposta,status,tratadoem,tratadopor',
                        'a tabela so tem as colunas aprovadas, nenhuma de quem enviou (' || sobra || ')');
  PERFORM public.exigir((SELECT data_type FROM information_schema.columns
                          WHERE table_schema = 'public' AND table_name = 'denunciasanonimas' AND column_name = 'dataregistro') = 'date',
                        'guarda so o dia, sem hora');
  SELECT string_agg(tgname, ',') INTO sobra FROM pg_trigger
   WHERE tgrelid = 'public.denunciasanonimas'::regclass AND NOT tgisinternal AND tgname <> 'denunciasanonimas_protege';
  PERFORM public.exigir(sobra IS NULL, 'nenhum gatilho copia o relato para outro lugar' || coalesce(' (' || sobra || ')', ''));
  SELECT string_agg(conname, ',') INTO sobra FROM pg_constraint
   WHERE contype = 'f' AND (conrelid = 'public.denunciasanonimas'::regclass AND confrelid <> 'public.contas'::regclass
                            OR confrelid = 'public.denunciasanonimas'::regclass);
  PERFORM public.exigir(sobra IS NULL, 'nenhuma chave liga o relato a pessoa, login ou outra tabela' || coalesce(' (' || sobra || ')', ''));
  SELECT string_agg(proname, ',') INTO sobra FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace AND prosrc ILIKE '%insert into public.denunciasanonimas%'
     AND proname <> 'registrar_relato';
  PERFORM public.exigir(sobra IS NULL, 'so registrar_relato grava relato' || coalesce(' (' || sobra || ')', ''));
  PERFORM public.exigir(NOT has_table_privilege('authenticated', 'public.denunciasanonimas', 'INSERT')
                        AND NOT has_table_privilege('authenticated', 'public.denunciasanonimas', 'UPDATE')
                        AND NOT has_table_privilege('authenticated', 'public.denunciasanonimas', 'DELETE')
                        AND NOT has_table_privilege('anon', 'public.denunciasanonimas', 'SELECT'),
                        'ninguem grava relato pelo navegador, nem o master');
  PERFORM public.exigir(NOT has_function_privilege('authenticated', 'public.registrar_relato(integer, text)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.consultar_relato(integer, text)', 'EXECUTE')
                        AND NOT has_function_privilege('anon', 'public.registrar_relato(integer, text)', 'EXECUTE'),
                        'a entrada e a consulta sao so do servidor');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE d integer; deu_erro boolean;
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.denunciasanonimas) = 1, 'o master le os relatos da propria conta, nao os de B');
  d := (SELECT denunciaid FROM public.denunciasanonimas);
  PERFORM public.tratar_relato(d, 'Em análise');
  PERFORM public.tratar_relato(d, 'Tratada', 'Conversamos com a equipe da tarde');
  PERFORM public.exigir((SELECT status = 'Tratada' AND resposta IS NOT NULL AND respondidoem IS NOT NULL
                           FROM public.denunciasanonimas WHERE denunciaid = d),
                        'o master marca como tratado e responde');
  BEGIN INSERT INTO public.denunciasanonimas (mensagem) VALUES ('forjado'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o master nao grava relato');
  BEGIN UPDATE public.denunciasanonimas SET mensagem = 'editado'; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem edita o texto');
  PERFORM set_config('teste.relato', d::text, false);
END $$;

SET teste.uid = '12121212-1212-1212-1212-121212121212';
DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.denunciasanonimas) = 0, 'gerente nao le o canal confidencial');
  BEGIN PERFORM public.tratar_relato(current_setting('teste.relato')::integer, 'Em análise'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'gerente nao trata relato');
END $$;

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.denunciasanonimas) = 1, 'B le so o relato dela');
  BEGIN PERFORM public.tratar_relato(current_setting('teste.relato')::integer, 'Tratada', 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao trata relato de A');
END $$;

RESET ROLE;
DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir((public.consultar_relato(1, current_setting('teste.protocolo'))->>'resposta') = 'Conversamos com a equipe da tarde',
                        'quem enviou ve a resposta pelo protocolo');
  BEGIN UPDATE public.denunciasanonimas SET mensagem = 'x'; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco altera o texto');
  BEGIN DELETE FROM public.denunciasanonimas; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem apaga relato');
END $$;

-- ===========================================================================
-- 32. Feedbacks, justificativas e solicitacoes de outro cliente
-- ===========================================================================

SET ROLE authenticated;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean; hoje date := public.dia_em_sao_paulo(now());
BEGIN
  RAISE NOTICE '32. feedbacks, justificativas e solicitacoes de outro cliente';
  PERFORM public.exigir((SELECT count(*) FROM public.feedbacks) = 0, 'B nao ve feedbacks de A');
  PERFORM public.exigir((SELECT count(*) FROM public.justificativas) = 0, 'B nao ve justificativas de A');
  PERFORM public.exigir((SELECT count(*) FROM public.solicitacoesinternas) = 0, 'B nao ve solicitacoes de A');
  PERFORM public.exigir((SELECT count(*) FROM public.solicitacoeshistorico) = 0, 'B nao ve o historico das solicitacoes de A');
  PERFORM public.exigir(public.justificaveis(110, hoje - 1) = '[]'::jsonb, 'B nao ve o que A pode justificar');

  BEGIN PERFORM public.registrar_feedback(120, hoje, 5); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao registra feedback para funcionario de A');
  BEGIN PERFORM public.anular_feedback((SELECT max(feedbackid) FROM public.feedbacks), 'x'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao anula feedback de A');
  BEGIN PERFORM public.registrar_justificativa(5100, hoje - 3, 'invasao', true); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao justifica tarefa de A');
  BEGIN PERFORM public.mudar_situacao_solicitacao(current_setting('teste.s1')::integer, 'Recusada', 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao mexe em solicitacao de A');
  BEGIN PERFORM public.abrir_solicitacao(10, 100, 'Compra', NULL, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao abre solicitacao em loja de A');
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean; j integer;
BEGIN
  SELECT justificativaid INTO j FROM public.justificativas ORDER BY 1 LIMIT 1;
  PERFORM set_config('teste.jus', j::text, false);
END $$;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.decidir_justificativa(current_setting('teste.jus')::integer, false, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao decide justificativa de A');
END $$;

-- ===========================================================================
-- 33. Metas de faturamento (Loja A2 = 11)
-- ===========================================================================

RESET ROLE;
-- Equipe da Loja A2: Duda (120) e Edu (121) trabalham todo dia; Fabi (122)
-- esta de folga no dia da semana de ONTEM; Gil (123) esta inativo;
-- Hugo (124) e so da Loja A1.
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, diadefolga, ativo) OVERRIDING SYSTEM VALUE VALUES
  (122, 1, 'Fabi da conta A', extract(dow FROM public.dia_em_sao_paulo(now()) - 1)::integer + 1, true),
  (123, 1, 'Gil da conta A', 0, false),
  (124, 1, 'Hugo da conta A', 0, true);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (1, 122, 11), (1, 123, 11), (1, 124, 10);
UPDATE public.funcionarios SET diadefolga = 0, domingofolgamensal = 0, datainicioafastamento = NULL, datafimafastamento = NULL
 WHERE funcionarioid IN (120, 121);

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
INSERT INTO public.metasdiariasmodelos (lojaid, diasemanaid, nomedia, valormeta, pontospremio)
SELECT 11, d, 'Dia ' || d, 1000, 10 FROM generate_series(1, 7) d;
INSERT INTO public.metasespeciais (lojaid, data, descricao, valormeta, pontospremio)
VALUES (11, public.dia_em_sao_paulo(now()) - 2, 'Dia especial', 5000, 50);

DO $$
DECLARE
  hoje date := public.dia_em_sao_paulo(now());
  ontem date := public.dia_em_sao_paulo(now()) - 1;
  anteontem date := public.dia_em_sao_paulo(now()) - 2;
  a1 integer; a2 integer; p1 integer; p2 integer; deu_erro boolean; quem text; n integer;
BEGIN
  RAISE NOTICE '33. metas de faturamento';

  PERFORM public.exigir((SELECT origem = 'especial' AND valormeta = 5000 FROM public.meta_do_dia(11, anteontem)),
                        'a meta especial substitui o modelo do dia da semana naquela data');
  PERFORM public.exigir((SELECT origem = 'semana' AND valormeta = 1000 FROM public.meta_do_dia(11, ontem)),
                        'nos outros dias vale o modelo do dia da semana');

  -- Lancamento de ontem feito hoje: paga quem trabalhou ONTEM.
  a1 := public.lancar_venda_do_dia(11, ontem, 1200);
  SELECT premiacaoid INTO p1 FROM public.metaspremiacoes WHERE apuracaoid = a1 AND estornadoem IS NULL;
  SELECT string_agg(funcionarioid::text, ',' ORDER BY funcionarioid) INTO quem
    FROM public.movimentospontos WHERE premiacaoid = p1 AND tipo = 'bonus';
  PERFORM public.exigir(quem = '120,121',
                        'lancamento de ontem feito hoje paga quem trabalhou ontem (' || coalesce(quem, '-') || ')');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.movimentospontos WHERE premiacaoid = p1 AND funcionarioid IN (122, 123, 124)),
                        'nao recebe quem estava de folga no dia da venda, quem esta inativo nem quem e de outra loja');
  PERFORM public.exigir((SELECT pontos FROM public.movimentospontos WHERE premiacaoid = p1 AND funcionarioid = 120) = 10,
                        'cada um recebe os pontos da meta do dia (10)');

  -- Correcao.
  BEGIN PERFORM public.lancar_venda_do_dia(11, ontem, 1500); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'correcao sem motivo e recusada');

  PERFORM public.lancar_venda_do_dia(11, ontem, 1500, 'Faltou somar o cartao');
  PERFORM public.exigir((SELECT count(*) FROM public.metaspremiacoes WHERE apuracaoid = a1) = 1
                        AND NOT EXISTS (SELECT 1 FROM public.movimentospontos WHERE premiacaoid = p1 AND tipo = 'estorno_bonus'),
                        'sobe e continua batida: nada muda');
  PERFORM public.lancar_venda_do_dia(11, ontem, 1100, 'Ajuste');
  PERFORM public.exigir((SELECT count(*) FROM public.metaspremiacoes WHERE apuracaoid = a1) = 1,
                        'desce e continua batida: nada muda');

  PERFORM public.lancar_venda_do_dia(11, ontem, 800, 'Devolucao');
  PERFORM public.exigir((SELECT estornadoem IS NOT NULL FROM public.metaspremiacoes WHERE premiacaoid = p1)
                        AND (SELECT sum(pontos) FROM public.movimentospontos WHERE premiacaoid = p1) = 0
                        AND (SELECT count(*) FROM public.movimentospontos WHERE premiacaoid = p1 AND tipo = 'estorno_bonus') = 2,
                        'deixou de bater: estorna, pelo livro, de quem recebeu');

  PERFORM public.lancar_venda_do_dia(11, ontem, 1300, 'Venda achada');
  SELECT premiacaoid INTO p2 FROM public.metaspremiacoes WHERE apuracaoid = a1 AND estornadoem IS NULL;
  PERFORM public.exigir(p2 IS NOT NULL AND p2 <> p1
                        AND (SELECT count(*) FROM public.movimentospontos WHERE premiacaoid = p2 AND tipo = 'bonus') = 2,
                        'voltou a bater: paga de novo');
  PERFORM public.exigir((SELECT count(*) FROM public.metaspremiacoes WHERE apuracaoid = a1 AND estornadoem IS NULL) = 1,
                        'nunca ha dois premios valendo no mesmo dia');

  PERFORM public.lancar_venda_do_dia(11, ontem, 1300);
  PERFORM public.exigir((SELECT count(*) FROM public.metashistorico WHERE apuracaoid = a1) = 5,
                        'historico: 1 lancamento + 4 correcoes (repetir o mesmo valor nao conta)');
  PERFORM public.exigir((SELECT valoranterior = 800 AND valornovo = 1300 AND motivo = 'Venda achada'
                                AND alteradopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                           FROM public.metashistorico WHERE apuracaoid = a1 ORDER BY historicoid DESC LIMIT 1),
                        'historico guarda quem, quando, valor antigo, valor novo e motivo');

  -- Meta especial (anteontem: 5.000 e 50 pontos).
  a2 := public.lancar_venda_do_dia(11, anteontem, 4000);
  PERFORM public.exigir((SELECT valormetadia = 5000 AND origemmeta = 'especial' FROM public.metasdiariasapuracoes WHERE apuracaoid = a2)
                        AND NOT EXISTS (SELECT 1 FROM public.metaspremiacoes WHERE apuracaoid = a2),
                        'com a meta especial, 4.000 nao bate (o modelo de 1.000 bateria)');
  PERFORM public.lancar_venda_do_dia(11, anteontem, 5200, 'Conferido');
  SELECT string_agg(funcionarioid::text, ',' ORDER BY funcionarioid) INTO quem
    FROM public.movimentospontos mv JOIN public.metaspremiacoes p USING (premiacaoid)
   WHERE p.apuracaoid = a2 AND p.estornadoem IS NULL AND mv.tipo = 'bonus' AND mv.pontos = 50;
  PERFORM public.exigir(quem = '120,121,122', 'a meta especial paga os pontos dela (50) a quem trabalhou naquele dia (' || coalesce(quem, '-') || ')');
  UPDATE public.metasespeciais SET valormeta = 9000 WHERE lojaid = 11 AND data = anteontem;
  PERFORM public.lancar_venda_do_dia(11, anteontem, 5300, 'Mais uma venda');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.metaspremiacoes WHERE apuracaoid = a2 AND estornadoem IS NULL),
                        'mudar a meta especial depois nao muda o dia ja lancado');

  -- So o mes atual e o anterior.
  BEGIN PERFORM public.lancar_venda_do_dia(11, (date_trunc('month', hoje) - interval '2 months')::date + 4, 100, 'x'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'lancamento ou correcao de dois meses atras e recusado');
  BEGIN PERFORM public.lancar_venda_do_dia(11, hoje + 1, 100); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'dia futuro e recusado');
  BEGIN PERFORM public.lancar_venda_do_dia(11, hoje, -1); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'valor negativo e recusado');

  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.ranking_pontos(anteontem, hoje, 11) WHERE funcionarioid = 121),
                        'bonus de meta fica fora do ranking');

  -- Nada muda por fora das funcoes.
  BEGIN INSERT INTO public.metasdiariasapuracoes (lojaid, dataapuracao, valordia) VALUES (11, hoje - 3, 1); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'lancamento so pela funcao (que registra no historico)');
  BEGIN UPDATE public.metaspremiacoes SET estornadoem = now(); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'premio nao se mexe na mao');
  BEGIN UPDATE public.metashistorico SET motivo = 'x'; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'historico nao se altera pelo navegador');
  BEGIN INSERT INTO public.metasprincipais (lojaid, nomemeta, valormetatotal, datainicio, datafim, pontospremio)
        VALUES (11, 'x', 1, date_trunc('month', hoje)::date, (date_trunc('month', hoje) + interval '1 month - 1 day')::date, 1);
        deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'meta do mes so pela funcao');
  PERFORM set_config('teste.a1', a1::text, false);
END $$;

-- Meta do mes (mes de ontem): ligado e ativo quando bateu.
DO $$
DECLARE
  ontem date := public.dia_em_sao_paulo(now()) - 1;
  mes date := date_trunc('month', public.dia_em_sao_paulo(now()) - 1)::date;
  v_total numeric; m integer; quem text; deu_erro boolean;
BEGIN
  SELECT coalesce(sum(valordia), 0) INTO v_total FROM public.metasdiariasapuracoes
   WHERE lojaid = 11 AND dataapuracao BETWEEN mes AND (mes + interval '1 month - 1 day')::date;
  m := public.salvar_meta_do_mes(11, mes, 'Meta do mes', v_total + 100, 30);
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.metaspremiacoes WHERE metaprincipalid = m),
                        'meta do mes ainda nao batida: sem premio');

  PERFORM public.lancar_venda_do_dia(11, ontem, 1500, 'Mais vendas');   -- +200 no mes
  SELECT string_agg(funcionarioid::text, ',' ORDER BY funcionarioid) INTO quem
    FROM public.movimentospontos mv JOIN public.metaspremiacoes p USING (premiacaoid)
   WHERE p.metaprincipalid = m AND p.estornadoem IS NULL AND mv.tipo = 'bonus';
  PERFORM public.exigir(quem = '120,121,122',
                        'meta do mes batida: paga quem esta ligado e ativo, mesmo de folga (' || coalesce(quem, '-') || ')');

  PERFORM public.lancar_venda_do_dia(11, ontem, 1350, 'Ajuste fino');   -- mes fica 50 acima do antes, abaixo da meta
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.metaspremiacoes WHERE metaprincipalid = m AND estornadoem IS NULL)
                        AND EXISTS (SELECT 1 FROM public.metaspremiacoes WHERE apuracaoid = current_setting('teste.a1')::integer
                                                                         AND estornadoem IS NULL),
                        'o mes deixou de bater e foi estornado; o dia continua batido');

  PERFORM public.salvar_meta_do_mes(11, mes, 'Meta do mes', v_total, 30);
  PERFORM public.exigir((SELECT count(*) FROM public.metaspremiacoes WHERE metaprincipalid = m AND estornadoem IS NULL) = 1,
                        'baixar a meta do mes para o que ja foi vendido paga de novo, uma vez');

  BEGIN PERFORM public.salvar_meta_do_mes(11, (date_trunc('month', ontem) - interval '3 months')::date, 'x', 10, 1); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'meta de meses atras nao se mexe');
END $$;

-- TV: sem a opcao da loja, nenhum valor em reais sai do banco.
DO $$
BEGIN
  PERFORM public.lancar_venda_do_dia(11, public.dia_em_sao_paulo(now()), 700);
  PERFORM set_config('teste.tv_meta', public.criar_link_tv(11, 'TV da meta'), false);
  PERFORM public.exigir((public.painel_da_loja(11)->'meta'->'dia'->>'vendido')::numeric = 700,
                        'no painel (logado) o gestor ve os valores');
END $$;

SET ROLE anon;
DO $$ BEGIN PERFORM set_config('teste.tv_sem', public.painel_da_tv(current_setting('teste.tv_meta'))::text, false); END $$;
RESET ROLE;
UPDATE public.lojas SET mostrarvalorestv = true WHERE lojaid = 11;
SET ROLE anon;
DO $$ BEGIN PERFORM set_config('teste.tv_com', public.painel_da_tv(current_setting('teste.tv_meta'))::text, false); END $$;
RESET ROLE;
UPDATE public.lojas SET mostrarvalorestv = false WHERE lojaid = 11;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE sem jsonb := current_setting('teste.tv_sem')::jsonb; com jsonb := current_setting('teste.tv_com')::jsonb;
BEGIN
  PERFORM public.exigir((sem->'meta'->'dia'->>'percentual')::numeric = 70, 'TV mostra a porcentagem da meta do dia (70%)');
  PERFORM public.exigir(NOT (sem->'meta'->'dia' ? 'vendido') AND NOT (sem->'meta'->'dia' ? 'meta')
                        AND NOT coalesce(sem->'meta'->'mes' ?| ARRAY['vendido', 'meta', 'projecao'], false)
                        AND sem::text NOT LIKE '%"vendido"%' AND sem::text NOT LIKE '%"projecao"%',
                        'TV sem a opcao ligada nao recebe nenhum valor em reais');
  PERFORM public.exigir((com->'meta'->'dia'->>'vendido')::numeric = 700 AND (com->'meta'->'dia'->>'meta')::numeric = 1000,
                        'com a opcao ligada, a TV recebe os valores');
  PERFORM public.exigir((sem->'meta'->'dia'->>'bateu')::boolean = false, 'a TV sabe se a meta bateu (para os fogos)');
END $$;

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean; hoje date := public.dia_em_sao_paulo(now());
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.metasdiariasapuracoes) = 0
                        AND (SELECT count(*) FROM public.metasprincipais) = 0
                        AND (SELECT count(*) FROM public.metaspremiacoes) = 0
                        AND (SELECT count(*) FROM public.metashistorico) = 0
                        AND (SELECT count(*) FROM public.metasespeciais) = 0
                        AND (SELECT count(*) FROM public.metasdiariasmodelos) = 0,
                        'B nao ve nada das metas de A');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.meta_do_dia(11, hoje)), 'B nao ve a meta do dia de A');
  PERFORM public.exigir((public.metas_do_mes(11, hoje)->>'vendido')::numeric = 0 AND public.metas_do_mes(11, hoje)->'mes' = 'null'::jsonb,
                        'B nao ve o resumo do mes de A');
  BEGIN PERFORM public.lancar_venda_do_dia(11, hoje, 1); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao lanca venda em loja de A');
  BEGIN PERFORM public.salvar_meta_do_mes(11, hoje, 'x', 1, 0); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao mexe na meta do mes de A');
  BEGIN INSERT INTO public.metasespeciais (lojaid, data, descricao, valormeta) VALUES (11, hoje, 'invasao', 1); deu_erro := false;
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao cria meta especial em loja de A');
END $$;

SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.lancar_venda_do_dia(11, public.dia_em_sao_paulo(now()), 1); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao lanca venda');
END $$;

-- ===========================================================================
-- 35. Agenda (Loja A1 = 10)
-- ===========================================================================

RESET ROLE;
SELECT public.cria_tipos_evento_padrao(1);
-- Carla (110) e a responsavel pelos agendamentos da Loja A1.
UPDATE public.lojas SET responsavelagendamentosid = 110 WHERE lojaid = 10;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
INSERT INTO public.tiposevento (nome) VALUES ('Aniversário');

DO $$
DECLARE
  hoje date := public.dia_em_sao_paulo(now());
  d1 timestamptz := ((public.dia_em_sao_paulo(now()) + 3)::timestamp + time '15:00') AT TIME ZONE 'America/Sao_Paulo';
  d2 timestamptz := ((public.dia_em_sao_paulo(now()) + 5)::timestamp + time '10:00') AT TIME ZONE 'America/Sao_Paulo';
  t integer; ag integer; ta record; deu_erro boolean; h record;
BEGIN
  RAISE NOTICE '35. agenda';
  PERFORM public.exigir((SELECT string_agg(nome, ',' ORDER BY nome) FROM public.tiposevento) = 'Aniversário,Evento',
                        'conta nova comeca so com o tipo generico "Evento" (e cadastra os dela)');
  t := (SELECT tipoeventoid FROM public.tiposevento WHERE nome = 'Aniversário');

  ag := public.criar_agendamento(10, t, d1, 'Maria Souza', '123.456.789-09', '(11) 98888-7777', 'Bolo de morango',
                                 150, 'Sinal pago', NULL, true);
  PERFORM public.exigir((SELECT funcionarioid = 110 AND cpfcliente = '12345678909' AND telefonecliente = '11988887777'
                                AND statusagendamento = 'Confirmado' AND statuspagamento = 'Sinal pago'
                           FROM public.agendamentos WHERE agendamentoid = ag),
                        'sem escolher, o responsavel e o da loja; CPF e telefone guardados so com numeros');
  SELECT * INTO ta FROM public.tarefasatribuidas WHERE agendamentoid = ag;
  PERFORM public.exigir(ta.funcionarioid = 110 AND ta.tipofrequencia = 'Unica' AND ta.dataagendamento = d1,
                        'a tarefa "Atender agendamento" nasce para o responsavel, no dia do evento');
  PERFORM public.exigir(ta.descricaooverride = '15:00 — Aniversário' AND ta.descricaooverride NOT LIKE '%Maria%',
                        'a tarefa nao leva dados do cliente (so "15:00 — Aniversário")');

  BEGIN PERFORM public.criar_agendamento(10, t, d1, 'X', NULL, NULL, NULL, NULL, 'Pendente', 120); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'responsavel que nao trabalha na loja e recusado');
  BEGIN PERFORM public.criar_agendamento(10, t, now() - interval '3 days', 'X'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'data no passado e recusada');
  BEGIN PERFORM public.criar_agendamento(10, t, d1, 'X', '123'); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'CPF incompleto e recusado');

  PERFORM public.exigir(jsonb_array_length(public.conflitos_agendamento(10, d1 + interval '1 hour')) = 1
                        AND jsonb_array_length(public.conflitos_agendamento(10, d1 + interval '3 hours')) = 0,
                        'aviso de outro agendamento a menos de 2 horas (sem bloquear)');

  -- Remarcar: a tarefa muda de dia.
  PERFORM public.remarcar_agendamento(ag, d2, 'Cliente pediu');
  SELECT * INTO ta FROM public.tarefasatribuidas WHERE agendamentoid = ag;
  PERFORM public.exigir((SELECT dataevento FROM public.agendamentos WHERE agendamentoid = ag) = d2
                        AND ta.dataagendamento = d2 AND ta.descricaooverride = '10:00 — Aniversário',
                        'remarcou: a tarefa muda de dia junto');
  SELECT * INTO h FROM public.agendamentoshistorico WHERE agendamentoid = ag AND acao = 'remarcado';
  PERFORM public.exigir(h.valoranterior = to_char(d1 AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
                        AND h.valornovo = to_char(d2 AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
                        AND h.alteradopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND h.motivo = 'Cliente pediu',
                        'o historico guarda a data antiga, a nova, quem e quando');

  -- Trocar o responsavel: a tarefa muda de pessoa.
  PERFORM public.trocar_responsavel_agendamento(ag, 124);
  PERFORM public.exigir((SELECT funcionarioid FROM public.tarefasatribuidas WHERE agendamentoid = ag) = 124,
                        'trocou o responsavel: a tarefa vai para a nova pessoa');
  BEGIN PERFORM public.trocar_responsavel_agendamento(ag, 120); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o novo responsavel tambem precisa trabalhar na loja');

  BEGIN UPDATE public.tarefasatribuidas SET datafimvigencia = hoje WHERE agendamentoid = ag; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'a tarefa do agendamento nao se mexe por fora da agenda');
  BEGIN INSERT INTO public.tarefasatribuidas (tarefaid, funcionarioid, lojaid, tipofrequencia)
        VALUES ((SELECT tarefaid FROM public.tarefas WHERE sistema = 'modelo_agendamento'), 110, 10, 'Unica');
        deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem atribui "Atender agendamento" na mao');

  PERFORM public.alterar_pagamento_agendamento(ag, 'Pago', 150);
  PERFORM public.exigir((SELECT valoranterior = 'Sinal pago (R$ 150,00)' AND valornovo = 'Pago (R$ 150,00)'
                           FROM public.agendamentoshistorico WHERE agendamentoid = ag AND acao = 'pagamento'),
                        'mudanca de pagamento no historico');

  -- Realizado e volta para confirmado com motivo.
  PERFORM public.marcar_agendamento_realizado(ag);
  BEGIN PERFORM public.remarcar_agendamento(ag, d1); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'realizado nao se remarca');
  BEGIN PERFORM public.reabrir_agendamento(ag, ''); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'voltar de realizado exige motivo');
  PERFORM public.reabrir_agendamento(ag, 'Marquei no errado');
  PERFORM public.exigir((SELECT statusagendamento FROM public.agendamentos WHERE agendamentoid = ag) = 'Confirmado'
                        AND EXISTS (SELECT 1 FROM public.agendamentoshistorico WHERE agendamentoid = ag AND acao = 'reaberto'
                                                                               AND motivo = 'Marquei no errado'),
                        'realizado volta para confirmado, com motivo no historico');

  -- Cancelar.
  BEGIN PERFORM public.cancelar_agendamento(ag, '  '); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o banco recusa cancelar sem motivo');
  PERFORM public.cancelar_agendamento(ag, 'Cliente desistiu');
  PERFORM public.exigir((SELECT statusagendamento = 'Cancelado' AND motivocancelamento = 'Cliente desistiu'
                           FROM public.agendamentos WHERE agendamentoid = ag)
                        AND (SELECT datafimvigencia FROM public.tarefasatribuidas WHERE agendamentoid = ag) = hoje,
                        'cancelou: a tarefa e encerrada');
  BEGIN PERFORM public.remarcar_agendamento(ag, d1); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'cancelado e final (nao se remarca)');
  BEGIN PERFORM public.marcar_agendamento_realizado(ag); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem vira realizado');
  BEGIN UPDATE public.agendamentos SET statusagendamento = 'Confirmado' WHERE agendamentoid = ag; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'agendamento so muda pelas funcoes');
  BEGIN DELETE FROM public.agendamentos WHERE agendamentoid = ag; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'agendamento nao se apaga');
  PERFORM set_config('teste.ag', ag::text, false);
END $$;

-- Tarefa ja entregue: remarcar e cancelar nao mexem nela.
DO $$
DECLARE
  hoje date := public.dia_em_sao_paulo(now());
  t integer := (SELECT tipoeventoid FROM public.tiposevento WHERE nome = 'Evento');
  ag integer; atr integer;
BEGIN
  ag := public.criar_agendamento(10, t, (hoje::timestamp + time '23:00') AT TIME ZONE 'America/Sao_Paulo', 'Pedro');
  atr := (SELECT atribuicaoid FROM public.tarefasatribuidas WHERE agendamentoid = ag);
  PERFORM public.registrar_entrega(atr);
  PERFORM public.remarcar_agendamento(ag, ((hoje + 4)::timestamp + time '09:00') AT TIME ZONE 'America/Sao_Paulo');
  PERFORM public.exigir(public.dia_em_sao_paulo((SELECT dataagendamento FROM public.tarefasatribuidas WHERE atribuicaoid = atr)) = hoje,
                        'tarefa ja entregue nao muda de dia (nada duplica)');
  PERFORM public.cancelar_agendamento(ag, 'Teste');
  PERFORM public.exigir((SELECT datafimvigencia FROM public.tarefasatribuidas WHERE atribuicaoid = atr) IS NULL
                        AND (SELECT count(*) FROM public.tarefasatribuidas WHERE agendamentoid = ag) = 1,
                        'e o cancelamento nao apaga a entrega feita');
END $$;

-- TV: so hora e tipo. Anexos no Storage.
DO $$
DECLARE
  t integer := (SELECT tipoeventoid FROM public.tiposevento WHERE nome = 'Aniversário');
  ag3 integer; deu_erro boolean; x jsonb; caminho text; anexo integer;
BEGIN
  ag3 := public.criar_agendamento(10, t, ((public.dia_em_sao_paulo(now()) + 2)::timestamp + time '15:00') AT TIME ZONE 'America/Sao_Paulo',
                                  'Joaquim Pereira', '98765432100', '11977776666', 'Segredo da festa', 777, 'Pendente');
  PERFORM set_config('teste.ag3', ag3::text, false);
  PERFORM set_config('teste.tv_agenda', public.criar_link_tv(10, 'TV da agenda'), false);
  x := public.painel_da_loja(10);
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(x->'agenda') i WHERE i->>'cliente' = 'Joaquim')
                        AND x::text NOT LIKE '%98765432100%' AND x::text NOT LIKE '%Pereira%',
                        'painel logado mostra hora, tipo e so o primeiro nome');

  -- Anexo na pasta certa.
  caminho := '1/10/' || ag3 || '/contrato.pdf';
  INSERT INTO storage.objects (bucket_id, name) VALUES ('agendamentos', caminho);
  anexo := public.registrar_anexo_agendamento(ag3, caminho, 'contrato.pdf', 'application/pdf', 1000);
  PERFORM public.exigir(anexo IS NOT NULL, 'anexo guardado na pasta da conta, da loja e do agendamento');
  BEGIN INSERT INTO storage.objects (bucket_id, name) VALUES ('agendamentos', '1/11/' || ag3 || '/errado.pdf'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'anexo fora da pasta do agendamento e recusado pelo Storage');
  BEGIN PERFORM public.registrar_anexo_agendamento(ag3, '1/10/999999/x.pdf', 'x.pdf', 'application/pdf', 10); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'e pela funcao tambem');
  PERFORM set_config('teste.anexo', anexo::text, false);
END $$;

SET ROLE anon;
DO $$ BEGIN PERFORM set_config('teste.tv_ag', public.painel_da_tv(current_setting('teste.tv_agenda'))::text, false); END $$;
RESET ROLE;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE tv jsonb := current_setting('teste.tv_ag')::jsonb; sobra text;
BEGIN
  PERFORM public.exigir(jsonb_array_length(tv->'agenda') >= 1, 'a TV recebe os proximos agendamentos');
  SELECT string_agg(DISTINCT k, ',') INTO sobra
    FROM jsonb_array_elements(tv->'agenda') i, jsonb_object_keys(i) k WHERE k NOT IN ('quando', 'tipo');
  PERFORM public.exigir(sobra IS NULL, 'na TV cada agendamento tem so hora e tipo' || coalesce(' (sobrou: ' || sobra || ')', ''));
  PERFORM public.exigir(tv::text NOT LIKE '%Joaquim%' AND tv::text NOT LIKE '%Maria%' AND tv::text NOT LIKE '%98765432100%'
                        AND tv::text NOT LIKE '%11977776666%' AND tv::text NOT LIKE '%Segredo%' AND tv::text NOT LIKE '%777%',
                        'a TV nao recebe nome, CPF, telefone, observacoes nem valor');

  sobra := public.remover_anexo_agendamento(current_setting('teste.anexo')::integer);
  PERFORM public.exigir(sobra LIKE '1/10/%'
                        AND EXISTS (SELECT 1 FROM public.agendamentoshistorico WHERE acao = 'anexo_removido')
                        AND (SELECT removidoem IS NOT NULL FROM public.agendamentosanexos
                              WHERE anexoid = current_setting('teste.anexo')::integer),
                        'remover anexo fica no historico');
END $$;

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean; ag3 integer := current_setting('teste.ag3')::integer;
BEGIN
  PERFORM public.exigir((SELECT count(*) FROM public.agendamentos) = 0
                        AND (SELECT count(*) FROM public.agendamentoshistorico) = 0
                        AND (SELECT count(*) FROM public.agendamentosanexos) = 0
                        AND (SELECT count(*) FROM public.tiposevento) = 0,
                        'B nao ve a agenda, o historico, os anexos nem os tipos de A');
  PERFORM public.exigir((SELECT count(*) FROM storage.objects WHERE bucket_id = 'agendamentos') = 0,
                        'documento de outro cliente nao abre (B nao le o arquivo de A)');
  BEGIN INSERT INTO storage.objects (bucket_id, name) VALUES ('agendamentos', '2/10/' || ag3 || '/x.pdf'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao grava arquivo no agendamento de A, nem na pasta dela');
  BEGIN PERFORM public.cancelar_agendamento(ag3, 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao cancela agendamento de A');
  BEGIN PERFORM public.criar_agendamento(10, 1, now() + interval '1 day', 'invasao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao cria agendamento em loja de A');
  PERFORM public.exigir(public.conflitos_agendamento(10, now() + interval '2 days') = '[]'::jsonb,
                        'B nao ve os horarios de A');
END $$;

SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.cancelar_agendamento(current_setting('teste.ag3')::integer, 'x'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao mexe na agenda');
END $$;

RESET ROLE;
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN DELETE FROM public.agendamentos WHERE agendamentoid = current_setting('teste.ag')::integer; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco apaga agendamento');
  BEGIN UPDATE public.agendamentos SET statusagendamento = 'Confirmado' WHERE agendamentoid = current_setting('teste.ag')::integer;
        deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem reabre cancelado');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 36. RH: comunicados, ciencias, documentos pessoais e onboarding
-- ===========================================================================

RESET ROLE;
SELECT public.cria_etapas_onboarding_padrao(1);
-- A tarefa do sistema "Leitura de comunicado" sugere 3 pontos por ciencia.
UPDATE public.tarefas SET pontos = 3 WHERE contaid = 1 AND sistema = 'leitura';

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE
  c1 integer; c2 integer; s integer; deu_erro boolean; quem text; x jsonb; k integer; r integer; ativos integer;
BEGIN
  RAISE NOTICE '36. RH: comunicados';
  c1 := public.publicar_comunicado('Nova regra do caixa', 'Texto 1', NULL, 'lojas', ARRAY[11]);
  SELECT string_agg(funcionarioid::text, ',' ORDER BY funcionarioid) INTO quem FROM public.documentosassinaturas WHERE documentoid = c1;
  PERFORM public.exigir(quem = '120,121,122', 'alvo "Loja A2": so os ativos da loja (' || coalesce(quem, '-') || ')');
  PERFORM public.exigir((SELECT pontosporciencia FROM public.documentos WHERE documentoid = c1) = 3,
                        'os pontos sugeridos vem da tarefa do sistema "Leitura de comunicado"');

  BEGIN PERFORM public.publicar_comunicado('X', 'Y', 1, 'funcionarios', NULL, ARRAY[200]); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'funcionario de outra conta nao pode ser destinatario');
  BEGIN PERFORM public.publicar_comunicado('X', 'Y', 1, 'funcionarios', NULL, ARRAY[123]); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'funcionario inativo nao pode ser destinatario');

  c2 := public.publicar_comunicado('Aviso geral', 'Texto geral', 5, 'conta');
  SELECT count(*) INTO ativos FROM public.funcionarios WHERE ativo;
  PERFORM public.exigir((SELECT count(*) FROM public.documentosassinaturas WHERE documentoid = c2) = ativos,
                        'alvo "toda a conta": todos os ativos');
  PERFORM set_config('teste.c2', c2::text, false);

  PERFORM public.editar_comunicado(c1, 'Nova regra do caixa (v2)', 'Texto 1 revisto', 4);
  PERFORM public.exigir((SELECT pontosporciencia = 4 AND conteudo = 'Texto 1 revisto' FROM public.documentos WHERE documentoid = c1),
                        'antes da primeira ciencia, titulo, texto e pontos podem mudar');

  -- Ciencia: pontos pelo livro, uma vez so.
  s := (SELECT assinaturaid FROM public.documentosassinaturas WHERE documentoid = c1 AND funcionarioid = 120);
  PERFORM public.exigir(public.registrar_ciencia(s), 'ciencia registrada pelo gestor');
  PERFORM public.exigir(NOT public.registrar_ciencia(s), 'a segunda ciencia nao faz nada');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos WHERE assinaturaid = s) = 1
                        AND (SELECT pontos FROM public.movimentospontos WHERE assinaturaid = s) = 4,
                        'ciencia dupla nao gera pontos duas vezes');
  PERFORM public.exigir((SELECT origem = 'gestor' AND dataciencia IS NOT NULL AND registradopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                           FROM public.documentosassinaturas WHERE assinaturaid = s),
                        'ciencia guarda data e hora, quem registrou e a origem (gestor)');
  x := public.extrato_pontos(120, public.dia_em_sao_paulo(now()), public.dia_em_sao_paulo(now()));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(x->'movimentos') m WHERE m->>'descricao' LIKE 'Ciência do comunicado%'),
                        'o bonus da ciencia aparece no extrato');

  BEGIN PERFORM public.editar_comunicado(c1, 'Outro', 'Outro texto', 4); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'comunicado com ciencia nao tem o texto editado');
  BEGIN PERFORM public.editar_comunicado(c1, 'Nova regra do caixa (v2)', 'Texto 1 revisto', 10); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem os pontos, depois da primeira ciencia');

  k := (public.criar_conquista('Leitor', NULL, NULL, 'total_comunicados_cientes', 1, NULL, 0, true))->>'conquistaid';
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 120 AND conquistaid = k),
                        'a ciencia conta na conquista "comunicados lidos"');
  PERFORM set_config('teste.s', s::text, false);
  PERFORM set_config('teste.c1', c1::text, false);
  PERFORM set_config('teste.kleitor', k::text, false);

  BEGIN PERFORM public.incluir_destinatarios(c1, ARRAY[200]); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem acrescentado depois');
  PERFORM public.exigir(public.incluir_destinatarios(c1, ARRAY[124, 120]) = 1, 'acrescimo manual depois (ignora quem ja esta)');

  BEGIN INSERT INTO public.documentosassinaturas (documentoid, funcionarioid) VALUES (c1, 110); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'destinatario so entra pelas funcoes');

  r := (SELECT min(resgateid) FROM public.resgates WHERE funcionarioid = 100);
  x := public.recibo_resgate(r);
  PERFORM public.exigir(x->>'pessoa' = 'Ana da conta A' AND x->>'conta' = 'Empresa A'
                        AND jsonb_array_length(x->'movimentos') >= 1 AND x->>'protocolo' = 'R-' || r,
                        'o recibo de resgate sai do livro de pontos, com o nome da conta');
END $$;

-- Desfazer: so o master; estorno pelo livro.
SET teste.uid = '12121212-1212-1212-1212-121212121212';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.desfazer_ciencia(current_setting('teste.s')::integer, 'x'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'gerente nao desfaz ciencia (so o master)');
  PERFORM public.exigir((SELECT count(*) FROM public.documentospessoais) = 0, 'gerente nao ve documentos pessoais');
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE s integer := current_setting('teste.s')::integer; deu_erro boolean; c1 integer := current_setting('teste.c1')::integer;
        outra integer;
BEGIN
  BEGIN PERFORM public.desfazer_ciencia(s, ' '); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'desfazer exige motivo');
  PERFORM public.desfazer_ciencia(s, 'Marquei a pessoa errada');
  PERFORM public.exigir((SELECT statusassinatura = 'Pendente' FROM public.documentosassinaturas WHERE assinaturaid = s)
                        AND EXISTS (SELECT 1 FROM public.movimentospontos WHERE assinaturaid = s AND tipo = 'estorno_bonus' AND pontos = -4),
                        'desfazer estorna os pontos pelo livro');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.conquistasfuncionarios WHERE funcionarioid = 120
                                                                           AND conquistaid = current_setting('teste.kleitor')::integer),
                        'a conquista fica');
  PERFORM public.registrar_ciencia(s);
  PERFORM public.exigir((SELECT sum(pontos) FROM public.movimentospontos WHERE assinaturaid = s) = 4,
                        'ciencia registrada de novo paga de novo, uma vez (nunca dois pagamentos valendo)');

  -- Arquivado: mantem historico e recibo, recusa ciencia e destinatario novos.
  PERFORM public.arquivar_comunicado(c1);
  outra := (SELECT assinaturaid FROM public.documentosassinaturas WHERE documentoid = c1 AND funcionarioid = 121);
  BEGIN PERFORM public.registrar_ciencia(outra); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'comunicado arquivado recusa ciencia nova');
  BEGIN PERFORM public.incluir_destinatarios(c1, ARRAY[110]); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'e recusa destinatario novo');
  PERFORM public.exigir((public.recibo_ciencia(s)->>'protocolo') = 'C-' || s, 'o recibo de ciencia continua disponivel');
  PERFORM public.exigir(public.fora_do_comunicado(current_setting('teste.c2')::integer) = '[]'::jsonb,
                        'ninguem ficou de fora do comunicado geral');
END $$;

RESET ROLE;
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES (125, 1, 'Iara nova da conta A');
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN UPDATE public.documentos SET pontosporciencia = 99 WHERE documentoid = current_setting('teste.c1')::integer; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco muda os pontos depois da ciencia');
  BEGIN DELETE FROM public.documentos WHERE documentoid = current_setting('teste.c2')::integer; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'comunicado nao se apaga');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
BEGIN
  PERFORM public.exigir(EXISTS (SELECT 1 FROM jsonb_array_elements(public.fora_do_comunicado(current_setting('teste.c2')::integer)) f
                                 WHERE (f->>'funcionarioid')::integer = 125),
                        'quem entrou depois aparece como "fora do comunicado", para incluir');
END $$;

-- Documentos pessoais
DO $$
DECLARE
  deu_erro boolean; cam text; d1 integer; d2 integer; d3 integer; d4 integer;
BEGIN
  RAISE NOTICE '36b. RH: documentos pessoais';
  BEGIN INSERT INTO storage.objects (bucket_id, name) VALUES ('documentos-rh', '1/funcionarios/100/solto.pdf'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o Storage recusa envio sem preparar (e registrar) antes');

  cam := public.preparar_envio_documento(100, 'holerite set.pdf');
  PERFORM public.exigir(cam LIKE '1/funcionarios/100/%', 'caminho privado <conta>/funcionarios/<pessoa>/');
  INSERT INTO storage.objects (bucket_id, name) VALUES ('documentos-rh', cam);
  d1 := public.registrar_documento_pessoal(100, 'Holerite', date '2026-08-01', NULL, cam, 'holerite set.pdf', 'application/pdf', 5000);
  PERFORM set_config('teste.d1', d1::text, false);

  BEGIN PERFORM public.registrar_documento_pessoal(100, 'Holerite', NULL, NULL, cam || 'x', 'a.exe', 'application/x-msdownload', 10);
        deu_erro := false;
  EXCEPTION WHEN no_data_found OR check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'arquivo que nao e PDF, JPG ou PNG e recusado');

  PERFORM public.exigir(public.liberar_documento_pessoal(d1) = cam, 'o master gera o link do documento');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.documentosacessos WHERE documentoid = d1 AND acao = 'visualizacao'
                                                                          AND usuario = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
                        'gerar o link registra quem, quando e qual documento');
  PERFORM public.exigir((SELECT count(*) FROM storage.objects WHERE bucket_id = 'documentos-rh') = 1,
                        'com o acesso liberado, o master abre o arquivo');

  -- Exclusao por engano: sem ciencia e ate 7 dias.
  PERFORM public.exigir(public.excluir_documento_por_engano(d1, 'Pessoa errada') = cam, 'exclusao por engano devolve o arquivo para apagar');
  PERFORM public.exigir((SELECT situacao = 'Excluido' AND motivoexclusao = 'Pessoa errada' AND nomearquivo = 'holerite set.pdf'
                                AND excluidopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                           FROM public.documentospessoais WHERE documentoid = d1),
                        'o registro fica: quem, quando, motivo, nome e tipo do arquivo');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.documentosacessos WHERE documentoid = d1 AND acao = 'exclusao'),
                        'a exclusao tambem fica no registro de acessos');
  DELETE FROM storage.objects WHERE bucket_id = 'documentos-rh' AND name = cam;
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM storage.objects WHERE name = cam), 'o arquivo sai do Storage');
  BEGIN PERFORM public.liberar_documento_pessoal(d1); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'documento excluido nao abre mais');

  cam := public.preparar_envio_documento(100, 'advertencia.pdf');
  INSERT INTO storage.objects (bucket_id, name) VALUES ('documentos-rh', cam);
  d2 := public.registrar_documento_pessoal(100, 'Advertência', NULL, NULL, cam, 'advertencia.pdf', 'application/pdf', 3000);
  PERFORM public.registrar_ciencia_documento(d2);
  BEGIN PERFORM public.excluir_documento_por_engano(d2, 'x'); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'exclusao por engano recusada quando ha ciencia');

  cam := public.preparar_envio_documento(100, 'nova.pdf');
  INSERT INTO storage.objects (bucket_id, name) VALUES ('documentos-rh', cam);
  d4 := public.registrar_documento_pessoal(100, 'Advertência', NULL, NULL, cam, 'nova.pdf', 'application/pdf', 3100, d2);
  PERFORM public.exigir((SELECT situacao = 'Substituido' AND substituidopor = d4 FROM public.documentospessoais WHERE documentoid = d2),
                        'substituir por nova versao: a anterior fica guardada e marcada');
  PERFORM public.exigir(public.liberar_documento_pessoal(d2) IS NOT NULL, 'versao substituida continua acessivel ao master');
  PERFORM public.arquivar_documento_pessoal(d4);
  PERFORM public.exigir((SELECT situacao FROM public.documentospessoais WHERE documentoid = d4) = 'Arquivado'
                        AND public.liberar_documento_pessoal(d4) IS NOT NULL,
                        'arquivado sai das listas, mas continua guardado');
  DELETE FROM storage.objects WHERE bucket_id = 'documentos-rh' AND name = cam;
  PERFORM public.exigir(EXISTS (SELECT 1 FROM storage.objects WHERE name = cam), 'o Storage nao apaga arquivo de documento que vale');

  cam := public.preparar_envio_documento(110, 'contrato.pdf');
  INSERT INTO storage.objects (bucket_id, name) VALUES ('documentos-rh', cam);
  d3 := public.registrar_documento_pessoal(110, 'Contrato', NULL, NULL, cam, 'contrato.pdf', 'application/pdf', 3000);
  PERFORM set_config('teste.d3', d3::text, false);
END $$;

RESET ROLE;
ALTER TABLE public.documentospessoais DISABLE TRIGGER documentospessoais_protege;
UPDATE public.documentospessoais SET dataupload = now() - interval '8 days' WHERE documentoid = current_setting('teste.d3')::integer;
ALTER TABLE public.documentospessoais ENABLE TRIGGER documentospessoais_protege;
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN DELETE FROM public.documentospessoais WHERE documentoid = current_setting('teste.d3')::integer; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco apaga documento pessoal');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.excluir_documento_por_engano(current_setting('teste.d3')::integer, 'x'); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'exclusao por engano recusada depois de 7 dias');
END $$;

SET teste.uid = '12121212-1212-1212-1212-121212121212';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.liberar_documento_pessoal(current_setting('teste.d3')::integer); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'gerente nao abre documento pessoal');
  PERFORM public.exigir((SELECT count(*) FROM storage.objects WHERE bucket_id = 'documentos-rh') = 0
                        AND (SELECT count(*) FROM public.documentosacessos) = 0,
                        'gerente nao ve os arquivos nem o registro de acessos');
END $$;

-- Onboarding
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE i record; deu_erro boolean;
BEGIN
  RAISE NOTICE '36c. RH: onboarding';
  PERFORM public.exigir((SELECT string_agg(nome, ' | ' ORDER BY ordem) FROM public.onboardingetapas)
                        = 'Documentos pessoais recebidos | Exame admissional | Contrato assinado | Cadastro no sistema | Treinamento inicial | Apresentação à equipe',
                        'conta nova recebe as 6 etapas genericas');
  PERFORM public.exigir(public.iniciar_onboarding(125) = 6, 'iniciar cria o checklist com as etapas ativas');
  FOR i IN SELECT itemid FROM public.onboardingitens WHERE funcionarioid = 125 LOOP
    PERFORM public.marcar_etapa_onboarding(i.itemid, true);
  END LOOP;
  PERFORM public.exigir((SELECT statusworkflow = 'Concluído' AND concluidoem IS NOT NULL FROM public.onboardingstatus WHERE funcionarioid = 125),
                        'todas as etapas feitas: onboarding concluido');
  UPDATE public.onboardingetapas SET ativo = false WHERE nome = 'Treinamento inicial';
  PERFORM public.exigir((SELECT count(*) FROM public.onboardingitens WHERE funcionarioid = 125) = 6,
                        'desativar uma etapa nao apaga o que ja foi marcado');
  BEGIN PERFORM public.iniciar_onboarding(123); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'onboarding so para funcionario ativo');
  BEGIN DELETE FROM public.onboardingetapas; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'etapa nao se apaga (desativa)');
END $$;

-- Outro cliente
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '36d. RH de outro cliente';
  PERFORM public.exigir((SELECT count(*) FROM public.documentos) = 0 AND (SELECT count(*) FROM public.documentosassinaturas) = 0
                        AND (SELECT count(*) FROM public.documentoslojas) = 0,
                        'B nao le comunicados nem ciencias de A');
  PERFORM public.exigir((SELECT count(*) FROM public.onboardingstatus) = 0 AND (SELECT count(*) FROM public.onboardingitens) = 0
                        AND (SELECT count(*) FROM public.onboardingetapas) = 0,
                        'B nao le o onboarding de A');
  PERFORM public.exigir((SELECT count(*) FROM public.documentospessoais) = 0 AND (SELECT count(*) FROM public.documentosacessos) = 0,
                        'B nao le documentos pessoais nem acessos de A');
  PERFORM public.exigir((SELECT count(*) FROM storage.objects WHERE bucket_id = 'documentos-rh') = 0,
                        'B nao abre arquivo de documentos-rh de A, nem pelo caminho direto do Storage');
  BEGIN PERFORM public.liberar_documento_pessoal(current_setting('teste.d3')::integer); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao libera documento de A');
  BEGIN INSERT INTO storage.objects (bucket_id, name) VALUES ('documentos-rh', '1/funcionarios/100/invasao.pdf'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao grava na pasta de A');
  BEGIN PERFORM public.preparar_envio_documento(100, 'x.pdf'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao prepara envio para funcionario de A');
  BEGIN PERFORM public.registrar_ciencia(current_setting('teste.s')::integer); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao registra ciencia em comunicado de A');
  BEGIN PERFORM public.iniciar_onboarding(100); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao mexe no onboarding de A');
  BEGIN PERFORM public.publicar_comunicado('X', 'Y', 0, 'lojas', ARRAY[10]); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao publica para loja de A');
  PERFORM public.exigir(public.recibo_ciencia(current_setting('teste.s')::integer) IS NULL, 'B nao gera recibo de ciencia de A');
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 37. Tela Inicio (painel_inicio): so a propria conta, sem dado pessoal
-- ===========================================================================

SET ROLE authenticated;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
BEGIN
  PERFORM set_config('teste.inicio_b', public.painel_inicio(NULL)::text, false);
  PERFORM set_config('teste.validar_b',
    (SELECT count(*)::text FROM public.entregas WHERE statusvalidacao = 'Pendente'), false);
END $$;

SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE
  v_todas jsonb;
  v_a1    jsonb;
  v_b     jsonb := current_setting('teste.inicio_b')::jsonb;
  deu_erro boolean;
BEGIN
  RAISE NOTICE '37. tela Inicio';
  v_todas := public.painel_inicio(NULL);
  v_a1    := public.painel_inicio(10);

  PERFORM public.exigir(v_todas ? 'cartoes' AND v_todas ? 'vendas' AND v_todas ? 'pontos' AND v_todas ? 'guia',
                        'painel_inicio devolve cartoes, graficos e guia');
  PERFORM public.exigir((v_todas->'cartoes'->>'validar')::integer
                          = (SELECT count(*) FROM public.entregas WHERE statusvalidacao = 'Pendente'),
                        'Inicio: "aguardando validacao" = entregas pendentes da propria conta');
  PERFORM public.exigir((v_a1->'cartoes'->>'validar')::integer
                          = (SELECT count(*) FROM public.entregas WHERE statusvalidacao = 'Pendente' AND lojaid = 10),
                        'Inicio por loja conta so a loja escolhida');
  PERFORM public.exigir((v_b->'cartoes'->>'validar')::integer = current_setting('teste.validar_b')::integer,
                        'Inicio de B conta so as entregas de B');
  PERFORM public.exigir((v_todas->'cartoes'->>'justificativas')::integer
                          = (SELECT count(*) FROM public.justificativas WHERE status = 'Pendente'),
                        'Inicio: justificativas pendentes da propria conta');
  PERFORM public.exigir(jsonb_array_length(v_todas->'vendas') BETWEEN 28 AND 31, 'Inicio: um ponto por dia do mes');
  PERFORM public.exigir(jsonb_array_length(v_todas->'pontos') = 8, 'Inicio: 8 semanas de pontos');

  -- Nada de outra conta: nem nome de loja, nem de pessoa.
  PERFORM public.exigir(v_todas::text NOT LIKE '%Loja B1%' AND v_todas::text NOT LIKE '%Bruno%'
                        AND v_todas::text NOT LIKE '%conta B%',
                        'Inicio de A nao mostra loja nem pessoa de B');
  PERFORM public.exigir(v_b::text NOT LIKE '%Loja A%' AND v_b::text NOT LIKE '%Ana da conta A%',
                        'Inicio de B nao mostra loja nem pessoa de A');

  -- Nada de CPF, telefone ou cliente final.
  PERFORM public.exigir(v_todas::text !~* '(cpf|telefone|cliente|whatsapp|caminho)',
                        'Inicio nao traz CPF, telefone, cliente nem caminho de arquivo');
  PERFORM public.exigir(NOT EXISTS (
      SELECT 1 FROM public.funcionarios f
       WHERE f.cpf IS NOT NULL AND length(f.cpf) > 3 AND v_todas::text LIKE '%' || f.cpf || '%'),
    'Inicio nao contem o CPF de ninguem');
  PERFORM public.exigir(v_todas::text NOT LIKE '%12345678909%' AND v_todas::text NOT LIKE '%988887777%',
                        'Inicio nao contem CPF nem telefone do cliente da agenda');

  -- Loja de outra conta: some, como se nao existisse.
  BEGIN PERFORM public.painel_inicio(20); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao abre o Inicio da loja de B');
END $$;

RESET ROLE;
DO $$
BEGIN
  PERFORM public.exigir(NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.painel_inicio(integer)'::regprocedure),
                        'painel_inicio roda com a permissao de quem chama (a RLS vale)');
  PERFORM public.exigir(NOT has_function_privilege('anon', 'public.painel_inicio(integer)', 'EXECUTE'),
                        'visitante sem login nao chama painel_inicio');
  PERFORM public.exigir(has_function_privilege('authenticated', 'public.painel_inicio(integer)', 'EXECUTE'),
                        'usuario logado chama painel_inicio');
END $$;

-- Login sem conta: nao ve nada.
SET ROLE authenticated;
SET teste.uid = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.painel_inicio(NULL); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'login sem conta nao abre o Inicio');
END $$;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 38. Rotinas automáticas (Etapa 1.11)
--     Datas simuladas no futuro: 28/12/2026 a 22/01/2027 (virada de ano e de
--     mês, paradas de 3 e de 10 dias). "Passar tarefa" usa o dia de hoje.
-- ===========================================================================

RESET ROLE;

CREATE OR REPLACE FUNCTION public.teste_agora(p_dia date, p_hora text)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
  SELECT (p_dia::text || ' ' || p_hora)::timestamp AT TIME ZONE 'America/Sao_Paulo'
$$;

UPDATE public.contas SET status = 'ativa'    WHERE contaid IN (1, 2);
UPDATE public.contas SET status = 'suspensa' WHERE contaid = 3;

-- Pessoas e tarefas desta seção (conta A: lojas 10 e 11; conta B: loja 20).
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, diadefolga, datainicioafastamento, datafimafastamento)
OVERRIDING SYSTEM VALUE VALUES
  (7001, 1, 'Ana Rotina',       0,    NULL, NULL),
  (7002, 1, 'Beto Folga Terca', 3,    NULL, NULL),          -- 3 = terça
  (7003, 1, 'Caio Afastado',    0,    '2026-12-28', '2026-12-30'),
  (7005, 1, 'Duda Lista',       0,    NULL, NULL),
  (7006, 1, 'Eva Duas Lojas',   0,    NULL, NULL),
  (7101, 2, 'Rui da conta B',   0,    NULL, NULL);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES
  (1, 7001, 10), (1, 7002, 10), (1, 7003, 10), (1, 7005, 10), (1, 7006, 10), (1, 7006, 11), (2, 7101, 20);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES
  (7201, 1, 'Rotina diaria', 10), (7202, 1, 'Rotina extra', 5), (7301, 2, 'Rotina de B', 8);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES
  (1, 7201, 10), (1, 7201, 11), (1, 7202, 10), (2, 7301, 20);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
OVERRIDING SYSTEM VALUE VALUES
  (7401, 1, 7201, 7001, 10, 'Diaria', '2026-12-01 09:00-03'),
  (7402, 1, 7201, 7002, 10, 'Diaria', '2026-12-01 09:00-03'),
  (7403, 1, 7201, 7003, 10, 'Diaria', '2026-12-01 09:00-03'),
  (7405, 1, 7201, 7005, 10, 'Diaria', '2026-12-28 00:01-03'),
  (7406, 1, 7201, 7006, 10, 'Diaria', '2026-12-28 00:01-03'),
  (7407, 1, 7201, 7006, 11, 'Diaria', '2026-12-28 00:01-03'),
  (7501, 2, 7301, 7101, 20, 'Diaria', '2026-12-01 09:00-03');

DO $$
DECLARE r jsonb;
BEGIN
  RAISE NOTICE '38. rotinas automaticas';

  -- Horário de verão (histórico de São Paulo): em 04/11/2018 o relógio pulou
  -- de 00:00 para 01:00; em 16/02/2019 as 23h se repetiram.
  PERFORM public.exigir((SELECT dia = '2018-11-04' AND hora = '01:05'
                           FROM public.rotina_hora_local('2018-11-04 03:05+00')),
                        'horario de verao: 01:05 local no dia em que o relogio pulou');
  PERFORM public.exigir((SELECT hora >= '00:30' FROM public.rotina_hora_local('2018-11-04 03:05+00')),
                        'horario de verao: hora que nao existiu (00:30) conta como passada');
  PERFORM public.exigir((SELECT dia FROM public.rotina_hora_local('2019-02-17 01:30+00'))
                        = (SELECT dia FROM public.rotina_hora_local('2019-02-17 02:30+00')),
                        'horario de verao: a hora repetida cai no mesmo dia (nao gera dia novo)');

  -- Antes do horário (00:05): nada.
  r := public.rotinas_despachar(public.teste_agora('2026-12-28', '00:02'));
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 1 AND dia = '2026-12-28'),
                        'antes do horario da conta, a lista do dia nao e gerada');

  r := public.rotinas_despachar(public.teste_agora('2026-12-28', '00:10'));
  PERFORM public.exigir((r->>'erros')::integer = 0, 'despachante rodou sem erro');
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7401 AND dia = '2026-12-28') = 'devida',
                        'lista gerada: tarefa de quem trabalha fica devida');
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7403 AND dia = '2026-12-28') = 'afastamento',
                        'lista gerada: quem esta afastado fica com a situacao afastamento');
  PERFORM public.exigir((SELECT pontos FROM public.tarefasdodia WHERE atribuicaoid = 7401 AND dia = '2026-12-28') = 10,
                        'lista gerada com os pontos do dia');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.rotinasexecucoes
                                 WHERE contaid = 1 AND rotina = 'lista_do_dia' AND referencia = '2026-12-28'
                                   AND resultado = 'ok' AND NOT recuperado),
                        'geracao registrada no registro de execucoes');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.tarefasdodia WHERE contaid = 2 AND atribuicaoid = 7501 AND dia = '2026-12-28'),
                        'todas as contas ativas rodam (conta B tambem)');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 3),
                        'conta suspensa fica de fora');
END $$;

-- Dia 29/12 (terça): folga do Beto, reconciliação durante o dia.
DO $$
DECLARE n integer; r jsonb;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2026-12-29', '00:10'));
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7402 AND dia = '2026-12-29') = 'folga',
                        'dia de folga do cadastro: item fica como folga (nao e obrigacao)');

  -- Rodar de novo não duplica nem registra de novo.
  SELECT count(*) INTO n FROM public.tarefasdodia WHERE contaid = 1 AND dia = '2026-12-29';
  r := public.rotinas_despachar(public.teste_agora('2026-12-29', '00:15'));
  r := public.rotinas_despachar(public.teste_agora('2026-12-29', '00:15'));
  PERFORM public.exigir((SELECT count(*) FROM public.tarefasdodia WHERE contaid = 1 AND dia = '2026-12-29') = n,
                        'rodar duas vezes nao duplica a lista');
  PERFORM public.exigir((SELECT count(*) FROM public.rotinasexecucoes
                          WHERE contaid = 1 AND rotina = 'lista_do_dia' AND referencia = '2026-12-29') = 1,
                        'rodada sem mudanca nao enche o registro');
END $$;

-- Mudanças de hoje no cadastro.
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
OVERRIDING SYSTEM VALUE VALUES (7404, 1, 7202, 7001, 10, 'Diaria', '2026-12-01 09:00-03');
UPDATE public.tarefas SET pontos = 20 WHERE tarefaid = 7201;
UPDATE public.funcionarios SET diadefolga = 0 WHERE funcionarioid = 7002;     -- a folga de hoje foi desfeita
UPDATE public.funcionarios SET ativo = false WHERE funcionarioid = 7003;      -- desativado hoje
-- A Ana entregou hoje (a entrega segura o item mesmo que a atribuição acabe).
INSERT INTO public.entregas (contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio, statusvalidacao)
VALUES (1, 7201, 7001, 10, 7401, '2026-12-29 10:00-03', 'Pendente');

DO $$
DECLARE r jsonb;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2026-12-29', '14:05'));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.tarefasdodia WHERE atribuicaoid = 7404 AND dia = '2026-12-29' AND situacao = 'devida'),
                        'reconciliacao: tarefa atribuida hoje entra na lista de hoje');
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7402 AND dia = '2026-12-29') = 'devida',
                        'reconciliacao: folga desfeita hoje volta a ser devida');
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7403 AND dia = '2026-12-29') = 'cancelada',
                        'reconciliacao: pessoa desativada hoje tem o item cancelado');
  PERFORM public.exigir((SELECT pontos FROM public.tarefasdodia WHERE atribuicaoid = 7401 AND dia = '2026-12-29') = 10,
                        'pontos mudados hoje nao mudam o item de hoje');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.rotinasexecucoes
                                 WHERE contaid = 1 AND rotina = 'lista_do_dia' AND referencia = '2026-12-29'
                                   AND (detalhe->>'ajuste')::boolean),
                        'ajuste do dia aparece no registro de execucoes');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.tarefasdodia WHERE atribuicaoid = 7404 AND dia = '2026-12-28'),
                        'dia que ja passou nao ganha itens novos');
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7403 AND dia = '2026-12-28') = 'afastamento',
                        'dia que ja passou nao muda (desativacao nao cancela ontem)');
END $$;

-- A atribuição da Ana acaba hoje, mas ela já entregou: o item fica.
UPDATE public.tarefasatribuidas SET datafimvigencia = '2026-12-29' WHERE atribuicaoid IN (7401, 7404);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2026-12-29', '15:05'));
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7401 AND dia = '2026-12-29') = 'devida',
                        'reconciliacao nunca mexe em item ja entregue');
  PERFORM public.exigir((SELECT situacao FROM public.tarefasdodia WHERE atribuicaoid = 7404 AND dia = '2026-12-29') = 'cancelada',
                        'reconciliacao cancela o que deixou de valer (atribuicao encerrada)');
END $$;
UPDATE public.tarefasatribuidas SET datafimvigencia = NULL WHERE atribuicaoid = 7401;

-- Dia passado não muda por nenhum caminho (nem pelo dono do banco).
DO $$
DECLARE deu_erro boolean;
BEGIN
  -- (as datas simuladas estão no futuro; o gatilho usa o dia real)
  BEGIN
    INSERT INTO public.tarefasdodia (contaid, lojaid, dia, atribuicaoid, funcionarioid, tarefaid, tipofrequencia, pontos, situacao)
    VALUES (1, 10, '2020-01-01', 7401, 7001, 7201, 'Diaria', 10, 'devida');
    UPDATE public.tarefasdodia SET situacao = 'cancelada' WHERE dia = '2020-01-01' AND atribuicaoid = 7401;
    deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'item de dia que ja passou nao se altera');
  BEGIN
    DELETE FROM public.tarefasdodia WHERE atribuicaoid = 7401 AND dia = '2026-12-29'; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'item da lista nunca se apaga');
  BEGIN
    UPDATE public.tarefasdodia SET pontos = 99 WHERE atribuicaoid = 7401 AND dia = '2026-12-29'; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'pontos de um item nao mudam depois de gerado');
END $$;

-- Parada de 3 dias (30/12, 31/12 e 01/01): na volta, recupera sem duplicar.
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2027-01-02', '00:10'));
  PERFORM public.exigir((SELECT count(*) FROM public.diasgerados
                          WHERE contaid = 1 AND dia IN ('2026-12-30', '2026-12-31', '2027-01-01') AND recuperado) = 3,
                        'parada de 3 dias: os 3 dias sao recuperados (virada de ano no meio)');
  PERFORM public.exigir((SELECT NOT recuperado FROM public.diasgerados WHERE contaid = 1 AND dia = '2027-01-02'),
                        'o dia de hoje nao e marcado como recuperado');
  PERFORM public.exigir((SELECT count(*) FROM public.rotinasexecucoes
                          WHERE contaid = 1 AND rotina = 'lista_do_dia' AND recuperado
                            AND referencia BETWEEN '2026-12-30' AND '2027-01-01') = 3,
                        'dias recuperados aparecem no registro de execucoes');
  PERFORM public.exigir((SELECT bool_and(recuperado) FROM public.tarefasdodia WHERE contaid = 1 AND dia = '2026-12-31'),
                        'itens de dia recuperado ficam marcados como recuperado');
  PERFORM public.exigir((SELECT pontos FROM public.tarefasdodia WHERE atribuicaoid = 7401 AND dia = '2026-12-30') = 20,
                        'pontos novos valem do dia seguinte em diante');
  r := public.rotinas_despachar(public.teste_agora('2027-01-02', '00:20'));
  PERFORM public.exigir((SELECT count(*) FROM public.diasgerados WHERE contaid = 1 AND dia BETWEEN '2026-12-28' AND '2027-01-02') = 6,
                        'recuperar de novo nao duplica');
END $$;

-- Entregas aprovadas da Eva, uma em cada loja (para o ranking por loja).
INSERT INTO public.entregas (contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio, statusvalidacao, pontosganhos, dataaprovacao)
VALUES
  (1, 7201, 7006, 10, 7406, '2026-12-28 10:00-03', 'Aprovada', 10, '2026-12-28 11:00-03'),
  (1, 7201, 7006, 11, 7407, '2026-12-28 10:00-03', 'Aprovada', 10, '2026-12-28 11:00-03'),
  (1, 7201, 7006, 11, 7407, '2026-12-29 10:00-03', 'Aprovada', 10, '2026-12-29 11:00-03');

-- Fechamento não fecha mês anterior à criação da conta (a conta A foi
-- criada neste mês, pelo relógio real do teste).
DO $$
DECLARE r jsonb; criada date; anterior date;
BEGIN
  SELECT date_trunc('month', public.dia_em_sao_paulo(criadoem))::date INTO criada FROM public.contas WHERE contaid = 1;
  anterior := (criada - interval '1 month')::date;
  r := public.rotina_fechamento_mensal(1, public.teste_agora(criada + 1, '09:00'));
  PERFORM public.exigir(r->>'acao' = 'mes anterior a criacao da conta'
                        AND NOT EXISTS (SELECT 1 FROM public.fechamentosmensais
                                         WHERE contaid = 1 AND ano = extract(year FROM anterior) AND mes = extract(month FROM anterior)),
                        'fechamento nao fecha mes anterior a criacao da conta');
  r := public.rotina_fechamento_mensal(1, public.teste_agora((criada + interval '1 month')::date + 1, '09:00'));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.fechamentosmensais
                                 WHERE contaid = 1 AND ano = extract(year FROM criada) AND mes = extract(month FROM criada)),
                        'o primeiro mes fechado e o mes em que a conta foi criada');
END $$;

-- Fechamento de dezembro/2026.
DO $$
DECLARE r jsonb; f integer;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2027-01-02', '00:30'));
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.fechamentosmensais WHERE contaid = 1 AND ano = 2026 AND mes = 12),
                        'fechamento espera o horario da conta (08:00)');
  r := public.rotinas_despachar(public.teste_agora('2027-01-02', '08:10'));
  SELECT fechamentoid INTO f FROM public.fechamentosmensais
   WHERE contaid = 1 AND ano = 2026 AND mes = 12 AND situacao = 'provisorio';
  PERFORM public.exigir(f IS NOT NULL, 'fechamento de dezembro criado provisorio (dia 2)');
  -- Duda: 28 e 29 com 10 pontos (lista), 30 e 31 com 20. Pelo cadastro de hoje seriam 4 x 20 = 80.
  PERFORM public.exigir((SELECT pontospossiveis FROM public.historicoranking
                          WHERE fechamentoid = f AND lojaid IS NULL AND funcionarioid = 7005) = 60,
                        'fechamento usa a lista congelada (60, nao os 80 do cadastro de hoje)');
  PERFORM public.exigir((SELECT pontosganhos FROM public.historicoranking WHERE fechamentoid = f AND lojaid = 10 AND funcionarioid = 7006) = 10
                        AND (SELECT pontosganhos FROM public.historicoranking WHERE fechamentoid = f AND lojaid = 11 AND funcionarioid = 7006) = 20
                        AND (SELECT pontosganhos FROM public.historicoranking WHERE fechamentoid = f AND lojaid IS NULL AND funcionarioid = 7006) = 30,
                        'quem trabalha em duas lojas: cada ponto conta na loja da tarefa, e o geral soma');
  PERFORM public.exigir((SELECT min(posicao) FROM public.historicoranking WHERE fechamentoid = f AND lojaid IS NULL) = 1,
                        'fechamento grava a posicao');
  PERFORM public.exigir((SELECT nota FROM public.historicoranking WHERE fechamentoid = f AND lojaid IS NULL AND funcionarioid = 7006)
                        = (SELECT nota FROM public.ranking_mensal_da_conta(1, 2026, 12, NULL, '2026-12-31') WHERE funcionarioid = 7006),
                        'a nota do fechamento e a mesma do ranking ao vivo');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.historicoranking WHERE contaid = 1 AND funcionarioid = 7101),
                        'fechamento da conta A nao tem ninguem da conta B');
END $$;

-- Dia 3: uma entrega de 31/12 aprovada depois muda o provisório.
INSERT INTO public.entregas (contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio, statusvalidacao, pontosganhos, dataaprovacao)
VALUES (1, 7201, 7005, 10, 7405, '2026-12-31 18:00-03', 'Aprovada', 20, '2027-01-03 09:00-03');
DO $$
DECLARE r jsonb; f integer;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2027-01-03', '08:10'));
  SELECT fechamentoid INTO f FROM public.fechamentosmensais WHERE contaid = 1 AND ano = 2026 AND mes = 12 AND situacao <> 'substituido';
  PERFORM public.exigir((SELECT pontosregulares FROM public.historicoranking WHERE fechamentoid = f AND lojaid IS NULL AND funcionarioid = 7005) = 20,
                        'provisorio e refeito no dia seguinte (entrega aprovada depois entrou)');
  PERFORM public.exigir((SELECT versao FROM public.fechamentosmensais WHERE fechamentoid = f) = 1,
                        'refazer o provisorio nao cria versao nova');
  r := public.rotinas_despachar(public.teste_agora('2027-01-08', '08:10'));
  PERFORM public.exigir((SELECT situacao FROM public.fechamentosmensais WHERE fechamentoid = f) = 'definitivo',
                        'no dia 8 o fechamento vira definitivo');
END $$;

-- Depois de definitivo, nada muda sozinho.
INSERT INTO public.entregas (contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio, statusvalidacao, pontosganhos, dataaprovacao)
VALUES (1, 7201, 7005, 10, 7405, '2026-12-30 18:00-03', 'Aprovada', 20, '2027-01-09 09:00-03');
DO $$
DECLARE r jsonb; f integer; deu_erro boolean;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2027-01-09', '08:10'));
  SELECT fechamentoid INTO f FROM public.fechamentosmensais WHERE contaid = 1 AND ano = 2026 AND mes = 12 AND situacao <> 'substituido';
  PERFORM public.exigir((SELECT pontosregulares FROM public.historicoranking WHERE fechamentoid = f AND lojaid IS NULL AND funcionarioid = 7005) = 20,
                        'fechamento definitivo nao muda com dados novos');
  BEGIN
    UPDATE public.historicoranking SET nota = 100 WHERE fechamentoid = f; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'linha de fechamento definitivo nao se altera (nem pelo dono do banco)');
  BEGIN
    UPDATE public.fechamentosmensais SET situacao = 'provisorio' WHERE fechamentoid = f; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'definitivo nao volta a provisorio');
END $$;

-- Refazer fechamento: só o master, com motivo, guardando a versão anterior.
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean; v integer; antigo integer;
BEGIN
  SELECT fechamentoid INTO antigo FROM public.fechamentosmensais WHERE ano = 2026 AND mes = 12 AND situacao <> 'substituido';
  BEGIN PERFORM public.refazer_fechamento(2026, 12, '  '); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'refazer fechamento exige motivo');
  BEGIN INSERT INTO public.historicoranking (contaid, fechamentoid, ano, mes, funcionarioid) VALUES (1, antigo, 2026, 12, 7005); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'ninguem grava no historico do ranking direto pela tela');

  v := public.refazer_fechamento(2026, 12, 'Entrega de 30/12 aprovada depois do fechamento');
  PERFORM public.exigir((SELECT situacao = 'definitivo' AND versao = 2 AND origem = 'master' FROM public.fechamentosmensais WHERE fechamentoid = v),
                        'refazer cria a versao 2, definitiva, pelo master');
  PERFORM public.exigir((SELECT pontosregulares FROM public.historicoranking WHERE fechamentoid = v AND lojaid IS NULL AND funcionarioid = 7005) = 40,
                        'a versao nova tem os numeros atualizados');
  PERFORM public.exigir((SELECT situacao FROM public.fechamentosmensais WHERE fechamentoid = antigo) = 'substituido'
                        AND (SELECT pontosregulares FROM public.historicoranking WHERE fechamentoid = antigo AND lojaid IS NULL AND funcionarioid = 7005) = 20,
                        'a versao anterior fica guardada, com os numeros dela');
END $$;

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.fechamentosmensais WHERE contaid = 1)
                        AND NOT EXISTS (SELECT 1 FROM public.historicoranking WHERE contaid = 1),
                        'B nao le os fechamentos de A');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.tarefasdodia WHERE contaid = 1)
                        AND NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 1)
                        AND NOT EXISTS (SELECT 1 FROM public.rotinasexecucoes WHERE contaid = 1),
                        'B nao le a lista do dia nem o registro de rotinas de A');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.lista_candidatos(1, '2026-12-29'))
                        AND NOT EXISTS (SELECT 1 FROM public.ranking_mensal_da_conta(1, 2026, 12, NULL, '2026-12-31')),
                        'B nao le a lista nem o ranking de A passando a conta de A');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.fechamentosmensais WHERE ano = 2026 AND mes = 12),
                        'B tem o proprio fechamento');
  BEGIN PERFORM public.rotinas_despachar(); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'usuario logado nao chama o despachante');
  BEGIN PERFORM public.lista_do_dia_gerar(1, '2026-12-29', '2026-12-29', false); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'usuario logado nao chama a geracao interna');
  BEGIN PERFORM public.rotina_lista_do_dia(1, now(), 'manual'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'usuario logado nao chama a rotina de outra conta');
  BEGIN PERFORM public.fechamento_calcular(1, 1); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'usuario logado nao chama o calculo interno do fechamento');
  BEGIN PERFORM * FROM public.rotinas_resumo_admin(); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'master nao ve o resumo do admin');
END $$;
RESET ROLE;

-- Parada de 10 dias: só os últimos 7 são recuperados; os outros 3 seguem
-- pela regra do cadastro na nota do mês.
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2027-01-20', '00:10'));
  PERFORM public.exigir((SELECT count(*) FROM public.diasgerados WHERE contaid = 1 AND dia BETWEEN '2027-01-13' AND '2027-01-19' AND recuperado) = 7,
                        'parada de 10 dias: recupera no maximo 7 dias');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 1 AND dia BETWEEN '2027-01-10' AND '2027-01-12'),
                        'dias alem do limite de 7 nao sao gerados');
END $$;
UPDATE public.tarefas SET pontos = 30 WHERE tarefaid = 7201;
DO $$
BEGIN
  -- Duda em janeiro até 19/01: 16 dias com lista (20 pontos) + 3 dias pela regra (30 de hoje).
  PERFORM public.exigir((SELECT pontospossiveis FROM public.ranking_mensal_da_conta(1, 2027, 1, NULL, '2027-01-19') WHERE funcionarioid = 7005)
                        = 16 * 20 + 3 * 30,
                        'nota do mes: dias com lista usam a lista, dias sem lista usam a regra');
END $$;

-- Uma conta com erro não trava as outras.
ALTER TABLE public.configuracoes DISABLE TRIGGER USER;
INSERT INTO public.configuracoes (contaid, chave, valor) VALUES (2, 'HORARIO_GERACAO_TAREFAS', 'quebrado')
ON CONFLICT (contaid, chave) DO UPDATE SET valor = 'quebrado';
ALTER TABLE public.configuracoes ENABLE TRIGGER USER;
UPDATE public.lojas SET ativa = false WHERE lojaid = 11;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rotinas_despachar(public.teste_agora('2027-01-21', '00:10'));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 1 AND dia = '2027-01-21'),
                        'conta A rodou mesmo com erro na conta B');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.rotinasexecucoes
                                 WHERE contaid = 2 AND rotina = 'lista_do_dia' AND referencia = '2027-01-21' AND resultado = 'erro'),
                        'o erro da conta B fica registrado');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 2 AND dia = '2027-01-21'),
                        'a conta com erro nao gera lista pela metade');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.tarefasdodia WHERE lojaid = 11 AND dia = '2027-01-21'),
                        'loja desativada fica de fora');
  r := public.rotinas_despachar(public.teste_agora('2027-01-21', '00:15'));
  PERFORM public.exigir((SELECT count(*) FROM public.rotinasexecucoes
                          WHERE contaid = 2 AND rotina = 'lista_do_dia' AND referencia = '2027-01-21' AND resultado = 'erro') = 1,
                        'o mesmo erro nao e registrado de novo a cada 5 minutos');
END $$;
DELETE FROM public.configuracoes WHERE contaid = 2 AND chave = 'HORARIO_GERACAO_TAREFAS';
UPDATE public.lojas SET ativa = true WHERE lojaid = 11;

-- Isolamento: gerar a lista da conta A não toca em nada da conta B.
DO $$
DECLARE antes text; depois text;
BEGIN
  SELECT md5(string_agg(t::text, '' ORDER BY itemid)) INTO antes FROM public.tarefasdodia t WHERE contaid = 2;
  PERFORM public.lista_do_dia_gerar(1, '2027-01-22', '2027-01-22', false);
  PERFORM public.rotina_lista_do_dia(1, public.teste_agora('2027-01-22', '09:00'), 'agendada');
  SELECT md5(string_agg(t::text, '' ORDER BY itemid)) INTO depois FROM public.tarefasdodia t WHERE contaid = 2;
  PERFORM public.exigir(antes = depois, 'a rotina da conta A nao cria nem altera nada da conta B');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.diasgerados WHERE contaid = 2 AND dia = '2027-01-22'),
                        'a rotina da conta A nao gera dia para a conta B');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.tarefasdodia i JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = i.atribuicaoid
                                     WHERE i.contaid <> ta.contaid),
                        'todo item da lista pertence a conta da atribuicao');
END $$;

-- Conferência do livro: nunca corrige, só registra.
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rotina_conferencia_livro(1, public.teste_agora('2027-01-21', '03:10'));
  PERFORM public.exigir(r->>'acao' = 'ok', 'conferencia do livro: saldos batem');
END $$;
SET session_replication_role = replica;      -- simula um saldo mexido por fora
UPDATE public.funcionarios SET saldopontos = saldopontos + 5 WHERE funcionarioid = 7001;
SET session_replication_role = origin;
DO $$
DECLARE r jsonb; saldo integer;
BEGIN
  SELECT saldopontos INTO saldo FROM public.funcionarios WHERE funcionarioid = 7001;
  r := public.rotina_conferencia_livro(1, public.teste_agora('2027-01-22', '03:10'));
  PERFORM public.exigir(r->>'acao' = 'diferenca', 'conferencia encontra a diferenca');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 7001) = saldo,
                        'conferencia nao corrige o saldo sozinha');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.rotinasexecucoes
                                 WHERE contaid = 1 AND rotina = 'conferencia_livro' AND referencia = '2027-01-22'
                                   AND resultado = 'erro' AND detalhe->'diferencas' @> '[{"funcionarioid": 7001}]'),
                        'diferenca registrada com a pessoa');
  r := public.rotina_conferencia_livro(1, public.teste_agora('2027-01-22', '04:00'));
  PERFORM public.exigir(r->>'acao' = 'ja rodou hoje', 'conferencia roda uma vez por dia');
END $$;
SET session_replication_role = replica;
UPDATE public.funcionarios SET saldopontos = saldopontos - 5 WHERE funcionarioid = 7001;
SET session_replication_role = origin;

-- Admin geral: vê a situação por conta, sem texto nem dados.
SET ROLE authenticated;
SET teste.uid = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
DO $$
BEGIN
  PERFORM public.exigir((SELECT situacao FROM public.rotinas_resumo_admin() WHERE contaid = 1 AND rotina = 'conferencia_livro') = 'diferenca',
                        'admin geral ve a diferenca na lista de contas');
  PERFORM public.exigir((SELECT situacao FROM public.rotinas_resumo_admin() WHERE contaid = 2 AND rotina = 'lista_do_dia') = 'erro',
                        'admin geral ve o erro da conta B');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.rotinasexecucoes),
                        'admin geral nao le o registro detalhado das contas');
END $$;
RESET ROLE;

-- Limpeza: só o registro de rotinas com mais de 180 dias.
INSERT INTO public.rotinasexecucoes (contaid, rotina, iniciadoem, resultado) VALUES
  (1, 'lista_do_dia', now() - interval '200 days', 'ok'),
  (1, 'lista_do_dia', now() - interval '181 days', 'ok'),
  (2, 'lista_do_dia', now() - interval '200 days', 'ok');
DO $$
DECLARE mov integer; acessos integer; recentes integer; r jsonb;
BEGIN
  SELECT count(*) INTO mov FROM public.movimentospontos;
  SELECT count(*) INTO acessos FROM public.documentosacessos;
  SELECT count(*) INTO recentes FROM public.rotinasexecucoes WHERE contaid = 1 AND iniciadoem > now() - interval '180 days';
  r := public.rotina_limpeza(1, public.teste_agora(public.dia_em_sao_paulo(now()), '23:59'));
  PERFORM public.exigir((r->>'apagados')::integer = 2, 'limpeza apaga o registro de rotinas com mais de 180 dias');
  PERFORM public.exigir((SELECT count(*) FROM public.rotinasexecucoes WHERE contaid = 1 AND iniciadoem > now() - interval '180 days') = recentes + 1,
                        'limpeza mantem o registro recente');
  PERFORM public.exigir((SELECT count(*) FROM public.rotinasexecucoes WHERE contaid = 2 AND iniciadoem < now() - interval '180 days') = 1,
                        'limpeza da conta A nao apaga nada da conta B');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos) = mov, 'limpeza nao toca no livro de pontos');
  PERFORM public.exigir((SELECT count(*) FROM public.documentosacessos) = acessos,
                        'limpeza nao toca no registro de acesso a documentos pessoais');
END $$;
DELETE FROM public.rotinasexecucoes WHERE contaid = 2 AND iniciadoem < now() - interval '180 days';

-- ---------------------------------------------------------------------------
-- Expurgo das fotos de entrega (Etapa 1.12): apaga so o ARQUIVO.
-- Usa entregas que ja existem no teste, so mudando data e caminho da foto.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r jsonb; mov integer;
  v_velha integer; v_nova integer; v_b integer;
  v_status text; v_pontos integer;
BEGIN
  RAISE NOTICE '38b. expurgo das fotos de entrega';
  SELECT count(*) INTO mov FROM public.movimentospontos;

  SELECT min(entregaid) INTO v_velha FROM public.entregas WHERE contaid = 1;
  SELECT min(entregaid) INTO v_nova  FROM public.entregas WHERE contaid = 1 AND entregaid > v_velha;
  SELECT min(entregaid) INTO v_b     FROM public.entregas WHERE contaid = 2;
  PERFORM public.exigir(v_velha IS NOT NULL AND v_nova IS NOT NULL AND v_b IS NOT NULL,
                        'o teste tem entregas das duas contas para o expurgo');

  UPDATE public.entregas SET dataenvio = now() - interval '200 days', pathfotoevidencia = '1/10/velha.jpg'
   WHERE entregaid = v_velha;
  UPDATE public.entregas SET dataenvio = now() - interval '10 days',  pathfotoevidencia = '1/10/nova.jpg'
   WHERE entregaid = v_nova;
  UPDATE public.entregas SET dataenvio = now() - interval '200 days', pathfotoevidencia = '2/20/outra.jpg'
   WHERE entregaid = v_b;
  SELECT statusvalidacao, pontosganhos INTO v_status, v_pontos FROM public.entregas WHERE entregaid = v_velha;

  r := public.rotina_expurgo_fotos(1, public.teste_agora(public.dia_em_sao_paulo(now()), '00:01'));
  PERFORM public.exigir(r->>'acao' = 'antes do horario', 'expurgo nao roda antes do horario da conta');

  r := public.rotina_expurgo_fotos(1, public.teste_agora(public.dia_em_sao_paulo(now()), '23:59'));
  PERFORM public.exigir((r->>'fotos')::integer = 1, 'expurgo marca so a foto vencida');
  PERFORM public.exigir((r->>'dias')::integer = 180, 'expurgo usa o prazo da conta (180 dias)');

  -- O que sai e o que FICA.
  PERFORM public.exigir((SELECT pathfotoevidencia IS NULL AND fotoexpiradaem IS NOT NULL
                           FROM public.entregas WHERE entregaid = v_velha),
                        'a entrega vencida fica marcada como foto removida por tempo');
  PERFORM public.exigir((SELECT statusvalidacao = v_status AND coalesce(pontosganhos, 0) = coalesce(v_pontos, 0)
                           FROM public.entregas WHERE entregaid = v_velha),
                        'o registro da entrega e os pontos continuam de pe');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos) = mov,
                        'o expurgo nao toca no livro de pontos');
  PERFORM public.exigir((SELECT pathfotoevidencia = '1/10/nova.jpg' AND fotoexpiradaem IS NULL
                           FROM public.entregas WHERE entregaid = v_nova),
                        'a foto dentro do prazo continua no lugar');
  PERFORM public.exigir((SELECT count(*) FROM public.fotosexpurgo
                          WHERE contaid = 1 AND caminho = '1/10/velha.jpg' AND removidoem IS NULL) = 1,
                        'o caminho entra na fila para a Edge Function apagar');

  -- Isolamento: a rotina da conta A nao encosta na conta B.
  PERFORM public.exigir((SELECT pathfotoevidencia = '2/20/outra.jpg' AND fotoexpiradaem IS NULL
                           FROM public.entregas WHERE entregaid = v_b),
                        'o expurgo da conta A nao apaga foto da conta B');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.fotosexpurgo WHERE contaid <> 1),
                        'nada de outra conta entra na fila da conta A');

  -- Uma vez por dia.
  r := public.rotina_expurgo_fotos(1, public.teste_agora(public.dia_em_sao_paulo(now()), '23:59'));
  PERFORM public.exigir(r->>'acao' = 'ja rodou hoje', 'expurgo roda uma vez por dia');

  -- Duas entregas com o MESMO arquivo: a recente nao pode perder a foto junto.
  UPDATE public.entregas SET pathfotoevidencia = '1/10/dividida.jpg', fotoexpiradaem = NULL,
                             dataenvio = now() - interval '300 days' WHERE entregaid = v_velha;
  UPDATE public.entregas SET pathfotoevidencia = '1/10/dividida.jpg', fotoexpiradaem = NULL,
                             dataenvio = now() - interval '3 days' WHERE entregaid = v_nova;
  DELETE FROM public.rotinasexecucoes WHERE contaid = 1 AND rotina = 'expurgo_fotos';
  r := public.rotina_expurgo_fotos(1, public.teste_agora(public.dia_em_sao_paulo(now()), '23:59'));
  PERFORM public.exigir((SELECT fotoexpiradaem IS NOT NULL FROM public.entregas WHERE entregaid = v_velha),
                        'a entrega vencida perde a foto');
  PERFORM public.exigir((SELECT fotoexpiradaem IS NULL AND pathfotoevidencia = '1/10/dividida.jpg'
                           FROM public.entregas WHERE entregaid = v_nova),
                        'a entrega DENTRO do prazo nao perde a foto, mesmo dividindo o arquivo');

  -- Documento de RH tem regra propria: nada dele entra nesta fila.
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.fotosexpurgo WHERE caminho LIKE '%funcionarios%'),
                        'nenhum documento pessoal entra na fila de expurgo');

  -- Prazo: minimo de 90 dias, mesmo se alguem tentar gravar menos.
  BEGIN
    UPDATE public.configuracoes SET valor = '10' WHERE contaid = 1 AND chave = 'DIAS_GUARDAR_FOTO_ENTREGA';
    PERFORM public.exigir(false, 'prazo menor que 90 dias e recusado');
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Limpa o que este bloco montou.
  UPDATE public.entregas SET pathfotoevidencia = NULL, fotoexpiradaem = NULL
   WHERE entregaid IN (v_velha, v_nova, v_b);
  DELETE FROM public.fotosexpurgo;
END $$;

-- A fila e as funcoes do expurgo nao existem para o navegador.
DO $$
BEGIN
  PERFORM public.exigir(NOT has_table_privilege('authenticated', 'public.fotosexpurgo', 'SELECT')
                        AND NOT has_table_privilege('anon', 'public.fotosexpurgo', 'SELECT'),
                        'ninguem le a fila de expurgo pelo navegador');
  PERFORM public.exigir(NOT has_function_privilege('authenticated', 'public.expurgo_pegar(integer)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.expurgo_resultado(integer[], text)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.rotina_expurgo_fotos(integer, timestamptz)', 'EXECUTE')
                        AND NOT has_function_privilege('anon', 'public.expurgo_pegar(integer)', 'EXECUTE'),
                        'funcoes do expurgo nao ficam liberadas para o navegador');
END $$;


-- ---------------------------------------------------------------------------
-- Passar tarefa de quem está de folga HOJE (data real).
-- ---------------------------------------------------------------------------
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, diadefolga, ativo, datainicioafastamento, datafimafastamento)
OVERRIDING SYSTEM VALUE VALUES
  (7010, 1, 'Fabi Folga',      extract(dow FROM public.dia_em_sao_paulo(now()))::integer + 1, true, NULL, NULL),
  (7011, 1, 'Gabi Trabalha',   0, true,  NULL, NULL),
  (7012, 1, 'Hugo Outra Loja', 0, true,  NULL, NULL),
  (7013, 1, 'Ivo Inativo',     0, true,  NULL, NULL),
  (7014, 1, 'Juca Afastado',   0, true,  public.dia_em_sao_paulo(now()), public.dia_em_sao_paulo(now()));
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES
  (1, 7010, 10), (1, 7011, 10), (1, 7012, 11), (1, 7013, 10), (1, 7014, 10);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (7203, 1, 'Limpar vitrine', 7);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (1, 7203, 10);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
OVERRIDING SYSTEM VALUE VALUES
  (7410, 1, 7203, 7010, 10, 'Diaria', now()),
  (7411, 1, 7203, 7011, 10, 'Diaria', now()),
  (7414, 1, 7203, 7014, 10, 'Diaria', now());
UPDATE public.funcionarios SET ativo = false WHERE funcionarioid = 7013;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean; lista jsonb; gente jsonb; nova integer; saldo integer; ultimo integer; r jsonb;
BEGIN
  lista := public.tarefas_de_folga_hoje(10);
  PERFORM public.exigir(lista @> '[{"atribuicaoid": 7410, "motivo": "folga"}]' AND lista @> '[{"atribuicaoid": 7414, "motivo": "afastamento"}]'
                        AND NOT lista @> '[{"atribuicaoid": 7411}]',
                        'bloco de folga lista folga e afastamento, e nao quem trabalha');
  gente := public.quem_trabalha_hoje(10);
  PERFORM public.exigir(gente @> '[{"funcionarioid": 7011}]' AND NOT gente @> '[{"funcionarioid": 7010}]'
                        AND NOT gente @> '[{"funcionarioid": 7012}]' AND NOT gente @> '[{"funcionarioid": 7013}]'
                        AND NOT gente @> '[{"funcionarioid": 7014}]',
                        '"Passar para" so mostra ativos da mesma loja que trabalham hoje');

  BEGIN PERFORM public.passar_tarefa_de_folga(7410, 7012); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nao passa para quem e de outra loja');
  BEGIN PERFORM public.passar_tarefa_de_folga(7410, 7013); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nao passa para funcionario inativo');
  BEGIN PERFORM public.passar_tarefa_de_folga(7410, 7014); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nao passa para quem esta afastado');
  BEGIN PERFORM public.passar_tarefa_de_folga(7411, 7010); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'tarefa de quem trabalha hoje nao se passa');

  nova := public.passar_tarefa_de_folga(7410, 7011);
  PERFORM public.exigir((SELECT tipofrequencia = 'Unica' AND funcionarioid = 7011 AND origematribuicaoid = 7410 AND tarefaid = 7203
                           FROM public.tarefasatribuidas WHERE atribuicaoid = nova),
                        'passar cria a tarefa unica de hoje, da mesma tarefa (mesmos pontos)');
  PERFORM public.exigir((SELECT passadapara = 7011 FROM public.tarefasdodia
                          WHERE atribuicaoid = 7410 AND dia = public.dia_em_sao_paulo(now())),
                        'na lista do dia, o item original fica "passada para"');
  PERFORM public.exigir(public.tarefas_de_folga_hoje(10) @> '[{"atribuicaoid": 7410, "passadapara": "Gabi Trabalha"}]',
                        'o bloco mostra para quem foi passada');
  BEGIN PERFORM public.passar_tarefa_de_folga(7410, 7011); deu_erro := false;
  EXCEPTION WHEN unique_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'uma tarefa nao e passada duas vezes no mesmo dia');
  BEGIN PERFORM public.registrar_entrega(7410); deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'a original passada nao recebe entrega');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.atribuicoes_para_entregar(10) WHERE atribuicaoid = 7410)
                        AND EXISTS (SELECT 1 FROM public.atribuicoes_para_entregar(10) WHERE atribuicaoid = nova),
                        'no quadro sai a original e entra a de quem recebeu');
  PERFORM public.exigir(public.painel_da_loja(10)::text NOT LIKE '%Fabi Folga%',
                        'painel da loja (e TV) nao mostra mais a tarefa passada de quem esta de folga');

  SELECT saldopontos INTO saldo FROM public.funcionarios WHERE funcionarioid = 7011;
  SELECT coalesce(max(movimentoid), 0) INTO ultimo FROM public.movimentospontos;
  PERFORM public.registrar_entrega(nova, NULL, NULL, true);
  -- (a aprovação pode destravar uma conquista: o bônus também entra pelo livro)
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 7011)
                          = saldo + (SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 7011 AND movimentoid > ultimo)
                        AND EXISTS (SELECT 1 FROM public.movimentospontos m JOIN public.entregas e ON e.entregaid = m.entregaid
                                     WHERE e.atribuicaoid = nova AND m.tipo = 'aprovacao' AND m.pontos = 7),
                        'os pontos da tarefa recebida entram pelo livro, na aprovacao');
  PERFORM public.exigir((SELECT pontospossiveis = 7 AND pontosregulares = 0 AND pontosganhos = 7
                           FROM public.ranking_mensal_da_conta(1, extract(year FROM public.dia_em_sao_paulo(now()))::integer,
                                                               extract(month FROM public.dia_em_sao_paulo(now()))::integer,
                                                               NULL, public.dia_em_sao_paulo(now()))
                          WHERE funcionarioid = 7011),
                        'tarefa recebida e esforco extra: conta nos ganhos, nao nos possiveis nem na confiabilidade');

  -- "Rodar agora" e o Início.
  r := public.rodar_geracao_hoje();
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.rotinasexecucoes
                                 WHERE rotina = 'lista_do_dia' AND origem = 'manual' AND referencia = public.dia_em_sao_paulo(now())),
                        '"Rodar agora" roda a geracao de hoje e registra como manual');
  PERFORM public.exigir(public.painel_inicio(NULL) ? 'avisos' AND public.painel_inicio(NULL)->'rotina'->>'resultado' = 'ok',
                        'Inicio mostra os avisos e a situacao da rotina de hoje');
END $$;

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir(public.tarefas_de_folga_hoje(10) = '[]'::jsonb AND public.quem_trabalha_hoje(10) = '[]'::jsonb,
                        'B nao ve as folgas nem a equipe da loja de A');
  BEGIN PERFORM public.passar_tarefa_de_folga(7414, 7011); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao passa tarefa de A');
END $$;

SET teste.uid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.rodar_geracao_hoje(); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'conta suspensa nao roda a rotina');
END $$;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
RESET ROLE;

DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN
    INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao, dataagendamento, origematribuicaoid)
    VALUES (1, 7203, 7011, 10, 'Unica', now(), now(), 7410);
    deu_erro := false;
  EXCEPTION WHEN unique_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o banco impede passar a mesma tarefa duas vezes no mesmo dia, por qualquer caminho');
  PERFORM public.exigir(NOT has_function_privilege('authenticated', 'public.rotinas_despachar(timestamptz)', 'EXECUTE')
                        AND NOT has_function_privilege('anon', 'public.rotinas_despachar(timestamptz)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.lista_do_dia_gerar(integer, date, date, boolean)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.rotina_fechamento_mensal(integer, timestamptz)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.rotina_conferencia_livro(integer, timestamptz)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.rotina_limpeza(integer, timestamptz)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.rotina_registrar(integer, text, date, text, timestamptz, text, jsonb, text, boolean)', 'EXECUTE'),
                        'funcoes da rotina nao ficam liberadas para o navegador');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 39. Telegram (Etapa 1.13A)
--     Chats: Tina 5001 (conta A), Vitor 5002 (validador loja 10), Nina 5003,
--     Otto 5004 (validador só da loja 11), master A 5000; grupos A: gestão
--     -1001 e equipe -1002 (loja 10). Conta B: Bia 6001, validador B 6002,
--     grupo de gestão B -2001 (loja 20).
-- ===========================================================================

RESET ROLE;
SET teste.uid = '';

INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, diadefolga) OVERRIDING SYSTEM VALUE VALUES
  (7501, 1, 'Tina Telegram', 0), (7502, 1, 'Vitor Validador', 0), (7503, 1, 'Nina Naovalida', 0),
  (7504, 1, 'Otto Outra Loja', 0), (7601, 2, 'Bia de B', 0), (7602, 2, 'Beto Validador B', 0);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid, validador) VALUES
  (1, 7501, 10, false), (1, 7502, 10, true), (1, 7503, 10, false), (1, 7504, 11, true),
  (2, 7601, 20, false), (2, 7602, 20, true);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES
  (7701, 1, 'Limpar balcao', 12), (7703, 1, 'Repor casquinhas', 3), (7704, 1, 'Varrer salao', 2), (7705, 1, 'Regar plantas', 1),
  (7702, 2, 'Tarefa de B', 9);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (1, 7701, 10), (1, 7703, 10), (1, 7704, 10), (1, 7705, 10), (2, 7702, 20);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
OVERRIDING SYSTEM VALUE VALUES
  (7801, 1, 7701, 7501, 10, 'Diaria', now() - interval '2 days'),
  (7803, 1, 7703, 7501, 10, 'Diaria', now() - interval '2 days'),
  (7804, 1, 7704, 7501, 10, 'Diaria', now() - interval '2 days'),
  (7805, 1, 7705, 7501, 10, 'Diaria', now() - interval '2 days'),
  (7802, 2, 7702, 7601, 20, 'Diaria', now() - interval '2 days');
INSERT INTO public.produtosloja (produtoid, contaid, nome, custoempontos, ativo) OVERRIDING SYSTEM VALUE VALUES
  (7901, 1, 'Brinde', 5, true), (7902, 2, 'Brinde de B', 1, true);

CREATE TEMP TABLE tg_b_antes AS
SELECT (SELECT md5(string_agg(e::text, '' ORDER BY entregaid)) FROM public.entregas e WHERE contaid = 2) AS entregas,
       (SELECT md5(string_agg(m::text, '' ORDER BY movimentoid)) FROM public.movimentospontos m WHERE contaid = 2) AS movimentos,
       (SELECT md5(string_agg(f::text, '' ORDER BY funcionarioid)) FROM public.funcionarios f WHERE contaid = 2) AS funcionarios;

-- O contexto do bot NUNCA vale para usuário logado.
SET ROLE authenticated;
SET teste.uid = '';
DO $$
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '39. telegram';
  PERFORM set_config('stgame.bot_conta', '2', false);
  PERFORM set_config('stgame.bot_funcionario', '7601', false);
  PERFORM set_config('stgame.bot_canal', 'telegram', false);
  PERFORM public.exigir(public.minha_conta() IS NULL AND (SELECT count(*) FROM public.funcionarios) = 0,
                        'usuario logado que tenta ativar o contexto do bot nao ve nada');
  BEGIN PERFORM public.bot_quem(6001); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'usuario logado nao chama as funcoes do bot');
  BEGIN PERFORM public.bot_entrar(2, 7601, NULL); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'usuario logado nao entra no contexto do bot');
END $$;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
BEGIN
  PERFORM public.exigir(public.minha_conta() = 1 AND NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE contaid = 2),
                        'master de A com o contexto do bot apontando para B continua so em A');
  PERFORM set_config('stgame.bot_conta', '', false);
  PERFORM set_config('stgame.bot_funcionario', '', false);
  PERFORM set_config('stgame.bot_canal', '', false);
END $$;

-- Convites (pelas telas).
DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM set_config('teste.c_master', public.criar_convite_meu_telegram(), false);
  PERFORM set_config('teste.c_tina', public.criar_convite_telegram(7501), false);
  PERFORM set_config('teste.c_vitor', public.criar_convite_telegram(7502), false);
  PERFORM set_config('teste.c_nina', public.criar_convite_telegram(7503), false);
  PERFORM set_config('teste.c_otto', public.criar_convite_telegram(7504), false);
  PERFORM set_config('teste.c_gestao', public.criar_convite_grupo(10, 'gestao'), false);
  PERFORM set_config('teste.c_equipe', public.criar_convite_grupo(10, 'equipe'), false);
  PERFORM public.exigir(current_setting('teste.c_tina') ~ '^[0-9a-f]{64}$', 'convite tem codigo longo e aleatorio (64 caracteres)');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.telegramvinculos WHERE contaid = 2),
                        'A nao ve vinculos de B');
  BEGIN PERFORM public.criar_convite_telegram(7601); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao cria convite para funcionario de B');
  BEGIN PERFORM public.criar_convite_grupo(20, 'gestao'); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'A nao cria convite de grupo para loja de B');
END $$;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
BEGIN
  PERFORM set_config('teste.c_bia', public.criar_convite_telegram(7601), false);
  PERFORM set_config('teste.c_vb', public.criar_convite_telegram(7602), false);
  PERFORM set_config('teste.c_gb', public.criar_convite_grupo(20, 'gestao'), false);
END $$;

-- O bot (servidor) usa os convites.
RESET ROLE;
SET teste.uid = '';
DO $$
DECLARE r jsonb; i integer;
BEGIN
  PERFORM public.exigir(public.bot_registrar_update(900001) AND NOT public.bot_registrar_update(900001),
                        'mensagem repetida do Telegram (mesmo update_id) e tratada uma vez so');
  PERFORM public.exigir(public.bot_quem(7777)->>'status' = 'sem_vinculo', 'chat sem vinculo nao recebe dado nenhum');

  r := public.bot_usar_convite(5000, 'private', current_setting('teste.c_master'), 'Ana');
  PERFORM public.exigir((r->>'ok')::boolean AND r->>'tipo' = 'master', 'master liga o proprio Telegram');
  r := public.bot_usar_convite(5001, 'private', current_setting('teste.c_tina'), 'Tina');
  PERFORM public.exigir((r->>'ok')::boolean AND r->>'nome' = 'Tina Telegram', 'pessoa liga o Telegram pelo convite');
  r := public.bot_usar_convite(5009, 'private', current_setting('teste.c_tina'), 'Outro');
  PERFORM public.exigir(r->>'erro' = 'invalido', 'convite usado duas vezes e recusado');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.avisossistema WHERE contaid = 1 AND texto = 'Tina Telegram ligou o Telegram agora.')
                        AND EXISTS (SELECT 1 FROM public.mensagensfila WHERE contaid = 1 AND chatid = 5000 AND tipo = 'vinculo'),
                        'vinculo novo avisa o master no sistema e no Telegram');

  UPDATE public.telegramconvites SET expiraem = now() - interval '1 minute' WHERE codigohash = public.telegram_hash(current_setting('teste.c_nina'));
  r := public.bot_usar_convite(5003, 'private', current_setting('teste.c_nina'), 'Nina');
  PERFORM public.exigir(r->>'erro' = 'invalido', 'convite vencido e recusado');
  UPDATE public.telegramconvites SET expiraem = now() + interval '1 hour' WHERE codigohash = public.telegram_hash(current_setting('teste.c_nina'));

  r := public.bot_usar_convite(5002, 'private', current_setting('teste.c_gestao'), 'X');
  PERFORM public.exigir(r->>'erro' = 'invalido', 'convite de grupo nao liga conversa privada');
  r := public.bot_usar_convite(-1001, 'group', current_setting('teste.c_tina'), 'Grupo');
  PERFORM public.exigir(r->>'erro' = 'invalido', 'convite de pessoa nao liga grupo');

  FOR i IN 1..5 LOOP
    PERFORM public.bot_usar_convite(5999, 'private', repeat('0', 64), 'Chutador');
  END LOOP;
  r := public.bot_usar_convite(5999, 'private', current_setting('teste.c_nina'), 'Chutador');
  PERFORM public.exigir(r->>'erro' = 'bloqueado', 'depois de 5 codigos errados em 1 hora, o chat fica bloqueado (nem codigo certo passa)');

  PERFORM public.exigir((public.bot_usar_convite(5002, 'private', current_setting('teste.c_vitor'), 'Vitor')->>'ok')::boolean
                        AND (public.bot_usar_convite(5003, 'private', current_setting('teste.c_nina'), 'Nina')->>'ok')::boolean
                        AND (public.bot_usar_convite(5004, 'private', current_setting('teste.c_otto'), 'Otto')->>'ok')::boolean
                        AND (public.bot_usar_convite(-1001, 'supergroup', current_setting('teste.c_gestao'), 'Gestao A')->>'ok')::boolean
                        AND (public.bot_usar_convite(-1002, 'group', current_setting('teste.c_equipe'), 'Equipe A')->>'ok')::boolean
                        AND (public.bot_usar_convite(6001, 'private', current_setting('teste.c_bia'), 'Bia')->>'ok')::boolean
                        AND (public.bot_usar_convite(6002, 'private', current_setting('teste.c_vb'), 'Beto')->>'ok')::boolean,
                        'demais vinculos feitos');
  r := public.bot_usar_convite(-1001, 'group', current_setting('teste.c_gb'), 'Gestao A');
  PERFORM public.exigir(r->>'erro' = 'invalido', 'grupo ja ligado a A nao aceita codigo de B');
  PERFORM public.exigir((public.bot_usar_convite(-2001, 'group', current_setting('teste.c_gb'), 'Gestao B')->>'ok')::boolean,
                        'grupo de B ligado com codigo de B');
  PERFORM public.exigir(public.bot_grupo(-9999)->>'vinculado' = 'false', 'grupo sem codigo fica sem vinculo');
END $$;

-- Tarefas, foto e entrega.
DO $$
DECLARE r jsonb; v_e1 integer; v_e2 integer; v_e3 integer;
BEGIN
  r := public.bot_tarefas(5001);
  PERFORM public.exigir(r->'tarefas' @> '[{"atribuicaoid": 7801}]' AND NOT r::text LIKE '%Tarefa de B%',
                        'bot mostra as tarefas de hoje da pessoa, e nada de outra conta');
  PERFORM public.exigir(public.bot_iniciar_entrega(5001, 7802)->>'ok' = 'false', 'bot de A nao inicia entrega de tarefa de B');
  PERFORM public.exigir(public.bot_conferir_foto(5001, 'fotoA')->>'erro' = 'sem_tarefa', 'foto sem escolher tarefa e recusada');

  PERFORM public.bot_iniciar_entrega(5001, 7801);
  r := public.bot_registrar_entrega(5001, 7801, '1/10/tg-a.jpg', 'fileA', 'fotoA');
  PERFORM public.exigir((r->>'ok')::boolean, 'entrega com foto registrada pelo bot (mesma funcao das telas)');
  v_e1 := (r->>'entregaid')::integer;
  PERFORM set_config('teste.e1', v_e1::text, false);
  PERFORM public.exigir((SELECT canalenvio = 'telegram' AND fotoidunico = 'fotoA' AND statusvalidacao = 'Pendente'
                           FROM public.entregas WHERE entregaid = v_e1), 'entrega marcada como vinda do Telegram');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.mensagensfila WHERE chatid = -1001 AND tipo = 'entrega_nova' AND referencia = v_e1),
                        'entrega nova vai para o grupo de gestao da loja');

  PERFORM public.bot_iniciar_entrega(5001, 7803);
  PERFORM public.exigir(public.bot_conferir_foto(5001, 'fotoA')->>'erro' = 'repetida', 'foto repetida e recusada');
  UPDATE bot.estados SET expiraem = now() - interval '1 second' WHERE chatid = 5001;
  PERFORM public.exigir(public.bot_conferir_foto(5001, 'fotoB')->>'erro' = 'expirou', 'foto depois de 10 minutos e recusada');

  PERFORM public.bot_iniciar_entrega(5001, 7803);
  v_e2 := (public.bot_registrar_entrega(5001, 7803, '1/10/tg-b.jpg', 'fileB', 'fotoB')->>'entregaid')::integer;
  PERFORM public.bot_iniciar_entrega(5001, 7804);
  v_e3 := (public.bot_registrar_entrega(5001, 7804, '1/10/tg-c.jpg', 'fileC', 'fotoC')->>'entregaid')::integer;
  PERFORM set_config('teste.e2', v_e2::text, false);
  PERFORM set_config('teste.e3', v_e3::text, false);
  PERFORM public.exigir(v_e2 IS NOT NULL AND v_e3 IS NOT NULL, 'outras duas entregas registradas');
END $$;

-- Validação pelo grupo de gestão.
DO $$
DECLARE r jsonb; e1 integer := current_setting('teste.e1')::integer; e2 integer := current_setting('teste.e2')::integer;
        e3 integer := current_setting('teste.e3')::integer; v_saldo integer;
BEGIN
  PERFORM public.exigir(public.bot_validar(-1001, 5003, e1, true)->>'erro' = 'sem_permissao'
                        AND (SELECT statusvalidacao FROM public.entregas WHERE entregaid = e1) = 'Pendente',
                        'quem nao e validador recebe "sem permissao" e nada muda');
  PERFORM public.exigir(public.bot_validar(-1001, 5004, e1, true)->>'erro' = 'sem_permissao',
                        'validador de outra loja nao aprova nesta loja');
  PERFORM public.exigir(public.bot_validar(-1001, 6002, e1, true)->>'erro' = 'sem_permissao',
                        'validador de B nao aprova no grupo de A');
  PERFORM public.exigir(public.bot_validar(-2001, 5002, e1, true)->>'ok' = 'false'
                        AND (SELECT statusvalidacao FROM public.entregas WHERE entregaid = e1) = 'Pendente',
                        'validador de A nao aprova entrega de A pelo grupo de B');
  PERFORM public.exigir(public.bot_validar(-1002, 5002, e1, true)->>'erro' = 'grupo',
                        'aprovacao so no grupo de gestao (nao no da equipe)');

  r := public.bot_validar(-1001, 5002, e1, true);
  PERFORM public.exigir((r->>'ok')::boolean AND (r->>'pontos')::integer = 12, 'validador da loja aprova pelo Telegram');
  PERFORM public.exigir((SELECT statusvalidacao = 'Aprovada' AND canalvalidacao = 'telegram' AND validadorfuncionarioid = 7502
                           FROM public.entregas WHERE entregaid = e1), 'fica gravado quem aprovou e por qual canal');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.movimentospontos WHERE entregaid = e1 AND tipo = 'aprovacao' AND pontos = 12),
                        'os pontos entram pelo livro');
  PERFORM public.exigir(public.bot_validar(-1001, 5002, e1, true)->>'erro' = 'ja_validada', 'segunda aprovacao nao muda nada');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.mensagensfila WHERE chatid = 5001 AND tipo = 'entrega_aprovada' AND referencia = e1),
                        'a pessoa recebe o aviso de aprovada');

  PERFORM public.exigir((public.bot_recusa_pedir(-1001, 5002, e2)->>'ok')::boolean, 'validador pede para recusar');
  PERFORM public.bot_recusa_guardar(-1001, 5002, e2, 555);
  PERFORM public.exigir(public.bot_recusa_motivo(-1001, 5003, 555, 'x')->>'erro' = 'sem_pedido', 'outra pessoa nao responde o motivo');
  PERFORM public.exigir(public.bot_recusa_motivo(-1001, 5002, 556, 'x')->>'erro' = 'sem_pedido', 'resposta a outra mensagem nao conta');
  r := public.bot_recusa_motivo(-1001, 5002, 555, 'Foto escura');
  PERFORM public.exigir((r->>'ok')::boolean AND (SELECT statusvalidacao = 'Recusada' AND motivorecusa = 'Foto escura'
                                                    FROM public.entregas WHERE entregaid = e2),
                        'recusa com o motivo guardado no banco');

  r := public.bot_validar(-1001, 5000, e3, true);
  PERFORM public.exigir((r->>'ok')::boolean AND (SELECT aprovadopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                                                     AND canalvalidacao = 'telegram' AND validadorfuncionarioid IS NULL
                                                   FROM public.entregas WHERE entregaid = e3),
                        'master aprova pelo Telegram como ele mesmo');

  SELECT saldopontos INTO v_saldo FROM public.funcionarios WHERE funcionarioid = 7501;
  PERFORM public.exigir(v_saldo = (SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 7501),
                        'saldo da pessoa bate com o livro');
END $$;

-- Menu, trava do feedback, prêmio, comanda.
DO $$
DECLARE r jsonb; v_saldo integer;
BEGIN
  PERFORM public.exigir((public.bot_consulta(5001, 'saldo')->>'saldo')::integer
                        = (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 7501), 'saldo pelo bot');
  PERFORM public.exigir(public.bot_resgatar(5001, 7901)->>'erro' = 'falta_feedback', 'resgate travado sem o feedback de ontem');
  PERFORM public.exigir(public.bot_comanda_iniciar(5001)->>'erro' = 'falta_feedback', 'comanda travada sem o feedback de ontem');
  PERFORM public.exigir((public.bot_consulta(5001, 'ranking')->>'ok')::boolean, 'ranking funciona sem trava');

  r := public.bot_feedback(5001, 'ontem', 8);
  PERFORM public.exigir((r->>'ok')::boolean AND (SELECT origem FROM public.feedbacks WHERE funcionarioid = 7501
                                                    AND datafeedback = public.dia_em_sao_paulo(now()) - 1) = 'bot',
                        'feedback pelo bot (mesma funcao, origem = bot)');
  PERFORM public.exigir(public.bot_resgatar(5001, 7902)->>'ok' = 'false', 'bot de A nao resgata premio de B');
  SELECT saldopontos INTO v_saldo FROM public.funcionarios WHERE funcionarioid = 7501;
  r := public.bot_resgatar(5001, 7901);
  PERFORM public.exigir((r->>'ok')::boolean AND (r->>'saldo')::integer = v_saldo - 5
                        AND (SELECT status FROM public.resgates WHERE resgateid = (r->>'resgateid')::integer) = 'Pendente',
                        'resgate pelo bot: pontos saem pelo livro e a entrega fica para a gestao');
  PERFORM public.exigir((public.bot_comanda_iniciar(5001)->>'ok')::boolean, 'comanda liberada depois do feedback');
  r := public.bot_comanda(5001, 0.06);
  PERFORM public.exigir((r->>'ok')::boolean AND (r->>'pontos')::integer = 2, 'abate na comanda pelo bot (mesma funcao)');
  PERFORM public.exigir((SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = 7501)
                        = (SELECT sum(pontos) FROM public.movimentospontos WHERE funcionarioid = 7501),
                        'saldo continua batendo com o livro');

  PERFORM public.exigir(public.bot_nao_aplicavel_iniciar(5001, 7801)->>'ok' = 'false', 'tarefa ja entregue hoje nao vira "nao se aplica"');
  PERFORM public.exigir((public.bot_nao_aplicavel_iniciar(5001, 7805)->>'ok')::boolean, 'bot pede o motivo do "nao se aplica"');
  r := public.bot_nao_aplicavel(5001, 'Chuva forte');
  PERFORM public.exigir((r->>'ok')::boolean, 'bot registra o "nao se aplica"');
  PERFORM public.exigir((SELECT status = 'Pendente' AND origem = 'bot' AND motivo = 'Chuva forte'
                           FROM public.justificativas WHERE atribuicaoid = 7805),
                        '"nao se aplica" pelo bot vira justificativa pendente (origem = bot)');
END $$;

-- Comunicado e documento pessoal.
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
BEGIN
  PERFORM set_config('teste.com_tg', public.publicar_comunicado('Aviso do bot', 'Leia pelo Telegram', 0, 'funcionarios', NULL, ARRAY[7501])::text, false);
END $$;
RESET ROLE;
SET teste.uid = '';
INSERT INTO public.documentospessoais (documentoid, contaid, funcionarioid, tipodocumento, mesano, caminhoarquivo, nomearquivo, situacao)
OVERRIDING SYSTEM VALUE VALUES (7951, 1, 7501, 'Holerite', '2026-08-01', '1/funcionarios/7501/holerite.pdf', 'holerite.pdf', 'Ativo');
INSERT INTO public.documentospessoaisciencia (contaid, documentoid, funcionarioid, status) VALUES (1, 7951, 7501, 'Pendente');
DO $$
DECLARE r jsonb; v_ass integer;
BEGIN
  SELECT assinaturaid INTO v_ass FROM public.documentosassinaturas
   WHERE documentoid = current_setting('teste.com_tg')::integer AND funcionarioid = 7501;
  PERFORM public.exigir(public.bot_ciencia(5002, v_ass)->>'ok' = 'false', 'outra pessoa nao da ciencia no comunicado de Tina');
  r := public.bot_ciencia(5001, v_ass);
  PERFORM public.exigir((r->>'ok')::boolean AND (SELECT origem = 'funcionario' AND statusassinatura = 'Ciente'
                                                    FROM public.documentosassinaturas WHERE assinaturaid = v_ass),
                        'ciencia pelo bot com origem = funcionario');

  PERFORM public.exigir(public.bot_documento(5001, 'group', 7951)->>'ok' = 'false', 'documento pessoal nunca em grupo');
  PERFORM public.exigir(public.bot_documento(5002, 'private', 7951)->>'ok' = 'false', 'documento de outra pessoa e recusado');
  r := public.bot_documento(5001, 'private', 7951);
  PERFORM public.exigir((r->>'ok')::boolean AND r->>'caminho' = '1/funcionarios/7501/holerite.pdf'
                        AND EXISTS (SELECT 1 FROM public.documentosacessos WHERE documentoid = 7951 AND funcionarioid = 7501
                                     AND canal = 'telegram' AND acao = 'visualizacao'),
                        'documento pessoal so na conversa privada da propria pessoa, com registro de acesso');
  r := public.bot_ciencia_documento(5001, 7951);
  PERFORM public.exigir((r->>'ok')::boolean, 'bot registra a ciencia do documento');
  PERFORM public.exigir((SELECT origem FROM public.documentospessoaisciencia WHERE documentoid = 7951) = 'funcionario',
                        'ciencia do documento pelo bot com origem = funcionario');
END $$;

-- Fila e medição.
DO $$
DECLARE v jsonb; x jsonb; e1 integer := current_setting('teste.e1')::integer;
BEGIN
  -- O teste nao pode depender da hora em que roda: estas pessoas nao tem
  -- horario de trabalho, entao o silencio da noite as pegaria. Aqui o silencio
  -- e jogado para daqui a duas horas (e volta ao normal no fim do bloco).
  UPDATE public.configuracoes
     SET valor = to_char(((now() AT TIME ZONE 'America/Sao_Paulo') + interval '2 hours')::time, 'HH24:MI')
   WHERE chave = 'HORARIO_SILENCIO_INICIO';
  UPDATE public.configuracoes
     SET valor = to_char(((now() AT TIME ZONE 'America/Sao_Paulo') + interval '3 hours')::time, 'HH24:MI')
   WHERE chave = 'HORARIO_SILENCIO_FIM';

  v := public.bot_fila_pegar(50);
  PERFORM public.exigir(jsonb_array_length(v) > 0, 'fila entrega os avisos para envio');
  FOR x IN SELECT * FROM jsonb_array_elements(v) LOOP
    PERFORM public.exigir((SELECT contaid FROM public.mensagensfila WHERE filaid = (x->>'filaid')::bigint)
                          = coalesce((SELECT contaid FROM public.telegramvinculos WHERE chatid = (x->>'chat_id')::bigint AND ativo
                                       ORDER BY vinculoid DESC LIMIT 1), -1),
                          'cada aviso vai para um chat da mesma conta');
    PERFORM public.bot_fila_resultado((x->>'filaid')::bigint, true, 700 + (x->>'filaid')::integer, NULL, 0);
  END LOOP;
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v) y
                                     WHERE y->>'tipo' = 'entrega_nova' AND (y->>'filaid')::bigint IN
                                       (SELECT filaid FROM public.mensagensfila WHERE referencia = e1 AND tipo = 'entrega_nova')),
                        'entrega ja validada nao e mais oferecida ao grupo');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.usomensagens WHERE contaid = 1 AND canal = 'telegram'),
                        'envio medido por conta, canal, tipo e dia');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'usomensagens'
                                     AND column_name NOT IN ('contaid', 'lojaid', 'canal', 'tipo', 'dia', 'quantidade')),
                        'a medicao nao guarda texto');

  UPDATE public.configuracoes SET valor = '22:00' WHERE chave = 'HORARIO_SILENCIO_INICIO';
  UPDATE public.configuracoes SET valor = '07:00' WHERE chave = 'HORARIO_SILENCIO_FIM';
END $$;

-- Funcionário desativado não usa nada; master desliga um vínculo.
UPDATE public.funcionarios SET ativo = false WHERE funcionarioid = 7503;
DO $$
BEGIN
  PERFORM public.exigir(public.bot_quem(5003)->>'status' = 'sem_vinculo'
                        AND public.bot_tarefas(5003)->>'erro' = 'sem_vinculo'
                        AND public.bot_feedback(5003, 'hoje', 5)->>'erro' = 'sem_vinculo',
                        'funcionario desativado nao consegue usar nada');
END $$;

SET ROLE authenticated;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN
    PERFORM public.desligar_telegram(-1); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'desligar vinculo inexistente da erro');
END $$;
RESET ROLE;
DO $$
DECLARE v integer; deu_erro boolean;
BEGIN
  SELECT vinculoid INTO v FROM public.telegramvinculos WHERE funcionarioid = 7501 AND ativo;
  PERFORM set_config('teste.v_tina', v::text, false);
END $$;
SET ROLE authenticated;
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN PERFORM public.desligar_telegram(current_setting('teste.v_tina')::integer); deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao desliga o Telegram de alguem de A');
END $$;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
BEGIN
  PERFORM public.desligar_telegram(current_setting('teste.v_tina')::integer);
END $$;
RESET ROLE;
SET teste.uid = '';
DO $$
BEGIN
  PERFORM public.exigir(public.bot_quem(5001)->>'status' = 'sem_vinculo', 'master desliga o Telegram da pessoa');
  PERFORM public.exigir((SELECT entregas FROM tg_b_antes) IS NOT DISTINCT FROM
                          (SELECT md5(string_agg(e::text, '' ORDER BY entregaid)) FROM public.entregas e WHERE contaid = 2)
                        AND (SELECT movimentos FROM tg_b_antes) IS NOT DISTINCT FROM
                          (SELECT md5(string_agg(m::text, '' ORDER BY movimentoid)) FROM public.movimentospontos m WHERE contaid = 2)
                        AND (SELECT funcionarios FROM tg_b_antes) IS NOT DISTINCT FROM
                          (SELECT md5(string_agg(f::text, '' ORDER BY funcionarioid)) FROM public.funcionarios f WHERE contaid = 2),
                        'o bot da conta A nunca alterou nada da conta B');
  PERFORM public.exigir(NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname LIKE 'bot\_%'
         AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
    'nenhuma funcao do bot fica liberada para o navegador');
END $$;

-- Como o webhook chama no Supabase (papel service_role).
SET ROLE service_role;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.bot_consulta(5002, 'saldo');
  PERFORM public.exigir((r->>'ok')::boolean, 'funcoes do bot funcionam com a chave de servidor (service_role)');
  r := public.bot_feedback(5002, 'hoje', 9);
  PERFORM public.exigir((r->>'ok')::boolean, 'contexto do bot vale com service_role');
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM public.exigir((SELECT origem FROM public.feedbacks WHERE funcionarioid = 7502
                          AND datafeedback = public.dia_em_sao_paulo(now())) = 'bot',
                        'feedback feito com a chave de servidor fica com origem = bot');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ===========================================================================
-- 40. Rotinas com mensagem (Etapa 1.13B1)
--     Diana 7510 (chats 5010, lojas 10 e 11, 08:00–17:00), Nelson 7511
--     (5011, loja 10, turno da noite 18:00–02:00), Sandra 7512 (5012, sem
--     horário), Fábio 7513 (5013, de folga hoje). Conta B: Bruno 7610 (6010).
-- ===========================================================================

RESET ROLE;
SET teste.uid = '';

INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, diadefolga, horarionotificacao, horariosaida)
OVERRIDING SYSTEM VALUE VALUES
  (7510, 1, 'Diana Diurna',   0, '08:00', '17:00'),
  (7511, 1, 'Nelson Noturno', 0, '18:00', '02:00'),
  (7512, 1, 'Sandra Sem Horario', 0, NULL, NULL),
  (7513, 1, 'Fabio Folga', (extract(dow FROM public.dia_em_sao_paulo(now()))::integer + 1), '08:00', '17:00'),
  (7610, 2, 'Bruno de B',    0, '08:00', '17:00');
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES
  (1, 7510, 10), (1, 7510, 11), (1, 7511, 10), (1, 7512, 10), (1, 7513, 10), (2, 7610, 20);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES
  (7710, 1, 'Conferir freezer', 5), (7711, 1, 'Trocar sabor', 5), (7712, 1, 'Lavar calhas', 8),
  (7713, 1, 'Missao do estoque', 20), (7714, 1, 'Tarefa do Nelson', 4), (7715, 2, 'Tarefa do Bruno', 6);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES
  (1, 7710, 10), (1, 7711, 11), (1, 7712, 10), (1, 7713, 10), (1, 7714, 10), (2, 7715, 20);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                      dataatribuicao, horariodisparo)
OVERRIDING SYSTEM VALUE VALUES
  (7810, 1, 7710, 7510, 10, 'Diaria', now() - interval '3 days', NULL),   -- Diana, loja 10
  (7811, 1, 7711, 7510, 11, 'Diaria', now() - interval '3 days', NULL),   -- Diana, loja 11
  (7812, 1, 7712, 7513, 10, 'Diaria', now() - interval '3 days', NULL),   -- Fabio (de folga hoje)
  (7814, 1, 7714, 7511, 10, 'Diaria', now() - interval '3 days', NULL),   -- Nelson
  (7813, 1, 7713, NULL,  10, 'Diaria', now() - interval '3 days', '10:00'),  -- missão da equipe
  (7815, 2, 7715, 7610, 20, 'Diaria', now() - interval '3 days', NULL);
-- Chats: pessoas de A e de B, e o grupo da equipe de B.
INSERT INTO public.telegramvinculos (contaid, tipo, chatid, funcionarioid) VALUES
  (1, 'pessoa', 5010, 7510), (1, 'pessoa', 5011, 7511), (1, 'pessoa', 5012, 7512), (1, 'pessoa', 5013, 7513),
  (2, 'pessoa', 6010, 7610);
INSERT INTO public.telegramvinculos (contaid, tipo, chatid, lojaid, papelgrupo) VALUES (2, 'grupo', -2002, 20, 'equipe');

CREATE TEMP TABLE b1_b_antes AS
SELECT (SELECT md5(string_agg(m::text, '' ORDER BY filaid)) FROM public.mensagensfila m WHERE contaid = 2) AS fila,
       (SELECT count(*) FROM public.mensagensfila WHERE contaid = 2) AS fila_n,
       (SELECT md5(string_agg(t::text, '' ORDER BY atribuicaoid)) FROM public.tarefasatribuidas t WHERE contaid = 2) AS atribuicoes;

-- ---------------------------------------------------------------------------
-- Janela de envio: turno, turno da noite, silêncio e folga
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  j jsonb;
BEGIN
  RAISE NOTICE '40. rotinas com mensagem';

  -- Turno da noite: 23:00 está DENTRO do turno, mesmo no horário de silêncio.
  j := public.bot_janela(1, 7511, public.instante_local(v_hoje, '23:00'));
  PERFORM public.exigir((j->>'pode')::boolean, 'turno da noite recebe as 23:00, apesar do silencio');

  -- 01:00 do dia seguinte ainda é o turno que começou ontem.
  j := public.bot_janela(1, 7511, public.instante_local(v_hoje + 1, '01:00'));
  PERFORM public.exigir((j->>'pode')::boolean, 'turno da noite recebe depois da meia-noite');

  -- 03:00 já passou do fim (02:00 + 30 min de folga).
  j := public.bot_janela(1, 7511, public.instante_local(v_hoje + 1, '03:00'));
  PERFORM public.exigir(NOT (j->>'pode')::boolean AND j->>'motivo' = 'fora_do_turno',
                        'depois do fim do turno da noite, espera');
  PERFORM public.exigir((j->>'proxima')::timestamptz = public.instante_local(v_hoje + 1, '18:00'),
                        'a espera vai ate a proxima entrada da noite');

  -- Diurna: 23:00 está fora do turno dela.
  j := public.bot_janela(1, 7510, public.instante_local(v_hoje, '23:00'));
  PERFORM public.exigir(NOT (j->>'pode')::boolean, 'quem trabalha de dia nao recebe as 23:00');
  j := public.bot_janela(1, 7510, public.instante_local(v_hoje, '10:00'));
  PERFORM public.exigir((j->>'pode')::boolean, 'quem trabalha de dia recebe as 10:00');

  -- Sem horário: vale só o silêncio.
  j := public.bot_janela(1, 7512, public.instante_local(v_hoje, '23:00'));
  PERFORM public.exigir(NOT (j->>'pode')::boolean AND j->>'motivo' = 'silencio',
                        'sem horario, o silencio da noite vale');
  j := public.bot_janela(1, 7512, public.instante_local(v_hoje, '12:00'));
  PERFORM public.exigir((j->>'pode')::boolean, 'sem horario, recebe avisos durante o dia');

  -- Folga: nada.
  j := public.bot_janela(1, 7513, public.instante_local(v_hoje, '10:00'));
  PERFORM public.exigir(NOT (j->>'pode')::boolean AND j->>'motivo' = 'folga', 'na folga ninguem recebe');
END $$;

-- ---------------------------------------------------------------------------
-- As rotinas: início, lembretes, fim, e nunca repetir
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  v_n integer;
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;

  -- 08:00: início da jornada.
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '08:00'));
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '08:05'));   -- roda de novo
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '08:10'));   -- e de novo

  SELECT count(*) INTO v_n FROM public.mensagensfila
   WHERE contaid = 1 AND tipo = 'inicio_jornada' AND funcionarioid = 7510;
  PERFORM public.exigir(v_n = 1, 'rodar a rotina tres vezes gera uma mensagem so (etiqueta unica)');

  SELECT count(*) INTO v_n FROM public.mensagensfila
   WHERE contaid = 1 AND tipo = 'inicio_jornada' AND funcionarioid IN (7512, 7513);
  PERFORM public.exigir(v_n = 0, 'quem esta de folga ou sem horario nao recebe a jornada');

  SELECT count(*) INTO v_n FROM public.mensagensfila WHERE contaid = 1 AND tipo = 'inicio_jornada';
  PERFORM public.exigir(v_n = 1, 'quem trabalha em duas lojas recebe uma mensagem so');

  -- Turno da noite: início às 18:00 e fim às 02:00 do dia seguinte.
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '18:00'));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.mensagensfila
                                 WHERE contaid = 1 AND tipo = 'inicio_jornada' AND funcionarioid = 7511
                                   AND chave = 'inicio:7511:' || v_hoje),
                        'turno da noite recebe o inicio as 18:00');
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje + 1, '02:05'));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.mensagensfila
                                 WHERE contaid = 1 AND tipo = 'fim_jornada' AND funcionarioid = 7511
                                   AND chave = 'fim:7511:' || v_hoje),
                        'o fim do turno da noite conta no dia em que o turno comecou');

  -- Lembretes: 3 h e 6 h depois da entrada da Diana.
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '11:00'));
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '14:00'));
  SELECT count(*) INTO v_n FROM public.mensagensfila
   WHERE contaid = 1 AND funcionarioid = 7510 AND tipo IN ('lembrete3', 'lembrete6');
  PERFORM public.exigir(v_n = 2, 'os lembretes de 3 h e 6 h sao gerados');

  -- Nada foi criado para a conta B.
  SELECT count(*) INTO v_n FROM public.mensagensfila WHERE contaid = 2;
  PERFORM public.exigir(v_n = (SELECT fila_n FROM b1_b_antes), 'a rotina da conta A nao cria mensagem na conta B');
END $$;

-- ---------------------------------------------------------------------------
-- Liga/desliga por loja
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  INSERT INTO public.mensagensrotinas (contaid, lojaid, rotina, ativo) VALUES (1, 10, 'inicio_jornada', false);
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '08:00'));
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.mensagensfila WHERE contaid = 1 AND tipo = 'inicio_jornada'
                                  AND funcionarioid = 7510),
                        'desligado numa loja, quem tem outra loja ligada continua recebendo');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.mensagensfila WHERE contaid = 1 AND tipo = 'inicio_jornada'
                                      AND funcionarioid = 7511),
                        'desligado na loja, quem so tem essa loja nao recebe');

  DELETE FROM public.mensagensfila WHERE contaid = 1;
  INSERT INTO public.mensagensrotinas (contaid, lojaid, rotina, ativo) VALUES (1, 11, 'inicio_jornada', false);
  PERFORM public.rotina_mensagens(1, public.instante_local(v_hoje, '08:00'));
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.mensagensfila WHERE contaid = 1 AND tipo = 'inicio_jornada'),
                        'desligado nas duas lojas, ninguem recebe');
  DELETE FROM public.mensagensrotinas WHERE contaid = 1;
END $$;

-- ---------------------------------------------------------------------------
-- Fila: silêncio, limite do dia, lembrete cancelado e avisos juntados
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  v_id bigint;
  v_saida jsonb;
  r public.mensagensfila%ROWTYPE;
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  -- O teste nao pode depender da hora em que roda: poe a Diana DENTRO do
  -- turno agora (entrada 1 h atras, saida daqui a 1 h). O horario fixo dela
  -- volta no fim do bloco.
  UPDATE public.funcionarios
     SET horarionotificacao = ((now() AT TIME ZONE 'America/Sao_Paulo') - interval '1 hour')::time,
         horariosaida       = ((now() AT TIME ZONE 'America/Sao_Paulo') + interval '1 hour')::time
   WHERE funcionarioid = 7510;

  -- Lembrete sem nada em aberto: some na hora de enviar.
  INSERT INTO public.entregas (contaid, lojaid, atribuicaoid, tarefaid, funcionarioid, statusvalidacao, dataenvio)
  VALUES (1, 10, 7810, 7710, 7510, 'Pendente', now()), (1, 11, 7811, 7711, 7510, 'Pendente', now());
  v_id := public.bot_enfileirar_ex(1, NULL, 5010, 7510, 'lembrete3', '{}', NULL, 'teste-lembrete', NULL, true, now());
  v_saida := public.bot_fila_pegar(10);
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = v_id;
  PERFORM public.exigir(r.status = 'descartada', 'lembrete some quando as tarefas ja foram entregues');

  -- Avisos juntados: duas aprovações viram uma mensagem só.
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  PERFORM public.bot_enfileirar_ex(1, 10, 5010, 7510, 'entrega_aprovada',
    jsonb_build_object('metodo', 'sendMessage', 'titulo', 'Tarefa 1', 'pontos', 10, 'texto', 'a'),
    NULL, NULL, 'juntas', false, now() - interval '1 minute');
  PERFORM public.bot_enfileirar_ex(1, 10, 5010, 7510, 'entrega_aprovada',
    jsonb_build_object('metodo', 'sendMessage', 'titulo', 'Tarefa 2', 'pontos', 5, 'texto', 'b'),
    NULL, NULL, 'juntas', false, now() - interval '1 minute');
  v_saida := public.bot_fila_pegar(10);
  PERFORM public.exigir(jsonb_array_length(v_saida) = 1, 'duas aprovacoes juntas viram uma mensagem so');
  PERFORM public.exigir((v_saida->0->>'texto') LIKE '%2 entregas aprovadas%' AND (v_saida->0->>'texto') LIKE '%15 pontos%',
                        'a mensagem juntada soma os pontos das duas');
  PERFORM public.exigir((SELECT count(*) FROM public.mensagensfila
                          WHERE contaid = 1 AND status = 'descartada' AND erro = 'juntada') = 1,
                        'a segunda mensagem nao e enviada de novo');

  UPDATE public.funcionarios SET horarionotificacao = '08:00', horariosaida = '17:00'
   WHERE funcionarioid = 7510;
  DELETE FROM public.mensagensfila WHERE contaid = 1;
END $$;

-- Fora do turno (e no silêncio): o aviso espera a próxima entrada.
DO $$
DECLARE v_id bigint; v_saida jsonb; r public.mensagensfila%ROWTYPE; v_hora time;
BEGIN
  v_hora := (now() AT TIME ZONE 'America/Sao_Paulo')::time;
  -- Turno curto daqui a 2 horas: agora a Diana está fora do turno dela.
  UPDATE public.funcionarios SET horarionotificacao = v_hora + interval '2 hours',
                                 horariosaida = v_hora + interval '4 hours'
   WHERE funcionarioid = 7510;
  v_id := public.bot_enfileirar_ex(1, NULL, 5010, 7510, 'conquista',
            jsonb_build_object('metodo', 'sendMessage', 'texto', 'x'), NULL, NULL, NULL, false, now());
  v_saida := public.bot_fila_pegar(10);
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = v_id;
  PERFORM public.exigir(r.status = 'pendente' AND r.proximaem > now(),
                        'aviso fora do turno espera a proxima entrada');
  PERFORM public.exigir(jsonb_array_length(v_saida) = 0, 'nada e enviado fora do turno');
  UPDATE public.funcionarios SET horarionotificacao = '08:00', horariosaida = '17:00' WHERE funcionarioid = 7510;
  DELETE FROM public.mensagensfila WHERE contaid = 1;
END $$;

-- Depois do FIM do expediente: espera a proxima entrada, nao vira "folga".
-- (Defeito da 1.13B1 corrigido em 23/09/2026: o aviso das 18:00 de quem
-- trabalha ate as 17:00 era guardado como se a pessoa estivesse de folga, e
-- voltava so como resumo — ou sumia depois de 7 dias.)
DO $$
DECLARE v_id bigint; v_saida jsonb; r public.mensagensfila%ROWTYPE; v_hora time; j jsonb;
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  v_hora := (now() AT TIME ZONE 'America/Sao_Paulo')::time;
  -- Turno que COMECOU ha 3 horas e TERMINOU ha 1 hora: expediente encerrado.
  UPDATE public.funcionarios SET horarionotificacao = (v_hora - interval '3 hours')::time,
                                 horariosaida       = (v_hora - interval '1 hour')::time
   WHERE funcionarioid = 7510;
  j := public.bot_janela(1, 7510, now());
  PERFORM public.exigir((j->>'motivo') = 'fora_do_turno',
                        'depois do expediente o motivo e fora_do_turno, nao folga');
  v_id := public.bot_enfileirar_ex(1, NULL, 5010, 7510, 'entrega_aprovada',
            jsonb_build_object('metodo', 'sendMessage', 'texto', 'x'), NULL, NULL, NULL, false, now());
  v_saida := public.bot_fila_pegar(10);
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = v_id;
  PERFORM public.exigir(r.status = 'pendente' AND r.proximaem > now(),
                        'aviso depois do expediente espera a proxima entrada');
  PERFORM public.exigir(r.status <> 'guardada', 'aviso depois do expediente nao vira resumo de ausencia');
  PERFORM public.exigir(jsonb_array_length(v_saida) = 0, 'nada e enviado depois do expediente');

  -- Quem esta de folga hoje continua no caminho do resumo (guardada).
  UPDATE public.funcionarios
     SET diadefolga = (extract(dow FROM public.dia_em_sao_paulo(now()))::integer + 1)
   WHERE funcionarioid = 7510;
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  v_id := public.bot_enfileirar_ex(1, NULL, 5010, 7510, 'entrega_aprovada',
            jsonb_build_object('metodo', 'sendMessage', 'texto', 'y'), NULL, NULL, NULL, false, now());
  PERFORM public.bot_fila_pegar(10);
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = v_id;
  PERFORM public.exigir(r.status = 'guardada', 'na folga o aviso continua sendo guardado para o resumo');

  UPDATE public.funcionarios SET horarionotificacao = '08:00', horariosaida = '17:00', diadefolga = 0
   WHERE funcionarioid = 7510;
  DELETE FROM public.mensagensfila WHERE contaid = 1;
END $$;

-- ---------------------------------------------------------------------------
-- Limite de mensagens por dia
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_id bigint; v_saida jsonb; r public.mensagensfila%ROWTYPE;
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  -- Fora do silencio, seja qual for a hora em que o teste rode.
  UPDATE public.configuracoes
     SET valor = to_char(((now() AT TIME ZONE 'America/Sao_Paulo') + interval '2 hours')::time, 'HH24:MI')
   WHERE chave = 'HORARIO_SILENCIO_INICIO';
  UPDATE public.configuracoes
     SET valor = to_char(((now() AT TIME ZONE 'America/Sao_Paulo') + interval '3 hours')::time, 'HH24:MI')
   WHERE chave = 'HORARIO_SILENCIO_FIM';
  UPDATE public.configuracoes SET valor = '1' WHERE contaid = 1 AND chave = 'MAX_MENSAGENS_AUTOMATICAS_DIA';

  -- Uma já enviada hoje.
  INSERT INTO public.mensagensfila (contaid, chatid, funcionarioid, tipo, conteudo, status, enviadoem, automatica)
  VALUES (1, 5012, 7512, 'conquista', '{}', 'enviada', now(), true);

  -- Rotina passa do limite: é descartada.
  v_id := public.bot_enfileirar_ex(1, NULL, 5012, 7512, 'inicio_jornada', '{}', NULL, 'lim-rotina', NULL, true, now());
  v_saida := public.bot_fila_pegar(10);
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = v_id;
  PERFORM public.exigir(r.status = 'descartada' AND r.erro = 'limite do dia',
                        'rotina acima do limite diario e descartada');

  -- Aviso passa do limite: fica para o dia seguinte.
  v_id := public.bot_enfileirar_ex(1, NULL, 5012, 7512, 'conquista',
            jsonb_build_object('metodo', 'sendMessage', 'texto', 'x'), NULL, NULL, NULL, false, now());
  v_saida := public.bot_fila_pegar(10);
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = v_id;
  PERFORM public.exigir(r.status = 'pendente' AND r.proximaem > now(),
                        'aviso acima do limite espera o dia seguinte');

  UPDATE public.configuracoes SET valor = '8' WHERE contaid = 1 AND chave = 'MAX_MENSAGENS_AUTOMATICAS_DIA';
  UPDATE public.configuracoes SET valor = '22:00' WHERE chave = 'HORARIO_SILENCIO_INICIO';
  UPDATE public.configuracoes SET valor = '07:00' WHERE chave = 'HORARIO_SILENCIO_FIM';
  DELETE FROM public.mensagensfila WHERE contaid = 1;
END $$;

-- ---------------------------------------------------------------------------
-- Folga: avisos guardados viram um resumo só (7 dias)
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_saida jsonb; v_id bigint; v_texto text;
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;

  -- Aviso para quem está de folga hoje: fica guardado, não é enviado.
  v_id := public.bot_enfileirar_ex(1, NULL, 5013, 7513, 'entrega_aprovada',
            jsonb_build_object('metodo', 'sendMessage', 'titulo', 'T', 'pontos', 3, 'texto', 'x'),
            NULL, NULL, NULL, false, now());
  v_saida := public.bot_fila_pegar(10);
  PERFORM public.exigir((SELECT status FROM public.mensagensfila WHERE filaid = v_id) = 'guardada',
                        'aviso de quem esta de folga fica guardado');

  -- Afastamento de 20 dias: 5 avisos recentes e 2 antigos viram UM resumo.
  INSERT INTO public.mensagensfila (contaid, chatid, funcionarioid, tipo, conteudo, status, criadoem, automatica)
  SELECT 1, 5013, 7513, x.tipo, '{}', 'guardada', now() - x.idade, true
    FROM (VALUES ('entrega_aprovada', interval '2 days'), ('entrega_aprovada', interval '3 days'),
                 ('comunicado_novo',  interval '4 days'), ('conquista', interval '5 days'),
                 ('entrega_recusada', interval '15 days'), ('conquista', interval '20 days')) AS x(tipo, idade);

  v_texto := public.bot_texto_rotina('resumo_ausencia', 1, 7513, NULL)->>'texto';
  PERFORM public.exigir(v_texto LIKE '%Enquanto você esteve fora%' AND v_texto LIKE '%3 entregas aprovadas%'
                          AND v_texto LIKE '%comunicado%',
                        'a volta gera um resumo so, com as contagens');
  PERFORM public.exigir(v_texto NOT LIKE '%recusada%',
                        'o resumo ignora o que ficou guardado ha mais de 7 dias');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.mensagensfila
                                     WHERE contaid = 1 AND funcionarioid = 7513 AND status = 'guardada'),
                        'depois do resumo nada fica guardado');
  PERFORM public.exigir(public.bot_texto_rotina('resumo_ausencia', 1, 7513, NULL) IS NULL,
                        'sem nada guardado, o resumo nao se repete');
  DELETE FROM public.mensagensfila WHERE contaid = 1;
END $$;

-- ---------------------------------------------------------------------------
-- Bot bloqueado pela pessoa
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_id bigint; v_saida jsonb;
BEGIN
  DELETE FROM public.mensagensfila WHERE contaid = 1;
  -- Independente da hora em que o teste roda: a Diana precisa estar DENTRO do
  -- turno para a mensagem sair da fila. O horario fixo dela volta no fim.
  UPDATE public.funcionarios
     SET horarionotificacao = ((now() AT TIME ZONE 'America/Sao_Paulo') - interval '1 hour')::time,
         horariosaida       = ((now() AT TIME ZONE 'America/Sao_Paulo') + interval '1 hour')::time
   WHERE funcionarioid = 7510;
  v_id := public.bot_enfileirar_ex(1, NULL, 5010, 7510, 'conquista',
            jsonb_build_object('metodo', 'sendMessage', 'texto', 'x'), NULL, NULL, NULL, false, now());
  v_saida := public.bot_fila_pegar(10);
  PERFORM public.bot_fila_resultado(v_id, false, NULL, '403 Forbidden: bot was blocked by the user', 0);

  PERFORM public.exigir((SELECT bloqueadoem IS NOT NULL FROM public.telegramvinculos
                          WHERE chatid = 5010 AND ativo), 'bot bloqueado marca o vinculo');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.avisossistema
                                 WHERE contaid = 1 AND tipo = 'telegram_bloqueado' AND lidoem IS NULL),
                        'o master e avisado no sistema quando alguem bloqueia o bot');
  PERFORM public.exigir(public.bot_enfileirar_ex(1, NULL, 5010, 7510, 'conquista', '{}', NULL, NULL, NULL, false, now()) IS NULL,
                        'com o bot bloqueado, nada mais e enfileirado');
  PERFORM public.bot_visto(5010);
  PERFORM public.exigir((SELECT bloqueadoem IS NULL FROM public.telegramvinculos WHERE chatid = 5010 AND ativo),
                        'quando a pessoa volta a usar o bot, o bloqueio some sozinho');
  UPDATE public.funcionarios SET horarionotificacao = '08:00', horariosaida = '17:00'
   WHERE funcionarioid = 7510;
  DELETE FROM public.mensagensfila WHERE contaid = 1;
END $$;

-- ---------------------------------------------------------------------------
-- "O primeiro que clicar": missão e tarefa de folga
-- ---------------------------------------------------------------------------
DO $$
DECLARE r jsonb; v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  -- Missão: o segundo a clicar não leva.
  r := public.bot_pegar_missao(-1002, 5010, 7813);
  PERFORM public.exigir((r->>'ok')::boolean, 'a primeira pessoa pega a missao');
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.tarefasatribuidas
                                 WHERE contaid = 1 AND origematribuicaoid = 7813 AND funcionarioid = 7510
                                   AND tipofrequencia = 'Unica'),
                        'quem pegou a missao ganha a tarefa de hoje (esforco extra)');
  r := public.bot_pegar_missao(-1002, 5011, 7813);
  PERFORM public.exigir(NOT (r->>'ok')::boolean AND r->>'erro' = 'ja_pega', 'a segunda pessoa recebe "ja foi pega"');

  -- Quem não tem o Telegram ligado não pega nada.
  r := public.bot_pegar_missao(-1002, 9999, 7813);
  PERFORM public.exigir(NOT (r->>'ok')::boolean AND r->>'erro' = 'sem_vinculo', 'quem nao tem vinculo nao pega missao');

  -- Tarefa de folga do Fábio: o limite por pessoa é respeitado.
  UPDATE public.configuracoes SET valor = '1' WHERE contaid = 1 AND chave = 'MAX_TAREFAS_FOLGA_POR_PESSOA';
  r := public.bot_pegar_folga(-1002, 5010, 7812);
  PERFORM public.exigir((r->>'ok')::boolean, 'a tarefa de quem esta de folga e pega pelo grupo');
  PERFORM public.exigir((SELECT passadapara FROM public.tarefasdodia
                          WHERE contaid = 1 AND dia = v_hoje AND atribuicaoid = 7812) = 7510,
                        'a lista do dia registra para quem a tarefa foi');
  r := public.bot_pegar_folga(-1002, 5011, 7812);
  PERFORM public.exigir(NOT (r->>'ok')::boolean AND r->>'erro' = 'ja_pega', 'a mesma tarefa nao e pega duas vezes');
  UPDATE public.configuracoes SET valor = '3' WHERE contaid = 1 AND chave = 'MAX_TAREFAS_FOLGA_POR_PESSOA';
END $$;

-- ---------------------------------------------------------------------------
-- Isolamento entre contas
-- ---------------------------------------------------------------------------
SET ROLE authenticated;
SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';   -- master da conta B
DO $$
DECLARE deu_erro boolean; v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.mensagensrotinas;
  PERFORM public.exigir(v_n = 0, 'B nao le o liga/desliga de rotinas de A');
  SELECT count(*) INTO v_n FROM public.missoesaceites;
  PERFORM public.exigir(v_n = 0, 'B nao le as missoes aceitas em A');

  BEGIN PERFORM public.definir_rotina_mensagem(10, 'inicio_jornada', false); deu_erro := false;
  EXCEPTION WHEN OTHERS THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao desliga uma rotina de uma loja de A');

  -- A função existe para B, mas não alcança ninguém de A: 0 pessoas mudadas.
  PERFORM public.exigir(public.definir_horario_equipe(ARRAY[7510], '07:00', '15:00') = 0,
                        'B pede para mudar o horario de alguem de A e nao muda ninguem');
END $$;

RESET ROLE;
SET teste.uid = '';
DO $$
BEGIN
  PERFORM public.exigir((SELECT horarionotificacao FROM public.funcionarios WHERE funcionarioid = 7510) = '08:00',
                        'B nao muda o horario de ninguem de A');
  PERFORM public.exigir((SELECT md5(string_agg(t::text, '' ORDER BY atribuicaoid)) FROM public.tarefasatribuidas t
                          WHERE contaid = 2) = (SELECT atribuicoes FROM b1_b_antes),
                        'nada da conta B foi alterado pelas rotinas de A');
  PERFORM public.exigir((SELECT count(*) FROM public.mensagensfila WHERE contaid = 2) = (SELECT fila_n FROM b1_b_antes),
                        'a fila da conta B continua igual');
END $$;

-- As funções novas do bot não ficam liberadas para o navegador.
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE f text; deu_erro boolean;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.bot_pegar_folga(-1002::bigint, 5010::bigint, 7812)',
                           'public.bot_pegar_missao(-1002::bigint, 5010::bigint, 7813)',
                           'public.bot_visto(5010::bigint)',
                           'public.rotina_mensagens(1, now())',
                           'public.bot_janela(1, 7510, now())',
                           'public.pegar_missao(7813, 7510)'] LOOP
    BEGIN EXECUTE format('SELECT %s', f); deu_erro := false;
    EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
    PERFORM public.exigir(deu_erro, 'usuario logado nao chama ' || split_part(f, '(', 1));
  END LOOP;
END $$;
RESET ROLE;
SET teste.uid = '';

-- ===========================================================================
-- 14. Conferencia estrutural: nenhuma tabela ficou sem RLS ou com USING (true)
-- ===========================================================================

RESET ROLE;

DO $$
DECLARE sem_rls text; liberadas text;
BEGIN
  RAISE NOTICE '14. conferencia estrutural';

  SELECT string_agg(tablename, ', ') INTO sem_rls
  FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity;
  PERFORM public.exigir(sem_rls IS NULL, 'todas as tabelas de public tem RLS ligada');

  SELECT string_agg(tablename || '.' || policyname, ', ') INTO liberadas
  FROM pg_policies
  WHERE schemaname IN ('public', 'storage')
    AND (qual = 'true' OR with_check = 'true');
  PERFORM public.exigir(liberadas IS NULL, 'nenhuma policy liberada com USING (true)');

  -- Policies se somam: uma unica policy que nao filtre por conta abre tudo.
  SELECT string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') INTO liberadas
  FROM pg_policies
  WHERE schemaname IN ('public', 'storage')
    AND coalesce(qual, '') || coalesce(with_check, '') NOT LIKE '%minha_conta%'
    AND coalesce(qual, '') || coalesce(with_check, '') NOT LIKE '%eh_admin_geral%';
  PERFORM public.exigir(liberadas IS NULL, 'toda policy filtra por conta ou e do admin geral');

  -- Uma tabela sem contaid nao teria como ser isolada.
  SELECT string_agg(t.table_name, ', ') INTO liberadas
  FROM information_schema.tables t
  WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
    AND NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'public' AND c.table_name = t.table_name
        AND c.column_name = 'contaid');
  PERFORM public.exigir(liberadas IS NULL, 'toda tabela de public tem coluna contaid');

  -- Toda tabela de nivel loja tem lojaid amarrado a mesma conta.
  SELECT string_agg(conrelid::regclass::text, ', ') INTO liberadas
  FROM information_schema.columns c
  JOIN pg_class k ON k.relname = c.table_name AND k.relnamespace = 'public'::regnamespace
  LEFT JOIN pg_constraint f
    ON f.conrelid = k.oid AND f.contype = 'f'
   AND f.confrelid = 'public.lojas'::regclass AND array_length(f.conkey, 1) = 2
  WHERE c.table_schema = 'public' AND c.column_name = 'lojaid' AND f.oid IS NULL;
  PERFORM public.exigir(liberadas IS NULL, 'todo lojaid aponta para lojas junto com o contaid');

  -- Funcao security definer ignora a RLS. Se qualquer um puder executa-la,
  -- ela precisa conferir por conta propria quem chamou. So as listadas aqui
  -- fazem isso; qualquer outra executavel por anon/authenticated e um furo.
  SELECT string_agg(p.proname, ', ') INTO liberadas
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND p.prorettype <> 'trigger'::regtype
    AND (has_function_privilege('anon', p.oid, 'EXECUTE')
         OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    AND p.proname NOT IN (
      'minha_conta', 'minha_conta_editavel', 'eh_admin_geral',
      'registrar_entrega', 'aprovar_entrega', 'recusar_entrega', 'estornar_entrega',
      'painel_da_loja', 'resumo_das_lojas', 'criar_link_tv', 'revogar_link_tv', 'painel_da_tv',
      'registrar_troca', 'registrar_troca_por_valor', 'concluir_troca', 'cancelar_troca', 'estornar_troca',
      'criar_conquista', 'alterar_configuracao',
      'registrar_feedback', 'anular_feedback', 'registrar_justificativa', 'decidir_justificativa',
      'sou_master', 'tratar_relato', 'abrir_solicitacao', 'mudar_situacao_solicitacao',
      'lancar_venda_do_dia', 'salvar_meta_do_mes',
      'criar_agendamento', 'remarcar_agendamento', 'trocar_responsavel_agendamento', 'alterar_pagamento_agendamento',
      'editar_agendamento', 'marcar_agendamento_realizado', 'reabrir_agendamento', 'cancelar_agendamento',
      'registrar_anexo_agendamento', 'remover_anexo_agendamento', 'pasta_de_agendamento_minha',
      'incluir_destinatarios', 'publicar_comunicado', 'editar_comunicado', 'arquivar_comunicado', 'fora_do_comunicado',
      'registrar_ciencia', 'desfazer_ciencia', 'preparar_envio_documento', 'documento_rh_liberado',
      'registrar_documento_pessoal', 'registrar_ciencia_documento', 'excluir_documento_por_engano',
      'arquivar_documento_pessoal', 'liberar_documento_pessoal', 'iniciar_onboarding', 'marcar_etapa_onboarding',
      'rodar_geracao_hoje', 'passar_tarefa_de_folga', 'refazer_fechamento', 'rotinas_resumo_admin',
      'criar_convite_telegram', 'criar_convite_grupo', 'criar_convite_meu_telegram', 'desligar_telegram', 'marcar_aviso_lido',
      'definir_rotina_mensagem', 'definir_horario_equipe',
      -- Etapa 1.12: falam so do proprio login (meu_acesso) ou exigem master
      -- (publicar_politica_de_uso, situacao_dos_acessos).
      'meu_acesso', 'publicar_politica_de_uso', 'situacao_dos_acessos', 'minha_politica_de_uso'
    );
  PERFORM public.exigir(liberadas IS NULL,
    'nenhuma funcao com poder total fica executavel por quem nao confere o chamador'
    || coalesce(' (sobrou: ' || liberadas || ')', ''));

  -- Nome e tema ficam no user_metadata, que o proprio usuario altera:
  -- nenhuma policy nem funcao pode usar isso para decidir acesso.
  SELECT string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') INTO liberadas
  FROM pg_policies
  WHERE coalesce(qual, '') || coalesce(with_check, '') ~* '(user_meta|raw_user_meta)';
  PERFORM public.exigir(liberadas IS NULL, 'nenhuma policy usa user_metadata' || coalesce(' (sobrou: ' || liberadas || ')', ''));
  SELECT string_agg(p.proname, ', ') INTO liberadas
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'storage') AND p.prosrc ~* '(user_meta|raw_user_meta)';
  PERFORM public.exigir(liberadas IS NULL, 'nenhuma funcao usa user_metadata' || coalesce(' (sobrou: ' || liberadas || ')', ''));

  -- Visitante sem login: so painel_da_tv, e nenhuma tabela.
  SELECT string_agg(p.proname, ', ') INTO liberadas
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname <> 'painel_da_tv';
  PERFORM public.exigir(liberadas IS NULL, 'visitante sem login so consegue chamar painel_da_tv' || coalesce(' (sobrou: ' || liberadas || ')', ''));

  SELECT string_agg(c.relname, ', ') INTO liberadas
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm')
    AND (has_table_privilege('anon', c.oid, 'SELECT') OR has_table_privilege('anon', c.oid, 'INSERT')
      OR has_table_privilege('anon', c.oid, 'UPDATE') OR has_table_privilege('anon', c.oid, 'DELETE'));
  PERFORM public.exigir(liberadas IS NULL, 'visitante sem login nao tem acesso a nenhuma tabela' || coalesce(' (sobrou: ' || liberadas || ')', ''));
END $$;

-- ===========================================================================
-- 21. O saldo so muda pelo livro de movimentos, por qualquer caminho
-- ===========================================================================

RESET ROLE;
CREATE FUNCTION public.teste_burla_saldo() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.funcionarios SET saldopontos = saldopontos + 100 WHERE funcionarioid = 100;
END $$;

DO $$
DECLARE deu_erro boolean; sobra text;
BEGIN
  RAISE NOTICE '21. o saldo so muda pelo livro de movimentos';

  BEGIN UPDATE public.funcionarios SET saldopontos = saldopontos + 1 WHERE funcionarioid = 100; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o dono do banco muda o saldo sem gravar movimento');

  BEGIN UPDATE public.funcionarios SET pontostotal = 999 WHERE funcionarioid = 100; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem o total de pontos');

  BEGIN PERFORM public.teste_burla_saldo(); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem uma funcao com poder total escrita para burlar');

  BEGIN
    PERFORM set_config('gamegb.aplicando_movimento', 'sim', true);
    UPDATE public.funcionarios SET saldopontos = saldopontos + 1 WHERE funcionarioid = 100;
    deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem imitando o aviso do gatilho do livro');

  BEGIN INSERT INTO public.funcionarios (contaid, nomecompleto, saldopontos) VALUES (1, 'Ja rico', 500); deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nem cadastrando alguem ja com saldo');

  BEGIN UPDATE public.movimentospontos SET pontos = 1000 WHERE funcionarioid = 100; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'movimento de pontos nao se altera');

  BEGIN DELETE FROM public.movimentospontos WHERE funcionarioid = 100; deu_erro := false;
  EXCEPTION WHEN restrict_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'movimento de pontos nao se apaga');

  -- A conta de verdade: em todas as contas, saldo e total batem com o livro.
  SELECT string_agg(f.nomecompleto || ' (saldo ' || f.saldopontos || ', livro ' || coalesce(m.soma, 0) || ')', ', ')
    INTO sobra
    FROM public.funcionarios f
    LEFT JOIN (SELECT funcionarioid, sum(pontos) AS soma,
                      sum(pontos) FILTER (WHERE tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')) AS ganhos
                 FROM public.movimentospontos GROUP BY funcionarioid) m USING (funcionarioid)
   WHERE f.saldopontos <> coalesce(m.soma, 0) OR coalesce(f.pontostotal, 0) <> coalesce(m.ganhos, 0);
  PERFORM public.exigir(sobra IS NULL,
    'em todas as contas, saldo e total batem com o livro de movimentos' || coalesce(' (diferente: ' || sobra || ')', ''));
END $$;

DROP FUNCTION public.teste_burla_saldo();


-- ===========================================================================
-- 42. Visoes LOJA e COLABORADOR (Etapa 1.12, parte A)
-- ===========================================================================
RESET ROLE;

DO $$ BEGIN RAISE NOTICE '42. visoes LOJA e COLABORADOR (acesso)'; END $$;

-- Logins novos: um da loja A1 e um do colaborador da conta A; um da conta B.
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
  ('10100000-0000-0000-0000-000000000001', 'loja-a1@lojas.stgame.app',    now()),
  ('10100000-0000-0000-0000-000000000002', 'colab-a@colab.stgame.app',    now()),
  ('10100000-0000-0000-0000-000000000003', 'colab-b@colab.stgame.app',    now());

-- CPF: valido, so numeros, unico por conta. O mesmo CPF pode existir em outra
-- conta (a pessoa pode trabalhar em duas empresas clientes).
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, cpf, ativo)
OVERRIDING SYSTEM VALUE VALUES
  (8100, 1, 'Carla Colaboradora', '529.982.247-25', true),
  (8101, 1, 'Caio Colega',        '11144477735',    true),
  (8200, 2, 'Bia da Conta B',     '52998224725',    true);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (1, 8100, 10), (1, 8101, 10);

DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir((SELECT cpf FROM public.funcionarios WHERE funcionarioid = 8100) = '52998224725',
                        'o CPF e guardado so com numeros');
  PERFORM public.exigir((SELECT cpf FROM public.funcionarios WHERE funcionarioid = 8200) = '52998224725',
                        'o mesmo CPF pode existir em outra conta');

  BEGIN
    UPDATE public.funcionarios SET cpf = '52998224725' WHERE funcionarioid = 8101; deu_erro := false;
  EXCEPTION WHEN unique_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o mesmo CPF nao se repete dentro da conta');

  BEGIN
    UPDATE public.funcionarios SET cpf = '11111111111' WHERE funcionarioid = 8101; deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'CPF com todos os digitos iguais e recusado');

  BEGIN
    UPDATE public.funcionarios SET cpf = '12345678900' WHERE funcionarioid = 8101; deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'CPF com verificador errado e recusado');

  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM information_schema.columns
                                     WHERE table_schema = 'public' AND table_name = 'funcionarios'
                                       AND column_name IN ('senhahash', 'verificadorcpf', 'nivelacesso')),
                        'as colunas mortas do sistema antigo sairam');
END $$;

-- Os acessos entram pelo servidor (contexto confiavel), nunca pelo navegador.
DO $$
BEGIN
  PERFORM public.criar_acesso_loja(1, 10, '10100000-0000-0000-0000-000000000001',
                                   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.criar_acesso_colaborador(1, 8100, '10100000-0000-0000-0000-000000000002',
                                          NULL, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.criar_acesso_colaborador(2, 8200, '10100000-0000-0000-0000-000000000003',
                                          NULL, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
  -- NAO existe senha nem PIN padrao: quem acabou de ganhar acesso nao tem nada
  -- que alguem possa adivinhar.
  PERFORM public.exigir((SELECT senhahashapp IS NULL AND pinhash IS NULL
                           FROM public.funcionarios WHERE funcionarioid = 8100),
                        'acesso novo nasce SEM senha e SEM PIN');
END $$;

-- ---------------------------------------------------------------------------
-- O acesso da LOJA nao le NADA pelo endereco
-- ---------------------------------------------------------------------------
SET ROLE authenticated;
SET teste.uid = '10100000-0000-0000-0000-000000000001';

DO $$
DECLARE deu_erro boolean;
BEGIN
  PERFORM public.exigir(public.minha_conta() IS NULL, 'o acesso da loja nao tem conta para a RLS');
  PERFORM public.exigir((SELECT count(*) FROM public.funcionarios) = 0, 'o acesso da loja nao le a equipe');
  PERFORM public.exigir((SELECT count(*) FROM public.lojas) = 0, 'o acesso da loja nao le nem a propria loja');
  PERFORM public.exigir((SELECT count(*) FROM public.tarefasatribuidas) = 0, 'o acesso da loja nao le tarefas');
  PERFORM public.exigir((SELECT count(*) FROM public.entregas) = 0, 'o acesso da loja nao le entregas');
  PERFORM public.exigir((SELECT count(*) FROM public.movimentospontos) = 0, 'o acesso da loja nao le o livro de pontos');
  PERFORM public.exigir((SELECT count(*) FROM public.documentospessoais) = 0, 'o acesso da loja nao le documento pessoal');
  PERFORM public.exigir((SELECT count(*) FROM public.denunciasanonimas) = 0, 'o acesso da loja nao le o canal confidencial');
  PERFORM public.exigir(NOT public.sou_master(), 'o acesso da loja nao e master');

  BEGIN
    INSERT INTO public.funcionarios (contaid, nomecompleto) VALUES (1, 'Intruso'); deu_erro := false;
  EXCEPTION WHEN others THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o acesso da loja nao grava nada');

  -- Mas sabe quem e, para o app saber para onde levar.
  PERFORM public.exigir(public.meu_acesso()->>'tipo' = 'loja', 'meu_acesso diz que e o acesso da loja');
  PERFORM public.exigir(public.meu_acesso()->>'loja' = 'Loja A1', 'meu_acesso traz a loja certa');

  -- E nao consegue ligar o contexto das visoes por conta propria.
  -- Erro TEM de ser de permissao: com "WHEN others" o teste passaria ate se a
  -- funcao nao existisse.
  BEGIN
    PERFORM public.entrar_na_visao(1, NULL, 10, 'tablet'); deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'quem esta logado nao liga o contexto das visoes');
END $$;

-- ---------------------------------------------------------------------------
-- O acesso do COLABORADOR tambem nao le nada
-- ---------------------------------------------------------------------------
SET teste.uid = '10100000-0000-0000-0000-000000000002';

DO $$
BEGIN
  PERFORM public.exigir(public.minha_conta() IS NULL, 'o colaborador nao tem conta para a RLS');
  PERFORM public.exigir((SELECT count(*) FROM public.funcionarios) = 0, 'o colaborador nao le nem o proprio cadastro');
  PERFORM public.exigir((SELECT count(*) FROM public.entregas) = 0, 'o colaborador nao le entregas pelo endereco');
  PERFORM public.exigir((SELECT count(*) FROM public.contasusuarios) = 0, 'o colaborador nao le a lista de acessos');
  PERFORM public.exigir(public.meu_acesso()->>'tipo' = 'colaborador', 'meu_acesso diz que e colaborador');
  PERFORM public.exigir(public.meu_acesso()->>'nome' = 'Carla Colaboradora', 'meu_acesso traz o nome da pessoa');
  PERFORM public.exigir((public.meu_acesso()->>'semsenha')::boolean, 'comeca sem senha (so entra com o codigo)');
  PERFORM public.exigir((public.meu_acesso()->>'sempin')::boolean, 'comeca sem PIN');
END $$;

-- O colaborador da conta B nao enxerga nada da conta A (nem o contrario).
SET teste.uid = '10100000-0000-0000-0000-000000000003';
DO $$
BEGIN
  PERFORM public.exigir(public.meu_acesso()->>'nome' = 'Bia da Conta B', 'cada colaborador so ve o proprio nome');
  PERFORM public.exigir((SELECT count(*) FROM public.funcionarios) = 0, 'colaborador da conta B nao le a conta A');
END $$;

RESET ROLE;

-- ---------------------------------------------------------------------------
-- PIN: unico na conta, e o erro nao entrega ninguem
-- ---------------------------------------------------------------------------
DO $$
DECLARE deu_erro boolean; v_msg text;
BEGIN
  PERFORM public.definir_pin(1, 8100, repeat('1', 64), false);
  PERFORM public.exigir((SELECT pinhash FROM public.funcionarios WHERE funcionarioid = 8100) = repeat('1', 64),
                        'a pessoa escolhe o proprio PIN');

  BEGIN
    PERFORM public.definir_pin(1, 8101, repeat('1', 64), false); deu_erro := false;
  EXCEPTION WHEN unique_violation THEN deu_erro := true; v_msg := SQLERRM; END;
  PERFORM public.exigir(deu_erro, 'PIN repetido na mesma conta e recusado');
  PERFORM public.exigir(v_msg = 'Escolha outro número.', 'o erro do PIN repetido nao diz de quem e o numero');

  -- O mesmo PIN pode existir em outra conta.
  PERFORM public.definir_pin(2, 8200, repeat('1', 64), false);
  PERFORM public.exigir((SELECT pinhash FROM public.funcionarios WHERE funcionarioid = 8200) = repeat('1', 64),
                        'o mesmo PIN pode existir em outra conta');

  -- Redefinir acesso: apaga senha e PIN, com registro de quem e quando.
  PERFORM public.definir_senha_app(1, 8100, 'pbkdf2$1$aa$bb');
  PERFORM public.redefinir_acesso(1, 8100, NULL, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.exigir((SELECT senhahashapp IS NULL AND pinhash IS NULL AND acessoredefinidoem IS NOT NULL
                           AND acessoredefinidopor = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                           FROM public.funcionarios WHERE funcionarioid = 8100),
                        'redefinir acesso apaga senha e PIN, com registro de quem e quando');
END $$;

-- ---------------------------------------------------------------------------
-- Trava: 5 erros seguidos
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  DELETE FROM public.tentativasacesso;
  -- Conferir e registrar sao a MESMA operacao (tentativa_abrir): e isso que faz
  -- a trava valer quando chegam varios pedidos juntos.
  FOR i IN 1..5 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'pin', repeat('c', 64), 'tablet-1'), false);
  END LOOP;
  PERFORM public.exigir(public.tentativa_abrir(1, 'pin', repeat('c', 64), 'tablet-1') IS NULL,
                        'cinco erros seguidos travam a janela');
  -- Outra pessoa (outra chave): nao esta travada.
  PERFORM public.exigir(public.tentativa_abrir(1, 'pin', repeat('z', 64), 'tablet-2') IS NOT NULL,
                        'a trava nao pega a loja inteira: outra pessoa continua entrando');
  PERFORM public.exigir(public.tentativa_abrir(1, 'pin', repeat('c', 64), 'tablet-2') IS NULL,
                        'quem errou 5 vezes fica travado mesmo trocando de tablet');
  PERFORM public.exigir(public.tentativa_abrir(2, 'pin', repeat('c', 64), 'tablet-1') IS NOT NULL,
                        'a trava de uma conta nao trava outra');

  -- Um acerto zera a conta de erros.
  PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', repeat('d', 64), 'login-1'), true);
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', repeat('d', 64), 'login-1') IS NOT NULL,
                        'depois de acertar, a contagem de erros zera');

  -- Senha: conta pelo CPF, para nao bastar trocar de aparelho.
  DELETE FROM public.tentativasacesso;
  FOR i IN 1..5 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', repeat('e', 64), 'login-' || i), false);
  END LOOP;
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', repeat('e', 64), 'login-9') IS NULL,
                        'cinco erros no mesmo CPF travam, mesmo trocando de aparelho');
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', repeat('f', 64), 'login-9') IS NOT NULL,
                        'a trava de um CPF nao trava o CPF do colega');

  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM information_schema.columns
                                     WHERE table_schema = 'public' AND table_name = 'tentativasacesso'
                                       AND column_name IN ('pin', 'senha', 'valor', 'digitado')),
                        'o registro de tentativas nao tem onde guardar o que foi digitado');
  -- A funcao antiga (conferir sem registrar) nao existe mais: era o furo.
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                     WHERE n.nspname = 'public' AND p.proname = 'acesso_travado'),
                        'nao existe mais conferir a trava sem registrar a tentativa');
  DELETE FROM public.tentativasacesso;
END $$;

-- ---------------------------------------------------------------------------
-- Desligado na hora: pessoa inativa e loja desativada
-- ---------------------------------------------------------------------------
UPDATE public.funcionarios SET ativo = false WHERE funcionarioid = 8100;
SET ROLE authenticated;
SET teste.uid = '10100000-0000-0000-0000-000000000002';
DO $$ BEGIN
  PERFORM public.exigir(public.meu_acesso()->>'tipo' = 'desligado',
                        'colaborador desativado perde o acesso na hora');
END $$;
RESET ROLE;
UPDATE public.funcionarios SET ativo = true WHERE funcionarioid = 8100;

UPDATE public.lojas SET ativa = false WHERE lojaid = 10;
SET ROLE authenticated;
SET teste.uid = '10100000-0000-0000-0000-000000000001';
DO $$ BEGIN
  PERFORM public.exigir(public.meu_acesso()->>'tipo' = 'desligado',
                        'acesso de loja desativada para na hora');
END $$;
RESET ROLE;
UPDATE public.lojas SET ativa = true WHERE lojaid = 10;

-- ---------------------------------------------------------------------------
-- Politica de uso: versionada, com ciencia por versao
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE politica_ids (versao integer, documentoid integer, assinaturaid integer);
GRANT ALL ON politica_ids TO authenticated;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE v_doc integer; v_assin integer;
BEGIN
  v_doc := public.publicar_politica_de_uso(repeat('Regras de uso do sistema. ', 20));
  PERFORM public.exigir((SELECT pontosporciencia FROM public.documentos WHERE documentoid = v_doc) = 0,
                        'a politica e publicada com 0 ponto de ciencia');
  SELECT assinaturaid INTO v_assin FROM public.documentosassinaturas
   WHERE documentoid = v_doc AND funcionarioid = 8100;
  INSERT INTO politica_ids VALUES (1, v_doc, v_assin);
END $$;
RESET ROLE;

DO $$
DECLARE v_doc integer; v_assin integer;
BEGIN
  SELECT documentoid, assinaturaid INTO v_doc, v_assin FROM politica_ids WHERE versao = 1;
  PERFORM public.exigir(v_assin IS NOT NULL, 'a politica chega a quem trabalha na conta');
  PERFORM public.exigir(public.politica_pendente(1, 8100), 'quem nao deu ciencia fica pendente');
END $$;

SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE v_assin integer; v_doc2 integer;
BEGIN
  SELECT assinaturaid INTO v_assin FROM politica_ids WHERE versao = 1;
  PERFORM public.registrar_ciencia(v_assin);
  v_doc2 := public.publicar_politica_de_uso(repeat('Regras novas do sistema. ', 20));
  INSERT INTO politica_ids VALUES (2, v_doc2, NULL);
END $$;
RESET ROLE;

DO $$
DECLARE v_doc integer; v_doc2 integer; v_assin integer;
BEGIN
  SELECT documentoid, assinaturaid INTO v_doc, v_assin FROM politica_ids WHERE versao = 1;
  SELECT documentoid INTO v_doc2 FROM politica_ids WHERE versao = 2;
  PERFORM public.exigir(v_doc2 <> v_doc, 'cada versao da politica e um comunicado novo');
  PERFORM public.exigir((SELECT status FROM public.documentos WHERE documentoid = v_doc) = 'Arquivado',
                        'a versao anterior fica arquivada');
  PERFORM public.exigir((SELECT statusassinatura FROM public.documentosassinaturas WHERE assinaturaid = v_assin) = 'Ciente',
                        'a ciencia antiga continua guardada na versao antiga');
  PERFORM public.exigir(public.politica_documento(1) = v_doc2, 'a versao em vigor e a nova');
  PERFORM public.exigir(public.politica_pendente(1, 8100), 'a versao nova volta a pedir ciencia');
END $$;

DROP TABLE politica_ids;

-- ---------------------------------------------------------------------------
-- Nada disso fica liberado para o navegador
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.entrar_na_visao(integer, integer, integer, text)',
    'public.criar_acesso_loja(integer, integer, uuid, uuid)',
    'public.criar_acesso_colaborador(integer, integer, uuid, text, uuid)',
    'public.definir_pin(integer, integer, text, boolean)',
    'public.redefinir_acesso(integer, integer, text, uuid)',
    'public.marcar_senha_trocada(integer, integer)',
    'public.tentativa_abrir(integer, text, text, text)',
    'public.tentativa_fechar(bigint, boolean)',
    'public.politica_pendente(integer, integer)',
    'public.politica_documento(integer)',
    'public.loja_da_visao()'
  ] LOOP
    PERFORM public.exigir(NOT has_function_privilege('authenticated', f, 'EXECUTE')
                          AND NOT has_function_privilege('anon', f, 'EXECUTE'),
                          'funcao do acesso nao liberada para o navegador: ' || f);
  END LOOP;
  PERFORM public.exigir(NOT has_table_privilege('authenticated', 'public.tentativasacesso', 'SELECT')
                        AND NOT has_table_privilege('anon', 'public.tentativasacesso', 'SELECT'),
                        'ninguem le o registro de tentativas pelo navegador');
END $$;


-- ===========================================================================
-- 43. Consertos da revisao adversarial (Etapa 1.12, parte A)
-- ===========================================================================
RESET ROLE;
DO $$ BEGIN RAISE NOTICE '43. consertos da revisao adversarial'; END $$;

-- ---------------------------------------------------------------------------
-- Nao existe senha padrao: so se entra com o codigo de primeiro acesso
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_pessoa jsonb; v_usou jsonb; deu_erro boolean;
BEGIN
  -- Quem tem acesso mas nunca entrou nao tem senha nenhuma guardada.
  v_pessoa := public.senha_app_de(1, '52998224725');
  PERFORM public.exigir(v_pessoa IS NOT NULL, 'o servidor acha a pessoa pelo CPF');
  PERFORM public.exigir(v_pessoa->>'senhahash' IS NULL,
                        'sem senha guardada: nao existe senha padrao para adivinhar');

  -- Codigo de primeiro acesso: uso unico.
  PERFORM public.criar_codigo_acesso(1, 8100, repeat('c', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  v_usou := public.usar_codigo_acesso(1, '52998224725', repeat('c', 64));
  PERFORM public.exigir((v_usou->>'funcionarioid')::integer = 8100, 'o codigo certo abre a porta uma vez');
  PERFORM public.exigir(public.usar_codigo_acesso(1, '52998224725', repeat('c', 64)) IS NULL,
                        'o mesmo codigo nao serve duas vezes');

  -- Codigo de outra pessoa, CPF trocado: nao serve.
  PERFORM public.criar_codigo_acesso(1, 8101, repeat('d', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.exigir(public.usar_codigo_acesso(1, '52998224725', repeat('d', 64)) IS NULL,
                        'codigo de um nao entra no CPF de outro');

  -- Codigo vencido nao serve.
  PERFORM public.criar_codigo_acesso(1, 8101, repeat('e', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  UPDATE public.codigosacesso SET expiraem = now() - interval '1 day' WHERE codigohash = repeat('e', 64);
  PERFORM public.exigir(public.usar_codigo_acesso(1, '11144477735', repeat('e', 64)) IS NULL,
                        'codigo vencido nao serve');

  -- Gerar outro cancela o anterior.
  PERFORM public.criar_codigo_acesso(1, 8101, repeat('f', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.criar_codigo_acesso(1, 8101, repeat('g', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.exigir(public.usar_codigo_acesso(1, '11144477735', repeat('f', 64)) IS NULL,
                        'gerar um codigo novo cancela o anterior');
  PERFORM public.exigir(public.usar_codigo_acesso(1, '11144477735', repeat('g', 64)) IS NOT NULL,
                        'o codigo novo funciona');

  -- Codigo da conta A nao vale na conta B.
  PERFORM public.criar_codigo_acesso(1, 8101, repeat('h', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  PERFORM public.exigir(public.usar_codigo_acesso(2, '11144477735', repeat('h', 64)) IS NULL,
                        'codigo de uma conta nao vale em outra');

  -- Ninguem gera codigo para pessoa de outra conta.
  BEGIN
    PERFORM public.criar_codigo_acesso(2, 8101, repeat('i', 64), 7, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    deu_erro := false;
  EXCEPTION WHEN no_data_found THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'nao se gera codigo para pessoa de outra conta');
END $$;

-- ---------------------------------------------------------------------------
-- O adivinhador de PIN morre no teto do dia
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_chave text := repeat('p', 64);
BEGIN
  DELETE FROM public.tentativasacesso;
  -- O adivinhador de PIN ACERTA quase sempre (o numero livre e aceito), entao o
  -- teto conta TODA tentativa, nao so erro. Era esse o furo: contando so erro,
  -- 500 tentativas passavam e o atacante descobria o PIN dos colegas.
  FOR i IN 1..29 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'pin', v_chave, 'origem-' || i), true);
  END LOOP;
  PERFORM public.exigir(public.tentativa_abrir(1, 'pin', v_chave, 'origem-nova') IS NOT NULL,
                        'ate 30 tentativas de PIN no dia ainda passam');
  PERFORM public.exigir(public.tentativa_abrir(1, 'pin', v_chave, 'origem-nova2') IS NULL,
                        'o teto do dia trava o adivinhador de PIN mesmo quando ele ACERTA');
  PERFORM public.exigir(public.tentativa_abrir(1, 'pin', repeat('q', 64), 'origem-nova') IS NOT NULL,
                        'o teto e por pessoa: nao trava o resto da equipe');

  -- E o teto NAO vale para o login: senao qualquer um travaria o dono da conta
  -- por um dia inteiro, so errando o e-mail dele 50 vezes.
  DELETE FROM public.tentativasacesso;
  INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso, em)
  SELECT 1, 'senha', repeat('m', 64), 'origem-' || g, false, now() - interval '30 minutes'
    FROM generate_series(1, 60) g;
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', repeat('m', 64), 'origem-nova') IS NOT NULL,
                        'erro antigo nao trava o login do dono: a janela e de 15 minutos, nao de um dia');
  DELETE FROM public.tentativasacesso;
END $$;

-- ---------------------------------------------------------------------------
-- O tablet da loja nao pode ser derrubado por e-mail (decisao de 23/09/2026)
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_chave text := repeat('w', 64);
BEGIN
  DELETE FROM public.tentativasacesso;
  -- Um estranho erra 5 vezes o e-mail do tablet, de outro lugar.
  FOR i IN 1..5 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'tablet', v_chave, 'atacante'), false);
  END LOOP;
  PERFORM public.exigir(public.tentativa_abrir(1, 'tablet', v_chave, 'atacante') IS NULL,
                        'o atacante e barrado pela origem dele');
  -- ...e o tablet da loja continua entrando normalmente.
  PERFORM public.exigir(public.tentativa_abrir(1, 'tablet', v_chave, 'ip-da-loja') IS NOT NULL,
                        'o tablet continua entrando: ninguem derruba o balcao errando o e-mail dele');

  -- Mas o gestor e o colaborador continuam com a trava por chave (senha
  -- escolhida por pessoa, que da para adivinhar).
  DELETE FROM public.tentativasacesso;
  FOR i IN 1..5 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', v_chave, 'atacante'), false);
  END LOOP;
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', v_chave, 'outro-lugar') IS NULL,
                        'para senha de pessoa, a trava por chave continua valendo');
  DELETE FROM public.tentativasacesso;
END $$;

-- Login por e-mail: quem nao tem papel nenhum nao entra (e nao vira "admin").
DO $$
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at)
  VALUES ('10100000-0000-0000-0000-000000000099', 'orfao@exemplo.com', now());
  PERFORM public.exigir(public.acesso_por_email('orfao@exemplo.com') IS NULL,
                        'login sem vinculo nenhum nao entra pela porta do e-mail');
  DELETE FROM auth.users WHERE id = '10100000-0000-0000-0000-000000000099';
END $$;

-- ---------------------------------------------------------------------------
-- Ninguem tranca a conta de outro para sempre (defeito que o conserto anterior
-- tinha criado: 5 tentativas de um estranho deixavam o dono de fora)
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_chave text := repeat('v', 64);
BEGIN
  DELETE FROM public.tentativasacesso;
  -- Um estranho erra 5 vezes o e-mail do dono.
  FOR i IN 1..5 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', v_chave, 'atacante'), false);
  END LOOP;
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', v_chave, 'atacante') IS NULL,
                        'depois de 5 erros o atacante e barrado');

  -- A janela e curta: 16 minutos depois, o dono entra.
  UPDATE public.tentativasacesso SET em = em - interval '16 minutes' WHERE chave = v_chave;
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', v_chave, 'dono') IS NOT NULL,
                        'passada a janela de 15 minutos, o dono entra de novo');

  -- E um acerto zera tudo na hora.
  PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', v_chave, 'dono'), true);
  FOR i IN 1..3 LOOP
    PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', v_chave, 'atacante2'), false);
  END LOOP;
  PERFORM public.tentativa_fechar(public.tentativa_abrir(1, 'senha', v_chave, 'dono'), true);
  PERFORM public.exigir(public.tentativa_abrir(1, 'senha', v_chave, 'dono') IS NOT NULL,
                        'depois de um acerto, os erros anteriores nao contam mais');
  DELETE FROM public.tentativasacesso;
END $$;

-- ---------------------------------------------------------------------------
-- O login por e-mail (gestor, admin e tablet) confere papel, pessoa e loja
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb;
BEGIN
  v := public.acesso_por_email('master.a@exemplo.com');
  PERFORM public.exigir(v->>'papel' = 'master', 'o master entra pela porta do e-mail');
  v := public.acesso_por_email('wisley_anderson@hotmail.com');
  PERFORM public.exigir(v->>'papel' = 'admin', 'o administrador geral tambem');
  v := public.acesso_por_email('loja-a1@lojas.stgame.app');
  PERFORM public.exigir(v->>'papel' = 'loja', 'o tablet da loja tambem');

  -- Colaborador NAO entra por esta porta (a dele e por CPF, com as regras dela).
  PERFORM public.exigir(public.acesso_por_email('colab-a@colab.stgame.app') IS NULL,
                        'colaborador nao entra pela porta do e-mail');

  -- Loja desativada perde o acesso no LOGIN, nao so depois.
  -- (A senha guardada TEM de existir antes, senao o teste passaria sozinho.)
  INSERT INTO public.senhasgestor (userid, contaid, senhahashapp)
  VALUES ('10100000-0000-0000-0000-000000000001', 1, 'pbkdf2$1$aa$bb')
  ON CONFLICT (userid) DO UPDATE SET senhahashapp = excluded.senhahashapp;
  PERFORM public.exigir(EXISTS (SELECT 1 FROM public.senhasgestor
                                 WHERE userid = '10100000-0000-0000-0000-000000000001'),
                        'o tablet tem senha guardada antes de a loja ser desativada');
  UPDATE public.lojas SET ativa = false WHERE lojaid = 10;
  PERFORM public.exigir(public.acesso_por_email('loja-a1@lojas.stgame.app') IS NULL,
                        'tablet de loja desativada nao entra');
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM public.senhasgestor s
                                     JOIN public.contasusuarios cu ON cu.userid = s.userid
                                    WHERE cu.lojaid = 10),
                        'desativar a loja apaga a senha guardada do tablet');
  UPDATE public.lojas SET ativa = true WHERE lojaid = 10;

  -- E-mail que nao existe nao devolve nada.
  PERFORM public.exigir(public.acesso_por_email('ninguem@exemplo.com') IS NULL,
                        'e-mail desconhecido nao devolve nada');
END $$;

-- ---------------------------------------------------------------------------
-- Desativar apaga senha e PIN e cancela o codigo pendente
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM public.definir_senha_app(1, 8100, 'pbkdf2$1$aa$bb');
  PERFORM public.definir_pin(1, 8100, repeat('7', 64), false);
  PERFORM public.criar_codigo_acesso(1, 8100, repeat('j', 64), 7, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

  -- Como AUTHENTICATED (o papel das telas): e assim que o gatilho roda de
  -- verdade. Antes o teste fazia isto como dono do banco e escondia o defeito.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('teste.uid', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
  UPDATE public.funcionarios SET ativo = false WHERE funcionarioid = 8100;
  RESET ROLE;

  PERFORM public.exigir((SELECT senhahashapp IS NULL AND pinhash IS NULL
                           FROM public.funcionarios WHERE funcionarioid = 8100),
                        'desativar a pessoa apaga a senha e o PIN dela');
  PERFORM public.exigir((SELECT canceladoem IS NOT NULL FROM public.codigosacesso WHERE codigohash = repeat('j', 64)),
                        'desativar a pessoa cancela o codigo pendente');
  PERFORM public.exigir(public.senha_app_de(1, '52998224725') IS NULL,
                        'pessoa desativada nao e achada pelo login');
  PERFORM public.exigir(public.usar_codigo_acesso(1, '52998224725', repeat('j', 64)) IS NULL,
                        'codigo de pessoa desativada nao serve');

  UPDATE public.funcionarios SET ativo = true WHERE funcionarioid = 8100;
END $$;

-- ---------------------------------------------------------------------------
-- Trocar o CPF de quem tem acesso so pelo caminho certo
-- ---------------------------------------------------------------------------
SET ROLE authenticated;
SET teste.uid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
DO $$
DECLARE deu_erro boolean;
BEGIN
  BEGIN
    UPDATE public.funcionarios SET cpf = '39053344705' WHERE funcionarioid = 8100;
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'o master nao troca sozinho o CPF de quem ja entra no app');
  PERFORM public.exigir((SELECT cpf FROM public.funcionarios WHERE funcionarioid = 8100) = '52998224725',
                        'o CPF continua o mesmo depois da recusa');
END $$;
RESET ROLE;

DO $$
BEGIN
  PERFORM public.trocar_cpf(1, 8100, '39053344705');
  PERFORM public.exigir((SELECT cpf FROM public.funcionarios WHERE funcionarioid = 8100) = '39053344705',
                        'pelo caminho certo (servidor), o CPF troca');
  PERFORM public.trocar_cpf(1, 8100, '52998224725');
END $$;

-- ---------------------------------------------------------------------------
-- Nem o master le os segredos, e nada disso e do navegador
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  PERFORM public.exigir(NOT has_column_privilege('authenticated', 'public.funcionarios', 'pinhash', 'SELECT'),
                        'ninguem le a coluna do PIN pelo navegador, nem o master');
  PERFORM public.exigir(NOT has_column_privilege('authenticated', 'public.funcionarios', 'senhahashapp', 'SELECT'),
                        'ninguem le a coluna da senha pelo navegador, nem o master');
  PERFORM public.exigir(has_column_privilege('authenticated', 'public.funcionarios', 'nomecompleto', 'SELECT'),
                        'o resto da equipe continua visivel para o master');
  PERFORM public.exigir(NOT has_table_privilege('authenticated', 'public.codigosacesso', 'SELECT')
                        AND NOT has_table_privilege('anon', 'public.codigosacesso', 'SELECT'),
                        'ninguem le os codigos de acesso pelo navegador');

  FOREACH f IN ARRAY ARRAY[
    'public.criar_codigo_acesso(integer, integer, text, integer, uuid)',
    'public.usar_codigo_acesso(integer, text, text)',
    'public.senha_app_de(integer, text)',
    'public.definir_senha_app(integer, integer, text)',
    'public.trocar_cpf(integer, integer, text)',
    'public.conta_do_codigo(text)'
  ] LOOP
    PERFORM public.exigir(NOT has_function_privilege('authenticated', f, 'EXECUTE')
                          AND NOT has_function_privilege('anon', f, 'EXECUTE'),
                          'funcao do acesso nao liberada para o navegador: ' || f);
  END LOOP;

  -- E o contrario tambem: estas PRECISAM estar liberadas, ou a tela quebra.
  FOREACH f IN ARRAY ARRAY[
    'public.meu_acesso()',
    'public.situacao_dos_acessos()',
    'public.minha_politica_de_uso()',
    'public.publicar_politica_de_uso(text)'
  ] LOOP
    PERFORM public.exigir(has_function_privilege('authenticated', f, 'EXECUTE'),
                          'funcao que a tela usa continua liberada: ' || f);
  END LOOP;

  -- O endereco publico que devolvia o nome da empresa saiu de vez.
  PERFORM public.exigir(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                     WHERE n.nspname = 'public' AND p.proname = 'conta_por_codigo'),
                        'o endereco que dizia o nome da empresa nao existe mais');
END $$;

-- Codigo de empresa novo nao e adivinhavel a partir do nome.
DO $$
DECLARE v_codigo text;
BEGIN
  INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
  VALUES (9001, 'Padaria Teste', 'padaria@exemplo.com', 1)
  RETURNING codigo INTO v_codigo;
  PERFORM public.exigir(v_codigo LIKE 'padariateste-%' AND length(v_codigo) > 15,
                        'o codigo da empresa nova tem parte sorteada (nao da para enumerar clientes)');
  DELETE FROM public.configuracoes WHERE contaid = 9001;
  DELETE FROM public.contas WHERE contaid = 9001;
END $$;


-- ===========================================================================
-- 44. CONTRATO: o servidor so chama funcao que existe, e os logins de quem
--     manda na conta continuam funcionando.
--     (Motivo: o admin geral ficou sem entrar porque o banco nao tinha
--     recebido as migracoes, e nada avisava.)
-- ===========================================================================
RESET ROLE;
DO $$ BEGIN RAISE NOTICE '44. contrato servidor-banco e login de quem manda'; END $$;

DO $$
DECLARE f text; v_faltando text[] := ARRAY[]::text[];
BEGIN
  -- Toda funcao que as funcoes de servidor chamam por RPC. Se uma sumir numa
  -- migracao futura, o teste falha aqui, e nao no ar.
  FOREACH f IN ARRAY ARRAY[
    'tentativa_abrir', 'tentativa_fechar', 'acesso_por_email', 'definir_senha_gestor',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'publicar_politica_de_uso', 'sou_master', 'minha_conta',
    'eh_admin_geral', 'diagnostico_do_sistema'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public' AND p.proname = f) THEN
      v_faltando := v_faltando || f;
    END IF;
  END LOOP;
  PERFORM public.exigir(cardinality(v_faltando) = 0,
    'toda funcao que o servidor chama existe no banco' ||
    coalesce(' (faltando: ' || array_to_string(v_faltando, ', ') || ')', ''));
END $$;

-- A chave de servidor precisa poder executar o que o servidor chama.
DO $$
DECLARE f text; v_sem text[] := ARRAY[]::text[];
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.tentativa_abrir(integer, text, text, text)',
    'public.tentativa_fechar(bigint, boolean)',
    'public.acesso_por_email(text)',
    'public.definir_senha_gestor(uuid, integer, text)',
    'public.senha_app_de(integer, text)',
    'public.conta_do_codigo(text)',
    'public.usar_codigo_acesso(integer, text, text)',
    'public.diagnostico_do_sistema()'
  ] LOOP
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      v_sem := v_sem || f;
    END IF;
  END LOOP;
  PERFORM public.exigir(cardinality(v_sem) = 0,
    'a chave de servidor executa tudo o que precisa' ||
    coalesce(' (sem permissao: ' || array_to_string(v_sem, ', ') || ')', ''));
END $$;

-- O caminho do login do ADMIN GERAL e do MASTER, ponta a ponta no banco.
DO $$
DECLARE v jsonb; v_id bigint;
BEGIN
  DELETE FROM public.tentativasacesso;

  -- Administrador geral: nao pertence a conta nenhuma, e mesmo assim entra.
  v := public.acesso_por_email('wisley_anderson@hotmail.com');
  PERFORM public.exigir(v IS NOT NULL, 'o administrador geral e encontrado pelo e-mail');
  PERFORM public.exigir(v->>'papel' = 'admin', 'e reconhecido como administrador geral');
  PERFORM public.exigir((v->>'userid') = 'cccccccc-cccc-cccc-cccc-cccccccccccc',
                        'com o login certo');
  v_id := public.tentativa_abrir(NULL, 'senha', repeat('a', 64), 'ip-do-admin');
  PERFORM public.exigir(v_id IS NOT NULL, 'a trava deixa o administrador tentar entrar');
  PERFORM public.tentativa_fechar(v_id, true);

  -- Master da conta A.
  v := public.acesso_por_email('master.a@exemplo.com');
  PERFORM public.exigir(v->>'papel' = 'master', 'o master e encontrado e reconhecido');
  PERFORM public.exigir((v->>'contaid')::integer = 1, 'com a conta certa');

  -- Guardar e reconhecer o resumo da senha do gestor.
  PERFORM public.definir_senha_gestor('cccccccc-cccc-cccc-cccc-cccccccccccc', NULL, 'pbkdf2$210000$aa$bb');
  v := public.acesso_por_email('wisley_anderson@hotmail.com');
  PERFORM public.exigir(v->>'senhahash' = 'pbkdf2$210000$aa$bb',
                        'a senha guardada do administrador volta para o servidor conferir');
  DELETE FROM public.senhasgestor WHERE userid = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  DELETE FROM public.tentativasacesso;
END $$;

-- O diagnostico enxerga o que falta (e nao devolve segredo nenhum).
DO $$
DECLARE d jsonb;
BEGIN
  d := public.diagnostico_do_sistema();
  PERFORM public.exigir(jsonb_array_length(d->'funcoesfaltando') = 0,
                        'o diagnostico nao encontra funcao faltando num banco atualizado');
  PERFORM public.exigir(jsonb_array_length(d->'tabelasfaltando') = 0,
                        'nem tabela faltando');
  PERFORM public.exigir(NOT (d::text ILIKE '%pbkdf2%') AND NOT (d::text ILIKE '%senhahash%'),
                        'o diagnostico nao devolve nenhum segredo');
END $$;

DO $$ BEGIN RAISE NOTICE '=== TESTE DE ISOLAMENTO: TUDO PASSOU ==='; END $$;
