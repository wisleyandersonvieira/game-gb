-- CLASSIFICAÇÃO: TIRA
-- (apaga funções, tabelas e colunas que a versão no ar usa — convite do
-- Telegram, vínculos, grupos, mensagens automáticas — e muda o salvar_pessoa
-- (sai o parâmetro p_validador) e o vinculos_da_tela (sai a coluna
-- validador). Aplica e publica JUNTOS, com as lojas fechadas.)
--
-- O Telegram sai inteiro (04/10/2026, decisão do Wisley: o sistema não vai
-- usar Telegram). Saem as funções do bot, os avisos por gatilho, o
-- agendamento da fila, a fila de mensagens, os convites, os vínculos e os
-- grupos, as mensagens automáticas, a marca "validador" (só dizia quem aprova
-- pelo Telegram) e as configurações que só o bot lia.
--
-- OS DADOS TAMBÉM SAEM: o identificador de Telegram das pessoas
-- (funcionarios.chatidtelegram, telegramvinculos) é dado pessoal sem
-- finalidade sem o bot. A fila de mensagens não tem valor histórico.
--
-- FICAM, de propósito (fatia 2 ou decisão do Wisley):
--   * bot_contexto_confiavel, conta_do_bot e funcionario_do_bot: estão dentro
--     de ~110 funções (inclusive minha_conta); saem na fatia 2, com prova
--     própria. Sem as funções do bot, nada liga esse contexto.
--   * bot_falta_feedback_ontem: o aplicativo do colaborador a usa (aviso de
--     feedback de ontem) — pergunta ao Wisley.
--   * marcar_aviso_lido: é a caixa "Avisos do sistema" do Início, não Telegram.
--   * o intervalo da jornada: pergunta ao Wisley.
--   * as configurações que só o bot lia, com o histórico delas (ver o item 3).

