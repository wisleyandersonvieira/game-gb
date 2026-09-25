-- =========================================================================
-- STGame — o som do tablet passa a ser POR LOJA, e ganha repetição.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes.
--
-- Este arquivo é UMA migração só:
--   20260929120000_som_por_loja.sql
--
-- O QUE MUDA PARA QUEM JÁ USA:
--   * Cada loja passa a ter as suas três configurações de tablet, e começa
--     EXATAMENTE com o que está valendo hoje na conta: ligado ou desligado, e
--     o mesmo volume que o tablet toca hoje. A repetição começa desligada.
--   * As duas configurações de som que ficavam em Configurações (som e
--     volume) saem de lá: agora o lugar é o botão "Configurações" do cartão
--     da loja, em "Lojas e links da TV". Duas telas mandando na mesma coisa
--     é pedir confusão.
--   * O arquivo do som foi regravado mais alto (normalizado, sem cortar), e o
--     número do volume é convertido na mesma proporção, com os 50% a mais
--     pedidos. O tablet toca uns 50% mais alto que hoje, e não 4 vezes.
-- =========================================================================


BEGIN;

-- O som do tablet passa a ser POR LOJA, e ganha repetição.
--
-- Por que mudou de lugar: o som era uma configuração da CONTA, e isso não
-- resiste à realidade de quem tem mais de uma loja. Uma fica no shopping, com
-- música alta; outra é um quiosque silencioso onde o som incomoda o cliente.
-- Quem regula é quem está na loja, ouvindo.
--
-- NADA muda de comportamento ao aplicar: cada loja começa exatamente com o que
-- está valendo hoje na conta dela (ligado ou desligado, e o mesmo volume que o
-- tablet toca hoje), e a repetição começa DESLIGADA em todas.
--
-- Sobre o volume: o arquivo do som foi regravado normalizado perto do máximo
-- (o pico saiu de 0,237 para 0,95 da escala, 4,0046 vezes mais alto), porque
-- amplificar no código distorce. Para o tablet não passar a berrar, o número
-- guardado aqui é convertido na mesma proporção, com os 50% a mais que o
-- Wisley pediu:
--
--     volume_novo = volume_antigo x 1,5 / 4,0046 = volume_antigo x 0,3745
--
-- O padrão de 50 vira 19, que é o "médio" da janela de configuração. Quem
-- tinha outro número continua proporcional ao que tinha.

-- ---------------------------------------------------------------------------
-- 1. As três colunas na loja, e o valor que cada uma começa com
-- ---------------------------------------------------------------------------
-- Tudo dentro de um IF que só entra quando as colunas AINDA NÃO EXISTEM.
--
-- Não é frescura de idempotência: sem isto, rodar o arquivo uma segunda vez
-- (coisa que acontece, e que o cabeçalho até promete que é seguro) jogaria
-- toda loja de volta para o que estava na conta, apagando o que o gestor
-- tivesse ajustado no botão "Configurações" de cada uma.
DO $migracao$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'lojas'
                AND column_name = 'somtarefanova') THEN
    RAISE NOTICE 'o som por loja já estava aplicado: nada foi tocado.';
    RETURN;
  END IF;

  ALTER TABLE public.lojas
    ADD COLUMN somtarefanova     boolean NOT NULL DEFAULT true,
    ADD COLUMN somvolume         integer NOT NULL DEFAULT 19,
    ADD COLUMN somrepetirminutos integer NOT NULL DEFAULT 0;

  -- Cada loja começa com o que está valendo hoje na conta dela.
  UPDATE public.lojas l
     SET somtarefanova = coalesce(
           (SELECT g.valor <> '0' FROM public.configuracoes g
             WHERE g.contaid = l.contaid AND g.chave = 'SOM_TAREFA_NOVA'), true),
         somvolume = greatest(0, least(100, round(coalesce(
           (SELECT nullif(btrim(g.valor), '')::numeric FROM public.configuracoes g
             WHERE g.contaid = l.contaid AND g.chave = 'SOM_VOLUME'
               AND btrim(g.valor) ~ '^[0-9]+$'), 50) * 0.3745)::integer));
