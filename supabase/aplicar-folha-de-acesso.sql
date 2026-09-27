-- =========================================================================
-- STGame — folha de acesso em PDF, código só no primeiro acesso, fuso
-- travado em Brasília e a cópia estornada no celular.
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique tudo o que veio antes. E aplique ESTE ARQUIVO ANTES de
-- publicar a versão nova: o botão PDF depende das funções daqui.
--
-- Este arquivo é UMA migração só:
--   20260929150000_folha_de_acesso.sql
--
-- O QUE MUDA PARA QUEM JÁ USA:
--   * O fuso horário fica em America/Sao_Paulo (o campo em Configurações
--     passa a ser só leitura).
--   * Código de acesso passa a ser só para o PRIMEIRO acesso. Códigos que
--     estivessem valendo para quem já tem senha ou PIN são CANCELADOS agora
--     (eram a brecha: com a folha e o CPF, dava para entrar na conta da
--     pessoa). Para quem já entrou, o caminho é redefinir o acesso.
--   * Os códigos gerados antes disto não podem ser reimpressos (o banco
--     nunca soube qual era o código). O primeiro PDF dessas pessoas gera um
--     código novo, e a tela avisa antes.
-- =========================================================================


BEGIN;

-- A folha de acesso em PDF, o código que não toma conta de ninguém, o fuso
-- travado em Brasília, e a cópia estornada que não fica para sempre no
-- celular (27/09/2026).

-- ---------------------------------------------------------------------------
-- 1. O fuso fica em São Paulo
-- ---------------------------------------------------------------------------
-- Parte do sistema (46 funções e 11 telas) ainda usa São Paulo fixo. Um
-- cliente que escolhesse Rio Branco teria metade obedecendo e metade não, sem
-- aviso. Até a conversão terminar, o único fuso aceito é America/Sao_Paulo —
-- e converter é PRÉ-REQUISITO para vender fora do horário de Brasília.
-- Parte da versão mais recente (20260929100700), com o diff conferido.
CREATE OR REPLACE FUNCTION public.valida_configuracao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_texto text := btrim(coalesce(NEW.valor, ''));
  v_num   numeric;
BEGIN
  IF NEW.chave = 'TAXA_CONVERSAO_PONTO_REAL' THEN
    BEGIN
      v_num := replace(v_texto, ',', '.')::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'A taxa precisa ser um número, como 0,03.' USING ERRCODE = 'check_violation';
    END;
    IF v_num IS NULL OR v_num <= 0 OR v_num > 10 THEN
      RAISE EXCEPTION 'A taxa precisa ser maior que zero e no máximo R$ 10 por ponto.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_num::text;

  ELSIF NEW.chave LIKE 'PONTOS_BONUS_%' OR NEW.chave = 'MAX_DIFERENCA_FOTO_SEGUNDOS' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro, sem vírgula.' USING ERRCODE = 'check_violation';
    END IF;
    v_num := CASE WHEN NEW.chave LIKE 'PONTOS_BONUS_%' THEN 10000 ELSE 86400 END;
    IF v_texto::numeric > v_num THEN
      RAISE EXCEPTION 'Valor alto demais para %.', NEW.chave USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  -- Prazo da foto: nunca menos de 90 dias (a política de uso promete um prazo,
  -- e um prazo curto demais apagaria prova de entrega ainda em discussão).
  ELSIF NEW.chave = 'DIAS_GUARDAR_FOTO_ENTREGA' THEN
    IF v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'O prazo precisa ser um número inteiro de dias.' USING ERRCODE = 'check_violation';
    END IF;
    IF v_texto::integer < 90 OR v_texto::integer > 3650 THEN
      RAISE EXCEPTION 'O prazo precisa ser de 90 a 3650 dias.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  -- Rodizio no aceite: 0 desliga, e o teto de 2 horas evita travar a loja por
  -- engano ao digitar um numero grande.
  ELSIF NEW.chave = 'MINUTOS_RODIZIO_ACEITE' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer > 120 THEN
      RAISE EXCEPTION 'O tempo de espera precisa ser um número inteiro de 0 a 120 minutos (0 desliga).'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave = 'MINUTOS_TAREFA_PARADA' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer < 5 OR v_texto::integer > 480 THEN
      RAISE EXCEPTION 'O tempo precisa ser um número inteiro de 5 a 480 minutos.'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave IN ('MAX_MENSAGENS_AUTOMATICAS_DIA', 'MAX_TAREFAS_FOLGA_POR_PESSOA') THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer < 1 OR v_texto::integer > 50 THEN
      RAISE EXCEPTION 'O valor precisa ser um número inteiro de 1 a 50.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave LIKE 'HORARIO_%' THEN
    IF v_texto !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
      RAISE EXCEPTION 'O horário precisa estar no formato HH:MM, entre 00:00 e 23:59.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  -- O fuso tem de ser um fuso que o banco conhece: errar aqui erraria TODAS
  -- as liberacoes da conta, e em silencio.
  -- Só o horário de Brasília, por enquanto (decisão do Wisley, 27/09/2026):
  -- parte do sistema ainda usa São Paulo fixo, e oferecer outro fuso faria
  -- metade obedecer e metade não, sem ninguém avisar. Abrir outros fusos
  -- depende de converter as funções que faltam (ver a catraca da seção 68).
  ELSIF NEW.chave = 'FUSO_HORARIO' THEN
    IF v_texto <> 'America/Sao_Paulo' THEN
      RAISE EXCEPTION 'Por enquanto o STGame funciona só no horário de Brasília (America/Sao_Paulo). Outros fusos ainda não estão disponíveis.'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave = 'SOM_TAREFA_NOVA' THEN
    IF v_texto NOT IN ('0', '1') THEN
      RAISE EXCEPTION 'Use 1 para ligar o som e 0 para desligar.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave = 'SOM_VOLUME' THEN
    IF v_texto !~ '^[0-9]+$' OR v_texto::integer > 100 THEN
      RAISE EXCEPTION 'O volume precisa ser um número inteiro de 0 a 100.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto::integer::text;

  ELSIF NEW.chave = 'CONTATO_PRIVACIDADE' THEN
    IF length(v_texto) > 200 THEN
      RAISE EXCEPTION 'O contato pode ter no máximo 200 letras.' USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor := v_texto;

  ELSIF NEW.chave LIKE 'TAREFA_%' THEN
    IF v_texto <> '' AND v_texto !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'ID de tarefa inválido.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    NEW.atualizadoem := now();
  END IF;
  RETURN NEW;
