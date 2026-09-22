-- Etapa 1.10 (antiga Fase 11): RH — comunicados, documentos pessoais e
-- onboarding. Decisoes do Wisley em 22/09/2026, em docs/PLANO_MIGRACAO.md.
--
-- - Sem portal do funcionario: o gestor registra ciencias; o modelo ja
--   guarda a origem ('gestor' ou 'funcionario') para o futuro.
-- - Comunicado: alvo = conta, lojas ou pessoas; destinatarios fixados na
--   publicacao (so ativos); acrescimo manual depois. Titulo, texto e pontos
--   travam na primeira ciencia. Nunca se apaga; arquivado nao aceita
--   ciencia nova nem destinatario novo.
-- - Ciencia gera pontos pelo livro, uma vez; desfazer (so o master) estorna
--   pelo livro. Conta na conquista "comunicados lidos". Fora do ranking.
-- - Documentos pessoais: bucket privado documentos-rh, so o master, com
--   registro de cada acesso. Excluir "por engano" so sem ciencia e ate 7
--   dias; fora disso, substituir por nova versao ou arquivar.
-- - Onboarding: checklist por pessoa com etapas por conta.

-- ===========================================================================
-- 1. Comunicados (tabela documentos)
-- ===========================================================================

ALTER TABLE public.documentos
  ADD COLUMN status            varchar(10) NOT NULL DEFAULT 'Publicado',
  ADD COLUMN alvo              varchar(12) NOT NULL DEFAULT 'funcionarios',
  ADD COLUMN criadopor         uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN atualizadoem      timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN primeiracienciaem timestamptz,
  ADD COLUMN arquivadoem       timestamptz,
  ADD COLUMN arquivadopor      uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.documentos ADD CONSTRAINT documentos_status_valido CHECK (status IN ('Publicado', 'Arquivado'));
ALTER TABLE public.documentos ADD CONSTRAINT documentos_alvo_valido CHECK (alvo IN ('conta', 'lojas', 'funcionarios'));
ALTER TABLE public.documentos ADD CONSTRAINT documentos_pontos_validos CHECK (pontosporciencia BETWEEN 0 AND 10000);
ALTER TABLE public.documentos ADD CONSTRAINT documentos_texto_preenchido
  CHECK (length(btrim(titulo)) > 0 AND length(btrim(conteudo)) > 0);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.documentos FROM anon, authenticated;

-- Lojas escolhidas como alvo.
CREATE TABLE public.documentoslojas (
  contaid     integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  documentoid integer NOT NULL,
  lojaid      integer NOT NULL,
  PRIMARY KEY (documentoid, lojaid),
  CONSTRAINT documentoslojas_documento_fk FOREIGN KEY (contaid, documentoid)
    REFERENCES public.documentos (contaid, documentoid) ON DELETE RESTRICT,
  CONSTRAINT documentoslojas_loja_fk FOREIGN KEY (contaid, lojaid)
    REFERENCES public.lojas (contaid, lojaid) ON DELETE RESTRICT
);
ALTER TABLE public.documentoslojas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.documentoslojas FROM anon, authenticated;
GRANT SELECT ON public.documentoslojas TO authenticated;
GRANT ALL ON public.documentoslojas TO service_role;
CREATE POLICY documentoslojas_sel ON public.documentoslojas FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- Titulo, texto e pontos travam na primeira ciencia; nada se apaga;
-- arquivado e final.
CREATE OR REPLACE FUNCTION public.protege_comunicado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Comunicado não se apaga; arquive.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF OLD.primeiracienciaem IS NOT NULL AND (NEW.titulo IS DISTINCT FROM OLD.titulo
       OR NEW.conteudo IS DISTINCT FROM OLD.conteudo OR NEW.pontosporciencia IS DISTINCT FROM OLD.pontosporciencia) THEN
    RAISE EXCEPTION 'Este comunicado já tem ciência: o texto e os pontos não mudam. Crie um novo.'
      USING ERRCODE = 'restrict_violation';
  END IF;
  IF OLD.status = 'Arquivado' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Comunicado arquivado não volta.' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.contaid IS DISTINCT FROM OLD.contaid OR NEW.alvo IS DISTINCT FROM OLD.alvo
     OR (OLD.primeiracienciaem IS NOT NULL AND NEW.primeiracienciaem IS DISTINCT FROM OLD.primeiracienciaem) THEN
    RAISE EXCEPTION 'Isso não muda num comunicado publicado.' USING ERRCODE = 'restrict_violation';
  END IF;
  NEW.atualizadoem := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER documentos_protege
  BEFORE UPDATE OR DELETE ON public.documentos
  FOR EACH ROW EXECUTE FUNCTION public.protege_comunicado();

-- ===========================================================================
-- 2. Ciencias (tabela documentosassinaturas)
-- ===========================================================================

UPDATE public.documentosassinaturas SET statusassinatura = 'Pendente' WHERE statusassinatura NOT IN ('Pendente', 'Ciente');
ALTER TABLE public.documentosassinaturas
  ADD COLUMN origem         varchar(12),
  ADD COLUMN registradopor  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN pontospagos    integer NOT NULL DEFAULT 0,
  ADD COLUMN desfeitaem     timestamptz,
  ADD COLUMN desfeitapor    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN motivodesfazer text;
ALTER TABLE public.documentosassinaturas ADD CONSTRAINT documentosassinaturas_status_valido
  CHECK (statusassinatura IN ('Pendente', 'Ciente'));
ALTER TABLE public.documentosassinaturas ADD CONSTRAINT documentosassinaturas_origem_valida
  CHECK (origem IS NULL OR origem IN ('gestor', 'funcionario'));