END
$migracao$;

COMMENT ON COLUMN public.lojas.somtarefanova IS
  'O tablet DESTA loja toca som quando chega tarefa nova. Só o tablet: o celular da pessoa nunca recebe aviso.';
COMMENT ON COLUMN public.lojas.somvolume IS
  'Volume do som do tablet desta loja, de 0 a 100. A janela oferece três níveis: baixo 10, médio 19, alto 45.';
COMMENT ON COLUMN public.lojas.somrepetirminutos IS
  'De quantos em quantos minutos o tablet repete o aviso enquanto ninguém aceita a tarefa. 0 desliga. Mínimo 5.';

-- ---------------------------------------------------------------------------
-- 2. O que o banco aceita, valha o que valer a tela
-- ---------------------------------------------------------------------------
ALTER TABLE public.lojas DROP CONSTRAINT IF EXISTS lojas_somvolume_valido;
ALTER TABLE public.lojas ADD CONSTRAINT lojas_somvolume_valido
  CHECK (somvolume BETWEEN 0 AND 100);

-- Intervalo mínimo de 5 minutos, sem opção menor: com menos que isso o aviso
-- vira barulho e a loja desliga o som, que é o pior desfecho possível.
ALTER TABLE public.lojas DROP CONSTRAINT IF EXISTS lojas_somrepetir_valido;
ALTER TABLE public.lojas ADD CONSTRAINT lojas_somrepetir_valido
  CHECK (somrepetirminutos IN (0, 5, 10, 15, 30));

-- ---------------------------------------------------------------------------
-- 3. As duas chaves da conta saem de cena
-- ---------------------------------------------------------------------------
-- Duas telas mandando na mesma coisa é pedir para o gestor mudar num lugar e
-- não ver efeito. Agora o único lugar é o botão "Configurações" da loja.
-- Partindo da versão MAIS RECENTE (20260929101000), sem as duas linhas do som.
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
     'Quantos pedidos de resgate a mesma pessoa pode fazer em uma hora.')
  ON CONFLICT (contaid, chave) DO NOTHING;
$fn$;

-- As duas linhas FICAM na tabela, de propósito, nas contas que já existem.
-- Apagá-las esbarra em `configuracoeshistorico`, que guarda quem mudou o que:
-- a chave que o gestor já alterou alguma vez tem histórico apontando para ela,
-- e o banco recusa o DELETE — foi o que aconteceu no teste. E apagar o
-- histórico junto seria pior: ele existe justamente para não se perder.
--
-- Ficar ali não faz efeito nenhum: nenhuma tela mostra essas duas chaves e
-- nenhum código as lê. Conta nova já nasce sem elas.

-- ---------------------------------------------------------------------------
-- 4. Salvar as configurações do tablet de uma loja
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.salvar_som_da_loja(
  p_lojaid  integer,
  p_ligado  boolean,
  p_volume  integer,
  p_repetir integer
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Os três níveis da janela, e nada além deles: o navegador não escolhe o
  -- número, escolhe o nível.
  IF coalesce(p_volume, 19) NOT IN (10, 19, 45) THEN
    RAISE EXCEPTION 'O volume é baixo, médio ou alto.' USING ERRCODE = 'check_violation';
  END IF;
  IF coalesce(p_repetir, 0) NOT IN (0, 5, 10, 15, 30) THEN
    RAISE EXCEPTION 'A repetição é de 5, 10, 15 ou 30 minutos, ou desligada.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.lojas
     SET somtarefanova     = coalesce(p_ligado, true),
         somvolume         = coalesce(p_volume, 19),
         somrepetirminutos = coalesce(p_repetir, 0)
   WHERE lojaid = p_lojaid AND contaid = v_conta;
END;
$$;

REVOKE ALL ON FUNCTION public.salvar_som_da_loja(integer, boolean, integer, integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.salvar_som_da_loja(integer, boolean, integer, integer) TO authenticated, service_role;

COMMIT;
