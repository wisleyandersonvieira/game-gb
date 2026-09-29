-- Desempate fixo nas listas (29/09/2026, pedido do Wisley).
--
-- Duas linhas com o mesmo horário (ou o mesmo nome/título) saíam em ordem
-- incerta: a mesma consulta, rodada duas vezes, podia devolver a lista em
-- ordens diferentes. Isso já sujou duas provas de antes/depois. Cada lista de
-- gestão ordenada por horário, nome ou título ganha, no fim da ordenação, o
-- número da própria linha (a chave). A numeração das linhas da lista do dia
-- (tarefasdodia.itemid) passa a sair sempre na mesma ordem (loja, atribuição).
-- Cada função parte da versão viva e muda SÓ a ordenação.
-- Nenhum dado é alterado.

-- agendamentos_sem_tarefa: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.agendamentos_sem_tarefa(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
         ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    FROM situacao s
   WHERE NOT coalesce(s.entregue, false)
     AND (s.atribuicaoid IS NULL OR s.datafimvigencia_ta IS NOT NULL OR NOT s.tarefaativa OR NOT s.respnaloja)
$function$;

-- conflitos_agendamento: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.conflitos_agendamento(p_lojaid integer, p_dataevento timestamp with time zone, p_ignorar integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object('quando', dataevento, 'tipo', tipoevento) ORDER BY dataevento, agendamentoid), '[]'::jsonb)
    FROM public.agendamentos
   WHERE lojaid = p_lojaid AND statusagendamento = 'Confirmado'
     AND (p_ignorar IS NULL OR agendamentoid <> p_ignorar)
     AND dataevento BETWEEN p_dataevento - interval '2 hours' AND p_dataevento + interval '2 hours'
$function$;

-- fila_de_um_dia: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_h        jsonb := public.meu_hoje();
  v_hoje     date  := (v_h->>'hoje')::date;
  v_fuso     text  := v_h->>'fuso';
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
  v_conta    integer := public.minha_conta();
BEGIN
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF v_conta IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.fila_de_um_dia_gerente(p_lojaid, p_dia);
  END IF;
  IF v_conta IS NULL OR v_hoje IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio, e.entregaid), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem, a.aceiteid), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$function$;

-- fila_de_um_dia_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.fila_de_um_dia_gerente(p_lojaid integer, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta    integer := public.conta_do_gerente();
  v_hoje     date  := public.hoje_da_conta(public.conta_do_gerente());
  v_fuso     text  := public.fuso_da_conta(public.conta_do_gerente());
  v_primeiro date;
  v_fim      timestamptz;
  v_foto     timestamptz;
  v_itens    jsonb;
  v_feitas   jsonb;
  v_andam    jsonb;
BEGIN
  IF v_conta IS NULL OR v_hoje IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT a.primeirodia INTO v_primeiro FROM public.fila_alcance(v_hoje) a;
  IF p_dia IS NULL OR p_dia >= v_hoje THEN
    RAISE EXCEPTION 'Escolha um dia que já passou (o de hoje é a fila ao vivo).' USING ERRCODE = 'check_violation';
  END IF;
  IF p_dia < v_primeiro THEN
    RAISE EXCEPTION 'O filtro vai até %.', to_char(v_primeiro, 'DD/MM/YYYY') USING ERRCODE = 'check_violation';
  END IF;
  -- A regra de cada tabela já limita à conta; o filtro explícito é a
  -- segunda tranca.
  IF NOT EXISTS (SELECT 1 FROM public.lojas WHERE lojaid = p_lojaid AND contaid = v_conta) THEN
    RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT dg.fotodafilaem INTO v_foto FROM public.diasgerados dg WHERE dg.contaid = v_conta AND dg.dia = p_dia;

  IF v_foto IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', f.atribuicaoid, 'titulo', f.titulo, 'pontos', f.pontos,
             'tipofrequencia', f.tipofrequencia, 'aberta', f.aberta, 'situacao', f.situacao,
             'atrasada', f.atrasada, 'quempegounome', f.quempegounome, 'pegaem', f.pegaem,
             'feitapor', f.feitapor, 'feitaem', f.feitaem, 'feitasituacao', f.feitasituacao)
             ORDER BY f.atrasada DESC, f.titulo, f.atribuicaoid), '[]'::jsonb)
      INTO v_itens
      FROM public.fotosdafila f
     WHERE f.contaid = v_conta AND f.lojaid = p_lojaid AND f.dia = p_dia;
    RETURN jsonb_build_object('dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
                              'registrado', true, 'fotoem', v_foto, 'itens', v_itens);
  END IF;

  -- Sem foto. O que tem hora gravada, como estava no fim do dia.
  v_fim := (p_dia + 1)::timestamp AT TIME ZONE v_fuso;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'feitapor', CASE WHEN f.funcionarioid IS NOT NULL THEN public.nome_curto(f.nomecompleto) END,
           'feitaem', e.dataenvio,
           'feitasituacao', CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                                 WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                                 WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= v_fim THEN 'Pendente'
                                 ELSE e.statusvalidacao END)
           ORDER BY e.dataenvio, e.entregaid), '[]'::jsonb)
    INTO v_feitas
    FROM public.entregas e
    JOIN public.tarefas t           ON t.tarefaid = e.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = v_conta
   WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
     AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
     AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
          OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
          OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim));

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'pontos', t.pontos,
           'quempegounome', public.nome_curto(p.nomecompleto), 'pegaem', a.aceitoem)
           ORDER BY a.aceitoem, a.aceiteid), '[]'::jsonb)
    INTO v_andam
    FROM public.missoesaceites a
    JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = a.atribuicaoid AND ta.lojaid = p_lojaid AND ta.contaid = v_conta
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = v_conta
    LEFT JOIN public.funcionarios p  ON p.funcionarioid = a.funcionarioid AND p.contaid = v_conta
   WHERE a.contaid = v_conta AND a.dia = p_dia AND a.aceitoem < v_fim
     AND (a.revogadoem IS NULL OR a.revogadoem >= v_fim)
     AND NOT EXISTS (SELECT 1 FROM public.entregas e
                      WHERE e.contaid = v_conta AND e.atribuicaoid = coalesce(a.novaatribuicaoid, a.atribuicaoid)
                        AND e.dataenvio >= (p_dia::timestamp AT TIME ZONE v_fuso) AND e.dataenvio < v_fim
                        AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                             OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= v_fim)
                             OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= v_fim)));

  RETURN jsonb_build_object(
    'dia', p_dia, 'hoje', v_hoje, 'fuso', v_fuso, 'primeirodia', v_primeiro,
    'registrado', false,
    -- "anterior": antes da primeira foto guardada; "semfoto": a rotina não
    -- tirou a foto deste dia (parada, atraso ou lista recuperada).
    'motivo', CASE WHEN EXISTS (SELECT 1 FROM public.diasgerados dg
                                 WHERE dg.contaid = v_conta AND dg.dia < p_dia AND dg.fotodafilaem IS NOT NULL)
                   THEN 'semfoto' ELSE 'anterior' END,
    'feitas', v_feitas, 'emandamento', v_andam);
END;
$function$;

