-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 2, fatia 13: Equipe.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-permissoes-parte-2-lojas.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929262000_equipe_permissoes.sql
--
-- O QUE MUDA: a gravação da Equipe vira função com as bordas (criar nas lojas
-- dele; dados só da pessoa inteira nas lojas dele; lojas, só as dele; CPF e
-- validador só o master; nunca o próprio). PIN e jornada na pessoa. A escrita
-- direta em funcionarios, funcionarioslojas e jornadas fecha (com a coluna do
-- CPF). Para o master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 2, fatia 13: Equipe (29/09/2026).
--
-- A gravação da Equipe (dados da pessoa e as lojas dela), que a tela fazia
-- direto nas tabelas, vira a função salvar_pessoa, com as BORDAS:
--   - criar: "equipe.criar" em TODAS as lojas escolhidas (sem loja: só master);
--   - dados da pessoa (nome, cargo, setor, telefone, folga): "equipe.editar"
--     com a pessoa INTEIRA dentro das lojas dele;
--   - lojas da pessoa: ele liga e desliga só as lojas DELE ("equipe.editar"
--     em cada loja que muda); as outras ficam como estão;
--   - CPF de quem já existe: só o master (fecha a coluna);
--   - marcar validador: só o master (mais restritivo; anotado);
--   - ninguém mexe no PRÓPRIO cadastro por aqui.
-- Liberar PIN: "equipe.liberar_pin" na pessoa (não mais só master), e nunca o
-- próprio. Ligar pessoa a jornada: "jornada.vincular" na pessoa, nunca a
-- própria. Apagar jornada: só o master, por função. Desativar e criar acesso
-- continuam no servidor, só do master.
-- Para o master nada muda. Nenhum dado é alterado.
-- liberar_pin: parte da versão viva no banco.
CREATE OR REPLACE FUNCTION public.liberar_pin(p_funcionarioid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  t public.travaspin%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE contaid = v_conta AND funcionarioid = p_funcionarioid) THEN
    RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão na pessoa, no banco (usuários gerenciais, parte 2 — Equipe).
  IF NOT public.pode_na_pessoa('equipe.liberar_pin', v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Seu cargo não permite liberar o PIN desta pessoa.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém libera o próprio PIN.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO t FROM public.travaspin WHERE contaid = v_conta AND funcionarioid = p_funcionarioid FOR UPDATE;
  INSERT INTO public.pinliberacoes (contaid, funcionarioid, liberadopor, estavaate, erros)
  VALUES (v_conta, p_funcionarioid, auth.uid(), t.bloqueadoate, t.erros);
  UPDATE public.travaspin SET erros = 0, nivel = 0, bloqueadoate = NULL
   WHERE contaid = v_conta AND funcionarioid = p_funcionarioid;
END;
$function$;

-- vincular_jornada: parte da versão viva no banco (exigia o master).
CREATE OR REPLACE FUNCTION public.vincular_jornada(p_funcionarios integer[], p_jornadaid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Permissão em cada pessoa, no banco (usuários gerenciais, parte 2 — Equipe):
  -- tudo ou nada; e nunca a própria.
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f)
              WHERE NOT public.pode_na_pessoa('jornada.vincular', v_conta, x.f)
                 OR public.e_o_proprio(v_conta, x.f)) THEN
    RAISE EXCEPTION 'Seu cargo não permite ligar à jornada alguma dessas pessoas (ou é você mesmo).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_jornadaid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.jornadas
                                              WHERE contaid = v_conta AND jornadaid = p_jornadaid AND ativa) THEN
    RAISE EXCEPTION 'Jornada não encontrada ou inativa.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.funcionarios SET jornadaid = p_jornadaid
   WHERE contaid = v_conta AND funcionarioid = ANY (p_funcionarios) AND ativo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------------
