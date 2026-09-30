-- CLASSIFICAÇÃO: ACRESCENTA
-- (cria uma tabela, uma permissão nova, uma leitura e três gatilhos; salvar_jornada
-- ganha um parâmetro OPCIONAL, as lojas: chamada sem ele, como a do site no ar,
-- faz o que fazia. Toda jornada que já existe nasce com TODAS as lojas da conta,
-- então nada muda para ninguém hoje.)
--
-- Jornada por loja (30/09/2026, decisões do Wisley):
-- 1. A jornada ganha a lista de lojas em que vale (jornadaslojas), como o
--    catálogo de tarefas. O master marca as que quiser; o gerente, só as dele.
-- 2. Permissão nova "Jornada: criar, editar e apagar" (jornada.editar), que
--    nasce negada para todo cargo. O gerente só mexe em jornada cujo alcance
--    cabe INTEIRO nas lojas em que ele tem a permissão — nem o nome, nem um
--    horário, se ela vale também para loja de fora. Apagar: o mesmo, e só sem
--    ninguém vinculado.
-- 3. Pessoa só se vincula a jornada com pelo menos UMA loja em comum. Quem
--    decide é o banco: o gatilho recusa por qualquer caminho, até direto na
--    tabela. E tirar a pessoa da única loja em comum (mantendo-a em outras)
--    também é recusado: o vínculo não fica apontando para uma jornada que não
--    vale para ela.
-- 4. Não se tira uma loja da jornada enquanto houver pessoa daquela loja
--    vinculada a ela: a mensagem diz quantas e de qual loja.
-- 6. As jornadas que já existem: TODAS as lojas da conta (ativas ou não). Com
--    isso elas continuam só do master (o alcance não cabe nas lojas de nenhum
--    gerente). A loja criada DEPOIS não entra sozinha em jornada nenhuma: o
--    master a marca na jornada (a opção mais restritiva).

-- ---------------------------------------------------------------------------
-- 1. As lojas de cada jornada
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.jornadaslojas (
  contaid   integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid),
  jornadaid integer NOT NULL,
  lojaid    integer NOT NULL,
  CONSTRAINT jornadaslojas_pkey PRIMARY KEY (contaid, jornadaid, lojaid),
  CONSTRAINT jornadaslojas_jornada_fk FOREIGN KEY (contaid, jornadaid)
    REFERENCES public.jornadas (contaid, jornadaid) ON DELETE CASCADE,
  CONSTRAINT jornadaslojas_loja_fk FOREIGN KEY (contaid, lojaid)
    REFERENCES public.lojas (contaid, lojaid)
);
COMMENT ON TABLE public.jornadaslojas IS
  'Em que lojas cada jornada vale (30/09/2026). Pessoa só se vincula a jornada com uma loja em comum; loja com gente vinculada não sai da jornada. Grava só pela salvar_jornada.';
CREATE INDEX IF NOT EXISTS jornadaslojas_loja_idx ON public.jornadaslojas (contaid, lojaid);
ALTER TABLE public.jornadaslojas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.jornadaslojas FROM anon, authenticated;
GRANT SELECT ON public.jornadaslojas TO authenticated;
GRANT ALL ON public.jornadaslojas TO service_role;
DROP POLICY IF EXISTS jornadaslojas_sel ON public.jornadaslojas;
CREATE POLICY jornadaslojas_sel ON public.jornadaslojas FOR SELECT TO authenticated
  USING (contaid = (SELECT public.minha_conta()));

