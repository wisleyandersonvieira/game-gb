-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 4, fatia 1: a porta de entrada do gerente.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- CLASSIFICAÇÃO: ACRESCENTA (marcada em 30/09/2026, já aplicada: o site
-- anterior continuava funcionando com o banco novo; nenhuma função que ele
-- chamava sumiu nem mudou de formato).
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-partes-2-e-3.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929270000_porta_do_gerente.sql
--
-- O QUE MUDA: o seletor de loja do topo pede ao banco só as lojas de quem
-- pergunta; o menu recebe só o que o cargo deixa ver; gerente bloqueado é
-- desligado. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 4, fatia 1: a porta de entrada do gerente
-- (29/09/2026).
--
-- 1. minhas_lojas(): o seletor de loja do topo. Hoje ele lê a tabela lojas
--    direto, e para o gerente vem vazio — nenhuma tela funciona. A função
--    devolve só as lojas de quem pergunta: o master, as ativas da conta dele
--    (o mesmo de hoje); o gerente, as ativas em que ele está.
-- 2. minhas_permissoes(): o que quem pergunta pode ver, para o menu esconder
--    o resto e o endereço digitado direto mostrar uma mensagem clara. Só diz
--    de quem pergunta. Esconder não é permissão: o banco continua conferindo.
-- 3. meu_acesso(): gerente bloqueado (usuário gerencial inativo) é desligado.
-- Para o master nada muda. Nenhum dado é alterado.

CREATE OR REPLACE FUNCTION public.minhas_lojas()
RETURNS TABLE (lojaid integer, nome varchar, cidade varchar, endereco varchar, ativa boolean,
               responsavelagendamentosid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.lojaid, l.nome, l.cidade, l.endereco, l.ativa, l.responsavelagendamentosid
    FROM public.lojas l
   WHERE l.ativa
     AND (l.contaid = public.minha_conta()
          OR (l.contaid = public.conta_do_gerente()
              AND EXISTS (SELECT 1 FROM public.usuarioslojas ul
                           WHERE ul.userid = auth.uid() AND ul.contaid = l.contaid AND ul.lojaid = l.lojaid)))
   ORDER BY l.nome, l.lojaid
$$;
REVOKE ALL ON FUNCTION public.minhas_lojas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.minhas_lojas() TO authenticated;

-- master: todos os códigos do catálogo; gerente: os do cargo dele, cada um com
-- as lojas em que vale. Qualquer outro: nada.
CREATE OR REPLACE FUNCTION public.minhas_permissoes()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN public.sou_master() THEN
      jsonb_build_object('master', true,
                         'codigos', (SELECT jsonb_agg(k.codigo ORDER BY k.ordem) FROM public.catalogo_de_permissoes() k))
    WHEN public.conta_do_gerente() IS NOT NULL THEN
      jsonb_build_object('master', false,
                         'codigos', coalesce((SELECT jsonb_agg(DISTINCT cp.codigo ORDER BY cp.codigo)
                                                FROM public.usuariosgerenciais ug
                                                JOIN public.cargospermissoes cp ON cp.contaid = ug.contaid AND cp.cargoid = ug.cargoid
                                               WHERE ug.userid = auth.uid() AND ug.ativo
                                                 AND EXISTS (SELECT 1 FROM public.usuarioslojas ul
                                                              JOIN public.lojas l ON l.lojaid = ul.lojaid AND l.contaid = ul.contaid AND l.ativa
                                                             WHERE ul.userid = ug.userid AND ul.contaid = ug.contaid)), '[]'::jsonb))
    ELSE jsonb_build_object('master', false, 'codigos', '[]'::jsonb)
  END
$$;
REVOKE ALL ON FUNCTION public.minhas_permissoes() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.minhas_permissoes() TO authenticated;

-- meu_acesso: parte da versão viva (20260929160000_admin_clientes_e_redes.sql);
-- muda só o gerente bloqueado.
CREATE OR REPLACE FUNCTION public.meu_acesso()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  a     record;
BEGIN
  IF v_uid IS NULL THEN
    -- Sem token, ou token inválido/vencido: o banco não reconhece ninguém.
    RETURN jsonb_build_object('tipo', 'semlogin');
  END IF;
  IF public.eh_admin_geral() THEN
    RETURN jsonb_build_object('tipo', 'admin');
  END IF;

  SELECT cu.papel, cu.contaid, cu.lojaid, cu.funcionarioid,
         c.status AS statusconta, c.nomefantasia AS nomeconta,
         l.nome AS nomeloja, l.ativa AS lojaativa,
         f.nomecompleto AS nomepessoa, f.ativo AS pessoaativa,
         f.senhahashapp IS NULL AS semsenha, f.pinhash IS NULL AS sempin
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = v_uid;

  IF NOT FOUND THEN
    -- Token bom, mas esta pessoa não pertence a conta nenhuma.
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;

  -- Desligado na hora: pessoa inativa, loja desativada ou conta cancelada.
  IF a.statusconta = 'cancelada'
     OR (a.papel = 'loja' AND coalesce(a.lojaativa, false) = false)
     OR (a.papel = 'colaborador' AND coalesce(a.pessoaativa, false) = false)
     -- Gerente sem usuário gerencial ATIVO (bloqueado pelo master): desligado na hora.
     OR (a.papel = 'gerente' AND public.conta_do_gerente() IS NULL) THEN
    RETURN jsonb_build_object('tipo', 'desligado');
  END IF;

  RETURN jsonb_build_object(
    'tipo', a.papel,
    'conta', a.nomeconta,
    'loja', a.nomeloja,
    'nome', coalesce(a.nomepessoa, a.nomeloja, a.nomeconta),
    'somenteleitura', a.statusconta <> 'ativa',
    'semsenha', coalesce(a.semsenha, false),
    'sempin', coalesce(a.sempin, false),
    'politicapendente', CASE WHEN a.papel = 'colaborador'
                             THEN public.politica_pendente(a.contaid, a.funcionarioid) ELSE false END);
END;
$function$;

COMMIT;