-- ---------------------------------------------------------------------------
-- 1. Os avisos por gatilho e o agendamento da fila
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS entregas_aviso_telegram ON public.entregas;
DROP TRIGGER IF EXISTS conquistasfuncionarios_aviso_telegram ON public.conquistasfuncionarios;
DROP TRIGGER IF EXISTS metaspremiacoes_aviso_telegram ON public.metaspremiacoes;
DROP TRIGGER IF EXISTS documentosassinaturas_aviso_telegram ON public.documentosassinaturas;
DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE $c$SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'stgame-telegram-fila'$c$;
  END IF;
  -- O segredo da fila no cofre (o que o agendamento usava).
  IF to_regclass('vault.secrets') IS NOT NULL THEN
    EXECUTE $c$DELETE FROM vault.secrets WHERE name = 'stgame_fila_segredo'$c$;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. As funções que ficam, sem o Telegram (cada uma a partir da versão mais recente)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rotinas_despachar(p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record; v_n integer := 0; v_erros integer := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(7310) THEN
    RETURN jsonb_build_object('ocupado', true);
  END IF;

  -- A resposta das chamadas ao servidor (o apagamento das fotos), antes de o
  -- banco jogar fora (30/09/2026). Um erro aqui não atrapalha as rotinas.
  BEGIN
    PERFORM public.registrar_respostas_do_servidor();
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  FOR c IN SELECT contaid FROM public.contas WHERE status = 'ativa' ORDER BY contaid LOOP
    BEGIN
      PERFORM public.rotina_lista_do_dia(c.contaid, p_agora, 'agendada');
      PERFORM public.rotina_fechamento_mensal(c.contaid, p_agora);
      PERFORM public.rotina_conferencia_livro(c.contaid, p_agora);
      PERFORM public.rotina_limpeza(c.contaid, p_agora);
      PERFORM public.rotina_expurgo_fotos(c.contaid, p_agora);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      PERFORM public.rotina_registrar(c.contaid, 'lista_do_dia', NULL, 'agendada', clock_timestamp(), 'erro', NULL, SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('contas', v_n, 'erros', v_erros);
END;
$function$;

CREATE OR REPLACE FUNCTION public.saude_das_rotinas()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_segredos jsonb := '{}'::jsonb;
  v_jobs     jsonb := '[]'::jsonb;
  v_nome     text;
  v_existe   boolean;
  v_fotos    jsonb;
  v_fila     jsonb;
  v_diarias  jsonb;
  v_apagar   jsonb;
  v_storage  jsonb;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    FOREACH v_nome IN ARRAY ARRAY['stgame_funcoes_url', 'stgame_expurgo_segredo'] LOOP
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = $1 AND coalesce(decrypted_secret, '''') <> '''')'
        INTO v_existe USING v_nome;
      v_segredos := v_segredos || jsonb_build_object(v_nome, v_existe);
    END LOOP;
  END IF;

  IF to_regclass('cron.job') IS NOT NULL THEN
    -- Os agendamentos (o do Telegram saiu em 04/10/2026), com o comando que cada um deve rodar, de quanto
    -- em quanto tempo, e se está atrasado: sem rodar há mais de 3 intervalos
    -- (no mínimo 15 minutos), ou nunca rodou (30/09/2026).
    EXECUTE $q$
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'nome', n.nome,
               'existe', j.jobid IS NOT NULL,
               'ativo', coalesce(j.active, false),
               'comandocerto', j.command IS NOT NULL AND btrim(j.command) = n.comando,
               'intervalosegundos', n.segundos,
               'ultimaexecucao', r.end_time,
               'ultimostatus', r.status,
               'atrasado', j.jobid IS NULL OR r.end_time IS NULL
                           OR r.end_time < now() - make_interval(secs => greatest(3 * n.segundos, 900)))
             ORDER BY n.nome), '[]'::jsonb)
        FROM (VALUES ('gamegb-rotinas', 'SELECT public.rotinas_despachar()', 300),
                     ('stgame-codigos-vencidos', 'SELECT public.limpar_codigos_vencidos()', 300)) n(nome, comando, segundos)
        LEFT JOIN cron.job j ON j.jobname = n.nome
        LEFT JOIN LATERAL (SELECT d.end_time, d.status FROM cron.job_run_details d
                            WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1) r ON true
    $q$ INTO v_jobs;
  END IF;

  SELECT jsonb_build_object(
           'vencidas', coalesce(sum((f->>'vencidas')::integer), 0),
           'diasdeatraso', coalesce(max((f->>'diasdeatraso')::integer), 0),
           'presas', coalesce(sum((f->>'presas')::integer), 0))
    INTO v_fotos
    FROM (SELECT public.fotos_vencidas_da_conta(c.contaid) f FROM public.contas c) x;

  -- Dias sem foto da fila: quantos, em quantas contas, e o mais recente.
  SELECT jsonb_build_object(
           'dias', coalesce(sum((f->>'dias')::integer), 0),
           'contas', count(*) FILTER (WHERE (f->>'dias')::integer > 0),
           'ultimo', max((f->>'ultimo')::date))
    INTO v_fila
    FROM (SELECT public.fila_dias_sem_foto(c.contaid) f FROM public.contas c WHERE c.status = 'ativa') x;

  -- Cada rotina diária: a última vez que rodou (em qualquer conta) e em
  -- quantas contas ativas ela está atrasada (sem rodar há mais de 30 horas;
  -- conta criada há menos de 30 horas não conta) ou com erro na última vez.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'rotina', x.rotina, 'ultima', x.ultima, 'contas', x.contas,
           'atrasadas', x.atrasadas, 'comerro', x.comerro) ORDER BY x.ordem), '[]'::jsonb)
    INTO v_diarias
    FROM (SELECT n.rotina, n.ordem, max(u.ultima) AS ultima, count(c.contaid) AS contas,
                 count(c.contaid) FILTER (WHERE c.criadoem < now() - interval '30 hours'
                                            AND (u.ultima IS NULL OR u.ultima < now() - interval '30 hours')) AS atrasadas,
                 count(c.contaid) FILTER (WHERE u.resultado = 'erro') AS comerro
            FROM (VALUES ('lista_do_dia', 1), ('foto_da_fila', 2), ('conferencia_livro', 3),
                         ('limpeza', 4), ('expurgo_fotos', 5)) n(rotina, ordem)
            CROSS JOIN public.contas c
            LEFT JOIN LATERAL (SELECT e.iniciadoem AS ultima, e.resultado
                                 FROM public.rotinasexecucoes e
                                WHERE e.contaid = c.contaid AND e.rotina = n.rotina
                                ORDER BY e.iniciadoem DESC LIMIT 1) u ON true
           WHERE c.status = 'ativa'
           GROUP BY n.rotina, n.ordem) x;

  -- O apagamento: a fila e a última chamada à função que apaga (com a resposta).
  SELECT jsonb_build_object(
           'nafila',       count(*) FILTER (WHERE f.removidoem IS NULL AND f.tentativas < 5),
           'presas',       count(*) FILTER (WHERE f.removidoem IS NULL AND f.tentativas >= 5),
           'maisantiga',   min(f.criadoem) FILTER (WHERE f.removidoem IS NULL),
           'apagadas24h',  count(*) FILTER (WHERE f.removidoem >= now() - interval '24 hours'),
           'apagadas7d',   count(*) FILTER (WHERE f.removidoem >= now() - interval '7 days'),
           'ultimachamada', (SELECT jsonb_build_object('pedidaem', c.pedidaem, 'chamou', c.requestid IS NOT NULL,
                                                        'respondidaem', c.respondidaem, 'status', c.status,
                                                        'apagados', c.apagados, 'erro', c.erro)
                               FROM public.chamadasdoservidor c WHERE c.funcao = 'expurgo-fotos'
                              ORDER BY c.pedidaem DESC, c.chamadaid DESC LIMIT 1),
           'ultimosucesso', (SELECT max(c.pedidaem) FROM public.chamadasdoservidor c
                              WHERE c.funcao = 'expurgo-fotos' AND c.status = 200),
           -- Até 5 caminhos apagados nos últimos 7 dias: a /saude pergunta ao
           -- próprio Storage se eles sumiram (o caminho não vai para a tela).
           'amostraapagadas', coalesce((SELECT jsonb_agg(s.caminho) FROM (
                                SELECT f2.caminho FROM public.fotosexpurgo f2
                                 WHERE f2.removidoem >= now() - interval '7 days'
                                 ORDER BY f2.removidoem DESC LIMIT 5) s), '[]'::jsonb))
    INTO v_apagar
    FROM public.fotosexpurgo f;

  -- CONTADO NO PRÓPRIO STORAGE (storage.objects, o índice do Storage), e não
  -- no que o sistema acha que fez. Bucket das fotos de entrega; a conta vem
  -- do começo do caminho (<contaid>/<lojaid>/...).
  IF to_regclass('storage.objects') IS NOT NULL THEN
    WITH prazo AS (
      SELECT c.contaid, public.dias_guardar_foto(c.contaid) AS dias FROM public.contas c
    ), arq AS (
      SELECT o.name, o.created_at, p.contaid, p.dias
        FROM storage.objects o
        LEFT JOIN prazo p ON o.name ~ '^[0-9]+/' AND p.contaid = split_part(o.name, '/', 1)::integer
       WHERE o.bucket_id = 'entregas'
    ), ent AS (
      -- Uma linha por arquivo: a entrega mais recente que o usa.
      SELECT e.contaid, e.pathfotoevidencia AS name, max(e.dataenvio) AS ultimoenvio
        FROM public.entregas e WHERE e.pathfotoevidencia IS NOT NULL
       GROUP BY 1, 2
    ), fila AS (
      SELECT f.contaid, f.caminho AS name,
             bool_or(f.removidoem IS NULL) AS na_fila, bool_or(f.removidoem IS NOT NULL) AS dado_como_apagado
        FROM public.fotosexpurgo f GROUP BY 1, 2
    ), classe AS (
      SELECT a.*,
             coalesce(en.ultimoenvio >= now() - make_interval(days => a.dias), false) AS serve_no_prazo,
             en.name IS NOT NULL AS tem_entrega,
             coalesce(fi.na_fila, false) AS na_fila,
             coalesce(fi.dado_como_apagado, false) AS dado_como_apagado
        FROM arq a
        LEFT JOIN ent en ON en.contaid = a.contaid AND en.name = a.name
        LEFT JOIN fila fi ON fi.contaid = a.contaid AND fi.name = a.name
    )
    SELECT jsonb_build_object(
             'arquivos', count(*),
             -- Vencido e ainda guardado: mais velho que o prazo da conta e não
             -- serve a nenhuma entrega dentro do prazo.
             'vencidos', count(*) FILTER (WHERE created_at < now() - make_interval(days => coalesce(dias, 90))
                                            AND NOT serve_no_prazo),
             'vencidomaisantigo', min(created_at) FILTER (WHERE created_at < now() - make_interval(days => coalesce(dias, 90))
                                                           AND NOT serve_no_prazo),
             -- O sistema diz que apagou e o arquivo continua lá: tem de ser 0.
             'apagadosquecontinuam', count(*) FILTER (WHERE dado_como_apagado),
             -- Nenhuma entrega usa e não está na fila: nunca será apagado.
             'semdono', count(*) FILTER (WHERE NOT tem_entrega AND NOT na_fila AND NOT dado_como_apagado),
             'semdonomaisantigo', min(created_at) FILTER (WHERE NOT tem_entrega AND NOT na_fila AND NOT dado_como_apagado))
      INTO v_storage
      FROM classe;
  END IF;

  RETURN jsonb_build_object(
    'diarias', v_diarias,
    'apagamento', v_apagar,
    'storage', v_storage,
    'cofre', to_regclass('vault.decrypted_secrets') IS NOT NULL,
    'pgnet', to_regproc('net.http_post') IS NOT NULL,
    'segredos', v_segredos,
    'agendador', to_regclass('cron.job') IS NOT NULL,
    'jobs', v_jobs,
    'fotos', v_fotos,
    'fila', v_fila);
