-- =========================================================================
-- STGame — Intervalo do Mapa por dia da semana; a semana numa consulta só.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema (a expansão só roda uma vez).
--
-- ATENÇÃO: aplique ANTES o aplicar-teto-fotos-e-agenda.sql. Aplique ESTE
-- ARQUIVO antes de publicar a versão nova: a tela grava o intervalo com o dia.
--
-- Este arquivo é UMA migração só:
--   20260929233000_intervalo_do_mapa_por_dia.sql
--
-- O QUE MUDA PARA QUEM JÁ USA (nada na tela):
--   * Só a tabela do intervalo do Mapa é tocada: cada intervalo vira um por
--     dia em que a pessoa trabalha, com o mesmo horário. Provado: 420
--     pessoa-dia, 0 diferenças no que a tela mostra; aplicar de novo não
--     duplica.
--   * Continua só planejamento: nenhuma outra função lê esse intervalo.
-- =========================================================================


BEGIN;

-- Intervalo do Mapa POR DIA da semana (29/09/2026, pedido do Wisley).
--
-- Antes: um intervalo de planejamento por pessoa, igual em todos os dias.
-- Agora: um por pessoa e por dia da semana (o de domingo, o de segunda...).
--
-- O que é tocado: SÓ a tabela intervalosdomapa. Cada intervalo que existe
-- vira uma linha por dia em que a pessoa trabalha (dia com horário na
-- jornada dela e que não é a folga semanal), com o mesmo horário — a tela
-- continua mostrando exatamente o que mostrava. Quem tem intervalo e nenhum
-- dia de trabalho fica com ele nos sete dias (não se perde; e não aparece em
-- lugar nenhum, igual a antes). Aplicar duas vezes não duplica: a expansão só
-- roda enquanto houver linha sem dia.
--
-- Continua sendo SÓ planejamento: não cala o bot, não mexe em tarefa,
-- liberação, nota nem rodízio. Só mapa_da_jornada e salvar_intervalo_do_mapa
-- leem ou gravam a tabela (seção 75 do teste de isolamento).

-- ---------------------------------------------------------------------------
-- 1. A coluna do dia e a expansão (uma vez só)
-- ---------------------------------------------------------------------------
ALTER TABLE public.intervalosdomapa ADD COLUMN IF NOT EXISTS diasemana smallint;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.intervalosdomapa WHERE diasemana IS NULL) THEN
    -- A chave antiga (uma linha por pessoa) sai antes de a pessoa ganhar
    -- uma linha por dia.
    ALTER TABLE public.intervalosdomapa DROP CONSTRAINT IF EXISTS intervalosdomapa_pkey;

    INSERT INTO public.intervalosdomapa (contaid, funcionarioid, diasemana, inicio, fim, atualizadoem)
    SELECT i.contaid, i.funcionarioid, d.dia, i.inicio, i.fim, i.atualizadoem
      FROM public.intervalosdomapa i
      JOIN public.funcionarios f ON f.contaid = i.contaid AND f.funcionarioid = i.funcionarioid
     CROSS JOIN LATERAL (
       SELECT jd.diasemana AS dia FROM public.jornadasdias jd
        WHERE jd.contaid = f.contaid AND jd.jornadaid = f.jornadaid
          AND jd.diasemana <> coalesce(f.diadefolga, 0)
       UNION
       -- Sem nenhum dia de trabalho: os sete, para não perder o intervalo.
       SELECT g::smallint FROM generate_series(1, 7) g
        WHERE NOT EXISTS (SELECT 1 FROM public.jornadasdias jd
                           WHERE jd.contaid = f.contaid AND jd.jornadaid = f.jornadaid
                             AND jd.diasemana <> coalesce(f.diadefolga, 0))
     ) d
     WHERE i.diasemana IS NULL;

    DELETE FROM public.intervalosdomapa WHERE diasemana IS NULL;
  END IF;
END $$;

ALTER TABLE public.intervalosdomapa ALTER COLUMN diasemana SET NOT NULL;
ALTER TABLE public.intervalosdomapa DROP CONSTRAINT IF EXISTS intervalosdomapa_dia_valido;
ALTER TABLE public.intervalosdomapa ADD CONSTRAINT intervalosdomapa_dia_valido CHECK (diasemana BETWEEN 1 AND 7);
ALTER TABLE public.intervalosdomapa DROP CONSTRAINT IF EXISTS intervalosdomapa_pkey;
ALTER TABLE public.intervalosdomapa ADD CONSTRAINT intervalosdomapa_pkey PRIMARY KEY (contaid, funcionarioid, diasemana);
COMMENT ON COLUMN public.intervalosdomapa.diasemana IS
  '1 = domingo ... 7 = sábado. Cada dia da semana tem o seu intervalo de planejamento.';

