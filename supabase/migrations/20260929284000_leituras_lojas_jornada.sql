-- Usuários gerenciais, PARTE 4, fatia 10: Lojas, Jornada e o nome da conta
-- no topo (30/09/2026).
--
-- As telas liam as tabelas direto e vinham vazias para o gerente. Agora:
--   * o topo mostra o NOME da conta para quem entra (master ou gerente);
--   * Lojas ("Lojas: ver"): as lojas dele, o resumo delas, as pessoas de cada
--     uma; os links de TV com "Lojas: TV"; o som do tablet com "Lojas: som do
--     tablet". Os dados de cadastro da conta (e-mail, telefone, limite de
--     lojas) continuam só do master;
--   * Jornada ("Jornada: ver"): o catálogo de jornadas da conta (só
--     leitura), as pessoas e os vínculos das lojas dele, e o MAPA: a própria
--     mapa_da_jornada passa a servir o gerente (é ela, e só ela, que lê o
--     intervalo de planejamento — a regra do CLAUDE.md continua valendo).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- O nome da conta, para o topo.
CREATE OR REPLACE FUNCTION public.nome_da_conta()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.nomefantasia::text FROM public.contas c
   WHERE c.contaid = CASE WHEN public.sou_master() THEN public.minha_conta() ELSE public.conta_do_gerente() END
$$;
REVOKE ALL ON FUNCTION public.nome_da_conta() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.nome_da_conta() TO authenticated;

-- A conta na tela de Lojas: o master, o cadastro todo; o gerente, só o nome.
CREATE OR REPLACE FUNCTION public.conta_da_gestao()
RETURNS TABLE(contaid integer, nome character varying, nomefantasia character varying, email character varying,
              telefone character varying, cidade character varying, limitelojas integer, status character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.contaid, c.nome, c.nomefantasia, c.email, c.telefone, c.cidade, c.limitelojas, c.status
    FROM public.contas c
   WHERE public.sou_master() AND c.contaid = public.minha_conta()
  UNION ALL
  SELECT c.contaid, c.nome, c.nomefantasia, NULL, NULL, NULL, NULL, NULL
    FROM public.contas c
   WHERE NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
     AND cardinality((SELECT public.lojas_onde_posso('lojas.ver'))::integer[]) > 0
$$;
REVOKE ALL ON FUNCTION public.conta_da_gestao() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_da_gestao() TO authenticated;

-- As lojas na tela de Lojas.
CREATE OR REPLACE FUNCTION public.lojas_da_gestao()
RETURNS TABLE(lojaid integer, nome character varying, cidade character varying, endereco character varying, ativa boolean,
              gestorid integer, responsavelagendamentosid integer, mostrarvalorestv boolean, tvblocos jsonb, tvsegundos integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.lojaid, l.nome, l.cidade, l.endereco, l.ativa, l.gestorid, l.responsavelagendamentosid, l.mostrarvalorestv,
         l.tvblocos, l.tvsegundos
    FROM public.lojas l
   WHERE (public.sou_master() AND l.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND l.contaid = public.conta_do_gerente()
          AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('lojas.ver'))::integer[]))
   ORDER BY l.nome, l.lojaid
$$;
REVOKE ALL ON FUNCTION public.lojas_da_gestao() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.lojas_da_gestao() TO authenticated;

