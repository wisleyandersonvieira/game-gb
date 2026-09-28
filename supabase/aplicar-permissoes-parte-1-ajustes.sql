-- =========================================================================
-- STGame — Permissões, ajustes da parte 1: histórico só do master e o
-- último master ATIVO (o login dele não se apaga nem se bloqueia).
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-1-base.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929249000_permissoes_ajustes.sql
--
-- O QUE MUDA: o Supabase passa a recusar apagar ou bloquear ("Ban user") o
-- login do último master ativo de uma conta. Para o master, nada muda na tela.
-- Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Permissões, ajustes da parte 1 (29/09/2026, perguntas do Wisley).
--
-- 1. Quem lê o histórico (e cargos, permissões, usuários gerenciais, lojas):
--    SÓ O MASTER, escrito na regra. Até aqui valia porque minha_conta() só
--    responde para o master; quando o gerente ganhar acesso (parte 5), a regra
--    já não depende disso.
-- 2. A conta nunca fica sem master ATIVO. A trava da parte 1 cobria apagar e
--    rebaixar o master na conta. Faltava o LOGIN: apagar o login do último
--    master, ou bloqueá-lo ("Ban user" no painel do Supabase), tira o acesso do
--    mesmo jeito, e ninguém mais entra para desfazer. E um segundo master com o
--    login bloqueado não conta como "outro master".

-- ---------------------------------------------------------------------------
-- 1. Leitura só do master
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['cargos', 'cargospermissoes', 'usuariosgerenciais', 'usuarioslojas', 'permissoeshistorico'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_sel', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated
                      USING (contaid = (select public.minha_conta()) AND (select public.sou_master()))', t || '_sel', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Sempre um master ATIVO
-- ---------------------------------------------------------------------------
-- Existe outro master na conta, com login que existe e não está bloqueado?
-- Interna: recebe a conta.
CREATE OR REPLACE FUNCTION public.outro_master_ativo(p_contaid integer, p_menos uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.contasusuarios cu
      JOIN auth.users au ON au.id = cu.userid
     WHERE cu.contaid = p_contaid AND cu.papel = 'master' AND cu.userid <> p_menos
       AND (au.banned_until IS NULL OR au.banned_until <= now()))
$$;
REVOKE ALL ON FUNCTION public.outro_master_ativo(integer, uuid) FROM public, anon, authenticated;

-- A trava da conta (parte 1), agora exigindo que o outro master esteja ATIVO.
-- Parte da versão de 20260929248000_permissoes_base.sql; muda só o NOT EXISTS.
CREATE OR REPLACE FUNCTION public.protege_ultimo_master()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.papel = 'master'
     AND (TG_OP = 'DELETE' OR NEW.papel IS DISTINCT FROM 'master' OR NEW.contaid IS DISTINCT FROM OLD.contaid)
     AND NOT public.outro_master_ativo(OLD.contaid, OLD.userid) THEN
    RAISE EXCEPTION 'A conta precisa de pelo menos um master ativo: não dá para apagar nem rebaixar o último.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END;
$$;
REVOKE ALL ON FUNCTION public.protege_ultimo_master() FROM public, anon, authenticated;

-- A trava no LOGIN: apagar ou bloquear o login do último master ativo.
CREATE OR REPLACE FUNCTION public.protege_login_do_ultimo_master()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer;
BEGIN
  -- Bloqueio que já existia, ou que acabou: não muda nada.
  IF TG_OP = 'UPDATE' AND (NEW.banned_until IS NULL OR NEW.banned_until <= now()) THEN
    RETURN NEW;
  END IF;
  SELECT contaid INTO v_conta FROM public.contasusuarios WHERE userid = OLD.id AND papel = 'master';
  IF v_conta IS NOT NULL AND NOT public.outro_master_ativo(v_conta, OLD.id) THEN
    RAISE EXCEPTION 'Este é o último master ativo da conta: o login não pode ser apagado nem bloqueado. Crie outro master antes.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END;
$$;
REVOKE ALL ON FUNCTION public.protege_login_do_ultimo_master() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS stgame_ultimo_master_apagar ON auth.users;
CREATE TRIGGER stgame_ultimo_master_apagar
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.protege_login_do_ultimo_master();
-- Só quando o bloqueio muda: o login de todo dia (que também mexe nesta
-- linha) nem chama a função.
DROP TRIGGER IF EXISTS stgame_ultimo_master_bloquear ON auth.users;
CREATE TRIGGER stgame_ultimo_master_bloquear
  BEFORE UPDATE ON auth.users
  FOR EACH ROW WHEN (NEW.banned_until IS DISTINCT FROM OLD.banned_until)
  EXECUTE FUNCTION public.protege_login_do_ultimo_master();

COMMIT;
