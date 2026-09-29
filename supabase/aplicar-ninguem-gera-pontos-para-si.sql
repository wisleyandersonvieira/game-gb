-- =========================================================================
-- STGame — Ninguém gera pontos para si mesmo.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-parte-4-porta-do-gerente.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929271000_ninguem_gera_pontos_para_si.sql
--
-- O QUE MUDA: comunicado com pontos: quem publica fica fora dos destinatários,
-- ninguém se inclui e ninguém dá pontos a um em que é destinatário. Para o
-- master nada muda. Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- NINGUÉM GERA PONTOS PARA SI MESMO (29/09/2026, regra geral do Wisley).
--
-- Quem pode estar ligado a uma pessoa da equipe e ao mesmo tempo dar pontos é
-- só o GERENTE (pelo usuário gerencial). O banco proíbe o master de ser pessoa
-- da equipe (contasusuarios_vinculo_do_papel), e o colaborador não dá pontos.
-- A regra já valia para entrega, feedback e ciência (e_o_proprio). Conquista:
-- só o master cria, e ele nunca é pessoa da equipe — já garantido.
-- Faltava o COMUNICADO: quem publica com pontos fica fora dos destinatários;
-- ninguém se inclui num comunicado com pontos, nem dá pontos a um em que é
-- destinatário. Para o master nada muda. Nenhum dado é alterado.