ALTER TABLE public.documentosassinaturas ADD CONSTRAINT documentosassinaturas_um_por_pessoa
  UNIQUE (documentoid, funcionarioid);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.documentosassinaturas FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.protege_ciencia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Ciência não se apaga; se foi engano, desfaça.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.documentoid IS DISTINCT FROM OLD.documentoid OR NEW.funcionarioid IS DISTINCT FROM OLD.funcionarioid
     OR NEW.contaid IS DISTINCT FROM OLD.contaid THEN
    RAISE EXCEPTION 'A ciência não muda de comunicado nem de pessoa.' USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER documentosassinaturas_protege
  BEFORE UPDATE OR DELETE ON public.documentosassinaturas
  FOR EACH ROW EXECUTE FUNCTION public.protege_ciencia();

-- O bonus da ciencia aponta para ela no livro.
ALTER TABLE public.movimentospontos ADD COLUMN assinaturaid integer;
ALTER TABLE public.movimentospontos ADD CONSTRAINT movimentospontos_ciencia_fk
  FOREIGN KEY (contaid, assinaturaid) REFERENCES public.documentosassinaturas (contaid, assinaturaid) ON DELETE RESTRICT;

-- Quem o alvo alcanca hoje: ativos da conta, ou ativos com vinculo ativo
-- numa das lojas escolhidas. Interna.
CREATE OR REPLACE FUNCTION public.alcance_do_comunicado(p_documentoid integer)
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT f.funcionarioid
    FROM public.documentos d
    JOIN public.funcionarios f ON f.contaid = d.contaid AND f.ativo
   WHERE d.documentoid = p_documentoid
     AND (d.alvo = 'conta'
          OR (d.alvo = 'lojas' AND EXISTS (
                SELECT 1 FROM public.funcionarioslojas fl
                  JOIN public.documentoslojas dl ON dl.lojaid = fl.lojaid AND dl.documentoid = d.documentoid
                 WHERE fl.funcionarioid = f.funcionarioid AND fl.contaid = d.contaid AND fl.ativo)))
   ORDER BY f.funcionarioid
$$;

-- Acrescenta destinatarios (so ativos e da conta; ignora quem ja esta).
CREATE OR REPLACE FUNCTION public.incluir_destinatarios(p_documentoid integer, p_funcionarios integer[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  d public.documentos%ROWTYPE;
  v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não aceita novos destinatários.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(fid)
              WHERE NOT EXISTS (SELECT 1 FROM public.funcionarios f
                                 WHERE f.funcionarioid = x.fid AND f.contaid = v_conta AND f.ativo)) THEN
    RAISE EXCEPTION 'Só funcionários ativos da sua conta podem receber o comunicado.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
  SELECT v_conta, p_documentoid, x.fid, now()
    FROM (SELECT DISTINCT unnest(coalesce(p_funcionarios, '{}'::integer[])) AS fid) x
  ON CONFLICT (documentoid, funcionarioid) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.publicar_comunicado(
  p_titulo       text,
  p_conteudo     text,
  p_pontos       integer,
  p_alvo         text,
  p_lojas        integer[] DEFAULT NULL,
  p_funcionarios integer[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_id    integer;
  v_pontos integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_titulo, ''))) = 0 OR length(btrim(coalesce(p_conteudo, ''))) = 0 THEN
    RAISE EXCEPTION 'Preencha o título e o texto.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo NOT IN ('conta', 'lojas', 'funcionarios') THEN
    RAISE EXCEPTION 'Escolha para quem é o comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  -- Pontos: os do comunicado, ou o padrao da tarefa do sistema "Leitura de comunicado".
  v_pontos := coalesce(p_pontos, (SELECT t.pontos FROM public.configuracoes c
                                    JOIN public.tarefas t ON t.tarefaid = nullif(c.valor, '')::integer AND t.contaid = c.contaid
                                   WHERE c.contaid = v_conta AND c.chave = 'TAREFA_ID_LEITURA'), 0);
  IF v_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'lojas' AND (coalesce(array_length(p_lojas, 1), 0) = 0
       OR EXISTS (SELECT 1 FROM unnest(p_lojas) x(l)
                   WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = x.l AND contaid = v_conta AND ativa))) THEN
    RAISE EXCEPTION 'Escolha lojas ativas da sua conta.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'funcionarios' AND coalesce(array_length(p_funcionarios, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Escolha pelo menos uma pessoa.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.documentos (contaid, titulo, conteudo, pontosporciencia, alvo, criadopor)
  VALUES (v_conta, btrim(p_titulo), btrim(p_conteudo), v_pontos, p_alvo, auth.uid())
  RETURNING documentoid INTO v_id;

  IF p_alvo = 'lojas' THEN
    INSERT INTO public.documentoslojas (contaid, documentoid, lojaid)
    SELECT DISTINCT v_conta, v_id, x FROM unnest(p_lojas) x;
  END IF;

  -- Destinatarios fixados agora (so ativos).
  IF p_alvo = 'funcionarios' THEN
    PERFORM public.incluir_destinatarios(v_id, p_funcionarios);
  ELSE
    INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
    SELECT v_conta, v_id, fid, now() FROM public.alcance_do_comunicado(v_id) fid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas WHERE documentoid = v_id) THEN
    RAISE EXCEPTION 'Nenhum funcionário ativo recebe este comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END;
$$;

