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
INSERT INTO public.entregas (tarefaid, funcionarioid, lojaid) VALUES (1000, 100, 10);
INSERT INTO public.grupos (grupoid, nomegrupo, lojaid) OVERRIDING SYSTEM VALUE VALUES (200, 'Cozinha', 10);
INSERT INTO public.configuracoes (chave, valor) VALUES ('TAXA_CONVERSAO_PONTO_REAL', '0.03');
INSERT INTO storage.objects (bucket_id, name) VALUES ('entregas', '1/10/foto-a.jpg');

SET teste.uid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.lojas (lojaid, nome) OVERRIDING SYSTEM VALUE VALUES (20, 'Loja B1');
INSERT INTO public.funcionarios (funcionarioid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES (200, 'Bruno da conta B');
INSERT INTO public.tarefas (tarefaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (2000, 'Tarefa B', 7);
INSERT INTO public.funcionarioslojas (funcionarioid, lojaid) VALUES (200, 20);
INSERT INTO public.tarefaslojas (tarefaid, lojaid) VALUES (2000, 20);
INSERT INTO public.tarefasatribuidas (atribuicaoid, tarefaid, funcionarioid, lojaid) OVERRIDING SYSTEM VALUE VALUES (6000, 2000, 200, 20);
INSERT INTO public.entregas (tarefaid, funcionarioid, lojaid) VALUES (2000, 200, 20);
INSERT INTO public.grupos (grupoid, nomegrupo, lojaid) OVERRIDING SYSTEM VALUE VALUES (300, 'Cozinha', 20);
INSERT INTO public.configuracoes (chave, valor) VALUES ('TAXA_CONVERSAO_PONTO_REAL', '0.05');
INSERT INTO storage.objects (bucket_id, name) VALUES ('entregas', '2/20/foto-b.jpg');

RESET ROLE;
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

  DELETE FROM public.entregas WHERE lojaid = 20;
  GET DIAGNOSTICS afetadas = ROW_COUNT;
  PERFORM public.exigir(afetadas = 0, 'A nao apaga entrega de B');

  DELETE FROM public.configuracoes WHERE chave = 'TAXA_CONVERSAO_PONTO_REAL' AND valor = '0.05';
  GET DIAGNOSTICS afetadas = ROW_COUNT;
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
DECLARE deu_erro boolean;
BEGIN
  RAISE NOTICE '9. limite de lojas da conta';
  BEGIN
    INSERT INTO public.lojas (nome) VALUES ('Loja A3 (acima do limite)');
    deu_erro := false;
  EXCEPTION WHEN check_violation THEN
    deu_erro := true;
  END;
  PERFORM public.exigir(deu_erro, 'conta com limite 2 nao cria a terceira loja ativa');
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
  PERFORM public.exigir(deu_erro, 'conta suspensa nao cadastra');
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
  PERFORM public.exigir((SELECT count(*) FROM public.lojas) = 3,   'o admin conta as lojas de todos');
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
END $$;

DO $$ BEGIN RAISE NOTICE '=== TESTE DE ISOLAMENTO: TUDO PASSOU ==='; END $$;