END;
$$;
-- Quem já tivesse escolhido outro fuso volta para São Paulo (o Wisley
-- confirmou que não há cliente fora do horário de Brasília).
UPDATE public.configuracoes SET valor = 'America/Sao_Paulo'
 WHERE chave = 'FUSO_HORARIO' AND valor IS DISTINCT FROM 'America/Sao_Paulo';

-- ---------------------------------------------------------------------------
-- 2. O celular: a cópia estornada não fica "recusada" para sempre
-- ---------------------------------------------------------------------------
-- O estorno de uma Única já a traz de volta para ser feita (provado na seção
-- 69 do teste). Faltava o celular: a cópia antiga, de outro dia, continuava
-- aparecendo como "recusada" todos os dias, e nem podia mais ser entregue.
-- Parte da versão mais recente (20260929140000), com o diff conferido.
CREATE OR REPLACE FUNCTION public.eu_tarefas(p_contaid integer, p_funcionarioid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
             'liberada',     x.liberada) ORDER BY x.pegaem NULLS LAST, x.titulo), '[]'::jsonb)
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
             ORDER BY e2.dataenvio DESC LIMIT 1) e ON true
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
$$;

-- ---------------------------------------------------------------------------
-- 3. Código de acesso: só para o PRIMEIRO acesso
-- ---------------------------------------------------------------------------
-- Até aqui, "Gerar código" funcionava para quem já usava o app, e quem
-- tivesse a folha e o CPF entrava na conta da pessoa sem mexer na senha dela
-- (a pessoa nem percebia) e podia trocar o PIN — a assinatura dela no tablet
-- — sem saber o atual. Agora:
--   * o banco recusa gerar código para quem já tem senha ou PIN (o caminho é
--     redefinir o acesso, que apaga senha e PIN antes e derruba as sessões);
--   * o código não abre a conta de quem já tem senha ou PIN;
--   * os códigos que já existiam nessa situação são cancelados agora.
UPDATE public.codigosacesso k SET canceladoem = now()
  FROM public.funcionarios f
 WHERE f.contaid = k.contaid AND f.funcionarioid = k.funcionarioid
   AND k.usadoem IS NULL AND k.canceladoem IS NULL
   AND (f.senhahashapp IS NOT NULL OR f.pinhash IS NOT NULL);

-- O código passa a ser guardado também CIFRADO, para a folha poder ser
-- reimpressa com o MESMO código (sortear outro trancaria quem já recebeu a
-- folha). Quem cifra e decifra é o servidor, com a chave dele: o banco
-- sozinho continua sem conseguir ler código nenhum. O resumo (codigohash)
-- continua sendo o que confere a entrada.
ALTER TABLE public.codigosacesso ADD COLUMN IF NOT EXISTS codigocifrado text;
COMMENT ON COLUMN public.codigosacesso.codigocifrado IS
  'O código cifrado pelo servidor (AES-GCM, chave fora do banco), só para reimprimir a folha. Vazio nos códigos anteriores a 27/09/2026: esses não se reimprimem.';

