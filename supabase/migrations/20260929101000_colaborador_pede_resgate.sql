-- Etapa 1.12, parte C2 — o colaborador PEDE resgate pelo celular.
--
-- Até aqui só o gestor registrava resgate. Agora a pessoa pede, e o pedido cai
-- como PENDENTE para o gestor aprovar — idêntico ao que o "Entregar depois" do
-- gestor já cria.
--
-- REAPROVEITA O CAMINHO QUE JÁ EXISTE, e não cria um paralelo: quem grava é
-- `registrar_troca` / `registrar_troca_por_valor` com p_entregar = false, e
-- quem desfaz é `cancelar_troca`. Isso importa por três motivos:
--
--   1. O LIVRO DE PONTOS. Os pontos saem no instante do pedido, por
--      `movimentospontos` — é isso que "reservar" quer dizer aqui. Cancelar
--      grava o movimento contrário; nada se altera nem se apaga.
--   2. AS TRAVAS DE CORRIDA já estão lá: `funcionarios` e `produtosloja` são
--      lidos com FOR UPDATE. Dois toques rápidos não geram dois resgates, e
--      com estoque 1 só um pedido passa.
--   3. O ESTOQUE volta pelo mesmo caminho do gestor.

-- ---------------------------------------------------------------------------
-- 0. De onde veio o pedido
-- ---------------------------------------------------------------------------
-- Coluna nova, VAZIA em tudo o que já existe: os resgates de antes continuam
-- como estão, e a tela do gestor lê vazio como "registrado por mim".
ALTER TABLE public.resgates
  ADD COLUMN IF NOT EXISTS origem varchar(20);

COMMENT ON COLUMN public.resgates.origem IS
  'De onde veio o pedido: "colaborador" quando foi pelo celular. Vazio nos resgates registrados pelo gestor.';

-- ---------------------------------------------------------------------------
-- 1. Os dois limites
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260929100900), com o diff conferido.
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
     'Quantos pedidos a mesma loja pode abrir pelo tablet em uma hora.'),
    -- Pedido de resgate feito pelo celular do colaborador.
    (p_contaid, 'MAX_RESGATES_PENDENTES', '3',
     'Quantos pedidos de resgate a mesma pessoa pode ter esperando o gestor.'),
    (p_contaid, 'MAX_RESGATES_HORA', '5',
     'Quantos pedidos de resgate a mesma pessoa pode fazer em uma hora.')
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
-- 2. O catálogo que ELA pode pedir
-- ---------------------------------------------------------------------------
-- O mesmo critério da tela do gestor: prêmio ativo, da conta, com estoque, e
-- que cabe no saldo dela. O saldo vem do banco, nunca do que a tela calculou.
CREATE OR REPLACE FUNCTION public.eu_premios(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_saldo integer;
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT saldopontos INTO v_saldo FROM public.funcionarios
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid;

  RETURN jsonb_build_object(
    'saldo', v_saldo,
    'premios', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'produtoid', p.produtoid,
               'nome',      p.nome,
               'custo',     p.custoempontos,
               'estoque',   p.estoquedisponivel,
               'cabe',      (v_saldo >= p.custoempontos)) ORDER BY p.custoempontos, p.nome), '[]'::jsonb)
        FROM public.produtosloja p
       WHERE p.contaid = p_contaid AND p.ativo AND p.sistema IS NULL
         AND (p.estoquedisponivel IS NULL OR p.estoquedisponivel > 0)));
END;
$$;

REVOKE ALL ON FUNCTION public.eu_premios(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_premios(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Os pedidos dela
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.eu_resgates(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'resgateid', r.resgateid,
             'nome',      p.nome,
             'pontos',    r.pontosgastos,
             'quando',    r.datasolicitacao,
             'status',    r.status) ORDER BY r.datasolicitacao DESC), '[]'::jsonb)
      FROM public.resgates r
      JOIN public.produtosloja p ON p.produtoid = r.produtoid AND p.contaid = p_contaid
     WHERE r.contaid = p_contaid AND r.funcionarioid = p_funcionarioid
       AND r.datasolicitacao > now() - interval '90 days');
END;
$$;

