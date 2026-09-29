-- =========================================================================
-- STGame — Arquivos do gerente: foto, anexo e recibo.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-meta-so-do-master.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929274000_arquivos_do_gerente.sql
--
-- O QUE MUDA: o gerente passa a ABRIR a foto da entrega (com "Quadro: ver"),
-- o anexo da agenda (com "Agenda: ver") e o recibo do resgate (com "Prêmios:
-- ver"), só das lojas dele e só para ler. Documentos pessoais e canal
-- confidencial: nunca. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Arquivos para o gerente: só leitura, só das lojas dele, só com a permissão
-- de ver aquela tela (29/09/2026, decisão 1 do Wisley).
--
--   foto da entrega   -> "Quadro: ver" na loja da entrega;
--   anexo da agenda   -> "Agenda: ver" na loja do agendamento;
--   recibo do resgate -> "Prêmios: ver" na loja do resgate (resgate sem loja: só o master).
--
-- O arquivo só abre se existir a LINHA no banco (a entrega com aquele caminho,
-- o agendamento daquela pasta) numa loja em que ele pode ver a tela: o nome do
-- arquivo sozinho não basta. Enviar, trocar e apagar continuam como estavam.
-- O canal confidencial e os documentos pessoais NUNCA, para nenhum papel: não
-- ganham regra nenhuma aqui (e a seção 112 do teste confere).
-- Para o master nada muda. Nenhum dado é alterado.

-- A foto: a entrega com este caminho, numa loja em que ele vê o Quadro.
CREATE OR REPLACE FUNCTION public.foto_de_entrega_do_gerente(p_nome text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.entregas e
     WHERE e.pathfotoevidencia = p_nome
       AND e.contaid = public.conta_do_gerente()
       AND split_part(p_nome, '/', 1) = e.contaid::text
       AND public.pode('quadro.ver', e.lojaid))
$$;
REVOKE ALL ON FUNCTION public.foto_de_entrega_do_gerente(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.foto_de_entrega_do_gerente(text) TO authenticated;

-- A foto é procurada pelo caminho: sem índice, cada foto do Quadro leria a
-- tabela de entregas inteira.
CREATE INDEX IF NOT EXISTS entregas_pathfotoevidencia ON public.entregas (pathfotoevidencia)
  WHERE pathfotoevidencia IS NOT NULL;

-- O anexo: a pasta <conta>/<loja>/<agendamento>/ de um agendamento de loja em
-- que ele vê a Agenda.
CREATE OR REPLACE FUNCTION public.anexo_da_agenda_do_gerente(p_nome text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.agendamentos a
     WHERE a.contaid = public.conta_do_gerente()
       AND split_part(p_nome, '/', 1) = a.contaid::text
       AND split_part(p_nome, '/', 2) = a.lojaid::text
       AND split_part(p_nome, '/', 3) = a.agendamentoid::text
       AND split_part(p_nome, '/', 4) <> ''
       AND public.pode('agenda.ver', a.lojaid))
$$;
REVOKE ALL ON FUNCTION public.anexo_da_agenda_do_gerente(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.anexo_da_agenda_do_gerente(text) TO authenticated;

-- As regras do Storage: SÓ leitura, presas à conta do gerente pela primeira
-- pasta e à linha do banco pela função acima.
DROP POLICY IF EXISTS entregas_sel_gerente ON storage.objects;
CREATE POLICY entregas_sel_gerente ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'entregas'
         AND split_part(name, '/', 1) = ((SELECT public.conta_do_gerente()))::text
         AND public.foto_de_entrega_do_gerente(name));
DROP POLICY IF EXISTS agendamentos_arq_sel_gerente ON storage.objects;
CREATE POLICY agendamentos_arq_sel_gerente ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'agendamentos'
         AND split_part(name, '/', 1) = ((SELECT public.conta_do_gerente()))::text
         AND public.anexo_da_agenda_do_gerente(name));

-- O recibo do resgate: o master segue pelo caminho de sempre (regras das
-- tabelas); o gerente, pela versão que lê só resgates das lojas em que ele vê
-- os Prêmios.
CREATE OR REPLACE FUNCTION public.recibo_resgate_gerente(p_resgateid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nomefantasia AS conta
      FROM public.resgates r
      JOIN public.funcionarios f ON f.funcionarioid = r.funcionarioid
      JOIN public.produtosloja p ON p.produtoid = r.produtoid
      JOIN public.contas c       ON c.contaid = r.contaid
      LEFT JOIN public.lojas l   ON l.lojaid = r.lojaid
     WHERE r.resgateid = p_resgateid
       AND r.contaid = public.conta_do_gerente()
       AND r.lojaid IS NOT NULL AND public.pode('premios.ver', r.lojaid)
  ),
  mov AS (
    SELECT m.movimentoid, m.datamovimento, m.tipo, m.pontos, m.descricao,
           (SELECT coalesce(sum(x.pontos), 0) FROM public.movimentospontos x
             WHERE x.funcionarioid = m.funcionarioid AND x.movimentoid < m.movimentoid) AS saldoantes
      FROM public.movimentospontos m
     WHERE m.resgateid = p_resgateid AND m.contaid = public.conta_do_gerente()
  )
  SELECT jsonb_build_object(
           'conta', r.conta, 'loja', r.loja, 'pessoa', r.nomecompleto,
           'premio', CASE WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda de ' || public.reais(r.valorreais) ELSE r.premio END,
           'pontos', r.pontosgastos, 'situacao', r.status, 'solicitadoem', r.datasolicitacao,
           'entregueem', r.dataentrega, 'protocolo', 'R-' || r.resgateid,
           'movimentos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                             'data', datamovimento, 'tipo', tipo, 'pontos', pontos, 'descricao', descricao,
                             'saldoantes', saldoantes, 'saldodepois', saldoantes + pontos) ORDER BY movimentoid), '[]'::jsonb)
                            FROM mov))
    FROM r