-- Editar: so antes da primeira ciencia.
CREATE OR REPLACE FUNCTION public.editar_comunicado(p_documentoid integer, p_titulo text, p_conteudo text, p_pontos integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel(); d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não muda.' USING ERRCODE = 'check_violation';
  END IF;
  IF d.primeiracienciaem IS NOT NULL THEN
    RAISE EXCEPTION 'Este comunicado já tem ciência: o texto e os pontos não mudam. Crie um novo.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF length(btrim(coalesce(p_titulo, ''))) = 0 OR length(btrim(coalesce(p_conteudo, ''))) = 0 THEN
    RAISE EXCEPTION 'Preencha o título e o texto.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_pontos IS NULL OR p_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.documentos SET titulo = btrim(p_titulo), conteudo = btrim(p_conteudo), pontosporciencia = p_pontos
   WHERE documentoid = p_documentoid;
END;
$$;

CREATE OR REPLACE FUNCTION public.arquivar_comunicado(p_documentoid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.documentos SET status = 'Arquivado', arquivadoem = now(), arquivadopor = auth.uid()
   WHERE documentoid = p_documentoid AND contaid = v_conta AND status = 'Publicado';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado ou já arquivado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- Quem o alvo alcanca hoje e ainda nao esta no comunicado ("entraram depois").
CREATE OR REPLACE FUNCTION public.fora_do_comunicado(p_documentoid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                                    ORDER BY f.nomecompleto), '[]'::jsonb)
            FROM public.alcance_do_comunicado(p_documentoid) a(fid)
            JOIN public.funcionarios f ON f.funcionarioid = a.fid
           WHERE NOT EXISTS (SELECT 1 FROM public.documentosassinaturas s
                              WHERE s.documentoid = p_documentoid AND s.funcionarioid = a.fid));
END;
$$;

-- Registra a ciencia (hoje pelo gestor). Atomica: trava a ciencia; paga os
-- pontos pelo livro uma vez so; um segundo clique nao faz nada.
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
     SET statusassinatura = 'Ciente', dataciencia = now(), origem = 'gestor', registradopor = auth.uid(),
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

-- Desfaz uma ciencia registrada por engano. So o master; estorno pelo livro.
CREATE OR REPLACE FUNCTION public.desfazer_ciencia(p_assinaturaid integer, p_motivo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  s public.documentosassinaturas%ROWTYPE;
  v_titulo text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta desfaz uma ciência.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO s FROM public.documentosassinaturas WHERE assinaturaid = p_assinaturaid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Destinatário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF s.statusassinatura <> 'Ciente' THEN
    RAISE EXCEPTION 'Esta ciência não está registrada.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT titulo INTO v_titulo FROM public.documentos WHERE documentoid = s.documentoid;

  UPDATE public.documentosassinaturas
     SET statusassinatura = 'Pendente', dataciencia = NULL, pontospagos = 0,
         desfeitaem = now(), desfeitapor = auth.uid(), motivodesfazer = btrim(p_motivo)
   WHERE assinaturaid = p_assinaturaid;
  IF s.pontospagos > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, assinaturaid, criadopor)
    VALUES (v_conta, s.funcionarioid, 'estorno_bonus', -s.pontospagos,
            'Ciência desfeita: ' || v_titulo || ' — ' || btrim(p_motivo), p_assinaturaid, auth.uid());
  END IF;
END;
$$;

-- Dados do recibo de ciencia (PDF). RLS de quem chama.
CREATE OR REPLACE FUNCTION public.recibo_ciencia(p_assinaturaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
           'conta', c.nome, 'pessoa', f.nomecompleto, 'titulo', d.titulo, 'conteudo', d.conteudo,
           'publicadoem', d.datacriacao, 'ciencia', s.dataciencia, 'origem', s.origem,
           'protocolo', 'C-' || s.assinaturaid, 'pontos', s.pontospagos)
    FROM public.documentosassinaturas s
    JOIN public.documentos d    ON d.documentoid = s.documentoid
    JOIN public.funcionarios f  ON f.funcionarioid = s.funcionarioid
    JOIN public.contas c        ON c.contaid = s.contaid
   WHERE s.assinaturaid = p_assinaturaid AND s.statusassinatura = 'Ciente'
$$;

-- Dados do recibo de resgate (PDF), direto do livro de pontos.
CREATE OR REPLACE FUNCTION public.recibo_resgate(p_resgateid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nome AS conta
      FROM public.resgates r
      JOIN public.funcionarios f ON f.funcionarioid = r.funcionarioid
      JOIN public.produtosloja p ON p.produtoid = r.produtoid
      JOIN public.contas c       ON c.contaid = r.contaid
      LEFT JOIN public.lojas l   ON l.lojaid = r.lojaid
     WHERE r.resgateid = p_resgateid
  ),
  mov AS (
    SELECT m.movimentoid, m.datamovimento, m.tipo, m.pontos, m.descricao,
           (SELECT coalesce(sum(x.pontos), 0) FROM public.movimentospontos x
             WHERE x.funcionarioid = m.funcionarioid AND x.movimentoid < m.movimentoid) AS saldoantes
      FROM public.movimentospontos m
     WHERE m.resgateid = p_resgateid
  )
  SELECT jsonb_build_object(
           'conta', r.conta, 'loja', r.loja, 'pessoa', r.nomecompleto,
           'premio', CASE WHEN r.valorreais IS NOT NULL THEN 'Abate na comanda de ' || public.reais(r.valorreais) ELSE r.premio END,
           'pontos', r.pontosgastos, 'situacao', r.status, 'solicitadoem', r.datasolicitacao,
           'entregueem', r.dataentrega, 'protocolo', 'R-' || r.resgateid,
           'movimentos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                             'data', datamovimento, 'tipo', tipo, 'pontos', pontos, 'descricao', descricao,
                             'saldoantes', saldoantes, 'saldodepois', saldoantes + pontos) ORDER BY movimentoid), '[]'::jsonb)
                            FROM mov))
    FROM r
$$;

