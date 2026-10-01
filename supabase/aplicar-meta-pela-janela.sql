-- =========================================================================
-- STGame — A janela da meta é a janela do lançamento: um dia se edita
-- enquanto não foi lançado, no mês atual e no anterior.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-metas-por-mes.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo tem UMA migração:
--   20261001100000_meta_pela_janela_do_lancamento.sql
--
-- CLASSIFICAÇÃO: ACRESCENTA (recria seis funções com o mesmo nome, os mesmos parâmetros e o mesmo formato de resposta; a leitura do mês ganha dois campos. O site no ar continua funcionando com o banco novo)
--
-- O QUE MUDA: a meta do mês anterior volta a ser editável (meta do mês, meta por dia e meta especial), menos nos dias já lançados. Meta especial não se cria nem se apaga mais em dia já lançado. Dois meses atrás ou antes: somente leitura. A lista dos Estornos passa a ter ordem fixa entre itens do mesmo instante.
-- =========================================================================


BEGIN;

-- ======== 20261001100000_meta_pela_janela_do_lancamento.sql ========
-- CLASSIFICAÇÃO: ACRESCENTA
-- (recria seis funções com o mesmo nome, os mesmos parâmetros e o mesmo
-- formato de resposta; a leitura do mês ganha dois campos. O site no ar
-- continua funcionando: só passa a aceitar o mês anterior e a recusar meta
-- especial em dia já lançado.)
--
-- A janela da meta é a janela do lançamento (01/10/2026, correção do Wisley).
-- A regra é do DIA, não do mês: UM DIA É EDITÁVEL ENQUANTO NÃO FOI LANÇADO,
-- dentro da mesma janela em que se pode lançar venda (mês atual e anterior,
-- primeiro_dia_editavel_meta — a MESMA função do lançamento). Fora dela,
-- somente leitura. Vale para a meta por dia, a meta do mês (o mês atual e o
-- anterior) e para criar e apagar meta especial (que também não mexe em dia
-- já lançado). E a lista dos Estornos ganha a loja no desempate. Motivo: em 2 de novembro, quem esqueceu a meta de outubro
-- lançava a venda contra o modelo e não conseguia mais corrigir a meta.

