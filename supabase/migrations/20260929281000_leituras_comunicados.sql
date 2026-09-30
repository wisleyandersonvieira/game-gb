-- Usuários gerenciais, PARTE 4, fatia 7: Comunicados (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Agora, com
-- "Comunicados: ver", ele vê o comunicado que chega às lojas dele:
--   * alvo "conta inteira": chega a todas as lojas, ele vê;
--   * alvo "lojas": se alguma das lojas escolhidas é dele;
--   * alvo "pessoas": só se TODA pessoa escolhida tem uma loja dele (se
--     alguma é só de outra loja, o comunicado não é dele).
-- As ciências: só de quem tem uma loja dele (nunca a situação de quem é só
-- de outra loja). O recibo de ciência, a lista de quem falta dar ciência e as
-- lojas e pessoas do formulário, pelas mesmas regras.
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

-- O comunicado chega às lojas do gerente? (interna: só as funções abaixo usam)
CREATE OR REPLACE FUNCTION public.comunicado_do_gerente(p_documentoid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ctx AS MATERIALIZED (
    SELECT public.conta_do_gerente() AS conta, (SELECT public.lojas_onde_posso('comunicados.ver'))::integer[] AS lojas
  )
  SELECT coalesce((
    SELECT CASE d.alvo
             WHEN 'conta' THEN cardinality(ctx.lojas) > 0
             WHEN 'lojas' THEN EXISTS (SELECT 1 FROM public.documentoslojas dl
                                        WHERE dl.contaid = ctx.conta AND dl.documentoid = d.documentoid AND dl.lojaid = ANY (ctx.lojas))
             ELSE EXISTS (SELECT 1 FROM public.documentosassinaturas s WHERE s.contaid = ctx.conta AND s.documentoid = d.documentoid)
                  AND NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                                   WHERE s.contaid = ctx.conta AND s.documentoid = d.documentoid
                                     AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                                      WHERE fl.contaid = ctx.conta AND fl.funcionarioid = s.funcionarioid
                                                        AND fl.ativo AND fl.lojaid = ANY (ctx.lojas)))
           END
      FROM public.documentos d, ctx
     WHERE d.documentoid = p_documentoid AND d.contaid = ctx.conta), false)
$$;
REVOKE ALL ON FUNCTION public.comunicado_do_gerente(integer) FROM public, anon, authenticated;

-- A pessoa tem uma loja em que o gerente vê Comunicados? (interna)
CREATE OR REPLACE FUNCTION public.pessoa_nos_comunicados_do_gerente(p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = public.conta_do_gerente() AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                    AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[]))
$$;
REVOKE ALL ON FUNCTION public.pessoa_nos_comunicados_do_gerente(integer) FROM public, anon, authenticated;

-- Os comunicados da tela.
CREATE OR REPLACE FUNCTION public.comunicados_da_tela()
RETURNS TABLE(documentoid integer, titulo character varying, conteudo text, pontosporciencia integer, datacriacao timestamptz,
              status character varying, alvo character varying, primeiracienciaem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT d.documentoid, d.titulo, d.conteudo, d.pontosporciencia, d.datacriacao, d.status, d.alvo, d.primeiracienciaem
    FROM public.documentos d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente() AND public.comunicado_do_gerente(d.documentoid))
   ORDER BY d.datacriacao DESC, d.documentoid DESC
   LIMIT 300
$$;
REVOKE ALL ON FUNCTION public.comunicados_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.comunicados_da_tela() TO authenticated;

