-- Etapa 1.12, parte A (1/3): CPF da equipe e limpeza do que veio do sistema
-- antigo.
--
-- O CPF passa a valer de verdade: é por ele que o colaborador entra no app.
-- Regras (decisões do Wisley, 23/09/2026):
--   * Guardado só com números (11 dígitos), validado com os dois dígitos
--     verificadores. "111.111.111-11" e afins são recusados.
--   * Único POR CONTA (não no mundo): a mesma pessoa pode trabalhar em duas
--     empresas clientes. Vale entre os ativos, para não travar recontratação.
--   * As colunas senhahash, verificadorcpf e nivelacesso são heranças mortas do
--     sistema Flask: nenhuma função e nenhuma tela usam. Saem agora, para
--     ninguém confundir com o acesso novo.

-- ---------------------------------------------------------------------------
-- 1. Só números, 11 dígitos, verificador certo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cpf_valido(p_cpf text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v text := regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g');
  d1 integer := 0;
  d2 integer := 0;
  i  integer;
BEGIN
  IF length(v) <> 11 THEN
    RETURN false;
  END IF;
  -- Todos os dígitos iguais passam na conta dos verificadores, mas não são CPF.
  IF v ~ '^(.)\1{10}$' THEN
    RETURN false;
  END IF;
  FOR i IN 1..9 LOOP
    d1 := d1 + substr(v, i, 1)::integer * (11 - i);
  END LOOP;
  d1 := 11 - (d1 % 11);
  IF d1 >= 10 THEN d1 := 0; END IF;
  IF d1 <> substr(v, 10, 1)::integer THEN
    RETURN false;
  END IF;
  FOR i IN 1..10 LOOP
    d2 := d2 + substr(v, i, 1)::integer * (12 - i);
  END LOOP;
  d2 := 11 - (d2 % 11);
  IF d2 >= 10 THEN d2 := 0; END IF;
  RETURN d2 = substr(v, 11, 1)::integer;
END;
$$;
COMMENT ON FUNCTION public.cpf_valido(text) IS 'CPF com 11 dígitos e verificadores certos (aceita com ou sem pontuação).';

-- Gatilho: guarda só os números e recusa CPF inválido.
CREATE OR REPLACE FUNCTION public.normaliza_cpf_funcionario()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.cpf := nullif(regexp_replace(coalesce(NEW.cpf, ''), '[^0-9]', '', 'g'), '');
  IF NEW.cpf IS NOT NULL AND NOT public.cpf_valido(NEW.cpf) THEN
    RAISE EXCEPTION 'CPF inválido. Confira os números.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

-- Os CPFs que já estão no banco (importação antiga) viram só números; os que
-- não passam na validação ficam vazios, para o master recadastrar.
UPDATE public.funcionarios
   SET cpf = nullif(regexp_replace(coalesce(cpf, ''), '[^0-9]', '', 'g'), '')
 WHERE cpf IS NOT NULL;
UPDATE public.funcionarios SET cpf = NULL
 WHERE cpf IS NOT NULL AND NOT public.cpf_valido(cpf);

-- Se a importação trouxe o mesmo CPF duas vezes na mesma conta, fica só o
-- primeiro: o índice único abaixo não pode falhar na migração.
UPDATE public.funcionarios f SET cpf = NULL
 WHERE f.cpf IS NOT NULL AND f.ativo
   AND EXISTS (SELECT 1 FROM public.funcionarios o
                WHERE o.contaid = f.contaid AND o.cpf = f.cpf AND o.ativo AND o.funcionarioid < f.funcionarioid);

-- A coluna continua varchar(14): assim a tela pode mandar "529.982.247-25"
-- que o gatilho guarda "52998224725". Se o tipo fosse varchar(11), o banco
-- recusaria o CPF com pontos ANTES de o gatilho limpar.
COMMENT ON COLUMN public.funcionarios.cpf IS
  'Guardado só com números (11 dígitos); aceita digitação com pontos. É o login do colaborador no app. Único por conta entre os ativos.';

CREATE TRIGGER funcionarios_normaliza_cpf
  BEFORE INSERT OR UPDATE OF cpf ON public.funcionarios
  FOR EACH ROW EXECUTE FUNCTION public.normaliza_cpf_funcionario();

-- Único por conta, entre os ativos.
CREATE UNIQUE INDEX funcionarios_cpf_unico_na_conta
  ON public.funcionarios (contaid, cpf) WHERE cpf IS NOT NULL AND ativo;


-- ---------------------------------------------------------------------------
-- 2. Fora o que sobrou do sistema antigo
-- ---------------------------------------------------------------------------
-- (Os GRANTs por coluna somem junto com a coluna.)
ALTER TABLE public.funcionarios DROP COLUMN senhahash;
ALTER TABLE public.funcionarios DROP COLUMN verificadorcpf;
ALTER TABLE public.funcionarios DROP COLUMN nivelacesso;

-- ---------------------------------------------------------------------------
-- 3. Permissões
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.cpf_valido(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cpf_valido(text) TO authenticated, service_role;
