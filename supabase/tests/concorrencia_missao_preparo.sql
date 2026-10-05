-- Prepara o teste de "o primeiro que pegar" (conta 14): a mesma missão pega
-- para duas pessoas no mesmo instante.
\set ON_ERROR_STOP on
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (14, 'Empresa Missao', 'missao@exemplo.com', 1);
INSERT INTO public.lojas (lojaid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (140, 14, 'Loja da Missao');
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES
  (1401, 14, 'Corredor Um'), (1402, 14, 'Corredor Dois');
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (14, 1401, 140), (14, 1402, 140);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (1410, 14, 'Missao disputada', 11);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (14, 1410, 140);
-- Missão: atribuição sem dono, com horário de disparo.
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                      dataatribuicao, horariodisparo)
OVERRIDING SYSTEM VALUE VALUES (14900, 14, 1410, NULL, 140, 'Diaria', now() - interval '1 day', '08:00');
-- O dono da conta pega a missão para cada pessoa (era o botão do grupo do
-- Telegram, que saiu em 04/10/2026; a trava que decide é a mesma: pegar_tarefa).
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES ('14141414-1414-1414-1414-141414141414', 'master.14@exemplo.com', now());
INSERT INTO public.contasusuarios (contaid, userid, papel) VALUES (14, '14141414-1414-1414-1414-141414141414', 'master');
