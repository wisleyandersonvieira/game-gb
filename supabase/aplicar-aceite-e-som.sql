-- =========================================================================
-- STGame — ninguém entrega sem aceitar antes, e o som de tarefa nova no
-- tablet.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929100700_aceite_obrigatorio_e_som.sql
--
-- O QUE MUDA PARA QUEM JÁ USA: as entregas que já existem continuam válidas —
-- esta mudança não olha para trás. Daqui para a frente, a equipe aceita no
-- tablet antes de entregar. O gestor continua registrando entrega pelo Quadro
-- sem aceite, como sempre.
-- =========================================================================

BEGIN;

-- Ninguém entrega sem aceitar antes, e o som de tarefa nova no tablet.
--
-- 1. ACEITE OBRIGATÓRIO (decisão do Wisley, 25/09/2026). Antes, entregar sem
--    ter pegado valia como aceite, e a tarefa de dono único nem passava pelo
--    aceite. Agora o caminho é sempre o mesmo, para toda tarefa: aceitar com o
--    PIN no tablet, depois entregar.
--
--    A regra mora AQUI, no banco, e não na tela: esconder o botão não resolve,
--    porque quem sabe mexer no navegador contorna. As duas portas por onde a
--    equipe entrega (`visao_entregar`, do tablet, e `eu_entregar`, do celular)
--    passaram a exigir o aceite. As duas só o servidor chama.
--
--    O QUE NÃO MUDA: o gestor continua registrando entrega pelo Quadro sem
--    aceite nenhum (`registrar_entrega` direto) — é outro ato, dele, e a regra
--    é sobre a equipe. As entregas que já existem no banco continuam válidas:
--    isto não olha para trás.
--
-- 2. SOM DE TAREFA NOVA, só no tablet. Duas configurações por conta, ligadas
--    por padrão. O celular da pessoa nunca recebe aviso — política da casa.

