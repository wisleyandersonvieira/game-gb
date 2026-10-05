-- =========================================================================
-- STGame — QUANTO DO TELEGRAM VAI SAIR (rode ANTES do aplicar-tirar-telegram.sql)
--
-- Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Só LÊ. Não altera nada. Me mande a tabela que aparecer.
--
-- Cada linha diz quantos registros daquele item existem hoje. Todos saem com
-- o aplicar-tirar-telegram.sql (o identificador de Telegram das pessoas é
-- dado pessoal sem finalidade sem o bot; a fila não tem valor histórico).
-- =========================================================================
SELECT 'Pessoas com identificador de Telegram (funcionarios.chatidtelegram)' AS item,
       (SELECT count(*) FROM public.funcionarios WHERE chatidtelegram IS NOT NULL) AS linhas
UNION ALL SELECT 'Vínculos com o bot (pessoas, master e grupos; ativos e desligados)', (SELECT count(*) FROM public.telegramvinculos)
UNION ALL SELECT '  dos quais ainda ativos', (SELECT count(*) FROM public.telegramvinculos WHERE ativo)
UNION ALL SELECT 'Convites do Telegram', (SELECT count(*) FROM public.telegramconvites)
UNION ALL SELECT 'Fila de mensagens', (SELECT count(*) FROM public.mensagensfila)
UNION ALL SELECT 'Liga/desliga das mensagens automáticas', (SELECT count(*) FROM public.mensagensrotinas)
UNION ALL SELECT 'Medição de uso das mensagens', (SELECT count(*) FROM public.usomensagens)
UNION ALL SELECT 'Grupos (sistema antigo)', (SELECT count(*) FROM public.grupos)
UNION ALL SELECT 'Pessoas em grupos (sistema antigo)', (SELECT count(*) FROM public.funcionariosgrupos)
UNION ALL SELECT 'Marcas de "validador" ligadas', (SELECT count(*) FROM public.funcionarioslojas WHERE validador)
UNION ALL SELECT 'Entregas com dados do Telegram (mensagem no grupo, foto)', (SELECT count(*) FROM public.entregas WHERE avisochatid IS NOT NULL OR fileidtelegram IS NOT NULL)
UNION ALL SELECT 'Mensagens do Telegram já tratadas (controle do bot)', (SELECT count(*) FROM bot.updates)
UNION ALL SELECT 'Códigos errados por chat (controle do bot)', (SELECT count(*) FROM bot.tentativas)
UNION ALL SELECT 'Conversas em andamento (controle do bot)', (SELECT count(*) FROM bot.estados)
UNION ALL SELECT 'Empresa escolhida por chat (controle do bot)', (SELECT count(*) FROM bot.contaativa);