-- Parte da versão mais recente (20260927100500): ganha o código cifrado,
-- devolve o id, e recusa quem já entrou.
DROP FUNCTION IF EXISTS public.criar_codigo_acesso(integer, integer, text, integer, uuid);
CREATE OR REPLACE FUNCTION public.criar_codigo_acesso(p_contaid integer, p_funcionarioid integer,
                                                      p_codigohash text, p_codigocifrado text,
                                                      p_dias integer, p_quem uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_id integer;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor gera código de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.funcionarios
                  WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid AND ativo) THEN
    RAISE EXCEPTION 'Pessoa não encontrada ou desativada.' USING ERRCODE = 'no_data_found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.funcionarios
              WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
                AND (senhahashapp IS NOT NULL OR pinhash IS NOT NULL)) THEN
    RAISE EXCEPTION 'Esta pessoa já fez o primeiro acesso. Para ela receber um código novo, redefina o acesso: a senha e o PIN atuais deixam de valer.'
      USING ERRCODE = 'check_violation';
  END IF;
  -- Gerar outro cancela o anterior: só um código vale por vez.
  UPDATE public.codigosacesso SET canceladoem = now()
   WHERE contaid = p_contaid AND funcionarioid = p_funcionarioid
     AND usadoem IS NULL AND canceladoem IS NULL;
  INSERT INTO public.codigosacesso (contaid, funcionarioid, codigohash, codigocifrado, expiraem, criadopor)
  VALUES (p_contaid, p_funcionarioid, left(p_codigohash, 64), left(p_codigocifrado, 200),
          now() + make_interval(days => greatest(coalesce(p_dias, 7), 1)), p_quem)
  RETURNING codigoid INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.criar_codigo_acesso(integer, integer, text, text, integer, uuid) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.criar_codigo_acesso(integer, integer, text, text, integer, uuid) TO service_role;

-- Parte da versão mais recente (20260927100500), com o diff conferido.
CREATE OR REPLACE FUNCTION public.usar_codigo_acesso(p_contaid integer, p_cpf text, p_codigohash text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE c record;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor usa código de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT k.codigoid, k.funcionarioid, f.nomecompleto
    INTO c
    FROM public.codigosacesso k
    JOIN public.funcionarios f ON f.contaid = k.contaid AND f.funcionarioid = k.funcionarioid AND f.ativo
   WHERE k.contaid = p_contaid
     AND k.codigohash = left(p_codigohash, 64)
     AND k.usadoem IS NULL AND k.canceladoem IS NULL
     AND k.expiraem > now()
     AND f.cpf = regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g')
     -- Código é só para o PRIMEIRO acesso. Quem já tem senha ou PIN não entra
     -- por código: antes de 27/09/2026 dava para gerar código para quem já
     -- usava o app, e quem tivesse a folha e o CPF abria a conta dela e
     -- trocava o PIN sem saber o atual. Para dar código novo a quem já
     -- entrou, o caminho é redefinir o acesso (apaga senha e PIN antes).
     AND f.senhahashapp IS NULL AND f.pinhash IS NULL
     FOR UPDATE OF k;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  UPDATE public.codigosacesso SET usadoem = now() WHERE codigoid = c.codigoid;
  RETURN jsonb_build_object('funcionarioid', c.funcionarioid, 'nome', c.nomecompleto);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. O registro de cada folha emitida
-- ---------------------------------------------------------------------------
-- Toda emissão fica registrada (quem, quando, com qual código, e se ela
-- redefiniu o acesso) e aparece no cartão da pessoa. A folha em si não é
-- guardada: é gerada na hora, no navegador.
CREATE TABLE IF NOT EXISTS public.folhasacesso (
  folhaid       integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  funcionarioid integer NOT NULL,
  codigoid      integer NOT NULL,
  redefiniu     boolean NOT NULL DEFAULT false,
  emitidaem     timestamptz NOT NULL DEFAULT now(),
  emitidapor    uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  -- Da mesma conta, sempre: a pessoa e o código.
  CONSTRAINT folhasacesso_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT folhasacesso_codigo_fk FOREIGN KEY (contaid, codigoid)
    REFERENCES public.codigosacesso (contaid, codigoid) ON DELETE RESTRICT
);
COMMENT ON TABLE public.folhasacesso IS
  'Cada folha de instruções de acesso emitida (PDF): quem, quando, com qual código, e se ela redefiniu o acesso. Nível conta.';
CREATE INDEX IF NOT EXISTS folhasacesso_pessoa_idx ON public.folhasacesso (contaid, funcionarioid, emitidaem DESC);

ALTER TABLE public.folhasacesso ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.folhasacesso FROM anon, authenticated;
GRANT SELECT ON public.folhasacesso TO authenticated;
GRANT ALL ON public.folhasacesso TO service_role;
DROP POLICY IF EXISTS folhasacesso_ler ON public.folhasacesso;
-- Só o master da conta lê. Ninguém escreve pelo navegador: quem registra é o
-- servidor, na mesma chamada que monta a folha.
CREATE POLICY folhasacesso_ler ON public.folhasacesso FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()) AND (select public.sou_master()));