END;
$function$;

CREATE OR REPLACE FUNCTION public.saude_da_minha_conta()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object(
    'fotos', public.fotos_vencidas_da_conta(v_conta),
    'fila', public.fila_dias_sem_foto(v_conta));
END;
$$;

CREATE OR REPLACE FUNCTION public.cria_configuracoes_padrao(p_contaid integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  INSERT INTO public.configuracoes (contaid, chave, valor, descricao) VALUES
    (p_contaid, 'TAXA_CONVERSAO_PONTO_REAL',     '0.03',  'Quanto vale 1 ponto em reais.'),
    (p_contaid, 'PONTOS_BONUS_FEEDBACK_DIARIO',  '5',     'Pontos de bonus por enviar o feedback do dia.'),
    (p_contaid, 'PONTOS_BONUS_NOTA_FISCAL',      '10',    'Pontos de bonus por enviar uma nota fiscal.'),
    (p_contaid, 'MAX_DIFERENCA_FOTO_SEGUNDOS',   '120',   'Tolerancia, em segundos, entre a hora da foto (EXIF) e o envio.'),
    (p_contaid, 'DIAS_GUARDAR_FOTO_ENTREGA',     '180',   'Por quantos dias a foto da entrega fica guardada. Depois disso o arquivo é apagado; a entrega e os pontos ficam. Mínimo 90.'),
    (p_contaid, 'HORARIO_GERACAO_TAREFAS',       '00:05', 'Hora em que a lista de tarefas do dia é gerada.'),
    (p_contaid, 'HORARIO_CONFERENCIA_LIVRO',     '03:00', 'Hora da conferência diária do livro de pontos, da limpeza do registro de rotinas e do expurgo de fotos.'),
    (p_contaid, 'HORARIO_FECHAMENTO_MENSAL',     '08:00', 'Hora do fechamento mensal do ranking (executa no dia 1).'),
    (p_contaid, 'CONTATO_PRIVACIDADE',           '',      'Nome e contato de quem responde sobre dados pessoais (aparece na política de uso).'),
    (p_contaid, 'MINUTOS_RODIZIO_ACEITE',       '10',    'Rodizio no aceite: minutos que quem pegou a ultima tarefa disputada da loja espera antes de poder pegar outra. 0 desliga.'),
    (p_contaid, 'MINUTOS_TAREFA_PARADA',        '30',    'A partir de quantos minutos o tablet marca a tarefa como parada ha muito tempo.'),
    (p_contaid, 'TAREFA_ID_FEEDBACK_DIARIO',           '', 'ID da tarefa de feedback diario. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_ID_LEITURA',                   '', 'ID da tarefa de leitura de comunicado. Preenchido pelo sistema.'),
    (p_contaid, 'TAREFA_MODELO_AGENDAMENTO_ID',        '', 'ID da tarefa modelo usada ao criar um agendamento.'),
    (p_contaid, 'TAREFA_ID_PONTOS_META',               '', 'ID da tarefa que credita os pontos da meta diaria.'),
    (p_contaid, 'TAREFA_ID_NOTA_FISCAL',               '', 'ID da tarefa de envio de nota fiscal.'),
    (p_contaid, 'TAREFA_ID_GUARDAR_MERCADORIA_MODELO', '', 'ID da tarefa modelo de guardar mercadoria.'),
    -- Fuso da empresa: decide a que horas a tarefa fica disponivel. Uma loja
    -- em Campo Grande fica uma hora atras de Brasilia.
    (p_contaid, 'FUSO_HORARIO', 'America/Sao_Paulo',
     'Fuso horario da empresa. Decide a que horas a tarefa fica disponivel para a equipe.'),
    -- SOM_TAREFA_NOVA e SOM_VOLUME sairam daqui em 25/09/2026: o som do tablet
    -- agora e por loja, nas colunas lojas.somtarefanova / somvolume /
    -- somrepetirminutos, configuradas no botao "Configuracoes" da loja.
    -- Cuidado com o dia do gestor, nao trava de seguranca.
    (p_contaid, 'MAX_PEDIDOS_LOJA_HORA', '10',
     'Quantos pedidos a mesma loja pode abrir pelo tablet em uma hora.'),
    -- Pedido de resgate feito pelo celular do colaborador.
    (p_contaid, 'MAX_RESGATES_PENDENTES', '3',
     'Quantos pedidos de resgate a mesma pessoa pode ter esperando o gestor.'),
    (p_contaid, 'MAX_RESGATES_HORA', '5',
     'Quantos pedidos de resgate a mesma pessoa pode fazer em uma hora.'),
    -- Teto de pontos por ciência de comunicado (29/09/2026).
    (p_contaid, 'MAX_PONTOS_CIENCIA', '50',
     'Máximo de pontos que a ciência de um comunicado pode pagar (vale para o comunicado e para a tarefa Leitura de comunicado).')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

CREATE OR REPLACE FUNCTION public.valida_configuracao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_texto text := btrim(coalesce(NEW.valor, ''));
  v_num   numeric;
BEGIN
  IF NEW.chave = 'TAXA_CONVERSAO_PONTO_REAL' THEN
    BEGIN
      v_num := replace(v_texto, ',', '.')::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'A taxa precisa ser um número, como 0,03.' USING ERRCODE = 'check_violation';
    END;
    IF v_num IS NULL OR v_num <= 0 OR v_num > 10 THEN
      RAISE EXCEPTION 'A taxa precisa ser maior que zero e no máximo R$ 10 por ponto.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_num::text;

  ELSIF NEW.chave LIKE 'PONTOS_BONUS_%' OR NEW.chave = 'MAX_DIFERENCA_FOTO_SEGUNDOS' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro, sem vírgula.' USING ERRCODE = 'check_violation';
    END IF;
    v_num := CASE WHEN NEW.chave LIKE 'PONTOS_BONUS_%' THEN 10000 ELSE 86400 END;
    IF v_texto::numeric > v_num THEN
      RAISE EXCEPTION 'Valor alto demais para %.', NEW.chave USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  -- Prazo da foto: nunca menos de 90 dias (a política de uso promete um prazo,
  -- e um prazo curto demais apagaria prova de entrega ainda em discussão).
  ELSIF NEW.chave = 'DIAS_GUARDAR_FOTO_ENTREGA' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O prazo precisa ser um número inteiro de dias.' USING ERRCODE = 'check_violation';
    END IF;
    IF v_texto::integer < 90 OR v_texto::integer > 3650 THEN
      RAISE EXCEPTION 'O prazo precisa ser de 90 a 3650 dias.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  -- Rodizio no aceite: 0 desliga, e o teto de 2 horas evita travar a loja por
  -- engano ao digitar um numero grande.
  ELSIF NEW.chave = 'MINUTOS_RODIZIO_ACEITE' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer > 120 THEN
      RAISE EXCEPTION 'O tempo de espera precisa ser um número inteiro de 0 a 120 minutos (0 desliga).'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave = 'MINUTOS_TAREFA_PARADA' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer < 5 OR v_texto::integer > 480 THEN
      RAISE EXCEPTION 'O tempo precisa ser um número inteiro de 5 a 480 minutos.'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave LIKE 'HORARIO_%' THEN
    IF v_texto !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
      RAISE EXCEPTION 'O horário precisa estar no formato HH:MM, entre 00:00 e 23:59.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  -- O fuso tem de ser um fuso que o banco conhece: errar aqui erraria TODAS
  -- as liberacoes da conta, e em silencio.
  -- Só o horário de Brasília, por enquanto (decisão do Wisley, 27/09/2026):
  -- parte do sistema ainda usa São Paulo fixo, e oferecer outro fuso faria
  -- metade obedecer e metade não, sem ninguém avisar. Abrir outros fusos
  -- depende de converter as funções que faltam (ver a catraca da seção 68).
  ELSIF NEW.chave = 'FUSO_HORARIO' THEN
    IF v_texto <> 'America/Sao_Paulo' THEN
      RAISE EXCEPTION 'Por enquanto o STGame funciona só no horário de Brasília (America/Sao_Paulo). Outros fusos ainda não estão disponíveis.'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave = 'SOM_TAREFA_NOVA' THEN
    IF v_texto NOT IN ('0', '1') THEN
      RAISE EXCEPTION 'Use 1 para ligar o som e 0 para desligar.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave = 'SOM_VOLUME' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer > 100 THEN
      RAISE EXCEPTION 'O volume precisa ser um número inteiro de 0 a 100.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  -- Teto de pontos por ciência (29/09/2026): a ciência paga sem validação,
  -- então o teto é a proteção contra o engano de digitar um número grande.
  ELSIF NEW.chave = 'MAX_PONTOS_CIENCIA' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::numeric > 10000 THEN
      RAISE EXCEPTION 'O máximo de pontos por ciência precisa ser um número inteiro de 0 a 10000.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave = 'CONTATO_PRIVACIDADE' THEN
    IF length(v_texto) > 200 THEN
      RAISE EXCEPTION 'O contato pode ter no máximo 200 letras.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave LIKE 'TAREFA_%' THEN
    IF v_texto <> '' AND v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'ID de tarefa inválido.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.atualizadoem := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP FUNCTION IF EXISTS public.vinculos_da_tela();
CREATE OR REPLACE FUNCTION public.vinculos_da_tela()
RETURNS TABLE(funcionarioid integer, lojaid integer, ativo boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT fl.funcionarioid, fl.lojaid, fl.ativo
    FROM public.funcionarioslojas fl
   WHERE (public.sou_master() AND fl.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND fl.contaid = public.conta_do_gerente()
          AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('equipe.ver'))::integer[]))
   ORDER BY fl.funcionarioid, fl.lojaid