-- fila_no_dia: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.fila_no_dia(p_contaid integer, p_lojaid integer, p_dia date, p_fim timestamp with time zone)
 RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (
    SELECT p_contaid AS conta,
           p_dia AS dia,
           public.fuso_da_conta(p_contaid) AS fuso,
           -- O fim do dia (a meia-noite seguinte), ou infinity para hoje.
           p_fim AS fim,
           coalesce((SELECT nullif(btrim(valor), '')::integer FROM public.configuracoes
                      WHERE contaid = p_contaid AND chave = 'MINUTOS_RODIZIO_ACEITE'), 0) AS rodizio
  )
  SELECT ta.atribuicaoid,
         CASE WHEN a.aceiteid IS NOT NULL THEN coalesce(a.novaatribuicaoid, ta.atribuicaoid) END,
         t.titulo,
         t.pontos,
         ta.tipofrequencia,
         (ta.funcionarioid IS NULL),
         ta.funcionarioid,
         a.funcionarioid,
         public.nome_curto(qp.nomecompleto),
         a.aceitoem,
         CASE
           -- Tarefa Única: entregue num dia, acabou (vale para a tarefa com
           -- dono e para qualquer cópia da compartilhada).
           WHEN ta.tipofrequencia = 'Unica' AND unica.cumprida THEN 'feita'
           WHEN EXISTS (SELECT 1 FROM public.entregas e
                         WHERE e.contaid = ctx.conta
                           AND e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
                           AND e.dataenvio < ctx.fim
                           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                           AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia) THEN 'feita'
           WHEN a.aceiteid IS NOT NULL THEN 'em_andamento'
           ELSE 'para_pegar'
         END,
         -- Atrasada é o que AINDA falta fazer. A Única entregue hoje, mesmo
         -- marcada para ontem, está em "Feitas hoje": não é atrasada.
         (ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
          AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) < ctx.dia
          AND NOT unica.cumprida),
         -- Disponível desde: o começo do dia, ou a hora da missão, ou a hora
         -- agendada — o que for mais tarde. greatest ignora o que for vazio.
         greatest(
           public.instante_na_conta(ctx.conta, ctx.dia, '00:00'::time),
           CASE WHEN ta.horariodisparo IS NOT NULL
                THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.horariodisparo) END,
           CASE WHEN ta.tipofrequencia = 'Unica' AND ta.dataagendamento IS NOT NULL
                     AND public.dia_no_fuso(ta.dataagendamento, ctx.fuso) = ctx.dia
                THEN ta.dataagendamento END,
           -- A hora de liberação também conta: o cronômetro de uma tarefa que
           -- abre às 18h começa às 18h, e não à meia-noite — senão ela nasceria
           -- vermelha, com 18 horas de "parada".
           lib.quando),
         (ctx.rodizio > 0 AND ta.funcionarioid IS NULL),
         now(),
         -- nome_curto(NULL) devolve texto VAZIO, nao nulo: sem este CASE a
         -- coluna vinha '' para toda tarefa sem entrega, e "sem nome" deixava
         -- de ser distinguivel de "nome vazio".
         CASE WHEN ent.funcionarioid IS NOT NULL THEN public.nome_curto(fez.nomecompleto) END,
         ent.dataenvio,
         ent.statusvalidacao,
         (lib.quando IS NULL OR lib.quando <= now()),
         lib.quando,
         ctx.dia,
         ctx.fuso
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
    LEFT JOIN public.funcionarios dono ON dono.funcionarioid = ta.funcionarioid AND dono.contaid = ctx.conta
    LEFT JOIN public.missoesaceites a  ON a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                                      AND a.dia = ctx.dia AND a.aceitoem < ctx.fim
                                      AND (a.revogadoem IS NULL OR a.revogadoem >= ctx.fim)
    LEFT JOIN public.funcionarios qp   ON qp.funcionarioid = a.funcionarioid AND qp.contaid = ctx.conta
    -- Única cumprida (a de tarefa_unica_ja_cumprida, no fim do dia): entregue
    -- por qualquer cópia, em qualquer dia até o fim deste.
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM public.entregas e
          JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid AND c.contaid = ctx.conta
         WHERE e.contaid = ctx.conta
           AND e.dataenvio < ctx.fim
           AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
           AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)) AS cumprida
    ) unica ON true
    -- A entrega que deixou a tarefa "feita". Espelha EXATAMENTE o CASE de
    -- cima, os dois ramos — foi o teste que cobrou isso duas vezes:
    --   Única: qualquer cópia, qualquer dia (igual a tarefa_unica_ja_cumprida);
    --   as demais: só a cópia de quem pegou, e só do dia.
    -- A situação é a do fim do dia: recusada ou estornada DEPOIS dele, ainda
    -- estava pendente ou aprovada.
    LEFT JOIN LATERAL (
      SELECT e.funcionarioid, e.dataenvio,
             CASE WHEN e.statusvalidacao = 'Recusada' THEN 'Pendente'
                  WHEN e.statusvalidacao = 'Estornada' THEN 'Aprovada'
                  WHEN e.statusvalidacao = 'Aprovada' AND e.dataaprovacao >= ctx.fim THEN 'Pendente'
                  ELSE e.statusvalidacao END::varchar AS statusvalidacao
        FROM public.entregas e
       WHERE e.contaid = ctx.conta
         AND e.dataenvio < ctx.fim
         AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
              OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
              OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
         AND (
           (ta.tipofrequencia = 'Unica'
            AND EXISTS (SELECT 1 FROM public.tarefasatribuidas c
                         WHERE c.contaid = ctx.conta AND c.atribuicaoid = e.atribuicaoid
                           AND (c.atribuicaoid = ta.atribuicaoid
                                OR c.origematribuicaoid = ta.atribuicaoid)))
           OR (e.atribuicaoid = coalesce(a.novaatribuicaoid, ta.atribuicaoid)
               AND public.dia_no_fuso(e.dataenvio, ctx.fuso) = ctx.dia)
         )
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 1
    ) ent ON true
    LEFT JOIN public.funcionarios fez  ON fez.funcionarioid = ent.funcionarioid AND fez.contaid = ctx.conta
    -- A hora de liberação, no fuso DA EMPRESA. A conversão é feita aqui, com
    -- o relógio do servidor: o tablet e o celular não opinam.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN ta.disponivelapartir IS NOT NULL
                  THEN public.instante_na_conta(ctx.conta, ctx.dia, ta.disponivelapartir) END AS quando
    ) lib ON true
   WHERE ctx.conta IS NOT NULL
     -- Valia no fim do dia: criada antes dele e não encerrada antes dele.
     AND coalesce(ta.criadaem, '-infinity'::timestamptz) < ctx.fim
     AND (ta.datafimvigencia IS NULL OR ta.encerradaem >= ctx.fim)
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     -- tem_justificativa(..., false), no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.justificativas j
                      WHERE j.contaid = ctx.conta AND j.atribuicaoid = ta.atribuicaoid
                        AND (ta.tipofrequencia = 'Unica' OR j.dia = ctx.dia)
                        AND j.registradoem < ctx.fim
                        AND (j.status IN ('Aceita', 'Pendente')
                             OR (j.status = 'Recusada' AND j.decididoem >= ctx.fim)))
     -- passada_hoje, no fim do dia.
     AND NOT EXISTS (SELECT 1 FROM public.tarefasdodia p
                      WHERE p.contaid = ctx.conta AND p.atribuicaoid = ta.atribuicaoid AND p.dia = ctx.dia
                        AND p.passadapara IS NOT NULL
                        AND coalesce(p.passadaem, '-infinity'::timestamptz) < ctx.fim)
     -- A Única entregue num dia ANTERIOR acabou: não volta na fila de hoje.
     -- Sem isto ela ficava para sempre em "Feitas hoje" (a regra de "feita"
     -- da Única vale para qualquer dia, porque ela só se faz uma vez), e
     -- ainda marcada como atrasada. A TV já tinha esta regra; a fila, não.
     AND NOT (ta.tipofrequencia = 'Unica'
              AND EXISTS (SELECT 1 FROM public.entregas e
                            JOIN public.tarefasatribuidas c ON c.atribuicaoid = e.atribuicaoid
                                                           AND c.contaid = ctx.conta
                           WHERE e.contaid = ctx.conta
                             AND e.dataenvio < ctx.fim
                             AND (e.statusvalidacao IN ('Pendente', 'Aprovada')
                                  OR (e.statusvalidacao = 'Recusada' AND e.datarecusa >= ctx.fim)
                                  OR (e.statusvalidacao = 'Estornada' AND e.dataestorno >= ctx.fim))
                             AND (c.atribuicaoid = ta.atribuicaoid OR c.origematribuicaoid = ta.atribuicaoid)
                             AND public.dia_no_fuso(e.dataenvio, ctx.fuso) < ctx.dia))
     AND (ta.funcionarioid IS NULL
          OR (dono.ativo
              AND public.dia_de_trabalho(dono.diadefolga, dono.domingofolgamensal,
                                         dono.datainicioafastamento, dono.datafimafastamento, ctx.dia)
              AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = ctx.conta AND fl.funcionarioid = ta.funcionarioid
                             AND fl.lojaid = ta.lojaid AND fl.ativo)))
   ORDER BY 12 DESC, 3, 1
$function$;

