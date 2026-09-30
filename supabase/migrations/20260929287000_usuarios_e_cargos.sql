-- Usuários gerenciais, PARTE 5: a página Usuários e cargos (30/09/2026).
--
-- Configurações -> Usuários e cargos, SÓ do master (nunca delegável):
--   1. Cargos reutilizáveis: criar, editar, DUPLICAR, apagar (se ninguém usa).
--      O cargo diz O QUÊ (as permissões); as lojas de cada pessoa dizem ONDE.
--   2. "Acesso total": um cargo com TODAS as permissões do catálogo de hoje.
--      Permissão que entrar no catálogo depois NÃO entra sozinha nele.
--   3. Permissões sem cargo nenhum aparecem como aviso ("N permissões novas
--      aguardando"): negar em silêncio viraria quebra em silêncio.
--   4. Convite por e-mail (o servidor manda; a pessoa cria a própria senha;
--      o master nunca vê a senha). Aqui ficam a conferência do convite e o
--      registro do gerente, que SÓ o servidor chama.
--   5. Vínculo com o funcionário (quando a pessoa também é da equipe): é o que
--      faz valer "ninguém aprova nem gera pontos para si mesmo".
--   6. Desativar: o banco nega tudo na hora (conta_do_gerente fica vazia); o
--      servidor ainda derruba a sessão.
--   7. Histórico: só o master lê; sobrevive ao apagamento do cargo, do usuário
--      e do login (a tabela não depende deles); guarda antes e depois.
--   8. A porta de entrada por e-mail passa a aceitar o gerente ATIVO de conta
--      não cancelada (até aqui ela o recusava).
-- Nenhum dado é alterado. Classificação: ACRESCENTA (só cria; a entrada por
-- e-mail muda só para o papel gerente, que ninguém tem até o botão existir).

-- O nome que o master digitou (para a lista; não decide acesso nenhum).
ALTER TABLE public.usuariosgerenciais ADD COLUMN IF NOT EXISTS nome varchar(80);

-- A conta do master que está mexendo na página, ou erro.
CREATE OR REPLACE FUNCTION public.conta_da_pagina_de_usuarios()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_conta;
END;
$$;
REVOKE ALL ON FUNCTION public.conta_da_pagina_de_usuarios() FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cargos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cargos_da_conta()
RETURNS TABLE(cargoid integer, nome character varying, codigos text[], usuarios integer, criadoem timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.cargoid, c.nome,
         coalesce((SELECT array_agg(cp.codigo::text ORDER BY cp.codigo) FROM public.cargospermissoes cp
                    WHERE cp.contaid = c.contaid AND cp.cargoid = c.cargoid), '{}'),
         (SELECT count(*)::integer FROM public.usuariosgerenciais u WHERE u.contaid = c.contaid AND u.cargoid = c.cargoid),
         c.criadoem
    FROM public.cargos c
   WHERE public.sou_master() AND c.contaid = public.minha_conta()
   ORDER BY c.nome, c.cargoid
$$;
REVOKE ALL ON FUNCTION public.cargos_da_conta() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cargos_da_conta() TO authenticated;

CREATE OR REPLACE FUNCTION public.salvar_cargo(p_cargoid integer, p_nome text, p_codigos text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.conta_da_pagina_de_usuarios();
  v_nome  text := btrim(coalesce(p_nome, ''));
  v_cods  text[] := (SELECT coalesce(array_agg(DISTINCT c), '{}') FROM unnest(coalesce(p_codigos, '{}')) c);
  v_id    integer;
  v_fora  text;
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_nome = '' THEN
    RAISE EXCEPTION 'Dê um nome ao cargo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT string_agg(c, ', ') INTO v_fora FROM unnest(v_cods) c
   WHERE NOT EXISTS (SELECT 1 FROM public.catalogo_de_permissoes() k WHERE k.codigo = c);
  IF v_fora IS NOT NULL THEN
    RAISE EXCEPTION 'Permissão que não existe: %.', v_fora USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cargos WHERE contaid = v_conta AND lower(nome) = lower(v_nome)
                                           AND cargoid IS DISTINCT FROM p_cargoid) THEN
    RAISE EXCEPTION 'Já existe um cargo com esse nome.' USING ERRCODE = 'unique_violation';
  END IF;
  IF p_cargoid IS NULL THEN
    INSERT INTO public.cargos (contaid, nome, criadopor) VALUES (v_conta, v_nome, auth.uid()) RETURNING cargoid INTO v_id;
  ELSE
    UPDATE public.cargos SET nome = v_nome WHERE contaid = v_conta AND cargoid = p_cargoid AND nome IS DISTINCT FROM v_nome;
    SELECT cargoid INTO v_id FROM public.cargos WHERE contaid = v_conta AND cargoid = p_cargoid;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Cargo não encontrado.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;
  DELETE FROM public.cargospermissoes WHERE contaid = v_conta AND cargoid = v_id AND codigo <> ALL (v_cods);
  INSERT INTO public.cargospermissoes (contaid, cargoid, codigo)
  SELECT v_conta, v_id, c FROM unnest(v_cods) c
  ON CONFLICT DO NOTHING;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_cargo(integer, text, text[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_cargo(integer, text, text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicar_cargo(p_cargoid integer, p_nome text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_da_pagina_de_usuarios(); v_cods text[];
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cargos WHERE contaid = v_conta AND cargoid = p_cargoid) THEN
    RAISE EXCEPTION 'Cargo não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT coalesce(array_agg(codigo::text), '{}') INTO v_cods FROM public.cargospermissoes WHERE contaid = v_conta AND cargoid = p_cargoid;
  RETURN public.salvar_cargo(NULL, p_nome, v_cods);
END;
$$;
REVOKE ALL ON FUNCTION public.duplicar_cargo(integer, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.duplicar_cargo(integer, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.apagar_cargo(p_cargoid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_da_pagina_de_usuarios(); v_n integer;
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT count(*) INTO v_n FROM public.usuariosgerenciais WHERE contaid = v_conta AND cargoid = p_cargoid;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Este cargo tem % usuário(s): troque o cargo deles antes de apagar.', v_n USING ERRCODE = 'foreign_key_violation';
  END IF;
  DELETE FROM public.cargos WHERE contaid = v_conta AND cargoid = p_cargoid;
END;
$$;
REVOKE ALL ON FUNCTION public.apagar_cargo(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.apagar_cargo(integer) TO authenticated;

-- "Acesso total": todas as permissões do catálogo DE HOJE (as que entrarem
-- depois não entram sozinhas: aparecem no aviso de permissões novas).
CREATE OR REPLACE FUNCTION public.criar_cargo_acesso_total(p_nome text DEFAULT 'Acesso total')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN public.salvar_cargo(NULL, p_nome, (SELECT array_agg(codigo) FROM public.catalogo_de_permissoes()));
END;
$$;
REVOKE ALL ON FUNCTION public.criar_cargo_acesso_total(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.criar_cargo_acesso_total(text) TO authenticated;

-- As permissões do catálogo que nenhum cargo da conta tem.
CREATE OR REPLACE FUNCTION public.permissoes_sem_cargo()
RETURNS TABLE(codigo text, tela text, nome text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT k.codigo, k.tela, k.nome
    FROM public.catalogo_de_permissoes() k
   WHERE public.sou_master()
     AND NOT EXISTS (SELECT 1 FROM public.cargospermissoes cp WHERE cp.contaid = public.minha_conta() AND cp.codigo = k.codigo)
   ORDER BY k.ordem, k.codigo
$$;
REVOKE ALL ON FUNCTION public.permissoes_sem_cargo() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.permissoes_sem_cargo() TO authenticated;

-- ---------------------------------------------------------------------------
-- Usuários gerenciais
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.usuarios_gerenciais()
RETURNS TABLE(userid uuid, nome character varying, email text, cargoid integer, cargo character varying, lojas integer[],
              funcionarioid integer, pessoa character varying, ativo boolean, convitependente boolean,
              criadoem timestamptz, ultimoacesso timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT u.userid, u.nome, au.email::text, u.cargoid, c.nome,
         coalesce((SELECT array_agg(ul.lojaid ORDER BY ul.lojaid) FROM public.usuarioslojas ul
                    WHERE ul.contaid = u.contaid AND ul.userid = u.userid), '{}'),
         u.funcionarioid, f.nomecompleto, u.ativo,
         au.last_sign_in_at IS NULL AND NOT EXISTS (SELECT 1 FROM public.senhasgestor s WHERE s.userid = u.userid),
         u.criadoem, au.last_sign_in_at
    FROM public.usuariosgerenciais u
    JOIN public.cargos c ON c.contaid = u.contaid AND c.cargoid = u.cargoid
    LEFT JOIN auth.users au ON au.id = u.userid
    LEFT JOIN public.funcionarios f ON f.contaid = u.contaid AND f.funcionarioid = u.funcionarioid
   WHERE public.sou_master() AND u.contaid = public.minha_conta()
   ORDER BY u.nome, u.userid
$$;
REVOKE ALL ON FUNCTION public.usuarios_gerenciais() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.usuarios_gerenciais() TO authenticated;

-- Confere tudo ANTES de o servidor mandar o convite. Não grava nada; devolve
-- a conta do master (a única onde o servidor pode registrar o gerente).
CREATE OR REPLACE FUNCTION public.preparar_convite_gerente(p_nome text, p_email text, p_cargoid integer, p_lojas integer[],
                                                           p_funcionarioid integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE v_conta integer := public.conta_da_pagina_de_usuarios();
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF btrim(coalesce(p_nome, '')) = '' THEN
    RAISE EXCEPTION 'Escreva o nome da pessoa.' USING ERRCODE = 'check_violation';
  END IF;
  IF coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'E-mail inválido.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = lower(btrim(p_email))) THEN
    RAISE EXCEPTION 'Este e-mail já tem um login no STGame. Use outro e-mail.' USING ERRCODE = 'unique_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cargos WHERE contaid = v_conta AND cargoid = p_cargoid) THEN
    RAISE EXCEPTION 'Escolha um cargo.' USING ERRCODE = 'check_violation';
  END IF;
  IF cardinality(coalesce(p_lojas, '{}')) = 0 THEN
    RAISE EXCEPTION 'Escolha pelo menos uma loja.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(p_lojas) l
              WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE contaid = v_conta AND lojaid = l AND ativa)) THEN
    RAISE EXCEPTION 'Loja inválida.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_funcionarioid IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE contaid = v_conta AND funcionarioid = p_funcionarioid AND ativo) THEN
      RAISE EXCEPTION 'Pessoa da equipe inválida.' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM public.usuariosgerenciais WHERE contaid = v_conta AND funcionarioid = p_funcionarioid) THEN
      RAISE EXCEPTION 'Esta pessoa da equipe já está ligada a outro usuário.' USING ERRCODE = 'unique_violation';
    END IF;
  END IF;
  RETURN v_conta;
END;
$$;
REVOKE ALL ON FUNCTION public.preparar_convite_gerente(text, text, integer, integer[], integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.preparar_convite_gerente(text, text, integer, integer[], integer) TO authenticated;

-- O registro do gerente convidado: SÓ o servidor (chave de serviço) chama,
-- depois de conferir pelo token do master (preparar_convite_gerente). Quem
-- convidou fica no histórico (é o "quem" da mudança).
CREATE OR REPLACE FUNCTION public.registrar_gerente_convidado(p_contaid integer, p_userid uuid, p_nome text, p_cargoid integer,
                                                              p_lojas integer[], p_funcionarioid integer, p_quem uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra o gerente convidado.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.contasusuarios WHERE contaid = p_contaid AND userid = p_quem AND papel = 'master') THEN
    RAISE EXCEPTION 'Quem convida tem de ser o master da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', p_quem::text, true);
  INSERT INTO public.contasusuarios (contaid, userid, papel) VALUES (p_contaid, p_userid, 'gerente');
  INSERT INTO public.usuariosgerenciais (contaid, userid, cargoid, funcionarioid, nome, criadopor)
  VALUES (p_contaid, p_userid, p_cargoid, p_funcionarioid, btrim(p_nome), p_quem);
  INSERT INTO public.usuarioslojas (contaid, userid, lojaid)
  SELECT p_contaid, p_userid, l FROM unnest(p_lojas) l;
END;
$$;
REVOKE ALL ON FUNCTION public.registrar_gerente_convidado(integer, uuid, text, integer, integer[], integer, uuid) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.registrar_gerente_convidado(integer, uuid, text, integer, integer[], integer, uuid) TO service_role;

-- Trocar o nome, o cargo, as lojas ou o vínculo de um gerente.
CREATE OR REPLACE FUNCTION public.editar_usuario_gerencial(p_userid uuid, p_nome text, p_cargoid integer, p_lojas integer[],
                                                           p_funcionarioid integer DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_da_pagina_de_usuarios();
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.usuariosgerenciais WHERE contaid = v_conta AND userid = p_userid) THEN
    RAISE EXCEPTION 'Usuário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cargos WHERE contaid = v_conta AND cargoid = p_cargoid) THEN
    RAISE EXCEPTION 'Escolha um cargo.' USING ERRCODE = 'check_violation';
  END IF;
  IF cardinality(coalesce(p_lojas, '{}')) = 0
     OR EXISTS (SELECT 1 FROM unnest(p_lojas) l WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE contaid = v_conta AND lojaid = l AND ativa)) THEN
    RAISE EXCEPTION 'Escolha pelo menos uma loja (ativa).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_funcionarioid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE contaid = v_conta AND funcionarioid = p_funcionarioid) THEN
    RAISE EXCEPTION 'Pessoa da equipe inválida.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.usuariosgerenciais
     SET nome = coalesce(nullif(btrim(coalesce(p_nome, '')), ''), nome), cargoid = p_cargoid, funcionarioid = p_funcionarioid
   WHERE contaid = v_conta AND userid = p_userid
     AND (nome IS DISTINCT FROM coalesce(nullif(btrim(coalesce(p_nome, '')), ''), nome) OR cargoid IS DISTINCT FROM p_cargoid
          OR funcionarioid IS DISTINCT FROM p_funcionarioid);
  DELETE FROM public.usuarioslojas WHERE contaid = v_conta AND userid = p_userid AND lojaid <> ALL (p_lojas);
  INSERT INTO public.usuarioslojas (contaid, userid, lojaid)
  SELECT v_conta, p_userid, l FROM unnest(p_lojas) l
  ON CONFLICT DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.editar_usuario_gerencial(uuid, text, integer, integer[], integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.editar_usuario_gerencial(uuid, text, integer, integer[], integer) TO authenticated;

-- Desativar (o banco nega tudo na hora) ou reativar um gerente.
CREATE OR REPLACE FUNCTION public.ativar_usuario_gerencial(p_userid uuid, p_ativo boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_da_pagina_de_usuarios();
BEGIN
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Usuários e cargos: só o dono da conta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.usuariosgerenciais WHERE contaid = v_conta AND userid = p_userid) THEN
    RAISE EXCEPTION 'Usuário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.usuariosgerenciais SET ativo = p_ativo
   WHERE contaid = v_conta AND userid = p_userid AND ativo IS DISTINCT FROM p_ativo;
END;
$$;
REVOKE ALL ON FUNCTION public.ativar_usuario_gerencial(uuid, boolean) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ativar_usuario_gerencial(uuid, boolean) TO authenticated;

-- O gerente é desta conta e ainda não entrou? (o servidor confere antes de
-- reenviar o convite ou derrubar a sessão). Devolve o e-mail, ou nada.
CREATE OR REPLACE FUNCTION public.email_do_gerente(p_userid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
  SELECT au.email::text FROM public.usuariosgerenciais u JOIN auth.users au ON au.id = u.userid
   WHERE public.sou_master() AND u.contaid = public.minha_conta() AND u.userid = p_userid
$$;
REVOKE ALL ON FUNCTION public.email_do_gerente(uuid) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.email_do_gerente(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- O histórico (só o master lê)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.historico_de_permissoes(p_limite integer DEFAULT 200)
RETURNS TABLE(historicoid bigint, em timestamptz, quem text, tabela character varying, acao character varying, antes jsonb, depois jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.em, coalesce(public.autor_em(h.quem, h.em), CASE WHEN h.quem IS NULL THEN 'Sistema' ELSE 'desconhecido' END),
         h.tabela, h.acao, h.antes, h.depois
    FROM public.permissoeshistorico h
   WHERE public.sou_master() AND h.contaid = public.minha_conta()
   ORDER BY h.em DESC, h.historicoid DESC
   LIMIT greatest(1, least(coalesce(p_limite, 200), 1000))
$$;
REVOKE ALL ON FUNCTION public.historico_de_permissoes(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_de_permissoes(integer) TO authenticated;

-- acesso_por_email: parte da versão viva (de 20260929247000_fechar_papel_gerente.sql); aceita o gerente ativo.
CREATE OR REPLACE FUNCTION public.acesso_por_email(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
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
  -- Parte 5 (30/09/2026): o gerente ATIVO também entra por aqui.
  IF NOT (u.ehadmin OR u.papel IN ('master', 'loja')
          OR (u.papel = 'gerente' AND EXISTS (SELECT 1 FROM public.usuariosgerenciais ug
                                               WHERE ug.userid = u.userid AND ug.ativo))) THEN
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
$function$;
