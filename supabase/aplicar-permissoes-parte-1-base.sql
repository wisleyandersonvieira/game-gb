-- =========================================================================
-- STGame — Usuários gerenciais, PARTE 1: a base (nenhum gerente é ligado).
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-fechar-papel-gerente.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929248000_permissoes_base.sql
--
-- O QUE MUDA: cria o catálogo de permissões, os cargos, as lojas de cada
-- usuário gerencial, o histórico e a trava do último master (tudo vazio).
-- Fecha a gravação direta de 20 tabelas sem tela (escala, estoque, notas,
-- financeiro) e de 2 colunas da pessoa. Para o master, nada muda na tela.
-- Nenhum dado é alterado.
-- =========================================================================


BEGIN;

-- Usuários gerenciais, PARTE 1: a base (29/09/2026, aprovada pelo Wisley).
-- O mapa e as decisões estão em docs/MAPA_PERMISSOES.md.
--
-- Nada aqui liga um gerente: o papel "gerente" continua FECHADO
-- (20260929247000) e nenhuma tela cria cargo nem usuário. Esta parte só põe
-- no lugar o que as outras vão usar, e fecha o que sobrou aberto:
--   1. o CATÁLOGO de permissões (o que existe para marcar);
--   2. cargos, permissões de cada cargo, usuários gerenciais (com o vínculo
--      opcional ao funcionário) e as lojas de cada um;
--   3. o HISTÓRICO de quem mudou o quê (só recebe linha nova, nunca muda);
--   4. a trava do ÚLTIMO MASTER (a conta nunca fica sem master);
--   5. pode(permissão, loja): a única função que decide;
--   6. fecha a escrita direta de 20 tabelas sem tela e de 2 colunas.
--
-- Regra 2 do Wisley: o que não foi marcado, NÃO PODE. Permissão nova entra no
-- catálogo e nenhum cargo a recebe sozinho — nem o "Acesso total".

-- ---------------------------------------------------------------------------
-- 1. O catálogo de permissões
-- ---------------------------------------------------------------------------
-- É da PLATAFORMA (o mesmo para toda conta), por isso não é tabela: uma
-- tabela sem conta seria a exceção da seção 14. Mudar o catálogo é uma
-- migração nova que recria esta função.
-- Fica FORA do catálogo tudo o que nunca se delega (mapa, item d): usuários e
-- cargos, canal confidencial, documentos pessoais, criar/ativar/desativar
-- loja, refazer fechamento, desfazer ciência, parâmetros, mensagens
-- automáticas, política de uso, medir, trocar CPF, e os catálogos sem alcance
-- por loja (prêmios, conquistas, modelo de jornada, etapas de onboarding,
-- tipos de evento).
CREATE OR REPLACE FUNCTION public.catalogo_de_permissoes()
RETURNS TABLE (codigo text, tela text, nome text, ordem integer)
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
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
    ('metas.criar_meta',          'Metas',           'Criar meta',                           132),
    ('metas.meta_especial',       'Metas',           'Criar meta especial',                  133),
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
$$;
REVOKE ALL ON FUNCTION public.catalogo_de_permissoes() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.catalogo_de_permissoes() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Cargos, permissões do cargo, usuários gerenciais e as lojas de cada um
-- ---------------------------------------------------------------------------
-- Quem ESCREVE aqui: só as funções da página de Usuários (parte 5), que só o
-- master chama. O navegador só lê a própria conta, e só o master (o gerente
-- continua sem conta nenhuma para as regras de acesso).
CREATE TABLE IF NOT EXISTS public.cargos (
  cargoid   integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid   integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  nome      varchar(60) NOT NULL CHECK (length(btrim(nome)) > 0),
  criadoem  timestamptz NOT NULL DEFAULT now(),
  criadopor uuid,
  CONSTRAINT cargos_conta_unico UNIQUE (contaid, cargoid),
  CONSTRAINT cargos_nome_unico UNIQUE (contaid, nome)
);

