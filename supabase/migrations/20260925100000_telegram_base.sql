-- Etapa 1.13A: base do Telegram (@STGameAppBot).
--
-- Regras (decisões do Wisley, 22/09/2026):
--   * Um bot só, da plataforma. O webhook (Edge Function) confere o
--     secret_token e chama SÓ as funções bot_* deste arquivo, com a chave de
--     servidor (service_role). Nenhuma delas é liberada para o navegador.
--   * O bot usa as MESMAS funções de negócio das telas. Para isso, as funções
--     bot_* entram num "contexto do bot" (conta, funcionário, canal), que só
--     vale quando quem chama é o servidor. Um usuário logado nunca consegue
--     ativar esse contexto (o teste de isolamento confere).
--   * Todo ponto continua passando pelo livro movimentospontos.
--   * Convite de uso único, 48 h, código longo e aleatório; só o hash fica
--     guardado. Tentativas de código erradas são limitadas.
--   * Aprovação pelo Telegram: só o master e funcionários "validador" da loja.
--   * Nenhuma tabela guarda texto de mensagem junto com quem mandou.

-- ---------------------------------------------------------------------------
-- 1. Contexto do bot
-- ---------------------------------------------------------------------------

-- Quem chama é o servidor? (service_role pela API, ou o dono do banco nas
-- rotinas e nos testes). Um usuário logado ('authenticated') nunca é.
CREATE OR REPLACE FUNCTION public.bot_contexto_confiavel()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(nullif(current_setting('role', true), ''), 'none') = 'service_role'
      OR (coalesce(nullif(current_setting('role', true), ''), 'none') = 'none' AND session_user = 'postgres')
$$;

CREATE OR REPLACE FUNCTION public.conta_do_bot()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.bot_contexto_confiavel()
              THEN nullif(current_setting('stgame.bot_conta', true), '')::integer END
$$;

CREATE OR REPLACE FUNCTION public.funcionario_do_bot()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.bot_contexto_confiavel()
              THEN nullif(current_setting('stgame.bot_funcionario', true), '')::integer END
$$;

-- Canal da ação: 'telegram' dentro do contexto do bot; 'app' no resto.
CREATE OR REPLACE FUNCTION public.canal_atual()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.bot_contexto_confiavel()
                   AND nullif(current_setting('stgame.bot_canal', true), '') IS NOT NULL
              THEN current_setting('stgame.bot_canal', true) ELSE 'app' END
$$;

-- Origem gravada nas ações: a do bot quando é o próprio funcionário pelo
-- Telegram; 'gestor' no resto (telas e master pelo Telegram).
CREATE OR REPLACE FUNCTION public.origem_da_acao(p_origem_bot text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN public.funcionario_do_bot() IS NOT NULL THEN p_origem_bot ELSE 'gestor' END
$$;

-- A conta de quem está logado ou, no contexto do bot, a conta do vínculo.
CREATE OR REPLACE FUNCTION public.minha_conta()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT contaid FROM public.contasusuarios WHERE userid = auth.uid()),
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
     AND c.contaid = coalesce((SELECT contaid FROM public.contasusuarios WHERE userid = auth.uid()),
                              public.conta_do_bot())
$$;

-- Entra no contexto do bot (só dentro das funções bot_*, até o fim da transação).
-- Master pelo Telegram: age como o próprio login (auth.uid() = master).
-- Funcionário pelo Telegram: sem login; o funcionário fica no contexto.
CREATE OR REPLACE FUNCTION public.bot_entrar(p_contaid integer, p_funcionarioid integer, p_userid uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Contexto do bot só no servidor.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM set_config('stgame.bot_conta', p_contaid::text, true);
  PERFORM set_config('stgame.bot_funcionario', coalesce(p_funcionarioid::text, ''), true);
  PERFORM set_config('stgame.bot_canal', 'telegram', true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_userid::text, ''), true);
  PERFORM set_config('request.jwt.claims',
                     CASE WHEN p_userid IS NULL THEN '{"role":"service_role"}'
                          ELSE json_build_object('sub', p_userid, 'role', 'authenticated')::text END, true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Marcas e colunas novas
-- ---------------------------------------------------------------------------
ALTER TABLE public.funcionarioslojas ADD COLUMN validador boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.funcionarioslojas.validador IS 'Pode aprovar e recusar entregas desta loja pelo Telegram (e usar /lancar e /pendencias).';

ALTER TABLE public.entregas ADD COLUMN canalenvio varchar(10) NOT NULL DEFAULT 'app' CHECK (canalenvio IN ('app', 'telegram'));
ALTER TABLE public.entregas ADD COLUMN canalvalidacao varchar(10) CHECK (canalvalidacao IN ('app', 'telegram'));
ALTER TABLE public.entregas ADD COLUMN validadorfuncionarioid integer;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_validador_fk FOREIGN KEY (contaid, validadorfuncionarioid)
  REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;
ALTER TABLE public.entregas ADD COLUMN fotoidunico text;
ALTER TABLE public.entregas ADD COLUMN avisochatid bigint;
ALTER TABLE public.entregas ADD COLUMN avisomsgid bigint;
CREATE UNIQUE INDEX entregas_foto_unica ON public.entregas (contaid, fotoidunico) WHERE fotoidunico IS NOT NULL;

ALTER TABLE public.documentosacessos ADD COLUMN funcionarioid integer;
ALTER TABLE public.documentosacessos ADD COLUMN canal varchar(10) NOT NULL DEFAULT 'app' CHECK (canal IN ('app', 'telegram'));
ALTER TABLE public.documentosacessos ADD CONSTRAINT documentosacessos_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
  REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT;

-- Quem enviou, quem validou e por qual canal (preenchido sozinho).
CREATE OR REPLACE FUNCTION public.entrega_marca_canal()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.canalenvio := public.canal_atual();
  ELSIF OLD.statusvalidacao = 'Pendente' AND NEW.statusvalidacao IN ('Aprovada', 'Recusada') THEN
    NEW.canalvalidacao := public.canal_atual();
    NEW.validadorfuncionarioid := public.funcionario_do_bot();
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER entregas_marca_canal BEFORE INSERT OR UPDATE OF statusvalidacao ON public.entregas
  FOR EACH ROW EXECUTE FUNCTION public.entrega_marca_canal();

-- ---------------------------------------------------------------------------
-- 3. Vínculos com o Telegram (pessoa, master e grupos da loja)
-- ---------------------------------------------------------------------------
CREATE TABLE public.telegramvinculos (
  vinculoid     integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  tipo          varchar(10) NOT NULL CHECK (tipo IN ('pessoa', 'master', 'grupo')),
  chatid        bigint NOT NULL,
  funcionarioid integer,
  userid        uuid,
  lojaid        integer,
  papelgrupo    varchar(10) CHECK (papelgrupo IN ('equipe', 'gestao')),
  nometelegram  varchar(120),
  ativo         boolean NOT NULL DEFAULT true,
  vinculadoem   timestamptz NOT NULL DEFAULT now(),
  desligadoem   timestamptz,
  desligadopor  uuid,
  CONSTRAINT telegramvinculos_conta_unico UNIQUE (contaid, vinculoid),
  CONSTRAINT telegramvinculos_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT telegramvinculos_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT,
  CONSTRAINT telegramvinculos_formato CHECK (
       (tipo = 'pessoa' AND funcionarioid IS NOT NULL AND userid IS NULL AND lojaid IS NULL AND papelgrupo IS NULL AND chatid > 0)
    OR (tipo = 'master' AND userid IS NOT NULL AND funcionarioid IS NULL AND lojaid IS NULL AND papelgrupo IS NULL AND chatid > 0)
    OR (tipo = 'grupo'  AND lojaid IS NOT NULL AND papelgrupo IS NOT NULL AND funcionarioid IS NULL AND userid IS NULL AND chatid < 0))
);
-- Um Telegram por pessoa; um chat por pessoa/master em cada conta; um grupo
-- em uma conta só; um grupo de cada papel por loja.
CREATE UNIQUE INDEX telegramvinculos_pessoa_uma ON public.telegramvinculos (funcionarioid) WHERE ativo AND tipo = 'pessoa';
CREATE UNIQUE INDEX telegramvinculos_master_um ON public.telegramvinculos (contaid, userid) WHERE ativo AND tipo = 'master';
CREATE UNIQUE INDEX telegramvinculos_chat_conta ON public.telegramvinculos (contaid, chatid) WHERE ativo AND tipo <> 'grupo';
CREATE UNIQUE INDEX telegramvinculos_grupo_um ON public.telegramvinculos (chatid) WHERE ativo AND tipo = 'grupo';
CREATE UNIQUE INDEX telegramvinculos_loja_papel ON public.telegramvinculos (contaid, lojaid, papelgrupo) WHERE ativo AND tipo = 'grupo';
CREATE INDEX telegramvinculos_chat_idx ON public.telegramvinculos (chatid) WHERE ativo;

ALTER TABLE public.telegramvinculos ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.telegramvinculos TO authenticated;
GRANT ALL ON public.telegramvinculos TO service_role;
CREATE POLICY telegramvinculos_sel ON public.telegramvinculos FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- Convites (só o hash do código fica guardado).
CREATE TABLE public.telegramconvites (
  conviteid     integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  tipo          varchar(10) NOT NULL CHECK (tipo IN ('pessoa', 'master', 'grupo')),
  funcionarioid integer,
  userid        uuid,
  lojaid        integer,
  papelgrupo    varchar(10) CHECK (papelgrupo IN ('equipe', 'gestao')),
  codigohash    text NOT NULL UNIQUE,
  expiraem      timestamptz NOT NULL,
  usadoem       timestamptz,
  canceladoem   timestamptz,
  criadopor     uuid,
  criadoem      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT telegramconvites_conta_unico UNIQUE (contaid, conviteid),
  CONSTRAINT telegramconvites_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT telegramconvites_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);
ALTER TABLE public.telegramconvites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.telegramconvites FROM anon, authenticated;
GRANT ALL ON public.telegramconvites TO service_role;

-- Avisos dentro do sistema (ex.: "Bruna ligou o Telegram agora").
CREATE TABLE public.avisossistema (
  avisoid  integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid  integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  tipo     varchar(30) NOT NULL,
  texto    varchar(300) NOT NULL,
  criadoem timestamptz NOT NULL DEFAULT now(),
  lidoem   timestamptz,
  CONSTRAINT avisossistema_conta_unico UNIQUE (contaid, avisoid)
);
CREATE INDEX avisossistema_conta_idx ON public.avisossistema (contaid, criadoem DESC);
ALTER TABLE public.avisossistema ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.avisossistema TO authenticated;
GRANT ALL ON public.avisossistema TO service_role;
CREATE POLICY avisossistema_sel ON public.avisossistema FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- ---------------------------------------------------------------------------
-- 4. Fila de envio e medição de uso
-- ---------------------------------------------------------------------------
-- Só avisos e rotinas passam pela fila (a resposta a uma ação da própria
-- pessoa sai direto do webhook). O texto fica aqui só até ser enviado; depois
-- de 7 dias a linha é apagada.
CREATE TABLE public.mensagensfila (
  filaid      bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid     integer NOT NULL REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  lojaid      integer,
  chatid      bigint NOT NULL,
  tipo        varchar(30) NOT NULL,
  conteudo    jsonb NOT NULL,
  referencia  integer,
  status      varchar(12) NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'enviando', 'enviada', 'falhou', 'descartada')),
  tentativas  integer NOT NULL DEFAULT 0,
  proximaem   timestamptz NOT NULL DEFAULT now(),
  criadoem    timestamptz NOT NULL DEFAULT now(),
  enviadoem   timestamptz,
  erro        varchar(300),
  CONSTRAINT mensagensfila_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);
