-- =========================================================================
-- STGame — Teto de pontos por ciência; fotos "apagadas" só de verdade e a
-- Saúde das rotinas; agendamento que não perde a tarefa.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes (inclusive
-- aplicar-tarefas-comuns-e-atribuicoes.sql). Aplique ESTE ARQUIVO ANTES de
-- publicar a versão nova.
--
-- Este arquivo tem TRÊS migrações, nesta ordem:
--   20260929230000_teto_pontos_ciencia.sql
--   20260929231000_fotos_de_verdade_e_saude.sql
--   20260929232000_agenda_nao_perde_a_tarefa.sql
--
-- O QUE MUDA PARA QUEM JÁ USA:
--   * Comunicado (e tarefa "Leitura de comunicado") acima de 50 pontos por
--     ciência passa a ser recusado. O que já foi publicado não muda.
--   * FOTOS: foto vencida some de todas as telas e a entrega diz "sendo
--     apagada"; "removida" só depois de o arquivo sair de verdade. Ao
--     aplicar, toda foto vencida ainda guardada entra na fila e some na hora.
--     Das que diziam "removida" com o arquivo guardado, SÓ voltam a aparecer
--     as que ainda estão no prazo (se o prazo foi aumentado depois).
--     Provado: 500 entregas; vencida que aparece 0, "removida" falsa 0.
--   * Remarcar ou trocar o responsável recria a tarefa de atender que faltar.
--
-- ANTES de aplicar, para ver os dois grupos das que dizem "removida" com o
-- arquivo ainda guardado (só leitura; cole sozinho e rode):
--   SELECT CASE WHEN e.dataenvio < now() - make_interval(days => public.dias_guardar_foto(e.contaid))
--               THEN 'A) vencidas (vão ficar escondidas, sendo apagadas)'
--               ELSE 'B) dentro do prazo (vão voltar a aparecer)' END AS grupo,
--          count(*) AS entregas
--     FROM public.entregas e
--     JOIN public.fotosexpurgo f ON f.contaid = e.contaid AND f.entregaid = e.entregaid
--    WHERE e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL AND f.removidoem IS NULL
--    GROUP BY 1 ORDER BY 1;
-- E as vencidas que a rotina antiga nem marcou (vão sumir das telas ao aplicar):
--   SELECT count(*) FROM public.entregas e
--    WHERE e.pathfotoevidencia IS NOT NULL AND e.fotoexpiradaem IS NULL
--      AND e.dataenvio < now() - make_interval(days => public.dias_guardar_foto(e.contaid));
-- =========================================================================


BEGIN;

-- ======== 20260929230000_teto_pontos_ciencia.sql ========
-- Teto de pontos por ciência de comunicado (29/09/2026, aprovado pelo Wisley).
--
-- A ciência de um comunicado é o único ponto que sai sem ninguém aprovar.
-- Antes, o único limite era 10.000 por ciência (documentos_pontos_validos):
-- 1000 digitado por engano pagaria até 20.000 pontos por comunicado numa loja
-- de 20 pessoas. Agora:
--   * Configuração POR CONTA, MAX_PONTOS_CIENCIA, padrão 50 (0 a 10.000).
--     Quem muda é o master (alterar_configuracao já exige o master).
--   * Vale para o campo de pontos do comunicado (publicar e editar) e para a
--     tarefa "Leitura de comunicado" (que dá o padrão). Recusa no banco, com
--     mensagem que diz o máximo.
--   * Não mexe em nada já lançado: comunicados publicados e ciências pagas
--     ficam como estão. O teto só vale para o que se grava daqui em diante.

-- ---------------------------------------------------------------------------
-- 1. A configuração (padrão 50) e a validação dela
-- ---------------------------------------------------------------------------
-- Parte das versões mais recentes (cria_configuracoes_padrao em
-- 20260929120000_som_por_loja.sql; valida_configuracao em
-- 20260929150000_folha_de_acesso.sql), com o diff conferido: só a chave nova.
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

-- As contas que já existem ganham a chave (com o padrão 50).
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_configuracoes_padrao(c.contaid);
  END LOOP;
END $$;

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