$$;

REVOKE ALL ON FUNCTION public.vinculos_da_tela() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.vinculos_da_tela() TO authenticated;

DROP FUNCTION IF EXISTS public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[], integer[]);
CREATE OR REPLACE FUNCTION public.salvar_pessoa(p_funcionarioid integer, p_nomecompleto text, p_cpf text, p_cargo text, p_setor text, p_telefone text, p_diadefolga integer, p_lojas integer[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta  integer := public.conta_do_gestor_editavel();
  v_lojas  integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_lojas, '{}'::integer[])) x ORDER BY 1);
  f        public.funcionarios%ROWTYPE;
  v_id     integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
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
      -- (decisão 4); e só as lojas dele mudam.
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
    END IF;
    UPDATE public.funcionarios
       SET nomecompleto = p_nomecompleto, cpf = p_cpf, cargo = p_cargo, setor = p_setor,
           telefonewhatsapp = p_telefone, diadefolga = p_diadefolga
     WHERE funcionarioid = v_id;
  END IF;

  -- As lojas, como a tela fazia: sair de uma loja é desativar o vínculo, nunca
  -- apagar (o histórico daquela loja aponta para ele).
  INSERT INTO public.funcionarioslojas (contaid, funcionarioid, lojaid, ativo)
  SELECT v_conta, v_id, l, true FROM unnest(v_lojas) l
  ON CONFLICT (funcionarioid, lojaid) DO UPDATE SET ativo = true;
  UPDATE public.funcionarioslojas SET ativo = false
   WHERE funcionarioid = v_id AND NOT (lojaid = ANY (v_lojas)) AND ativo;
  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_pessoa(integer, text, text, text, text, text, integer, integer[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Os dados e a estrutura (antes das funções: a tabela de vínculos leva o gatilho dela)
-- ---------------------------------------------------------------------------
-- As configurações que só o bot lia (silêncio, limite de mensagens, horários
-- dos lembretes...) FICAM: o histórico de quem mudou cada uma aponta para elas
-- (ON DELETE RESTRICT, de propósito). Ninguém mais as lê nem as mostra, e conta
-- nova não as recebe (cria_configuracoes_padrao, acima).
DROP TABLE IF EXISTS public.mensagensfila;
DROP TABLE IF EXISTS public.mensagensrotinas;
DROP TABLE IF EXISTS public.usomensagens;
DROP TABLE IF EXISTS public.telegramconvites;
DROP TABLE IF EXISTS public.telegramvinculos;
ALTER TABLE public.tarefasatribuidas DROP COLUMN IF EXISTS grupoid, DROP COLUMN IF EXISTS statustarefagrupo;
DROP TABLE IF EXISTS public.funcionariosgrupos;
DROP TABLE IF EXISTS public.grupos;
-- O controle técnico do bot (schema próprio): mensagens já tratadas, códigos
-- errados por chat, passo da conversa e empresa escolhida por chat. Também
-- guarda o identificador de Telegram (o chat): sai junto.
DROP TABLE IF EXISTS bot.updates;
DROP TABLE IF EXISTS bot.tentativas;
DROP TABLE IF EXISTS bot.estados;
DROP TABLE IF EXISTS bot.contaativa;
DROP SCHEMA IF EXISTS bot;
ALTER TABLE public.funcionarios DROP COLUMN IF EXISTS chatidtelegram;
ALTER TABLE public.funcionarioslojas DROP COLUMN IF EXISTS validador;
ALTER TABLE public.entregas DROP COLUMN IF EXISTS avisochatid, DROP COLUMN IF EXISTS fileidtelegram;
ALTER TABLE public.documentos DROP COLUMN IF EXISTS telegramfileidfoto;
ALTER TABLE public.notasfiscais DROP COLUMN IF EXISTS fileidtelegram;

-- ---------------------------------------------------------------------------
-- 4. As funções do Telegram (todas as versões de cada nome)
-- ---------------------------------------------------------------------------
DO $$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS assinatura FROM pg_proc p
            WHERE p.pronamespace = 'public'::regnamespace
              AND p.proname = ANY (ARRAY['bot_abertas_da_pessoa','bot_aviso_comunicado','bot_aviso_conquista','bot_aviso_entrega','bot_aviso_meta','bot_aviso_vinculo','bot_chat_da_pessoa','bot_chat_do_grupo','bot_ciencia','bot_ciencia_documento','bot_comanda','bot_comanda_iniciar','bot_conferir_foto','bot_consulta','bot_documento','bot_enfileirar','bot_enfileirar_ex','bot_entrar','bot_entrar_pessoa','bot_enviadas_hoje','bot_erro','bot_escolher_conta','bot_estado','bot_feedback','bot_fila_disparar','bot_fila_pegar','bot_fila_resultado','bot_grupo','bot_guardar_estado','bot_html','bot_iniciar_entrega','bot_janela','bot_lancar','bot_legenda_entrega','bot_limpar_estado','bot_lista_tarefas','bot_marcar_bloqueio','bot_nao_aplicavel','bot_nao_aplicavel_iniciar','bot_pegar_folga','bot_pegar_missao','bot_pendencias','bot_pessoa_do_chat','bot_pessoa_do_grupo','bot_quem','bot_recusa_guardar','bot_recusa_motivo','bot_recusa_pedir','bot_registrar_entrega','bot_registrar_update','bot_registrar_uso','bot_resgatar','bot_resumo_ausencia','bot_status_meta','bot_tarefas','bot_texto_grupo','bot_texto_juntado','bot_texto_rotina','bot_usar_convite','bot_validador','bot_validar','bot_visto','criar_convite_grupo','criar_convite_meu_telegram','criar_convite_telegram','definir_rotina_mensagem','desligar_telegram','no_silencio','rotina_ligada','rotina_ligada_pessoa','rotina_mensagens','telegram_hash','telegram_novo_codigo','usar_mensagens']) LOOP
    EXECUTE 'DROP FUNCTION ' || f.assinatura;
  END LOOP;
END $$;