CREATE OR REPLACE FUNCTION public.metas_do_mes_por_dia(p_lojaid integer, p_mes date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta    integer := coalesce(public.minha_conta(), public.conta_do_gerente());
  v_ini      date := date_trunc('month', p_mes)::date;
  v_fim      date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje     date;
  v_esp      boolean;
  v_editar   boolean;
  v_espedit  boolean;
  v_janela   date;
BEGIN
  IF v_conta IS NULL OR p_mes IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.lojas l WHERE l.contaid = v_conta AND l.lojaid = p_lojaid)
     OR NOT (public.pode('metas.ver', p_lojaid) AND public.pode('valores.ver_rs', p_lojaid)
             AND public.pode('metas.dia_ver', p_lojaid)) THEN
    RETURN NULL;
  END IF;
  v_hoje := public.hoje_da_conta(v_conta);
  -- A janela da meta e a do lancamento (01/10/2026): mes atual e anterior em diante.
  v_janela := public.primeiro_dia_editavel_meta();
  v_esp := public.pode('metas.especiais_ver', p_lojaid);
  v_editar := v_fim >= v_janela AND public.pode('metas.dia_editar', p_lojaid);
  v_espedit := v_fim >= v_janela AND v_esp AND public.pode('metas.especiais_editar', p_lojaid);
  RETURN jsonb_build_object(
    'hoje', v_hoje,
    'mesatual', date_trunc('month', v_hoje)::date,
    'primeirodiaeditavel', v_janela,
    'podeeditar', v_editar,
    'especiaisver', v_esp,
    'especiaiseditar', v_espedit,
    'modelo', (SELECT coalesce(jsonb_agg(jsonb_build_object('diasemanaid', m.diasemanaid, 'valormeta', m.valormeta,
                                                            'pontospremio', m.pontospremio) ORDER BY m.diasemanaid), '[]'::jsonb)
                 FROM public.metasdiariasmodelos m WHERE m.contaid = v_conta AND m.lojaid = p_lojaid),
    'dias', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'dia', x.dia, 'lancado', x.lancado, 'origem', x.origem,
               -- Um dia se edita enquanto nao foi lancado, dentro da janela do lancamento.
               'editavel', NOT x.lancado AND x.dia >= v_janela,
               'meta', CASE WHEN x.especial AND NOT v_esp THEN NULL ELSE x.meta END,
               'pontos', CASE WHEN x.especial AND NOT v_esp THEN NULL ELSE x.pontos END,
               'descricao', CASE WHEN x.especial AND NOT v_esp THEN NULL ELSE x.descricao END,
               'modelo', x.modelo, 'modelopontos', x.modelopontos) ORDER BY x.dia), '[]'::jsonb)
        FROM (
          SELECT d::date AS dia,
                 a.apuracaoid IS NOT NULL AS lancado,
                 CASE WHEN a.apuracaoid IS NOT NULL THEN coalesce(a.origemmeta, 'semana') ELSE md.origem END AS origem,
                 coalesce(CASE WHEN a.apuracaoid IS NOT NULL THEN a.origemmeta ELSE md.origem END, '') = 'especial' AS especial,
                 CASE WHEN a.apuracaoid IS NOT NULL THEN a.valormetadia ELSE md.valormeta END AS meta,
                 CASE WHEN a.apuracaoid IS NOT NULL THEN a.pontosmetadia ELSE md.pontospremio END AS pontos,
                 CASE WHEN a.apuracaoid IS NOT NULL THEN a.descricaometa ELSE md.descricao END AS descricao,
                 mm.valormeta AS modelo, mm.pontospremio AS modelopontos
            FROM generate_series(v_ini, v_fim, interval '1 day') d
            LEFT JOIN public.metasdiariasapuracoes a ON a.contaid = v_conta AND a.lojaid = p_lojaid AND a.dataapuracao = d::date
            LEFT JOIN LATERAL public.meta_do_dia(p_lojaid, d::date) md ON true
            LEFT JOIN public.metasdiariasmodelos mm ON mm.contaid = v_conta AND mm.lojaid = p_lojaid
                                                   AND mm.diasemanaid = extract(dow FROM d)::integer + 1
        ) x)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.metas_do_mes_por_dia(integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.metas_do_mes_por_dia(integer, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.salvar_metas_do_mes_por_dia(p_lojaid integer, p_mes date, p_linhas jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.conta_do_gestor_editavel();
  v_ini   date := date_trunc('month', p_mes)::date;
  v_fim   date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_hoje  date;
  l       record;
  v_atual public.metasdodia%ROWTYPE;
  n       integer := 0;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (a régua do alcance: pode() na loja).
  IF NOT public.pode('metas.dia_editar', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite editar a meta por dia desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Quem não pode ver um valor não pode gravá-lo.
  IF NOT public.pode('metas.dia_ver', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra a meta por dia desta loja, então não a edita.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.pode('valores.ver_rs', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não edita meta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje := public.hoje_da_conta(v_conta);
  -- A regra é do DIA (01/10/2026): editável enquanto não foi lançado, dentro
  -- da mesma janela em que se lança venda (mês atual e anterior). O mês
  -- anterior inteiro já passou da janela? Somente leitura. (A janela começa no
  -- dia 1º do mês anterior, então todo dia de um mês aceito aqui está dentro.)
  IF p_mes IS NULL OR v_fim < public.primeiro_dia_editavel_meta() THEN
    RAISE EXCEPTION 'Este mês já saiu da janela de lançamento (mês atual e anterior): a meta dele fica como foi.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_linhas IS NULL OR jsonb_typeof(p_linhas) <> 'array' THEN
    RAISE EXCEPTION 'Nada para salvar.' USING ERRCODE = 'check_violation';
  END IF;
  IF (SELECT count(*) <> count(DISTINCT e->>'dia') FROM jsonb_array_elements(p_linhas) e) THEN
    RAISE EXCEPTION 'O mesmo dia veio duas vezes.' USING ERRCODE = 'check_violation';
  END IF;

  FOR l IN SELECT (e->>'dia')::date AS dia,
                  nullif(e->>'valormeta', '')::numeric AS valor,
                  nullif(e->>'pontospremio', '')::numeric AS pontos
             FROM jsonb_array_elements(p_linhas) e
            ORDER BY 1 LOOP
    IF l.dia IS NULL OR l.dia < v_ini OR l.dia > v_fim THEN
      RAISE EXCEPTION 'O dia % não é deste mês.', coalesce(to_char(l.dia, 'DD/MM/YYYY'), '(vazio)') USING ERRCODE = 'check_violation';
    END IF;
    -- O mesmo cadeado do lançamento daquele dia: ou a meta muda antes, ou o
    -- lançamento guarda a meta de antes e esta gravação é recusada.
    PERFORM pg_advisory_xact_lock(p_lojaid, l.dia - date '2000-01-01');
    IF EXISTS (SELECT 1 FROM public.metasdiariasapuracoes
                WHERE contaid = v_conta AND lojaid = p_lojaid AND dataapuracao = l.dia) THEN
      RAISE EXCEPTION 'O dia % já foi lançado: a meta dele ficou guardada no lançamento e não muda mais.', to_char(l.dia, 'DD/MM/YYYY')
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM public.metasespeciais
                WHERE contaid = v_conta AND lojaid = p_lojaid AND data = l.dia) THEN
      RAISE EXCEPTION 'O dia % tem meta especial: mude na aba Metas especiais.', to_char(l.dia, 'DD/MM/YYYY')
        USING ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_atual FROM public.metasdodia WHERE contaid = v_conta AND lojaid = p_lojaid AND data = l.dia;
    IF l.valor IS NULL THEN
      -- Volta para o modelo do dia da semana.
      IF v_atual.metadodiaid IS NOT NULL THEN
        DELETE FROM public.metasdodia WHERE metadodiaid = v_atual.metadodiaid;
        n := n + 1;
      END IF;
      CONTINUE;
    END IF;
    IF l.valor < 0 OR l.valor >= 1000000000 THEN
      RAISE EXCEPTION 'Meta inválida em %.', to_char(l.dia, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
    END IF;
    IF l.pontos IS NULL OR l.pontos < 0 OR l.pontos > 10000 OR l.pontos <> trunc(l.pontos) THEN
      RAISE EXCEPTION 'Pontos inválidos em % (um número inteiro de 0 a 10.000).', to_char(l.dia, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
    END IF;
    IF v_atual.metadodiaid IS NULL THEN
      INSERT INTO public.metasdodia (contaid, lojaid, data, valormeta, pontospremio, alteradopor)
      VALUES (v_conta, p_lojaid, l.dia, round(l.valor, 2), l.pontos::integer, auth.uid());
      n := n + 1;
    ELSIF v_atual.valormeta IS DISTINCT FROM round(l.valor, 2) OR v_atual.pontospremio IS DISTINCT FROM l.pontos::integer THEN
      UPDATE public.metasdodia
         SET valormeta = round(l.valor, 2), pontospremio = l.pontos::integer, alteradopor = auth.uid(), alteradoem = now()
       WHERE metadodiaid = v_atual.metadodiaid;
      n := n + 1;
    END IF;
  END LOOP;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.salvar_metas_do_mes_por_dia(integer, date, jsonb) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.salvar_metas_do_mes_por_dia(integer, date, jsonb) TO authenticated;

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
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta AND ativa) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Permissão e loja, no banco (30/09/2026: o master pode delegar).
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('metas.mes_editar', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite editar a meta do mês desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Quem não pode ver um valor não pode gravá-lo.
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('metas.mes_ver', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra a meta do mês desta loja, então não a edita.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.bot_contexto_confiavel() AND NOT public.pode('valores.ver_rs', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não edita meta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- A janela da meta é a do lançamento (01/10/2026): mês atual e anterior em
  -- diante. Antes disso, somente leitura.
  IF p_mes IS NULL OR v_ini < date_trunc('month', public.primeiro_dia_editavel_meta())::date THEN
    RAISE EXCEPTION 'Este mês já saiu da janela de lançamento (mês atual e anterior): a meta dele fica como foi.' USING ERRCODE = 'check_violation';
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

CREATE OR REPLACE FUNCTION public.criar_meta_especial(p_lojaid integer, p_data date, p_descricao text, p_valormeta numeric, p_pontospremio integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_id integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT public.pode('metas.especiais_editar', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não permite editar metas especiais desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.pode('metas.especiais_ver', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra as metas especiais desta loja, então não as edita.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.pode('valores.ver_rs', p_lojaid) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não edita meta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- A regra do dia (01/10/2026): dentro da janela de lançamento e sem lançamento.
  IF p_data IS NULL OR p_data < public.primeiro_dia_editavel_meta() THEN
    RAISE EXCEPTION 'Esta data já saiu da janela de lançamento (mês atual e anterior): a meta dela fica como foi.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.metasdiariasapuracoes WHERE contaid = v_conta AND lojaid = p_lojaid AND dataapuracao = p_data) THEN
    RAISE EXCEPTION 'O dia % já foi lançado: a meta dele ficou guardada no lançamento e não muda mais.', to_char(p_data, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO public.metasespeciais (contaid, lojaid, data, descricao, valormeta, pontospremio)
  VALUES (v_conta, p_lojaid, p_data, p_descricao, p_valormeta, p_pontospremio)
  RETURNING metaespecialid INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.apagar_meta_especial(p_metaespecialid integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_loja integer; v_data date;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT lojaid, data INTO v_loja, v_data FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
  -- Não existe (ou é de outra conta): como antes, não apaga nada.
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT public.pode('metas.especiais_editar', v_loja) THEN
    RAISE EXCEPTION 'Seu cargo não permite editar metas especiais desta loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.pode('metas.especiais_ver', v_loja) THEN
    RAISE EXCEPTION 'Seu cargo não mostra as metas especiais desta loja, então não as edita.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.pode('valores.ver_rs', v_loja) THEN
    RAISE EXCEPTION 'Seu cargo não mostra valores em R$ nesta loja, então não edita meta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- A regra do dia (01/10/2026): dentro da janela de lançamento e sem lançamento.
  IF v_data < public.primeiro_dia_editavel_meta() THEN
    RAISE EXCEPTION 'Esta meta especial já saiu da janela de lançamento (mês atual e anterior): fica como foi.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.metasdiariasapuracoes WHERE contaid = v_conta AND lojaid = v_loja AND dataapuracao = v_data) THEN
    RAISE EXCEPTION 'O dia % já foi lançado: a meta dele ficou guardada no lançamento e não muda mais.', to_char(v_data, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
  DELETE FROM public.metasespeciais WHERE contaid = v_conta AND metaespecialid = p_metaespecialid;
END;
$function$;

-- A lista dos Estornos: a loja entra no desempate (achado da prova de 01/10/2026).
CREATE OR REPLACE FUNCTION public.estornos_da_conta(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(tipo text, quando timestamp with time zone, lojaid integer, loja text, pessoa text, descricao text, pontos integer, motivo text, quem text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.minha_conta();
BEGIN
  IF v_conta IS NULL OR NOT public.sou_master() THEN
    RAISE EXCEPTION 'Só o dono da conta vê a lista de estornos.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT 'entrega'::text, e.dataestorno, e.lojaid, l.nome::text, f.nomecompleto::text,
         t.titulo::text, -coalesce(e.pontosganhos, 0), e.motivoestorno::text,
         coalesce(public.autor_em(e.estornadopor, e.dataestorno), 'desconhecido')
    FROM public.entregas e
    JOIN public.lojas l ON l.contaid = e.contaid AND l.lojaid = e.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = e.contaid AND f.funcionarioid = e.funcionarioid
    LEFT JOIN public.tarefas t ON t.contaid = e.contaid AND t.tarefaid = e.tarefaid
   WHERE e.contaid = v_conta AND e.statusvalidacao = 'Estornada'
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  UNION ALL
  -- Resgates cancelados (antes de entregar) e estornados (depois): os pontos
  -- voltam para a pessoa. Resgate registrado sem loja só aparece na lista de
  -- todas as lojas (p_lojaid vazio).
  SELECT CASE r.status WHEN 'Cancelado' THEN 'resgate cancelado' ELSE 'resgate estornado' END,
         CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END,
         r.lojaid, l.nome::text, f.nomecompleto::text,
         CASE WHEN r.valorreais IS NOT NULL THEN 'abate na comanda de ' || public.reais(r.valorreais) ELSE p.nome::text END,
         r.pontosgastos,
         (CASE r.status WHEN 'Cancelado' THEN r.motivocancelamento ELSE r.motivoestorno END)::text,
         coalesce(public.autor_em(CASE r.status WHEN 'Cancelado' THEN r.canceladopor ELSE r.estornadopor END,
                                  CASE r.status WHEN 'Cancelado' THEN r.datacancelamento ELSE r.dataestorno END), 'desconhecido')
    FROM public.resgates r
    LEFT JOIN public.lojas l ON l.contaid = r.contaid AND l.lojaid = r.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = r.contaid AND f.funcionarioid = r.funcionarioid
    LEFT JOIN public.produtosloja p ON p.contaid = r.contaid AND p.produtoid = r.produtoid
   WHERE r.contaid = v_conta AND r.status IN ('Cancelado', 'Estornado')
     AND (p_lojaid IS NULL OR r.lojaid = p_lojaid)
  UNION ALL
  -- Feedbacks anulados: o bônus sai de volta da pessoa. Feedback não tem
  -- loja: aparece na lista de todas as lojas e na de cada loja da pessoa.
  SELECT 'feedback anulado', fb.anuladoem, NULL::integer, NULL::text, f.nomecompleto::text,
         'Feedback de ' || to_char(fb.datafeedback, 'DD/MM/YYYY') || ' (nota ' || fb.notadia || ')',
         -coalesce(fb.pontosbonus, 0), fb.motivoanulacao::text,
         coalesce(public.autor_em(fb.anuladopor, fb.anuladoem), 'desconhecido')
    FROM public.feedbacks fb
    LEFT JOIN public.funcionarios f ON f.contaid = fb.contaid AND f.funcionarioid = fb.funcionarioid
   WHERE fb.contaid = v_conta AND fb.anuladoem IS NOT NULL
     AND (p_lojaid IS NULL OR EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                                       WHERE fl.contaid = fb.contaid AND fl.funcionarioid = fb.funcionarioid AND fl.lojaid = p_lojaid))
  UNION ALL
  -- Entrega registrada por um GERENTE sem foto (30/09/2026, decisão do
  -- Wisley): não é bloqueada, fica à vista do master aqui.
  SELECT 'entrega sem foto', e.dataenvio, e.lojaid, l.nome::text, f.nomecompleto::text,
         t.titulo::text || ' (' || e.statusvalidacao || ')', coalesce(e.pontosganhos, 0), e.observacao::text,
         coalesce(public.autor_em(e.registradopor, e.dataenvio), 'desconhecido')
    FROM public.entregas e
    JOIN public.lojas l ON l.contaid = e.contaid AND l.lojaid = e.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = e.contaid AND f.funcionarioid = e.funcionarioid
    LEFT JOIN public.tarefas t ON t.contaid = e.contaid AND t.tarefaid = e.tarefaid
   WHERE e.contaid = v_conta AND e.pathfotoevidencia IS NULL
     AND EXISTS (SELECT 1 FROM public.contasusuarios cu
                  WHERE cu.contaid = e.contaid AND cu.userid = e.registradopor AND cu.papel = 'gerente')
     AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  UNION ALL
  -- Toda mudança de meta (30/09/2026, decisão do Wisley): o master delega a
  -- meta e VÊ o que foi feito — quem, quando, o valor antes e o depois.
  SELECT 'meta alterada', ma.alteradoem, ma.lojaid, l.nome::text, NULL::text,
         ma.referencia || ': '
           || CASE WHEN ma.valorantes IS NULL AND ma.pontosantes IS NULL THEN 'criada, '
                   ELSE coalesce(public.reais(ma.valorantes), '—') || ' e ' || coalesce(ma.pontosantes::text, '—') || ' pontos → ' END
           || CASE WHEN ma.valordepois IS NULL AND ma.pontosdepois IS NULL THEN 'apagada'
                   ELSE coalesce(public.reais(ma.valordepois), '—') || ' e ' || coalesce(ma.pontosdepois::text, '—') || ' pontos' END,
         0, NULL::text,
         coalesce(public.autor_em(ma.alteradopor, ma.alteradoem), CASE WHEN ma.alteradopor IS NULL THEN 'Sistema' ELSE 'desconhecido' END)
    FROM public.metasalteracoes ma
    JOIN public.lojas l ON l.contaid = ma.contaid AND l.lojaid = ma.lojaid
   WHERE ma.contaid = v_conta
     AND (p_lojaid IS NULL OR ma.lojaid = p_lojaid)
   -- Desempate fixo: dois estornos no mesmo instante saem sempre na mesma ordem.
   -- (01/10/2026: a loja entrou no desempate — mudanças de meta de lojas
   -- diferentes no mesmo instante, com o mesmo texto, trocavam de lugar.)
   ORDER BY 2 DESC, 1, 3, 6, 5, 9, 8
   LIMIT 500;
END;
$function$;

COMMIT;
