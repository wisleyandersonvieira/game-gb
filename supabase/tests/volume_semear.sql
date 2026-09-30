-- =========================================================================
-- Volume de LOJA REAL, 12 MESES de uso, para o teste de tempo das telas
-- (volume_medir.sql). Pedido do Wisley (30/09/2026): o teste tem de pegar o
-- CRESCIMENTO com os dias, não só a piora do código; todo cliente chega a um
-- ano de uso.
--
-- Uma conta sintética (900) com duas lojas ativas e uma inativa, 40 pessoas,
-- 80 tarefas, 700 atribuições; e, dia a dia por 365 dias: a lista do dia,
-- ~100 entregas por dia (~36 mil no ano), o livro de pontos, missões aceitas,
-- justificativas, 7 resgates por dia, o lançamento de venda, 2 agendamentos e
-- 3 solicitações por dia; e um gerente com todas as permissões nas duas
-- lojas ativas. Gerado direto nas tabelas (gatilhos desligados), com semente
-- fixa. Roda DEPOIS do teste de isolamento, num banco descartável.
-- =========================================================================
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES ('99999999-9999-9999-9999-999999999999','m900@e.com',now()) ON CONFLICT DO NOTHING;
INSERT INTO public.contas (contaid, nome, email, limitelojas, status) OVERRIDING SYSTEM VALUE VALUES (900,'Empresa 900','e900@e.com',5,'ativa');
INSERT INTO public.contasusuarios (contaid, userid) VALUES (900,'99999999-9999-9999-9999-999999999999');
SET session_replication_role = replica;
SELECT setseed(0.42);
INSERT INTO public.lojas (lojaid, contaid, nome, ativa) OVERRIDING SYSTEM VALUE VALUES (9001,900,'L1',true),(9002,900,'L2',true),(9003,900,'L3 inativa',false);
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, ativo, diadefolga, datainicioafastamento, datafimafastamento) OVERRIDING SYSTEM VALUE
  SELECT 90000+g, 900, 'Pessoa '||g||' Sobrenome', random() > 0.1,
         CASE WHEN random() < 0.15 THEN extract(dow from now() AT TIME ZONE 'America/Sao_Paulo')::int + 1 ELSE (floor(random()*7)+1)::int END,
         CASE WHEN random() < 0.08 THEN current_date - 2 END, CASE WHEN random() < 0.08 THEN current_date + 2 END
    FROM generate_series(1,40) g;
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid, ativo) SELECT 900, 90000+g, 9001 + (g % 3), random() > 0.05 FROM generate_series(1,40) g;
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos, ativa) OVERRIDING SYSTEM VALUE
  SELECT 900000+g, 900, 'Tarefa sintetica '||g, (g%9)+1, random() > 0.07 FROM generate_series(1,80) g;
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, valorfrequencia,
       dataagendamento, horariodisparo, compartilhada, disponivelapartir, datafimvigencia, dataatribuicao) OVERRIDING SYSTEM VALUE
  SELECT 9000000+g, 900, 900000 + (g % 80) + 1, CASE WHEN r1 < 0.7 THEN 90000 + ((g*7) % 40) + 1 END, 9001 + (g % 3), fr,
         CASE fr WHEN 'Semanal' THEN (floor(random()*7)+1)::int WHEN 'Mensal' THEN (floor(random()*31)+1)::int END,
         CASE WHEN fr = 'Unica' THEN now() + make_interval(hours => (floor(random()*200)-140)::int) END,
         CASE WHEN r1 >= 0.7 THEN time '08:00' + make_interval(mins => (floor(random()*600))::int) END,
         r1 >= 0.85,
         CASE WHEN random() < 0.3 THEN time '00:00' + make_interval(mins => (floor(random()*1439))::int) END,
         CASE WHEN random() < 0.1 THEN current_date - (floor(random()*3))::int END,
         now() - make_interval(days => (floor(random()*30))::int)
    FROM (SELECT g, random() r1, (ARRAY['Diaria','Diaria','Semanal','Mensal','Unica','Unica'])[floor(random()*6)+1] fr
            FROM generate_series(1,700) g) s;
INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, aceitoem, revogadoem, motivorevogacao)
  SELECT 900, ta.atribuicaoid, (now() AT TIME ZONE 'America/Sao_Paulo')::date, 90000 + ((ta.atribuicaoid*3) % 40) + 1,
         now() - interval '2 hours', r2, CASE WHEN r2 IS NOT NULL THEN 'teste' END
    FROM (SELECT ta.*, CASE WHEN random() < 0.2 THEN now() - interval '1 hour' END r2 FROM public.tarefasatribuidas ta
           WHERE ta.contaid = 900 AND random() < 0.35) ta;
INSERT INTO public.entregas (contaid, lojaid, atribuicaoid, tarefaid, funcionarioid, dataenvio, statusvalidacao, dataaprovacao, datarecusa, dataestorno, motivorecusa, motivoestorno)
  SELECT 900, ta.lojaid, ta.atribuicaoid, ta.tarefaid, coalesce(ta.funcionarioid, 90001), env, st,
         CASE WHEN st IN ('Aprovada','Estornada') THEN env + interval '10 minutes' END,
         CASE WHEN st = 'Recusada' THEN env + interval '10 minutes' END,
         CASE WHEN st = 'Estornada' THEN env + interval '20 minutes' END, 'x', 'x'
    FROM (SELECT ta.*, now() - make_interval(hours => (floor(random()*80))::int) env,
                 (ARRAY['Pendente','Aprovada','Aprovada','Recusada','Estornada'])[floor(random()*5)+1] st
            FROM public.tarefasatribuidas ta WHERE ta.contaid = 900 AND random() < 0.45) ta;
INSERT INTO public.justificativas (contaid, lojaid, atribuicaoid, funcionarioid, dia, motivo, status, decididoem, motivorecusa)
  SELECT 900, ta.lojaid, ta.atribuicaoid, coalesce(ta.funcionarioid, 90001), (now() AT TIME ZONE 'America/Sao_Paulo')::date, 'x',
         st, CASE WHEN st <> 'Pendente' THEN now() END, 'x'
    FROM (SELECT ta.*, (ARRAY['Pendente','Aceita','Recusada'])[floor(random()*3)+1] st
            FROM public.tarefasatribuidas ta WHERE ta.contaid = 900 AND random() < 0.08) ta;
SET session_replication_role = origin;