-- ===========================================================================
-- 3. Documentos pessoais (holerite, recibo, contrato...). So o master.
--    Arquivo em documentos-rh: <conta>/funcionarios/<funcionario>/<arquivo>.
-- ===========================================================================

ALTER TABLE public.documentospessoais ALTER COLUMN mesano DROP NOT NULL;
ALTER TABLE public.documentospessoais
  ADD COLUMN descricao        varchar(200),
  ADD COLUMN nomearquivo      varchar(200),
  ADD COLUMN tipoarquivo      varchar(50),
  ADD COLUMN tamanho          integer,
  ADD COLUMN enviadopor       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN situacao         varchar(12) NOT NULL DEFAULT 'Ativo',
  ADD COLUMN substituidopor   integer,
  ADD COLUMN substituidoem    timestamptz,
  ADD COLUMN arquivadoem      timestamptz,
  ADD COLUMN arquivadopor     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN excluidoem       timestamptz,
  ADD COLUMN excluidopor      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN motivoexclusao   text;
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_tipo_valido CHECK (tipodocumento IN (
  'Holerite', 'Recibo', 'Contrato', 'Atestado', 'Advertência', 'Cartão de ponto', 'Documento de admissão', 'Outro'));
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_situacao_valida
  CHECK (situacao IN ('Ativo', 'Substituido', 'Arquivado', 'Excluido'));
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_arquivo_valido
  CHECK (tipoarquivo IS NULL OR (tipoarquivo IN ('application/pdf', 'image/jpeg', 'image/png')
                                 AND tamanho > 0 AND tamanho <= 10485760));
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_exclusao_com_motivo
  CHECK (situacao <> 'Excluido' OR length(btrim(coalesce(motivoexclusao, ''))) > 0);
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_caminho_unico UNIQUE (caminhoarquivo);
ALTER TABLE public.documentospessoais ADD CONSTRAINT documentospessoais_substituto_fk
  FOREIGN KEY (contaid, substituidopor) REFERENCES public.documentospessoais (contaid, documentoid) ON DELETE RESTRICT;
CREATE INDEX documentospessoais_funcionario_idx ON public.documentospessoais (funcionarioid, dataupload DESC);

-- So o master le; ninguem grava pelo navegador (so pelas funcoes).
DROP POLICY IF EXISTS documentospessoais_sel ON public.documentospessoais;
DROP POLICY IF EXISTS documentospessoais_ins ON public.documentospessoais;
DROP POLICY IF EXISTS documentospessoais_upd ON public.documentospessoais;
DROP POLICY IF EXISTS documentospessoais_del ON public.documentospessoais;
REVOKE ALL ON public.documentospessoais FROM anon, authenticated;
GRANT SELECT ON public.documentospessoais TO authenticated;
GRANT ALL ON public.documentospessoais TO service_role;
CREATE POLICY documentospessoais_master_le ON public.documentospessoais FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()) AND (select public.sou_master()));

CREATE OR REPLACE FUNCTION public.protege_documento_pessoal()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Documento pessoal não se apaga; arquive, substitua ou (se foi engano) exclua com motivo.'
      USING ERRCODE = 'restrict_violation';
  END IF;
  IF NEW.funcionarioid IS DISTINCT FROM OLD.funcionarioid OR NEW.caminhoarquivo IS DISTINCT FROM OLD.caminhoarquivo
     OR NEW.contaid IS DISTINCT FROM OLD.contaid OR NEW.tipodocumento IS DISTINCT FROM OLD.tipodocumento
     OR NEW.dataupload IS DISTINCT FROM OLD.dataupload THEN
    RAISE EXCEPTION 'O documento não muda; envie uma nova versão.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF OLD.situacao = 'Excluido' OR (OLD.situacao = 'Substituido' AND NEW.situacao <> 'Substituido') THEN
    RAISE EXCEPTION 'Esta versão não muda mais.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER documentospessoais_protege
  BEFORE UPDATE OR DELETE ON public.documentospessoais
  FOR EACH ROW EXECUTE FUNCTION public.protege_documento_pessoal();

-- Ciencia de recebimento do documento (uma por documento).
UPDATE public.documentospessoaisciencia SET status = 'Pendente' WHERE status NOT IN ('Pendente', 'Ciente');
ALTER TABLE public.documentospessoaisciencia
  ADD COLUMN origem        varchar(12),
  ADD COLUMN registradopor uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.documentospessoaisciencia ADD CONSTRAINT documentospessoaisciencia_status_valido
  CHECK (status IN ('Pendente', 'Ciente'));
ALTER TABLE public.documentospessoaisciencia ADD CONSTRAINT documentospessoaisciencia_origem_valida
  CHECK (origem IS NULL OR origem IN ('gestor', 'funcionario'));
ALTER TABLE public.documentospessoaisciencia ADD CONSTRAINT documentospessoaisciencia_uma_por_documento UNIQUE (documentoid);
DROP POLICY IF EXISTS documentospessoaisciencia_sel ON public.documentospessoaisciencia;
DROP POLICY IF EXISTS documentospessoaisciencia_ins ON public.documentospessoaisciencia;
DROP POLICY IF EXISTS documentospessoaisciencia_upd ON public.documentospessoaisciencia;
DROP POLICY IF EXISTS documentospessoaisciencia_del ON public.documentospessoaisciencia;
REVOKE ALL ON public.documentospessoaisciencia FROM anon, authenticated;
GRANT SELECT ON public.documentospessoaisciencia TO authenticated;
GRANT ALL ON public.documentospessoaisciencia TO service_role;
CREATE POLICY documentospessoaisciencia_master_le ON public.documentospessoaisciencia FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()) AND (select public.sou_master()));

