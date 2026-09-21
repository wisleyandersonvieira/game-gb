-- Prepara o teste de concorrencia: uma conta separada, uma pessoa com
-- EXATAMENTE 10 pontos e um premio de 10 pontos com 5 unidades.
-- So cabe um resgate. Duas conexoes vao tentar ao mesmo tempo.
\set ON_ERROR_STOP on

INSERT INTO auth.users (id, email, email_confirmed_at)
VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'master.c@exemplo.com', now());
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (9, 'Empresa C', 'c@exemplo.com', 1);
INSERT INTO public.contasusuarios (contaid, userid) VALUES (9, 'ffffffff-ffff-ffff-ffff-ffffffffffff');

INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto) OVERRIDING SYSTEM VALUE
VALUES (900, 9, 'Carla da conta C');
INSERT INTO public.produtosloja (produtoid, contaid, nome, custoempontos, estoquedisponivel) OVERRIDING SYSTEM VALUE
VALUES (900, 9, 'Vale-lanche', 10, 5);
INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao)
VALUES (9, 900, 'ajuste_abertura', 10, 'Saldo inicial do teste de concorrencia');