-- ---------------------------------------------------------------------------
-- 1. O tablet: aceite obrigatório
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100600), com o diff conferido.
CREATE OR REPLACE FUNCTION public.visao_entregar(p_contaid integer, p_lojaid integer,
                                                 p_funcionarioid integer, p_atribuicaoid integer,
                                                 p_caminho text, p_observacao text,
                                                 p_fotoidunico text DEFAULT NULL,
                                                 p_semhorafoto boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  m      public.tarefasatribuidas%ROWTYPE;
  v_hoje date := public.dia_em_sao_paulo(now());
  v_alvo integer;
  v_dono integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  -- Na fila de hoje E ja liberada.
  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(p_lojaid) f
                  WHERE f.atribuicaoid = p_atribuicaoid AND f.situacao <> 'feita' AND f.liberada) THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  -- NINGUEM ENTREGA SEM ACEITAR ANTES (regra do Wisley, 25/09/2026).
  --
  -- Antes: entregar sem ter pegado VALIA como aceite, e a tarefa de dono
  -- unico nem passava pelo aceite. Agora o caminho e sempre o mesmo, e vale
  -- para TODA tarefa: aceitar com o PIN, depois entregar.
  --
  -- A regra mora aqui, no banco, e nao na tela: esconder o botao nao resolve,
  -- porque quem sabe mexer no navegador contorna. Esta funcao so o servidor
  -- chama, e e por ela que passa toda entrega feita no tablet.
  SELECT novaatribuicaoid, funcionarioid INTO v_alvo, v_dono
    FROM public.missoesaceites
   WHERE contaid = p_contaid AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aceite a tarefa antes de entregar.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Quem aceitou e o unico que entrega. Ja valia para tarefa disputada;
  -- passa a valer para todas.
  IF v_dono <> p_funcionarioid THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Tarefa com dono unico nao gera copia: o aceite fica na propria atribuicao.
  v_alvo := coalesce(v_alvo, p_atribuicaoid);

  RETURN public.registrar_entrega(v_alvo, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

REVOKE ALL ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text, text, boolean)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 2. O celular: aceite obrigatório (feito no tablet)
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100600), com o diff conferido.
CREATE OR REPLACE FUNCTION public.eu_entregar(p_contaid integer, p_funcionarioid integer,
                                              p_atribuicaoid integer, p_caminho text,
                                              p_observacao text, p_fotoidunico text,
                                              p_semhorafoto boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_lojaid integer; v_hoje date := public.dia_em_sao_paulo(now());
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT ta.lojaid INTO v_lojaid
    FROM public.tarefasatribuidas ta
   WHERE ta.atribuicaoid = p_atribuicaoid AND ta.contaid = p_contaid
     AND ta.funcionarioid = p_funcionarioid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta tarefa não é sua.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, v_lojaid, 'colaborador');

  -- Na fila de hoje E ja liberada: antes da hora combinada nao se entrega,
  -- como nao se pega.
  IF NOT EXISTS (SELECT 1 FROM public.fila_da_loja(v_lojaid) f
                  WHERE (f.atribuicaoid = p_atribuicaoid OR f.entregarid = p_atribuicaoid)
                    AND f.situacao <> 'feita' AND f.liberada) THEN
    RAISE EXCEPTION 'Esta tarefa não está na fila de hoje.' USING ERRCODE = 'no_data_found';
  END IF;

  -- NINGUEM ENTREGA SEM ACEITAR ANTES. O aceite e sempre no TABLET da loja:
  -- o celular entrega o que ela ja assumiu com o PIN.
  --
  -- A atribuicao que chega aqui e a da PESSOA (a copia, quando a tarefa era
  -- disputada), entao o aceite pode estar nela mesma ou na atribuicao de
  -- origem.
  IF NOT EXISTS (
    SELECT 1 FROM public.missoesaceites a
     WHERE a.contaid = p_contaid AND a.dia = v_hoje AND a.revogadoem IS NULL
       AND a.funcionarioid = p_funcionarioid
       AND (a.novaatribuicaoid = p_atribuicaoid OR a.atribuicaoid = p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Aceite a tarefa no tablet da loja antes de entregar.'
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN public.registrar_entrega(p_atribuicaoid, p_observacao, p_caminho, false,
                                  p_fotoidunico, p_semhorafoto);
END;
$$;

REVOKE ALL ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_entregar(integer, integer, integer, text, text, text, boolean)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 3. As configurações do som do tablet
-- ---------------------------------------------------------------------------
-- As duas funções partem da versão mais recente (20260929100600), com o diff
-- conferido: entram só as duas chaves novas e a validação delas.
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
    (p_contaid, 'HORARIO_DELEGACAO_FOLGA',       '09:05', 'Hora da delegacao automatica das tarefas de quem esta de folga.'),
    (p_contaid, 'HORARIO_LEMBRETE_COMUNICADOS',  '09:00', 'Hora do lembrete de comunicados pendentes de leitura.'),
    (p_contaid, 'HORARIO_LEMBRETE_HOJE',         '08:00', 'Hora do lembrete dos agendamentos de hoje.'),
    (p_contaid, 'HORARIO_LEMBRETE_DIARIO_AMANHA','09:00', 'Hora do lembrete dos agendamentos de amanha.'),
    (p_contaid, 'HORARIO_LEMBRETE_SEMANAL',      '08:00', 'Hora do lembrete semanal de agendamentos.'),
    (p_contaid, 'HORARIO_SILENCIO_INICIO',       '22:00', 'A partir desta hora o bot não manda mensagem automática (não vale dentro do turno da pessoa).'),
    (p_contaid, 'HORARIO_SILENCIO_FIM',          '07:00', 'A partir desta hora o bot volta a mandar mensagem automática.'),
    (p_contaid, 'MAX_MENSAGENS_AUTOMATICAS_DIA', '8',     'Máximo de mensagens automáticas por pessoa por dia.'),
    (p_contaid, 'MAX_TAREFAS_FOLGA_POR_PESSOA',  '3',     'Máximo de tarefas de folga que uma pessoa pode pegar por dia pelo grupo.'),
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
    -- Som de tarefa nova. SO no tablet da loja: o celular da pessoa nunca
    -- recebe aviso, por politica.
    (p_contaid, 'SOM_TAREFA_NOVA', '1',  'Toca um som no tablet quando chega tarefa nova na fila. 1 liga, 0 desliga.'),
    (p_contaid, 'SOM_VOLUME',      '50', 'Volume do som do tablet, de 0 a 100.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

REVOKE EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) TO service_role;

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

  ELSIF NEW.chave IN ('MAX_MENSAGENS_AUTOMATICAS_DIA', 'MAX_TAREFAS_FOLGA_POR_PESSOA') THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer < 1 OR v_texto::integer > 50 THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro de 1 a 50.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave LIKE 'HORARIO_%' THEN
    IF v_texto !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
      RAISE EXCEPTION 'O horário precisa estar no formato HH:MM, entre 00:00 e 23:59.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  -- O fuso tem de ser um fuso que o banco conhece: errar aqui erraria TODAS
  -- as liberacoes da conta, e em silencio.
  ELSIF NEW.chave = 'FUSO_HORARIO' THEN
    IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = v_texto) THEN
      RAISE EXCEPTION 'Fuso horário desconhecido. Use, por exemplo, America/Sao_Paulo.'
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

-- As contas que JÁ EXISTEM recebem as chaves novas.
DO $backfill$
DECLARE c integer;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_configuracoes_padrao(c);
  END LOOP;
END $backfill$;

-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
BEGIN
  -- As duas portas da equipe têm de exigir o aceite.
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'visao_entregar') NOT LIKE '%Aceite a tarefa%' THEN
    RAISE EXCEPTION 'O tablet ainda entregaria sem aceite.';
  END IF;
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'eu_entregar') NOT LIKE '%Aceite a tarefa%' THEN
    RAISE EXCEPTION 'O celular ainda entregaria sem aceite.';
  END IF;

  -- E o tablet não pode mais criar o aceite sozinho na hora de entregar.
  IF (SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'visao_entregar') LIKE '%pegar_tarefa%' THEN
    RAISE EXCEPTION 'O tablet ainda cria o aceite ao entregar: a regra não valeria.';
  END IF;

  -- As configurações do som têm de chegar em TODA conta.
  IF EXISTS (SELECT 1 FROM public.contas c
              WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                                 WHERE g.contaid = c.contaid AND g.chave = 'SOM_TAREFA_NOVA')
                 OR NOT EXISTS (SELECT 1 FROM public.configuracoes g
                                 WHERE g.contaid = c.contaid AND g.chave = 'SOM_VOLUME')) THEN
    RAISE EXCEPTION 'A configuração do som não chegou em alguma conta.';
  END IF;

  RAISE NOTICE 'tudo certo: aceite obrigatório e som do tablet aplicados.';
END $verifica$;

COMMIT;