-- As jornadas que já existem: todas as lojas da conta. Rodar de novo não duplica.
INSERT INTO public.jornadaslojas (contaid, jornadaid, lojaid)
SELECT j.contaid, j.jornadaid, l.lojaid
  FROM public.jornadas j JOIN public.lojas l ON l.contaid = j.contaid
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Os gatilhos: o banco garante a loja em comum, por qualquer caminho
-- ---------------------------------------------------------------------------
-- A pessoa ativa só aponta para jornada com loja em comum. (Tirar a pessoa de
-- TODAS as lojas — saída da empresa — não é barrado aqui.)
CREATE OR REPLACE FUNCTION public.jornada_serve_a_pessoa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_contaid integer; v_func integer; v_jornada integer; v_nome text; v_jnome text;
BEGIN
  IF TG_TABLE_NAME = 'funcionarios' THEN
    IF NEW.jornadaid IS NULL OR NOT NEW.ativo THEN RETURN NEW; END IF;
    v_contaid := NEW.contaid; v_func := NEW.funcionarioid; v_jornada := NEW.jornadaid; v_nome := NEW.nomecompleto;
  ELSE
    -- funcionarioslojas: a pessoa saiu (ou foi desligada) de uma loja.
    SELECT f.contaid, f.funcionarioid, f.jornadaid, f.nomecompleto INTO v_contaid, v_func, v_jornada, v_nome
      FROM public.funcionarios f
     WHERE f.contaid = OLD.contaid AND f.funcionarioid = OLD.funcionarioid AND f.ativo AND f.jornadaid IS NOT NULL;
    IF v_jornada IS NULL THEN RETURN NULL; END IF;
  END IF;
  -- Jornada que não é da conta da pessoa: quem recusa é a chave estrangeira
  -- (funcionarios_jornada_fk), como sempre foi.
  IF NOT EXISTS (SELECT 1 FROM public.jornadas j WHERE j.contaid = v_contaid AND j.jornadaid = v_jornada) THEN
    RETURN CASE WHEN TG_TABLE_NAME = 'funcionarios' THEN NEW END;
  END IF;
  -- Saindo de TODAS as lojas (saída da empresa): o desligamento passa. Mas
  -- vincular pessoa sem loja nenhuma, não (não há loja em comum).
  IF TG_TABLE_NAME <> 'funcionarios' AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                  WHERE fl.contaid = v_contaid AND fl.funcionarioid = v_func AND fl.ativo) THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                   JOIN public.jornadaslojas jl ON jl.contaid = fl.contaid AND jl.lojaid = fl.lojaid AND jl.jornadaid = v_jornada
                  WHERE fl.contaid = v_contaid AND fl.funcionarioid = v_func AND fl.ativo) THEN
    SELECT j.nome INTO v_jnome FROM public.jornadas j WHERE j.contaid = v_contaid AND j.jornadaid = v_jornada;
    IF TG_TABLE_NAME = 'funcionarios' THEN
      RAISE EXCEPTION 'A jornada "%" não vale para nenhuma loja de %. Escolha uma jornada de uma das lojas dessa pessoa.', v_jnome, v_nome
        USING ERRCODE = 'check_violation';
    END IF;
    RAISE EXCEPTION '% está na jornada "%", que não vale para nenhuma das outras lojas dessa pessoa. Mude a jornada dela antes (ou marque a loja na jornada).', v_nome, v_jnome
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN CASE WHEN TG_TABLE_NAME = 'funcionarios' THEN NEW END;
END;
$$;
REVOKE ALL ON FUNCTION public.jornada_serve_a_pessoa() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS funcionarios_jornada_na_loja ON public.funcionarios;
CREATE TRIGGER funcionarios_jornada_na_loja BEFORE INSERT OR UPDATE OF jornadaid ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.jornada_serve_a_pessoa();
DROP TRIGGER IF EXISTS funcionarioslojas_jornada_na_loja ON public.funcionarioslojas;
CREATE TRIGGER funcionarioslojas_jornada_na_loja AFTER UPDATE OF ativo OR DELETE ON public.funcionarioslojas
  FOR EACH ROW EXECUTE FUNCTION public.jornada_serve_a_pessoa();

-- Loja com gente vinculada não sai da jornada (a jornada apagada leva as
-- lojas junto: ela só se apaga sem ninguém, então nada é barrado aí).
CREATE OR REPLACE FUNCTION public.loja_sai_da_jornada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_n integer; v_loja text;
BEGIN
  SELECT count(*) INTO v_n
    FROM public.funcionarios f
    JOIN public.funcionarioslojas fl ON fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
   WHERE f.contaid = OLD.contaid AND f.jornadaid = OLD.jornadaid AND f.ativo AND fl.lojaid = OLD.lojaid;
  IF v_n > 0 THEN
    SELECT l.nome INTO v_loja FROM public.lojas l WHERE l.contaid = OLD.contaid AND l.lojaid = OLD.lojaid;
    RAISE EXCEPTION 'Não dá para tirar a loja % desta jornada: % pessoa(s) dessa loja estão vinculadas a ela. Mude a jornada dessas pessoas em Equipe antes.', v_loja, v_n
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.loja_sai_da_jornada() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS jornadaslojas_loja_com_gente ON public.jornadaslojas;
CREATE TRIGGER jornadaslojas_loja_com_gente BEFORE DELETE ON public.jornadaslojas
  FOR EACH ROW EXECUTE FUNCTION public.loja_sai_da_jornada();

