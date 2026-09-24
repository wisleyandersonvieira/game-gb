-- Etapa 1.12, parte B1 — a tela Ranking passa a ler o fechamento (24/09/2026).
--
-- Decisão do Wisley: mês já fechado vem do fechamento; mês aberto continua
-- sendo calculado ao vivo. Antes, a tela Ranking recalculava qualquer mês, e
-- uma mudança de regra (como "quem pega assume", da parte B1a) mexia em meses
-- antigos — a tela Ranking e a tela "Meses fechados" podiam mostrar números
-- diferentes para o mesmo mês.

-- Qual fechamento vale para este mês, na conta de quem está perguntando.
-- Nada de SECURITY DEFINER: a RLS de fechamentosmensais já filtra a conta, e
-- o filtro está explícito de novo aqui.
CREATE OR REPLACE FUNCTION public.fechamento_valendo(p_ano integer, p_mes integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT f.fechamentoid
    FROM public.fechamentosmensais f
   WHERE f.contaid = (select public.minha_conta())
     AND f.ano = p_ano AND f.mes = p_mes
     AND f.situacao <> 'substituido'
   ORDER BY f.versao DESC
   LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.ranking_mensal(p_ano integer, p_mes integer, p_lojaid integer DEFAULT NULL)
RETURNS TABLE (
  funcionarioid   integer,
  nomecompleto    varchar,
  pontosganhos    integer,
  pontosregulares integer,
  pontospossiveis integer,
  confiabilidade  numeric,
  esforco         numeric,
  nota            numeric
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fechamento integer := public.fechamento_valendo(p_ano, p_mes);
BEGIN
  IF v_fechamento IS NOT NULL THEN
    -- Mês fechado: os números estão congelados. É a mesma fonte da tela
    -- "Meses fechados", então as duas nunca discordam.
    RETURN QUERY
      SELECT h.funcionarioid, h.nomefuncionario, h.pontosganhos,
             coalesce(h.pontosregulares, 0), h.pontospossiveis,
             coalesce(h.confiabilidade, 0), coalesce(h.esforco, 0), coalesce(h.nota, 0)
        FROM public.historicoranking h
       WHERE h.fechamentoid = v_fechamento
         AND h.lojaid IS NOT DISTINCT FROM p_lojaid
       ORDER BY h.posicao;
  ELSE
    -- Mês aberto: ao vivo, até ontem.
    RETURN QUERY
      SELECT * FROM public.ranking_mensal_da_conta(public.minha_conta(), p_ano, p_mes, p_lojaid,
                                                   public.dia_em_sao_paulo(now()) - 1);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fechamento_valendo(integer, integer)      FROM public, anon;
REVOKE ALL ON FUNCTION public.ranking_mensal(integer, integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fechamento_valendo(integer, integer)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.ranking_mensal(integer, integer, integer) TO authenticated;