-- Registro de acesso (LGPD): cada envio e cada link gerado. So o master le;
-- nunca muda nem se apaga.
CREATE TABLE public.documentosacessos (
  acessoid     integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid      integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  documentoid  integer,
  caminho      text NOT NULL,
  acao         varchar(12) NOT NULL CHECK (acao IN ('envio', 'visualizacao')),
  usuario      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  acessadoem   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT documentosacessos_documento_fk FOREIGN KEY (contaid, documentoid)
    REFERENCES public.documentospessoais (contaid, documentoid) ON DELETE RESTRICT
);
CREATE INDEX documentosacessos_caminho_idx ON public.documentosacessos (caminho, usuario, acessadoem DESC);
CREATE INDEX documentosacessos_documento_idx ON public.documentosacessos (documentoid, acessadoem DESC);
ALTER TABLE public.documentosacessos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.documentosacessos FROM anon, authenticated;
GRANT SELECT ON public.documentosacessos TO authenticated;
GRANT ALL ON public.documentosacessos TO service_role;
CREATE POLICY documentosacessos_master_le ON public.documentosacessos FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()) AND (select public.sou_master()));
CREATE TRIGGER documentosacessos_imutavel
  BEFORE UPDATE OR DELETE ON public.documentosacessos
  FOR EACH ROW EXECUTE FUNCTION public.historico_imutavel();

-- Master da conta, com a conta editavel? Interna.
CREATE OR REPLACE FUNCTION public.exige_master_editavel()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta mexe nos documentos pessoais.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_conta;
END;
$$;

