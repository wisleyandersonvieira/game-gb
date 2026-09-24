-- Prepara a corrida "revogar o aceite" x "entregar" (conta 16).
-- O gestor revoga no mesmo instante em que a pessoa entrega no tablet. Sem
-- lock, o revisor provou que as duas passavam: entrega orfa numa copia ja
-- revogada, e a tarefa paga duas vezes.
\set ON_ERROR_STOP on
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (16, 'Empresa Revoga', 'revoga@exemplo.com', 1);
INSERT INTO public.lojas (lojaid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (160, 16, 'Loja da Revoga');
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto) OVERRIDING SYSTEM VALUE
VALUES (1601, 16, 'Pessoa da Revoga');
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (16, 1601, 160);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE
VALUES (1610, 16, 'Tarefa disputada', 9);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (16, 1610, 160);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia,
                                      dataatribuicao, compartilhada)
OVERRIDING SYSTEM VALUE VALUES (16900, 16, 1610, NULL, 160, 'Diaria', now() - interval '1 day', true);
INSERT INTO public.tarefascandidatos (contaid, atribuicaoid, funcionarioid) VALUES (16, 16900, 1601);

-- A pessoa ja pegou: e esse aceite que o gestor vai tentar revogar.
SET ROLE service_role;
BEGIN;
SELECT set_config('stgame.bot_conta', '16', true);
SELECT public.pegar_tarefa(16900, 1601);
COMMIT;
RESET ROLE;