-- quadro_validacao: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quadro_validacao(p_lojaid integer, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- Ramo do gerente (parte 3): desviado para a versão que lê só a loja dele.
  IF public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL THEN
    RETURN public.quadro_validacao_gerente(p_lojaid, p_de, p_ate, p_offset);
  END IF;
  v_de := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio, x.entregaid), '[]'::jsonb) INTO v_pend
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
$function$;

-- quadro_validacao_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quadro_validacao_gerente(p_lojaid integer, p_de date, p_ate date, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conta integer := public.conta_do_gerente();
  v_hoje  date;
  v_fuso  text;
  v_ate   date;
  v_de    date;
  v_pend  jsonb;
  v_hist  jsonb;
  v_n     integer;
BEGIN
  IF v_conta IS NULL OR NOT public.pode('quadro.ver', p_lojaid) THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  v_hoje := public.hoje_da_conta(v_conta);
  v_fuso := public.fuso_da_conta(v_conta);
  v_ate  := coalesce(p_ate, v_hoje - 1);
  v_de   := coalesce(p_de, v_ate - 6);
  IF v_de > v_ate THEN
    RAISE EXCEPTION 'A data inicial é depois da final.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_ate - v_de > 92 THEN
    RAISE EXCEPTION 'Escolha um período de no máximo 93 dias.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.dataenvio, x.entregaid), '[]'::jsonb) INTO v_pend
    FROM (SELECT e.entregaid, e.tarefaid, e.funcionarioid, e.statusvalidacao, e.dataenvio, e.pontosganhos,
                 e.observacao, CASE WHEN e.fotoaguardaremocaoem IS NULL THEN e.pathfotoevidencia END AS pathfotoevidencia,
                 e.fotoexpiradaem, e.fotoaguardaremocaoem, e.semhorafoto,
                 t.titulo, t.pontos AS pontostarefa, f.nomecompleto AS nome
            FROM public.entregas e
            LEFT JOIN public.tarefas t      ON t.tarefaid = e.tarefaid AND t.contaid = e.contaid
            LEFT JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid AND f.contaid = e.contaid
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid AND e.statusvalidacao = 'Pendente') x;

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
           WHERE e.contaid = v_conta AND e.lojaid = p_lojaid
             AND e.statusvalidacao IN ('Aprovada', 'Recusada', 'Estornada')
             AND e.dataenvio >= (v_de::timestamp AT TIME ZONE v_fuso)
             AND e.dataenvio <  ((v_ate + 1)::timestamp AT TIME ZONE v_fuso)
           ORDER BY e.dataenvio DESC, e.entregaid DESC
          OFFSET greatest(coalesce(p_offset, 0), 0)
           LIMIT 51) x;

  RETURN jsonb_build_object(
    'hoje', v_hoje, 'de', v_de, 'ate', v_ate,
    'pendentes', v_pend,
    'historico', CASE WHEN v_n > 50 THEN v_hist - 50 ELSE v_hist END,
    'temmais', v_n > 50);
END;
$function$;

-- atribuicoes_para_entregar: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_em_sao_paulo(ta.dataagendamento) < hoje.dia) AS atrasada
  FROM public.tarefasatribuidas ta
  CROSS JOIN hoje
  JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
  JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
  WHERE ta.lojaid = p_lojaid
    AND ta.datafimvigencia IS NULL
    AND ta.funcionarioid IS NOT NULL
    AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, hoje.dia)
    AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, hoje.dia, false)
    AND NOT public.passada_hoje(ta.atribuicaoid, hoje.dia)
    AND NOT EXISTS (
      SELECT 1 FROM public.entregas e
      WHERE e.atribuicaoid = ta.atribuicaoid
        AND e.statusvalidacao IN ('Pendente', 'Aprovada')
        AND (ta.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)
    )
    -- Ramo do gerente (parte 3): este caminho é o de sempre; o gerente vai
    -- para a versão dele, que lê só a loja pedida.
    AND NOT (public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL)
  UNION ALL
  SELECT g.* FROM public.atribuicoes_para_entregar_gerente(p_lojaid) g
   WHERE public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
  ORDER BY 5, 2, 1
$function$;

-- atribuicoes_para_entregar_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.atribuicoes_para_entregar_gerente(p_lojaid integer)
 RETURNS TABLE(atribuicaoid integer, titulo character varying, pontos integer, funcionarioid integer, nomecompleto character varying, tipofrequencia character varying, atrasada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT ta.atribuicaoid, t.titulo, t.pontos, f.funcionarioid, f.nomecompleto, ta.tipofrequencia,
         (ta.tipofrequencia = 'Unica'
          AND ta.dataagendamento IS NOT NULL
          AND public.dia_da_conta(ctx.conta, ta.dataagendamento) < public.hoje_da_conta(ctx.conta)) AS atrasada
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.lojaid = p_lojaid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    JOIN public.funcionarios f       ON f.funcionarioid = ta.funcionarioid AND f.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND public.pode('quadro.registrar_entrega', p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.funcionarioid IS NOT NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, public.hoje_da_conta(ctx.conta), public.fuso_da_conta(ctx.conta))
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, public.hoje_da_conta(ctx.conta), false)
     AND NOT public.passada_hoje(ta.atribuicaoid, public.hoje_da_conta(ctx.conta))
     AND NOT EXISTS (
       SELECT 1 FROM public.entregas e
        WHERE e.contaid = ctx.conta AND e.atribuicaoid = ta.atribuicaoid
          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
          AND (ta.tipofrequencia = 'Unica' OR public.dia_da_conta(ctx.conta, e.dataenvio) = public.hoje_da_conta(ctx.conta)))
   ORDER BY f.nomecompleto, t.titulo, ta.atribuicaoid
$function$;