-- Prepara o envio: devolve o caminho e libera, por 2 minutos, o envio
-- daquele arquivo ao Storage (e registra o envio).
CREATE OR REPLACE FUNCTION public.preparar_envio_documento(p_funcionarioid integer, p_nomearquivo text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.exige_master_editavel();
  v_nome text := left(regexp_replace(coalesce(p_nomearquivo, 'arquivo'), '[^A-Za-z0-9._-]+', '_', 'g'), 80);
  v_caminho text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  v_caminho := v_conta || '/funcionarios/' || p_funcionarioid || '/' || replace(gen_random_uuid()::text, '-', '') || '-' || v_nome;
  INSERT INTO public.documentosacessos (contaid, caminho, acao, usuario) VALUES (v_conta, v_caminho, 'envio', auth.uid());
  RETURN v_caminho;
END;
$$;

-- Usada nas regras do Storage: o master tem acesso liberado a este caminho
-- ha menos de 2 minutos? (liberado por preparar_envio_documento ou por
-- liberar_documento_pessoal, que registram o acesso).
CREATE OR REPLACE FUNCTION public.documento_rh_liberado(p_nome text, p_acao text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.sou_master() AND EXISTS (
    SELECT 1 FROM public.documentosacessos a
     WHERE a.contaid = public.minha_conta() AND a.caminho = p_nome AND a.acao = p_acao
       AND a.usuario = auth.uid() AND a.acessadoem > now() - interval '2 minutes')
$$;

-- Registra o documento depois do envio ao Storage. Com p_substitui, a
-- versao anterior fica guardada e marcada como substituida.
CREATE OR REPLACE FUNCTION public.registrar_documento_pessoal(
  p_funcionarioid integer, p_tipo text, p_referencia date, p_descricao text,
  p_caminho text, p_nomearquivo text, p_tipoarquivo text, p_tamanho integer, p_substitui integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.exige_master_editavel();
  v_antigo public.documentospessoais%ROWTYPE;
  v_id integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Funcionário não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF p_caminho NOT LIKE v_conta || '/funcionarios/' || p_funcionarioid || '/%' THEN
    RAISE EXCEPTION 'Arquivo fora da pasta do funcionário.' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'documentos-rh' AND name = p_caminho) THEN
    RAISE EXCEPTION 'Arquivo não encontrado. Envie de novo.' USING ERRCODE = 'no_data_found';
  END IF;
  IF p_tipoarquivo NOT IN ('application/pdf', 'image/jpeg', 'image/png') OR p_tamanho IS NULL
     OR p_tamanho <= 0 OR p_tamanho > 10485760 THEN
    RAISE EXCEPTION 'Só PDF, JPG ou PNG de até 10 MB.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_substitui IS NOT NULL THEN
    SELECT * INTO v_antigo FROM public.documentospessoais
     WHERE documentoid = p_substitui AND contaid = v_conta FOR UPDATE;
    IF NOT FOUND OR v_antigo.funcionarioid <> p_funcionarioid OR v_antigo.situacao NOT IN ('Ativo', 'Arquivado') THEN
      RAISE EXCEPTION 'Só dá para substituir um documento ativo ou arquivado da mesma pessoa.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  INSERT INTO public.documentospessoais (contaid, funcionarioid, tipodocumento, mesano, descricao, caminhoarquivo,
                                         nomearquivo, tipoarquivo, tamanho, enviadopor)
  VALUES (v_conta, p_funcionarioid, coalesce(v_antigo.tipodocumento, p_tipo), p_referencia,
          nullif(btrim(coalesce(p_descricao, '')), ''), p_caminho, left(btrim(p_nomearquivo), 200), p_tipoarquivo,
          p_tamanho, auth.uid())
  RETURNING documentoid INTO v_id;
  INSERT INTO public.documentospessoaisciencia (contaid, documentoid, funcionarioid, dataenvio)
  VALUES (v_conta, v_id, p_funcionarioid, now());

  IF p_substitui IS NOT NULL THEN
    UPDATE public.documentospessoais SET situacao = 'Substituido', substituidopor = v_id, substituidoem = now()
     WHERE documentoid = p_substitui;
  END IF;
  RETURN v_id;
END;
$$;

-- Registra que a pessoa recebeu o documento (hoje, pelo gestor).
CREATE OR REPLACE FUNCTION public.registrar_ciencia_documento(p_documentoid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel(); v_n integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.documentospessoais
                  WHERE documentoid = p_documentoid AND contaid = v_conta AND situacao IN ('Ativo', 'Arquivado')) THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  UPDATE public.documentospessoaisciencia
     SET status = 'Ciente', dataciencia = now(), origem = 'gestor', registradopor = auth.uid()
   WHERE documentoid = p_documentoid AND contaid = v_conta AND status = 'Pendente';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;

-- Excluir "enviado por engano": so sem ciencia e ate 7 dias. O registro
-- fica (quem, quando, motivo, nome e tipo); a tela apaga o arquivo do
-- Storage com o caminho devolvido.
CREATE OR REPLACE FUNCTION public.excluir_documento_por_engano(p_documentoid integer, p_motivo text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel(); d public.documentospessoais%ROWTYPE;
BEGIN
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO d FROM public.documentospessoais WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  IF d.situacao <> 'Ativo' THEN
    RAISE EXCEPTION 'Só um documento ativo pode ser excluído por engano.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.documentospessoaisciencia WHERE documentoid = p_documentoid AND status = 'Ciente') THEN
    RAISE EXCEPTION 'O documento já tem ciência: não se apaga. Substitua por nova versão ou arquive.' USING ERRCODE = 'restrict_violation';
  END IF;
  IF d.dataupload < now() - interval '7 days' THEN
    RAISE EXCEPTION 'Passaram mais de 7 dias do envio: não se apaga. Substitua por nova versão ou arquive.' USING ERRCODE = 'restrict_violation';
  END IF;
  UPDATE public.documentospessoais
     SET situacao = 'Excluido', excluidoem = now(), excluidopor = auth.uid(), motivoexclusao = btrim(p_motivo)
   WHERE documentoid = p_documentoid;
  RETURN d.caminhoarquivo;
END;
$$;

CREATE OR REPLACE FUNCTION public.arquivar_documento_pessoal(p_documentoid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.exige_master_editavel();
BEGIN
  UPDATE public.documentospessoais SET situacao = 'Arquivado', arquivadoem = now(), arquivadopor = auth.uid()
   WHERE documentoid = p_documentoid AND contaid = v_conta AND situacao = 'Ativo';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Documento não encontrado ou não está ativo.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

-- Libera o arquivo para gerar o link (5 minutos) e registra o acesso.
-- Versoes substituidas e arquivadas continuam acessiveis ao master.
CREATE OR REPLACE FUNCTION public.liberar_documento_pessoal(p_documentoid integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta(); d public.documentospessoais%ROWTYPE;
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o responsável pela conta abre documentos pessoais.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentospessoais WHERE documentoid = p_documentoid AND contaid = v_conta;
  IF NOT FOUND OR d.situacao = 'Excluido' THEN
    RAISE EXCEPTION 'Documento não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.documentosacessos (contaid, documentoid, caminho, acao, usuario)
  VALUES (v_conta, d.documentoid, d.caminhoarquivo, 'visualizacao', auth.uid());
  RETURN d.caminhoarquivo;
END;
$$;

-- Storage documentos-rh: so o master, so na pasta de um funcionario da
-- conta, e so com o acesso liberado (e registrado) ha menos de 2 minutos.
DROP POLICY IF EXISTS documentos_rh_sel ON storage.objects;
DROP POLICY IF EXISTS documentos_rh_ins ON storage.objects;
DROP POLICY IF EXISTS documentos_rh_upd ON storage.objects;
DROP POLICY IF EXISTS documentos_rh_del ON storage.objects;
CREATE POLICY documentos_rh_sel ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta())::text
         AND (public.documento_rh_liberado(name, 'visualizacao') OR public.documento_rh_liberado(name, 'envio')));
CREATE POLICY documentos_rh_ins ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text
              AND public.documento_rh_liberado(name, 'envio'));
-- Apagar: so o arquivo de um documento excluido por engano, ou um envio
-- que nao chegou a ser registrado.
CREATE POLICY documentos_rh_del ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'documentos-rh' AND split_part(name, '/', 1) = (select public.minha_conta_editavel())::text
         AND (select public.sou_master())
         AND NOT EXISTS (SELECT 1 FROM public.documentospessoais dp
                          WHERE dp.caminhoarquivo = storage.objects.name AND dp.situacao <> 'Excluido'));

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets
                  SET file_size_limit = 10485760,
                      allowed_mime_types = ARRAY['application/pdf', 'image/jpeg', 'image/png']
                WHERE id = 'documentos-rh'$q$;
  END IF;
END $$;

-- ===========================================================================
-- 4. Onboarding: checklist por pessoa, etapas por conta
-- ===========================================================================

-- Dados pessoais do questionario antigo saem (LGPD: guardar so o necessario).
ALTER TABLE public.onboardingstatus
  DROP COLUMN escolaridade, DROP COLUMN estadocivil, DROP COLUMN qtdfilhos, DROP COLUMN dadosfilhos,
  DROP COLUMN rg_fileid, DROP COLUMN cpf_fileid, DROP COLUMN ctps_fileid, DROP COLUMN tituloeleitor_fileid,
  DROP COLUMN datacasamento, DROP COLUMN nomeconjugue, DROP COLUMN cpfconjugue,
  DROP COLUMN dataadmissional, DROP COLUMN statusadmissional, DROP COLUMN ultimaetapa;
