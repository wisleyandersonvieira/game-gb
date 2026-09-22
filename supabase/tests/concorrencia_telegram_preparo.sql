-- Prepara o teste de duas aprovações ao mesmo tempo pelo Telegram (conta 13):
-- o validador e o master tocam "Aprovar" na mesma entrega no mesmo instante.
\set ON_ERROR_STOP on
INSERT INTO auth.users (id, email, email_confirmed_at)
VALUES ('13131313-1313-1313-1313-131313131313', 'master.telegram@exemplo.com', now());
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (13, 'Empresa Telegram', 'telegram@exemplo.com', 1);
INSERT INTO public.contasusuarios (contaid, userid) VALUES (13, '13131313-1313-1313-1313-131313131313');
INSERT INTO public.lojas (lojaid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (130, 13, 'Loja Telegram');
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto) OVERRIDING SYSTEM VALUE VALUES
  (1301, 13, 'Pessoa Um'), (1302, 13, 'Validador Um');
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid, validador) VALUES (13, 1301, 130, false), (13, 1302, 130, true);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (1310, 13, 'Tarefa disputada', 7);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (13, 1310, 130);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
OVERRIDING SYSTEM VALUE VALUES (1320, 13, 1310, 1301, 130, 'Diaria', now() - interval '1 day');
INSERT INTO public.entregas (entregaid, contaid, tarefaid, funcionarioid, lojaid, atribuicaoid, dataenvio, statusvalidacao)
OVERRIDING SYSTEM VALUE VALUES (13901, 13, 1310, 1301, 130, 1320, now(), 'Pendente');
INSERT INTO public.telegramvinculos (contaid, tipo, chatid, lojaid, papelgrupo) VALUES (13, 'grupo', -13001, 130, 'gestao');
INSERT INTO public.telegramvinculos (contaid, tipo, chatid, funcionarioid) VALUES (13, 'pessoa', 13002, 1302);
INSERT INTO public.telegramvinculos (contaid, tipo, chatid, userid) VALUES (13, 'master', 13000, '13131313-1313-1313-1313-131313131313');