-- painel_inicio: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.painel_inicio(p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje      date := public.dia_em_sao_paulo(now());
  v_mes_ini   date := date_trunc('month', public.dia_em_sao_paulo(now()))::date;
  v_mes_fim   date := (date_trunc('month', public.dia_em_sao_paulo(now())) + interval '1 month - 1 day')::date;
  v_sem_ini   date := (date_trunc('week', public.dia_em_sao_paulo(now())) - interval '7 weeks')::date;
  v_lojas     integer[];
  v_cartoes   jsonb;
  v_tarefas   jsonb;
  v_metadia   jsonb;
  v_metames   jsonb;
  v_vendas    jsonb;
  v_pontos    jsonb;
  v_entregas  jsonb;
  v_ranking   jsonb;
  v_agenda    jsonb;
  v_validar   jsonb;
  v_guia      jsonb;
BEGIN
  IF public.minha_conta() IS NULL THEN
    RAISE EXCEPTION 'Sem acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Lojas consideradas: a escolhida ou todas as ativas (a RLS já limita à conta).
  IF p_lojaid IS NULL THEN
    SELECT coalesce(array_agg(lojaid), '{}') INTO v_lojas FROM public.lojas WHERE ativa;
  ELSE
    SELECT array_agg(lojaid) INTO v_lojas FROM public.lojas WHERE lojaid = p_lojaid;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
  END IF;

  -- Tarefas de hoje: a MESMA fila do tablet, do Quadro e da TV (29/09/2026,
  -- decisão do Wisley — a sexta vez que a mesma pergunta tinha duas
  -- respostas). Antes este cartão tinha regra própria: só tarefa com dono,
  -- contava quem estava de folga e ficava de fora a missão da equipe.
  -- fila_da_loja confere a conta de quem pede; a RLS já limitou v_lojas.
  -- A MESMA conta da TV (progresso_da_fila): a fração "concluídas" conta só
  -- as APROVADAS; o que espera o gestor fica à parte (29/09/2026).
  SELECT public.progresso_da_fila(f.situacao, f.feitasituacao, f.disponivel)
    INTO v_tarefas
    FROM unnest(v_lojas) AS l(lojaid)
    CROSS JOIN LATERAL public.fila_da_loja(l.lojaid) f;

  -- Meta do dia: soma das lojas que têm meta hoje.
  WITH m AS (
    SELECT coalesce(a.valormetadia, md.valormeta) AS meta,
           coalesce(a.valordia, 0)                AS vendido,
           a.apuracaoid IS NOT NULL               AS lancado
      FROM unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = v_hoje
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, v_hoje) md ON true
  )
  SELECT CASE WHEN coalesce(sum(meta) FILTER (WHERE meta > 0), 0) > 0 THEN
           jsonb_build_object(
             'meta',       sum(meta) FILTER (WHERE meta > 0),
             'vendido',    sum(vendido) FILTER (WHERE meta > 0),
             'percentual', round(sum(vendido) FILTER (WHERE meta > 0) * 100 / sum(meta) FILTER (WHERE meta > 0), 1),
             'lancadas',   count(*) FILTER (WHERE meta > 0 AND lancado),
             'lojas',      count(*) FILTER (WHERE meta > 0))
         END
    INTO v_metadia
    FROM m;

  -- Meta do mês: soma das metas do mês das lojas.
  WITH m AS (
    SELECT mp.lojaid, mp.valormetatotal,
           (SELECT coalesce(sum(a.valordia), 0) FROM public.metasdiariasapuracoes a
             WHERE a.lojaid = mp.lojaid AND a.dataapuracao BETWEEN mp.datainicio AND mp.datafim) AS vendido,
           (SELECT count(*) FROM public.dias_sem_lancamento(mp.lojaid, mp.datainicio, v_hoje - 1,
                                                            public.meu_hoje()->>'fuso')) AS semlancar
      FROM public.metasprincipais mp
     WHERE mp.lojaid = ANY (v_lojas) AND v_hoje BETWEEN mp.datainicio AND mp.datafim
  )
  SELECT CASE WHEN count(*) > 0 THEN
           jsonb_build_object(
             'meta',       sum(valormetatotal),
             'vendido',    sum(vendido),
             'percentual', round(sum(vendido) * 100 / nullif(sum(valormetatotal), 0), 1),
             'lojas',      count(*),
             -- Dias (por loja) do mês com meta e sem venda lançada, até ontem.
             'diassemlancamento', sum(semlancar))
         END
    INTO v_metames
    FROM m;

  v_cartoes := jsonb_build_object(
    'tarefas',      v_tarefas,
    'metadia',      v_metadia,
    'metames',      v_metames,
    'validar',      (SELECT count(*) FROM public.entregas
                      WHERE lojaid = ANY (v_lojas) AND statusvalidacao = 'Pendente'),
    'agendahoje',   (SELECT count(*) FROM public.agendamentos
                      WHERE lojaid = ANY (v_lojas) AND statusagendamento <> 'Cancelado'
                        AND public.dia_em_sao_paulo(dataevento) = v_hoje),
    'comunicados',  (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                               'pessoas',     count(DISTINCT s.funcionarioid))
                       FROM public.documentosassinaturas s
                       JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                       JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                      WHERE s.statusassinatura = 'Pendente'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'onboarding',   (SELECT count(*) FROM public.onboardingstatus o
                       JOIN public.funcionarios f ON f.funcionarioid = o.funcionarioid AND f.ativo
                      WHERE o.statusworkflow = 'Em andamento'
                        AND (p_lojaid IS NULL OR EXISTS (
                              SELECT 1 FROM public.funcionarioslojas fl
                               WHERE fl.funcionarioid = o.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
    'solicitacoes', (SELECT count(*) FROM public.solicitacoesinternas
                      WHERE lojaid = ANY (v_lojas) AND status IN ('Aberta', 'Em andamento')),
    'justificativas', (SELECT count(*) FROM public.justificativas
                        WHERE lojaid = ANY (v_lojas) AND status = 'Pendente'));

  -- Vendas do mês, dia a dia, contra a meta (soma das lojas).
  WITH dias AS (
    SELECT g::date AS d FROM generate_series(v_mes_ini, v_mes_fim, interval '1 day') g
  ),
  linhas AS (
    SELECT d.d,
           sum(a.valordia)                            AS vendido,
           sum(coalesce(a.valormetadia, md.valormeta)) AS meta
      FROM dias d
      CROSS JOIN unnest(v_lojas) AS l(lojaid)
      LEFT JOIN public.metasdiariasapuracoes a ON a.lojaid = l.lojaid AND a.dataapuracao = d.d
      LEFT JOIN LATERAL public.meta_do_dia(l.lojaid, d.d) md ON true
     GROUP BY d.d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('dia', d, 'vendido', vendido, 'meta', meta) ORDER BY d), '[]'::jsonb)
    INTO v_vendas
    FROM linhas;

  -- Pontos por semana (últimas 8, começando na segunda), pelo livro.
  -- Entraram: aprovações e bônus, já descontados os estornos.
  -- Saíram: resgates, já descontados cancelamentos e estornos de resgate.
  WITH semanas AS (
    SELECT g::date AS ini FROM generate_series(v_sem_ini, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  mov AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(mv.datamovimento))::date AS ini, mv.tipo, mv.pontos
      FROM public.movimentospontos mv
     WHERE mv.datamovimento >= (v_sem_ini::timestamp AT TIME ZONE 'America/Sao_Paulo')
       AND (p_lojaid IS NULL OR mv.lojaid = p_lojaid)
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',   s.ini,
           'entraram', coalesce((SELECT sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('aprovacao', 'estorno_entrega', 'bonus', 'estorno_bonus')), 0),
           'sairam',   coalesce((SELECT -sum(pontos) FROM mov
                                  WHERE mov.ini = s.ini
                                    AND tipo IN ('resgate', 'cancelamento_resgate', 'estorno_resgate')), 0))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_pontos
    FROM semanas s;

  -- Entregas aprovadas x recusadas por semana do mês (pelo dia da decisão).
  WITH semanas AS (
    SELECT g::date AS ini
      FROM generate_series(date_trunc('week', v_mes_ini)::date, date_trunc('week', v_hoje)::date, interval '1 week') g
  ),
  dec AS (
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.dataaprovacao))::date AS ini, 'a'::text AS r
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Aprovada'
       AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN v_mes_ini AND v_hoje
    UNION ALL
    SELECT date_trunc('week', public.dia_em_sao_paulo(e.datarecusa))::date, 'r'
      FROM public.entregas e
     WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Recusada'
       AND public.dia_em_sao_paulo(e.datarecusa) BETWEEN v_mes_ini AND v_hoje
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana',    greatest(s.ini, v_mes_ini),
           'aprovadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'a'),
           'recusadas', (SELECT count(*) FROM dec WHERE dec.ini = s.ini AND r = 'r'))
           ORDER BY s.ini), '[]'::jsonb)
    INTO v_entregas
    FROM semanas s;

  -- Top 5 do mês (pontos aprovados no mês).
  SELECT coalesce(jsonb_agg(jsonb_build_object('nome', r.nomecompleto, 'pontos', r.pontos, 'entregas', r.entregas)
                            ORDER BY r.pontos DESC, r.nomecompleto, r.funcionarioid), '[]'::jsonb)
    INTO v_ranking
    FROM (SELECT * FROM public.ranking_pontos(v_mes_ini, v_hoje, p_lojaid) LIMIT 5) r;

  -- Próximos agendamentos: hora, tipo e responsável (sem dados do cliente).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', s.dataevento, 'tipo', s.tipoevento, 'responsavel', s.responsavel, 'loja', s.loja)
           ORDER BY s.dataevento, s.agendamentoid), '[]'::jsonb)
    INTO v_agenda
    FROM (
      SELECT a.agendamentoid, a.dataevento, a.tipoevento, l.nome AS loja,
             split_part(btrim(f.nomecompleto), ' ', 1) AS responsavel
        FROM public.agendamentos a
        JOIN public.lojas l             ON l.lojaid = a.lojaid
        LEFT JOIN public.funcionarios f ON f.funcionarioid = a.funcionarioid
       WHERE a.lojaid = ANY (v_lojas) AND a.statusagendamento = 'Confirmado'
         AND a.dataevento >= now() - interval '1 hour'
       ORDER BY a.dataevento, a.agendamentoid
       LIMIT 5
    ) s;

  -- Últimas entregas esperando validação.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', s.titulo, 'pessoa', s.pessoa, 'pontos', s.pontos, 'enviadaem', s.dataenvio, 'loja', s.loja)
           ORDER BY s.dataenvio DESC, s.entregaid DESC), '[]'::jsonb)
    INTO v_validar
    FROM (
      SELECT t.titulo, e.pontosganhos AS pontos, e.dataenvio, e.entregaid, l.nome AS loja,
             public.nome_curto(f.nomecompleto) AS pessoa
        FROM public.entregas e
        JOIN public.tarefas t      ON t.tarefaid = e.tarefaid
        JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
        JOIN public.lojas l        ON l.lojaid = e.lojaid
       WHERE e.lojaid = ANY (v_lojas) AND e.statusvalidacao = 'Pendente'
       ORDER BY e.dataenvio DESC, e.entregaid DESC
       LIMIT 5
    ) s;

  -- Guia de primeiros passos (vale para a conta toda).
  v_guia := jsonb_build_object(
    'loja',    EXISTS (SELECT 1 FROM public.lojas WHERE ativa),
    'equipe',  EXISTS (SELECT 1 FROM public.funcionarios f
                         JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.ativo
                        WHERE f.ativo),
    'tarefas', EXISTS (SELECT 1 FROM public.tarefasatribuidas ta
                         JOIN public.tarefas t ON t.tarefaid = ta.tarefaid
                        WHERE ta.datafimvigencia IS NULL AND t.sistema IS NULL),
    'meta',    EXISTS (SELECT 1 FROM public.metasdiariasmodelos WHERE valormeta > 0)
               OR EXISTS (SELECT 1 FROM public.metasprincipais),
    'tv',      EXISTS (SELECT 1 FROM public.linkstv WHERE revogadoem IS NULL));

  RETURN jsonb_build_object(
    'hoje',         v_hoje,
    'atualizadoem', now(),
    'cartoes',      v_cartoes,
    'vendas',       v_vendas,
    'pontos',       v_pontos,
    'entregas',     v_entregas,
    'ranking',      v_ranking,
    'agenda',       v_agenda,
    'validar',      v_validar,
    'guia',         v_guia,
    -- Avisos (calculados na hora, sem rotina).
    'avisos', jsonb_build_object(
      -- VENDA DE ONTEM NÃO LANÇADA (29/09/2026): loja ativa que tinha meta
      -- ontem (a especial da data ou o modelo do dia da semana, com valor) e
      -- não tem lançamento de ontem. Loja que não abre tem meta zero naquele
      -- dia (ou uma especial com valor 0 no feriado) e não avisa. Só ontem:
      -- não acumula. Todas as lojas que a pessoa enxerga, com ou sem filtro.
      'vendaontem', (SELECT coalesce(jsonb_agg(jsonb_build_object('lojaid', l.lojaid, 'loja', l.nome)
                                               ORDER BY l.nome, l.lojaid), '[]'::jsonb)
                       FROM public.lojas l
                       CROSS JOIN LATERAL (SELECT (public.meu_hoje()->>'hoje')::date - 1 AS dia) o
                      WHERE l.ativa
                        -- A MESMA regra da faixa do mês (dias_sem_lancamento).
                        AND EXISTS (SELECT 1 FROM public.dias_sem_lancamento(l.lojaid, o.dia, o.dia,
                                                                               public.meu_hoje()->>'fuso'))),
      'agendamentospassados', (SELECT count(*) FROM public.agendamentos
                                WHERE lojaid = ANY (v_lojas) AND statusagendamento = 'Confirmado'
                                  AND dataevento < now() - interval '1 hour'),
      'comunicados24h', (SELECT jsonb_build_object('comunicados', count(DISTINCT s.documentoid),
                                                   'pessoas',     count(DISTINCT s.funcionarioid))
                           FROM public.documentosassinaturas s
                           JOIN public.documentos d   ON d.documentoid = s.documentoid AND d.status = 'Publicado'
                           JOIN public.funcionarios f ON f.funcionarioid = s.funcionarioid AND f.ativo
                          WHERE s.statusassinatura = 'Pendente'
                            AND s.dataenvio < now() - interval '24 hours'
                            AND (p_lojaid IS NULL OR EXISTS (
                                  SELECT 1 FROM public.funcionarioslojas fl
                                   WHERE fl.funcionarioid = s.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo))),
      'livro', (SELECT CASE WHEN r.resultado = 'ok' THEN 'ok'
                            WHEN r.detalhe ? 'diferencas' THEN 'diferenca' ELSE 'erro' END
                  FROM public.rotinasexecucoes r
                 WHERE r.rotina = 'conferencia_livro'
                 ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1)),
    -- Última geração da lista de hoje (para "rodou sozinha às 00:05 ✓").
    'rotina', (SELECT jsonb_build_object('quando', coalesce(r.terminadoem, r.iniciadoem),
                                         'resultado', r.resultado, 'origem', r.origem)
                 FROM public.rotinasexecucoes r
                WHERE r.rotina = 'lista_do_dia' AND r.referencia = v_hoje
                ORDER BY r.iniciadoem DESC, r.execucaoid DESC LIMIT 1));
