-- CLASSIFICAÇÃO: ACRESCENTA
-- (muda por dentro duas funções do Mapa, sem mudar o que recebem; o mapa
-- ganha um campo novo, que o site no ar ignora.)
--
-- O Mapa da jornada para o gerente (30/09/2026, item 5 da jornada por loja):
-- com "Jornada: mapa e exportar" numa loja, ele marca o intervalo de quem
-- tem uma loja em comum com ele (planejamento do dia a dia), nunca o próprio.
-- O mapa diz à tela se quem vê pode marcar e exportar naquela loja (podemapa).
-- Continua valendo: o intervalo do mapa só existe para enxergar e imprimir;
-- nenhuma regra do sistema o lê (bot, tarefa, liberação, nota, rodízio). As
-- duas únicas funções que tocam intervalosdomapa continuam sendo estas.

-- salvar_intervalo_do_mapa: parte da versão viva.
CREATE OR REPLACE FUNCTION public.salvar_intervalo_do_mapa(p_funcionarioid integer, p_diasemana integer, p_inicio time without time zone, p_fim time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- O gerente: só quem tem uma loja em comum com ele, onde ele pode mexer no
  -- Mapa; nunca o próprio intervalo (30/09/2026).
  IF NOT v_master THEN
    IF NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                    WHERE fl.contaid = v_conta AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                      AND public.pode('jornada.mapa', fl.lojaid)) THEN
      RAISE EXCEPTION 'Marcar o intervalo desta pessoa não está liberado para o seu cargo (ela não é de uma loja em que você mexe no Mapa).'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
      RAISE EXCEPTION 'Você não marca o seu próprio intervalo.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
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
$function$;

-- mapa_da_jornada: parte da versão viva; só o campo podemapa é novo.
CREATE OR REPLACE FUNCTION public.mapa_da_jornada(p_lojaid integer, p_diasemana integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- A conta: a do master, ou a do gerente que vê a Jornada nesta loja. As
  -- regras das tabelas faziam esse corte para o master; agora é explícito.
  v_conta integer := CASE WHEN public.sou_master() THEN public.minha_conta()
                          WHEN public.conta_do_gerente() IS NOT NULL AND public.pode('jornada.ver', p_lojaid)
                          THEN public.conta_do_gerente() END;
  v_hoje date := CASE WHEN public.sou_master() THEN (public.meu_hoje()->>'hoje')::date
                      ELSE public.hoje_da_conta(public.conta_do_gerente()) END;
  v_dia  integer := coalesce(p_diasemana, extract(dow FROM v_hoje)::integer + 1);
  v_loja text;
BEGIN
  IF v_dia NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT l.nome INTO v_loja FROM public.lojas l WHERE l.lojaid = p_lojaid AND l.contaid = v_conta;

  RETURN jsonb_build_object(
    'diasemana', v_dia,
    'hoje', v_hoje,
    'loja', v_loja,
    -- Quem vê pode marcar o intervalo e exportar nesta loja? (30/09/2026)
    'podemapa', v_conta IS NOT NULL AND (public.sou_master() OR public.pode('jornada.mapa', p_lojaid)),
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
       WHERE fl.contaid = v_conta AND fl.lojaid = p_lojaid AND fl.ativo), '[]'::jsonb));
END;
$function$;