CREATE TABLE IF NOT EXISTS public.cargospermissoes (
  contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  cargoid integer NOT NULL,
  codigo  varchar(40) NOT NULL,
  PRIMARY KEY (contaid, cargoid, codigo),
  CONSTRAINT cargospermissoes_cargo_fk FOREIGN KEY (contaid, cargoid)
    REFERENCES public.cargos (contaid, cargoid) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.usuariosgerenciais (
  contaid       integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  userid        uuid NOT NULL,
  cargoid       integer NOT NULL,
  -- Quem ele é na equipe, quando também é da equipe (decisão 5): com isso o
  -- banco recusa que ele registre, aprove ou estorne a PRÓPRIA entrega.
  funcionarioid integer,
  ativo         boolean NOT NULL DEFAULT true,
  criadoem      timestamptz NOT NULL DEFAULT now(),
  criadopor     uuid,
  PRIMARY KEY (contaid, userid),
  CONSTRAINT usuariosgerenciais_um_por_login UNIQUE (userid),
  CONSTRAINT usuariosgerenciais_um_por_pessoa UNIQUE (contaid, funcionarioid),
  CONSTRAINT usuariosgerenciais_cargo_fk FOREIGN KEY (contaid, cargoid)
    REFERENCES public.cargos (contaid, cargoid) ON DELETE RESTRICT,
  CONSTRAINT usuariosgerenciais_funcionario_fk FOREIGN KEY (contaid, funcionarioid)
    REFERENCES public.funcionarios (contaid, funcionarioid) ON DELETE RESTRICT,
  CONSTRAINT usuariosgerenciais_login_fk FOREIGN KEY (contaid, userid)
    REFERENCES public.contasusuarios (contaid, userid) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.usuarioslojas (
  contaid integer NOT NULL DEFAULT public.minha_conta() REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  userid  uuid NOT NULL,
  lojaid  integer NOT NULL,
  PRIMARY KEY (userid, lojaid),
  CONSTRAINT usuarioslojas_usuario_fk FOREIGN KEY (contaid, userid)
    REFERENCES public.usuariosgerenciais (contaid, userid) ON DELETE CASCADE,
  CONSTRAINT usuarioslojas_loja_fk FOREIGN KEY (contaid, lojaid)
    REFERENCES public.lojas (contaid, lojaid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS usuarioslojas_loja_idx ON public.usuarioslojas (contaid, lojaid);

-- Só código que existe no catálogo entra num cargo.
CREATE OR REPLACE FUNCTION public.cargospermissoes_codigo_valido()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.catalogo_de_permissoes() k WHERE k.codigo = NEW.codigo) THEN
    RAISE EXCEPTION 'Permissão "%" não existe.', NEW.codigo USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS cargospermissoes_codigo_valido ON public.cargospermissoes;
CREATE TRIGGER cargospermissoes_codigo_valido
  BEFORE INSERT OR UPDATE ON public.cargospermissoes
  FOR EACH ROW EXECUTE FUNCTION public.cargospermissoes_codigo_valido();

-- Usuário gerencial é um login com papel "gerente" da mesma conta.
CREATE OR REPLACE FUNCTION public.usuariosgerenciais_so_gerente()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.contasusuarios
                  WHERE contaid = NEW.contaid AND userid = NEW.userid AND papel = 'gerente') THEN
    RAISE EXCEPTION 'Só um login de gerente desta conta vira usuário gerencial.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS usuariosgerenciais_so_gerente ON public.usuariosgerenciais;
CREATE TRIGGER usuariosgerenciais_so_gerente
  BEFORE INSERT OR UPDATE ON public.usuariosgerenciais
  FOR EACH ROW EXECUTE FUNCTION public.usuariosgerenciais_so_gerente();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['cargos', 'cargospermissoes', 'usuariosgerenciais', 'usuarioslojas'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_sel', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated
                      USING (contaid = (select public.minha_conta()))', t || '_sel', t);
  END LOOP;
END $$;
COMMENT ON TABLE public.cargos IS 'Cargos gerenciais da conta ("Gerente de loja", "Supervisor"). Só o master cria e edita (página Usuários).';
COMMENT ON TABLE public.cargospermissoes IS 'O que cada cargo pode: um código do catálogo (catalogo_de_permissoes) por linha. Sem linha = não pode.';
COMMENT ON TABLE public.usuariosgerenciais IS 'Logins de gerente: o cargo, o funcionário que ele é (quando também é da equipe) e se está ativo.';
COMMENT ON TABLE public.usuarioslojas IS 'Em quais lojas cada usuário gerencial pode agir. Permissão e loja valem juntas.';

-- ---------------------------------------------------------------------------
-- 3. O histórico: quem mudou o quê, e quando (regra 6)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.permissoeshistorico (
  historicoid bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  contaid     integer NOT NULL REFERENCES public.contas (contaid) ON DELETE RESTRICT,
  em          timestamptz NOT NULL DEFAULT now(),
  quem        uuid,
  tabela      varchar(30) NOT NULL,
  acao        varchar(10) NOT NULL,
  antes       jsonb,
  depois      jsonb
);
CREATE INDEX IF NOT EXISTS permissoeshistorico_conta_idx ON public.permissoeshistorico (contaid, em DESC);
ALTER TABLE public.permissoeshistorico ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.permissoeshistorico FROM anon, authenticated;
GRANT SELECT ON public.permissoeshistorico TO authenticated;
GRANT SELECT, INSERT ON public.permissoeshistorico TO service_role;
DROP POLICY IF EXISTS permissoeshistorico_sel ON public.permissoeshistorico;
CREATE POLICY permissoeshistorico_sel ON public.permissoeshistorico FOR SELECT TO authenticated
  USING (contaid = (select public.minha_conta()));
COMMENT ON TABLE public.permissoeshistorico IS
  'Quem criou usuário gerencial, mudou cargo, lojas ou as permissões de um cargo, e quando. Gravado por gatilho; nunca muda nem se apaga.';

-- Grava UMA linha por mudança, de qualquer caminho (tela, servidor, SQL).
CREATE OR REPLACE FUNCTION public.registrar_mudanca_de_permissao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  -- Pelo JSON da linha: o mesmo gatilho serve a tabelas com colunas diferentes.
  v_antes  jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
  v_depois jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
BEGIN
  -- contasusuarios: só os papéis de gestão (tablet e colaborador não são daqui).
  IF TG_TABLE_NAME = 'contasusuarios'
     AND coalesce(v_depois->>'papel', '') NOT IN ('master', 'gerente')
     AND coalesce(v_antes->>'papel', '') NOT IN ('master', 'gerente') THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.permissoeshistorico (contaid, quem, tabela, acao, antes, depois)
  VALUES (coalesce((v_depois->>'contaid')::integer, (v_antes->>'contaid')::integer),
          auth.uid(), TG_TABLE_NAME, TG_OP, v_antes, v_depois);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.registrar_mudanca_de_permissao() FROM public, anon, authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['cargos', 'cargospermissoes', 'usuariosgerenciais', 'usuarioslojas', 'contasusuarios'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t || '_historico', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.registrar_mudanca_de_permissao()', t || '_historico', t);
  END LOOP;
END $$;

-- O histórico nunca muda nem se apaga: nem pelo dono do banco.
CREATE OR REPLACE FUNCTION public.historico_nao_muda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'O histórico de permissões não se altera nem se apaga.' USING ERRCODE = 'insufficient_privilege';
END;
$$;
DROP TRIGGER IF EXISTS permissoeshistorico_nao_muda ON public.permissoeshistorico;
CREATE TRIGGER permissoeshistorico_nao_muda
  BEFORE UPDATE OR DELETE ON public.permissoeshistorico
  FOR EACH ROW EXECUTE FUNCTION public.historico_nao_muda();

-- ---------------------------------------------------------------------------
-- 4. A conta nunca fica sem master (regra 3)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protege_ultimo_master()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.papel = 'master'
     AND (TG_OP = 'DELETE' OR NEW.papel IS DISTINCT FROM 'master' OR NEW.contaid IS DISTINCT FROM OLD.contaid)
     AND NOT EXISTS (SELECT 1 FROM public.contasusuarios
                      WHERE contaid = OLD.contaid AND papel = 'master' AND userid <> OLD.userid) THEN
    RAISE EXCEPTION 'A conta precisa de pelo menos um master: não dá para apagar nem rebaixar o último.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END;
$$;
REVOKE ALL ON FUNCTION public.protege_ultimo_master() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS contasusuarios_ultimo_master ON public.contasusuarios;
CREATE TRIGGER contasusuarios_ultimo_master
  BEFORE UPDATE OR DELETE ON public.contasusuarios
  FOR EACH ROW EXECUTE FUNCTION public.protege_ultimo_master();

-- ---------------------------------------------------------------------------
-- 5. pode(permissão, loja): a única função que decide
-- ---------------------------------------------------------------------------
-- Master: pode tudo o que está no catálogo, em qualquer loja DA CONTA DELE
-- (loja vazia = operação da conta). Gerente: só se o cargo tem a permissão E
-- a loja está na lista dele; operação da conta (loja vazia) nunca. Código fora
-- do catálogo: ninguém pode (um erro de digitação aparece na hora, até para o
-- master). Sem cache: cada chamada consulta as tabelas, então tirar uma
-- permissão vale na ação seguinte (regra 5).
CREATE OR REPLACE FUNCTION public.pode(p_codigo text, p_lojaid integer DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.catalogo_de_permissoes() k WHERE k.codigo = p_codigo)
     AND (
       -- master
       EXISTS (SELECT 1 FROM public.contasusuarios cu
                WHERE cu.userid = auth.uid() AND cu.papel = 'master'
                  AND (p_lojaid IS NULL
                       OR EXISTS (SELECT 1 FROM public.lojas l WHERE l.contaid = cu.contaid AND l.lojaid = p_lojaid)))
       OR
       -- gerente
       (p_lojaid IS NOT NULL AND EXISTS (
          SELECT 1
            FROM public.contasusuarios cu
            JOIN public.usuariosgerenciais ug ON ug.contaid = cu.contaid AND ug.userid = cu.userid AND ug.ativo
            JOIN public.contas c ON c.contaid = cu.contaid AND c.status <> 'cancelada'
            JOIN public.cargospermissoes cp ON cp.contaid = ug.contaid AND cp.cargoid = ug.cargoid AND cp.codigo = p_codigo
            JOIN public.usuarioslojas ul ON ul.userid = ug.userid AND ul.lojaid = p_lojaid AND ul.contaid = ug.contaid
           WHERE cu.userid = auth.uid() AND cu.papel = 'gerente'))
     )
$$;
REVOKE ALL ON FUNCTION public.pode(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pode(text, integer) TO authenticated;

-- As lojas onde quem chamou pode fazer X (para as leituras da parte 3).
CREATE OR REPLACE FUNCTION public.lojas_onde_posso(p_codigo text)
RETURNS integer[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(array_agg(l.lojaid ORDER BY l.lojaid), '{}')
    FROM public.lojas l
   WHERE EXISTS (SELECT 1 FROM public.catalogo_de_permissoes() k WHERE k.codigo = p_codigo)
     AND (
       EXISTS (SELECT 1 FROM public.contasusuarios cu
                WHERE cu.userid = auth.uid() AND cu.papel = 'master' AND cu.contaid = l.contaid)
       OR EXISTS (
          SELECT 1
            FROM public.contasusuarios cu
            JOIN public.usuariosgerenciais ug ON ug.contaid = cu.contaid AND ug.userid = cu.userid AND ug.ativo
            JOIN public.contas c ON c.contaid = cu.contaid AND c.status <> 'cancelada'
            JOIN public.cargospermissoes cp ON cp.contaid = ug.contaid AND cp.cargoid = ug.cargoid AND cp.codigo = p_codigo
            JOIN public.usuarioslojas ul ON ul.userid = ug.userid AND ul.lojaid = l.lojaid AND ul.contaid = ug.contaid
           WHERE cu.userid = auth.uid() AND cu.papel = 'gerente')
     )
$$;
REVOKE ALL ON FUNCTION public.lojas_onde_posso(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.lojas_onde_posso(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Fecha a escrita direta que não tem tela (decisão 6)
-- ---------------------------------------------------------------------------
-- 20 tabelas da Fase 2 (escala, estoque, notas fiscais, financeiro) aceitavam
-- gravação direta de quem estivesse logado, sem tela nenhuma. Fecha para
-- TODOS, master inclusive: quando a tela existir, ela nasce com função e
-- permissão. Funções do servidor e do banco continuam gravando.
REVOKE INSERT, UPDATE, DELETE ON
  public.configuracoesescala, public.configuracoessetores, public.escaladiaria, public.posicoesloja,
  public.picodiario, public.freelancers, public.grupos, public.funcionariosgrupos,
  public.contagensestoque, public.itenscontagemestoque, public.produtosestoque, public.fornecedores,
  public.produtosfornecedor, public.categoriasproduto, public.notasfiscais, public.notasfiscaisentrada,
  public.itensnotafiscalentrada, public.lucromensalhistorico, public.metasdiariasinstancias,
  public.feedbacksolicitacoes
FROM authenticated;

-- Duas colunas da pessoa que nenhuma tela grava. (O CPF continua: o
-- formulário da Equipe o grava ao cadastrar e editar quem ainda NÃO tem
-- login; quem já tem login só troca pelo "Trocar CPF", e isso o banco já
-- garante desde 27/09 — funcionarios_protege_cpf. Vira função na parte 2.)
REVOKE INSERT (isgestor, chatidtelegram), UPDATE (isgestor, chatidtelegram) ON public.funcionarios FROM authenticated;

-- ---------------------------------------------------------------------------
-- 7. Um nome que engana (pergunta do Wisley, 29/09/2026)
-- ---------------------------------------------------------------------------
COMMENT ON TABLE public.produtosloja IS
  'Prêmios da LOJA DE RECOMPENSAS (pontos), não de uma loja física. Vale para a CONTA INTEIRA: não tem lojaid, e o estoque do prêmio é um só para todas as lojas. O nome vem do sistema antigo (ProdutosLoja).';

COMMIT;
