-- =========================================================================
-- STGame — Meta só do master; quem lançou a venda, pelo nome.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- CLASSIFICAÇÃO: ACRESCENTA (marcada em 30/09/2026, já aplicada: o site
-- anterior continuava funcionando com o banco novo; nenhuma função que ele
-- chamava sumiu nem mudou de formato).
--
-- ATENÇÃO: aplique antes o aplicar-pessoa-pelo-tipo-da-acao.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929273000_meta_so_do_master.sql
--
-- O QUE MUDA: o gerente continua lançando a venda da loja dele; criar e mudar
-- a meta do mês, as metas da semana e as especiais volta a ser só do master
-- (os códigos "criar meta" e "meta especial" saem do catálogo e dos cargos).
-- O histórico das vendas mostra o nome de quem lançou e de quem corrigiu.
-- =========================================================================


BEGIN;

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

COMMIT;