-- Um gerente na conta sintética 900, com todas as permissões, nas lojas 9001 e 9002.
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES ('90909090-9090-9090-9090-909090909090', 'gerente.900@e.com', now());
INSERT INTO public.contasusuarios (contaid, userid, papel) VALUES (900, '90909090-9090-9090-9090-909090909090', 'gerente');
INSERT INTO public.cargos (cargoid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (9009, 900, 'Tudo (900)');
INSERT INTO public.cargospermissoes (contaid, cargoid, codigo) SELECT 900, 9009, codigo FROM public.catalogo_de_permissoes();
INSERT INTO public.usuariosgerenciais (contaid, userid, cargoid) VALUES (900, '90909090-9090-9090-9090-909090909090', 9009);
INSERT INTO public.usuarioslojas (contaid, userid, lojaid) VALUES (900, '90909090-9090-9090-9090-909090909090', 9001),
                                                           (900, '90909090-9090-9090-9090-909090909090', 9002);

SET session_replication_role = replica;
INSERT INTO public.produtosloja (produtoid, contaid, nome, custoempontos, estoquedisponivel, ativo) OVERRIDING SYSTEM VALUE
SELECT 900000 + g, 900, 'Prêmio ' || g, 20 + g * 5, 50, true FROM generate_series(1, 20) g;
INSERT INTO public.metasdiariasmodelos (contaid, lojaid, diasemanaid, nomedia, valormeta, pontospremio)
SELECT 900, l, d, 'Dia ' || d, 3000, 5 FROM (VALUES (9001), (9002)) v(l), generate_series(1, 7) d;
INSERT INTO public.metasprincipais (contaid, lojaid, nomemeta, valormetatotal, datainicio, datafim, pontospremio)
SELECT 900, l, 'Meta ' || to_char(m, 'MM/YYYY'), 90000, m, (m + interval '1 month - 1 day')::date, 50
  FROM (VALUES (9001), (9002)) v(l),
       generate_series(date_trunc('month', current_date) - interval '12 months', date_trunc('month', current_date), interval '1 month') m;
SET session_replication_role = origin;

-- Uso de uma loja real, dia a dia, para a conta 900: dias 1 a 365 atrás.
-- Tudo o que cresce com o uso: entregas, livro de pontos, lista do dia,
-- missões aceitas, justificativas, resgates, metas, agenda, solicitações.
SET session_replication_role = replica;
-- Os contadores de número atrás dos números fixos do teste: acerta todos.
DO $$ DECLARE r record; m bigint; BEGIN
  FOR r IN SELECT c.table_name, c.column_name, pg_get_serial_sequence('public.' || c.table_name, c.column_name) s
             FROM information_schema.columns c WHERE c.table_schema = 'public' AND c.is_identity = 'YES' LOOP
    EXECUTE format('SELECT max(%I) FROM public.%I', r.column_name, r.table_name) INTO m;
    IF m IS NOT NULL THEN PERFORM setval(r.s, m); END IF;
  END LOOP; END $$;
SELECT setseed(0.5 + 1 / 1000.0);
CREATE TEMP TABLE dias AS SELECT d FROM generate_series(1, 365) d;
-- A lista do dia: toda atribuição diária com dono, todo dia.
INSERT INTO public.tarefasdodia (contaid, lojaid, dia, atribuicaoid, funcionarioid, tarefaid, tipofrequencia, pontos, situacao, geradoem)
SELECT 900, ta.lojaid, (now() AT TIME ZONE 'America/Sao_Paulo')::date - d, ta.atribuicaoid, ta.funcionarioid, ta.tarefaid, 'Diaria', 5,
       CASE WHEN random() < 0.1 THEN 'folga' ELSE 'devida' END, now() - make_interval(days => d)
  FROM public.tarefasatribuidas ta CROSS JOIN dias
 WHERE ta.contaid = 900 AND ta.funcionarioid IS NOT NULL AND ta.tipofrequencia = 'Diaria'
ON CONFLICT DO NOTHING;
INSERT INTO public.diasgerados (contaid, dia) SELECT 900, (now() AT TIME ZONE 'America/Sao_Paulo')::date - d FROM dias ON CONFLICT DO NOTHING;
-- Entregas: ~60% dos itens do dia.
INSERT INTO public.entregas (contaid, lojaid, atribuicaoid, tarefaid, funcionarioid, dataenvio, statusvalidacao,
                             dataaprovacao, datarecusa, dataestorno, pontosganhos, motivorecusa, motivoestorno)
SELECT 900, ta.lojaid, ta.atribuicaoid, ta.tarefaid, ta.funcionarioid, env, st,
       CASE WHEN st IN ('Aprovada', 'Estornada') THEN env + interval '30 minutes' END,
       CASE WHEN st = 'Recusada' THEN env + interval '30 minutes' END,
       CASE WHEN st = 'Estornada' THEN env + interval '2 hours' END,
       CASE WHEN st = 'Aprovada' THEN 5 ELSE 0 END, 'x', 'x'
  FROM public.tarefasatribuidas ta CROSS JOIN dias
 CROSS JOIN LATERAL (SELECT now() - make_interval(days => d, mins => (floor(random() * 600))::int) AS env,
                            (ARRAY['Aprovada', 'Aprovada', 'Aprovada', 'Aprovada', 'Recusada', 'Estornada'])[floor(random() * 6) + 1] AS st) x
 WHERE ta.contaid = 900 AND ta.funcionarioid IS NOT NULL AND ta.tipofrequencia = 'Diaria' AND random() < 0.6
ON CONFLICT DO NOTHING;
-- O livro: um movimento por entrega aprovada (e o estorno das estornadas).
INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, datamovimento, tipo, pontos, descricao, entregaid)
SELECT 900, e.funcionarioid, e.lojaid, e.dataaprovacao, 'aprovacao', 5, 'Tarefa', e.entregaid
  FROM public.entregas e WHERE e.contaid = 900 AND e.statusvalidacao IN ('Aprovada', 'Estornada')
   AND e.dataenvio >= now() - make_interval(days => 365 + 1) AND e.dataenvio < now() - make_interval(days => 1 - 1)
   AND NOT EXISTS (SELECT 1 FROM public.movimentospontos m WHERE m.entregaid = e.entregaid);