-- O teto de uma conta. Interna: recebe a conta, então ninguém de fora chama.
CREATE OR REPLACE FUNCTION public.teto_pontos_ciencia(p_contaid integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                    WHERE contaid = p_contaid AND chave = 'MAX_PONTOS_CIENCIA'), 50)
$$;
REVOKE ALL ON FUNCTION public.teto_pontos_ciencia(integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Comunicado: publicar e editar respeitam o teto
-- ---------------------------------------------------------------------------
-- publicar_comunicado parte da versão mais recente
-- (20260929220000_tarefas_comuns_e_atribuicoes.sql); editar_comunicado, de
-- 20260922400000_rh_comunicados_documentos_onboarding.sql. Diff conferido:
-- só a recusa acima do teto.
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
  -- Teto da conta (29/09/2026). Só vale para o que se grava agora.
  IF p_pontos > public.teto_pontos_ciencia(v_conta) THEN
    RAISE EXCEPTION '% pontos por ciência passa do máximo permitido nesta conta (% pontos). Diminua os pontos, ou mude o máximo em Configurações.',
      p_pontos, public.teto_pontos_ciencia(v_conta) USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.documentos SET titulo = btrim(p_titulo), conteudo = btrim(p_conteudo), pontosporciencia = p_pontos
   WHERE documentoid = p_documentoid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. A tarefa "Leitura de comunicado" também respeita o teto
-- ---------------------------------------------------------------------------
-- Achada pelo código (sistema = 'leitura'). Só confere quando os pontos
-- MUDAM: baixar o teto não trava a edição do nome de uma tarefa que já está
-- acima dele (o comunicado publicado com o campo em branco é que é recusado,
-- com a mensagem dizendo o porquê).
CREATE OR REPLACE FUNCTION public.teto_na_tarefa_de_leitura()
RETURNS trigger
LANGUAGE plpgsql
-- Roda como dono: o teto é lido por uma função interna, sem permissão para o
-- usuário logado.
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_teto integer;
BEGIN
  IF NEW.sistema IS DISTINCT FROM 'leitura' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.pontos IS NOT DISTINCT FROM OLD.pontos THEN
    RETURN NEW;
  END IF;
  v_teto := public.teto_pontos_ciencia(NEW.contaid);
  IF NEW.pontos > v_teto THEN
    RAISE EXCEPTION 'A "Leitura de comunicado" paga sozinha, sem validação: o máximo permitido nesta conta é % pontos (Configurações).', v_teto
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.teto_na_tarefa_de_leitura() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS tarefas_teto_da_leitura ON public.tarefas;
CREATE TRIGGER tarefas_teto_da_leitura
  BEFORE INSERT OR UPDATE OF pontos ON public.tarefas
  FOR EACH ROW EXECUTE FUNCTION public.teto_na_tarefa_de_leitura();


-- ======== 20260929231000_fotos_de_verdade_e_saude.sql ========
-- Fotos: "apagada" só depois de sair de verdade; e a Saúde confere as
-- rotinas (29/09/2026, pedidos do Wisley).
--
-- 1. FOTOS. A política de uso diz que a foto é apagada depois do prazo. A
--    rotina marcava a entrega como "foto removida" ANTES de o arquivo sair;
--    se a remoção (Edge Function, via pg_net + Vault) nunca rodava, ficava
--    gravado "apagada" para uma foto que continuava guardada. Agora há TRÊS
--    estados, e cada um diz a verdade:
--      * no prazo: a foto aparece;
--      * vencida, na fila (entregas.fotoaguardaremocaoem): a foto NÃO aparece
--        em tela nenhuma — a política promete que ela some depois do prazo —
--        e a entrega diz "foto vencida, sendo apagada";
--      * removida (entregas.fotoexpiradaem): só depois de a Edge Function
--        confirmar que o arquivo saiu.
--    Fila parada (presa em 5 tentativas, ou esperando há mais de 2 dias) vira
--    aviso e erro na aba Rotinas.
--    As entregas que diziam "removida" com o arquivo ainda guardado:
--      * vencidas (o caso normal: a rotina antiga só marcava vencidas) passam
--        a "sendo apagada" — continuam escondidas e o arquivo continua na fila;
--      * dentro do prazo (só se o prazo foi AUMENTADO depois da marcação)
--        voltam a mostrar a foto e saem da fila.
-- 2. SAÚDE. A /saude passa a conferir o que as rotinas precisam para rodar:
--    os segredos do cofre (só se existem, nunca o valor), o agendamento
--    automático (pg_cron) e as mensagens que falharam; e mostra as fotos
--    vencidas ainda guardadas, quantas e há quantos dias.

-- ---------------------------------------------------------------------------
-- 1. O estado "vencida, sendo apagada"
-- ---------------------------------------------------------------------------
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS fotoaguardaremocaoem timestamptz;
COMMENT ON COLUMN public.entregas.fotoaguardaremocaoem IS
  'Quando a foto passou do prazo e o arquivo entrou na fila para ser apagado. Daí em diante a foto não aparece em tela nenhuma; fotoexpiradaem só é gravado quando o arquivo sai de verdade.';

-- ---------------------------------------------------------------------------
-- 1a. A rotina enfileira e esconde; não diz "removida"
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260927100800_pin_tablet_e_expurgo.sql),
-- com o diff conferido.
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
  v_atraso integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    -- Já fez o trabalho do dia: com "ok", ou com o aviso de fila parada (que
    -- tem os números). Erro inesperado (sem números) tenta de novo.
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje
                  AND (resultado = 'ok' OR detalhe ? 'enfileiradas')) THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    -- 29/09/2026: a rotina só PÕE NA FILA o arquivo vencido. A entrega NÃO
    -- é marcada aqui: "foto removida" só é gravado quando o arquivo sai de
    -- verdade (expurgo_resultado). Antes, a entrega era marcada antes, e uma
    -- remoção que nunca rodava deixava gravado "apagada" para foto que
    -- continuava guardada.
    -- Fica de fora o arquivo que ainda serve a uma entrega DENTRO do prazo
    -- (apagá-lo levaria a foto dela junto) e o que já está na fila.
    INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
    SELECT p_contaid, e.entregaid, e.pathfotoevidencia
      FROM public.entregas e
     WHERE e.contaid = p_contaid
       AND e.pathfotoevidencia IS NOT NULL
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias)
       AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                        WHERE f.contaid = p_contaid AND f.caminho = e.pathfotoevidencia)
       AND NOT EXISTS (SELECT 1 FROM public.entregas r
                        WHERE r.contaid = p_contaid AND r.pathfotoevidencia = e.pathfotoevidencia
                          AND r.dataenvio >= p_agora - make_interval(days => v_dias))
     ORDER BY e.dataenvio
     LIMIT 2000
    ON CONFLICT (contaid, caminho) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Na fila = vencida: some das telas (a política promete), sem dizer
    -- "removida". Todas as entregas que usam o arquivo estão vencidas: o
    -- arquivo que ainda serve a uma no prazo não entra na fila.
    UPDATE public.entregas e
       SET fotoaguardaremocaoem = p_agora
      FROM public.fotosexpurgo f
     WHERE f.contaid = p_contaid AND f.removidoem IS NULL
       AND e.contaid = p_contaid AND e.pathfotoevidencia = f.caminho
       AND e.fotoaguardaremocaoem IS NULL AND e.fotoexpiradaem IS NULL;

    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    -- Remoção que não acontece não fica calada: presa (5 tentativas) ou
    -- atrasada (na fila há mais de 2 dias, sinal de que a remoção nem roda).
    SELECT count(*) FILTER (WHERE tentativas >= 5),
           coalesce(max(extract(day FROM p_agora - criadoem))::integer, 0)
      INTO v_presas, v_atraso
      FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL;
    IF v_presas > 0 OR v_atraso > 2 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso', left(
               'Fotos vencidas continuam guardadas: ' ||
               (SELECT count(*) FROM public.fotosexpurgo WHERE contaid = p_contaid AND removidoem IS NULL) ||
               ' esperando para sair, a mais antiga há ' || v_atraso || ' dia(s)' ||
               CASE WHEN v_presas > 0 THEN ', ' || v_presas || ' com a remoção falhando 5 vezes' ELSE '' END ||
               '. Veja a Saúde do sistema.', 300)
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('enfileiradas', v_n, 'dias', v_dias, 'presas', v_presas, 'atraso', v_atraso),
                                      'fotos vencidas continuam no armazenamento');
      RETURN jsonb_build_object('enfileiradas', v_n, 'dias', v_dias, 'presas', v_presas, 'atraso', v_atraso);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('enfileiradas', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('enfileiradas', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1b. "Foto removida" só quando o arquivo saiu
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260927100100_expurgo_fotos_entrega.sql),
-- com o diff conferido.
CREATE OR REPLACE FUNCTION public.expurgo_resultado(p_ids integer[], p_erro text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra o resultado do expurgo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_erro IS NULL THEN
    -- O arquivo saiu de verdade: SÓ AGORA a entrega diz "foto removida"
    -- (29/09/2026). Todas as entregas que apontavam para o arquivo — que só
    -- entrou na fila porque nenhuma delas estava mais no prazo.
    WITH saiu AS (
      UPDATE public.fotosexpurgo SET removidoem = now(), erro = NULL
       WHERE expurgoid = ANY (p_ids) AND removidoem IS NULL
      RETURNING contaid, caminho, removidoem
    )
    UPDATE public.entregas e
       SET fotoexpiradaem = s.removidoem, pathfotoevidencia = NULL
      FROM saiu s
     WHERE e.contaid = s.contaid AND e.pathfotoevidencia = s.caminho;
  ELSE
    UPDATE public.fotosexpurgo SET erro = left(p_erro, 500)
     WHERE expurgoid = ANY (p_ids) AND removidoem IS NULL;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1c. Consertar o que já está gravado errado
-- ---------------------------------------------------------------------------
-- Entrega marcada "removida" cujo arquivo NÃO saiu (continua na fila). Roda
-- de novo sem efeito.
-- (a) Dentro do prazo de hoje (só acontece se o prazo foi aumentado depois
--     da marcação): a foto volta a aparecer e o arquivo SAI da fila.
WITH no_prazo AS (
  UPDATE public.entregas e
     SET pathfotoevidencia = f.caminho, fotoexpiradaem = NULL, fotoaguardaremocaoem = NULL
    FROM public.fotosexpurgo f
   WHERE f.contaid = e.contaid AND f.entregaid = e.entregaid
     AND f.removidoem IS NULL
     AND e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL
     AND e.dataenvio >= now() - make_interval(days => public.dias_guardar_foto(e.contaid))
  RETURNING f.expurgoid
)
DELETE FROM public.fotosexpurgo WHERE expurgoid IN (SELECT expurgoid FROM no_prazo);
-- (b) Vencida (o caso normal): continua escondida e na fila, e passa a dizer
--     a verdade — "sendo apagada", não "removida".
UPDATE public.entregas e
   SET pathfotoevidencia = f.caminho, fotoexpiradaem = NULL, fotoaguardaremocaoem = f.criadoem
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.entregaid = e.entregaid
   AND f.removidoem IS NULL
   AND e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL;

-- (c) Toda foto que JÁ passou do prazo e ainda não estava na fila entra
--     nela agora, e some das telas na hora — sem esperar a rotina da
--     madrugada (a política promete que ela some depois do prazo). As mesmas
--     regras da rotina: nunca o arquivo que ainda serve a uma entrega no
--     prazo.
INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
SELECT DISTINCT ON (e.contaid, e.pathfotoevidencia) e.contaid, e.entregaid, e.pathfotoevidencia
  FROM public.entregas e
 WHERE e.pathfotoevidencia IS NOT NULL AND e.fotoexpiradaem IS NULL
   AND e.dataenvio < now() - make_interval(days => public.dias_guardar_foto(e.contaid))
   AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                    WHERE f.contaid = e.contaid AND f.caminho = e.pathfotoevidencia)
   AND NOT EXISTS (SELECT 1 FROM public.entregas r
                    WHERE r.contaid = e.contaid AND r.pathfotoevidencia = e.pathfotoevidencia
                      AND r.dataenvio >= now() - make_interval(days => public.dias_guardar_foto(e.contaid)))
 ORDER BY e.contaid, e.pathfotoevidencia, e.dataenvio
ON CONFLICT (contaid, caminho) DO NOTHING;
UPDATE public.entregas e
   SET fotoaguardaremocaoem = now()
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.removidoem IS NULL AND e.pathfotoevidencia = f.caminho
   AND e.fotoaguardaremocaoem IS NULL AND e.fotoexpiradaem IS NULL;
-- E pede a remoção já (sem cofre/pg_net, como no teste, não faz nada; a
-- Saúde mostra).
SELECT public.fotos_expurgo_disparar();

-- ---------------------------------------------------------------------------
-- 1d. O Quadro não mostra foto vencida
-- ---------------------------------------------------------------------------
-- A única tela que mostra a foto da entrega. Parte da versão mais recente
-- (20260929200000_quadro_e_intervalo.sql), com o diff conferido: a foto na
-- fila para apagar sai sem caminho, e vem o estado "sendo apagada".
CREATE OR REPLACE FUNCTION public.quadro_validacao(p_lojaid integer, p_de date DEFAULT NULL,
                                                   p_ate date DEFAULT NULL, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_dia   jsonb   := public.meu_hoje();
  v_hoje  date    := (v_dia->>'hoje')::date;
  v_fuso  text    := v_dia->>'fuso';
  v_ate   date    := coalesce(p_ate, (v_dia->>'hoje')::date - 1);
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  v_de := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 -- Foto vencida (na fila para apagar) não aparece (29/09/2026).
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

  -- O histórico não leva "sem hora da foto": a decisão já foi tomada.
  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio DESC, x.entregaid DESC), '[]'::jsonb), count(*)
    INTO v_hist, v_n
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.dataaprovacao,
                 e.datarecusa, e.dataestorno, e.pontosganhos, e.observacao, e.motivorecusa, e.motivoestorno,
                 CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    -- Pediu 51 para saber se tem mais; devolve 50.
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2a. Fotos vencidas ainda guardadas, de uma conta (interna)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fotos_vencidas_da_conta(p_contaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH d AS (SELECT public.dias_guardar_foto(p_contaid) AS dias),
  v AS (
    SELECT e.dataenvio FROM public.entregas e, d
     WHERE e.contaid = p_contaid AND e.pathfotoevidencia IS NOT NULL AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < now() - make_interval(days => d.dias)
  )
  SELECT jsonb_build_object(
    'vencidas', (SELECT count(*) FROM v),
    -- Há quantos dias a mais antiga passou do prazo.
    'diasdeatraso', coalesce((SELECT extract(day FROM now() - min(v.dataenvio) - make_interval(days => d.dias))::integer
                                FROM v, d GROUP BY d.dias), 0),
    'presas', (SELECT count(*) FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas >= 5))
$$;
REVOKE ALL ON FUNCTION public.fotos_vencidas_da_conta(integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2b. A saúde da MINHA conta (qualquer um logado nela; a conta sai do login)
-- ---------------------------------------------------------------------------
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
    'mensagensfalhadas', (SELECT count(*) FROM public.mensagensfila
                           WHERE contaid = v_conta AND status = 'falhou' AND criadoem >= now() - interval '24 hours'));
END;
$$;
REVOKE ALL ON FUNCTION public.saude_da_minha_conta() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.saude_da_minha_conta() TO authenticated;

-- ---------------------------------------------------------------------------
-- 2c. A saúde da PLATAFORMA (só o servidor chama, para a /saude)
-- ---------------------------------------------------------------------------
-- Cofre: diz só SE cada segredo existe, nunca o valor. Agendamento: os jobs
-- que as rotinas precisam, se estão ativos, e a última execução. Números
-- somados de todas as contas: a tela só mostra ao admin geral (ou com a
-- chave da Saúde).
CREATE OR REPLACE FUNCTION public.saude_das_rotinas()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_segredos jsonb := '{}'::jsonb;
  v_jobs     jsonb := '[]'::jsonb;
  v_nome     text;
  v_existe   boolean;
  v_fotos    jsonb;
BEGIN
  IF to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
    FOREACH v_nome IN ARRAY ARRAY['stgame_funcoes_url', 'stgame_fila_segredo', 'stgame_expurgo_segredo'] LOOP
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = $1 AND coalesce(decrypted_secret, '''') <> '''')'
        INTO v_existe USING v_nome;
      v_segredos := v_segredos || jsonb_build_object(v_nome, v_existe);
    END LOOP;
  END IF;

  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE $q$
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'nome', n.nome,
               'existe', j.jobid IS NOT NULL,
               'ativo', coalesce(j.active, false),
               'ultimaexecucao', r.end_time,
               'ultimostatus', r.status) ORDER BY n.nome), '[]'::jsonb)
        FROM unnest(ARRAY['gamegb-rotinas', 'stgame-telegram-fila']) n(nome)
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

  RETURN jsonb_build_object(
    'cofre', to_regclass('vault.decrypted_secrets') IS NOT NULL,
    'pgnet', to_regproc('net.http_post') IS NOT NULL,
    'segredos', v_segredos,
    'agendador', to_regclass('cron.job') IS NOT NULL,
    'jobs', v_jobs,
    'mensagensfalhadas', (SELECT count(*) FROM public.mensagensfila
                           WHERE status = 'falhou' AND criadoem >= now() - interval '24 hours'),
    'fotos', v_fotos);