$function$;
REVOKE ALL ON FUNCTION public.recibo_resgate_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.recibo_resgate_gerente(integer) TO authenticated;

-- recibo_resgate: parte da versão viva; o master, igual; o gerente, desviado.
CREATE OR REPLACE FUNCTION public.recibo_resgate(p_resgateid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.recibo_resgate_gerente(p_resgateid);
  END IF;
  RETURN (
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nomefantasia AS conta
      FROM public.resgates r
      JOIN public.funcionarios f ON f.funcionarioid = r.funcionarioid
      JOIN public.produtosloja p ON p.produtoid = r.produtoid
      JOIN public.contas c       ON c.contaid = r.contaid
      LEFT JOIN public.lojas l   ON l.lojaid = r.lojaid
     WHERE r.resgateid = p_resgateid
  ),
  mov AS (
    SELECT m.movimentoid, m.datamovimento, m.tipo, m.pontos, m.descricao,
           (SELECT coalesce(sum(x.pontos), 0) FROM public.movimentospontos x
             WHERE x.funcionarioid = m.funcionarioid AND x.movimentoid < m.movimentoid) AS saldoantes
      FROM public.movimentospontos m
     WHERE m.resgateid = p_resgateid
  )
  SELECT jsonb_build_object(
           'conta', r.conta, 'loja', r.loja, 'pessoa', r.nomecompleto,
           'premio', CASE WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda de ' || public.reais(r.valorreais) ELSE r.premio END,
           'pontos', r.pontosgastos, 'situacao', r.status, 'solicitadoem', r.datasolicitacao,
           'entregueem', r.dataentrega, 'protocolo', 'R-' || r.resgateid,
           'movimentos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                             'data', datamovimento, 'tipo', tipo, 'pontos', pontos, 'descricao', descricao,
                             'saldoantes', saldoantes, 'saldodepois', saldoantes + pontos) ORDER BY movimentoid), '[]'::jsonb)
                            FROM mov))
    FROM r
  );
END;
$function$;

COMMIT;