-- Missões da equipe aceitas (compartilhadas), e justificativas (~5% dos itens).
INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, aceitoem)
SELECT 900, ta.atribuicaoid, (now() AT TIME ZONE 'America/Sao_Paulo')::date - d, 90000 + ((ta.atribuicaoid * 3 + d) % 40) + 1, now() - make_interval(days => d)
  FROM public.tarefasatribuidas ta CROSS JOIN dias
 WHERE ta.contaid = 900 AND ta.funcionarioid IS NULL AND random() < 0.35 ON CONFLICT DO NOTHING;
INSERT INTO public.justificativas (contaid, lojaid, atribuicaoid, funcionarioid, dia, motivo, status, decididoem, motivorecusa)
SELECT 900, t.lojaid, t.atribuicaoid, t.funcionarioid, t.dia, 'x', st, now(), 'x'
  FROM public.tarefasdodia t CROSS JOIN LATERAL (SELECT (ARRAY['Aceita', 'Recusada', 'Recusada'])[floor(random() * 3) + 1] st) s
 WHERE t.contaid = 900 AND t.dia BETWEEN (now() AT TIME ZONE 'America/Sao_Paulo')::date - 365 AND (now() AT TIME ZONE 'America/Sao_Paulo')::date - 1
   AND random() < 0.05;
-- Resgates (~7 por dia) com o débito no livro.
INSERT INTO public.resgates (contaid, lojaid, funcionarioid, produtoid, pontosgastos, datasolicitacao, status, dataaprovacao, dataentrega, datacancelamento, motivocancelamento)
SELECT 900, 9001 + (g % 2), 90000 + (g % 40) + 1, 900000 + (g % 20) + 1, 50, now() - make_interval(days => d, hours => g % 10),
       st, CASE WHEN st <> 'Cancelado' THEN now() - make_interval(days => d) END,
       CASE WHEN st = 'Entregue' THEN now() - make_interval(days => d) END, CASE WHEN st = 'Cancelado' THEN now() - make_interval(days => d) END, CASE WHEN st = 'Cancelado' THEN 'desistiu' END
  FROM dias CROSS JOIN generate_series(1, 7) g
 CROSS JOIN LATERAL (SELECT (ARRAY['Entregue', 'Entregue', 'Entregue', 'Cancelado'])[floor(random() * 4) + 1] st) x;
INSERT INTO public.movimentospontos (contaid, funcionarioid, lojaid, datamovimento, tipo, pontos, descricao, resgateid)
SELECT 900, r.funcionarioid, r.lojaid, r.datasolicitacao, 'resgate', -r.pontosgastos, 'Resgate', r.resgateid
  FROM public.resgates r WHERE r.contaid = 900 AND NOT EXISTS (SELECT 1 FROM public.movimentospontos m WHERE m.resgateid = r.resgateid);
-- Metas (o lançamento de cada dia), agenda (~2 por dia) e solicitações (~3 por dia).
INSERT INTO public.metasdiariasapuracoes (contaid, lojaid, dataapuracao, valordia, valormetadia, pontosmetadia, origemmeta, lancadoem)
SELECT 900, l, (now() AT TIME ZONE 'America/Sao_Paulo')::date - d, 2000 + floor(random() * 2500), 3000, 5, 'modelo', now() - make_interval(days => d)
  FROM (VALUES (9001), (9002)) v(l) CROSS JOIN dias ON CONFLICT DO NOTHING;
INSERT INTO public.agendamentos (contaid, lojaid, nomecliente, tipoevento, dataevento, funcionarioid, statusagendamento, valor)
SELECT 900, 9001 + (g % 2), 'Cliente ' || d || '-' || g, 'Evento', now() - make_interval(days => d), 90000 + ((d + g) % 40) + 1, 'Realizado', 150
  FROM dias CROSS JOIN generate_series(1, 2) g;
