-- Mapa da jornada (27/09/2026): quem está em expediente em cada hora de um
-- dia da semana, numa loja, com o total por hora. Fase 2 ("mapa"), feito a
-- pedido explícito do Wisley.
--
-- ENQUADRAMENTO (CLAUDE.md: "o STGame não controla jornada"). O mapa é
-- PLANEJAMENTO de escala, montado só com o que está cadastrado (jornada e
-- folga). Não olha hora nenhuma de verdade: não há "agora", marcação de
-- entrada e saída, nem comparação entre previsto e feito.
--
-- O INTERVALO DO MAPA é outra coisa que o intervalo da jornada:
--   * jornadas.pausainicio/pausafim = silêncio do bot (continua igual);
--   * intervalosdomapa = só para enxergar e imprimir a escala. NÃO cala o
--     bot, não mexe em tarefa, liberação, nota nem rodízio. Só as duas
--     funções desta migração leem ou gravam a tabela, e o teste de
--     isolamento (seção 75) reprova qualquer outra que passe a ler.
--
-- Nenhuma função existente muda: esta migração só ACRESCENTA.

-- ---------------------------------------------------------------------------
-- 1. A tabela: um intervalo de planejamento por pessoa
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.intervalosdomapa (
  contaid        integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  funcionarioid  integer NOT NULL,
  -- Fim menor que o começo: cruza a meia-noite (turno da noite).
  inicio         time NOT NULL,
  fim            time NOT NULL,
  atualizadoem   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contaid, funcionarioid),
  CONSTRAINT intervalosdomapa_pessoa_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE CASCADE,
  CONSTRAINT intervalosdomapa_valido CHECK (inicio <> fim)
);
COMMENT ON TABLE public.intervalosdomapa IS
  'Intervalo de PLANEJAMENTO do mapa da jornada, um por pessoa. Só para enxergar e imprimir a escala: não afeta o sistema (bot, tarefas, liberação, nota, rodízio). Não confundir com jornadas.pausainicio/pausafim, o silêncio do bot. Nível conta.';

ALTER TABLE public.intervalosdomapa ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.intervalosdomapa FROM anon, authenticated;
-- Lê direto (pela função do mapa, que respeita esta regra); grava só por
-- salvar_intervalo_do_mapa.
GRANT SELECT ON public.intervalosdomapa TO authenticated;
GRANT ALL ON public.intervalosdomapa TO service_role;
DROP POLICY IF EXISTS intervalosdomapa_sel ON public.intervalosdomapa;
CREATE POLICY intervalosdomapa_sel ON public.intervalosdomapa FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- ---------------------------------------------------------------------------
-- 2. O mapa de uma loja num dia da semana, numa consulta só
-- ---------------------------------------------------------------------------
-- SECURITY INVOKER: quem chama só enxerga a própria conta (a regra de cada
-- tabela vale aqui dentro). p_diasemana: 1 = domingo ... 7 = sábado; vazio =
-- o dia da semana de hoje, na conta.
--
-- O turno é do dia em que COMEÇA: o mapa de segunda mostra quem entra na
-- segunda, inclusive a parte depois da meia-noite do turno da noite.
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
        LEFT JOIN public.intervalosdomapa im
          ON im.contaid = f.contaid AND im.funcionarioid = f.funcionarioid
       WHERE fl.lojaid = p_lojaid AND fl.ativo), '[]'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.mapa_da_jornada(integer, integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_da_jornada(integer, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Gravar (ou tirar) o intervalo do mapa de uma pessoa
-- ---------------------------------------------------------------------------
-- Não recebe conta: é a de quem chamou (e só o master grava). Começo e fim
-- vazios = tira o intervalo.
CREATE OR REPLACE FUNCTION public.salvar_intervalo_do_mapa(p_funcionarioid integer, p_inicio time, p_fim time)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND ativo) THEN
    RAISE EXCEPTION 'Colaborador não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF p_inicio IS NULL AND p_fim IS NULL THEN
    DELETE FROM public.intervalosdomapa WHERE contaid = v_conta AND funcionarioid = p_funcionarioid;
    RETURN;
  END IF;
  IF p_inicio IS NULL OR p_fim IS NULL THEN
    RAISE EXCEPTION 'Preencha o começo e o fim do intervalo (ou tire o intervalo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_inicio = p_fim THEN
    RAISE EXCEPTION 'O começo e o fim do intervalo são iguais.' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.intervalosdomapa (contaid, funcionarioid, inicio, fim)
  VALUES (v_conta, p_funcionarioid, p_inicio, p_fim)
  ON CONFLICT (contaid, funcionarioid)
  DO UPDATE SET inicio = EXCLUDED.inicio, fim = EXCLUDED.fim, atualizadoem = now();
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_intervalo_do_mapa(integer, time, time) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.salvar_intervalo_do_mapa(integer, time, time) TO authenticated;