-- publicar_comunicado: parte da versão viva; quem publica com pontos fica fora.
CREATE OR REPLACE FUNCTION public.publicar_comunicado(p_titulo text, p_conteudo text, p_pontos integer, p_alvo text, p_lojas integer[] DEFAULT NULL::integer[], p_funcionarios integer[] DEFAULT NULL::integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
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
  -- Pontos: os do comunicado, ou o padrao da tarefa "Leitura de comunicado"
  -- (achada pelo CODIGO guardado em configuracoes, nunca pelo nome). Com a
  -- tarefa desativada ou apagada, o padrao e 0 e isso vira aviso (28/09/2026).
  v_pontos := p_pontos;
  IF v_pontos IS NULL THEN
    SELECT t.pontos INTO v_pontos FROM public.configuracoes c
      JOIN public.tarefas t ON t.tarefaid = nullif(c.valor, '')::integer AND t.contaid = c.contaid
     WHERE c.contaid = v_conta AND c.chave = 'TAREFA_ID_LEITURA' AND t.ativa;
    IF NOT FOUND THEN
      v_pontos := 0;
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      VALUES (v_conta, 'rotina_sem_tarefa', left(
        'Comunicados: "' || btrim(coalesce(p_titulo, '')) || '" foi publicado com 0 ponto por ciência, porque a tarefa "Leitura de comunicado" (que dá o padrão) está desativada ou foi apagada.', 300));
    END IF;
  END IF;
  IF v_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;
  -- Teto da conta (29/09/2026): a ciência paga sem ninguém aprovar.
  IF v_pontos > public.teto_pontos_ciencia(v_conta) THEN
    RAISE EXCEPTION '% pontos por ciência passa do máximo permitido nesta conta (% pontos). %',
      v_pontos, public.teto_pontos_ciencia(v_conta),
      CASE WHEN p_pontos IS NULL THEN 'O padrão vem da tarefa "Leitura de comunicado": ajuste os pontos dela, ou escreva os pontos no comunicado.'
           ELSE 'Diminua os pontos, ou mude o máximo em Configurações.' END
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'lojas' AND (coalesce(array_length(p_lojas, 1), 0) = 0
       OR EXISTS (SELECT 1 FROM unnest(p_lojas) x(l)
                   WHERE NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = x.l AND contaid = v_conta AND ativa))) THEN
    RAISE EXCEPTION 'Escolha lojas ativas da sua conta.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_alvo = 'funcionarios' AND coalesce(array_length(p_funcionarios, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Escolha pelo menos uma pessoa.' USING ERRCODE = 'check_violation';
  END IF;
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados).
  IF NOT public.bot_contexto_confiavel() AND (
       (p_alvo = 'conta' AND NOT public.pode('comunicados.publicar', NULL))
    OR (p_alvo = 'lojas' AND EXISTS (SELECT 1 FROM unnest(p_lojas) x(l) WHERE NOT public.pode('comunicados.publicar', x.l)))
    OR (p_alvo = 'funcionarios' AND EXISTS (SELECT 1 FROM unnest(p_funcionarios) x(f)
                                             WHERE NOT public.pode_na_pessoa('comunicados.publicar', v_conta, x.f)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite publicar para esse alcance (a conta inteira é só do dono; lojas e pessoas, só as suas).'
      USING ERRCODE = 'insufficient_privilege';
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
    SELECT v_conta, v_id, fid, now() FROM public.alcance_do_comunicado(v_id) fid
     -- Com pontos, quem publica não recebe o próprio comunicado (ninguém gera pontos para si).
     WHERE v_pontos = 0 OR NOT public.e_o_proprio(v_conta, fid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.documentosassinaturas WHERE documentoid = v_id) THEN
    RAISE EXCEPTION 'Nenhum funcionário ativo recebe este comunicado.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v_id;
END;
$function$;

-- incluir_destinatarios: parte da versão viva; não inclui quem inclui, se tiver pontos.
CREATE OR REPLACE FUNCTION public.incluir_destinatarios(p_documentoid integer, p_funcionarios integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
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
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados):
  -- "conta inteira" é só do master; "lojas", todas dentro das dele; "pessoas",
  -- todas as lojas de cada destinatário dentro das dele.
  IF NOT public.bot_contexto_confiavel() AND NOT (
       public.pode('comunicados.publicar', NULL)
    OR (d.alvo = 'lojas' AND NOT EXISTS (
          SELECT 1 FROM public.documentoslojas dl
           WHERE dl.documentoid = d.documentoid AND NOT public.pode('comunicados.publicar', dl.lojaid)))
    OR (d.alvo = 'funcionarios' AND NOT EXISTS (
          SELECT 1 FROM public.documentosassinaturas a
           WHERE a.documentoid = d.documentoid
             AND NOT public.pode_na_pessoa('comunicados.publicar', v_conta, a.funcionarioid)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer neste comunicado (ele alcança lojas ou pessoas fora das suas).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.bot_contexto_confiavel()
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f)
                  WHERE NOT public.pode_na_pessoa('comunicados.publicar', v_conta, x.f)) THEN
    RAISE EXCEPTION 'Seu cargo não permite incluir pessoas de fora das suas lojas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF d.status <> 'Publicado' THEN
    RAISE EXCEPTION 'Comunicado arquivado não aceita novos destinatários.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(fid)
              WHERE NOT EXISTS (SELECT 1 FROM public.funcionarios f
                                 WHERE f.funcionarioid = x.fid AND f.contaid = v_conta AND f.ativo)) THEN
    RAISE EXCEPTION 'Só funcionários ativos da sua conta podem receber o comunicado.' USING ERRCODE = 'check_violation';
  END IF;

  -- Ninguém gera pontos para si: comunicado com pontos não inclui quem inclui.
  IF d.pontosporciencia > 0
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f) WHERE public.e_o_proprio(v_conta, x.f)) THEN
    RAISE EXCEPTION 'Comunicado com pontos não pode ter você como destinatário: ninguém gera pontos para si mesmo.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.documentosassinaturas (contaid, documentoid, funcionarioid, dataenvio)
  SELECT v_conta, p_documentoid, x.fid, now()
    FROM (SELECT DISTINCT unnest(coalesce(p_funcionarios, '{}'::integer[])) AS fid) x
  ON CONFLICT (documentoid, funcionarioid) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- editar_comunicado: parte da versão viva; não dá pontos a comunicado em que quem edita é destinatário.
CREATE OR REPLACE FUNCTION public.editar_comunicado(p_documentoid integer, p_titulo text, p_conteudo text, p_pontos integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); d public.documentos%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO d FROM public.documentos WHERE documentoid = p_documentoid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comunicado não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e alcance, no banco (usuários gerenciais, parte 2 — Comunicados):
  -- "conta inteira" é só do master; "lojas", todas dentro das dele; "pessoas",
  -- todas as lojas de cada destinatário dentro das dele.
  IF NOT public.bot_contexto_confiavel() AND NOT (
       public.pode('comunicados.publicar', NULL)
    OR (d.alvo = 'lojas' AND NOT EXISTS (
          SELECT 1 FROM public.documentoslojas dl
           WHERE dl.documentoid = d.documentoid AND NOT public.pode('comunicados.publicar', dl.lojaid)))
    OR (d.alvo = 'funcionarios' AND NOT EXISTS (
          SELECT 1 FROM public.documentosassinaturas a
           WHERE a.documentoid = d.documentoid
             AND NOT public.pode_na_pessoa('comunicados.publicar', v_conta, a.funcionarioid)))) THEN
    RAISE EXCEPTION 'Seu cargo não permite mexer neste comunicado (ele alcança lojas ou pessoas fora das suas).'
      USING ERRCODE = 'insufficient_privilege';
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
  -- Teto da conta (29/09/2026). Só vale para o que se grava agora.
  IF p_pontos > public.teto_pontos_ciencia(v_conta) THEN
    RAISE EXCEPTION '% pontos por ciência passa do máximo permitido nesta conta (% pontos). Diminua os pontos, ou mude o máximo em Configurações.',
      p_pontos, public.teto_pontos_ciencia(v_conta) USING ERRCODE = 'check_violation';
  END IF;
  -- Ninguém gera pontos para si: dar pontos a um comunicado em que você é destinatário, não.
  IF p_pontos > 0 AND EXISTS (SELECT 1 FROM public.documentosassinaturas a
                               WHERE a.documentoid = p_documentoid AND public.e_o_proprio(v_conta, a.funcionarioid)) THEN
    RAISE EXCEPTION 'Você é destinatário deste comunicado: ele não pode valer pontos (ninguém gera pontos para si mesmo).'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE public.documentos SET titulo = btrim(p_titulo), conteudo = btrim(p_conteudo), pontosporciencia = p_pontos
   WHERE documentoid = p_documentoid;
END;
$function$;

COMMIT;