-- ---------------------------------------------------------------------------
-- 2. O mapa lê o intervalo do dia escolhido
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929210000_mapa_da_jornada.sql), com o
-- diff conferido: só o dia no encontro com o intervalo.
CREATE OR REPLACE FUNCTION public.mapa_da_jornada(p_lojaid integer, p_diasemana integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := (public.meu_hoje()->>'hoje')::date;
  v_dia  integer := coalesce(p_diasemana, extract(dow FROM v_hoje)::integer + 1);
  v_loja text;
BEGIN
  IF v_dia NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT l.nome INTO v_loja FROM public.lojas l WHERE l.lojaid = p_lojaid;

  RETURN jsonb_build_object(
    'diasemana', v_dia,
    'hoje', v_hoje,
    'loja', v_loja,
    'pessoas', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'funcionarioid', f.funcionarioid,
               'nome', f.nomecompleto,
               'cargo', f.cargo,
               -- A mesma ordem de dia_de_trabalho: afastamento e folga
               -- vencem o horário.
               'situacao', CASE
                 WHEN f.datainicioafastamento IS NOT NULL AND f.datafimafastamento IS NOT NULL
                      AND v_hoje BETWEEN f.datainicioafastamento AND f.datafimafastamento THEN 'afastado'
                 WHEN f.diadefolga = v_dia THEN 'folga'
                 WHEN f.jornadaid IS NULL THEN 'sem_jornada'
                 WHEN jd.entrada IS NULL THEN 'sem_horario'
                 ELSE 'trabalha' END,
               'afastadoate', f.datafimafastamento,
               -- Domingo de folga do mês (1º, 2º...): só avisa no mapa de domingo.
               'domingofolga', CASE WHEN v_dia = 1 AND coalesce(f.domingofolgamensal, 0) > 0
                                    THEN f.domingofolgamensal END,
               'entrada', to_char(jd.entrada, 'HH24:MI'),
               'saida', to_char(jd.saida, 'HH24:MI'),
               'intervaloinicio', to_char(im.inicio, 'HH24:MI'),
               'intervalofim', to_char(im.fim, 'HH24:MI'))
             ORDER BY jd.entrada NULLS LAST, f.nomecompleto)
        FROM public.funcionarioslojas fl
        JOIN public.funcionarios f
          ON f.contaid = fl.contaid AND f.funcionarioid = fl.funcionarioid AND f.ativo
        LEFT JOIN public.jornadasdias jd
          ON jd.contaid = f.contaid AND jd.jornadaid = f.jornadaid AND jd.diasemana = v_dia
        -- 29/09/2026: o intervalo é do DIA da semana escolhido.
        LEFT JOIN public.intervalosdomapa im
          ON im.contaid = f.contaid AND im.funcionarioid = f.funcionarioid AND im.diasemana = v_dia
       WHERE fl.lojaid = p_lojaid AND fl.ativo), '[]'::jsonb));
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. A semana inteira numa consulta só (para o PDF da semana)
-- ---------------------------------------------------------------------------
-- Uma ida ao banco: os sete dias saem juntos. SECURITY INVOKER: cada conta
-- só enxerga a dela, como no mapa do dia.
CREATE OR REPLACE FUNCTION public.mapa_da_semana(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'loja', (SELECT l.nome FROM public.lojas l WHERE l.lojaid = p_lojaid),
    'dias', jsonb_agg(public.mapa_da_jornada(p_lojaid, d) ORDER BY d))
    FROM generate_series(1, 7) d
$$;
REVOKE ALL ON FUNCTION public.mapa_da_semana(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_da_semana(integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Gravar (ou tirar) o intervalo de UM dia
-- ---------------------------------------------------------------------------
-- A versão sem dia sai: deixá-la viva gravaria sem saber de que dia é.
DROP FUNCTION IF EXISTS public.salvar_intervalo_do_mapa(integer, time, time);

CREATE OR REPLACE FUNCTION public.salvar_intervalo_do_mapa(p_funcionarioid integer, p_diasemana integer,
                                                           p_inicio time, p_fim time)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel();
BEGIN
  IF p_diasemana IS NULL OR p_diasemana NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND ativo) THEN
    RAISE EXCEPTION 'Colaborador não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF p_inicio IS NULL AND p_fim IS NULL THEN
    DELETE FROM public.intervalosdomapa
     WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND diasemana = p_diasemana;
    RETURN;
  END IF;
  IF p_inicio IS NULL OR p_fim IS NULL THEN
    RAISE EXCEPTION 'Preencha o começo e o fim do intervalo (ou tire o intervalo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_inicio = p_fim THEN
    RAISE EXCEPTION 'O começo e o fim do intervalo são iguais.' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.intervalosdomapa (contaid, funcionarioid, diasemana, inicio, fim)
  VALUES (v_conta, p_funcionarioid, p_diasemana, p_inicio, p_fim)
  ON CONFLICT (contaid, funcionarioid, diasemana)
  DO UPDATE SET inicio = EXCLUDED.inicio, fim = EXCLUDED.fim, atualizadoem = now();
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_intervalo_do_mapa(integer, integer, time, time) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.salvar_intervalo_do_mapa(integer, integer, time, time) TO authenticated;

COMMIT;