REVOKE ALL ON FUNCTION public.eu_resgates(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_resgates(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. Pedir o resgate
-- ---------------------------------------------------------------------------
-- QUEM PEDE vem de fora, do servidor, a partir da sessão dela. Esta função
-- recebe a conta, então nunca é liberada para quem está logado.
CREATE OR REPLACE FUNCTION public.eu_pedir_resgate(
  p_contaid       integer,
  p_funcionarioid integer,
  p_produtoid     integer DEFAULT NULL,
  p_valorreais    numeric DEFAULT NULL,
  p_lojaid        integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id       integer;
  v_pend     integer;
  v_hora     integer;
  v_maxpend  integer;
  v_maxhora  integer;
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  IF (p_produtoid IS NULL) = (p_valorreais IS NULL) THEN
    RAISE EXCEPTION 'Escolha um prêmio do catálogo ou um valor para abater.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- A loja, quando vem, tem de ser da conta dela.
  IF p_lojaid IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.funcionarioslojas fl
        WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid
          AND fl.lojaid = p_lojaid AND fl.ativo) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  -- Uma pessoa por vez: dois toques rápidos entram em fila aqui, e o segundo
  -- já encontra o primeiro contado nos limites.
  PERFORM pg_advisory_xact_lock(hashtextextended('stgame.resgate:' || p_contaid || ':' || p_funcionarioid, 0));

  SELECT coalesce(nullif(btrim(valor), '')::integer, 3) INTO v_maxpend
    FROM public.configuracoes WHERE contaid = p_contaid AND chave = 'MAX_RESGATES_PENDENTES';
  SELECT coalesce(nullif(btrim(valor), '')::integer, 5) INTO v_maxhora
    FROM public.configuracoes WHERE contaid = p_contaid AND chave = 'MAX_RESGATES_HORA';
  v_maxpend := coalesce(v_maxpend, 3);
  v_maxhora := coalesce(v_maxhora, 5);

  SELECT count(*) INTO v_pend FROM public.resgates r
   WHERE r.contaid = p_contaid AND r.funcionarioid = p_funcionarioid AND r.status = 'Pendente';
  IF v_pend >= v_maxpend THEN
    RAISE EXCEPTION 'Você já tem % pedidos esperando o gestor. Espere ele entregar ou cancele um.', v_pend
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT count(*) INTO v_hora FROM public.resgates r
   WHERE r.contaid = p_contaid AND r.funcionarioid = p_funcionarioid
     AND r.datasolicitacao > now() - interval '1 hour';
  IF v_hora >= v_maxhora THEN
    RAISE EXCEPTION 'Você já fez % pedidos nesta hora. Espere um pouco.', v_hora
      USING ERRCODE = 'check_violation';
  END IF;

  -- O contexto da visão faz minha_conta() responder, que é o que as funções
  -- de sempre usam. Daqui para baixo é EXATAMENTE o caminho do gestor com
  -- "Entregar depois": mesmos FOR UPDATE, mesmo livro de pontos, mesmo estoque.
  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'colaborador');

  IF p_produtoid IS NOT NULL THEN
    v_id := public.registrar_troca(p_funcionarioid, p_produtoid, p_lojaid, false);
  ELSE
    v_id := public.registrar_troca_por_valor(p_funcionarioid, p_valorreais, p_lojaid, false);
  END IF;

  UPDATE public.resgates SET origem = 'colaborador' WHERE resgateid = v_id AND contaid = p_contaid;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.eu_pedir_resgate(integer, integer, integer, numeric, integer)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_pedir_resgate(integer, integer, integer, numeric, integer)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Desistir enquanto está pendente
-- ---------------------------------------------------------------------------
-- Pela MESMA função de cancelar que o gestor usa: os pontos e o estoque voltam
-- exatamente como voltariam para ele.
CREATE OR REPLACE FUNCTION public.eu_cancelar_resgate(p_contaid integer, p_funcionarioid integer,
                                                      p_resgateid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_lojaid integer;
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  -- Só o pedido DELA, e só enquanto está pendente.
  SELECT lojaid INTO v_lojaid FROM public.resgates
   WHERE resgateid = p_resgateid AND contaid = p_contaid
     AND funcionarioid = p_funcionarioid AND status = 'Pendente';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Este pedido não é seu, ou já foi resolvido.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, v_lojaid, 'colaborador');
  PERFORM public.cancelar_troca(p_resgateid, 'cancelado pelo colaborador');
END;
$$;

REVOKE ALL ON FUNCTION public.eu_cancelar_resgate(integer, integer, integer)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_cancelar_resgate(integer, integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. A lista do gestor mostra de onde veio o pedido
-- ---------------------------------------------------------------------------
-- Parte da versao mais recente (20260921150000), com o diff conferido: entra
-- so a origem.
CREATE OR REPLACE FUNCTION public.listar_trocas(p_limite integer DEFAULT 100)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY ds DESC, id DESC), '[]'::jsonb)
    FROM (
      SELECT r.datasolicitacao AS ds, r.resgateid AS id,
             jsonb_build_object(
               'trocaid',            r.resgateid,
               'status',             r.status,
               'pontos',             r.pontosgastos,
               'valorreais',         r.valorreais,
               'datasolicitacao',    r.datasolicitacao,
               'dataentrega',        r.dataentrega,
               'motivocancelamento', r.motivocancelamento,
               'motivoestorno',      r.motivoestorno,
               'funcionarioid',      r.funcionarioid,
               'pessoa',             f.nomecompleto,
               'premio',             CASE WHEN r.valorreais IS NOT NULL
                                          THEN 'Abate na comanda de ' || public.reais(r.valorreais)
                                          ELSE p.nome END,
               'loja',               l.nome,
               -- De onde veio: "colaborador" quando foi pelo celular. Vazio
               -- nos resgates que o gestor registrou, inclusive os antigos.
               'origem',             r.origem) AS x
        FROM public.resgates r
        JOIN public.funcionarios f  ON f.funcionarioid = r.funcionarioid
        JOIN public.produtosloja p  ON p.produtoid = r.produtoid
        LEFT JOIN public.lojas l    ON l.lojaid = r.lojaid
       ORDER BY r.datasolicitacao DESC, r.resgateid DESC
       LIMIT greatest(1, least(coalesce(p_limite, 100), 1000))
    ) s
$$;

REVOKE ALL ON FUNCTION public.listar_trocas(integer) FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.listar_trocas(integer) TO authenticated, service_role;