CREATE OR REPLACE FUNCTION public.registrar_folha_de_acesso(p_contaid integer, p_funcionarioid integer,
                                                            p_codigoid integer, p_redefiniu boolean, p_quem uuid)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_em timestamptz;
BEGIN
  IF NOT public.bot_contexto_confiavel() THEN
    RAISE EXCEPTION 'Só o servidor registra folha de acesso.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO public.folhasacesso (contaid, funcionarioid, codigoid, redefiniu, emitidapor)
  VALUES (p_contaid, p_funcionarioid, p_codigoid, coalesce(p_redefiniu, false), p_quem)
  RETURNING emitidaem INTO v_em;
  RETURN v_em;
END;
$$;
REVOKE ALL ON FUNCTION public.registrar_folha_de_acesso(integer, integer, integer, boolean, uuid) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.registrar_folha_de_acesso(integer, integer, integer, boolean, uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Tudo o que a folha precisa, numa consulta só
-- ---------------------------------------------------------------------------
-- Antes, os dados estavam em cinco lugares (pessoa, lojas, empresa, código e
-- acesso), e o código nem existia em forma legível. Interna: recebe a conta,
-- então só o servidor chama, depois de conferir que quem pediu é o master.
CREATE OR REPLACE FUNCTION public.folha_de_acesso(p_contaid integer, p_funcionarioids integer[])
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'conta',  c.nome,
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
             ) ORDER BY f.nomecompleto)
        FROM public.funcionarios f
        LEFT JOIN public.contasusuarios cu
               ON cu.contaid = f.contaid AND cu.funcionarioid = f.funcionarioid AND cu.papel = 'colaborador'
        LEFT JOIN LATERAL (SELECT k2.codigoid, k2.codigocifrado, k2.expiraem, k2.criadoem
                             FROM public.codigosacesso k2
                            WHERE k2.contaid = f.contaid AND k2.funcionarioid = f.funcionarioid
                              AND k2.usadoem IS NULL AND k2.canceladoem IS NULL AND k2.expiraem > now()
                            ORDER BY k2.criadoem DESC LIMIT 1) k ON true
       WHERE f.contaid = c.contaid AND f.funcionarioid = ANY (p_funcionarioids)), '[]'::jsonb))
    FROM public.contas c
   WHERE c.contaid = p_contaid AND public.bot_contexto_confiavel()
$$;
REVOKE ALL ON FUNCTION public.folha_de_acesso(integer, integer[]) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.folha_de_acesso(integer, integer[]) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. O cartão da pessoa mostra quem gerou o código e quem imprimiu a folha
-- ---------------------------------------------------------------------------
-- Parte da versão mais recente (20260927100500). Ganha colunas no fim, por
-- isso é recriada. Quem aparece é o e-mail do login do gestor.
DROP FUNCTION IF EXISTS public.situacao_dos_acessos();
CREATE OR REPLACE FUNCTION public.situacao_dos_acessos()
RETURNS TABLE (funcionarioid integer, temacesso boolean, nuncaentrou boolean,
               semsenha boolean, sempin boolean, codigopendente boolean,
               codigoexpiraem timestamptz, redefinidoem timestamptz,
               codigogeradoem timestamptz, codigogeradopor text, codigoreimprimivel boolean,
               folhaemitidaem timestamptz, folhaemitidapor text, folhas integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
                        ORDER BY k2.criadoem DESC LIMIT 1) k ON true
    LEFT JOIN LATERAL (SELECT max(x.emitidaem) AS emitidaem,
                              (array_agg(x.emitidapor ORDER BY x.emitidaem DESC))[1] AS emitidapor,
                              count(*) AS total
                         FROM public.folhasacesso x
                        WHERE x.contaid = f.contaid AND x.funcionarioid = f.funcionarioid) fa ON true
   WHERE f.contaid = (select public.minha_conta()) AND (select public.sou_master())
$$;
REVOKE ALL ON FUNCTION public.situacao_dos_acessos() FROM public, anon;
GRANT  EXECUTE ON FUNCTION public.situacao_dos_acessos() TO authenticated;

COMMIT;
