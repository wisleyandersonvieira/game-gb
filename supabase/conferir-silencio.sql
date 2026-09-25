-- =========================================================================
-- STGame — O HORÁRIO DE SILÊNCIO DO BOT está certo?
--
-- Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Só LÊ. Não altera nada.
--
-- O silêncio é a faixa em que o bot NÃO manda mensagem automática. O padrão
-- é 22:00 até 07:00. Esta consulta mostra o valor de hoje e se ele já foi
-- alterado alguma vez — se nunca foi, é o padrão de fábrica.
-- =========================================================================

SELECT g.contaid                                   AS "conta",
       g.chave                                     AS "configuracao",
       g.valor                                     AS "valor de hoje",
       CASE g.chave
         WHEN 'HORARIO_SILENCIO_INICIO' THEN '22:00'
         WHEN 'HORARIO_SILENCIO_FIM'    THEN '07:00'
       END                                         AS "padrao de fabrica",
       CASE WHEN g.valor = CASE g.chave
                             WHEN 'HORARIO_SILENCIO_INICIO' THEN '22:00'
                             WHEN 'HORARIO_SILENCIO_FIM'    THEN '07:00'
                           END
            THEN 'ok: esta no padrao'
            ELSE '>>> DIFERENTE do padrao'
       END                                         AS "situacao",
       coalesce((SELECT count(*)::text FROM public.configuracoeshistorico h
                  WHERE h.contaid = g.contaid AND h.chave = g.chave), '0')
                                                   AS "vezes que foi alterado",
       (SELECT max(h.alteradoem)::text FROM public.configuracoeshistorico h
         WHERE h.contaid = g.contaid AND h.chave = g.chave)
                                                   AS "ultima alteracao"
  FROM public.configuracoes g
 WHERE g.chave IN ('HORARIO_SILENCIO_INICIO', 'HORARIO_SILENCIO_FIM')
 ORDER BY g.contaid, g.chave;
