-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 4 (começo) e as cinco decisões de 29/09.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- CLASSIFICAÇÃO: ACRESCENTA (marcada em 30/09/2026, já aplicada: o site
-- anterior continuava funcionando com o banco novo; nenhuma função que ele
-- chamava sumiu nem mudou de formato).
--
-- ATENÇÃO: o banco precisa já ter as partes 2 e 3
-- (aplicar-permissoes-partes-2-e-3.sql), aplicadas em 29/09.
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo tem 5 migrações, nesta ordem (as mesmas dos arquivos de
-- aplicar de cada fatia, que continuam valendo um por um):
--   1. 20260929270000_porta_do_gerente.sql
--   2. 20260929271000_ninguem_gera_pontos_para_si.sql
--   3. 20260929272000_pessoa_pelo_tipo_da_acao.sql
--   4. 20260929273000_meta_so_do_master.sql
--   5. 20260929274000_arquivos_do_gerente.sql
--
-- O que muda: o gerente entra (seletor de loja e menu só com o que ele pode);
-- ninguém gera pontos para si mesmo (comunicado); pessoa em várias lojas pela
-- linha do tipo da ação; meta só do master e o nome de quem lançou a venda;
-- o gerente abre foto, anexo e recibo das lojas dele. Para o master nada muda
-- na tela, fora o histórico de vendas com nomes. Única mudança de dado: os
-- cargos perdem os códigos "Metas: criar meta" e "Metas: criar meta especial".
-- =========================================================================

BEGIN;

-- ------------------------------------------------------------------------
-- 20260929270000_porta_do_gerente.sql
-- ------------------------------------------------------------------------
-- Usuários gerenciais, PARTE 4, fatia 1: a porta de entrada do gerente
-- (29/09/2026).
--
-- 1. minhas_lojas(): o seletor de loja do topo. Hoje ele lê a tabela lojas
--    direto, e para o gerente vem vazio — nenhuma tela funciona. A função
--    devolve só as lojas de quem pergunta: o master, as ativas da conta dele
--    (o mesmo de hoje); o gerente, as ativas em que ele está.
-- 2. minhas_permissoes(): o que quem pergunta pode ver, para o menu esconder
--    o resto e o endereço digitado direto mostrar uma mensagem clara. Só diz
--    de quem pergunta. Esconder não é permissão: o banco continua conferindo.
-- 3. meu_acesso(): gerente bloqueado (usuário gerencial inativo) é desligado.
-- Para o master nada muda. Nenhum dado é alterado.

