-- Etapa 1.12, parte A (2/3): os dois acessos novos, o contexto das visões e a
-- política de uso versionada.
--
-- Desenho aprovado em 23/09/2026:
--   * Um login por LOJA (tablet) e um por COLABORADOR (celular, entra por CPF),
--     guardados em contasusuarios, junto com o master.
--   * minha_conta() responde NULO para esses dois. Com isso, as ~200 regras de
--     acesso que já existem passam a negar tudo para eles, sem serem
--     reescritas: eles não leem nenhuma tabela pelo endereço.
--   * Tudo o que essas visões fazem passa por função de servidor, que entra
--     num "contexto da visão" — o mesmo desenho já aprovado do bot, e que só
--     vale quando quem chama é o servidor.
--   * A política de uso é um comunicado. Cada versão nova é um comunicado novo;
--     as ciências antigas continuam guardadas, ligadas à versão que valia.

-- ---------------------------------------------------------------------------
-- 1. Papéis novos em contasusuarios
-- ---------------------------------------------------------------------------
ALTER TABLE public.contasusuarios DROP CONSTRAINT contasusuarios_papel_check;
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_papel_check
  CHECK (papel IN ('master', 'gerente', 'loja', 'colaborador'));

ALTER TABLE public.contasusuarios ADD COLUMN lojaid integer;
ALTER TABLE public.contasusuarios ADD COLUMN funcionarioid integer;
ALTER TABLE public.contasusuarios ADD COLUMN criadopor uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_loja_fk
  FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT;
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_funcionario_fk
  FOREIGN KEY (contaid, funcionarioid) REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;

-- Cada papel tem o seu vínculo, e só o dele.
ALTER TABLE public.contasusuarios ADD CONSTRAINT contasusuarios_vinculo_do_papel CHECK (
  (papel IN ('master', 'gerente') AND lojaid IS NULL AND funcionarioid IS NULL)
  OR (papel = 'loja'        AND lojaid IS NOT NULL AND funcionarioid IS NULL)
  OR (papel = 'colaborador' AND funcionarioid IS NOT NULL AND lojaid IS NULL)
);

CREATE UNIQUE INDEX contasusuarios_um_acesso_por_loja
  ON public.contasusuarios (contaid, lojaid) WHERE lojaid IS NOT NULL;
CREATE UNIQUE INDEX contasusuarios_um_acesso_por_pessoa
  ON public.contasusuarios (contaid, funcionarioid) WHERE funcionarioid IS NOT NULL;

COMMENT ON COLUMN public.contasusuarios.papel IS
  'master (dono da conta), gerente (Etapa 1.14), loja (tablet) ou colaborador (celular).';

-- ---------------------------------------------------------------------------
-- 1a. Código da empresa (por onde o colaborador entra)
-- ---------------------------------------------------------------------------
-- O colaborador abre stgame.app/e/<codigo> (link e QR que o gestor imprime) ou
-- digita esse código na tela de login. É por ele que o app sabe de qual
-- empresa a pessoa é, antes de ela entrar.
ALTER TABLE public.contas ADD COLUMN codigo varchar(30);