END;
$function$;

-- visao_mural: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.visao_mural(p_contaid integer, p_lojaid integer, p_funcionarioid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre o mural da loja.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Quem lê tem de ser gente ativa DESTA loja.
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                   JOIN public.funcionarioslojas fl
                     ON fl.funcionarioid = f.funcionarioid AND fl.contaid = p_contaid AND fl.ativo
                  WHERE f.funcionarioid = p_funcionarioid AND f.contaid = p_contaid AND f.ativo
                    AND fl.lojaid = p_lojaid) THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'assinaturaid', s.assinaturaid,
             'titulo',       d.titulo,
             'conteudo',     d.conteudo,
             'pontos',       d.pontosporciencia,
             'quando',       s.dataenvio) ORDER BY s.dataenvio, s.assinaturaid), '[]'::jsonb)
      FROM public.documentosassinaturas s
      JOIN public.documentos d ON d.documentoid = s.documentoid AND d.contaid = p_contaid
     WHERE s.contaid = p_contaid
       AND s.funcionarioid = p_funcionarioid
       -- SÓ o que falta ler. Nada de histórico: o tablet é compartilhado.
       AND s.statusassinatura = 'Pendente'
       AND d.status = 'Publicado');
END;
$function$;

-- tarefas_nao_pegas: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_nao_pegas(p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(atribuicaoid integer, lojaid integer, loja character varying, titulo character varying, pontos integer, atribuidos text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.minha_conta() AS conta,
                      public.hoje_da_conta(public.minha_conta()) AS dia,
                      public.fuso_da_conta(public.minha_conta()) AS fuso)
  SELECT ta.atribuicaoid, ta.lojaid, l.nome, t.titulo, t.pontos,
         coalesce((SELECT string_agg(public.nome_curto(f.nomecompleto), ', ' ORDER BY f.nomecompleto)
                     FROM public.tarefascandidatos c
                     JOIN public.funcionarios f ON f.funcionarioid = c.funcionarioid AND f.contaid = ctx.conta
                    WHERE c.contaid = ctx.conta AND c.atribuicaoid = ta.atribuicaoid),
                  'toda a equipe da loja')
    FROM ctx
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.funcionarioid IS NULL
    JOIN public.lojas l              ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta AND l.ativa
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
                                    AND coalesce(t.ativa, true)
   WHERE ctx.conta IS NOT NULL
     AND (p_lojaid IS NULL OR ta.lojaid = p_lojaid)
     AND ta.datafimvigencia IS NULL
     AND ta.origematribuicaoid IS NULL
     AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, ctx.dia, ctx.fuso)
     AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, ctx.dia, false)
     AND NOT (ta.tipofrequencia = 'Unica' AND public.tarefa_unica_ja_cumprida(ctx.conta, ta.atribuicaoid))
     AND NOT EXISTS (SELECT 1 FROM public.missoesaceites a
                      WHERE a.contaid = ctx.conta AND a.atribuicaoid = ta.atribuicaoid
                        AND a.dia = ctx.dia AND a.revogadoem IS NULL)
   ORDER BY l.nome, t.titulo, ta.atribuicaoid
$function$;

-- quem_trabalha_hoje: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.quem_trabalha_hoje_gerente(p_lojaid)
           ELSE (
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto, f.funcionarioid), '[]'::jsonb)
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
   WHERE f.ativo
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.dia_em_sao_paulo(now()))
           ) END
$function$;

-- quem_trabalha_hoje_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.quem_trabalha_hoje_gerente(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta)
  SELECT coalesce(jsonb_agg(jsonb_build_object('funcionarioid', f.funcionarioid, 'nome', f.nomecompleto)
                            ORDER BY f.nomecompleto, f.funcionarioid), '[]'::jsonb)
    FROM ctx
    JOIN public.funcionarios f       ON f.contaid = ctx.conta AND f.ativo
    JOIN public.funcionarioslojas fl ON fl.funcionarioid = f.funcionarioid AND fl.lojaid = p_lojaid AND fl.ativo
                                    AND fl.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)
     AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal, f.datainicioafastamento,
                                f.datafimafastamento, public.hoje_da_conta(ctx.conta))
