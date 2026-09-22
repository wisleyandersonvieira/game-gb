-- Prepara o teste de feedback concorrente na conta C: as configuracoes
-- padrao (bonus de 5 pontos). Duas conexoes registram o feedback de hoje da
-- mesma pessoa ao mesmo tempo; so um pode entrar, com um bonus so.
\set ON_ERROR_STOP on
SELECT public.cria_configuracoes_padrao(9);