INSERT INTO public.solicitacoesinternas (contaid, lojaid, funcionarioid, tipo, descricao, status, datasolicitacao)
SELECT 900, 9001 + (g % 2), 90000 + ((d + g) % 40) + 1, 'Compra', 'Item ' || d || '-' || g, 'Concluída', now() - make_interval(days => d)
  FROM dias CROSS JOIN generate_series(1, 3) g;
SET session_replication_role = origin;
ANALYZE;
SELECT 365 AS dias_de_uso,
       (SELECT count(*) FROM public.entregas WHERE contaid = 900) AS entregas,
       (SELECT count(*) FROM public.movimentospontos WHERE contaid = 900) AS livro,
       (SELECT count(*) FROM public.tarefasdodia WHERE contaid = 900) AS lista_do_dia,
       (SELECT count(*) FROM public.resgates WHERE contaid = 900) AS resgates,
       (SELECT count(*) FROM public.justificativas WHERE contaid = 900) AS justificativas;

-- Feedbacks: um por pessoa por semana, no ano.
SET session_replication_role = replica;
INSERT INTO public.feedbacks (contaid, funcionarioid, datafeedback, notadia, comentario, origem, pontosbonus)
SELECT 900, 90000 + g, (now() AT TIME ZONE 'America/Sao_Paulo')::date - w * 7 - (g % 7), 5 + (g % 5), 'Semana ' || w, 'gestor', 0
  FROM generate_series(1, 40) g CROSS JOIN generate_series(0, 51) w
ON CONFLICT DO NOTHING;
SET session_replication_role = origin;
ANALYZE public.feedbacks;

-- Comunicados (2 por semana, para as duas lojas ativas, com a ciência de
-- metade da equipe) e conquistas (5 no catálogo, cada pessoa ganha as 5 ao longo do ano).
SET session_replication_role = replica;
INSERT INTO public.documentos (documentoid, contaid, titulo, conteudo, pontosporciencia, datacriacao, status, alvo) OVERRIDING SYSTEM VALUE
SELECT 900000 + w, 900, 'Comunicado ' || w, 'Texto', 0, now() - make_interval(days => w * 3), 'Publicado', 'lojas'
  FROM generate_series(1, 104) w;
INSERT INTO public.documentoslojas (contaid, documentoid, lojaid)
SELECT 900, 900000 + w, 9001 + (w % 2) FROM generate_series(1, 104) w;
INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, statusassinatura, dataenvio, dataciencia, origem)
SELECT 900, 900000 + w, fl.funcionarioid, CASE WHEN fl.funcionarioid % 2 = 0 THEN 'Ciente' ELSE 'Pendente' END,
       now() - make_interval(days => w * 3), CASE WHEN fl.funcionarioid % 2 = 0 THEN now() - make_interval(days => w * 3) END,
       CASE WHEN fl.funcionarioid % 2 = 0 THEN 'gestor' END
  FROM generate_series(1, 104) w
  JOIN public.funcionarioslojas fl ON fl.contaid = 900 AND fl.lojaid = 9001 + (w % 2) AND fl.ativo;
INSERT INTO public.conquistas (conquistaid, contaid, nome, descricao, criteriotipo, criteriovalor, pontosbonus, ativa) OVERRIDING SYSTEM VALUE
SELECT 900000 + c, 900, 'Conquista ' || c, 'x', 'total_tarefas_aprovadas', 10 * c, 0, true FROM generate_series(1, 5) c;
INSERT INTO public.conquistasfuncionarios (contaid, funcionarioid, conquistaid, dataconquista, pontosbonus)
SELECT 900, 90000 + g, 900000 + c, now() - make_interval(days => c * 60 + g % 20), 0
  FROM generate_series(1, 40) g CROSS JOIN generate_series(1, 5) c;
SET session_replication_role = origin;
ANALYZE public.documentos; ANALYZE public.documentosassinaturas; ANALYZE public.conquistasfuncionarios;

-- As tarefas valem nas lojas (numa conta real toda tarefa tem loja; o
-- catálogo do gerente mostra só as que valem nas lojas dele).
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid)
SELECT 900, 900000 + g, l FROM generate_series(1, 80) g CROSS JOIN (VALUES (9001), (9002), (9003)) v(l)
ON CONFLICT DO NOTHING;
ANALYZE public.tarefaslojas;
