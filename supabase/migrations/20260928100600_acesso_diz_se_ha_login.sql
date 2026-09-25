-- Etapa 1.12 — desempenho (25/09/2026): o acesso passa a dizer se há login.
--
-- Motivo: o guardião das telas do gestor fazia TRÊS idas ao servidor em fila
-- a cada troca de tela — `getUser` (rede), depois `meuAcesso()`, que refazia o
-- mesmo `getUser` e só então perguntava `meu_acesso`. Com o Supabase nos EUA,
-- eram ~450 ms de espera antes de a tela começar a carregar.
--
-- Agora fica UMA ida: `meu_acesso`. Ela já roda no banco com o token, então
-- confere o token melhor do que a tela conferia. Só faltava distinguir dois
-- casos que ela devolvia igual:
--   * 'semlogin'  — não há token válido (auth.uid() vazio) → ir para a entrada;
--   * 'nenhum'    — o token vale, mas a pessoa não tem vínculo → "sem acesso".
--
-- Nada de permissão muda: quem protege continua sendo a RLS, que não depende
-- do que a tela acha. A prova está na seção 51 do teste de isolamento.
--
-- Esta é a versão da migração 20260927100500 (a mais recente) com essa única
-- mudança — nada mais foi tocado.
CREATE OR REPLACE FUNCTION public.meu_acesso()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  a     record;
BEGIN
  IF v_uid IS NULL THEN
    -- Sem token, ou token inválido/vencido: o banco não reconhece ninguém.
    RETURN jsonb_build_object('tipo', 'semlogin');
  END IF;
  IF public.eh_admin_geral() THEN
    RETURN jsonb_build_object('tipo', 'admin');
  END IF;

  SELECT cu.papel, cu.contaid, cu.lojaid, cu.funcionarioid,
         c.status AS statusconta, c.nome AS nomeconta,
         l.nome AS nomeloja, l.ativa AS lojaativa,
         f.nomecompleto AS nomepessoa, f.ativo AS pessoaativa,
         f.senhahashapp IS NULL AS semsenha, f.pinhash IS NULL AS sempin
    INTO a
    FROM public.contasusuarios cu
    JOIN public.contas c ON c.contaid = cu.contaid
    LEFT JOIN public.lojas l ON l.contaid = cu.contaid AND l.lojaid = cu.lojaid
    LEFT JOIN public.funcionarios f ON f.contaid = cu.contaid AND f.funcionarioid = cu.funcionarioid
   WHERE cu.userid = v_uid;

  IF NOT FOUND THEN
    -- Token bom, mas esta pessoa não pertence a conta nenhuma.
    RETURN jsonb_build_object('tipo', 'nenhum');
  END IF;

  -- Desligado na hora: pessoa inativa, loja desativada ou conta cancelada.
  IF a.statusconta = 'cancelada'
     OR (a.papel = 'loja' AND coalesce(a.lojaativa, false) = false)
     OR (a.papel = 'colaborador' AND coalesce(a.pessoaativa, false) = false) THEN
    RETURN jsonb_build_object('tipo', 'desligado');
  END IF;

  RETURN jsonb_build_object(
    'tipo', a.papel,
    'conta', a.nomeconta,
    'loja', a.nomeloja,
    'nome', coalesce(a.nomepessoa, a.nomeloja, a.nomeconta),
    'somenteleitura', a.statusconta <> 'ativa',
    'semsenha', coalesce(a.semsenha, false),
    'sempin', coalesce(a.sempin, false),
    'politicapendente', CASE WHEN a.papel = 'colaborador'
                             THEN public.politica_pendente(a.contaid, a.funcionarioid) ELSE false END);
END;
$$;

REVOKE ALL ON FUNCTION public.meu_acesso() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.meu_acesso() TO authenticated, service_role;
