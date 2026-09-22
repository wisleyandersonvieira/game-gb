-- Prepara o teste da trava de tentativas (conta 15): a chave chega a UMA
-- tentativa do teto do dia, e duas conexões tentam ao mesmo tempo.
-- Sem a trava atômica, as duas passavam (era assim que o adivinhador de PIN
-- voltava, disparando tudo junto).
\set ON_ERROR_STOP on
INSERT INTO public.contas (contaid, nome, email, limitelojas) OVERRIDING SYSTEM VALUE
VALUES (15, 'Empresa Trava', 'trava@exemplo.com', 1);

-- 29 ERROS de PIN hoje: falta um para o teto de 30. Ficam fora da janela de
-- 1 minuto, para quem barrar seja o teto do dia, e nao os 5 erros seguidos.
INSERT INTO public.tentativasacesso (contaid, tipo, chave, origem, sucesso, em)
SELECT 15, 'pin', repeat('t', 64), 'origem-' || g, false, now() - interval '5 minutes'
  FROM generate_series(1, 29) g;
