-- Prepara as DUAS corridas do pedido de resgate feito pelo colaborador.
--
-- Uma conta separada, com:
--   - uma pessoa com EXATAMENTE 30 pontos e um premio de 30: so cabe UM
--     pedido, entao dois toques rapidos nao podem reservar duas vezes;
--   - um premio com ESTOQUE 1 e duas pessoas com saldo de sobra: com duas
--     pedindo ao mesmo tempo, so uma pode passar.
\set ON_ERROR_STOP on

INSERT INTO auth.users (id, email, email_confirmed_at)
VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'master.d@exemplo.com', now())
ON CONFLICT DO NOTHING;
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (11, 'Empresa D', 'd@exemplo.com', 1) ON CONFLICT DO NOTHING;
INSERT INTO public.contasusuarios (contaid, userid)
VALUES (11, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') ON CONFLICT DO NOTHING;

INSERT INTO public.funcionarios (funcionarioid, contaid, nomecompleto, ativo) OVERRIDING SYSTEM VALUE
VALUES (910, 11, 'Duda dois toques', true), (912, 11, 'Edu do estoque', true),
       (913, 11, 'Eva do estoque', true)
ON CONFLICT DO NOTHING;

-- (a) so cabe um pedido de 30
INSERT INTO public.produtosloja (produtoid, contaid, nome, custoempontos, estoquedisponivel, ativo)
OVERRIDING SYSTEM VALUE VALUES (910, 11, 'Camiseta', 30, 50, true) ON CONFLICT DO NOTHING;
INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao)
VALUES (11, 910, 'ajuste_abertura', 30, 'Saldo do teste de dois toques');

-- (b) estoque 1, DUAS PESSOAS diferentes com saldo de sobra. Nao se
-- reaproveita a pessoa do teste (a): dar saldo extra a ela faria os dois
-- toques passarem com razao, e o teste (a) perderia o sentido.
INSERT INTO public.produtosloja (produtoid, contaid, nome, custoempontos, estoquedisponivel, ativo)
OVERRIDING SYSTEM VALUE VALUES (911, 11, 'Ultima caneca', 5, 1, true) ON CONFLICT DO NOTHING;
INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao)
VALUES (11, 912, 'ajuste_abertura', 100, 'Saldo do teste de estoque 1'),
       (11, 913, 'ajuste_abertura', 100, 'Saldo do teste de estoque 1');
