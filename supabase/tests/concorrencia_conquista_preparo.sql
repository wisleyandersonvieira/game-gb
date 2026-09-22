-- Prepara o teste de conquista concorrente, na conta C (criada pelo teste de
-- resgates): uma pessoa com duas entregas pendentes e uma conquista "1 tarefa
-- aprovada" com 50 pontos de bonus. Duas conexoes aprovam ao mesmo tempo;
-- a conquista e o bonus so podem sair uma vez.
\set ON_ERROR_STOP on

INSERT INTO public.lojas (lojaid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (90, 9, 'Loja C1');
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto) OVERRIDING SYSTEM VALUE
VALUES (901, 9, 'Davi da conta C');
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE
VALUES (9001, 9, 'Varrer', 2), (9002, 9, 'Lavar', 3);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (9, 901, 90);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (9, 9001, 90), (9, 9002, 90);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia)
  OVERRIDING SYSTEM VALUE VALUES (9101, 9, 9001, 901, 90, 'Diaria'), (9102, 9, 9002, 901, 90, 'Diaria');
INSERT INTO public.entregas (entregaid, contaid, tarefaid, funcionarioid, lojaid, atribuicaoid)
  OVERRIDING SYSTEM VALUE VALUES (9201, 9, 9001, 901, 90, 9101), (9202, 9, 9002, 901, 90, 9102);
INSERT INTO public.conquistas (contaid, nome, descricao, criteriotipo, criteriovalor, pontosbonus)
VALUES (9, 'Primeira tarefa', 'Primeira tarefa aprovada', 'total_tarefas_aprovadas', 1, 50);
