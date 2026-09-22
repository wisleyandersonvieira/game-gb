-- Prepara o teste de rotinas ao mesmo tempo (Etapa 1.11) na conta 12:
-- uma pessoa de folga hoje com uma tarefa, e duas que trabalham hoje.
-- Duas conexoes rodam a rotina e tentam passar a MESMA tarefa, cada uma
-- para uma pessoa diferente. So uma pode passar, e a lista nao duplica.
\set ON_ERROR_STOP on
INSERT INTO auth.users (id, email, email_confirmed_at)
VALUES ('0c0c0c0c-0c0c-0c0c-0c0c-0c0c0c0c0c0c', 'master.rotina@exemplo.com', now());
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (12, 'Empresa Rotina', 'rotina@exemplo.com', 1);
INSERT INTO public.contasusuarios (contaid, userid) VALUES (12, '0c0c0c0c-0c0c-0c0c-0c0c-0c0c0c0c0c0c');
INSERT INTO public.lojas (lojaid, contaid, nome) OVERRIDING SYSTEM VALUE VALUES (120, 12, 'Loja Rotina');
INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, diadefolga) OVERRIDING SYSTEM VALUE VALUES
  (1201, 12, 'Folguista', extract(dow FROM public.dia_em_sao_paulo(now()))::integer + 1),
  (1202, 12, 'Pessoa Um', 0),
  (1203, 12, 'Pessoa Dois', 0);
INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid) VALUES (12, 1201, 120), (12, 1202, 120), (12, 1203, 120);
INSERT INTO public.tarefas (tarefaid, contaid, titulo, pontos) OVERRIDING SYSTEM VALUE VALUES (1210, 12, 'Tarefa da folga', 4);
INSERT INTO public.tarefaslojas (contaid, tarefaid, lojaid) VALUES (12, 1210, 120);
INSERT INTO public.tarefasatribuidas (atribuicaoid, contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataatribuicao)
OVERRIDING SYSTEM VALUE VALUES
  (1220, 12, 1210, 1201, 120, 'Diaria', now()),
  (1221, 12, 1210, 1202, 120, 'Diaria', now()),
  (1222, 12, 1210, 1203, 120, 'Diaria', now());
