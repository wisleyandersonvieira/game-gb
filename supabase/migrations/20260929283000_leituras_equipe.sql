-- Usuários gerenciais, PARTE 4, fatia 9: Equipe (30/09/2026).
--
-- A tela lia as tabelas direto e vinha vazia para o gerente. Agora, com
-- "Equipe: ver":
--   * a lista: quem tem uma loja em comum com ele; CPF e telefone só de quem
--     está INTEIRO nas lojas dele (os dados da pessoa são cadastro);
--   * as lojas de cada pessoa: só as dele (não diz em que outra loja ela está);
--   * a situação do acesso e as travas do PIN: só de quem está inteiro nas
--     lojas dele (é o que ele pode mexer, decisões 2 e 4);
--   * as jornadas: o catálogo da conta, só leitura.
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.equipe_da_tela()
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, cpf character varying, cargo character varying,
              setor character varying, telefonewhatsapp character varying, diadefolga integer, saldopontos integer,
              ativo boolean, jornadaid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto,
         CASE WHEN public.sou_master() OR coalesce(public.pode_na_pessoa('equipe.ver', f.contaid, f.funcionarioid), false) THEN f.cpf END,
         f.cargo, f.setor,
         CASE WHEN public.sou_master() OR coalesce(public.pode_na_pessoa('equipe.ver', f.contaid, f.funcionarioid), false) THEN f.telefonewhatsapp END,
         f.diadefolga, f.saldopontos, f.ativo, f.jornadaid
    FROM public.funcionarios f
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente()
          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                       WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
                         AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('equipe.ver'))::integer[])))
   ORDER BY f.nomecompleto, f.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.equipe_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.equipe_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.vinculos_da_tela()
RETURNS TABLE(funcionarioid integer, lojaid integer, ativo boolean, validador boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fl.funcionarioid, fl.lojaid, fl.ativo, fl.validador
    FROM public.funcionarioslojas fl
   WHERE (public.sou_master() AND fl.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND fl.contaid = public.conta_do_gerente()
          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('equipe.ver'))::integer[]))
   ORDER BY fl.funcionarioid, fl.lojaid
$$;
REVOKE ALL ON FUNCTION public.vinculos_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.vinculos_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.jornadas_da_conta()
RETURNS TABLE(jornadaid integer, nome character varying, ativa boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT j.jornadaid, j.nome, j.ativa
    FROM public.jornadas j
   WHERE (public.sou_master() AND j.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente()
          AND (cardinality((SELECT public.lojas_onde_posso('equipe.ver'))::integer[]) > 0
               OR cardinality((SELECT public.lojas_onde_posso('jornada.ver'))::integer[]) > 0))
   ORDER BY j.nome, j.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_da_conta() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.jornadas_da_conta() TO authenticated;

-- A situação do acesso, para o gerente: só de quem está inteiro nas lojas dele.
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos_gerente()
 RETURNS TABLE(funcionarioid integer, temacesso boolean, nuncaentrou boolean, semsenha boolean, sempin boolean, codigopendente boolean, codigoexpiraem timestamp with time zone, redefinidoem timestamp with time zone, codigogeradoem timestamp with time zone, codigogeradopor text, codigoreimprimivel boolean, folhaemitidaem timestamp with time zone, folhaemitidapor text, folhas integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem,
         k.criadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = k.criadopor),
         k.codigocifrado IS NOT NULL,
         fa.emitidaem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = fa.emitidapor),
         coalesce(fa.total, 0)::integer
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem, criadoem, criadopor, codigocifrado FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC, x.folhaid DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.conta_do_gerente())
     AND coalesce(public.pode_na_pessoa('equipe.ver', f.contaid, f.funcionarioid), false)
   ORDER BY f.funcionarioid
$function$;

REVOKE ALL ON FUNCTION public.situacao_dos_acessos_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.situacao_dos_acessos_gerente() TO authenticated;

-- situacao_dos_acessos: parte da versão viva (de 20260929265500_desempate_nas_listas.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
 RETURNS TABLE(funcionarioid integer, temacesso boolean, nuncaentrou boolean, semsenha boolean, sempin boolean, codigopendente boolean, codigoexpiraem timestamp with time zone, redefinidoem timestamp with time zone, codigogeradoem timestamp with time zone, codigogeradopor text, codigoreimprimivel boolean, folhaemitidaem timestamp with time zone, folhaemitidapor text, folhas integer)

 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.situacao_dos_acessos_gerente();
    RETURN;
  END IF;
  RETURN QUERY
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem,
         k.criadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = k.criadopor),
         k.codigocifrado IS NOT NULL,
         fa.emitidaem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = fa.emitidapor),
         coalesce(fa.total, 0)::integer
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem, criadoem, criadopor, codigocifrado FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC, x.folhaid DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
   ORDER BY f.funcionarioid;
END;
$function$;

-- As travas do PIN, para o gerente: só de quem está inteiro nas lojas dele.
CREATE OR REPLACE FUNCTION public.travas_do_pin_gerente()
 RETURNS TABLE(funcionarioid integer, erros integer, minutosfaltam integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT t.funcionarioid, t.erros,
         CASE WHEN t.bloqueadoate > now()
              THEN greatest(1, ceil(extract(epoch FROM t.bloqueadoate - now()) / 60)::integer) ELSE 0 END
    FROM public.travaspin t
   WHERE t.contaid = public.conta_do_gerente()
     AND coalesce(public.pode_na_pessoa('equipe.ver', t.contaid, t.funcionarioid), false)
     AND (t.bloqueadoate > now() OR (t.erros > 0 AND t.ultimoerro > now() - interval '24 hours'))
$function$;
REVOKE ALL ON FUNCTION public.travas_do_pin_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.travas_do_pin_gerente() TO authenticated;

-- travas_do_pin: parte da versão viva (de 20260929246000_trava_do_pin_por_pessoa.sql); o gerente é desviado.
CREATE OR REPLACE FUNCTION public.travas_do_pin()
 RETURNS TABLE(funcionarioid integer, erros integer, minutosfaltam integer)

 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN QUERY SELECT * FROM public.travas_do_pin_gerente();
    RETURN;
  END IF;
  RETURN QUERY
  SELECT t.funcionarioid, t.erros,
         CASE WHEN t.bloqueadoate > now()
              THEN greatest(1, ceil(extract(epoch FROM t.bloqueadoate - now()) / 60)::integer) ELSE 0 END
    FROM public.travaspin t
   WHERE t.contaid = public.minha_conta()
     AND (t.bloqueadoate > now() OR (t.erros > 0 AND t.ultimoerro > now() - interval '24 hours'));
END;
$function$;
