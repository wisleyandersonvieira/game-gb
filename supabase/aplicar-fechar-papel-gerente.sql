-- =========================================================================
-- STGame — Fecha o papel "gerente" até a permissão por cargo existir.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-trava-do-pin-por-pessoa.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929247000_fechar_papel_gerente.sql
--
-- O QUE MUDA: um login com papel "gerente" deixa de entrar e de ver qualquer
-- dado. O master não muda em nada. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Fecha o papel "gerente" (29/09/2026, pedido do Wisley).
--
-- O papel existia no banco desde 21/09, mas nenhuma tela cria um gerente. E
-- ele entrava pela MESMA porta do master (minha_conta): um gerente faria quase
-- tudo o que o master faz, sem cargo, sem lista de lojas e sem registro. Até a
-- permissão por cargo e loja existir (docs/MAPA_PERMISSOES.md), um login com
-- papel "gerente":
--   * não tem conta nenhuma para as regras de acesso (não lê nem grava nada);
--   * não entra pela tela de login do gestor.
-- O valor "gerente" continua aceito na coluna: é ele que a permissão por cargo
-- vai usar, e só o admin geral grava em contasusuarios.
--
-- As três funções partem da versão MAIS RECENTE de cada uma:
--   minha_conta, minha_conta_editavel: 20260927100300_acessos_papeis_e_contexto.sql
--   acesso_por_email:                  20260928100500_senha_do_tablet_a_mao.sql
-- A única mudança em cada uma é tirar 'gerente' da lista de papéis.

CREATE OR REPLACE FUNCTION public.minha_conta()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT contaid FROM public.contasusuarios
                    WHERE userid = auth.uid() AND papel = 'master'),
                  public.conta_do_bot())
$$;

CREATE OR REPLACE FUNCTION public.minha_conta_editavel()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.contaid
    FROM public.contas c
   WHERE c.status = 'ativa'
     AND c.contaid = coalesce((SELECT contaid FROM public.contasusuarios
                                WHERE userid = auth.uid() AND papel = 'master'),
                              public.conta_do_bot())
$$;

CREATE OR REPLACE FUNCTION public.acesso_por_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE u record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura acesso por e-mail.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT au.id AS userid, s.senhahashapp, coalesce(s.definidaamao, false) AS amao,
         cu.contaid, coalesce(cu.papel, '') AS papel,
         coalesce(c.status, 'ativa') AS statusconta, l.ativa AS lojaativa,
         coalesce(lower(au.email) = 'wisley_anderson@hotmail.com', false) AS ehadmin
    INTO u
    FROM auth.users au
    LEFT JOIN public.senhasgestor s ON s.userid = au.id
    LEFT JOIN public.contasusuarios cu ON cu.userid = au.id
    LEFT JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
   WHERE lower(au.email) = lower(btrim(coalesce(p_email, '')));
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Esta porta é do gestor, do administrador geral e do tablet. O colaborador
  -- entra pelo CPF, com as conferências dele. Sem papel, ninguém entra.
  IF NOT (u.ehadmin OR u.papel IN ('master', 'loja')) THEN
    RETURN NULL;
  END IF;
  IF u.papel <> '' AND u.statusconta = 'cancelada' THEN
    RETURN NULL;
  END IF;
  IF u.papel = 'loja' AND coalesce(u.lojaativa, false) = false THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object('userid', u.userid, 'senhahash', u.senhahashapp,
                            'contaid', u.contaid,
                            'papel', CASE WHEN u.papel = '' THEN 'admin' ELSE u.papel END,
                            'senhamanual', u.amao);
END;
$$;

REVOKE ALL ON FUNCTION public.acesso_por_email(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.acesso_por_email(text) TO service_role;

COMMIT;
