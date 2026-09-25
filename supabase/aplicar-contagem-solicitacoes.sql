-- =========================================================================
-- STGame — as marcações de quantidade em Solicitações.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929110000_contagem_solicitacoes.sql
--
-- O QUE MUDA PARA QUEM JÁ USA: nada nos dados. Entra um índice novo (só
-- acelera a consulta) e uma função nova, que devolve quantas solicitações
-- ainda esperam alguém, por loja. É o que alimenta a bolinha vermelha do
-- menu e os números nas abas da tela de Solicitações.
-- =========================================================================

BEGIN;

-- Contagem das solicitações que ainda esperam alguém.
--
-- Serve às duas marcações de quantidade da tela de Solicitações: a bandeirinha
-- vermelha do menu lateral, que soma TODAS as lojas que o gestor enxerga, e os
-- números das abas, que são só da loja do seletor do topo.
--
-- As duas saem da MESMA resposta, de propósito. O menu acompanha todas as
-- telas: se cada marcação tivesse a sua consulta, trocar de tela viraria três
-- ou quatro idas ao banco. Aqui é uma só, guardada 30 s pela mesma chave de
-- cache no menu e na página (src/ui/pendencias.ts).
--
-- A conta é feita DENTRO do banco: volta um número por loja e por situação,
-- nunca a linha da solicitação. Uma conta com milhares de pedidos devolve o
-- mesmo punhado de linhas de contagem.
--
-- Só entram lojas ativas: o seletor do topo também só oferece essas, e um
-- pedido antigo de loja desativada não pode ficar cobrando o gestor para
-- sempre numa loja onde ele não consegue nem entrar.
--
-- E é SECURITY INVOKER de propósito: quem filtra a conta é a RLS da própria
-- tabela, exatamente como na tela. A função não recebe contaid nem lojaid,
-- então não há o que forjar pelo navegador.

-- Índice parcial: só as situações que a gente conta. Ele é pequeno (as
-- concluídas e recusadas, que são a maioria com o tempo, ficam de fora) e
-- responde a contagem sem varrer a tabela.
CREATE INDEX IF NOT EXISTS solicitacoesinternas_a_resolver_idx
  ON public.solicitacoesinternas (contaid, lojaid, status)
  WHERE status IN ('Aberta', 'Em andamento');

CREATE OR REPLACE FUNCTION public.contagem_solicitacoes()
RETURNS TABLE (loja integer, situacao text, quantos integer)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT s.lojaid, s.status::text, count(*)::integer
  FROM public.solicitacoesinternas s
  JOIN public.lojas l ON l.lojaid = s.lojaid AND l.ativa
  WHERE s.status IN ('Aberta', 'Em andamento')
  GROUP BY s.lojaid, s.status;
$$;

COMMENT ON FUNCTION public.contagem_solicitacoes() IS
  'Quantas solicitações estão Aberta ou Em andamento, por loja. Uma resposta só para a bandeirinha do menu e para os números das abas.';

REVOKE ALL ON FUNCTION public.contagem_solicitacoes() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.contagem_solicitacoes() TO authenticated;

COMMIT;
