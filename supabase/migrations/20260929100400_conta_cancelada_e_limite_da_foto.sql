-- Dois consertos da revisão adversarial de 25/09/2026.
--
-- 1. CONTA CANCELADA fechava só a escrita, não a leitura. eu_confere_pessoa
--    conferia apenas funcionarios.ativo, então o Início, as tarefas e o
--    extrato abriam numa conta cancelada. Não era furo (nada chega às eu_*
--    sem passar pelo servidor, que confere meu_acesso), mas era exatamente a
--    "tranca única fora do banco" que esta mesma etapa existiu para eliminar.
--
-- 2. O BUCKET DAS FOTOS ficou sem limite de tamanho e sem lista de tipos.
--    Os outros dois buckets ganharam 10 MB e tipos permitidos; entregas não.
--    E agora o servidor BAIXA o arquivo inteiro para tirar a impressão
--    digital, então o tamanho deixou de ser só uma questão de espaço.

-- ---------------------------------------------------------------------------
-- 1. Conta cancelada fecha as leituras também
-- ---------------------------------------------------------------------------
-- Parte da versão de 20260929100100, com uma conferência a mais.
CREATE OR REPLACE FUNCTION public.eu_confere_pessoa(p_contaid integer, p_funcionarioid integer)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios f
                  WHERE f.contaid = p_contaid AND f.funcionarioid = p_funcionarioid AND f.ativo) THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
  -- Conta cancelada: a mesma mensagem, para não revelar o motivo a quem está
  -- do lado de fora.
  IF NOT EXISTS (SELECT 1 FROM public.contas c
                  WHERE c.contaid = p_contaid AND c.status <> 'cancelada') THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.eu_confere_pessoa(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_confere_pessoa(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 1b. eu_inicio passa a usar a MESMA conferência das outras três
-- ---------------------------------------------------------------------------
-- Ela tinha a dela, por dentro (só funcionarios.ativo), e por isso continuava
-- abrindo com a conta cancelada mesmo depois do conserto acima. Quem achou
-- foi o teste: com a conta ativa o Início abria (controle), com a conta
-- cancelada ele continuava abrindo.
--
-- Parte da versão de 20260929100000, trocando só o bloco da conferência.
CREATE OR REPLACE FUNCTION public.eu_inicio(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_hoje date := public.dia_em_sao_paulo(now());
  f      record;
  v_nota numeric;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor abre a visão do colaborador.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Uma porta só para as quatro funções: pessoa ativa E conta não cancelada.
  PERFORM public.eu_confere_pessoa(p_contaid, p_funcionarioid);

  SELECT nomecompleto, saldopontos INTO f
    FROM public.funcionarios
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cadastro não encontrado.' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT r.nota INTO v_nota
    FROM public.ranking_mensal_da_conta(p_contaid,
           extract(year FROM v_hoje)::integer, extract(month FROM v_hoje)::integer,
           NULL, v_hoje - 1) r
   WHERE r.funcionarioid = p_funcionarioid;

  RETURN jsonb_build_object(
    'nome',   public.nome_curto(f.nomecompleto),
    -- Saldo só em pontos. Nunca convertido em dinheiro nesta visão.
    'saldo',  f.saldopontos,
    'nota',   v_nota,
    'feedbackpendente', public.bot_falta_feedback_ontem(p_contaid, p_funcionarioid),
    'comunicados', (SELECT count(*) FROM public.documentosassinaturas s
                     WHERE s.contaid = p_contaid AND s.funcionarioid = p_funcionarioid
                       AND s.statusassinatura = 'Pendente'));
END;
$$;

REVOKE ALL ON FUNCTION public.eu_inicio(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.eu_inicio(integer, integer) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Limite de tamanho e de tipo no bucket das fotos de entrega
-- ---------------------------------------------------------------------------
-- Em DO porque o Storage do Supabase é que traz a tabela storage.buckets: no
-- Postgres de teste ela pode não existir, e a migração não pode quebrar ali.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'storage' AND table_name = 'buckets'
                AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets
                  SET file_size_limit = 10485760,
                      allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
                WHERE id = 'entregas'$q$;
  END IF;
END $$;
