-- Usuários gerenciais, PARTE 4, fatia 6: Conquistas (e as conquistas no
-- Relatório da pessoa) (30/09/2026).
--
-- As telas liam as tabelas direto e vinham vazias para o gerente. Agora:
--   * o catálogo de conquistas é da conta (só leitura) para quem vê
--     Conquistas ou Relatórios em alguma loja;
--   * a lista de conquistas ganhas ("Conquistas: ver"): de quem tem uma loja
--     em comum com ele (é dia a dia, como feedback);
--   * as conquistas de UMA pessoa, no Relatório ("Relatórios: ver"): só de
--     quem está INTEIRO nas lojas dele (a regra do histórico da pessoa).
-- Para o master nada muda. Nenhum dado é alterado. Classificação: ACRESCENTA.

CREATE OR REPLACE FUNCTION public.conquistas_do_catalogo()
RETURNS TABLE(conquistaid integer, nome character varying, descricao character varying, icone character varying,
              criteriotipo character varying, criteriovalor integer, criteriodias integer, pontosbonus integer,
              ativa boolean, contardesde timestamptz, criadoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.conquistaid, c.nome, c.descricao, c.icone, c.criteriotipo, c.criteriovalor, c.criteriodias, c.pontosbonus,
         c.ativa, c.contardesde, c.criadoem
    FROM public.conquistas c
   WHERE (public.sou_master() AND c.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND c.contaid = public.conta_do_gerente()
          AND (cardinality((SELECT public.lojas_onde_posso('conquistas.ver'))::integer[]) > 0
               OR cardinality((SELECT public.lojas_onde_posso('relatorios.ver'))::integer[]) > 0))
   ORDER BY c.criadoem, c.conquistaid
$$;
REVOKE ALL ON FUNCTION public.conquistas_do_catalogo() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conquistas_do_catalogo() TO authenticated;

-- As conquistas ganhas (a tela de Conquistas): as 200 mais recentes.
CREATE OR REPLACE FUNCTION public.conquistas_ganhas()
RETURNS TABLE(conquistafuncionarioid integer, funcionarioid integer, conquistaid integer, dataconquista timestamptz, pontosbonus integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT cf.conquistafuncionarioid, cf.funcionarioid, cf.conquistaid, cf.dataconquista, cf.pontosbonus
    FROM public.conquistasfuncionarios cf
   WHERE (public.sou_master() AND cf.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND cf.contaid = public.conta_do_gerente()
          AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                       WHERE fl.contaid = cf.contaid AND fl.funcionarioid = cf.funcionarioid AND fl.ativo
                         AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('conquistas.ver'))::integer[])))
   ORDER BY cf.dataconquista DESC, cf.conquistafuncionarioid DESC
   LIMIT 200
$$;
REVOKE ALL ON FUNCTION public.conquistas_ganhas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conquistas_ganhas() TO authenticated;

-- As conquistas de uma pessoa (o Relatório da pessoa).
CREATE OR REPLACE FUNCTION public.conquistas_da_pessoa(p_funcionarioid integer)
RETURNS TABLE(conquistafuncionarioid integer, conquistaid integer, dataconquista timestamptz, pontosbonus integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT cf.conquistafuncionarioid, cf.conquistaid, cf.dataconquista, cf.pontosbonus
    FROM public.conquistasfuncionarios cf
   WHERE cf.funcionarioid = p_funcionarioid
     AND ((public.sou_master() AND cf.contaid = public.minha_conta())
       OR (NOT public.sou_master() AND cf.contaid = public.conta_do_gerente()
           AND coalesce(public.pode_na_pessoa('relatorios.ver', cf.contaid, p_funcionarioid), false)))
   ORDER BY cf.dataconquista DESC, cf.conquistafuncionarioid DESC
$$;
REVOKE ALL ON FUNCTION public.conquistas_da_pessoa(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conquistas_da_pessoa(integer) TO authenticated;

-- As pessoas que o Relatório da pessoa pode abrir: o master, todas; o
-- gerente, só quem está INTEIRO nas lojas em que ele vê Relatórios (o mesmo
-- corte do histórico, das pendências e das conquistas da pessoa).
CREATE OR REPLACE FUNCTION public.pessoas_inteiras_para(p_codigo text)
RETURNS TABLE(funcionarioid integer, nomecompleto character varying, ativo boolean,
              saldopontos integer, pontostotal integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid, f.nomecompleto, f.ativo, f.saldopontos, f.pontostotal
    FROM public.funcionarios f
   WHERE (public.sou_master() AND f.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND f.contaid = public.conta_do_gerente()
          AND coalesce(public.pode_na_pessoa(p_codigo, f.contaid, f.funcionarioid), false))
   ORDER BY f.nomecompleto, f.funcionarioid
$$;
REVOKE ALL ON FUNCTION public.pessoas_inteiras_para(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pessoas_inteiras_para(text) TO authenticated;