UPDATE public.onboardingstatus SET statusworkflow = 'Em andamento' WHERE statusworkflow NOT IN ('Em andamento', 'Concluído');
ALTER TABLE public.onboardingstatus ALTER COLUMN statusworkflow SET DEFAULT 'Em andamento';
ALTER TABLE public.onboardingstatus
  ADD COLUMN iniciadoem  timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN iniciadopor uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN concluidoem timestamptz;
ALTER TABLE public.onboardingstatus ADD CONSTRAINT onboardingstatus_status_valido
  CHECK (statusworkflow IN ('Em andamento', 'Concluído'));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.onboardingstatus FROM anon, authenticated;

CREATE TABLE public.onboardingetapas (
  etapaid   integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid   integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  nome      varchar(120) NOT NULL CHECK (length(btrim(nome)) > 0),
  ordem     integer NOT NULL DEFAULT 0,
  ativo     boolean NOT NULL DEFAULT true,
  criadoem  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT onboardingetapas_conta_unico UNIQUE (contaid, etapaid)
);
CREATE UNIQUE INDEX onboardingetapas_nome_por_conta ON public.onboardingetapas (contaid, lower(btrim(nome)));
ALTER TABLE public.onboardingetapas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.onboardingetapas FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.onboardingetapas TO authenticated;
GRANT ALL ON public.onboardingetapas TO service_role;
CREATE POLICY onboardingetapas_sel ON public.onboardingetapas FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));
CREATE POLICY onboardingetapas_ins ON public.onboardingetapas FOR INSERT TO authenticated
  WITH CHECK (contaid = (select public.minha_conta_editavel()));
CREATE POLICY onboardingetapas_upd ON public.onboardingetapas FOR UPDATE TO authenticated
  USING (contaid = (select public.minha_conta_editavel())) WITH CHECK (contaid = (select public.minha_conta_editavel()));

CREATE TABLE public.onboardingitens (
  itemid        integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas(contaid) ON DELETE RESTRICT,
  funcionarioid integer NOT NULL,
  etapaid       integer NOT NULL,
  concluidoem   timestamptz,
  concluidopor  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  observacao    text,
  documentoid   integer,
  criadoem      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT onboardingitens_um_por_etapa UNIQUE (funcionarioid, etapaid),
  CONSTRAINT onboardingitens_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.onboardingstatus (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT onboardingitens_etapa_fk FOREIGN KEY (contaid, etapaid)
    REFERENCES public.onboardingetapas (contaid, etapaid) ON DELETE RESTRICT,
  CONSTRAINT onboardingitens_documento_fk FOREIGN KEY (contaid, documentoid)
    REFERENCES public.documentospessoais (contaid, documentoid) ON DELETE RESTRICT
);
ALTER TABLE public.onboardingitens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.onboardingitens FROM anon, authenticated;
GRANT SELECT ON public.onboardingitens TO authenticated;
GRANT ALL ON public.onboardingitens TO service_role;
CREATE POLICY onboardingitens_sel ON public.onboardingitens FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));