$function$;

-- tarefas_de_folga_hoje: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
           -- Ramo do gerente (parte 3): a versão dele lê só a loja pedida.
           WHEN public.minha_conta() IS NULL AND public.conta_do_gerente() IS NOT NULL
             THEN public.tarefas_de_folga_hoje_gerente(p_lojaid)
           ELSE (
  WITH hoje AS (SELECT public.dia_em_sao_paulo(now()) AS dia),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(public.minha_conta(), hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e, hoje
                                    WHERE e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = hoje.dia)))
           ORDER BY f.nomecompleto, t.titulo, it.atribuicaoid), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara
           ) END
$function$;

-- tarefas_de_folga_hoje_gerente: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_de_folga_hoje_gerente(p_lojaid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.conta_do_gerente() AS conta),
  hoje AS (SELECT public.hoje_da_conta(ctx.conta) AS dia, ctx.conta FROM ctx
            WHERE ctx.conta IS NOT NULL AND public.pode('quadro.passar_folga', p_lojaid)),
  itens AS (
    SELECT c.atribuicaoid, c.funcionarioid, c.tarefaid, c.tipofrequencia, c.pontos, c.situacao, i.passadapara, hoje.conta, hoje.dia
      FROM hoje CROSS JOIN LATERAL public.lista_candidatos(hoje.conta, hoje.dia) c
      LEFT JOIN public.tarefasdodia i ON i.atribuicaoid = c.atribuicaoid AND i.dia = hoje.dia AND i.contaid = hoje.conta
     WHERE c.lojaid = p_lojaid AND c.situacao IN ('folga', 'afastamento')
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'atribuicaoid', it.atribuicaoid,
           'titulo',       t.titulo,
           'pontos',       it.pontos,
           'pessoa',       f.nomecompleto,
           'motivo',       it.situacao,
           'passadapara',  p.nomecompleto,
           'entregue',     EXISTS (SELECT 1 FROM public.entregas e
                                    WHERE e.contaid = it.conta AND e.atribuicaoid = it.atribuicaoid
                                      AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                                      AND (it.tipofrequencia = 'Unica' OR public.dia_da_conta(it.conta, e.dataenvio) = it.dia)))
           ORDER BY f.nomecompleto, t.titulo, it.atribuicaoid), '[]'::jsonb)
    FROM itens it
    JOIN public.tarefas t      ON t.tarefaid = it.tarefaid AND t.contaid = it.conta
    JOIN public.funcionarios f ON f.funcionarioid = it.funcionarioid AND f.contaid = it.conta
    LEFT JOIN public.funcionarios p ON p.funcionarioid = it.passadapara AND p.contaid = it.conta
$function$;

-- pendencias_da_pessoa: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.pendencias_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH lim AS (
    SELECT greatest(p_de, p_ate - 92) AS ini,
           least(p_ate, public.dia_em_sao_paulo(now()) - 1) AS fim
  ),
  gerados AS (
    SELECT dg.dia FROM public.diasgerados dg, lim
     WHERE dg.contaid = public.minha_conta() AND dg.dia BETWEEN lim.ini AND lim.fim
  ),
  itens AS (
    -- Dias com lista congelada.
    SELECT i.dia, i.atribuicaoid, i.tipofrequencia, t.titulo, i.pontos, l.nome AS loja
      FROM public.tarefasdodia i
      JOIN gerados g           ON g.dia = i.dia
      JOIN public.tarefas t    ON t.tarefaid = i.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = i.lojaid
     WHERE i.funcionarioid = p_funcionarioid
       AND i.situacao = 'devida'
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = i.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND (i.tipofrequencia = 'Unica' OR public.dia_em_sao_paulo(e.dataenvio) = i.dia))
    UNION ALL
    -- Dias sem lista: regra do cadastro.
    SELECT g.d::date, ta.atribuicaoid, ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t      ON t.tarefaid = ta.tarefaid
      JOIN public.funcionarios f ON f.funcionarioid = ta.funcionarioid
      LEFT JOIN public.lojas l   ON l.lojaid = ta.lojaid
      CROSS JOIN lim
      CROSS JOIN LATERAL generate_series(
        greatest(lim.ini, coalesce(public.dia_em_sao_paulo(ta.dataatribuicao), lim.ini),
                 coalesce(ta.datainiciovigencia, lim.ini)),
        least(lim.fim, coalesce(ta.datafimvigencia - 1, lim.fim)),
        interval '1 day') AS g(d)
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia IN ('Diaria', 'Semanal', 'Mensal')
       AND g.d::date NOT IN (SELECT dia FROM gerados)
       AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, g.d::date)
       AND public.dia_de_trabalho(f.diadefolga, f.domingofolgamensal,
                                  f.datainicioafastamento, f.datafimafastamento, g.d::date)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada')
                          AND public.dia_em_sao_paulo(e.dataenvio) = g.d::date)
    UNION ALL
    SELECT public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)), ta.atribuicaoid,
           ta.tipofrequencia, t.titulo, t.pontos, l.nome
      FROM public.tarefasatribuidas ta
      JOIN public.tarefas t    ON t.tarefaid = ta.tarefaid
      LEFT JOIN public.lojas l ON l.lojaid = ta.lojaid
      CROSS JOIN lim
     WHERE ta.funcionarioid = p_funcionarioid
       AND ta.origematribuicaoid IS NULL
       AND ta.tipofrequencia = 'Unica'
       AND ta.datafimvigencia IS NULL
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) BETWEEN lim.ini AND lim.fim
       AND public.dia_em_sao_paulo(coalesce(ta.dataagendamento, ta.dataatribuicao)) NOT IN (SELECT dia FROM gerados)
       AND NOT EXISTS (SELECT 1 FROM public.entregas e
                        WHERE e.atribuicaoid = ta.atribuicaoid
                          AND e.statusvalidacao IN ('Pendente', 'Aprovada'))
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'dia', i.dia, 'atribuicaoid', i.atribuicaoid, 'titulo', i.titulo, 'pontos', i.pontos, 'loja', i.loja,
           'justificativa', (SELECT j.status FROM public.justificativas j
                              WHERE j.atribuicaoid = i.atribuicaoid
                                AND (i.tipofrequencia = 'Unica' OR j.dia = i.dia)
                              ORDER BY j.justificativaid DESC LIMIT 1))
           ORDER BY i.dia DESC, i.titulo, i.atribuicaoid), '[]'::jsonb)
    FROM itens i
   WHERE NOT public.tem_justificativa(i.atribuicaoid, i.tipofrequencia, i.dia, true)
$function$;

