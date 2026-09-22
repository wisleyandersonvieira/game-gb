-- Prepara o teste de ciencia concorrente na conta C: um comunicado de 7
-- pontos para Davi (901). Duas conexoes registram a ciencia ao mesmo tempo;
-- os pontos so podem sair uma vez.
\set ON_ERROR_STOP on
INSERT INTO public.documentos (documentoid, contaid, titulo, conteudo, pontosporciencia, alvo) OVERRIDING SYSTEM VALUE
VALUES (9300, 9, 'Aviso C', 'Texto do aviso', 7, 'funcionarios');
INSERT INTO public.documentosassinaturas (assinaturaid, contaid, documentoid, funcionarioid) OVERRIDING SYSTEM VALUE
VALUES (9301, 9, 9300, 901);
