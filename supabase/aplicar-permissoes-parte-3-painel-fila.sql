-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 3, fatia 2: painel da loja e fila.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-3-rh.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929264000_leituras_painel_fila.sql
--
-- O QUE MUDA: a base das leituras do gerente (conta_do_gerente) e o ramo do gerente
-- no painel da loja e na fila. Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 3, fatia 1: a base das leituras por loja, o
-- painel da loja e a fila (29/09/2026).
--
-- O gerente continua "fechado": minha_conta() segue vazia para ele, então toda
-- regra de leitura das tabelas e toda função que lê pela conta seguem sem
-- mostrar nada a ele. Nada disso muda.
-- O que muda: cada tela da lista (Início, bolinhas do menu, Quadro, fila,
-- painel da loja, relatórios, metas) ganha um RAMO DO GERENTE, no começo da
-- função, que só lê as lojas em que ele tem a permissão de VER aquela tela.
-- O caminho do master fica igual, linha por linha.
-- Mais restritivo (parte 4 refina): no painel, o bloco da meta (tem R$) só com
-- "Ver valores em R$"; o da agenda (tem nome de cliente) só com "Agenda: ver".

-- A conta do gerente que chama (ativo, conta não cancelada); vazio para
-- qualquer outro. Não recebe nada: só diz a conta de quem pergunta.
CREATE OR REPLACE FUNCTION public.conta_do_gerente()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.contaid
    FROM public.contasusuarios cu
    JOIN public.usuariosgerenciais ug ON ug.contaid = cu.contaid AND ug.userid = cu.userid AND ug.ativo
    JOIN public.contas c ON c.contaid = cu.contaid AND c.status <> 'cancelada'
   WHERE cu.userid = auth.uid() AND cu.papel = 'gerente'
$$;
REVOKE ALL ON FUNCTION public.conta_do_gerente() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_do_gerente() TO authenticated;

-- painel_da_loja: parte da versão viva (20260924... montar_painel); ramo do gerente.
CREATE OR REPLACE FUNCTION public.painel_da_loja(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta   integer := public.minha_conta();
  v_painel  jsonb;
  v_gerente boolean := false;
BEGIN
  IF v_conta IS NULL THEN
    -- Ramo do gerente (parte 3): só a loja em que ele pode ver o painel.
    v_conta := public.conta_do_gerente();
    IF v_conta IS NULL OR NOT public.pode('painel.ver', p_lojaid) THEN
      RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    v_gerente := true;
  END IF;

  v_painel := public.montar_painel(v_conta, p_lojaid, false);
  IF v_painel IS NULL THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_gerente THEN
    IF NOT public.pode('valores.ver_rs', p_lojaid) THEN
      v_painel := v_painel - 'meta';
    END IF;
    IF NOT public.pode('agenda.ver', p_lojaid) THEN
      v_painel := v_painel - 'agenda';
    END IF;
  END IF;
  RETURN v_painel;
END;
$function$;

-- fila_da_loja: parte da versão viva; o gerente vê a fila da loja em que pode
-- ver o Quadro.
CREATE OR REPLACE FUNCTION public.fila_da_loja(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text, disponivel boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.*
    FROM public.fila_de_hoje(coalesce(public.minha_conta(),
                                      CASE WHEN public.pode('quadro.ver', p_lojaid) THEN public.conta_do_gerente() END),
                             p_lojaid) f
   ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid
$function$;

COMMIT;
