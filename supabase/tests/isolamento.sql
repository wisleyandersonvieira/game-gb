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
      'criar_conquista', 'alterar_configuracao'
    );
  PERFORM public.exigir(liberadas IS NULL,
    'nenhuma funcao com poder total fica executavel por quem nao confere o chamador'
    || coalesce(' (sobrou: ' || liberadas || ')', ''));

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
                      sum(pontos) FILTER (WHERE tipo IN ('aprovacao', 'estorno_entrega', 'bonus')) AS ganhos
                 FROM public.movimentospontos GROUP BY funcionarioid) m USING (funcionarioid)
   WHERE f.saldopontos <> coalesce(m.soma, 0) OR coalesce(f.pontostotal, 0) <> coalesce(m.ganhos, 0);
  PERFORM public.exigir(sobra IS NULL,
    'em todas as contas, saldo e total batem com o livro de movimentos' || coalesce(' (diferente: ' || sobra || ')', ''));
END $$;

DROP FUNCTION public.teste_burla_saldo();

DO $$ BEGIN RAISE NOTICE '=== TESTE DE ISOLAMENTO: TUDO PASSOU ==='; END $$;