UPDATE public.contas SET codigo =
  left(regexp_replace(lower(translate(nome,
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
         'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
       '[^a-z0-9]+', '', 'g'), 22) || contaid::text
 WHERE codigo IS NULL;
UPDATE public.contas SET codigo = 'empresa' || contaid::text WHERE btrim(coalesce(codigo, '')) = '';

-- Conta nova nasce com o código pronto (o admin não precisa inventar um).
CREATE OR REPLACE FUNCTION public.codigo_padrao_da_conta()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v text;
BEGIN
  IF btrim(coalesce(NEW.codigo, '')) <> '' THEN
    NEW.codigo := lower(btrim(NEW.codigo));
    RETURN NEW;
  END IF;
  v := left(regexp_replace(lower(translate(coalesce(NEW.nome, ''),
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
         'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
       '[^a-z0-9]+', '', 'g'), 22);
  IF v = '' THEN v := 'empresa'; END IF;
  NEW.codigo := v || NEW.contaid::text;
  RETURN NEW;
END;
$$;

CREATE TRIGGER contas_codigo_padrao
  BEFORE INSERT ON public.contas
  FOR EACH ROW EXECUTE FUNCTION public.codigo_padrao_da_conta();

ALTER TABLE public.contas ALTER COLUMN codigo SET NOT NULL;
ALTER TABLE public.contas ADD CONSTRAINT contas_codigo_formato
  CHECK (codigo ~ '^[a-z0-9-]{3,30}$');
CREATE UNIQUE INDEX contas_codigo_unico ON public.contas (codigo);
COMMENT ON COLUMN public.contas.codigo IS
  'Código público da empresa, usado no link/QR de entrada do colaborador (stgame.app/e/<codigo>).';

-- O navegador não escreve o código (a tabela contas já é só do admin geral).
-- Quem procura a empresa pelo código é o servidor, na tela de login.
CREATE OR REPLACE FUNCTION public.conta_por_codigo(p_codigo text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE c record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor procura empresa por código.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT contaid, nome, status INTO c FROM public.contas
   WHERE codigo = lower(btrim(coalesce(p_codigo, '')));
  IF NOT FOUND OR c.status = 'cancelada' THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('contaid', c.contaid, 'nome', c.nome);
END;
$$;
REVOKE ALL ON FUNCTION public.conta_por_codigo(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.conta_por_codigo(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 1b. Marcas de acesso na pessoa
-- ---------------------------------------------------------------------------
-- Senha e PIN começam com os 6 primeiros dígitos do CPF e são trocados no
-- primeiro acesso. Enquanto forem provisórios, o gestor vê o aviso na Equipe.
ALTER TABLE public.funcionarios ADD COLUMN senhaprovisoria    boolean NOT NULL DEFAULT true;
ALTER TABLE public.funcionarios ADD COLUMN pinprovisorio      boolean NOT NULL DEFAULT true;
ALTER TABLE public.funcionarios ADD COLUMN primeiroacessoem   timestamptz;
ALTER TABLE public.funcionarios ADD COLUMN acessoredefinidoem timestamptz;
ALTER TABLE public.funcionarios ADD COLUMN acessoredefinidopor uuid REFERENCES auth.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.funcionarios.primeiroacessoem IS 'Quando a pessoa entrou no app pela primeira vez. Vazio = nunca entrou.';

-- O navegador do master não escreve estas colunas: em funcionarios o UPDATE é
-- liberado coluna por coluna (a tela grava só os campos de cadastro), e coluna
-- nova nasce sem permissão. Elas mudam só pelas funções de acesso.

-- ---------------------------------------------------------------------------
-- 2. minha_conta(): só master e gerente (mais o contexto de servidor)
-- ---------------------------------------------------------------------------
-- É a peça central do isolamento das visões novas: quem entra como loja ou
-- como colaborador não tem conta nenhuma para a RLS, então não lê nada.
CREATE OR REPLACE FUNCTION public.minha_conta()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT contaid FROM public.contasusuarios
                    WHERE userid = auth.uid() AND papel IN ('master', 'gerente')),
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
                                WHERE userid = auth.uid() AND papel IN ('master', 'gerente')),
                              public.conta_do_bot())
$$;

-- ---------------------------------------------------------------------------
-- 3. Contexto das visões (tablet e colaborador)
-- ---------------------------------------------------------------------------
-- Mesmo mecanismo do bot: só vale quando quem chama é o servidor
-- (bot_contexto_confiavel), e dura até o fim da transação.
CREATE OR REPLACE FUNCTION public.loja_da_visao()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.bot_contexto_confiavel()
              THEN nullif(current_setting('stgame.visao_loja', true), '')::integer END
$$;

CREATE OR REPLACE FUNCTION public.entrar_na_visao(p_contaid integer, p_funcionarioid integer,
                                                  p_lojaid integer, p_canal text)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Contexto das visões só no servidor.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_canal NOT IN ('tablet', 'colaborador') THEN
    RAISE EXCEPTION 'Canal inválido.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_contaid IS NULL THEN
    RAISE EXCEPTION 'Sem conta no contexto.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM set_config('stgame.bot_conta', p_contaid::text, true);
  PERFORM set_config('stgame.bot_funcionario', coalesce(p_funcionarioid::text, ''), true);
  PERFORM set_config('stgame.bot_canal', p_canal, true);
  PERFORM set_config('stgame.visao_loja', coalesce(p_lojaid::text, ''), true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Quem sou eu (usada pelo app para saber para onde levar quem entrou)
-- ---------------------------------------------------------------------------
-- Só fala do próprio login (auth.uid()). Não recebe parâmetro nenhum, por isso
-- pode ser liberada para quem está logado.
CREATE OR REPLACE FUNCTION public.meu_acesso()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  a     record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;
  IF public.eh_admin_geral() THEN
    RETURN jsonb_build_object('tipo', 'admin');
  END IF;

  SELECT cu.papel, cu.contaid, cu.lojaid, cu.funcionarioid,
         c.status AS statusconta, c.nome AS nomeconta,
         l.nome AS nomeloja, l.ativa AS lojaativa,
         f.nomecompleto AS nomepessoa, f.ativo AS pessoaativa,
         f.senhaprovisoria, f.pinprovisorio
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;

  -- Desligado na hora: pessoa inativa, loja desativada ou conta cancelada
  -- perdem o acesso na mesma hora, sem esperar a sessão vencer.
  IF a.statusconta = 'cancelada'
     OR (a.papel = 'loja' AND coalesce(a.lojaativa, false) = false)
     OR (a.papel = 'colaborador' AND coalesce(a.pessoaativa, false) = false) THEN
    RETURN jsonb_build_object('tipo', 'desligado');
  END IF;

  RETURN jsonb_build_object(
    'tipo', a.papel,
    'conta', a.nomeconta,
    'loja', a.nomeloja,
    'nome', coalesce(a.nomepessoa, a.nomeloja, a.nomeconta),
    'somenteleitura', a.statusconta <> 'ativa',
    'senhaprovisoria', coalesce(a.senhaprovisoria, false),
    'pinprovisorio', coalesce(a.pinprovisorio, false),
    'politicapendente', CASE WHEN a.papel = 'colaborador'
                             THEN public.politica_pendente(a.contaid, a.funcionarioid) ELSE false END);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Política de uso: um comunicado por versão
-- ---------------------------------------------------------------------------
-- A versão em vigor fica em configuracoes (POLITICA_USO_DOCUMENTOID). Publicar
-- uma versão nova arquiva a anterior; as ciências antigas continuam guardadas,
-- ligadas ao comunicado daquela versão.
CREATE OR REPLACE FUNCTION public.politica_documento(p_contaid integer)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
   WHERE contaid = p_contaid AND chave = 'POLITICA_USO_DOCUMENTOID'
$$;

-- Esta pessoa ainda deve ciência na versão em vigor?
CREATE OR REPLACE FUNCTION public.politica_pendente(p_contaid integer, p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
           WHEN public.politica_documento(p_contaid) IS NULL THEN false
           ELSE NOT EXISTS (SELECT 1 FROM public.documentosassinaturas a
                             WHERE a.contaid = p_contaid
                               AND a.documentoid = public.politica_documento(p_contaid)
                               AND a.funcionarioid = p_funcionarioid
                               AND a.statusassinatura = 'Ciente')
         END
$$;

-- Publica uma versão nova (só o master). Sempre com 0 ponto de ciência:
-- ninguém ganha ponto por aceitar a política.
CREATE OR REPLACE FUNCTION public.publicar_politica_de_uso(p_conteudo text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.exige_master_editavel();
  v_antigo integer := public.politica_documento(v_conta);
  v_novo  integer;
  v_texto text := btrim(coalesce(p_conteudo, ''));
BEGIN
  IF length(v_texto) < 200 THEN
    RAISE EXCEPTION 'A política de uso está curta demais: confira o texto.' USING ERRCODE = 'check_violation';
  END IF;

  v_novo := public.publicar_comunicado(
    'Política de uso do sistema — ' || to_char(public.dia_em_sao_paulo(now()), 'DD/MM/YYYY'),
    v_texto, 0, 'conta', NULL, NULL);

  IF v_antigo IS NOT NULL THEN
    PERFORM public.arquivar_comunicado(v_antigo);
  END IF;

  UPDATE public.configuracoes SET valor = v_novo::text
   WHERE contaid = v_conta AND chave = 'POLITICA_USO_DOCUMENTOID';
  IF NOT FOUND THEN
    INSERT INTO public.configuracoes (contaid, chave, valor, descricao)
    VALUES (v_conta, 'POLITICA_USO_DOCUMENTOID', v_novo::text,
            'Comunicado da versão da política de uso em vigor. Preenchido pelo sistema.');
  END IF;
  RETURN v_novo;
END;
$$;

-- O colaborador lê a política dele (e só a dele) para aceitar no primeiro
-- acesso. Fala só do próprio login, então pode ir para a tela.
CREATE OR REPLACE FUNCTION public.minha_politica_de_uso()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('assinaturaid', a.assinaturaid, 'titulo', d.titulo, 'conteudo', d.conteudo)
    FROM public.contasusuarios cu
    JOIN public.documentos d
      ON d.contaid = cu.contaid AND d.documentoid = public.politica_documento(cu.contaid)
    JOIN public.documentosassinaturas a
      ON a.contaid = cu.contaid AND a.documentoid = d.documentoid AND a.funcionarioid = cu.funcionarioid
   WHERE cu.userid = auth.uid() AND cu.papel = 'colaborador'
$$;

-- A ciência da política: entra no contexto da visão e usa a MESMA função de
-- ciência das telas do gestor (nada de caminho paralelo). Só o servidor chama.
CREATE OR REPLACE FUNCTION public.politica_dar_ciencia(p_contaid integer, p_funcionarioid integer,
                                                       p_assinaturaid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra a ciência da política.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas
                  WHERE assinaturaid = p_assinaturaid AND contaid = p_contaid
                    AND funcionarioid = p_funcionarioid
                    AND documentoid = public.politica_documento(p_contaid)) THEN
    RAISE EXCEPTION 'Esta ciência não é da política em vigor.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, NULL, 'colaborador');
  RETURN public.registrar_ciencia(p_assinaturaid);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permissões
-- ---------------------------------------------------------------------------
-- Recebem conta/loja por parâmetro: internas, nunca liberadas.
REVOKE ALL ON FUNCTION public.entrar_na_visao(integer, integer, integer, text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.politica_documento(integer)                      FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.politica_pendente(integer, integer)              FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.loja_da_visao()                                  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.entrar_na_visao(integer, integer, integer, text) TO service_role;

-- Falam só do próprio login: podem ser chamadas pelas telas.
REVOKE ALL ON FUNCTION public.meu_acesso() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.meu_acesso() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.publicar_politica_de_uso(text) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.publicar_politica_de_uso(text) TO authenticated;
REVOKE ALL ON FUNCTION public.minha_politica_de_uso() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.minha_politica_de_uso() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.politica_dar_ciencia(integer, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.politica_dar_ciencia(integer, integer, integer) TO service_role;