-- ---------------------------------------------------------------------------
-- 3. A permissão nova (nasce negada para todo cargo). Parte da versão viva.
-- ---------------------------------------------------------------------------
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
    ('jornada.editar',            'Jornada',         'Criar, editar e apagar jornada',        83),
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

-- ---------------------------------------------------------------------------
-- 4. Criar e editar: o master em qualquer loja da conta; o gerente só com a
--    jornada INTEIRA nas lojas em que ele pode editar jornada
-- ---------------------------------------------------------------------------
-- A versão anterior (7 parâmetros) sai: esta aceita a mesma chamada, e as
-- lojas são opcionais (sem elas: jornada nova = todas as lojas da conta, só
-- para o master; jornada que existe = as lojas não mudam).
DROP FUNCTION IF EXISTS public.salvar_jornada(integer, text, jsonb, time, time, text, boolean);
CREATE OR REPLACE FUNCTION public.salvar_jornada(p_jornadaid integer, p_nome text, p_dias jsonb,
                                                 p_pausainicio time, p_pausafim time, p_observacao text,
                                                 p_ativa boolean, p_lojas integer[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
  v_id     integer;
  v_lojas  integer[];
  v_antes  integer[];
  v_falta  text;
  d        jsonb;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_master AND cardinality((SELECT public.lojas_onde_posso('jornada.editar'))::integer[]) = 0 THEN
    RAISE EXCEPTION 'Criar e editar jornada não está liberado para o seu cargo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF btrim(coalesce(p_nome, '')) = '' THEN
    RAISE EXCEPTION 'Dê um nome à jornada.' USING ERRCODE = 'check_violation';
  END IF;
  IF jsonb_typeof(p_dias) IS DISTINCT FROM 'array' OR jsonb_array_length(p_dias) = 0 THEN
    RAISE EXCEPTION 'Preencha a entrada e a saída de pelo menos um dia.' USING ERRCODE = 'check_violation';
  END IF;
  IF (p_pausainicio IS NULL) <> (p_pausafim IS NULL) THEN
    RAISE EXCEPTION 'O intervalo precisa de começo e fim (ou fica sem intervalo).' USING ERRCODE = 'check_violation';
  END IF;

  -- As lojas pedidas: da conta, pelo menos uma; o gerente, só as dele.
  IF p_lojas IS NOT NULL THEN
    SELECT array_agg(DISTINCT x ORDER BY x) INTO v_lojas FROM unnest(p_lojas) x WHERE x IS NOT NULL;
    IF v_lojas IS NULL THEN
      RAISE EXCEPTION 'Marque pelo menos uma loja em que a jornada vale.' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_lojas) x
                WHERE NOT EXISTS (SELECT 1 FROM public.lojas l WHERE l.contaid = v_conta AND l.lojaid = x)) THEN
      RAISE EXCEPTION 'Loja não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    IF NOT v_master AND EXISTS (SELECT 1 FROM unnest(v_lojas) x WHERE NOT public.pode('jornada.editar', x)) THEN
      RAISE EXCEPTION 'Você só pode marcar as lojas em que o seu cargo cria e edita jornada.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF p_jornadaid IS NULL THEN
    IF v_lojas IS NULL THEN
      IF NOT v_master THEN
        RAISE EXCEPTION 'Marque as lojas em que a jornada vale.' USING ERRCODE = 'check_violation';
      END IF;
      SELECT array_agg(l.lojaid ORDER BY l.lojaid) INTO v_lojas FROM public.lojas l WHERE l.contaid = v_conta;
    END IF;
    INSERT INTO public.jornadas (contaid, nome, pausainicio, pausafim, observacao, ativa)
    VALUES (v_conta, btrim(p_nome), p_pausainicio, p_pausafim, nullif(btrim(coalesce(p_observacao, '')), ''),
            coalesce(p_ativa, true))
    RETURNING jornadaid INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid) THEN
      RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
    END IF;
    SELECT array_agg(jl.lojaid ORDER BY jl.lojaid) INTO v_antes
      FROM public.jornadaslojas jl WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid;
    -- O gerente só mexe se a jornada INTEIRA couber nas lojas dele (nem o nome).
    IF NOT v_master AND (v_antes IS NULL OR EXISTS (SELECT 1 FROM unnest(v_antes) x WHERE NOT public.pode('jornada.editar', x))) THEN
      RAISE EXCEPTION 'Esta jornada vale também para lojas que não são suas: só quem cuida de todas elas pode alterá-la.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Tirar loja com gente vinculada dela: a mensagem diz quantas e de qual.
    IF v_lojas IS NOT NULL THEN
      SELECT string_agg(l.nome || ' (' || x.n || ' pessoa' || CASE WHEN x.n = 1 THEN '' ELSE 's' END || ')', ', ' ORDER BY l.nome)
        INTO v_falta
        FROM (SELECT fl.lojaid, count(DISTINCT f.funcionarioid) AS n
                FROM public.funcionarios f
                JOIN public.funcionarioslojas fl ON fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo
               WHERE f.contaid = v_conta AND f.jornadaid = p_jornadaid AND f.ativo
                 AND fl.lojaid = ANY (coalesce(v_antes, '{}'::integer[])) AND NOT fl.lojaid = ANY (v_lojas)
               GROUP BY fl.lojaid) x
        JOIN public.lojas l ON l.contaid = v_conta AND l.lojaid = x.lojaid;
      IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Não dá para tirar da jornada a(s) loja(s) %: há gente dessa(s) loja(s) vinculada a ela. Mude a jornada dessas pessoas em Equipe antes.', v_falta
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    UPDATE public.jornadas
       SET nome = btrim(p_nome), pausainicio = p_pausainicio, pausafim = p_pausafim,
           observacao = nullif(btrim(coalesce(p_observacao, '')), ''), ativa = coalesce(p_ativa, true)
     WHERE contaid = v_conta AND jornadaid = p_jornadaid
    RETURNING jornadaid INTO v_id;
    DELETE FROM public.jornadasdias WHERE contaid = v_conta AND jornadaid = v_id;
  END IF;

  FOR d IN SELECT * FROM jsonb_array_elements(p_dias) LOOP
    IF (d->>'dia')::integer NOT BETWEEN 1 AND 7 THEN
      RAISE EXCEPTION 'Dia da semana inválido.' USING ERRCODE = 'check_violation';
    END IF;
    IF (d->>'entrada')::time = (d->>'saida')::time THEN
      RAISE EXCEPTION 'Entrada e saída iguais no mesmo dia.' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO public.jornadasdias (contaid, jornadaid, diasemana, entrada, saida)
    VALUES (v_conta, v_id, (d->>'dia')::smallint, (d->>'entrada')::time, (d->>'saida')::time);
  END LOOP;

  -- As lojas: só quando vieram (sem elas, numa edição, ficam como estão).
  IF v_lojas IS NOT NULL THEN
    DELETE FROM public.jornadaslojas
     WHERE contaid = v_conta AND jornadaid = v_id AND NOT lojaid = ANY (v_lojas);
    INSERT INTO public.jornadaslojas (contaid, jornadaid, lojaid)
    SELECT v_conta, v_id, x FROM unnest(v_lojas) x
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Já existe uma jornada com esse nome (ou o mesmo dia apareceu duas vezes).' USING ERRCODE = 'unique_violation';
END;
$$;
REVOKE ALL ON FUNCTION public.salvar_jornada(integer, text, jsonb, time, time, text, boolean, integer[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.salvar_jornada(integer, text, jsonb, time, time, text, boolean, integer[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Apagar: o master; o gerente com a jornada INTEIRA nas lojas dele. E
--    ninguém apaga jornada com gente vinculada.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apagar_jornada(p_jornadaid integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_master boolean := public.sou_master();
  v_conta  integer := CASE WHEN public.sou_master() THEN public.minha_conta_editavel()
                           ELSE public.conta_do_gestor_editavel() END;
  v_nome   text;
  v_n      integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT v_master AND cardinality((SELECT public.lojas_onde_posso('jornada.editar'))::integer[]) = 0 THEN
    RAISE EXCEPTION 'Apagar jornada não está liberado para o seu cargo.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT j.nome INTO v_nome FROM public.jornadas j WHERE j.contaid = v_conta AND j.jornadaid = p_jornadaid;
  IF v_nome IS NULL THEN
    RAISE EXCEPTION 'Jornada não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT v_master THEN
    IF NOT EXISTS (SELECT 1 FROM public.jornadaslojas jl WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid)
       OR EXISTS (SELECT 1 FROM public.jornadaslojas jl
                   WHERE jl.contaid = v_conta AND jl.jornadaid = p_jornadaid AND NOT public.pode('jornada.editar', jl.lojaid)) THEN
      RAISE EXCEPTION 'Esta jornada vale também para lojas que não são suas: só quem cuida de todas elas pode apagá-la.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  SELECT count(*) INTO v_n FROM public.funcionarios WHERE contaid = v_conta AND jornadaid = p_jornadaid;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'A jornada "%" tem % pessoa(s) vinculada(s). Mova essas pessoas para outra jornada (ou "sem jornada") antes de apagar.', v_nome, v_n
      USING ERRCODE = 'foreign_key_violation';   -- o mesmo texto e codigo de antes (protege_jornada_em_uso)
  END IF;
  DELETE FROM public.jornadas WHERE contaid = v_conta AND jornadaid = p_jornadaid;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Vincular: só com loja em comum. Parte da versão viva.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vincular_jornada(p_funcionarios integer[], p_jornadaid integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_conta integer := public.conta_do_gestor_editavel(); v_n integer; v_fora text;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION '%', public.motivo_da_recusa() USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Permissão em cada pessoa, no banco (usuários gerenciais, parte 2 — Equipe):
  -- tudo ou nada; e nunca a própria.
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_funcionarios, '{}'::integer[])) x(f)
              WHERE NOT public.pode_na_pessoa('jornada.vincular', v_conta, x.f)
                 OR public.e_o_proprio(v_conta, x.f)) THEN
    RAISE EXCEPTION 'Seu cargo não permite ligar à jornada alguma dessas pessoas (ou é você mesmo).' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_jornadaid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.jornadas
                                              WHERE contaid = v_conta AND jornadaid = p_jornadaid AND ativa) THEN
    RAISE EXCEPTION 'Jornada não encontrada ou inativa.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Só jornada com pelo menos UMA loja em comum com cada pessoa (30/09/2026).
  -- O gatilho de funcionarios garante o mesmo por qualquer caminho; aqui a
  -- mensagem diz quem.
  IF p_jornadaid IS NOT NULL THEN
    SELECT string_agg(f.nomecompleto, ', ' ORDER BY f.nomecompleto) INTO v_fora
      FROM public.funcionarios f
     WHERE f.contaid = v_conta AND f.funcionarioid = ANY (p_funcionarios) AND f.ativo
       AND NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                         JOIN public.jornadaslojas jl ON jl.contaid = fl.contaid AND jl.lojaid = fl.lojaid AND jl.jornadaid = p_jornadaid
                        WHERE fl.contaid = f.contaid AND fl.funcionarioid = f.funcionarioid AND fl.ativo);
    IF v_fora IS NOT NULL THEN
      RAISE EXCEPTION 'Esta jornada não vale para nenhuma loja de: %. Escolha uma jornada das lojas dessa(s) pessoa(s).', v_fora
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  UPDATE public.funcionarios SET jornadaid = p_jornadaid
   WHERE contaid = v_conta AND funcionarioid = ANY (p_funcionarios) AND ativo;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. As leituras: a lista de jornadas (com as lojas e se o gerente pode editar)
--    e as jornadas que servem para as pessoas que vão ser vinculadas
-- ---------------------------------------------------------------------------
-- O gerente vê as jornadas que valem em pelo menos uma loja em que ele vê a
-- Jornada; das lojas de fora, só quantas são (o nome não).
DROP FUNCTION IF EXISTS public.jornadas_da_tela();
CREATE FUNCTION public.jornadas_da_tela()
RETURNS TABLE(jornadaid integer, nome character varying, pausainicio time, pausafim time, observacao text,
              ativa boolean, lojas integer[], outraslojas integer, editavel boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH ver AS (SELECT (SELECT public.lojas_onde_posso('jornada.ver'))::integer[] AS l),
       edita AS (SELECT (SELECT public.lojas_onde_posso('jornada.editar'))::integer[] AS l),
       todas AS (
    SELECT j.*, coalesce((SELECT array_agg(jl.lojaid ORDER BY jl.lojaid) FROM public.jornadaslojas jl
                           WHERE jl.contaid = j.contaid AND jl.jornadaid = j.jornadaid), '{}'::integer[]) AS alcance
      FROM public.jornadas j
     WHERE (public.sou_master() AND j.contaid = public.minha_conta())
        OR (NOT public.sou_master() AND j.contaid = public.conta_do_gerente())
  )
  SELECT t.jornadaid, t.nome, t.pausainicio, t.pausafim, t.observacao, t.ativa,
         CASE WHEN public.sou_master() THEN t.alcance
              ELSE ARRAY(SELECT x FROM unnest(t.alcance) x WHERE x = ANY ((SELECT l FROM ver)::integer[]) ORDER BY x) END,
         CASE WHEN public.sou_master() THEN 0
              ELSE (SELECT count(*)::integer FROM unnest(t.alcance) x WHERE NOT x = ANY ((SELECT l FROM ver)::integer[])) END,
         public.sou_master()
           OR (cardinality(t.alcance) > 0 AND t.alcance <@ (SELECT l FROM edita))
    FROM todas t
   WHERE public.sou_master() OR t.alcance && (SELECT l FROM ver)
   ORDER BY t.nome, t.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_da_tela() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.jornadas_da_tela() TO authenticated;

CREATE OR REPLACE FUNCTION public.dias_das_jornadas()
RETURNS TABLE(jornadaid integer, diasemana smallint, entrada time, saida time)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT d.jornadaid, d.diasemana, d.entrada, d.saida
    FROM public.jornadasdias d
   WHERE (public.sou_master() AND d.contaid = public.minha_conta())
      OR (NOT public.sou_master() AND d.contaid = public.conta_do_gerente()
          AND EXISTS (SELECT 1 FROM public.jornadaslojas jl
                       WHERE jl.contaid = d.contaid AND jl.jornadaid = d.jornadaid
                         AND jl.lojaid = ANY ((SELECT public.lojas_onde_posso('jornada.ver'))::integer[])))
   ORDER BY d.jornadaid, d.diasemana
$$;

-- As jornadas ATIVAS que servem para TODAS as pessoas da lista (uma loja em
-- comum com cada uma). É o que a Equipe mostra na hora de vincular.
CREATE OR REPLACE FUNCTION public.jornadas_que_servem(p_funcionarios integer[])
RETURNS TABLE(jornadaid integer, nome character varying)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH c AS (
    SELECT CASE WHEN public.sou_master() THEN public.minha_conta()
                WHEN cardinality((SELECT public.lojas_onde_posso('jornada.vincular'))::integer[]) > 0
                THEN public.conta_do_gerente() END AS contaid
  )
  SELECT j.jornadaid, j.nome
    FROM public.jornadas j, c
   WHERE j.contaid = c.contaid AND j.ativa
     AND cardinality(coalesce(p_funcionarios, '{}'::integer[])) > 0
     AND NOT EXISTS (
       SELECT 1 FROM unnest(p_funcionarios) x(f)
        WHERE NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                            JOIN public.jornadaslojas jl ON jl.contaid = fl.contaid AND jl.lojaid = fl.lojaid AND jl.jornadaid = j.jornadaid
                           WHERE fl.contaid = c.contaid AND fl.funcionarioid = x.f AND fl.ativo))
     -- O gerente só pergunta por gente das lojas em que ele liga pessoa a jornada.
     AND (public.sou_master() OR NOT EXISTS (
       SELECT 1 FROM unnest(p_funcionarios) y(f)
        WHERE NOT EXISTS (SELECT 1 FROM public.funcionarioslojas fl
                           WHERE fl.contaid = c.contaid AND fl.funcionarioid = y.f AND fl.ativo
                             AND fl.lojaid = ANY ((SELECT public.lojas_onde_posso('jornada.vincular'))::integer[]))))
   ORDER BY j.nome, j.jornadaid
$$;
REVOKE ALL ON FUNCTION public.jornadas_que_servem(integer[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.jornadas_que_servem(integer[]) TO authenticated;
