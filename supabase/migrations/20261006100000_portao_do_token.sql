-- CLASSIFICAÇÃO: ACRESCENTA
-- (só cria: o schema portao, a tabela das nossas chaves de assinatura e a
-- função que roda antes de cada pedido. Com a tabela vazia, a função não faz
-- nada com nenhum token: o site no ar continua igual.)
--
-- 06/10/2026 — o PORTÃO do WhatsApp (docs/PROPOSTA_WHATSAPP_CONSULTAS.md, 6.4),
-- obrigatório antes de qualquer fatia (decisão do Wisley).
--
-- Quem tiver a nossa chave de assinatura (a do porteiro) consegue fabricar um
-- token de SERVIDOR. Este portão faz o banco, pela API, aceitar dessa chave só
-- os dois formatos fixos:
--   A: role authenticated, um usuário (sub), canal "whatsapp", até 5 minutos;
--   B: role wa_porteiro, sem usuário, canal "whatsapp_porteiro", até 60 segundos.
-- Qualquer outro token assinado por uma chave nossa é recusado ("Token
-- recusado."). Tokens de outras chaves (os logins do Supabase, a chave de
-- servidor, o visitante) passam sem mudança nenhuma.
--
-- Como sabe que a chave é nossa: pelo "kid" do cabeçalho do token, registrado
-- em portao.chavesproprias (só pelo SQL Editor; ninguém pela API).
--
-- Fica num schema próprio, fora da API: ninguém chama estas funções pelo
-- navegador. Só o PostgREST, por dentro, antes de cada pedido.
--
-- Limite: vale para o banco pela API (PostgREST). Storage e Auth não passam
-- por aqui; lá a defesa é revogar a chave (proposta, seção 18).

CREATE SCHEMA IF NOT EXISTS portao;
REVOKE ALL ON SCHEMA portao FROM public;
GRANT USAGE ON SCHEMA portao TO anon, authenticated, service_role;

-- As nossas chaves de assinatura (tabela de PLATAFORMA: não é de conta nenhuma).
CREATE TABLE IF NOT EXISTS portao.chavesproprias (
  kid      text PRIMARY KEY CHECK (length(kid) BETWEEN 8 AND 100),
  motivo   text NOT NULL CHECK (length(btrim(motivo)) > 0),
  criadoem timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE portao.chavesproprias IS
  'As chaves de assinatura do STGame importadas no Supabase (o kid). Token assinado por uma delas só vale nos formatos A e B do WhatsApp (portao.token_permitido). Só se mexe pelo SQL Editor.';
ALTER TABLE portao.chavesproprias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON portao.chavesproprias FROM public, anon, authenticated, service_role;

-- A decisão, sem efeito colateral: o pedido com este cabeçalho e estes dados
-- do token pode seguir? (Separada para o teste conferir o RESULTADO.)
CREATE OR REPLACE FUNCTION portao.token_permitido(p_autorizacao text, p_claims jsonb)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET jit = off
AS $$
DECLARE
  v_seg text;
  v_cab jsonb;
  v_kid text;
  v_vida bigint;
BEGIN
  -- Sem token: o visitante (e o que o PostgREST já recusou por conta própria).
  IF p_autorizacao IS NULL OR p_autorizacao !~* '^bearer ' THEN
    RETURN true;
  END IF;
  -- O cabeçalho do token (a primeira parte, em base64url).
  v_seg := split_part(substr(p_autorizacao, 8), '.', 1);
  BEGIN
    v_seg := translate(v_seg, '-_', '+/');
    v_seg := v_seg || repeat('=', (4 - length(v_seg) % 4) % 4);
    v_cab := convert_from(decode(v_seg, 'base64'), 'UTF8')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    -- Ilegível: não é um token que o PostgREST aceitaria; ele mesmo recusa.
    RETURN true;
  END;
  v_kid := v_cab ->> 'kid';
  IF v_kid IS NULL OR NOT EXISTS (SELECT 1 FROM portao.chavesproprias k WHERE k.kid = v_kid) THEN
    RETURN true;  -- não é chave nossa
  END IF;

  -- É chave nossa: só os dois formatos fixos.
  v_vida := CASE WHEN (p_claims ->> 'exp') ~ '^\d+$' AND (p_claims ->> 'iat') ~ '^\d+$'
                 THEN (p_claims ->> 'exp')::bigint - (p_claims ->> 'iat')::bigint END;
  RETURN coalesce(
    (p_claims ->> 'role' = 'authenticated' AND p_claims ->> 'canal' = 'whatsapp'
     AND coalesce(p_claims ->> 'sub', '') <> '' AND v_vida BETWEEN 1 AND 300)
    OR
    (p_claims ->> 'role' = 'wa_porteiro' AND p_claims ->> 'canal' = 'whatsapp_porteiro'
     AND NOT p_claims ? 'sub' AND v_vida BETWEEN 1 AND 60),
    false);
END;
$$;
REVOKE ALL ON FUNCTION portao.token_permitido(text, jsonb) FROM public, anon, authenticated, service_role;

-- Roda antes de CADA pedido ao banco pela API (pgrst.db_pre_request).
CREATE OR REPLACE FUNCTION portao.antes_de_cada_pedido()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET jit = off
AS $$
BEGIN
  IF NOT portao.token_permitido(
           nullif(current_setting('request.headers', true), '')::json ->> 'authorization',
           nullif(current_setting('request.jwt.claims', true), '')::jsonb) THEN
    RAISE EXCEPTION 'Token recusado.' USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION portao.antes_de_cada_pedido() FROM public;
GRANT EXECUTE ON FUNCTION portao.antes_de_cada_pedido() TO anon, authenticated, service_role;

-- Liga no PostgREST, sem pisar numa função "antes de cada pedido" que já
-- exista com outro nome (se existir, nada é aplicado: chame o Claude).
DO $$
DECLARE v_atual text;
BEGIN
  IF to_regrole('authenticator') IS NULL THEN
    RETURN;  -- banco de teste, sem o PostgREST
  END IF;
  SELECT s INTO v_atual
    FROM pg_db_role_setting d
    JOIN pg_roles r ON r.oid = d.setrole, unnest(d.setconfig) s
   WHERE r.rolname = 'authenticator' AND d.setdatabase = 0 AND s LIKE 'pgrst.db_pre_request=%';
  IF v_atual IS NOT NULL AND v_atual <> 'pgrst.db_pre_request=portao.antes_de_cada_pedido' THEN
    RAISE EXCEPTION 'Já existe outra função antes de cada pedido (%). Nada foi aplicado: chame o Claude.', v_atual;
  END IF;
  EXECUTE 'ALTER ROLE authenticator SET pgrst.db_pre_request = ''portao.antes_de_cada_pedido''';
END $$;
NOTIFY pgrst, 'reload config';