-- salvar_pessoa: o que a tela da Equipe gravava direto
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_pessoa(p_funcionarioid integer, p_nomecompleto text, p_cpf text,
                                                p_cargo text, p_setor text, p_telefone text, p_diadefolga integer,
                                                p_lojas integer[], p_validador integer[] DEFAULT '{}')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_lojas  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_lojas, '{}'::integer[])) x ORDER BY 1);
  v_valid  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_validador, '{}'::integer[])) x
                               WHERE x = ANY (coalesce(p_lojas, '{}'::integer[])) ORDER BY 1);
  f        public.funcionarios%ROWTYPE;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_lojas) x(l)
              WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = x.l AND contaid = v_conta)) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF p_funcionarioid IS NULL THEN
    -- Criar: em todas as lojas escolhidas; sem loja, só o master.
    IF (cardinality(v_lojas) = 0 AND NOT public.pode('equipe.criar', NULL))
       OR EXISTS (SELECT 1 FROM unnest(v_lojas) x(l) WHERE NOT public.pode('equipe.criar', x.l)) THEN
      RAISE EXCEPTION 'Seu cargo não permite cadastrar pessoa nessas lojas.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF cardinality(v_valid) > 0 AND NOT public.sou_master() THEN
      RAISE EXCEPTION 'Só o dono da conta marca quem valida.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    INSERT INTO public.funcionarios (contaid, nomecompleto, cpf, cargo, setor, telefonewhatsapp, diadefolga)
    VALUES (v_conta, p_nomecompleto, p_cpf, p_cargo, p_setor, p_telefone, p_diadefolga)
    RETURNING funcionarioid INTO v_id;
  ELSE
    SELECT * INTO f FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Pessoa não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    v_id := f.funcionarioid;
    IF NOT public.sou_master() THEN
      IF public.e_o_proprio(v_conta, v_id) THEN
        RAISE EXCEPTION 'Ninguém mexe no próprio cadastro por aqui.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- Dados da pessoa: ela inteira dentro das lojas dele.
      IF (p_nomecompleto, p_cargo, p_setor, p_telefone, p_diadefolga)
           IS DISTINCT FROM (f.nomecompleto::text, f.cargo::text, f.setor::text, f.telefonewhatsapp::text, f.diadefolga)
         AND NOT public.pode_na_pessoa('equipe.editar', v_conta, v_id) THEN
        RAISE EXCEPTION 'Seu cargo não permite mudar os dados desta pessoa (ela trabalha em loja fora das suas).'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- CPF de quem já existe: só o master.
      IF public.so_digitos(p_cpf) IS DISTINCT FROM f.cpf THEN
        RAISE EXCEPTION 'Só o dono da conta muda o CPF de quem já está cadastrado.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- Lojas: só as dele mudam; quem valida, só o master.
      IF EXISTS (
           SELECT 1
             FROM (SELECT l FROM unnest(v_lojas) l
                   UNION SELECT lojaid FROM public.funcionarioslojas WHERE funcionarioid = v_id AND ativo) u(l)
             LEFT JOIN public.funcionarioslojas fl ON fl.funcionarioid = v_id AND fl.lojaid = u.l
            WHERE coalesce(fl.ativo, false) IS DISTINCT FROM (u.l = ANY (v_lojas))
              AND NOT public.pode('equipe.editar', u.l)) THEN
        RAISE EXCEPTION 'Seu cargo não permite tirar nem pôr esta pessoa em loja fora das suas.' USING ERRCODE = 'insufficient_privilege';
      END IF;
      IF EXISTS (
           SELECT 1
             FROM (SELECT l FROM unnest(v_lojas) l
                   UNION SELECT lojaid FROM public.funcionarioslojas WHERE funcionarioid = v_id) u(l)
             LEFT JOIN public.funcionarioslojas fl ON fl.funcionarioid = v_id AND fl.lojaid = u.l
            WHERE coalesce(fl.validador AND fl.ativo, false) IS DISTINCT FROM (u.l = ANY (v_valid))) THEN
        RAISE EXCEPTION 'Só o dono da conta marca quem valida.' USING ERRCODE = 'insufficient_privilege';
      END IF;
    END IF;
    UPDATE public.funcionarios
       SET nomecompleto = p_nomecompleto, cpf = p_cpf, cargo = p_cargo, setor = p_setor,
           telefonewhatsapp = p_telefone, diadefolga = p_diadefolga
     WHERE funcionarioid = v_id;
  END IF;

  -- As lojas, como a tela fazia: sair de uma loja é desativar o vínculo, nunca
  -- apagar (o histórico daquela loja aponta para ele).
  INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid, ativo, validador)
  SELECT v_conta, v_id, l, true, l = ANY (v_valid) FROM unnest(v_lojas) l
  ON CONFLICT (funcionarioid, lojaid) DO UPDATE SET ativo = true, validador = EXCLUDED.validador;
  UPDATE public.funcionarioslojas SET ativo = false, validador = false
   WHERE funcionarioid = v_id AND NOT (lojaid = ANY (v_lojas)) AND (ativo OR validador);
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[], integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[], integer[]) TO authenticated;

-- Apagar jornada: só o master (a tela apagava direto na tabela).
CREATE OR REPLACE FUNCTION public.apagar_jornada(p_jornadaid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta apaga jornada.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.apagar_jornada(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.apagar_jornada(integer) TO authenticated;

-- A gravação direta fecha: funcionarios (e a coluna do CPF), funcionarioslojas, jornadas.
REVOKE INSERT, UPDATE, DELETE ON public.funcionarios, public.funcionarioslojas, public.jornadas FROM authenticated;
-- O direito de gravar por COLUNA também sai (ele sobrevive ao REVOKE da tabela).
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT DISTINCT table_name, column_name, privilege_type
             FROM information_schema.column_privileges
            WHERE grantee = 'authenticated' AND table_schema = 'public'
              AND table_name IN ('funcionarios', 'funcionarioslojas', 'jornadas')
              AND privilege_type IN ('INSERT', 'UPDATE') LOOP
    EXECUTE format('REVOKE %s (%I) ON public.%I FROM authenticated', c.privilege_type, c.column_name, c.table_name);
  END LOOP;
END $$;


COMMIT;
