-- Chaves primarias nas 5 tabelas que estavam sem, coluna ativo em funcionarios
-- e ajuste de nome na tabela configuracoes.
-- Decisoes do Wisley em 21/09/2026, registradas em docs/PLANO_MIGRACAO.md.

-- ---------------------------------------------------------------------------
-- Chaves primarias naturais.
-- Em todas as 5, o sistema antigo endereca a linha pela propria chave de
-- negocio (legado/database.py), nunca por um ID sintetico:
--   ConfiguracoesSetores  -> WHERE Setor = ?
--   FuncionariosGrupos    -> WHERE FuncionarioID = ? AND GrupoID = ?
--   MetasDiariasModelos   -> WHERE DiaSemanaID = ?
--   OnboardingStatus      -> WHERE FuncionarioID = ?
--   PicoDiario            -> WHERE DiaSemanaID = ?
-- A chave natural tambem impede duplicatas que quebrariam esses UPDATEs
-- (dois setores iguais, dois modelos de meta para a mesma segunda-feira,
-- dois onboardings para o mesmo funcionario).
-- ---------------------------------------------------------------------------

ALTER TABLE public.configuracoessetores
  ADD CONSTRAINT configuracoessetores_pkey PRIMARY KEY (setor);

ALTER TABLE public.funcionariosgrupos
  ADD CONSTRAINT funcionariosgrupos_pkey PRIMARY KEY (funcionarioid, grupoid);

ALTER TABLE public.metasdiariasmodelos
  ADD CONSTRAINT metasdiariasmodelos_pkey PRIMARY KEY (diasemanaid);

ALTER TABLE public.onboardingstatus
  ADD CONSTRAINT onboardingstatus_pkey PRIMARY KEY (funcionarioid);

ALTER TABLE public.picodiario
  ADD CONSTRAINT picodiario_pkey PRIMARY KEY (diasemanaid);

-- ---------------------------------------------------------------------------
-- Funcionario ativo/inativo.
-- Desligamento definitivo: ativo = false.
-- As datas de afastamento continuam servindo so para afastamento temporario.
-- ---------------------------------------------------------------------------

ALTER TABLE public.funcionarios
  ADD COLUMN ativo boolean NOT NULL DEFAULT true;

-- ---------------------------------------------------------------------------
-- Padroniza o nome da coluna (sem underscore, como as demais).
-- ---------------------------------------------------------------------------

ALTER TABLE public.configuracoes
  RENAME COLUMN atualizado_em TO atualizadoem;
