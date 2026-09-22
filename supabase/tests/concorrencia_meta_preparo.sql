-- Prepara o teste de meta concorrente na conta C (loja 90, Davi 901):
-- meta de 1.000 em todos os dias da semana, 25 pontos. Duas conexoes lancam
-- a venda de hoje ao mesmo tempo (1.500 e 1.600); o premio so pode sair uma vez.
\set ON_ERROR_STOP on
INSERT INTO public.metasdiariasmodelos (contaid, lojaid, diasemanaid, nomedia, valormeta, pontospremio)
SELECT 9, 90, d, 'Dia ' || d, 1000, 25 FROM generate_series(1, 7) d;