CREATE OR REPLACE FUNCTION public.minhas_lojas()
RETURNS TABLE (lojaid integer, nome varchar, cidade varchar, endereco varchar, ativa boolean,
               responsavelagendamentosid integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT l.lojaid, l.nome, l.cidade, l.endereco, l.ativa, l.responsavelagendamentosid
    FROM public.lojas l
   WHERE l.ativa
     AND (l.contaid = public.minha_conta()
          OR (l.contaid = public.conta_do_gerente()
              AND EXISTS (SELECT 1 FROM public.usuarioslojas ul
                           WHERE ul.userid = auth.uid() AND ul.contaid = l.contaid AND ul.lojaid = l.lojaid)))
   ORDER BY l.nome, l.lojaid
$$;
REVOKE ALL ON FUNCTION public.minhas_lojas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.minhas_lojas() TO authenticated;

-- master: todos os códigos do catálogo; gerente: os do cargo dele, cada um com
-- as lojas em que vale. Qualquer outro: nada.
CREATE OR REPLACE FUNCTION public.minhas_permissoes()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN public.sou_master() THEN
      jsonb_build_object('master', true,
                         'codigos', (SELECT jsonb_agg(k.codigo ORDER BY k.ordem) FROM public.catalogo_de_permissoes() k))
    WHEN public.conta_do_gerente() IS NOT NULL THEN
      jsonb_build_object('master', false,
                         'codigos', coalesce((SELECT jsonb_agg(DISTINCT cp.codigo ORDER BY cp.codigo)
                                                FROM public.usuariosgerenciais ug
                                                JOIN public.cargospermissoes cp ON cp.contaid = ug.contaid AND cp.cargoid = ug.cargoid
                                               WHERE ug.userid = auth.uid() AND ug.ativo
                                                 AND EXISTS (SELECT 1 FROM public.usuarioslojas ul
                                                              JOIN public.lojas l ON l.lojaid = ul.lojaid AND l.contaid = ul.contaid AND l.ativa
                                                             WHERE ul.userid = ug.userid AND ul.contaid = ug.contaid)), '[]'::jsonb))
    ELSE jsonb_build_object('master', false, 'codigos', '[]'::jsonb)
  END
$$;
REVOKE ALL ON FUNCTION public.minhas_permissoes() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.minhas_permissoes() TO authenticated;

-- meu_acesso: parte da versão viva (20260929160000_admin_clientes_e_redes.sql);
-- muda só o gerente bloqueado.
CREATE OR REPLACE FUNCTION public.meu_acesso()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  a     record;
BEGIN
  IF v_uid IS NULL THEN
    -- Sem token, ou token inválido/vencido: o banco não reconhece ninguém.
    RETURN jsonb_build_object('tipo', 'semlogin');
  END IF;
  IF public.eh_admin_geral() THEN
    RETURN jsonb_build_object('tipo', 'admin');
  END IF;

  SELECT cu.papel, cu.contaid, cu.lojaid, cu.funcionarioid,
         c.status AS statusconta, c.nomefantasia AS nomeconta,
         l.nome AS nomeloja, l.ativa AS lojaativa,
         f.nomecompleto AS nomepessoa, f.ativo AS pessoaativa,
         f.senhahashapp IS NULL AS semsenha, f.pinhash IS NULL AS sempin
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = v_uid;

  IF NOT FOUND THEN
    -- Token bom, mas esta pessoa não pertence a conta nenhuma.
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;

  -- Desligado na hora: pessoa inativa, loja desativada ou conta cancelada.
  IF a.statusconta = 'cancelada'
     OR (a.papel = 'loja' AND coalesce(a.lojaativa, false) = false)
     OR (a.papel = 'colaborador' AND coalesce(a.pessoaativa, false) = false)
     -- Gerente sem usuário gerencial ATIVO (bloqueado pelo master): desligado na hora.
     OR (a.papel = 'gerente' AND public.conta_do_gerente() IS NULL) THEN
    RETURN jsonb_build_object('tipo', 'desligado');
  END IF;

  RETURN jsonb_build_object(
    'tipo', a.papel,
    'conta', a.nomeconta,
    'loja', a.nomeloja,
    'nome', coalesce(a.nomepessoa, a.nomeloja, a.nomeconta),
    'somenteleitura', a.statusconta <> 'ativa',
    'semsenha', coalesce(a.semsenha, false),
    'sempin', coalesce(a.sempin, false),
    'politicapendente', CASE WHEN a.papel = 'colaborador'
                             THEN public.politica_pendente(a.contaid, a.funcionarioid) ELSE false END);
END;
$function$;

-- ------------------------------------------------------------------------
-- 20260929271000_ninguem_gera_pontos_para_si.sql
-- ------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------
-- 20260929272000_pessoa_pelo_tipo_da_acao.sql
-- ------------------------------------------------------------------------
-- A pessoa em várias lojas: a linha é o TIPO da ação (29/09/2026, decisão 4
-- do Wisley), e o acesso da pessoa passa a valer para o gerente (decisão 2).
--
--   dia a dia (feedback; justificativa e entrega já seguem a loja da tarefa):
--     UMA loja em comum com o gerente basta;
--   cadastro e acesso (trocar as lojas da pessoa, desativar, criar e redefinir
--     acesso): TODAS as lojas dela têm de ser dele.
-- Desativar, criar e redefinir acesso rodam no servidor: ele passa a
-- perguntar ao banco (posso_na_pessoa), com o login de quem pediu, em vez de
-- "é o master?". Ninguém faz isso com o próprio cadastro. Marcar quem valida e
-- trocar CPF continuam só do master. Para o master nada muda. Nenhum dado é
-- alterado.

-- registrar_feedback: parte da versão viva; dia a dia = uma loja em comum.
CREATE OR REPLACE FUNCTION public.registrar_feedback(p_funcionarioid integer, p_dia date, p_nota integer, p_comentario text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
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
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT (public.sou_master() OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                        WHERE fl.contaid = v_conta AND fl.funcionarioid = p_funcionarioid AND fl.ativo
                                          AND public.pode('feedbacks.registrar', fl.lojaid))) THEN
    RAISE EXCEPTION 'Seu cargo não permite dar feedback a esta pessoa (ela precisa trabalhar em uma das suas lojas).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém dá feedback de si mesmo (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, p_funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém dá feedback de si mesmo.' USING ERRCODE = 'insufficient_privilege';
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
$function$;

-- anular_feedback: parte da versão viva; dia a dia = uma loja em comum.
CREATE OR REPLACE FUNCTION public.anular_feedback(p_feedbackid integer, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_fb    public.feedbacks%ROWTYPE;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF length(btrim(coalesce(p_motivo, ''))) = 0 THEN
    RAISE EXCEPTION 'Informe o motivo.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_fb FROM public.feedbacks WHERE feedbackid = p_feedbackid AND contaid = v_conta FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Feedback não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão sobre a pessoa, no banco (usuários gerenciais, parte 2 — Feedbacks).
  IF NOT public.bot_contexto_confiavel() AND NOT (public.sou_master() OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                        WHERE fl.contaid = v_conta AND fl.funcionarioid = v_fb.funcionarioid AND fl.ativo
                                          AND public.pode('feedbacks.anular', fl.lojaid))) THEN
    RAISE EXCEPTION 'Seu cargo não permite anular feedback desta pessoa (ela precisa trabalhar em uma das suas lojas).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Ninguém anula feedback de si mesmo (o usuário gerencial ligado à pessoa).
  IF public.e_o_proprio(v_conta, v_fb.funcionarioid) THEN
    RAISE EXCEPTION 'Ninguém anula feedback de si mesmo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_fb.anuladoem IS NOT NULL THEN
    RAISE EXCEPTION 'Este feedback já foi anulado.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.feedbacks
     SET anuladoem = now(), anuladopor = auth.uid(), motivoanulacao = btrim(p_motivo)
   WHERE feedbackid = p_feedbackid;

  IF v_fb.pontosbonus > 0 THEN
    INSERT INTO public.movimentospontos (contaid, funcionarioid, tipo, pontos, descricao, feedbackid, criadopor)
    VALUES (v_conta, v_fb.funcionarioid, 'estorno_bonus', -v_fb.pontosbonus,
            'Feedback do dia ' || to_char(v_fb.datafeedback, 'DD/MM/YYYY') || ' anulado: ' || btrim(p_motivo),
            p_feedbackid, auth.uid());
  END IF;
END;
$function$;

-- salvar_pessoa: parte da versão viva; trocar as lojas exige a pessoa inteira nas lojas dele.
CREATE OR REPLACE FUNCTION public.salvar_pessoa(p_funcionarioid integer, p_nomecompleto text, p_cpf text, p_cargo text, p_setor text, p_telefone text, p_diadefolga integer, p_lojas integer[], p_validador integer[] DEFAULT '{}'::integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      -- Lojas: trocar as lojas é CADASTRO: a pessoa inteira nas lojas dele
      -- (decisão 4); e só as lojas dele mudam; quem valida, só o master.
      IF EXISTS (
           SELECT 1
             FROM (SELECT l FROM unnest(v_lojas) l
                   UNION SELECT lojaid FROM public.funcionarioslojas WHERE funcionarioid = v_id AND ativo) u(l)
             LEFT JOIN public.funcionarioslojas fl ON fl.funcionarioid = v_id AND fl.lojaid = u.l
            WHERE coalesce(fl.ativo, false) IS DISTINCT FROM (u.l = ANY (v_lojas)))
         AND NOT public.pode_na_pessoa('equipe.editar', v_conta, v_id) THEN
        RAISE EXCEPTION 'Esta pessoa trabalha também em loja fora das suas: só o dono da conta troca as lojas dela.'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
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
$function$;

-- O servidor pergunta: quem pediu pode fazer <codigo> nesta pessoa? Responde
-- só sobre quem pergunta (pelo token): a conta dele e se pode. Para o acesso
-- da pessoa (cadastro): TODAS as lojas dela dentro das dele, e nunca o próprio.
CREATE OR REPLACE FUNCTION public.posso_na_pessoa(p_codigo text, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  -- Negado: só {"pode": false}, sem a conta.
  IF v_conta IS NULL OR p_codigo NOT IN ('equipe.desativar', 'equipe.criar_acesso', 'equipe.redefinir_acesso')
     OR NOT EXISTS (SELECT 1 FROM public.funcionarios WHERE contaid = v_conta AND funcionarioid = p_funcionarioid)
     OR NOT coalesce(public.pode_na_pessoa(p_codigo, v_conta, p_funcionarioid), false)
     OR coalesce(public.e_o_proprio(v_conta, p_funcionarioid), true) THEN
    RETURN jsonb_build_object('pode', false);
  END IF;
  RETURN jsonb_build_object('pode', true, 'conta', v_conta);
END;
$$;
REVOKE ALL ON FUNCTION public.posso_na_pessoa(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.posso_na_pessoa(text, integer) TO authenticated;

-- ------------------------------------------------------------------------
-- 20260929273000_meta_so_do_master.sql
-- ------------------------------------------------------------------------
-- Metas: a meta e os pontos são só do master (29/09/2026, decisão 5 do Wisley).
--
-- O gerente pode LANÇAR a venda da loja dele (com "Metas: lançar venda"), mas
-- criar ou mudar a meta do mês, as metas da semana e as metas especiais volta
-- a ser só do dono da conta: "o risco não é ele ganhar os pontos, é ele inflar
-- a venda para bater a meta". Os códigos "Metas: criar meta" e "Metas: criar
-- meta especial" saem do catálogo, e os cargos que os tinham os perdem (esta é
-- a única mudança de dado). Quem lançou cada venda já ficava gravado; agora o
-- master vê o NOME de quem lançou e de quem corrigiu (historico_das_vendas).

-- salvar_meta_do_mes: parte da versão viva; só o master (ou o bot).
CREATE OR REPLACE FUNCTION public.salvar_meta_do_mes(p_lojaid integer, p_mes date, p_nome text, p_valor numeric, p_pontos integer, p_descricao text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_ini   date := date_trunc('month', p_mes)::date;
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (usuários gerenciais, parte 2 — Metas).
  IF NOT public.bot_contexto_confiavel() AND NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria e muda a meta do mês.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_ini < public.primeiro_dia_editavel_meta() THEN
    RAISE EXCEPTION 'Só dá para mexer na meta do mês atual, do anterior e dos próximos.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_valor IS NULL OR p_valor <= 0 THEN
    RAISE EXCEPTION 'A meta do mês precisa ser maior que zero.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_pontos IS NULL OR p_pontos < 0 THEN
    RAISE EXCEPTION 'Os pontos do prêmio precisam ser zero ou mais.' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM pg_advisory_xact_lock(p_lojaid, -(extract(year FROM v_ini)::integer * 12 + extract(month FROM v_ini)::integer));

  INSERT INTO public.metasprincipais (contaid, lojaid, nomemeta, descricao, valormetatotal, datainicio, datafim,
                                      pontospremio, criadopor)
  VALUES (v_conta, p_lojaid, coalesce(nullif(btrim(coalesce(p_nome, '')), ''), 'Meta de ' || to_char(v_ini, 'MM/YYYY')),
          nullif(btrim(coalesce(p_descricao, '')), ''), round(p_valor, 2), v_ini,
          (v_ini + interval '1 month - 1 day')::date, p_pontos, auth.uid())
  ON CONFLICT (lojaid, datainicio) DO UPDATE
     SET nomemeta = EXCLUDED.nomemeta, descricao = EXCLUDED.descricao,
         valormetatotal = EXCLUDED.valormetatotal, pontospremio = EXCLUDED.pontospremio, atualizadoem = now()
  RETURNING metaprincipalid INTO v_id;

  -- Lancamentos do mes que ainda nao estavam ligados a meta.
  UPDATE public.metasdiariasapuracoes SET metaprincipalid = v_id
   WHERE lojaid = p_lojaid AND dataapuracao BETWEEN v_ini AND (v_ini + interval '1 month - 1 day')::date
     AND metaprincipalid IS DISTINCT FROM v_id;

  PERFORM public.reavaliar_meta_do_mes(v_conta, p_lojaid, v_ini);
  RETURN v_id;
END;
$function$;

-- salvar_metas_da_semana: parte da versão viva; só o master.
CREATE OR REPLACE FUNCTION public.salvar_metas_da_semana(p_lojaid integer, p_linhas jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria e muda as metas da semana.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.metasdiariasmodelos (contaid, lojaid, diasemanaid, nomedia, valormeta, pontospremio)
  SELECT v_conta, p_lojaid, (l->>'diasemanaid')::integer, l->>'nomedia', (l->>'valormeta')::numeric, (l->>'pontospremio')::integer
    FROM jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) l
  ON CONFLICT (lojaid, diasemanaid) DO UPDATE
     SET nomedia = EXCLUDED.nomedia, valormeta = EXCLUDED.valormeta, pontospremio = EXCLUDED.pontospremio;
END;
$function$;

-- criar_meta_especial: parte da versão viva; só o master.
CREATE OR REPLACE FUNCTION public.criar_meta_especial(p_lojaid integer, p_data date, p_descricao text, p_valormeta numeric, p_pontospremio integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta cria meta especial.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.metasespeciais (contaid, lojaid, data, descricao, valormeta, pontospremio)
  VALUES (v_conta, p_lojaid, p_data, p_descricao, p_valormeta, p_pontospremio)
  RETURNING metaespecialid INTO v_id;
  RETURN v_id;
END;
$function$;

-- apagar_meta_especial: parte da versão viva; só o master.
CREATE OR REPLACE FUNCTION public.apagar_meta_especial(p_metaespecialid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_loja integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT lojaid INTO v_loja FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
  -- Não existe (ou é de outra conta): como antes, não apaga nada.
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta apaga meta especial.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  DELETE FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
END;
$function$;

-- catalogo_de_permissoes: parte da versão viva; sem os dois códigos de meta.
CREATE OR REPLACE FUNCTION public.catalogo_de_permissoes()
 RETURNS TABLE(codigo text, tela text, nome text, ordem integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT v.codigo, v.tela, v.nome, v.ordem FROM (VALUES
    ('inicio.ver',                'Início',          'Ver',                                   10),
    ('painel.ver',                'Painel da loja',  'Ver',                                   20),
    ('quadro.ver',                'Quadro',          'Ver',                                   30),
    ('quadro.registrar_entrega',  'Quadro',          'Registrar entrega',                     31),
    ('quadro.aprovar',            'Quadro',          'Aprovar',                               32),
    ('quadro.recusar',            'Quadro',          'Recusar',                               33),
    ('quadro.estornar',           'Quadro',          'Estornar entrega aprovada',             34),
    ('quadro.revogar_aceite',     'Quadro',          'Revogar aceite',                        35),
    ('quadro.passar_folga',       'Quadro',          'Passar tarefa de quem está de folga',   36),
    ('tarefas.ver',               'Tarefas',         'Ver',                                   40),
    ('tarefas.atribuir',          'Tarefas',         'Atribuir',                              41),
    ('tarefas.encerrar_atribuicao','Tarefas',        'Encerrar atribuição',                   42),
    ('tarefas.catalogo',          'Tarefas',         'Editar catálogo (criar, editar, desativar)', 43),
    ('solicitacoes.ver',          'Solicitações',    'Ver',                                   50),
    ('solicitacoes.abrir',        'Solicitações',    'Abrir',                                 51),
    ('solicitacoes.concluir',     'Solicitações',    'Concluir',                              52),
    ('solicitacoes.recusar',      'Solicitações',    'Recusar',                               53),
    ('relatorios.ver',            'Relatórios',      'Ver',                                   60),
    ('equipe.ver',                'Equipe',          'Ver',                                   70),
    ('equipe.criar',              'Equipe',          'Criar pessoa',                          71),
    ('equipe.editar',             'Equipe',          'Editar',                                72),
    ('equipe.desativar',          'Equipe',          'Desativar e reativar',                  73),
    ('equipe.criar_acesso',       'Equipe',          'Criar acesso',                          74),
    ('equipe.redefinir_acesso',   'Equipe',          'Redefinir acesso',                      75),
    ('equipe.liberar_pin',        'Equipe',          'Liberar PIN',                           76),
    ('jornada.ver',               'Jornada',         'Ver',                                   80),
    ('jornada.vincular',          'Jornada',         'Ligar pessoa a uma jornada',            81),
    ('jornada.mapa',              'Jornada',         'Mapa e exportar',                       82),
    ('feedbacks.ver',             'Feedbacks',       'Ver',                                   90),
    ('feedbacks.registrar',       'Feedbacks',       'Registrar',                             91),
    ('feedbacks.anular',          'Feedbacks',       'Anular',                                92),
    ('justificativas.ver',        'Justificativas',  'Ver',                                  100),
    ('justificativas.registrar',  'Justificativas',  'Registrar',                            101),
    ('justificativas.decidir',    'Justificativas',  'Aceitar e recusar',                    102),
    ('ranking.ver',               'Ranking',         'Ver',                                  110),
    ('conquistas.ver',            'Conquistas',      'Ver',                                  111),
    ('extrato.ver',               'Extrato',         'Ver',                                  112),
    ('premios.ver',               'Prêmios',         'Ver',                                  120),
    ('premios.registrar',         'Prêmios',         'Registrar resgate',                    121),
    ('premios.entregar',          'Prêmios',         'Aprovar (entregar) resgate',           122),
    ('premios.cancelar',          'Prêmios',         'Cancelar resgate',                     123),
    ('premios.estornar',          'Prêmios',         'Estornar resgate',                     124),
    ('metas.ver',                 'Metas',           'Ver',                                  130),
    ('metas.lancar_venda',        'Metas',           'Lançar venda',                         131),
    ('agenda.ver',                'Agenda',          'Ver',                                  140),
    ('agenda.editar',             'Agenda',          'Criar e editar',                       141),
    ('agenda.realizado',          'Agenda',          'Marcar realizado',                     142),
    ('agenda.pagamento',          'Agenda',          'Pagamento',                            143),
    ('comunicados.ver',           'Comunicados',     'Ver',                                  150),
    ('comunicados.publicar',      'Comunicados',     'Publicar',                             151),
    ('onboarding.ver',            'Onboarding',      'Ver',                                  160),
    ('onboarding.conduzir',       'Onboarding',      'Conduzir',                             161),
    ('lojas.ver',                 'Lojas',           'Ver',                                  170),
    ('lojas.editar',              'Lojas',           'Editar',                               171),
    ('lojas.tv',                  'Lojas',           'Configurar TV',                        172),
    ('lojas.tablet_som',          'Lojas',           'Som do tablet',                        173),
    ('lojas.tablet_acesso',       'Lojas',           'Senha do tablet',                      174),
    ('valores.ver_rs',            'Todas as telas',  'Ver valores em R$',                    180)
  ) AS v(codigo, tela, nome, ordem)
$function$;

-- Os cargos que tinham os dois códigos os perdem (o histórico dos cargos
-- registra a remoção, como qualquer outra).
DELETE FROM public.cargospermissoes WHERE codigo IN ('metas.criar_meta', 'metas.meta_especial');

-- O que aconteceu com as vendas da loja: lançamentos e correções, com o nome
-- de quem fez. Só o master (é a conferência dele sobre quem lança a venda).
CREATE OR REPLACE FUNCTION public.historico_das_vendas(p_lojaid integer)
RETURNS TABLE(historicoid integer, dataapuracao date, valoranterior numeric, valornovo numeric,
              motivo text, alteradoem timestamptz, quem text, foivoce boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT h.historicoid, h.dataapuracao, h.valoranterior, h.valornovo, h.motivo::text, h.alteradoem,
         coalesce(public.autor_em(h.alteradopor, h.alteradoem), CASE WHEN h.alteradopor IS NULL THEN 'Sistema' ELSE 'desconhecido' END),
         h.alteradopor IS NOT DISTINCT FROM auth.uid()
    FROM public.metashistorico h
   WHERE public.sou_master() AND h.contaid = public.minha_conta() AND h.lojaid = p_lojaid
   ORDER BY h.alteradoem DESC, h.historicoid DESC
   LIMIT 200
$$;
REVOKE ALL ON FUNCTION public.historico_das_vendas(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.historico_das_vendas(integer) TO authenticated;

-- ------------------------------------------------------------------------
-- 20260929274000_arquivos_do_gerente.sql
-- ------------------------------------------------------------------------
-- Arquivos para o gerente: só leitura, só das lojas dele, só com a permissão
-- de ver aquela tela (29/09/2026, decisão 1 do Wisley).
--
--   foto da entrega   -> "Quadro: ver" na loja da entrega;
--   anexo da agenda   -> "Agenda: ver" na loja do agendamento;
--   recibo do resgate -> "Prêmios: ver" na loja do resgate (resgate sem loja: só o master).
--
-- O arquivo só abre se existir a LINHA no banco (a entrega com aquele caminho,
-- o agendamento daquela pasta) numa loja em que ele pode ver a tela: o nome do
-- arquivo sozinho não basta. Enviar, trocar e apagar continuam como estavam.
-- O canal confidencial e os documentos pessoais NUNCA, para nenhum papel: não
-- ganham regra nenhuma aqui (e a seção 112 do teste confere).
-- Para o master nada muda. Nenhum dado é alterado.

-- A foto: a entrega com este caminho, numa loja em que ele vê o Quadro.
CREATE OR REPLACE FUNCTION public.foto_de_entrega_do_gerente(p_nome text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.entregas e
     WHERE e.pathfotoevidencia = p_nome
       AND e.contaid = public.conta_do_gerente()
       AND split_part(p_nome, '/', 1) = e.contaid::text
       AND public.pode('quadro.ver', e.lojaid))
$$;
REVOKE ALL ON FUNCTION public.foto_de_entrega_do_gerente(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.foto_de_entrega_do_gerente(text) TO authenticated;

-- A foto é procurada pelo caminho: sem índice, cada foto do Quadro leria a
-- tabela de entregas inteira.
CREATE INDEX IF NOT EXISTS entregas_pathfotoevidencia ON public.entregas (pathfotoevidencia)
  WHERE pathfotoevidencia IS NOT NULL;

-- O anexo: a pasta <conta>/<loja>/<agendamento>/ de um agendamento de loja em
-- que ele vê a Agenda.
CREATE OR REPLACE FUNCTION public.anexo_da_agenda_do_gerente(p_nome text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.agendamentos a
     WHERE a.contaid = public.conta_do_gerente()
       AND split_part(p_nome, '/', 1) = a.contaid::text
       AND split_part(p_nome, '/', 2) = a.lojaid::text
       AND split_part(p_nome, '/', 3) = a.agendamentoid::text
       AND split_part(p_nome, '/', 4) <> ''
       AND public.pode('agenda.ver', a.lojaid))
$$;
REVOKE ALL ON FUNCTION public.anexo_da_agenda_do_gerente(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.anexo_da_agenda_do_gerente(text) TO authenticated;

-- As regras do Storage: SÓ leitura, presas à conta do gerente pela primeira
-- pasta e à linha do banco pela função acima.
DROP POLICY IF EXISTS entregas_sel_gerente ON storage.objects;
CREATE POLICY entregas_sel_gerente ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'entregas'
         AND split_part(name, '/', 1) = ((SELECT public.conta_do_gerente()))::text
         AND public.foto_de_entrega_do_gerente(name));
DROP POLICY IF EXISTS agendamentos_arq_sel_gerente ON storage.objects;
CREATE POLICY agendamentos_arq_sel_gerente ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'agendamentos'
         AND split_part(name, '/', 1) = ((SELECT public.conta_do_gerente()))::text
         AND public.anexo_da_agenda_do_gerente(name));

-- O recibo do resgate: o master segue pelo caminho de sempre (regras das
-- tabelas); o gerente, pela versão que lê só resgates das lojas em que ele vê
-- os Prêmios.
CREATE OR REPLACE FUNCTION public.recibo_resgate_gerente(p_resgateid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nomefantasia AS conta
      FROM public.resgates r
      JOIN public.funcionarios f ON f.funcionarioid = r.funcionarioid
      JOIN public.produtosloja p ON p.produtoid = r.produtoid
      JOIN public.contas c       ON c.contaid = r.contaid
      LEFT JOIN public.lojas l   ON l.lojaid = r.lojaid
     WHERE r.resgateid = p_resgateid
       AND r.contaid = public.conta_do_gerente()
       AND r.lojaid IS NOT NULL AND public.pode('premios.ver', r.lojaid)
  ),
  mov AS (
    SELECT m.movimentoid, m.datamovimento, m.tipo, m.pontos, m.descricao,
           (SELECT coalesce(sum(x.pontos), 0) FROM public.movimentospontos x
             WHERE x.funcionarioid = m.funcionarioid AND x.movimentoid < m.movimentoid) AS saldoantes
      FROM public.movimentospontos m
     WHERE m.resgateid = p_resgateid AND m.contaid = public.conta_do_gerente()
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
$function$;
REVOKE ALL ON FUNCTION public.recibo_resgate_gerente(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.recibo_resgate_gerente(integer) TO authenticated;

-- recibo_resgate: parte da versão viva; o master, igual; o gerente, desviado.
CREATE OR REPLACE FUNCTION public.recibo_resgate(p_resgateid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.recibo_resgate_gerente(p_resgateid);
  END IF;
  RETURN (
  WITH r AS (
    SELECT r.*, f.nomecompleto, p.nome AS premio, l.nome AS loja, c.nomefantasia AS conta
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
  );
END;
$function$;

COMMIT;
