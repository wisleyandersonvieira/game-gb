-- Remover anexo da administração (27/09/2026).
--
-- Não é organização, é obrigação: um contrato subido no cliente errado é dado
-- de uma empresa na pasta de outra, e um cliente que encerra pode pedir a
-- exclusão dos dados (LGPD). O ARQUIVO sai de verdade do armazenamento (quem
-- apaga é o servidor); aqui fica o registro de que ele existiu, de quem
-- removeu e quando.
--
-- O NOME do arquivo também sai na remoção: ele pode carregar o nome da outra
-- empresa, ou de uma pessoa. Ficam tipo, tamanho e as datas.

ALTER TABLE public.anexosadmin ADD COLUMN IF NOT EXISTS removidoem  timestamptz;
ALTER TABLE public.anexosadmin ADD COLUMN IF NOT EXISTS removidopor uuid REFERENCES auth.users (id) ON DELETE SET NULL;
COMMENT ON COLUMN public.anexosadmin.removidoem IS
  'Quando o arquivo foi removido do armazenamento. O registro fica; o arquivo e o nome dele, não.';

-- Rede apagada leva junto o REGISTRO dos anexos dela (os arquivos já saíram:
-- rede com anexo ativo não se apaga, ver abaixo).
ALTER TABLE public.anexosadmin DROP CONSTRAINT IF EXISTS anexosadmin_redeid_fkey;
ALTER TABLE public.anexosadmin ADD CONSTRAINT anexosadmin_redeid_fkey
  FOREIGN KEY (redeid) REFERENCES public.redes (redeid) ON DELETE CASCADE;

-- Parte da versão mais recente (20260929160000): só anexo AINDA ATIVO segura
-- a rede, e a mensagem diz o que fazer.
CREATE OR REPLACE FUNCTION public.impede_apagar_rede_com_clientes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.contas WHERE redeid = OLD.redeid;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'A rede "%" tem % cliente(s) ligado(s). Mova esses clientes para outra rede (ou "sem rede") antes de apagar.',
      OLD.nome, v_n USING ERRCODE = 'foreign_key_violation';
  END IF;
  SELECT count(*) INTO v_n FROM public.anexosadmin WHERE redeid = OLD.redeid AND removidoem IS NULL;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'A rede "%" tem % anexo(s). Remova os anexos antes de apagar a rede.', OLD.nome, v_n
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN OLD;
END;
$$;

-- A lista da tela, com quem subiu e quem removeu (o e-mail do login do
-- admin). Não recebe conta; recusa quem não é o admin geral.
CREATE OR REPLACE FUNCTION public.anexos_admin()
RETURNS TABLE (anexoid integer, contaid integer, redeid integer, nomearquivo varchar, tipo varchar,
               tamanho integer, enviadoem timestamptz, enviadopor text, removidoem timestamptz, removidopor text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.eh_admin_geral() THEN
    RAISE EXCEPTION 'Só o administrador geral.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT a.anexoid, a.contaid, a.redeid, a.nomearquivo, a.tipo, a.tamanho, a.enviadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = a.enviadopor),
         a.removidoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = a.removidopor)
    FROM public.anexosadmin a
   ORDER BY a.enviadoem DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.anexos_admin() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.anexos_admin() TO authenticated;