-- Etapas genericas de uma conta nova. So o servidor chama.
CREATE OR REPLACE FUNCTION public.cria_etapas_onboarding_padrao(p_contaid integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.onboardingetapas (contaid, nome, ordem)
  SELECT p_contaid, e.nome, e.ordem
    FROM (VALUES ('Documentos pessoais recebidos', 1), ('Exame admissional', 2), ('Contrato assinado', 3),
                 ('Cadastro no sistema', 4), ('Treinamento inicial', 5), ('Apresentação à equipe', 6)) e(nome, ordem)
   WHERE NOT EXISTS (SELECT 1 FROM public.onboardingetapas WHERE contaid = p_contaid);
$$;

-- Inicia o onboarding de uma pessoa (ou acrescenta as etapas ativas que
-- ainda nao estao no checklist dela).
CREATE OR REPLACE FUNCTION public.iniciar_onboarding(p_funcionarioid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel(); v_n integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = v_conta AND ativo) THEN
    RAISE EXCEPTION 'Funcionário ativo não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  INSERT INTO public.onboardingstatus (contaid, funcionarioid, iniciadopor)
  VALUES (v_conta, p_funcionarioid, auth.uid())
  ON CONFLICT (funcionarioid) DO NOTHING;
  INSERT INTO public.onboardingitens (contaid, funcionarioid, etapaid)
  SELECT v_conta, p_funcionarioid, e.etapaid FROM public.onboardingetapas e
   WHERE e.contaid = v_conta AND e.ativo
  ON CONFLICT (funcionarioid, etapaid) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE public.onboardingstatus SET statusworkflow = 'Em andamento', concluidoem = NULL
   WHERE funcionarioid = p_funcionarioid AND v_n > 0;
  RETURN v_n;
END;
$$;

-- Marca ou desmarca uma etapa. Tudo feito: onboarding concluido.
CREATE OR REPLACE FUNCTION public.marcar_etapa_onboarding(p_itemid integer, p_feito boolean, p_observacao text DEFAULT NULL,
                                                          p_documentoid integer DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta_editavel(); i public.onboardingitens%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO i FROM public.onboardingitens WHERE itemid = p_itemid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Etapa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF p_documentoid IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.documentospessoais
        WHERE documentoid = p_documentoid AND contaid = v_conta AND funcionarioid = i.funcionarioid AND situacao <> 'Excluido') THEN
    RAISE EXCEPTION 'O documento precisa ser desta pessoa.' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.onboardingitens
     SET concluidoem = CASE WHEN p_feito THEN coalesce(concluidoem, now()) END,
         concluidopor = CASE WHEN p_feito THEN coalesce(concluidopor, auth.uid()) END,
         observacao = coalesce(nullif(btrim(coalesce(p_observacao, '')), ''), observacao),
         documentoid = coalesce(p_documentoid, documentoid)
   WHERE itemid = p_itemid;
  UPDATE public.onboardingstatus s
     SET statusworkflow = CASE WHEN x.faltam = 0 THEN 'Concluído' ELSE 'Em andamento' END,
         concluidoem = CASE WHEN x.faltam = 0 THEN coalesce(s.concluidoem, now()) END
    FROM (SELECT count(*) FILTER (WHERE concluidoem IS NULL) AS faltam
            FROM public.onboardingitens WHERE funcionarioid = i.funcionarioid) x
   WHERE s.funcionarioid = i.funcionarioid;
END;
$$;

-- ===========================================================================
-- 5. Conquistas: "comunicados lidos" passa a valer (copias das versoes
--    anteriores com o criterio a mais).
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.criterio_disponivel(p_tipo text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT p_tipo IN ('total_tarefas_aprovadas', 'tarefas_aprovadas_periodo', 'sequencia_dias_tarefas',
                    'sequencia_feedback_diario', 'total_comunicados_cientes')
$$;

CREATE OR REPLACE FUNCTION public.pessoa_cumpre_conquista(p_contaid integer, p_funcionarioid integer, p_conquistaid integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c       public.conquistas%ROWTYPE;
  f       public.funcionarios%ROWTYPE;
  v_desde timestamptz;
  n       integer;
BEGIN
  SELECT * INTO c FROM public.conquistas WHERE conquistaid = p_conquistaid AND contaid = p_contaid;
  IF NOT FOUND OR NOT c.ativa OR NOT public.criterio_disponivel(c.criteriotipo) THEN
    RETURN false;
  END IF;
  SELECT * INTO f FROM public.funcionarios WHERE funcionarioid = p_funcionarioid AND contaid = p_contaid;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  v_desde := coalesce(c.contardesde, '-infinity'::timestamptz);

  IF c.criteriotipo = 'total_tarefas_aprovadas' THEN
    SELECT count(*) INTO n
      FROM public.entregas
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
       AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
       AND dataenvio >= v_desde;
    RETURN n >= c.criteriovalor;

  ELSIF c.criteriotipo = 'tarefas_aprovadas_periodo' THEN
    -- Alguma janela de X dias seguidos com pelo menos N tarefas.
    RETURN EXISTS (
      WITH dias AS (
        SELECT public.dia_em_sao_paulo(dataenvio) AS d
          FROM public.entregas
         WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
           AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
           AND dataenvio >= v_desde
      )
      SELECT 1
        FROM (SELECT DISTINCT d FROM dias) inicio
       WHERE (SELECT count(*) FROM dias x
               WHERE x.d BETWEEN inicio.d AND inicio.d + c.criteriodias - 1) >= c.criteriovalor
    );

  ELSIF c.criteriotipo = 'sequencia_dias_tarefas' THEN
    -- Folga, domingo de folga, afastamento e justificativa aceita sao dias
    -- neutros: nao quebram nem somam.
    n := public.maior_sequencia(
           ARRAY(SELECT DISTINCT public.dia_em_sao_paulo(dataenvio)
                   FROM public.entregas
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                    AND statusvalidacao = 'Aprovada' AND atribuicaoid IS NOT NULL
                    AND dataenvio >= v_desde),
           ARRAY(SELECT DISTINCT dia FROM public.justificativas
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND status = 'Aceita'),
           f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento);
    RETURN n >= c.criteriovalor;

  ELSIF c.criteriotipo = 'sequencia_feedback_diario' THEN
    -- Dias seguidos com feedback (anulado nao conta). Folga, domingo de folga
    -- e afastamento sao neutros.
    n := public.maior_sequencia(
           ARRAY(SELECT DISTINCT datafeedback FROM public.feedbacks
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                    AND anuladoem IS NULL AND criadoem >= v_desde),
           NULL,
           f.diadefolga, f.domingofolgamensal, f.datainicioafastamento, f.datafimafastamento);
    RETURN n >= c.criteriovalor;

  ELSIF c.criteriotipo = 'total_comunicados_cientes' THEN
    -- Comunicados com ciencia valendo (a desfeita nao conta).
    SELECT count(*) INTO n FROM public.documentosassinaturas
     WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
       AND statusassinatura = 'Ciente' AND dataciencia >= v_desde;
    RETURN n >= c.criteriovalor;
  END IF;

  RETURN false;
END;
$$;

-- ===========================================================================
-- 6. Permissoes (negadas por padrao).
-- ===========================================================================

REVOKE EXECUTE ON FUNCTION
  public.alcance_do_comunicado(integer),
  public.exige_master_editavel(),
  public.cria_etapas_onboarding_padrao(integer),
  public.pessoa_cumpre_conquista(integer, integer, integer)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.incluir_destinatarios(integer, integer[]),
  public.publicar_comunicado(text, text, integer, text, integer[], integer[]),
  public.editar_comunicado(integer, text, text, integer),
  public.arquivar_comunicado(integer),
  public.fora_do_comunicado(integer),
  public.registrar_ciencia(integer),
  public.desfazer_ciencia(integer, text),
  public.recibo_ciencia(integer),
  public.recibo_resgate(integer),
  public.preparar_envio_documento(integer, text),
  public.documento_rh_liberado(text, text),
  public.registrar_documento_pessoal(integer, text, date, text, text, text, text, integer, integer),
  public.registrar_ciencia_documento(integer),
  public.excluir_documento_por_engano(integer, text),
  public.arquivar_documento_pessoal(integer),
  public.liberar_documento_pessoal(integer),
  public.iniciar_onboarding(integer),
  public.marcar_etapa_onboarding(integer, boolean, text, integer),
  public.criterio_disponivel(text)
TO authenticated;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;