-- tarefas_pegas_da_pessoa: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.tarefas_pegas_da_pessoa(p_funcionarioid integer, p_de date, p_ate date)
 RETURNS TABLE(dia date, titulo character varying, pontos integer, loja character varying, entregue boolean, revogadoem timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ctx AS (SELECT public.minha_conta() AS conta)
  SELECT a.dia, t.titulo, t.pontos, l.nome,
         EXISTS (SELECT 1 FROM public.entregas e
                  WHERE e.contaid = ctx.conta AND e.atribuicaoid = a.novaatribuicaoid
                    AND e.statusvalidacao IN ('Pendente', 'Aprovada')),
         a.revogadoem
    FROM ctx
    JOIN public.missoesaceites a     ON a.contaid = ctx.conta AND a.funcionarioid = p_funcionarioid
    JOIN public.tarefasatribuidas ta ON ta.contaid = ctx.conta AND ta.atribuicaoid = a.novaatribuicaoid
    JOIN public.tarefas t            ON t.tarefaid = ta.tarefaid AND t.contaid = ctx.conta
    LEFT JOIN public.lojas l         ON l.lojaid = ta.lojaid AND l.contaid = ctx.conta
   WHERE ctx.conta IS NOT NULL
     AND a.novaatribuicaoid IS NOT NULL
     AND a.dia BETWEEN p_de AND p_ate
   ORDER BY a.dia DESC, t.titulo, a.aceiteid
$function$;

-- ranking_pontos: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.ranking_pontos(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS TABLE(funcionarioid integer, nomecompleto character varying, pontos bigint, entregas bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid, f.nomecompleto, sum(e.pontosganhos)::bigint, count(*)::bigint
  FROM public.entregas e
  JOIN public.funcionarios f ON f.funcionarioid = e.funcionarioid
  WHERE e.statusvalidacao = 'Aprovada'
    AND public.dia_em_sao_paulo(e.dataaprovacao) BETWEEN p_de AND p_ate
    AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
  GROUP BY f.funcionarioid, f.nomecompleto
  ORDER BY 3 DESC, 2, 1
$function$;

-- analise_de_tarefas: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.analise_de_tarefas(p_de date, p_ate date, p_lojaid integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ent AS (
    SELECT e.tarefaid,
           count(*) FILTER (WHERE e.statusvalidacao = 'Aprovada')  AS aprovadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Recusada')  AS recusadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Estornada') AS estornadas,
           count(*) FILTER (WHERE e.statusvalidacao = 'Pendente')  AS pendentes
      FROM public.entregas e
     WHERE e.atribuicaoid IS NOT NULL
       AND public.dia_em_sao_paulo(e.dataenvio) BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR e.lojaid = p_lojaid)
     GROUP BY e.tarefaid
  ),
  jus AS (
    SELECT ta.tarefaid, count(*) AS naoseaplica
      FROM public.justificativas j
      JOIN public.tarefasatribuidas ta ON ta.atribuicaoid = j.atribuicaoid
     WHERE j.status = 'Aceita'
       AND j.dia BETWEEN p_de AND p_ate
       AND (p_lojaid IS NULL OR j.lojaid = p_lojaid)
     GROUP BY ta.tarefaid
  ),
  juntos AS (
    SELECT coalesce(ent.tarefaid, jus.tarefaid) AS tarefaid,
           coalesce(aprovadas, 0) AS aprovadas, coalesce(recusadas, 0) AS recusadas,
           coalesce(estornadas, 0) AS estornadas, coalesce(pendentes, 0) AS pendentes,
           coalesce(naoseaplica, 0) AS naoseaplica
      FROM ent FULL JOIN jus ON jus.tarefaid = ent.tarefaid
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'aprovadas', j.aprovadas, 'recusadas', j.recusadas,
           'estornadas', j.estornadas, 'pendentes', j.pendentes, 'naoseaplica', j.naoseaplica)
           ORDER BY j.recusadas + j.estornadas + j.naoseaplica DESC, t.titulo, t.tarefaid), '[]'::jsonb)
    FROM juntos j
    JOIN public.tarefas t ON t.tarefaid = j.tarefaid
$function$;

-- situacao_dos_acessos: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
 RETURNS TABLE(funcionarioid integer, temacesso boolean, nuncaentrou boolean, semsenha boolean, sempin boolean, codigopendente boolean, codigoexpiraem timestamp with time zone, redefinidoem timestamp with time zone, codigogeradoem timestamp with time zone, codigogeradopor text, codigoreimprimivel boolean, folhaemitidaem timestamp with time zone, folhaemitidapor text, folhas integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT f.funcionarioid,
         cu.userid IS NOT NULL,
         cu.userid IS NOT NULL AND f.primeiroacessoem IS NULL,
         f.senhahashapp IS NULL,
         f.pinhash IS NULL,
         k.codigoid IS NOT NULL,
         k.expiraem,
         f.acessoredefinidoem,
         k.criadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = k.criadopor),
         k.codigocifrado IS NOT NULL,
         fa.emitidaem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = fa.emitidapor),
         coalesce(fa.total, 0)::integer
    FROM public.funcionarios f
    LEFT JOIN public.contasusuarios cu
           ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
    LEFT JOIN LATERAL (SELECT codigoid, expiraem, criadoem, criadopor, codigocifrado FROM public.codigosacesso k2
                        WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                          AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                        ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC, x.folhaid DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
   ORDER BY f.funcionarioid
$function$;

-- folha_de_acesso: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.folha_de_acesso(p_contaid integer, p_funcionarioids integer[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'conta',  c.nomefantasia,
    'codigoempresa', c.codigo,
    'pessoas', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'funcionarioid', f.funcionarioid,
               'nome',          f.nomecompleto,
               'cargo',         f.cargo,
               'cpf',           f.cpf,
               'ativo',         f.ativo,
               'lojas',         coalesce((SELECT jsonb_agg(l.nome ORDER BY l.nome)
                                            FROM public.funcionarioslojas fl
                                            JOIN public.lojas l ON l.contaid = fl.contaid AND l.lojaid = fl.lojaid
                                           WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid
                                             AND fl.ativo AND l.ativa), '[]'::jsonb),
               'temacesso',     cu.userid IS NOT NULL,
               'jaentrou',      (f.senhahashapp IS NOT NULL OR f.pinhash IS NOT NULL),
               'codigo',        CASE WHEN k.codigoid IS NOT NULL THEN jsonb_build_object(
                                  'codigoid', k.codigoid, 'cifrado', k.codigocifrado,
                                  'expiraem', k.expiraem, 'criadoem', k.criadoem) END
             ) ORDER BY f.nomecompleto, f.funcionarioid)
        FROM public.funcionarios f
        LEFT JOIN public.contasusuarios cu
               ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
        LEFT JOIN LATERAL (SELECT k2.codigoid, k2.codigocifrado, k2.expiraem, k2.criadoem
                             FROM public.codigosacesso k2
                            WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                              AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                            ORDER BY k2.criadoem DESC, k2.codigoid DESC LIMIT 1) k ON true
       WHERE f.contaid = c.contaid AND f.funcionarioid = ANY (p_funcionarioids)), '[]'::jsonb))
    FROM public.contas c
   WHERE c.contaid = p_contaid AND public.bot_contexto_confiavel()
$function$;

-- rotinas_resumo_admin: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.rotinas_resumo_admin()
 RETURNS TABLE(contaid integer, rotina text, ultimaem timestamp with time zone, situacao text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.eh_admin_geral() THEN
    RAISE EXCEPTION 'Só o administrador geral vê este resumo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
    SELECT DISTINCT ON (r.contaid, r.rotina)
           r.contaid, r.rotina::text, coalesce(r.terminadoem, r.iniciadoem),
           CASE WHEN r.resultado = 'ok' THEN 'ok'
                WHEN r.detalhe ? 'diferencas' THEN 'diferenca'
                ELSE 'erro' END
      FROM public.rotinasexecucoes r
     ORDER BY r.contaid, r.rotina, r.iniciadoem DESC, r.execucaoid DESC;
END;
$function$;

-- eu_resgates: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.eu_resgates(p_contaid integer, p_funcionarioid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'resgateid', r.resgateid,
             'nome',      p.nome,
             'pontos',    r.pontosgastos,
             'quando',    r.datasolicitacao,
             'status',    r.status) ORDER BY r.datasolicitacao DESC, r.resgateid DESC), '[]'::jsonb)
      FROM public.resgates r
      JOIN public.produtosloja p ON p.produtoid = r.produtoid AND p.contaid = p_contaid
     WHERE r.contaid = p_contaid AND r.funcionarioid = p_funcionarioid
       AND r.datasolicitacao > now() - interval '90 days');
END;
$function$;

