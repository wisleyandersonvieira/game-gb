-- Etapa 1.12, parte B1b — o que o tablet da loja pode pedir ao banco.
--
-- O tablet entra como a LOJA, e para ele `minha_conta()` responde vazio: as
-- ~200 regras de acesso que já existiam negam tudo. Estas funções são a única
-- porta, e só o SERVIDOR as chama (elas recebem conta e loja, então nunca são
-- liberadas para quem está logado — regra da Etapa 1.6).
--
-- Cada uma liga o contexto da visão e faz o trabalho na MESMA transação: o
-- contexto é local à transação, então não dá para ligá-lo numa chamada e usá-lo
-- na seguinte.

-- ---------------------------------------------------------------------------
-- 1. A fila do dia
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.visao_fila(p_contaid integer, p_lojaid integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, NULL, p_lojaid, 'tablet');
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) FROM public.fila_da_loja(p_lojaid) f);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Quem é o PIN
-- ---------------------------------------------------------------------------
-- O resumo do PIN é feito pelo SERVIDOR (HMAC com a chave que só ele tem), do
-- mesmo jeito da parte A: quem tiver só o banco não consegue testar número
-- nenhum. Aqui é busca direta pelo índice, sem comparar uma pessoa por vez.
-- Só encontra quem está ativo, ligado a ESTA loja e trabalhando hoje.
CREATE OR REPLACE FUNCTION public.visao_pessoa_do_pin(p_contaid integer, p_lojaid integer, p_pinhash text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  f      record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT fu.funcionarioid, fu.nomecompleto INTO f
    FROM public.funcionarios fu
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = fu.funcionarioid AND fl.contaid = p_contaid
                                    AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE fu.contaid = p_contaid AND fu.ativo
     AND fu.pinhash = p_pinhash
     AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
   LIMIT 1;

  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('funcionarioid', f.funcionarioid,
                            'nome', public.nome_curto(f.nomecompleto));
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Pegar
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.visao_pegar(p_contaid integer, p_lojaid integer,
                                              p_funcionarioid integer, p_atribuicaoid integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tarefasatribuidas
                  WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid) THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');
  RETURN public.pegar_tarefa(p_atribuicaoid, p_funcionarioid);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Entregar
-- ---------------------------------------------------------------------------
-- Recebe sempre a tarefa de origem; a função descobre onde a entrega entra.
-- Entregar sem ter pegado vale como aceite. O PIN de outra pessoa é recusado.
CREATE OR REPLACE FUNCTION public.visao_entregar(p_contaid integer, p_lojaid integer,
                                                 p_funcionarioid integer, p_atribuicaoid integer,
                                                 p_caminho text, p_observacao text)
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

  SELECT * INTO m FROM public.tarefasatribuidas
   WHERE atribuicaoid = p_atribuicaoid AND contaid = p_contaid AND lojaid = p_lojaid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarefa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.entrar_na_visao(p_contaid, p_funcionarioid, p_lojaid, 'tablet');

  IF m.funcionarioid IS NULL THEN
    SELECT novaatribuicaoid, funcionarioid INTO v_alvo, v_dono
      FROM public.missoesaceites
     WHERE contaid = p_contaid AND atribuicaoid = p_atribuicaoid AND dia = v_hoje AND revogadoem IS NULL;
    IF v_alvo IS NULL THEN
      -- Ninguém pegou ainda: entregar vale como aceite.
      v_alvo := public.pegar_tarefa(p_atribuicaoid, p_funcionarioid);
    ELSIF v_dono <> p_funcionarioid THEN
      RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF m.funcionarioid <> p_funcionarioid THEN
    RAISE EXCEPTION 'Esta tarefa é de outra pessoa.' USING ERRCODE = 'insufficient_privilege';
  ELSE
    v_alvo := p_atribuicaoid;
  END IF;

  RETURN public.registrar_entrega(v_alvo, p_observacao, p_caminho, false);
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Permissões: só o servidor. Recebem conta e loja, então nunca são
--    liberadas para quem está logado (regra da Etapa 1.6).
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.visao_fila(integer, integer)                        FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_pessoa_do_pin(integer, integer, text)         FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_pegar(integer, integer, integer, integer)     FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text)
                                                                                  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.visao_fila(integer, integer)                     TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_pessoa_do_pin(integer, integer, text)      TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_pegar(integer, integer, integer, integer)  TO service_role;
GRANT EXECUTE ON FUNCTION public.visao_entregar(integer, integer, integer, integer, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. O diagnóstico (/saude) passa a conhecer as funções desta parte
-- ---------------------------------------------------------------------------
-- Sem isto, um banco sem a B1a/B1b daria "não foi possível" na tela do tablet
-- sem dizer o motivo — foi o que aconteceu em 23/09/2026 com a parte A.
CREATE OR REPLACE FUNCTION public.diagnostico_do_sistema()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_esperadas text[] := ARRAY[
    'tentativa_abrir', 'tentativa_fechar', 'acesso_por_email', 'definir_senha_gestor',
    'senha_app_de', 'senha_app_do_funcionario', 'definir_senha_app', 'definir_pin',
    'criar_codigo_acesso', 'usar_codigo_acesso', 'conta_do_codigo',
    'criar_acesso_loja', 'criar_acesso_colaborador', 'redefinir_acesso', 'trocar_cpf',
    'meu_acesso', 'situacao_dos_acessos', 'minha_politica_de_uso', 'politica_dar_ciencia',
    'limpar_senha_gestor', 'rotina_expurgo_fotos', 'expurgo_pegar', 'expurgo_resultado',
    -- Etapa 1.12, partes B1a e B1b
    'pegar_tarefa', 'revogar_aceite', 'atribuir_tarefa', 'fila_da_loja',
    'tarefas_nao_pegas', 'tarefas_pegas_da_pessoa',
    'visao_fila', 'visao_pessoa_do_pin', 'visao_pegar', 'visao_entregar'
  ];
  v_faltando text[];
  v_tabelas  text[];
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor pede o diagnóstico.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(array_agg(f ORDER BY f), ARRAY[]::text[]) INTO v_faltando
    FROM unnest(v_esperadas) f
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                      WHERE n.nspname = 'public' AND p.proname = f);

  SELECT coalesce(array_agg(t ORDER BY t), ARRAY[]::text[]) INTO v_tabelas
    FROM unnest(ARRAY['codigosacesso', 'tentativasacesso', 'senhasgestor', 'fotosexpurgo',
                      'tarefascandidatos']) t
   WHERE to_regclass('public.' || t) IS NULL;

  RETURN jsonb_build_object(
    'funcoesfaltando', to_jsonb(v_faltando),
    'tabelasfaltando', to_jsonb(v_tabelas),
    'acessos', (SELECT count(*) FROM public.contasusuarios),
    'senhasgestor', (SELECT count(*) FROM public.senhasgestor));
END;
$$;

REVOKE ALL ON FUNCTION public.diagnostico_do_sistema() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.diagnostico_do_sistema() TO service_role;