END;
$$;
REVOKE ALL ON FUNCTION public.saude_das_rotinas() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.saude_das_rotinas() TO service_role;


-- ======== 20260929232000_agenda_nao_perde_a_tarefa.sql ========
-- Agendamento que não perde a tarefa de atender (29/09/2026, pedido do Wisley).
--
-- A tarefa "Atender agendamento" do responsável podia sumir da lista do dia,
-- sem aviso, em três casos da operação normal:
--   * o responsável saiu da loja (ou foi desligado) depois de marcado;
--   * a tarefa "Atender agendamento" foi desativada depois de marcado;
--   * o agendamento nasceu sem a tarefa — e remarcar ou trocar o
--     responsável não a recriava.
-- Agora:
--   * remarcar e trocar o responsável RECRIAM a tarefa que faltar (se a
--     tarefa modelo estiver ativa e o responsável trabalhar na loja);
--   * agendamentos_sem_tarefa lista, para a Agenda, os agendamentos futuros
--     cuja tarefa não vai aparecer, com o motivo de cada um;
--   * recriar_tarefa_do_agendamento é o botão "Recriar tarefa" da Agenda.

-- ---------------------------------------------------------------------------
-- 1. Garantir a tarefa de um agendamento (interna)
-- ---------------------------------------------------------------------------
-- Devolve true se a tarefa existe (ou foi recriada). Não recria com a tarefa
-- modelo desativada (vira aviso, como em criar_agendamento), nem com o
-- responsável fora da loja (aí a saída é trocar o responsável).
CREATE OR REPLACE FUNCTION public.garantir_tarefa_do_agendamento(p_agendamentoid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE; v_modelo integer;
BEGIN
  SELECT * INTO a FROM public.agendamentos WHERE agendamentoid = p_agendamentoid;
  IF NOT FOUND OR a.statusagendamento <> 'Confirmado' THEN
    RETURN false;
  END IF;
  -- Já tem tarefa em aberto, ou a tarefa já foi entregue: nada a fazer.
  IF EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
              WHERE ta.agendamentoid = a.agendamentoid
                AND (ta.datafimvigencia IS NULL OR public.tarefa_da_agenda_entregue(ta.atribuicaoid))) THEN
    RETURN true;
  END IF;
  SELECT tarefaid INTO v_modelo FROM public.tarefas
   WHERE contaid = a.contaid AND sistema = 'modelo_agendamento' AND ativa;
  IF v_modelo IS NULL THEN
    INSERT INTO public.avisossistema (contaid, tipo, texto)
    VALUES (a.contaid, 'rotina_sem_tarefa', left(
      'Agenda: o agendamento de ' || a.nomecliente || ' (' ||
      to_char(a.dataevento AT TIME ZONE public.fuso_da_conta(a.contaid), 'DD/MM/YYYY HH24:MI') ||
      ') continua SEM a tarefa de atender, porque a tarefa "Atender agendamento" está desativada ou foi apagada. Reative-a no Catálogo de tarefas.', 300));
    RETURN false;
  END IF;
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, a.funcionarioid) THEN
    RETURN false;
  END IF;
  PERFORM set_config('gamegb.agenda', 'sim', true);
  INSERT INTO public.tarefasatribuidas (contaid, tarefaid, funcionarioid, lojaid, tipofrequencia, dataagendamento,
                                        descricaooverride, agendamentoid)
  VALUES (a.contaid, v_modelo, a.funcionarioid, a.lojaid, 'Unica', a.dataevento,
          public.texto_da_tarefa_agenda(a.dataevento, a.tipoevento), a.agendamentoid);
  PERFORM set_config('gamegb.agenda', '', true);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garantir_tarefa_do_agendamento(integer) FROM public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Remarcar e trocar o responsável recriam a tarefa que faltar