CREATE INDEX mensagensfila_pendentes_idx ON public.mensagensfila (proximaem) WHERE status = 'pendente';
CREATE INDEX mensagensfila_chat_idx ON public.mensagensfila (chatid, enviadoem) WHERE status = 'enviada';
ALTER TABLE public.mensagensfila ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mensagensfila FROM anon, authenticated;
GRANT ALL ON public.mensagensfila TO service_role;

-- Medição de uso: conta, loja, canal, tipo e dia. Nunca o texto.
CREATE TABLE public.usomensagens (
  contaid    integer NOT NULL REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  lojaid     integer,
  canal      varchar(10) NOT NULL CHECK (canal IN ('telegram', 'whatsapp')),
  tipo       varchar(30) NOT NULL,
  dia        date NOT NULL,
  quantidade integer NOT NULL DEFAULT 0,
  CONSTRAINT usomensagens_loja_fk FOREIGN KEY (contaid, lojaid) REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX usomensagens_um ON public.usomensagens (contaid, coalesce(lojaid, 0), canal, tipo, dia);
ALTER TABLE public.usomensagens ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.usomensagens TO authenticated;
GRANT ALL ON public.usomensagens TO service_role;
CREATE POLICY usomensagens_sel ON public.usomensagens FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- ---------------------------------------------------------------------------
-- 5. Controle técnico do bot (schema próprio, sem acesso para o navegador)
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS bot;
REVOKE ALL ON SCHEMA bot FROM public, anon, authenticated;

-- Mensagens do Telegram já processadas (a mesma nunca é tratada duas vezes).
CREATE TABLE bot.updates (
  updateid   bigint PRIMARY KEY,
  recebidoem timestamptz NOT NULL DEFAULT now()
);
-- Tentativas de código erradas, por chat (contra adivinhação).
CREATE TABLE bot.tentativas (
  chatid bigint NOT NULL,
  em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tentativas_chat_idx ON bot.tentativas (chatid, em);
-- Passo da conversa (ex.: esperando a foto da tarefa X). Nunca guarda texto.
CREATE TABLE bot.estados (
  chatid    bigint NOT NULL,
  usuarioid bigint NOT NULL,
  contaid   integer NOT NULL,
  estado    varchar(30) NOT NULL,
  dados     jsonb NOT NULL DEFAULT '{}',
  criadoem  timestamptz NOT NULL DEFAULT now(),
  expiraem  timestamptz NOT NULL,
  PRIMARY KEY (chatid, usuarioid)
);
-- Empresa escolhida por quem trabalha em mais de uma empresa cliente.
CREATE TABLE bot.contaativa (
  chatid  bigint PRIMARY KEY,
  contaid integer NOT NULL
);
ALTER TABLE bot.updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot.tentativas ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot.estados ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot.contaativa ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA bot FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. O que as telas chamam (master)
-- ---------------------------------------------------------------------------

-- Código novo: 64 caracteres aleatórios (dois UUID v4). Só o hash é guardado.
CREATE OR REPLACE FUNCTION public.telegram_novo_codigo()
RETURNS text
LANGUAGE sql
VOLATILE
SET search_path = public, pg_temp
AS $$
  SELECT replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
$$;

CREATE OR REPLACE FUNCTION public.telegram_hash(p_codigo text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT encode(sha256(convert_to(p_codigo, 'UTF8')), 'hex')
$$;

-- Convite para uma pessoa da equipe. Cancela convites anteriores não usados.
CREATE OR REPLACE FUNCTION public.criar_convite_telegram(p_funcionarioid integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.exige_master_editavel();
  v_codigo text := public.telegram_novo_codigo();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta AND ativo) THEN
    RAISE EXCEPTION 'Funcionário ativo não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.telegramconvites SET canceladoem = now()
   WHERE contaid = v_conta AND tipo = 'pessoa' AND funcionarioid = p_funcionarioid
     AND usadoem IS NULL AND canceladoem IS NULL;
  INSERT INTO public.telegramconvites (contaid, tipo, funcionarioid, codigohash, expiraem, criadopor)
  VALUES (v_conta, 'pessoa', p_funcionarioid, public.telegram_hash(v_codigo), now() + interval '48 hours', auth.uid());
  RETURN v_codigo;
END;
$$;

-- Convite para o grupo da equipe ou de gestão de uma loja da própria conta.
CREATE OR REPLACE FUNCTION public.criar_convite_grupo(p_lojaid integer, p_papel text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.exige_master_editavel();
  v_codigo text := public.telegram_novo_codigo();
BEGIN
  IF p_papel NOT IN ('equipe', 'gestao') THEN
    RAISE EXCEPTION 'Tipo de grupo inválido.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.telegramconvites SET canceladoem = now()
   WHERE contaid = v_conta AND tipo = 'grupo' AND lojaid = p_lojaid AND papelgrupo = p_papel
     AND usadoem IS NULL AND canceladoem IS NULL;
  INSERT INTO public.telegramconvites (contaid, tipo, lojaid, papelgrupo, codigohash, expiraem, criadopor)
  VALUES (v_conta, 'grupo', p_lojaid, p_papel, public.telegram_hash(v_codigo), now() + interval '48 hours', auth.uid());
  RETURN v_codigo;
END;
$$;

-- Convite para o Telegram do próprio master (Meu perfil).
CREATE OR REPLACE FUNCTION public.criar_convite_meu_telegram()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.exige_master_editavel();
  v_codigo text := public.telegram_novo_codigo();
BEGIN
  UPDATE public.telegramconvites SET canceladoem = now()
   WHERE contaid = v_conta AND tipo = 'master' AND userid = auth.uid() AND usadoem IS NULL AND canceladoem IS NULL;
  INSERT INTO public.telegramconvites (contaid, tipo, userid, codigohash, expiraem, criadopor)
  VALUES (v_conta, 'master', auth.uid(), public.telegram_hash(v_codigo), now() + interval '48 hours', auth.uid());
  RETURN v_codigo;
END;
$$;

-- Desliga um vínculo (pessoa, grupo ou o próprio Telegram).
CREATE OR REPLACE FUNCTION public.desligar_telegram(p_vinculoid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.exige_master_editavel();
BEGIN
  UPDATE public.telegramvinculos SET ativo = false, desligadoem = now(), desligadopor = auth.uid()
   WHERE vinculoid = p_vinculoid AND contaid = v_conta AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vínculo não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.marcar_aviso_lido(p_avisoid integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.avisossistema SET lidoem = now()
   WHERE avisoid = p_avisoid AND contaid = public.minha_conta() AND lidoem IS NULL
$$;

-- ---------------------------------------------------------------------------
-- 7. Funções de negócio: a origem passa a vir do canal (a regra é a mesma).
--    Pelo Telegram, a própria pessoa: feedback e justificativa = 'bot';
--    ciência de comunicado e de documento = 'funcionario'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_feedback(
  p_funcionarioid integer,
  p_dia           date,
  p_nota          integer,
  p_comentario    text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta  integer := public.minha_conta_editavel();
  v_hoje   date    := public.dia_em_sao_paulo(now());
  v_func   public.funcionarios%ROWTYPE;
  v_bonus  integer;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_func FROM public.funcionarios
   WHERE funcionarioid = p_funcionarioid AND contaid = v_conta FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT v_func.ativo THEN
    RAISE EXCEPTION 'Esta pessoa está inativa.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia IS NULL OR p_dia NOT IN (v_hoje, v_hoje - 1) THEN
    RAISE EXCEPTION 'O feedback só pode ser de hoje ou de ontem.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_nota IS NULL OR p_nota NOT BETWEEN 0 AND 10 THEN
    RAISE EXCEPTION 'A nota vai de 0 a 10.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT CASE WHEN valor ~ '^[0-9]+$' THEN valor::integer ELSE 0 END INTO v_bonus
    FROM public.configuracoes WHERE contaid = v_conta AND chave = 'PONTOS_BONUS_FEEDBACK_DIARIO';
  v_bonus := coalesce(v_bonus, 0);

  BEGIN
    INSERT INTO public.feedbacks (contaid, funcionarioid, datafeedback, notadia, comentario, origem, registradopor, pontosbonus)
    VALUES (v_conta, p_funcionarioid, p_dia, p_nota, nullif(btrim(coalesce(p_comentario, '')), ''), public.origem_da_acao('bot'), auth.uid(), v_bonus)
    RETURNING feedbackid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION '% já tem feedback de %.', v_func.nomecompleto, to_char(p_dia, 'DD/MM/YYYY')
      USING ERRCODE = 'unique_violation';
  END;

  IF v_bonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, p_funcionarioid, 'bonus', v_bonus,
            'Feedback do dia ' || to_char(p_dia, 'DD/MM/YYYY'), v_id, auth.uid());
  END IF;

  PERFORM public.avaliar_conquistas(v_conta, p_funcionarioid);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_justificativa(
  p_atribuicaoid integer,
  p_dia          date,
  p_motivo       text,
  p_aceitar      boolean
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_aceitar IS NULL THEN
    RAISE EXCEPTION 'Escolha se já aceita ou se fica para decidir.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_atr FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta AND funcionarioid IS NOT NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa atribuída não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.justificaveis(v_atr.funcionarioid, p_dia)) x
                  WHERE (x->>'atribuicaoid')::integer = p_atribuicaoid) THEN
    RAISE EXCEPTION 'Nesse dia a tarefa não caía para a pessoa, ou já foi entregue ou justificada, ou era folga.'
      USING ERRCODE = 'check_violation';
  END IF;

  BEGIN
    INSERT INTO public.justificativas (contaid, lojaid, atribuicaoid, funcionarioid, dia, motivo, status,
                                       origem, registradopor, decididopor, decididoem)
    VALUES (v_conta, v_atr.lojaid, p_atribuicaoid, v_atr.funcionarioid, p_dia, btrim(p_motivo),
            CASE WHEN p_aceitar THEN 'Aceita' ELSE 'Pendente' END,
            public.origem_da_acao('bot'), auth.uid(),
            CASE WHEN p_aceitar THEN auth.uid() END,
            CASE WHEN p_aceitar THEN now() END)
    RETURNING justificativaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Esta tarefa já tem justificativa neste dia.' USING ERRCODE = 'unique_violation';
  END;

  IF p_aceitar THEN
    PERFORM public.avaliar_conquistas(v_conta, v_atr.funcionarioid);
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_ciencia(p_assinaturaid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  s public.documentosassinaturas%ROWTYPE;
  d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO s FROM public.documentosassinaturas WHERE assinaturaid = p_assinaturaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Destinatário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = s.documentoid FOR UPDATE;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não aceita ciência nova.' USING ERRCODE = 'check_violation';
  END IF;
  IF s.statusassinatura = 'Ciente' THEN
    RETURN false;   -- ja estava: nada muda, nada e pago de novo
  END IF;

  UPDATE public.documentosassinaturas
     SET statusassinatura = 'Ciente', dataciencia = now(), origem = public.origem_da_acao('funcionario'), registradopor = auth.uid(),
         pontospagos = d.pontosporciencia
   WHERE assinaturaid = p_assinaturaid;
  IF d.primeiracienciaem IS NULL THEN
    UPDATE public.documentos SET primeiracienciaem = now() WHERE documentoid = d.documentoid;
  END IF;

  IF d.pontosporciencia > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, assinaturaid, criadopor)
    VALUES (v_conta, s.funcionarioid, 'bonus', d.pontosporciencia, 'Ciência do comunicado: ' || d.titulo,
            p_assinaturaid, auth.uid());
  END IF;
  PERFORM public.avaliar_conquistas(v_conta, s.funcionarioid);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_ciencia_documento(p_documentoid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel(); v_n integer; v_fid integer := public.funcionario_do_bot();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- O master, ou a própria pessoa dona do documento (pelo Telegram).
  IF NOT public.sou_master() AND NOT (v_fid IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.documentospessoais
        WHERE documentoid = p_documentoid AND contaid = v_conta AND funcionarioid = v_fid AND situacao = 'Ativo')) THEN
    RAISE EXCEPTION 'Só o responsável pela conta mexe nos documentos pessoais.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentospessoais
                  WHERE documentoid = p_documentoid AND contaid = v_conta AND situacao IN ('Ativo', 'Arquivado')) THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.documentospessoaisciencia
     SET status = 'Ciente', dataciencia = now(), origem = public.origem_da_acao('funcionario'), registradopor = auth.uid()
   WHERE documentoid = p_documentoid AND contaid = v_conta AND status = 'Pendente';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;


-- ---------------------------------------------------------------------------
-- 8. Peças internas do bot
-- ---------------------------------------------------------------------------

-- Texto seguro para o modo HTML do Telegram.
CREATE OR REPLACE FUNCTION public.bot_html(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT replace(replace(replace(coalesce(p_texto, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$$;

-- Quem é este chat privado: a pessoa (funcionário ativo) ou o master, na
-- empresa ativa. Se estiver em mais de uma empresa e não escolheu, volta vazio
-- com a lista de opções (só as empresas em que este chat está ligado).
CREATE OR REPLACE FUNCTION public.bot_quem(p_chatid bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_opcoes jsonb;
  v_n      integer;
  v_escolha integer;
  r        record;
BEGIN
  SELECT count(*), jsonb_agg(jsonb_build_object('contaid', x.contaid, 'empresa', x.empresa) ORDER BY x.empresa)
    INTO v_n, v_opcoes
    FROM (SELECT DISTINCT v.contaid, c.nome AS empresa
            FROM public.telegramvinculos v
            JOIN public.contas c ON c.contaid = v.contaid AND c.status IN ('ativa', 'suspensa')
            LEFT JOIN public.funcionarios f ON f.funcionarioid = v.funcionarioid AND f.contaid = v.contaid
           WHERE v.chatid = p_chatid AND v.ativo AND v.tipo IN ('pessoa', 'master')
             AND (v.tipo = 'master' OR f.ativo)) x;
  IF v_n = 0 THEN
    RETURN jsonb_build_object('status', 'sem_vinculo');
  END IF;

  SELECT contaid INTO v_escolha FROM bot.contaativa WHERE chatid = p_chatid;
  IF v_n > 1 AND (v_escolha IS NULL OR NOT v_opcoes @> jsonb_build_array(jsonb_build_object('contaid', v_escolha))) THEN
    RETURN jsonb_build_object('status', 'escolher', 'opcoes', v_opcoes);
  END IF;

  SELECT v.contaid, v.tipo, v.funcionarioid, v.userid, c.nome AS empresa, c.status AS situacao,
         f.nomecompleto AS nome,
         (SELECT min(fl.lojaid) FROM public.funcionarioslojas fl JOIN public.lojas l ON l.lojaid = fl.lojaid AND l.ativa
           WHERE fl.funcionarioid = v.funcionarioid AND fl.ativo) AS lojaid
    INTO r
    FROM public.telegramvinculos v
    JOIN public.contas c ON c.contaid = v.contaid
    LEFT JOIN public.funcionarios f ON f.funcionarioid = v.funcionarioid AND f.contaid = v.contaid
   WHERE v.chatid = p_chatid AND v.ativo AND v.tipo IN ('pessoa', 'master')
     AND c.status IN ('ativa', 'suspensa') AND (v.tipo = 'master' OR f.ativo)
     AND (v_n = 1 OR v.contaid = v_escolha)
   ORDER BY (v.tipo = 'pessoa') DESC
   LIMIT 1;

  RETURN jsonb_build_object('status', 'ok', 'contaid', r.contaid, 'tipo', r.tipo, 'funcionarioid', r.funcionarioid,
                            'userid', r.userid, 'nome', coalesce(r.nome, 'responsável'), 'empresa', r.empresa,
                            'suspensa', r.situacao = 'suspensa', 'lojaid', r.lojaid, 'varias', v_n > 1,
                            'opcoes', v_opcoes);
END;
$$;

-- A pessoa deste chat (só funcionário ativo), ou erro.
CREATE OR REPLACE FUNCTION public.bot_pessoa_do_chat(p_chatid bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb := public.bot_quem(p_chatid);
BEGIN
  IF q->>'status' <> 'ok' OR q->>'tipo' <> 'pessoa' THEN
    RAISE EXCEPTION 'sem_vinculo' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN q;
END;
$$;

-- Entra no contexto da pessoa deste chat. Devolve a pessoa.
CREATE OR REPLACE FUNCTION public.bot_entrar_pessoa(p_chatid bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb := public.bot_pessoa_do_chat(p_chatid);
BEGIN
  PERFORM public.bot_entrar((q->>'contaid')::integer, (q->>'funcionarioid')::integer, NULL);
  RETURN q;
END;
$$;

-- Resposta padrão de erro das funções bot_*.
CREATE OR REPLACE FUNCTION public.bot_erro(p_mensagem text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('ok', false,
                            'erro', CASE WHEN p_mensagem = 'sem_vinculo' THEN 'sem_vinculo' ELSE 'regra' END,
                            'mensagem', p_mensagem)
$$;

-- Trava de pendências (decisão b): resgate e comanda só depois do feedback de
-- ontem, se ontem foi dia de trabalho.
CREATE OR REPLACE FUNCTION public.bot_falta_feedback_ontem(p_contaid integer, p_funcionarioid integer)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento,
                                public.dia_em_sao_paulo(now()) - 1)
     AND NOT EXISTS (SELECT 1 FROM public.feedbacks fb
                      WHERE fb.contaid = p_contaid AND fb.funcionarioid = p_funcionarioid
                        AND fb.datafeedback = public.dia_em_sao_paulo(now()) - 1 AND fb.anuladoem IS NULL)
    FROM public.funcionarios f
   WHERE f.funcionarioid = p_funcionarioid AND f.contaid = p_contaid
$$;

-- Guarda o passo da conversa (nunca texto).
CREATE OR REPLACE FUNCTION public.bot_guardar_estado(p_chatid bigint, p_usuarioid bigint, p_contaid integer,
                                                   p_estado text, p_dados jsonb, p_minutos integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO bot.estados (chatid, usuarioid, contaid, estado, dados, criadoem, expiraem)
  VALUES (p_chatid, p_usuarioid, p_contaid, p_estado, coalesce(p_dados, '{}'), now(), now() + make_interval(mins => p_minutos))
  ON CONFLICT (chatid, usuarioid) DO UPDATE
    SET contaid = EXCLUDED.contaid, estado = EXCLUDED.estado, dados = EXCLUDED.dados,
        criadoem = EXCLUDED.criadoem, expiraem = EXCLUDED.expiraem
$$;

-- ---------------------------------------------------------------------------
-- 9. O que o webhook chama (só o servidor)
-- ---------------------------------------------------------------------------

-- A mesma mensagem do Telegram só é tratada uma vez.
CREATE OR REPLACE FUNCTION public.bot_registrar_update(p_updateid bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_n integer;
BEGIN
  INSERT INTO bot.updates (updateid) VALUES (p_updateid) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  DELETE FROM bot.updates WHERE recebidoem < now() - interval '3 days';
  DELETE FROM bot.tentativas WHERE em < now() - interval '1 day';
  DELETE FROM bot.estados WHERE expiraem < now() - interval '1 day';
  RETURN v_n = 1;
END;
$$;

-- Usa um convite. Código errado, vencido, usado ou do tipo errado: "inválido".
-- Mais de 5 erros em 1 hora no mesmo chat: bloqueado (mesma resposta).
CREATE OR REPLACE FUNCTION public.bot_usar_convite(p_chatid bigint, p_tipochat text, p_codigo text, p_nome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c        public.telegramconvites%ROWTYPE;
  v_grupo  public.telegramvinculos%ROWTYPE;
  v_valido boolean := false;
  v_nome   text;
  v_loja   text;
BEGIN
  IF (SELECT count(*) FROM bot.tentativas WHERE chatid = p_chatid AND em > now() - interval '1 hour') >= 5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'bloqueado');
  END IF;

  IF p_codigo ~ '^[0-9a-f]{64}$' THEN
    SELECT * INTO c FROM public.telegramconvites
     WHERE codigohash = public.telegram_hash(p_codigo) AND usadoem IS NULL AND canceladoem IS NULL AND expiraem > now()
     FOR UPDATE;
    v_valido := FOUND
      AND EXISTS (SELECT 1 FROM public.contas WHERE contaid = c.contaid AND status = 'ativa')
      AND ((c.tipo IN ('pessoa', 'master') AND p_tipochat = 'private')
        OR (c.tipo = 'grupo' AND p_tipochat IN ('group', 'supergroup') AND p_chatid < 0))
      AND (c.tipo <> 'pessoa' OR EXISTS (SELECT 1 FROM public.funcionarios
                                          WHERE funcionarioid = c.funcionarioid AND contaid = c.contaid AND ativo));
  END IF;

  IF v_valido AND c.tipo = 'grupo' THEN
    SELECT * INTO v_grupo FROM public.telegramvinculos WHERE chatid = p_chatid AND tipo = 'grupo' AND ativo;
    IF FOUND AND NOT (v_grupo.contaid = c.contaid AND v_grupo.lojaid = c.lojaid AND v_grupo.papelgrupo = c.papelgrupo) THEN
      v_valido := false;   -- grupo já ligado a outra loja ou empresa
    END IF;
  END IF;

  IF NOT v_valido THEN
    INSERT INTO bot.tentativas (chatid) VALUES (p_chatid);
    RETURN jsonb_build_object('ok', false, 'erro', 'invalido');
  END IF;

  UPDATE public.telegramconvites SET usadoem = now() WHERE conviteid = c.conviteid;

  IF c.tipo = 'pessoa' THEN
    UPDATE public.telegramvinculos SET ativo = false, desligadoem = now()
     WHERE ativo AND ((tipo = 'pessoa' AND funcionarioid = c.funcionarioid)
                   OR (contaid = c.contaid AND chatid = p_chatid AND tipo <> 'grupo'));
    INSERT INTO public.telegramvinculos (contaid, tipo, chatid, funcionarioid, nometelegram)
    VALUES (c.contaid, 'pessoa', p_chatid, c.funcionarioid, left(p_nome, 120));
    SELECT nomecompleto INTO v_nome FROM public.funcionarios WHERE funcionarioid = c.funcionarioid;
  ELSIF c.tipo = 'master' THEN
    UPDATE public.telegramvinculos SET ativo = false, desligadoem = now()
     WHERE ativo AND contaid = c.contaid AND ((tipo = 'master' AND userid = c.userid) OR (chatid = p_chatid AND tipo <> 'grupo'));
    INSERT INTO public.telegramvinculos (contaid, tipo, chatid, userid, nometelegram)
    VALUES (c.contaid, 'master', p_chatid, c.userid, left(p_nome, 120));
  ELSE
    IF v_grupo.vinculoid IS NULL THEN
      UPDATE public.telegramvinculos SET ativo = false, desligadoem = now()
       WHERE ativo AND tipo = 'grupo' AND contaid = c.contaid AND lojaid = c.lojaid AND papelgrupo = c.papelgrupo;
      INSERT INTO public.telegramvinculos (contaid, tipo, chatid, lojaid, papelgrupo, nometelegram)
      VALUES (c.contaid, 'grupo', p_chatid, c.lojaid, c.papelgrupo, left(p_nome, 120));
    END IF;
    SELECT nome INTO v_loja FROM public.lojas WHERE lojaid = c.lojaid;
  END IF;

  DELETE FROM bot.contaativa WHERE chatid = p_chatid;
  RETURN jsonb_build_object('ok', true, 'tipo', c.tipo, 'nome', v_nome, 'loja', v_loja, 'papel', c.papelgrupo,
                            'empresa', (SELECT nome FROM public.contas WHERE contaid = c.contaid));
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_escolher_conta(p_chatid bigint, p_contaid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.telegramvinculos
                  WHERE chatid = p_chatid AND contaid = p_contaid AND ativo AND tipo IN ('pessoa', 'master')) THEN
    RETURN public.bot_erro('sem_vinculo');
  END IF;
  INSERT INTO bot.contaativa (chatid, contaid) VALUES (p_chatid, p_contaid)
  ON CONFLICT (chatid) DO UPDATE SET contaid = EXCLUDED.contaid;
  RETURN public.bot_quem(p_chatid) || jsonb_build_object('ok', true);
END;
$$;

-- Tarefas de hoje da própria pessoa, em todas as lojas dela.
CREATE OR REPLACE FUNCTION public.bot_tarefas(p_chatid bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_fid integer; v_conta integer;
BEGIN
  q := public.bot_pessoa_do_chat(p_chatid);
  v_fid := (q->>'funcionarioid')::integer; v_conta := (q->>'contaid')::integer;
  RETURN jsonb_build_object('ok', true, 'pessoa', q->>'nome', 'tarefas', coalesce((
    SELECT jsonb_agg(jsonb_build_object('atribuicaoid', a.atribuicaoid, 'titulo', a.titulo, 'pontos', a.pontos,
                                        'loja', l.nome, 'atrasada', a.atrasada) ORDER BY a.atrasada DESC, a.titulo)
      FROM public.funcionarioslojas fl
      JOIN public.lojas l ON l.lojaid = fl.lojaid AND l.contaid = v_conta AND l.ativa
      CROSS JOIN LATERAL public.atribuicoes_para_entregar(fl.lojaid) a
     WHERE fl.funcionarioid = v_fid AND fl.contaid = v_conta AND fl.ativo AND a.funcionarioid = v_fid), '[]'::jsonb));
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Consultas do menu (só da própria pessoa).
CREATE OR REPLACE FUNCTION public.bot_consulta(p_chatid bigint, p_item text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  q       jsonb;
  v_fid   integer;
  v_conta integer;
  v_hoje  date := public.dia_em_sao_paulo(now());
  v_taxa  numeric;
  v_saldo integer;
BEGIN
  q := public.bot_pessoa_do_chat(p_chatid);
  v_fid := (q->>'funcionarioid')::integer; v_conta := (q->>'contaid')::integer;
  SELECT saldopontos INTO v_saldo FROM public.funcionarios WHERE funcionarioid = v_fid AND contaid = v_conta;
  v_taxa := public.taxa_da_conta(v_conta);

  IF p_item = 'saldo' THEN
    RETURN jsonb_build_object('ok', true, 'saldo', v_saldo, 'reais', CASE WHEN v_taxa IS NOT NULL THEN round(v_saldo * v_taxa, 2) END);

  ELSIF p_item = 'historico' THEN
    RETURN jsonb_build_object('ok', true, 'itens', public.historico_da_pessoa(v_fid, 10));

  ELSIF p_item = 'conquistas' THEN
    RETURN jsonb_build_object('ok', true, 'itens', coalesce((
      SELECT jsonb_agg(jsonb_build_object('nome', k.nome, 'icone', k.icone, 'descricao', k.descricao,
                                          'dia', public.dia_em_sao_paulo(cf.dataconquista), 'pontos', cf.pontosbonus)
                       ORDER BY cf.dataconquista DESC)
        FROM public.conquistasfuncionarios cf
        JOIN public.conquistas k ON k.conquistaid = cf.conquistaid AND k.contaid = v_conta
       WHERE cf.funcionarioid = v_fid AND cf.contaid = v_conta), '[]'::jsonb));

  ELSIF p_item = 'ranking' THEN
    RETURN jsonb_build_object('ok', true, 'itens', coalesce((
      SELECT jsonb_agg(jsonb_build_object('posicao', x.pos, 'nome', public.nome_curto(x.nomecompleto), 'nota', x.nota,
                                          'eu', x.funcionarioid = v_fid) ORDER BY x.pos)
        FROM (SELECT r.*, row_number() OVER (ORDER BY r.nota DESC, r.pontosganhos DESC, r.nomecompleto) AS pos
                FROM public.ranking_mensal_da_conta(v_conta, extract(year FROM v_hoje)::integer,
                                                    extract(month FROM v_hoje)::integer, NULL, v_hoje - 1) r) x
       WHERE x.pos <= 5 OR x.funcionarioid = v_fid), '[]'::jsonb));

  ELSIF p_item = 'meta' THEN
    RETURN jsonb_build_object('ok', true, 'lojas', coalesce((
      SELECT jsonb_agg(jsonb_build_object('loja', l.nome, 'meta', public.meta_para_painel(v_conta, l.lojaid, true)) ORDER BY l.nome)
        FROM public.funcionarioslojas fl JOIN public.lojas l ON l.lojaid = fl.lojaid AND l.contaid = v_conta AND l.ativa
       WHERE fl.funcionarioid = v_fid AND fl.contaid = v_conta AND fl.ativo), '[]'::jsonb));

  ELSIF p_item = 'premios' THEN
    RETURN jsonb_build_object('ok', true, 'saldo', v_saldo, 'taxa', v_taxa,
      'travado', public.bot_falta_feedback_ontem(v_conta, v_fid),
      'itens', coalesce((SELECT jsonb_agg(jsonb_build_object('produtoid', p.produtoid, 'nome', p.nome, 'custo', p.custoempontos,
                                                             'estoque', p.estoquedisponivel) ORDER BY p.custoempontos, p.nome)
                           FROM public.produtosloja p
                          WHERE p.contaid = v_conta AND p.ativo AND p.sistema IS NULL
                            AND (p.estoquedisponivel IS NULL OR p.estoquedisponivel > 0)), '[]'::jsonb),
      'comanda', EXISTS (SELECT 1 FROM public.produtosloja WHERE contaid = v_conta AND sistema = 'abate_comanda' AND ativo));

  ELSIF p_item = 'comunicados' THEN
    RETURN jsonb_build_object('ok', true, 'itens', coalesce((
      SELECT jsonb_agg(jsonb_build_object('assinaturaid', s.assinaturaid, 'titulo', d.titulo, 'conteudo', left(d.conteudo, 3000),
                                          'pontos', d.pontosporciencia) ORDER BY s.dataenvio)
        FROM public.documentosassinaturas s
        JOIN public.documentos d ON d.documentoid = s.documentoid AND d.contaid = v_conta AND d.status = 'Publicado'
       WHERE s.funcionarioid = v_fid AND s.contaid = v_conta AND s.statusassinatura = 'Pendente'), '[]'::jsonb));

  ELSIF p_item = 'documentos' THEN
    RETURN jsonb_build_object('ok', true, 'itens', coalesce((
      SELECT jsonb_agg(jsonb_build_object('documentoid', d.documentoid, 'tipo', d.tipodocumento,
                                          'mes', to_char(d.mesano, 'MM/YYYY'),
                                          'pendente', EXISTS (SELECT 1 FROM public.documentospessoaisciencia c
                                                               WHERE c.documentoid = d.documentoid AND c.status = 'Pendente'))
                       ORDER BY d.dataupload DESC)
        FROM (SELECT * FROM public.documentospessoais
               WHERE funcionarioid = v_fid AND contaid = v_conta AND situacao = 'Ativo'
               ORDER BY dataupload DESC LIMIT 10) d), '[]'::jsonb));

  ELSIF p_item = 'feedback' THEN
    RETURN jsonb_build_object('ok', true,
      'hoje', EXISTS (SELECT 1 FROM public.feedbacks WHERE contaid = v_conta AND funcionarioid = v_fid
                       AND datafeedback = v_hoje AND anuladoem IS NULL),
      'faltaontem', public.bot_falta_feedback_ontem(v_conta, v_fid));
  END IF;
  RETURN public.bot_erro('Opção desconhecida.');
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- "Enviar foto": a foto precisa chegar em até 10 minutos.
CREATE OR REPLACE FUNCTION public.bot_iniciar_entrega(p_chatid bigint, p_atribuicaoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_t jsonb;
BEGIN
  q := public.bot_tarefas(p_chatid);
  IF NOT (q->>'ok')::boolean THEN RETURN q; END IF;
  SELECT x INTO v_t FROM jsonb_array_elements(q->'tarefas') x WHERE (x->>'atribuicaoid')::integer = p_atribuicaoid;
  IF v_t IS NULL THEN
    RETURN public.bot_erro('Esta tarefa não está mais na sua lista de hoje.');
  END IF;
  PERFORM public.bot_guardar_estado(p_chatid, p_chatid, (public.bot_quem(p_chatid)->>'contaid')::integer,
                                    'foto', jsonb_build_object('atribuicaoid', p_atribuicaoid), 10);
  RETURN jsonb_build_object('ok', true, 'titulo', v_t->>'titulo');
END;
$$;

-- Confere a foto antes de baixar: tarefa escolhida, janela de 10 min e foto nova.
CREATE OR REPLACE FUNCTION public.bot_conferir_foto(p_chatid bigint, p_fotoidunico text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; e bot.estados%ROWTYPE; v_loja integer; v_titulo text;
BEGIN
  q := public.bot_pessoa_do_chat(p_chatid);
  SELECT * INTO e FROM bot.estados WHERE chatid = p_chatid AND usuarioid = p_chatid AND estado = 'foto';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_tarefa');
  END IF;
  IF e.expiraem < now() THEN
    DELETE FROM bot.estados WHERE chatid = p_chatid AND usuarioid = p_chatid;
    RETURN jsonb_build_object('ok', false, 'erro', 'expirou');
  END IF;
  IF EXISTS (SELECT 1 FROM public.entregas WHERE contaid = (q->>'contaid')::integer AND fotoidunico = p_fotoidunico) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'repetida');
  END IF;
  SELECT ta.lojaid, t.titulo INTO v_loja, v_titulo
    FROM public.tarefasatribuidas ta JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
   WHERE ta.atribuicaoid = (e.dados->>'atribuicaoid')::integer AND ta.contaid = (q->>'contaid')::integer
     AND ta.funcionarioid = (q->>'funcionarioid')::integer;
  IF v_loja IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_tarefa');
  END IF;
  RETURN jsonb_build_object('ok', true, 'atribuicaoid', (e.dados->>'atribuicaoid')::integer,
                            'contaid', (q->>'contaid')::integer, 'lojaid', v_loja, 'titulo', v_titulo);
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Registra a entrega com a foto já guardada no Storage (mesma função das telas).
CREATE OR REPLACE FUNCTION public.bot_registrar_entrega(p_chatid bigint, p_atribuicaoid integer, p_caminho text,
                                                      p_fileid text, p_fotoidunico text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_id integer; v_conf jsonb;
BEGIN
  v_conf := public.bot_conferir_foto(p_chatid, p_fotoidunico);
  IF NOT (v_conf->>'ok')::boolean THEN RETURN v_conf; END IF;
  IF (v_conf->>'atribuicaoid')::integer <> p_atribuicaoid THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_tarefa');
  END IF;
  q := public.bot_entrar_pessoa(p_chatid);
  BEGIN
    v_id := public.registrar_entrega(p_atribuicaoid, NULL, p_caminho, false);
    UPDATE public.entregas SET fileidtelegram = left(p_fileid, 250), fotoidunico = p_fotoidunico
     WHERE entregaid = v_id AND contaid = (q->>'contaid')::integer;
  EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('ok', false, 'erro', 'repetida', 'mensagem', SQLERRM);
    WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  DELETE FROM bot.estados WHERE chatid = p_chatid AND usuarioid = p_chatid;
  RETURN jsonb_build_object('ok', true, 'entregaid', v_id, 'titulo', v_conf->>'titulo');
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Passo atual da conversa (para saber o que fazer com o texto recebido).
CREATE OR REPLACE FUNCTION public.bot_estado(p_chatid bigint, p_usuarioid bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT jsonb_build_object('estado', estado, 'dados', dados)
                     FROM bot.estados WHERE chatid = p_chatid AND usuarioid = p_usuarioid AND expiraem > now()),
                  '{}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION public.bot_limpar_estado(p_chatid bigint, p_usuarioid bigint)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  DELETE FROM bot.estados WHERE chatid = p_chatid AND usuarioid = p_usuarioid
$$;

-- "Não se aplica": pede o motivo; depois registra a justificativa pendente.
CREATE OR REPLACE FUNCTION public.bot_nao_aplicavel_iniciar(p_chatid bigint, p_atribuicaoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_t jsonb;
BEGIN
  q := public.bot_tarefas(p_chatid);
  IF NOT (q->>'ok')::boolean THEN RETURN q; END IF;
  SELECT x INTO v_t FROM jsonb_array_elements(q->'tarefas') x WHERE (x->>'atribuicaoid')::integer = p_atribuicaoid;
  IF v_t IS NULL THEN
    RETURN public.bot_erro('Esta tarefa não está mais na sua lista de hoje.');
  END IF;
  PERFORM public.bot_guardar_estado(p_chatid, p_chatid, (public.bot_quem(p_chatid)->>'contaid')::integer,
                                    'nao_aplicavel', jsonb_build_object('atribuicaoid', p_atribuicaoid), 30);
  RETURN jsonb_build_object('ok', true, 'titulo', v_t->>'titulo');
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_nao_aplicavel(p_chatid bigint, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; e jsonb := public.bot_estado(p_chatid, p_chatid); v_atr integer;
BEGIN
  IF e->>'estado' IS DISTINCT FROM 'nao_aplicavel' THEN
    RETURN public.bot_erro('Escolha a tarefa de novo em "Minhas tarefas".');
  END IF;
  v_atr := (e->'dados'->>'atribuicaoid')::integer;
  q := public.bot_entrar_pessoa(p_chatid);
  IF NOT EXISTS (SELECT 1 FROM public.tarefasatribuidas WHERE atribuicaoid = v_atr
                    AND contaid = (q->>'contaid')::integer AND funcionarioid = (q->>'funcionarioid')::integer) THEN
    RETURN public.bot_erro('Tarefa não encontrada.');
  END IF;
  BEGIN
    PERFORM public.registrar_justificativa(v_atr, public.dia_em_sao_paulo(now()), p_motivo, false);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  PERFORM public.bot_limpar_estado(p_chatid, p_chatid);
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Feedback do dia (hoje ou ontem), mesma função das telas (bônus pelo livro).
CREATE OR REPLACE FUNCTION public.bot_feedback(p_chatid bigint, p_quando text, p_nota integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_dia date := public.dia_em_sao_paulo(now()) - CASE WHEN p_quando = 'ontem' THEN 1 ELSE 0 END;
        v_bonus integer;
BEGIN
  q := public.bot_entrar_pessoa(p_chatid);
  BEGIN
    PERFORM public.registrar_feedback((q->>'funcionarioid')::integer, v_dia, p_nota, NULL);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  SELECT pontosbonus INTO v_bonus FROM public.feedbacks
   WHERE contaid = (q->>'contaid')::integer AND funcionarioid = (q->>'funcionarioid')::integer AND datafeedback = v_dia AND anuladoem IS NULL;
  RETURN jsonb_build_object('ok', true, 'bonus', coalesce(v_bonus, 0), 'dia', v_dia);
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Resgate de prêmio (fica pendente para a gestão entregar). Trava: feedback de ontem.
CREATE OR REPLACE FUNCTION public.bot_resgatar(p_chatid bigint, p_produtoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_id integer;
BEGIN
  q := public.bot_entrar_pessoa(p_chatid);
  IF public.bot_falta_feedback_ontem((q->>'contaid')::integer, (q->>'funcionarioid')::integer) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'falta_feedback');
  END IF;
  BEGIN
    v_id := public.registrar_troca((q->>'funcionarioid')::integer, p_produtoid, (q->>'lojaid')::integer, false);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'resgateid', v_id,
    'premio', (SELECT nome FROM public.produtosloja WHERE produtoid = p_produtoid),
    'saldo', (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = (q->>'funcionarioid')::integer));
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Abate na comanda: pede o valor; depois registra (pendente para a gestão).
CREATE OR REPLACE FUNCTION public.bot_comanda_iniciar(p_chatid bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_saldo integer; v_taxa numeric;
BEGIN
  q := public.bot_pessoa_do_chat(p_chatid);
  IF public.bot_falta_feedback_ontem((q->>'contaid')::integer, (q->>'funcionarioid')::integer) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'falta_feedback');
  END IF;
  v_taxa := public.taxa_da_conta((q->>'contaid')::integer);
  IF v_taxa IS NULL OR NOT EXISTS (SELECT 1 FROM public.produtosloja
                                    WHERE contaid = (q->>'contaid')::integer AND sistema = 'abate_comanda' AND ativo) THEN
    RETURN public.bot_erro('O abate na comanda não está disponível nesta empresa.');
  END IF;
  SELECT saldopontos INTO v_saldo FROM public.funcionarios WHERE funcionarioid = (q->>'funcionarioid')::integer;
  PERFORM public.bot_guardar_estado(p_chatid, p_chatid, (q->>'contaid')::integer, 'comanda', '{}', 10);
  RETURN jsonb_build_object('ok', true, 'saldo', v_saldo, 'reais', round(v_saldo * v_taxa, 2));
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_comanda(p_chatid bigint, p_valor numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_id integer; r public.resgates%ROWTYPE;
BEGIN
  IF public.bot_estado(p_chatid, p_chatid)->>'estado' IS DISTINCT FROM 'comanda' THEN
    RETURN public.bot_erro('Toque em "Abater na comanda" de novo.');
  END IF;
  q := public.bot_entrar_pessoa(p_chatid);
  IF public.bot_falta_feedback_ontem((q->>'contaid')::integer, (q->>'funcionarioid')::integer) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'falta_feedback');
  END IF;
  BEGIN
    v_id := public.registrar_troca_por_valor((q->>'funcionarioid')::integer, p_valor, (q->>'lojaid')::integer, false);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  PERFORM public.bot_limpar_estado(p_chatid, p_chatid);
  SELECT * INTO r FROM public.resgates WHERE resgateid = v_id;
  RETURN jsonb_build_object('ok', true, 'valor', r.valorreais, 'pontos', r.pontosgastos,
    'saldo', (SELECT saldopontos FROM public.funcionarios WHERE funcionarioid = (q->>'funcionarioid')::integer));
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Ciência de comunicado pela própria pessoa (origem = 'funcionario').
CREATE OR REPLACE FUNCTION public.bot_ciencia(p_chatid bigint, p_assinaturaid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_novo boolean; v_pontos integer; v_titulo text;
BEGIN
  q := public.bot_entrar_pessoa(p_chatid);
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas WHERE assinaturaid = p_assinaturaid
                    AND contaid = (q->>'contaid')::integer AND funcionarioid = (q->>'funcionarioid')::integer) THEN
    RETURN public.bot_erro('Comunicado não encontrado.');
  END IF;
  BEGIN
    v_novo := public.registrar_ciencia(p_assinaturaid);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  SELECT s.pontospagos, d.titulo INTO v_pontos, v_titulo
    FROM public.documentosassinaturas s JOIN public.documentos d ON d.documentoid = s.documentoid
   WHERE s.assinaturaid = p_assinaturaid;
  RETURN jsonb_build_object('ok', true, 'novo', v_novo, 'pontos', CASE WHEN v_novo THEN v_pontos ELSE 0 END,
                            'titulo', v_titulo, 'quando', now());
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- Documento pessoal: só na conversa privada da própria pessoa. Registra o acesso
-- e devolve o caminho; o webhook cria o link de 5 minutos.
CREATE OR REPLACE FUNCTION public.bot_documento(p_chatid bigint, p_tipochat text, p_documentoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; d public.documentospessoais%ROWTYPE;
BEGIN
  IF p_tipochat IS DISTINCT FROM 'private' OR p_chatid <= 0 THEN
    RETURN public.bot_erro('Documentos só na conversa privada com o bot.');
  END IF;
  q := public.bot_pessoa_do_chat(p_chatid);
  SELECT * INTO d FROM public.documentospessoais
   WHERE documentoid = p_documentoid AND contaid = (q->>'contaid')::integer
     AND funcionarioid = (q->>'funcionarioid')::integer AND situacao = 'Ativo';
  IF NOT FOUND THEN
    RETURN public.bot_erro('Documento não encontrado.');
  END IF;
  INSERT INTO public.documentosacessos (contaid, documentoid, caminho, acao, usuario, funcionarioid, canal)
  VALUES (d.contaid, d.documentoid, d.caminhoarquivo, 'visualizacao', NULL, d.funcionarioid, 'telegram');
  RETURN jsonb_build_object('ok', true, 'caminho', d.caminhoarquivo, 'tipo', d.tipodocumento,
                            'mes', to_char(d.mesano, 'MM/YYYY'),
                            'pendente', EXISTS (SELECT 1 FROM public.documentospessoaisciencia
                                                 WHERE documentoid = d.documentoid AND status = 'Pendente'));
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_ciencia_documento(p_chatid bigint, p_documentoid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE q jsonb; v_novo boolean;
BEGIN
  q := public.bot_entrar_pessoa(p_chatid);
  BEGIN
    v_novo := public.registrar_ciencia_documento(p_documentoid);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'novo', v_novo);
EXCEPTION WHEN insufficient_privilege THEN
  RETURN public.bot_erro(SQLERRM);
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Grupos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bot_grupo(p_chatid bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT jsonb_build_object('vinculado', true, 'contaid', v.contaid, 'lojaid', v.lojaid,
                                             'papel', v.papelgrupo, 'loja', l.nome)
                     FROM public.telegramvinculos v
                     JOIN public.lojas l ON l.lojaid = v.lojaid
                     JOIN public.contas c ON c.contaid = v.contaid AND c.status IN ('ativa', 'suspensa')
                    WHERE v.chatid = p_chatid AND v.tipo = 'grupo' AND v.ativo),
                  jsonb_build_object('vinculado', false))
$$;

-- Quem apertou, num grupo de gestão, pode validar? Só o master da conta ou um
-- funcionário ativo marcado como validador daquela loja.
CREATE OR REPLACE FUNCTION public.bot_validador(p_chatgrupo bigint, p_usuario bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE g jsonb := public.bot_grupo(p_chatgrupo); r record;
BEGIN
  IF NOT (g->>'vinculado')::boolean OR g->>'papel' <> 'gestao' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'grupo');
  END IF;
  SELECT v.tipo, v.funcionarioid, v.userid, coalesce(f.nomecompleto, 'Responsável') AS nome INTO r
    FROM public.telegramvinculos v
    LEFT JOIN public.funcionarios f ON f.funcionarioid = v.funcionarioid AND f.contaid = v.contaid
   WHERE v.chatid = p_usuario AND v.contaid = (g->>'contaid')::integer AND v.ativo
     AND (v.tipo = 'master'
          OR (v.tipo = 'pessoa' AND f.ativo AND EXISTS (
                SELECT 1 FROM public.funcionarioslojas fl
                 WHERE fl.funcionarioid = v.funcionarioid AND fl.lojaid = (g->>'lojaid')::integer
                   AND fl.ativo AND fl.validador)))
   ORDER BY (v.tipo = 'master') DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  RETURN g || jsonb_build_object('ok', true, 'tipo', r.tipo, 'funcionarioid', r.funcionarioid,
                                 'userid', r.userid, 'nome', r.nome);
END;
$$;

-- Aprovar ou recusar pelo grupo de gestão (mesmas funções das telas).
CREATE OR REPLACE FUNCTION public.bot_validar(p_chatgrupo bigint, p_usuario bigint, p_entregaid integer,
                                            p_aprovar boolean, p_motivo text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a jsonb := public.bot_validador(p_chatgrupo, p_usuario); e public.entregas%ROWTYPE; v_pontos integer;
BEGIN
  IF NOT (a->>'ok')::boolean THEN RETURN a; END IF;
  SELECT * INTO e FROM public.entregas
   WHERE entregaid = p_entregaid AND contaid = (a->>'contaid')::integer AND lojaid = (a->>'lojaid')::integer;
  IF NOT FOUND THEN
    RETURN public.bot_erro('Entrega não encontrada.');
  END IF;
  PERFORM public.bot_entrar((a->>'contaid')::integer, (a->>'funcionarioid')::integer, (a->>'userid')::uuid);
  BEGIN
    IF p_aprovar THEN
      v_pontos := public.aprovar_entrega(p_entregaid);
    ELSE
      PERFORM public.recusar_entrega(p_entregaid, p_motivo);
    END IF;
  EXCEPTION WHEN check_violation THEN
    SELECT * INTO e FROM public.entregas WHERE entregaid = p_entregaid;
    IF e.statusvalidacao <> 'Pendente' THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'ja_validada', 'status', e.statusvalidacao);
    END IF;
    RETURN public.bot_erro(SQLERRM);
  WHEN OTHERS THEN
    RETURN public.bot_erro(SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'aprovada', p_aprovar, 'pontos', v_pontos, 'validador', a->>'nome',
    'pessoa', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = e.funcionarioid),
    'titulo', (SELECT titulo FROM public.tarefas WHERE tarefaid = e.tarefaid),
    'motivo', btrim(p_motivo));
END;
$$;

-- "Recusar": confere a permissão e guarda que a próxima resposta desta pessoa
-- à pergunta do bot é o motivo (fica no banco, não na memória do bot).
CREATE OR REPLACE FUNCTION public.bot_recusa_pedir(p_chatgrupo bigint, p_usuario bigint, p_entregaid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a jsonb := public.bot_validador(p_chatgrupo, p_usuario); v_status text;
BEGIN
  IF NOT (a->>'ok')::boolean THEN RETURN a; END IF;
  SELECT statusvalidacao INTO v_status FROM public.entregas
   WHERE entregaid = p_entregaid AND contaid = (a->>'contaid')::integer AND lojaid = (a->>'lojaid')::integer;
  IF v_status IS NULL THEN RETURN public.bot_erro('Entrega não encontrada.'); END IF;
  IF v_status <> 'Pendente' THEN RETURN jsonb_build_object('ok', false, 'erro', 'ja_validada', 'status', v_status); END IF;
  RETURN jsonb_build_object('ok', true, 'nome', a->>'nome');
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_recusa_guardar(p_chatgrupo bigint, p_usuario bigint, p_entregaid integer, p_msgid bigint)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.bot_guardar_estado(p_chatgrupo, p_usuario, (public.bot_grupo(p_chatgrupo)->>'contaid')::integer,
                                   'motivo_recusa', jsonb_build_object('entregaid', p_entregaid, 'msgid', p_msgid), 30)
$$;

-- Resposta com o motivo (tem de ser resposta à pergunta do bot, da mesma pessoa).
CREATE OR REPLACE FUNCTION public.bot_recusa_motivo(p_chatgrupo bigint, p_usuario bigint, p_respostaa bigint, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE e jsonb := public.bot_estado(p_chatgrupo, p_usuario); r jsonb;
BEGIN
  IF e->>'estado' IS DISTINCT FROM 'motivo_recusa' OR (e->'dados'->>'msgid')::bigint IS DISTINCT FROM p_respostaa THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_pedido');
  END IF;
  r := public.bot_validar(p_chatgrupo, p_usuario, (e->'dados'->>'entregaid')::integer, false, p_motivo);
  IF (r->>'ok')::boolean OR r->>'erro' = 'ja_validada' THEN
    PERFORM public.bot_limpar_estado(p_chatgrupo, p_usuario);
  END IF;
  RETURN r || jsonb_build_object('entregaid', (e->'dados'->>'entregaid')::integer);
END;
$$;

-- /pendencias no grupo de gestão.
CREATE OR REPLACE FUNCTION public.bot_pendencias(p_chatgrupo bigint, p_usuario bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a jsonb := public.bot_validador(p_chatgrupo, p_usuario);
BEGIN
  IF NOT (a->>'ok')::boolean THEN RETURN a; END IF;
  RETURN jsonb_build_object('ok', true, 'loja', a->>'loja',
    'avalidar', (SELECT count(*) FROM public.entregas WHERE contaid = (a->>'contaid')::integer
                   AND lojaid = (a->>'lojaid')::integer AND statusvalidacao = 'Pendente'),
    'pessoas', coalesce((SELECT jsonb_agg(jsonb_build_object('nome', x.nome, 'tarefas', x.tarefas) ORDER BY x.nome)
                           FROM (SELECT a2.nomecompleto AS nome, jsonb_agg(a2.titulo ORDER BY a2.titulo) AS tarefas
                                   FROM public.atribuicoes_para_entregar((a->>'lojaid')::integer) a2
                                  GROUP BY a2.nomecompleto) x), '[]'::jsonb));
END;
$$;

-- /lancar e /status_meta no grupo de gestão.
CREATE OR REPLACE FUNCTION public.bot_lancar(p_chatgrupo bigint, p_usuario bigint, p_valor numeric, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a jsonb := public.bot_validador(p_chatgrupo, p_usuario);
BEGIN
  IF NOT (a->>'ok')::boolean THEN RETURN a; END IF;
  PERFORM public.bot_entrar((a->>'contaid')::integer, (a->>'funcionarioid')::integer, (a->>'userid')::uuid);
  BEGIN
    PERFORM public.lancar_venda_do_dia((a->>'lojaid')::integer, public.dia_em_sao_paulo(now()), p_valor, p_motivo);
  EXCEPTION WHEN OTHERS THEN RETURN public.bot_erro(SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'loja', a->>'loja', 'validador', a->>'nome',
                            'meta', public.meta_para_painel((a->>'contaid')::integer, (a->>'lojaid')::integer, false));
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_status_meta(p_chatgrupo bigint, p_usuario bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a jsonb := public.bot_validador(p_chatgrupo, p_usuario);
BEGIN
  IF NOT (a->>'ok')::boolean THEN RETURN a; END IF;
  RETURN jsonb_build_object('ok', true, 'loja', a->>'loja',
                            'meta', public.meta_para_painel((a->>'contaid')::integer, (a->>'lojaid')::integer, false));
END;
$$;

-- Medição das respostas imediatas (as da fila são medidas no envio).
CREATE OR REPLACE FUNCTION public.bot_registrar_uso(p_chatid bigint, p_tipo text, p_qtd integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer; v_loja integer;
BEGIN
  IF coalesce(p_qtd, 0) <= 0 THEN RETURN; END IF;
  IF p_chatid < 0 THEN
    SELECT contaid, lojaid INTO v_conta, v_loja FROM public.telegramvinculos WHERE chatid = p_chatid AND tipo = 'grupo' AND ativo;
  ELSE
    v_conta := (public.bot_quem(p_chatid)->>'contaid')::integer;
  END IF;
  IF v_conta IS NULL THEN RETURN; END IF;   -- quem não tem vínculo não é medido
  PERFORM public.usar_mensagens(v_conta, v_loja, 'telegram', left(p_tipo, 30), p_qtd);
END;
$$;

CREATE OR REPLACE FUNCTION public.usar_mensagens(p_contaid integer, p_lojaid integer, p_canal text, p_tipo text, p_qtd integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.usomensagens (contaid, lojaid, canal, tipo, dia, quantidade)
  VALUES (p_contaid, p_lojaid, p_canal, p_tipo, public.dia_em_sao_paulo(now()), p_qtd)
  ON CONFLICT (contaid, coalesce(lojaid, 0), canal, tipo, dia)
  DO UPDATE SET quantidade = public.usomensagens.quantidade + EXCLUDED.quantidade
$$;

-- ---------------------------------------------------------------------------
-- 11. Avisos (entram na fila; o envio respeita os limites do Telegram)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bot_chat_da_pessoa(p_contaid integer, p_funcionarioid integer)
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT v.chatid FROM public.telegramvinculos v
    JOIN public.funcionarios f ON f.funcionarioid = v.funcionarioid AND f.contaid = v.contaid AND f.ativo
   WHERE v.contaid = p_contaid AND v.funcionarioid = p_funcionarioid AND v.tipo = 'pessoa' AND v.ativo
$$;

CREATE OR REPLACE FUNCTION public.bot_chat_do_grupo(p_contaid integer, p_lojaid integer, p_papel text)
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT chatid FROM public.telegramvinculos
   WHERE contaid = p_contaid AND lojaid = p_lojaid AND papelgrupo = p_papel AND tipo = 'grupo' AND ativo
$$;

-- Chama o envio da fila na hora (pg_net). Sem pg_net (testes), não faz nada:
-- o pg_cron também chama a cada 15 segundos.
CREATE OR REPLACE FUNCTION public.bot_fila_disparar()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_url text; v_segredo text;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NULL OR to_regproc('net.http_post') IS NULL THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.mensagensfila WHERE status = 'pendente' AND proximaem <= now()) THEN
    RETURN;
  END IF;
  EXECUTE $q$SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'stgame_funcoes_url'$q$ INTO v_url;
  EXECUTE $q$SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'stgame_fila_segredo'$q$ INTO v_segredo;
  IF v_url IS NULL OR v_segredo IS NULL THEN
    RETURN;
  END IF;
  EXECUTE 'SELECT net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 30000)'
    USING rtrim(v_url, '/') || '/telegram-fila', '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-fila-segredo', v_segredo);
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_enfileirar(p_contaid integer, p_lojaid integer, p_chatid bigint, p_tipo text,
                                               p_conteudo jsonb, p_referencia integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_chatid IS NULL THEN RETURN; END IF;
  INSERT INTO public.mensagensfila (contaid, lojaid, chatid, tipo, conteudo, referencia)
  VALUES (p_contaid, p_lojaid, p_chatid, p_tipo, coalesce(p_conteudo, '{}'), p_referencia);
  PERFORM public.bot_fila_disparar();
END;
$$;

-- Legenda da entrega no grupo de gestão (nova ou já validada).
CREATE OR REPLACE FUNCTION public.bot_legenda_entrega(p_entregaid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE e public.entregas%ROWTYPE; v_pessoa text; v_titulo text; v_pontos integer; v_loja text; v_topo text; v_quem text;
BEGIN
  SELECT * INTO e FROM public.entregas WHERE entregaid = p_entregaid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT nomecompleto INTO v_pessoa FROM public.funcionarios WHERE funcionarioid = e.funcionarioid;
  SELECT titulo, pontos INTO v_titulo, v_pontos FROM public.tarefas WHERE tarefaid = e.tarefaid;
  SELECT nome INTO v_loja FROM public.lojas WHERE lojaid = e.lojaid;
  v_quem := CASE
    WHEN e.validadorfuncionarioid IS NOT NULL THEN (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = e.validadorfuncionarioid)
    ELSE 'responsável' END || CASE WHEN coalesce(e.canalvalidacao, 'app') = 'telegram' THEN ' (Telegram)' ELSE ' (sistema)' END;
  v_topo := CASE e.statusvalidacao
    WHEN 'Pendente' THEN '📋 <b>Nova entrega para validar</b>'
    WHEN 'Aprovada' THEN '✅ <b>Aprovada</b> por ' || public.bot_html(v_quem) || ' · +' || coalesce(e.pontosganhos, 0) || ' pts'
    WHEN 'Recusada' THEN '❌ <b>Recusada</b> por ' || public.bot_html(v_quem) || E'\nMotivo: ' || public.bot_html(e.motivorecusa)
    ELSE '↩️ <b>' || e.statusvalidacao || '</b>' END;
  RETURN jsonb_build_object(
    'texto', v_topo || E'\n👤 ' || public.bot_html(v_pessoa) || E'\n📝 ' || public.bot_html(v_titulo) || ' (' || v_pontos || E' pts)\n🏪 '
             || public.bot_html(v_loja) || ' · ' || to_char(e.dataenvio AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI')
             || CASE WHEN e.observacao IS NOT NULL THEN E'\n💬 ' || public.bot_html(e.observacao) ELSE '' END,
    'pendente', e.statusvalidacao = 'Pendente',
    'foto_tg', e.fileidtelegram,
    'foto_storage', CASE WHEN e.fileidtelegram IS NULL AND e.pathfotoevidencia IS NOT NULL
                         THEN jsonb_build_object('bucket', 'entregas', 'caminho', e.pathfotoevidencia) END,
    'temfoto', e.fileidtelegram IS NOT NULL OR e.pathfotoevidencia IS NOT NULL,
    'avisomsgid', e.avisomsgid,
    'botoes', CASE WHEN e.statusvalidacao = 'Pendente' THEN jsonb_build_array(jsonb_build_array(
                jsonb_build_object('text', '✅ Aprovar', 'callback_data', 'ap:' || e.entregaid),
                jsonb_build_object('text', '❌ Recusar', 'callback_data', 'rc:' || e.entregaid))) END);
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_aviso_entrega()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_titulo text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.statusvalidacao = 'Pendente' THEN
      PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, public.bot_chat_do_grupo(NEW.contaid, NEW.lojaid, 'gestao'),
                                    'entrega_nova', '{}', NEW.entregaid);
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.statusvalidacao = 'Pendente' AND NEW.statusvalidacao IN ('Aprovada', 'Recusada') THEN
    SELECT titulo INTO v_titulo FROM public.tarefas WHERE tarefaid = NEW.tarefaid;
    PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, public.bot_chat_da_pessoa(NEW.contaid, NEW.funcionarioid),
      CASE WHEN NEW.statusvalidacao = 'Aprovada' THEN 'entrega_aprovada' ELSE 'entrega_recusada' END,
      jsonb_build_object('metodo', 'sendMessage', 'texto',
        CASE WHEN NEW.statusvalidacao = 'Aprovada'
             THEN '✅ Sua entrega <b>' || public.bot_html(v_titulo) || '</b> foi aprovada! +' || coalesce(NEW.pontosganhos, 0) || ' pontos.'
             ELSE '❌ Sua entrega <b>' || public.bot_html(v_titulo) || E'</b> foi recusada.\nMotivo: '
                  || public.bot_html(NEW.motivorecusa) || E'\n\nVocê pode enviar de novo em 📋 Minhas tarefas.' END),
      NEW.entregaid);
    -- Validada pelo sistema: atualiza a mensagem do grupo (pelo Telegram, o próprio bot já atualiza).
    IF NEW.avisomsgid IS NOT NULL AND coalesce(NEW.canalvalidacao, 'app') <> 'telegram' THEN
      PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, NEW.avisochatid, 'editar_entrega', '{}', NEW.entregaid);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER entregas_aviso_telegram AFTER INSERT OR UPDATE OF statusvalidacao ON public.entregas
  FOR EACH ROW EXECUTE FUNCTION public.bot_aviso_entrega();

CREATE OR REPLACE FUNCTION public.bot_aviso_conquista()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE k public.conquistas%ROWTYPE;
BEGIN
  SELECT * INTO k FROM public.conquistas WHERE conquistaid = NEW.conquistaid;
  PERFORM public.bot_enfileirar(NEW.contaid, NULL, public.bot_chat_da_pessoa(NEW.contaid, NEW.funcionarioid), 'conquista',
    jsonb_build_object('metodo', 'sendMessage', 'texto',
      '🏅 Nova conquista: ' || coalesce(k.icone, '') || ' <b>' || public.bot_html(k.nome) || '</b>!'
      || CASE WHEN coalesce(NEW.pontosbonus, 0) > 0 THEN ' +' || NEW.pontosbonus || ' pontos de bônus.' ELSE '' END),
    NEW.conquistafuncionarioid);
  RETURN NEW;
END;
$$;
CREATE TRIGGER conquistasfuncionarios_aviso_telegram AFTER INSERT ON public.conquistasfuncionarios
  FOR EACH ROW EXECUTE FUNCTION public.bot_aviso_conquista();

CREATE OR REPLACE FUNCTION public.bot_aviso_meta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_loja text;
BEGIN
  SELECT nome INTO v_loja FROM public.lojas WHERE lojaid = NEW.lojaid;
  PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, public.bot_chat_do_grupo(NEW.contaid, NEW.lojaid, 'equipe'), 'meta_batida',
    jsonb_build_object('metodo', 'sendMessage', 'texto',
      CASE WHEN NEW.tipo = 'mes' THEN '🏆 <b>Meta do mês batida!</b>' ELSE '🎉 <b>Meta do dia batida!</b>' END
      || ' Parabéns, equipe da ' || public.bot_html(v_loja) || '!'
      || CASE WHEN coalesce(NEW.pontos, 0) > 0 THEN ' Cada um ganhou ' || NEW.pontos || ' pontos.' ELSE '' END),
    NEW.premiacaoid);
  RETURN NEW;
END;
$$;
CREATE TRIGGER metaspremiacoes_aviso_telegram AFTER INSERT ON public.metaspremiacoes
  FOR EACH ROW EXECUTE FUNCTION public.bot_aviso_meta();

-- Vínculo novo: aviso no sistema e no Telegram do master.
CREATE OR REPLACE FUNCTION public.bot_aviso_vinculo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_texto text; v_chat bigint;
BEGIN
  v_texto := CASE NEW.tipo
    WHEN 'pessoa' THEN (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = NEW.funcionarioid) || ' ligou o Telegram agora.'
    WHEN 'grupo'  THEN 'O grupo ' || CASE WHEN NEW.papelgrupo = 'gestao' THEN 'de gestão' ELSE 'da equipe' END || ' da '
                       || (SELECT nome FROM public.lojas WHERE lojaid = NEW.lojaid) || ' foi ligado ao Telegram.'
    ELSE 'Seu Telegram foi ligado ao STGame.' END;
  INSERT INTO public.avisossistema (contaid, tipo, texto) VALUES (NEW.contaid, 'telegram_vinculo', left(v_texto, 300));
  IF NEW.tipo <> 'master' THEN
    FOR v_chat IN SELECT chatid FROM public.telegramvinculos WHERE contaid = NEW.contaid AND tipo = 'master' AND ativo LOOP
      PERFORM public.bot_enfileirar(NEW.contaid, NEW.lojaid, v_chat, 'vinculo',
        jsonb_build_object('metodo', 'sendMessage', 'texto', '📲 ' || public.bot_html(v_texto)), NEW.vinculoid);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER telegramvinculos_aviso AFTER INSERT ON public.telegramvinculos
  FOR EACH ROW EXECUTE FUNCTION public.bot_aviso_vinculo();

-- ---------------------------------------------------------------------------
-- 12. Envio da fila (chamado pela Edge Function telegram-fila)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bot_fila_pegar(p_limite integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE r public.mensagensfila%ROWTYPE; v_out jsonb := '[]'; v_cont jsonb := '{}'; v_n integer; v_env jsonb; l jsonb;
BEGIN
  -- Presa em "enviando" há mais de 5 minutos: volta para a fila.
  UPDATE public.mensagensfila SET status = 'pendente' WHERE status = 'enviando' AND proximaem < now() - interval '5 minutes';
  DELETE FROM public.mensagensfila WHERE status IN ('enviada', 'descartada', 'falhou') AND criadoem < now() - interval '7 days';

  FOR r IN SELECT * FROM public.mensagensfila WHERE status = 'pendente' AND proximaem <= now()
            ORDER BY filaid FOR UPDATE SKIP LOCKED LIMIT greatest(p_limite, 1) * 3 LOOP
    EXIT WHEN jsonb_array_length(v_out) >= greatest(p_limite, 1);
    -- Grupos: no máximo 18 por minuto. Conversa privada: até 3 por rodada.
    v_n := coalesce((v_cont->>(r.chatid::text))::integer,
                    CASE WHEN r.chatid < 0 THEN (SELECT count(*)::integer FROM public.mensagensfila
                                                  WHERE chatid = r.chatid AND status = 'enviada'
                                                    AND enviadoem > now() - interval '1 minute') ELSE 0 END);
    CONTINUE WHEN (r.chatid < 0 AND v_n >= 18) OR (r.chatid > 0 AND v_n >= 3);
    v_cont := v_cont || jsonb_build_object(r.chatid::text, v_n + 1);

    IF r.tipo IN ('entrega_nova', 'editar_entrega') THEN
      l := public.bot_legenda_entrega(r.referencia);
      IF l IS NULL OR (r.tipo = 'entrega_nova' AND NOT (l->>'pendente')::boolean) THEN
        UPDATE public.mensagensfila SET status = 'descartada' WHERE filaid = r.filaid;
        CONTINUE;
      END IF;
      IF r.tipo = 'entrega_nova' THEN
        v_env := jsonb_build_object('metodo', CASE WHEN (l->>'temfoto')::boolean THEN 'sendPhoto' ELSE 'sendMessage' END,
                                    'texto', l->>'texto', 'foto_tg', l->'foto_tg', 'foto_storage', l->'foto_storage',
                                    'botoes', l->'botoes');
      ELSE
        v_env := jsonb_build_object('metodo', CASE WHEN (l->>'temfoto')::boolean THEN 'editMessageCaption' ELSE 'editMessageText' END,
                                    'texto', l->>'texto', 'message_id',
                                    (SELECT avisomsgid FROM public.entregas WHERE entregaid = r.referencia));
      END IF;
    ELSE
      v_env := r.conteudo;
    END IF;

    UPDATE public.mensagensfila SET status = 'enviando', tentativas = tentativas + 1, proximaem = now() WHERE filaid = r.filaid;
    v_out := v_out || jsonb_build_array(v_env || jsonb_build_object('filaid', r.filaid, 'chat_id', r.chatid, 'tipo', r.tipo));
  END LOOP;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.bot_fila_resultado(p_filaid bigint, p_ok boolean, p_msgid bigint, p_erro text, p_esperar integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE r public.mensagensfila%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.mensagensfila WHERE filaid = p_filaid FOR UPDATE;
  IF NOT FOUND OR r.status <> 'enviando' THEN RETURN; END IF;
  IF p_ok THEN
    UPDATE public.mensagensfila SET status = 'enviada', enviadoem = now(), erro = NULL WHERE filaid = p_filaid;
    PERFORM public.usar_mensagens(r.contaid, r.lojaid, 'telegram', r.tipo, 1);
    IF r.tipo = 'entrega_nova' AND p_msgid IS NOT NULL THEN
      UPDATE public.entregas SET avisochatid = r.chatid, avisomsgid = p_msgid
       WHERE entregaid = r.referencia AND contaid = r.contaid;
    END IF;
  ELSIF coalesce(p_esperar, 0) > 0 THEN
    UPDATE public.mensagensfila SET status = 'pendente', proximaem = now() + make_interval(secs => p_esperar),
           erro = left(p_erro, 300) WHERE filaid = p_filaid;
  ELSIF r.tentativas >= 5 THEN
    UPDATE public.mensagensfila SET status = 'falhou', erro = left(p_erro, 300) WHERE filaid = p_filaid;
  ELSE
    UPDATE public.mensagensfila SET status = 'pendente', proximaem = now() + make_interval(mins => power(2, r.tentativas)::integer),
           erro = left(p_erro, 300) WHERE filaid = p_filaid;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Permissões: bot_* só para o servidor (service_role); telas só as de convite.
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  -- Internas: ninguém chama direto.
  FOREACH f IN ARRAY ARRAY[
    'public.bot_contexto_confiavel()', 'public.conta_do_bot()', 'public.funcionario_do_bot()', 'public.canal_atual()',
    'public.origem_da_acao(text)', 'public.bot_entrar(integer, integer, uuid)', 'public.entrega_marca_canal()',
    'public.telegram_novo_codigo()', 'public.telegram_hash(text)', 'public.bot_html(text)',
    'public.bot_pessoa_do_chat(bigint)', 'public.bot_entrar_pessoa(bigint)', 'public.bot_erro(text)',
    'public.bot_falta_feedback_ontem(integer, integer)',
    'public.bot_guardar_estado(bigint, bigint, integer, text, jsonb, integer)',
    'public.bot_chat_da_pessoa(integer, integer)', 'public.bot_chat_do_grupo(integer, integer, text)',
    'public.bot_fila_disparar()', 'public.bot_enfileirar(integer, integer, bigint, text, jsonb, integer)',
    'public.bot_aviso_entrega()', 'public.bot_aviso_conquista()', 'public.bot_aviso_meta()', 'public.bot_aviso_vinculo()',
    'public.usar_mensagens(integer, integer, text, text, integer)', 'public.bot_validador(bigint, bigint)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
  END LOOP;

  -- O webhook e a fila (Edge Functions, com a chave de servidor).
  FOREACH f IN ARRAY ARRAY[
    'public.bot_registrar_update(bigint)', 'public.bot_usar_convite(bigint, text, text, text)', 'public.bot_quem(bigint)',
    'public.bot_escolher_conta(bigint, integer)', 'public.bot_tarefas(bigint)', 'public.bot_consulta(bigint, text)',
    'public.bot_iniciar_entrega(bigint, integer)', 'public.bot_conferir_foto(bigint, text)',
    'public.bot_registrar_entrega(bigint, integer, text, text, text)', 'public.bot_estado(bigint, bigint)',
    'public.bot_limpar_estado(bigint, bigint)', 'public.bot_nao_aplicavel_iniciar(bigint, integer)',
    'public.bot_nao_aplicavel(bigint, text)', 'public.bot_feedback(bigint, text, integer)',
    'public.bot_resgatar(bigint, integer)', 'public.bot_comanda_iniciar(bigint)', 'public.bot_comanda(bigint, numeric)',
    'public.bot_ciencia(bigint, integer)', 'public.bot_documento(bigint, text, integer)',
    'public.bot_ciencia_documento(bigint, integer)', 'public.bot_grupo(bigint)',
    'public.bot_validar(bigint, bigint, integer, boolean, text)', 'public.bot_recusa_pedir(bigint, bigint, integer)',
    'public.bot_recusa_guardar(bigint, bigint, integer, bigint)', 'public.bot_recusa_motivo(bigint, bigint, bigint, text)',
    'public.bot_pendencias(bigint, bigint)', 'public.bot_lancar(bigint, bigint, numeric, text)',
    'public.bot_status_meta(bigint, bigint)', 'public.bot_registrar_uso(bigint, text, integer)',
    'public.bot_legenda_entrega(integer)', 'public.bot_fila_pegar(integer)',
    'public.bot_fila_resultado(bigint, boolean, bigint, text, integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;

  -- As telas (conferem quem chamou; não recebem conta).
  FOREACH f IN ARRAY ARRAY[
    'public.criar_convite_telegram(integer)', 'public.criar_convite_grupo(integer, text)',
    'public.criar_convite_meu_telegram()', 'public.desligar_telegram(integer)', 'public.marcar_aviso_lido(integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 14. Agendamento da fila (a cada 15 s, só no Supabase)
-- ---------------------------------------------------------------------------
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net') THEN
    CREATE EXTENSION IF NOT EXISTS pg_net;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    EXECUTE $$SELECT cron.schedule('stgame-telegram-fila', '15 seconds', 'SELECT public.bot_fila_disparar()')$$;
  ELSE
    RAISE NOTICE 'pg_cron indisponível aqui: fila do Telegram não agendada (ambiente de teste).';
  END IF;
END
$cron$;
