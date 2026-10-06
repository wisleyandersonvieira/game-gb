-- =========================================================================
-- STGame — DESLIGAR O PORTÃO (emergência)
--
-- Use SÓ se, depois de aplicar o aplicar-portao-do-token.sql, o site, o
-- tablet ou a TV pararem de carregar dados. Este arquivo faz o banco parar de
-- rodar a função antes de cada pedido (volta a ser como era antes). Não apaga
-- nada: a função e a tabela continuam lá, só não são mais chamadas.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Depois, recarregue o site. E me chame.
-- =========================================================================
ALTER ROLE authenticator RESET pgrst.db_pre_request;
NOTIFY pgrst, 'reload config';
SELECT 'portão desligado: o banco não roda mais a função antes de cada pedido' AS resultado;
