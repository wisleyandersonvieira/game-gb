-- =========================================================================
-- STGame — Etapa 1.12, parte B2: pedidos pelo tablet da loja.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929100900_pedido_no_tablet.sql
--
-- O QUE MUDA PARA QUEM JÁ USA: nada nos pedidos que já existem. A coluna nova
-- da observação nasce vazia neles, e a categoria deles continua onde está — a
-- tela do gestor segue mostrando.
-- =========================================================================

BEGIN;

-- Etapa 1.12, parte B2 — o primeiro item do menu do tablet: SOLICITAÇÕES.
--
-- A equipe abre pedido de compra ou de manutenção pelo tablet do balcão,
-- assinando com o PIN. O pedido cai na tela de Solicitações do gestor como
-- qualquer outro, em "Aberta".
--
-- QUEM PEDIU E EM QUE LOJA SAI DAQUI, e não da tela: a conta e a loja vêm do
-- tablet pareado, e a pessoa vem do PIN que o servidor conferiu. O navegador
-- não escolhe nada disso — é a mesma regra do pegar e do entregar.
--
-- A CATEGORIA fica vazia: o tablet não pergunta Limpeza/Cozinha/Escritório. A
-- coluna já aceitava vazio, então NADA muda nos pedidos antigos — eles seguem
-- com a categoria que têm, e a tela do gestor continua mostrando.

-- ---------------------------------------------------------------------------
-- 0. A observação do pedido
-- ---------------------------------------------------------------------------
-- Coluna nova, vazia em tudo o que já existe: nada muda nos pedidos antigos.
-- Até aqui a observação só existia no histórico do gestor; o tablet precisa
-- de um lugar para o que a pessoa escreve junto do pedido.
ALTER TABLE public.solicitacoesinternas
  ADD COLUMN IF NOT EXISTS observacao text;

COMMENT ON COLUMN public.solicitacoesinternas.observacao IS
  'O que a pessoa escreveu junto do pedido. Vazio nos pedidos anteriores a 25/09/2026.';