-- eu_tarefas: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.eu_tarefas(p_contaid integer, p_funcionarioid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje date := public.hoje_da_conta(p_contaid);
  v_fuso text := public.fuso_da_conta(p_contaid);
BEGIN
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'atribuicaoid', x.atribuicaoid,
             'titulo',       x.titulo,
             'pontos',       x.pontos,
             'loja',         x.loja,
             'pegaem',       x.pegaem,
             'situacao',     x.situacao,
             -- Enquanto não libera, a tela do celular mostra "a partir das 15h".
             'liberaas',     x.liberaas,
             'liberada',     x.liberada) ORDER BY x.pegaem NULLS LAST, x.titulo, x.atribuicaoid), '[]'::jsonb)
      FROM (
        SELECT ta.atribuicaoid, t.titulo, t.pontos, l.nome AS loja, a.aceitoem AS pegaem,
               CASE WHEN e.entregaid IS NULL THEN 'a_fazer'
                    WHEN e.statusvalidacao = 'Pendente'  THEN 'esperando'
                    WHEN e.statusvalidacao = 'Aprovada'  THEN 'aprovada'
                    ELSE 'recusada' END AS situacao,
               -- A hora de liberação, no fuso da EMPRESA e com o relógio do
               -- servidor. O celular não converte nada.
               CASE WHEN ta.disponivelapartir IS NOT NULL
                    THEN public.instante_na_conta(p_contaid, v_hoje, ta.disponivelapartir) END AS liberaas,
               (ta.disponivelapartir IS NULL
                OR public.instante_na_conta(p_contaid, v_hoje, ta.disponivelapartir) <= now()) AS liberada
          FROM public.tarefasatribuidas ta
          JOIN public.tarefas t  ON t.tarefaid = ta.tarefaid AND t.contaid = p_contaid
                                AND coalesce(t.ativa, true)
          -- Loja desativada não gera mais tarefa: era LEFT JOIN e passava.
          JOIN public.lojas l    ON l.lojaid = ta.lojaid AND l.contaid = p_contaid AND l.ativa
          JOIN public.funcionarios fu ON fu.funcionarioid = p_funcionarioid AND fu.contaid = p_contaid
          LEFT JOIN public.missoesaceites a
                 ON a.contaid = p_contaid AND a.novaatribuicaoid = ta.atribuicaoid AND a.revogadoem IS NULL
          LEFT JOIN LATERAL (
            SELECT e2.entregaid, e2.statusvalidacao FROM public.entregas e2
             WHERE e2.contaid = p_contaid AND e2.atribuicaoid = ta.atribuicaoid
               AND (ta.tipofrequencia = 'Unica' OR public.dia_no_fuso(e2.dataenvio, v_fuso) = v_hoje)
             ORDER BY e2.dataenvio DESC, e2.entregaid DESC LIMIT 1) e ON true
         WHERE ta.contaid = p_contaid
           AND ta.funcionarioid = p_funcionarioid
           AND ta.datafimvigencia IS NULL
           AND public.tarefa_cai_no_dia(ta.tipofrequencia, ta.valorfrequencia, ta.dataagendamento, v_hoje, v_fuso)
           AND NOT public.tem_justificativa(ta.atribuicaoid, ta.tipofrequencia, v_hoje, false)
           AND NOT public.passada_hoje(ta.atribuicaoid, v_hoje)
           -- A CÓPIA de quem pegou uma tarefa compartilhada é daquele dia: o
           -- aceite vale só no dia, e depois dele ninguém entrega por ela.
           -- Cópia de outro dia só aparece no dia em que o gestor a recusou
           -- ou estornou (para a pessoa ver que precisa refazer — refazer é
           -- aceitar de novo no tablet, e isso gera outra cópia). Sem isto, a
           -- cópia estornada ficava "recusada" no celular para sempre.
           AND (ta.origematribuicaoid IS NULL
                OR public.dia_no_fuso(ta.dataagendamento, v_fuso) = v_hoje
                OR EXISTS (SELECT 1 FROM public.entregas e4
                            WHERE e4.contaid = p_contaid AND e4.atribuicaoid = ta.atribuicaoid
                              AND public.dia_no_fuso(coalesce(e4.dataestorno, e4.datarecusa), v_fuso) = v_hoje))
           -- A Única entregue num dia ANTERIOR acabou: não volta hoje (a
           -- mesma regra da fila do tablet e da TV).
           AND NOT (ta.tipofrequencia = 'Unica'
                    AND EXISTS (SELECT 1 FROM public.entregas e3
                                 WHERE e3.contaid = p_contaid AND e3.atribuicaoid = ta.atribuicaoid
                                   AND e3.statusvalidacao IN ('Pendente', 'Aprovada')
                                   AND public.dia_no_fuso(e3.dataenvio, v_fuso) < v_hoje))
           -- Folga, afastamento e vínculo com a loja: as mesmas condições da
           -- fila do tablet.
           AND public.dia_de_trabalho(fu.diadefolga, fu.domingofolgamensal,
                                      fu.datainicioafastamento, fu.datafimafastamento, v_hoje)
           AND EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                        WHERE fl.contaid = p_contaid AND fl.funcionarioid = p_funcionarioid
                          AND fl.lojaid = ta.lojaid AND fl.ativo)
      ) x);
END;
$function$;

-- anexos_admin: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.anexos_admin()
 RETURNS TABLE(anexoid integer, contaid integer, redeid integer, nomearquivo character varying, tipo character varying, tamanho integer, enviadoem timestamp with time zone, enviadopor text, removidoem timestamp with time zone, removidopor text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.eh_admin_geral() THEN
    RAISE EXCEPTION 'Só o administrador geral.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT a.anexoid, a.contaid, a.redeid, a.nomearquivo, a.tipo, a.tamanho, a.enviadoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = a.enviadopor),
         a.removidoem,
         (SELECT u.email::text FROM auth.users u WHERE u.id = a.removidopor)
    FROM public.anexosadmin a
   ORDER BY a.enviadoem DESC, a.anexoid DESC;
END;
$function$;

-- lista_do_dia_gerar: parte da versão viva; muda só a ordenação.
CREATE OR REPLACE FUNCTION public.lista_do_dia_gerar(p_contaid integer, p_dia date, p_hoje date, p_recuperado boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_novos      integer := 0;
  v_cancelados integer := 0;
  v_ajustados  integer := 0;
BEGIN
  IF p_dia > p_hoje THEN
    RAISE EXCEPTION 'Não se gera lista de um dia que ainda não chegou.' USING ERRCODE = 'check_violation';
  END IF;
  -- Uma geração por conta de cada vez (duas rodadas simultâneas esperam).
  PERFORM pg_advisory_xact_lock(7311, p_contaid);

  INSERT INTO public.tarefasdodia (contaid, lojaid, dia, atribuicaoid, funcionarioid, tarefaid,
                                   tipofrequencia, pontos, situacao, recuperado)
  SELECT p_contaid, c.lojaid, p_dia, c.atribuicaoid, c.funcionarioid, c.tarefaid,
         c.tipofrequencia, c.pontos, c.situacao, p_recuperado
    FROM public.lista_candidatos(p_contaid, p_dia) c
   -- A numeração das linhas (itemid) sai sempre na mesma ordem.
   ORDER BY c.lojaid, c.atribuicaoid
  ON CONFLICT (contaid, dia, atribuicaoid) DO NOTHING;
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  IF p_dia = p_hoje THEN
    UPDATE public.tarefasdodia i
       SET situacao = 'cancelada'
     WHERE i.contaid = p_contaid AND i.dia = p_dia AND i.situacao <> 'cancelada'
       AND NOT EXISTS (SELECT 1 FROM public.lista_candidatos(p_contaid, p_dia) c WHERE c.atribuicaoid = i.atribuicaoid)
       AND NOT public.item_tratado(i.atribuicaoid, i.tipofrequencia, i.dia, i.passadapara);
    GET DIAGNOSTICS v_cancelados = ROW_COUNT;

    UPDATE public.tarefasdodia i
       SET situacao = c.situacao
      FROM public.lista_candidatos(p_contaid, p_dia) c
     WHERE i.contaid = p_contaid AND i.dia = p_dia AND i.atribuicaoid = c.atribuicaoid
       AND i.situacao IS DISTINCT FROM c.situacao
       AND NOT public.item_tratado(i.atribuicaoid, i.tipofrequencia, i.dia, i.passadapara);
    GET DIAGNOSTICS v_ajustados = ROW_COUNT;
  END IF;

  INSERT INTO public.diasgerados (contaid, dia, recuperado)
  VALUES (p_contaid, p_dia, p_recuperado)
  ON CONFLICT (contaid, dia) DO NOTHING;

  RETURN jsonb_build_object(
    'dia', p_dia, 'novos', v_novos, 'cancelados', v_cancelados, 'ajustados', v_ajustados,
    'devidas',  (SELECT count(*) FROM public.tarefasdodia WHERE contaid = p_contaid AND dia = p_dia AND situacao = 'devida'),
    'folgas',   (SELECT count(*) FROM public.tarefasdodia WHERE contaid = p_contaid AND dia = p_dia
                   AND situacao IN ('folga', 'afastamento')),
    'canceladas', (SELECT count(*) FROM public.tarefasdodia WHERE contaid = p_contaid AND dia = p_dia AND situacao = 'cancelada'));
END;
$function$;