-- As ciências da tela.
CREATE OR REPLACE FUNCTION public.ciencias_da_tela()
RETURNS TABLE(assinaturaid integer, documentoid integer, funcionarioid integer, statusassinatura character varying,
              dataciencia timestamptz, origem character varying, pontospagos integer, motivodesfazer text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.assinaturaid, s.documentoid, s.funcionarioid, s.statusassinatura, s.dataciencia, s.origem, s.pontospagos, s.motivodesfazer
    FROM public.documentosassinaturas s
   WHERE (public.sou_master() AND s.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND s.contaid = public.conta_do_gerente()
          AND public.comunicado_do_gerente(s.documentoid) AND public.pessoa_nos_comunicados_do_gerente(s.funcionarioid))
   ORDER BY s.documentoid, s.assinaturaid
$$;
REVOKE ALL ON FUNCTION public.ciencias_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ciencias_da_tela() TO authenticated;

-- As lojas de um formulário: o master, todas da conta; o gerente, as dele
-- em que tem a permissão.
CREATE OR REPLACE FUNCTION public.lojas_para(p_codigo text)
RETURNS TABLE(lojaid integer, nome character varying, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.lojaid, l.nome, l.ativa
    FROM public.lojas l
   WHERE (public.sou_master() AND l.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND l.contaid = public.conta_do_gerente()
          AND l.lojaid = ANY ((SELECT public.lojas_onde_posso(p_codigo))::integer[]))
   ORDER BY l.nome, l.lojaid
$$;
REVOKE ALL ON FUNCTION public.lojas_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.lojas_para(text) TO authenticated;

-- Os pontos padrão da ciência (a tarefa de rotina "leitura").
CREATE OR REPLACE FUNCTION public.pontos_da_leitura()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT t.pontos FROM public.tarefas t
   WHERE t.sistema = 'leitura' AND t.ativa
     AND ((public.sou_master() AND t.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND t.contaid = public.conta_do_gerente()
           AND cardinality((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[]) > 0))
   LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.pontos_da_leitura() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pontos_da_leitura() TO authenticated;

-- Quem falta dar ciência, para o gerente: só quem tem uma loja dele.
CREATE OR REPLACE FUNCTION public.fora_do_comunicado_gerente(p_documentoid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gerente();
BEGIN
  IF v_conta IS NULL OR cardinality(public.lojas_onde_posso('comunicados.ver')) = 0
     OR NOT public.comunicado_do_gerente(p_documentoid) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                                    ORDER BY f.nomecompleto), '[]'::jsonb)
            FROM public.alcance_do_comunicado(p_documentoid) a(fid)
            JOIN public.funcionarios f ON f.funcionarioid = a.fid AND f.contaid = v_conta
           WHERE public.pessoa_nos_comunicados_do_gerente(a.fid)
             AND NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                              WHERE s.documentoid = p_documentoid AND s.funcionarioid = a.fid));
END;
$function$;

REVOKE ALL ON FUNCTION public.fora_do_comunicado_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.fora_do_comunicado_gerente(integer) TO authenticated;

-- fora_do_comunicado: parte da versão viva (de 20260922400000_rh_comunicados_documentos_onboarding.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.fora_do_comunicado(p_documentoid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fora_do_comunicado_gerente(p_documentoid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                                    ORDER BY f.nomecompleto), '[]'::jsonb)
            FROM public.alcance_do_comunicado(p_documentoid) a(fid)
            JOIN public.funcionarios f ON f.funcionarioid = a.fid
           WHERE NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                              WHERE s.documentoid = p_documentoid AND s.funcionarioid = a.fid));
END;
$function$;

-- O recibo de ciência, para o gerente: comunicado dele e pessoa de loja dele.
CREATE OR REPLACE FUNCTION public.recibo_ciencia_gerente(p_assinaturaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
           'conta', c.nomefantasia, 'pessoa', f.nomecompleto, 'titulo', d.titulo, 'conteudo', d.conteudo,
           'publicadoem', d.datacriacao, 'ciencia', s.dataciencia, 'origem', s.origem,
           'protocolo', 'C-' || s.assinaturaid, 'pontos', s.pontospagos)
    FROM public.documentosassinaturas s
    JOIN public.documentos d    ON d.documentoid = s.documentoid AND d.contaid = s.contaid
    JOIN public.funcionarios f  ON f.funcionarioid = s.funcionarioid AND f.contaid = s.contaid
    JOIN public.contas c        ON c.contaid = s.contaid
   WHERE s.assinaturaid = p_assinaturaid AND s.statusassinatura = 'Ciente'
     AND s.contaid = public.conta_do_gerente()
     AND cardinality((SELECT public.lojas_onde_posso('comunicados.ver'))::integer[]) > 0
     AND public.comunicado_do_gerente(s.documentoid) AND public.pessoa_nos_comunicados_do_gerente(s.funcionarioid)
$function$;
REVOKE ALL ON FUNCTION public.recibo_ciencia_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.recibo_ciencia_gerente(integer) TO authenticated;

-- recibo_ciencia: parte da versão viva (de 20260929160000_admin_clientes_e_redes.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.recibo_ciencia(p_assinaturaid integer)
 RETURNS jsonb

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.recibo_ciencia_gerente(p_assinaturaid);
  END IF;
  RETURN (
  SELECT jsonb_build_object(
           'conta', c.nomefantasia, 'pessoa', f.nomecompleto, 'titulo', d.titulo, 'conteudo', d.conteudo,
           'publicadoem', d.datacriacao, 'ciencia', s.dataciencia, 'origem', s.origem,
           'protocolo', 'C-' || s.assinaturaid, 'pontos', s.pontospagos)
    FROM public.documentosassinaturas s
    JOIN public.documentos d    ON d.documentoid = s.documentoid
    JOIN public.funcionarios f  ON f.funcionarioid = s.funcionarioid
    JOIN public.contas c        ON c.contaid = s.contaid
   WHERE s.assinaturaid = p_assinaturaid AND s.statusassinatura = 'Ciente'
  );
END;
$function$;
