-- =========================================================================
-- Volume de LOJA REAL para o teste de tempo das telas (volume_medir.sql).
--
-- Uma conta sintética (900) com duas lojas ativas e uma inativa, 40 pessoas,
-- 80 tarefas, 700 atribuições, 90 dias de entregas (~10 mil), 600 resgates,
-- metas com lançamento diário, 200 agendamentos e 300 solicitações; e um
-- gerente com todas as permissões nas duas lojas ativas. Gerado direto nas
-- tabelas (gatilhos desligados), com semente fixa: a mesma rodada sempre.
-- Roda DEPOIS do teste de isolamento, num banco descartável.
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

-- Volume de LOJA REAL para a conta sintética 900 (lojas 9001 e 9002 ativas):
-- 90 dias de entregas, prêmios e resgates, metas com lançamento diário,
-- agenda e solicitações. Gerado direto nas tabelas (gatilhos desligados).
SET session_replication_role = replica;
SELECT setseed(0.77);

-- 90 dias de entregas: cada atribuição diária com dono entrega em ~60% dos dias.
INSERT INTO public.entregas (contaid, lojaid, atribuicaoid, tarefaid, funcionarioid, dataenvio, statusvalidacao,
                             dataaprovacao, datarecusa, dataestorno, pontosganhos, motivorecusa, motivoestorno)
SELECT 900, ta.lojaid, ta.atribuicaoid, ta.tarefaid, ta.funcionarioid, env, st,
       CASE WHEN st IN ('Aprovada', 'Estornada') THEN env + interval '30 minutes' END,
       CASE WHEN st = 'Recusada' THEN env + interval '30 minutes' END,
       CASE WHEN st = 'Estornada' THEN env + interval '2 hours' END,
       CASE WHEN st = 'Aprovada' THEN 5 ELSE 0 END, 'x', 'x'
  FROM public.tarefasatribuidas ta
 CROSS JOIN generate_series(1, 90) d
 CROSS JOIN LATERAL (SELECT now() - make_interval(days => d, mins => (floor(random() * 600))::int) AS env,
                            (ARRAY['Aprovada', 'Aprovada', 'Aprovada', 'Aprovada', 'Recusada', 'Estornada'])[floor(random() * 6) + 1] AS st) x
 WHERE ta.contaid = 900 AND ta.funcionarioid IS NOT NULL AND ta.tipofrequencia = 'Diaria' AND random() < 0.6
ON CONFLICT DO NOTHING;

-- Prêmios e resgates (90 dias).
INSERT INTO public.produtosloja (produtoid, contaid, nome, custoempontos, estoquedisponivel, ativo) OVERRIDING SYSTEM VALUE
SELECT 900000 + g, 900, 'Prêmio ' || g, 20 + g * 5, 50, true FROM generate_series(1, 20) g;
INSERT INTO public.resgates (contaid, lojaid, funcionarioid, produtoid, pontosgastos, datasolicitacao, status,
                             dataaprovacao, dataentrega, datacancelamento, dataestorno)
SELECT 900, 9001 + (g % 2), 90000 + (g % 40) + 1, 900000 + (g % 20) + 1, 50, ds, st,
       CASE WHEN st IN ('Aprovado', 'Entregue', 'Estornado') THEN ds + interval '1 hour' END,
       CASE WHEN st IN ('Entregue', 'Estornado') THEN ds + interval '1 day' END,
       CASE WHEN st = 'Cancelado' THEN ds + interval '2 hours' END,
       CASE WHEN st = 'Estornado' THEN ds + interval '2 days' END
  FROM generate_series(1, 600) g
 CROSS JOIN LATERAL (SELECT now() - make_interval(days => (floor(random() * 90))::int) AS ds,
                            (ARRAY['Pendente', 'Entregue', 'Entregue', 'Entregue', 'Cancelado', 'Estornado'])[floor(random() * 6) + 1] AS st) x;