-- ---------------------------------------------------------------------------
-- 1. Quantos pedidos uma loja abre por hora
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100700), com o diff conferido.
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
    (p_contaid, 'SOM_VOLUME',      '50', 'Volume do som do tablet, de 0 a 100.'),
    -- Cuidado com o dia do gestor, nao trava de seguranca.
    (p_contaid, 'MAX_PEDIDOS_LOJA_HORA', '10',
     'Quantos pedidos a mesma loja pode abrir pelo tablet em uma hora.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

REVOKE EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cria_configuracoes_padrao(integer) TO service_role;

DO $backfill$
DECLARE c integer;
BEGIN
  FOR c IN SELECT contaid FROM public.contas LOOP
    PERFORM public.cria_configuracoes_padrao(c);
  END LOOP;
END $backfill$;

-- ---------------------------------------------------------------------------
-- 2. O pedido feito no tablet
-- ---------------------------------------------------------------------------
-- Recebe conta e loja, então NUNCA é liberada para quem está logado (regra da
-- Etapa 1.6): só o servidor a chama, depois de conferir o PIN.
CREATE OR REPLACE FUNCTION public.visao_abrir_pedido(
  p_contaid       integer,
  p_lojaid        integer,
  p_funcionarioid integer,
  p_tipo          text,
  p_descricao     text,
  p_quantidade    numeric DEFAULT NULL,
  p_unidade       text    DEFAULT NULL,
  p_observacao    text    DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id    integer;
  v_desc  text    := btrim(coalesce(p_descricao, ''));
  v_obs   text    := nullif(btrim(coalesce(p_observacao, '')), '');
  v_max   integer;
  v_feitos integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre pedido pelo tablet.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_tipo NOT IN ('Compra', 'Manutencao') THEN
    RAISE EXCEPTION 'Escolha Compra ou Manutenção.' USING ERRCODE = 'check_violation';
  END IF;

  -- A loja tem de ser da conta e estar ativa.
  IF NOT EXISTS (SELECT 1 FROM public.lojas
                  WHERE lojaid = p_lojaid AND contaid = p_contaid AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  -- QUEM PEDE tem de ser gente ativa DESTA loja. É o que impede gravar pedido
  -- no nome de outra pessoa ou em outra loja, mesmo chamando esta função
  -- direto, sem passar pela tela.
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl
                     ON fl.funcionarioid = f.funcionarioid AND fl.contaid = p_contaid AND fl.ativo
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = p_contaid AND f.ativo
                    AND fl.lojaid = p_lojaid) THEN
    RAISE EXCEPTION 'Quem pede precisa trabalhar nesta loja.' USING ERRCODE = 'check_violation';
  END IF;

  -- Obrigatório: o item (compra) ou a descrição (manutenção).
  IF length(v_desc) = 0 THEN
    RAISE EXCEPTION 'Escreva o que você precisa.' USING ERRCODE = 'check_violation';
  END IF;
  IF length(v_desc) > 500 THEN
    RAISE EXCEPTION 'Use no máximo 500 letras.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_obs IS NOT NULL AND length(v_obs) > 500 THEN
    RAISE EXCEPTION 'A observação pode ter no máximo 500 letras.' USING ERRCODE = 'check_violation';
  END IF;

  -- Quantidade só na compra, e só número maior que zero.
  IF p_tipo = 'Compra' THEN
    IF p_quantidade IS NULL OR p_quantidade <= 0 THEN
      RAISE EXCEPTION 'A quantidade precisa ser maior que zero.' USING ERRCODE = 'check_violation';
    END IF;
    IF p_quantidade > 100000 THEN
      RAISE EXCEPTION 'Quantidade alta demais. Confira o número.' USING ERRCODE = 'check_violation';
    END IF;
    IF length(coalesce(btrim(p_unidade), '')) > 20 THEN
      RAISE EXCEPTION 'A unidade pode ter no máximo 20 letras.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Limite por loja e por hora: ninguém enche a tela do gestor sem querer.
  SELECT coalesce(nullif(btrim(valor), '')::integer, 10) INTO v_max
    FROM public.configuracoes WHERE contaid = p_contaid AND chave = 'MAX_PEDIDOS_LOJA_HORA';
  v_max := coalesce(v_max, 10);
  SELECT count(*) INTO v_feitos FROM public.solicitacoesinternas s
   WHERE s.contaid = p_contaid AND s.lojaid = p_lojaid
     AND s.datasolicitacao > now() - interval '1 hour';
  IF v_feitos >= v_max THEN
    RAISE EXCEPTION 'Esta loja já abriu % pedidos na última hora. Espere um pouco.', v_feitos
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  INSERT INTO public.solicitacoesinternas (contaid, lojaid, funcionarioid, tipo, categoria, descricao,
                                           quantidade, unidade, observacao)
  VALUES (p_contaid, p_lojaid, p_funcionarioid, p_tipo,
          -- Sem categoria: o tablet não pergunta.
          NULL,
          v_desc,
          CASE WHEN p_tipo = 'Compra' THEN p_quantidade END,
          CASE WHEN p_tipo = 'Compra' THEN nullif(btrim(coalesce(p_unidade, '')), '') END,
          v_obs)
  RETURNING solicitacaoid INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.visao_abrir_pedido(integer, integer, integer, text, text, numeric, text, text)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.visao_abrir_pedido(integer, integer, integer, text, text, numeric, text, text)
  TO service_role;

-- =========================================================================
-- Conferência final: se faltou alguma coisa, esta transação não fecha.
-- =========================================================================
DO $verifica$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'visao_abrir_pedido') THEN
    RAISE EXCEPTION 'Faltou a função de abrir pedido pelo tablet.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'solicitacoesinternas'
                    AND column_name = 'observacao') THEN
    RAISE EXCEPTION 'Faltou a coluna da observação do pedido.';
  END IF;

  -- Recebe conta e loja: nunca pode ficar liberada para quem está logado.
  IF has_function_privilege('authenticated',
       'public.visao_abrir_pedido(integer, integer, integer, text, text, numeric, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'A função do pedido ficou liberada para o usuário logado.';
  END IF;

  -- COMPATIBILIDADE: nenhum pedido antigo pode ter perdido a categoria.
  IF EXISTS (SELECT 1 FROM public.solicitacoesinternas
              WHERE observacao IS NOT NULL AND datasolicitacao < now() - interval '1 minute') THEN
    RAISE EXCEPTION 'Algum pedido antigo ganhou observação. Isto não devia acontecer.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.contas c
              WHERE NOT EXISTS (SELECT 1 FROM public.configuracoes g
                                 WHERE g.contaid = c.contaid AND g.chave = 'MAX_PEDIDOS_LOJA_HORA')) THEN
    RAISE EXCEPTION 'O limite de pedidos por hora não chegou em alguma conta.';
  END IF;

  RAISE NOTICE 'tudo certo: o tablet pode abrir pedidos.';
END $verifica$;

COMMIT;