-- ---------------------------------------------------------------------------
-- Partem das versões mais recentes (20260922300000_agenda.sql), com o diff
-- conferido: só a chamada a garantir_tarefa_do_agendamento.
CREATE OR REPLACE FUNCTION public.remarcar_agendamento(p_agendamentoid integer, p_novadata timestamptz, p_motivo text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE; t record;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para remarcar agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_novadata IS NULL OR public.dia_em_sao_paulo(p_novadata) < public.dia_em_sao_paulo(now()) THEN
    RAISE EXCEPTION 'A nova data não pode estar no passado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_novadata = a.dataevento THEN
    RETURN;
  END IF;

  UPDATE public.agendamentos SET dataevento = p_novadata WHERE agendamentoid = a.agendamentoid;

  -- A tarefa vai junto, se ainda nao foi entregue.
  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas
         SET dataagendamento = p_novadata,
             descricaooverride = public.texto_da_tarefa_agenda(p_novadata, a.tipoevento)
       WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);
  -- Sem tarefa (criado sem ela, ou ela sumiu): recria, se der (29/09/2026).
  PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'remarcado',
    to_char(a.dataevento AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    to_char(p_novadata AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), p_motivo);
END;
$$;

CREATE OR REPLACE FUNCTION public.trocar_responsavel_agendamento(p_agendamentoid integer, p_funcionarioid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE; t record; v_antes text; v_depois text;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF a.statusagendamento <> 'Confirmado' THEN
    RAISE EXCEPTION 'Só dá para trocar o responsável de agendamento confirmado.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_funcionarioid = a.funcionarioid THEN
    -- Mesma pessoa: nada muda, mas a tarefa que faltar é recriada.
    PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);
    RETURN;
  END IF;
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, p_funcionarioid) THEN
    RAISE EXCEPTION 'O responsável precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;
  SELECT nomecompleto INTO v_antes FROM public.funcionarios WHERE funcionarioid = a.funcionarioid;
  SELECT nomecompleto INTO v_depois FROM public.funcionarios WHERE funcionarioid = p_funcionarioid;

  UPDATE public.agendamentos SET funcionarioid = p_funcionarioid WHERE agendamentoid = a.agendamentoid;

  PERFORM set_config('gamegb.agenda', 'sim', true);
  FOR t IN SELECT atribuicaoid FROM public.tarefasatribuidas
            WHERE agendamentoid = a.agendamentoid AND datafimvigencia IS NULL LOOP
    IF NOT public.tarefa_da_agenda_entregue(t.atribuicaoid) THEN
      UPDATE public.tarefasatribuidas SET funcionarioid = p_funcionarioid WHERE atribuicaoid = t.atribuicaoid;
    END IF;
  END LOOP;
  PERFORM set_config('gamegb.agenda', '', true);
  -- Sem tarefa (criado sem ela, ou ela sumiu): recria, já com o novo
  -- responsável (29/09/2026).
  PERFORM public.garantir_tarefa_do_agendamento(a.agendamentoid);

  PERFORM public.registra_agenda(a.contaid, a.lojaid, a.agendamentoid, 'responsavel', v_antes, v_depois, NULL);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. O botão "Recriar tarefa" da Agenda