-- Metas: modelo da semana, meta do mês (3 meses) e lançamento de todo dia.
INSERT INTO public.metasdiariasmodelos (contaid, lojaid, diasemanaid, nomedia, valormeta, pontospremio)
SELECT 900, l, d, 'Dia ' || d, 3000, 5 FROM (VALUES (9001), (9002)) v(l), generate_series(1, 7) d;
INSERT INTO public.metasprincipais (contaid, lojaid, nomemeta, valormetatotal, datainicio, datafim, pontospremio)
SELECT 900, l, 'Meta ' || to_char(m, 'MM/YYYY'), 90000, m, (m + interval '1 month - 1 day')::date, 50
  FROM (VALUES (9001), (9002)) v(l),
       generate_series(date_trunc('month', current_date) - interval '2 months', date_trunc('month', current_date), interval '1 month') m;
INSERT INTO public.metasdiariasapuracoes (contaid, lojaid, dataapuracao, valordia, valormetadia, pontosmetadia, origemmeta, lancadoem)
SELECT 900, l, d::date, 2000 + floor(random() * 2500), 3000, 5, 'modelo', d + interval '22 hours'
  FROM (VALUES (9001), (9002)) v(l), generate_series(current_date - 90, current_date - 1, interval '1 day') d;

-- Agenda e solicitações.
INSERT INTO public.agendamentos (contaid, lojaid, nomecliente, tipoevento, dataevento, funcionarioid, statusagendamento, valor, motivocancelamento, canceladoem)
SELECT 900, 9001 + (g % 2), 'Cliente ' || g, 'Evento', now() + make_interval(days => (g % 60) - 30, hours => g % 10),
       90000 + (g % 40) + 1, (ARRAY['Confirmado', 'Confirmado', 'Realizado', 'Cancelado'])[(g % 4) + 1], 150,
       CASE WHEN g % 4 = 3 THEN 'desistiu' END, CASE WHEN g % 4 = 3 THEN now() END
  FROM generate_series(1, 200) g;
INSERT INTO public.solicitacoesinternas (contaid, lojaid, funcionarioid, tipo, descricao, status, datasolicitacao, motivorecusa)
SELECT 900, 9001 + (g % 2), 90000 + (g % 40) + 1, 'Compra', 'Item ' || g,
       (ARRAY['Aberta', 'Em andamento', 'Concluída', 'Recusada'])[(g % 4) + 1], now() - make_interval(days => g % 90),
       CASE WHEN g % 4 = 3 THEN 'nao precisa' END
  FROM generate_series(1, 300) g;
SET session_replication_role = origin;
ANALYZE;
SELECT 'entregas' AS tabela, count(*) FROM public.entregas WHERE contaid = 900
UNION ALL SELECT 'resgates', count(*) FROM public.resgates WHERE contaid = 900
UNION ALL SELECT 'apuracoes', count(*) FROM public.metasdiariasapuracoes WHERE contaid = 900
UNION ALL SELECT 'agendamentos', count(*) FROM public.agendamentos WHERE contaid = 900
UNION ALL SELECT 'solicitacoes', count(*) FROM public.solicitacoesinternas WHERE contaid = 900
UNION ALL SELECT 'atribuicoes', count(*) FROM public.tarefasatribuidas WHERE contaid = 900
UNION ALL SELECT 'pessoas', count(*) FROM public.funcionarios WHERE contaid = 900;

-- Um gerente na conta sintética 900, com todas as permissões, nas lojas 9001 e 9002.
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES ('90909090-9090-9090-9090-909090909090', 'gerente.900@e.com', now());
INSERT INTO public.contasusuarios (contaid, userid, papel) VALUES (900, '90909090-9090-9090-9090-909090909090', 'gerente');
INSERT INTO public.cargos (cargoid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (9009, 900, 'Tudo (900)');
INSERT INTO public.cargospermissoes (contaid, cargoid, codigo) SELECT 900, 9009, codigo FROM public.catalogo_de_permissoes();
INSERT INTO public.usuariosgerenciais (contaid, userid, cargoid) VALUES (900, '90909090-9090-9090-9090-909090909090', 9009);
INSERT INTO public.usuarioslojas (contaid, userid, lojaid) VALUES (900, '90909090-9090-9090-9090-909090909090', 9001),
                                                           (900, '90909090-9090-9090-9090-909090909090', 9002);
ANALYZE;
