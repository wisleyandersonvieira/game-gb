-- =========================================================================
-- STGame — RECUPERAÇÃO DE EMERGÊNCIA: definir uma senha temporária
--
-- Para quando o dono da conta (ou o administrador geral) não consegue entrar e
-- o link de recuperação por e-mail não abre.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar -> trocar as DUAS
-- linhas marcadas abaixo -> Run.
--
-- O que ele faz: grava uma senha temporária no login, do mesmo jeito que o
-- Supabase grava. Nada mais é alterado.
--
-- Depois de rodar: entre no site com essa senha temporária. O sistema converte
-- a senha na hora, e a partir daí ela passa a ser conferida por nós. Troque por
-- uma senha definitiva em seguida.
--
-- Cuidado: a senha temporária fica visível no histórico do SQL Editor. Use uma
-- senha de uso único e troque assim que entrar.
-- =========================================================================

DO $$
DECLARE
  -- >>> TROQUE ESTAS DUAS LINHAS <<<
  v_email text := 'wisley_anderson@hotmail.com';
  v_senha text := 'TrocarAgora!2026';

  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM auth.users WHERE lower(email) = lower(btrim(v_email));
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Não existe login com esse e-mail: %', v_email;
  END IF;
  IF length(v_senha) < 8 THEN
    RAISE EXCEPTION 'Use uma senha temporária de pelo menos 8 caracteres.';
  END IF;

  UPDATE auth.users
     SET encrypted_password = extensions.crypt(v_senha, extensions.gen_salt('bf')),
         updated_at = now()
   WHERE id = v_id;

  -- O resumo guardado por nós sai de cena: assim o próximo login entra pelo
  -- caminho de conversão e grava a senha nova do jeito certo.
  DELETE FROM public.senhasgestor WHERE userid = v_id;

  -- Confere que a senha temporária realmente vale.
  IF NOT EXISTS (SELECT 1 FROM auth.users
                  WHERE id = v_id AND extensions.crypt(v_senha, encrypted_password) = encrypted_password) THEN
    RAISE EXCEPTION 'A senha não foi gravada como esperado. Não mexa em mais nada e me avise.';
  END IF;

  RAISE NOTICE 'Senha temporária definida para %. Entre no site com ela e troque em seguida.', v_email;
END $$;