-- Os links de TV.
CREATE OR REPLACE FUNCTION public.links_de_tv()
RETURNS TABLE(linktvid integer, lojaid integer, nome character varying, criadoem timestamptz, revogadoem timestamptz, ultimouso timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.linktvid, t.lojaid, t.nome, t.criadoem, t.revogadoem, t.ultimouso
    FROM public.linkstv t
   WHERE (public.sou_master() AND t.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND t.contaid = public.conta_do_gerente()
          AND t.lojaid = ANY ((SELECT public.lojas_onde_posso('lojas.tv'))::integer[]))
   ORDER BY t.criadoem DESC, t.linktvid DESC
$$;
REVOKE ALL ON FUNCTION public.links_de_tv() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.links_de_tv() TO authenticated;

-- O som do tablet de uma loja.
CREATE OR REPLACE FUNCTION public.som_da_loja(p_lojaid integer)
RETURNS TABLE(somtarefanova boolean, somvolume integer, somrepetirminutos integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.somtarefanova, l.somvolume, l.somrepetirminutos
    FROM public.lojas l
   WHERE l.lojaid = p_lojaid
     AND ((public.sou_master() AND l.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND l.contaid = public.conta_do_gerente() AND public.pode('lojas.tablet_som', p_lojaid)))
$$;
REVOKE ALL ON FUNCTION public.som_da_loja(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.som_da_loja(integer) TO authenticated;

-- Os vínculos pessoa-loja de uma tela (o gerente: só com as lojas dele).
CREATE OR REPLACE FUNCTION public.vinculos_para(p_codigo text)
RETURNS TABLE(funcionarioid integer, lojaid integer, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fl.funcionarioid, fl.lojaid, fl.ativo
    FROM public.funcionarioslojas fl
   WHERE (public.sou_master() AND fl.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND fl.contaid = public.conta_do_gerente()
          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso(p_codigo))::integer[]))
   ORDER BY fl.funcionarioid, fl.lojaid
$$;
REVOKE ALL ON FUNCTION public.vinculos_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.vinculos_para(text) TO authenticated;

-- As jornadas com os horários (catálogo da conta, só leitura).
CREATE OR REPLACE FUNCTION public.jornadas_da_tela()
RETURNS TABLE(jornadaid integer, nome character varying, pausainicio time, pausafim time, observacao text, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT j.jornadaid, j.nome, j.pausainicio, j.pausafim, j.observacao, j.ativa
    FROM public.jornadas j
   WHERE (public.sou_master() AND j.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('jornada.ver'))::integer[]) > 0)
   ORDER BY j.nome, j.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.jornadas_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.dias_das_jornadas()
RETURNS TABLE(jornadaid integer, diasemana smallint, entrada time, saida time)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT d.jornadaid, d.diasemana, d.entrada, d.saida
    FROM public.jornadasdias d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente()
          AND cardinality((SELECT public.lojas_onde_posso('jornada.ver'))::integer[]) > 0)
   ORDER BY d.jornadaid, d.diasemana
$$;
REVOKE ALL ON FUNCTION public.dias_das_jornadas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dias_das_jornadas() TO authenticated;

-- O resumo das lojas, para o gerente: só as dele.
CREATE OR REPLACE FUNCTION public.resumo_das_lojas_gerente()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gerente();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
             jsonb_build_object(
               'lojaid',    l.lojaid,
               'nome',      l.nome,
               'progresso', p.painel->'progresso',
               'pendentes', p.painel->'pendentes',
               'lider',     p.painel->'podio'->0)
             ORDER BY l.nome), '[]'::jsonb)
      FROM public.lojas l
      CROSS JOIN LATERAL (SELECT public.montar_painel(v_conta, l.lojaid, false) AS painel) p
     WHERE l.contaid = v_conta AND l.ativa
       AND l.lojaid = ANY ((SELECT public.lojas_onde_posso('lojas.ver'))::integer[])
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.resumo_das_lojas_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.resumo_das_lojas_gerente() TO authenticated;

-- resumo_das_lojas: parte da versão viva (de 20260921130000_painel_e_modo_tv.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.resumo_das_lojas()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.minha_conta();
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.resumo_das_lojas_gerente();
  END IF;
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
             jsonb_build_object(
               'lojaid',    l.lojaid,
               'nome',      l.nome,
               'progresso', p.painel->'progresso',
               'pendentes', p.painel->'pendentes',
               'lider',     p.painel->'podio'->0)
             ORDER BY l.nome), '[]'::jsonb)
      FROM public.lojas l
      CROSS JOIN LATERAL (SELECT public.montar_painel(v_conta, l.lojaid, false) AS painel) p
     WHERE l.contaid = v_conta AND l.ativa
  );
END;
$function$;

-- mapa_da_jornada: parte da versão viva (de 20260929233000_intervalo_do_mapa_por_dia.sql); serve também o gerente.
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

-- mapa_da_semana: parte da versão viva (de 20260929233000_intervalo_do_mapa_por_dia.sql); o nome da loja, pela mesma regra.
CREATE OR REPLACE FUNCTION public.mapa_da_semana(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'loja', (SELECT l.nome FROM public.lojas l
              WHERE l.lojaid = p_lojaid
                AND l.contaid = CASE WHEN public.sou_master() THEN public.minha_conta()
                                     WHEN public.pode('jornada.ver', p_lojaid) THEN public.conta_do_gerente() END),
    'dias', jsonb_agg(public.mapa_da_jornada(p_lojaid, d) ORDER BY d))
    FROM generate_series(1, 7) d
$function$;