-- ---------------------------------------------------------------------------
-- A conta sai do login (agendamento_para_mudar confere que o agendamento é
-- da conta de quem pede e que a conta pode alterar dados).
CREATE OR REPLACE FUNCTION public.recriar_tarefa_do_agendamento(p_agendamentoid integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE a public.agendamentos%ROWTYPE;
BEGIN
  a := public.agendamento_para_mudar(p_agendamentoid);
  IF NOT public.responsavel_valido(a.contaid, a.lojaid, a.funcionarioid) THEN
    RAISE EXCEPTION 'O responsável deste agendamento não trabalha mais na loja: troque o responsável (a tarefa é recriada junto).'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tarefas WHERE contaid = a.contaid AND sistema = 'modelo_agendamento' AND ativa) THEN
    RAISE EXCEPTION 'A tarefa "Atender agendamento" está desativada ou foi apagada: reative-a no Catálogo de tarefas.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN public.garantir_tarefa_do_agendamento(a.agendamentoid);
END;
$$;
REVOKE ALL ON FUNCTION public.recriar_tarefa_do_agendamento(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.recriar_tarefa_do_agendamento(integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Quais agendamentos futuros estão sem tarefa, e por quê
-- ---------------------------------------------------------------------------
-- SECURITY INVOKER: cada conta só enxerga os dela. Motivos:
--   'sem_tarefa'        — não há tarefa em aberto (nem entregue);
--   'tarefa_desativada' — há, mas "Atender agendamento" está desativada;
--   'responsavel_fora'  — há, mas o responsável não trabalha mais na loja.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa(p_lojaid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH dia AS (SELECT (public.meu_hoje()->>'hoje')::date AS hoje, public.meu_hoje()->>'fuso' AS fuso),
  futuros AS (
    SELECT a.*, dia.fuso FROM public.agendamentos a, dia
     WHERE a.lojaid = p_lojaid AND a.statusagendamento = 'Confirmado'
       AND (a.dataevento AT TIME ZONE dia.fuso)::date >= dia.hoje
  ),
  situacao AS (
    SELECT f.*,
           ta.atribuicaoid,
           ta.datafimvigencia AS datafimvigencia_ta,
           EXISTS (SELECT 1 FROM public.entregas e
                    WHERE e.atribuicaoid = ta.atribuicaoid AND e.statusvalidacao IN ('Pendente', 'Aprovada')) AS entregue,
           t.ativa AS tarefaativa,
           EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                     JOIN public.funcionarios fu ON fu.contaid = fl.contaid AND fu.funcionarioid = fl.funcionarioid
                    WHERE fl.lojaid = f.lojaid AND fl.funcionarioid = ta.funcionarioid AND fl.ativo AND fu.ativo) AS respnaloja
      FROM futuros f
      -- A última tarefa do agendamento, em aberto ou não (a entregue e
      -- encerrada não é problema).
      LEFT JOIN LATERAL (SELECT x.* FROM public.tarefasatribuidas x
                          WHERE x.agendamentoid = f.agendamentoid
                          ORDER BY x.atribuicaoid DESC LIMIT 1) ta ON true
      LEFT JOIN public.tarefas t ON t.contaid = ta.contaid AND t.tarefaid = ta.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'agendamentoid', s.agendamentoid,
           'quando', to_char(s.dataevento AT TIME ZONE s.fuso, 'DD/MM/YYYY HH24:MI'),
           'cliente', s.nomecliente,
           'responsavel', (SELECT nomecompleto FROM public.funcionarios WHERE funcionarioid = s.funcionarioid),
           'motivo', CASE WHEN s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL THEN 'sem_tarefa'
                          WHEN NOT s.tarefaativa THEN 'tarefa_desativada'
                          ELSE 'responsavel_fora' END)
         ORDER BY s.dataevento), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
$$;
REVOKE ALL ON FUNCTION public.agendamentos_sem_tarefa(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.agendamentos_sem_tarefa(integer) TO authenticated;

COMMIT;
