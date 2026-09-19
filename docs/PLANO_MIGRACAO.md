# Plano de Migração — Game GB (Python/SQL Server → React/Supabase)

> **Documento-guia do projeto.** Toda sessão de trabalho deve começar lendo este plano e terminar atualizando o **Status** e o **Registro de decisões**.
> Repositório: https://github.com/wisleyandersonvieira/game-gb
> Última atualização: 19/09/2026 (Fase 1 concluída — banco limpo aplicado no Supabase; ferramenta: Claude Code)

---

## Objetivo
Recolocar em funcionamento todas as funcionalidades do sistema original (painel web Flask, programas desktop Tkinter, rotinas automáticas, bot do Telegram) numa aplicação web única em React (TanStack Start) com banco Supabase (Postgres), desenvolvida com **Claude Code no VS Code**, acessível de qualquer lugar.

**Regras de ordem:**
- Integrações com o **bot do Telegram** ficam para a **Fase 11**. Até lá, o bot antigo pode continuar desligado ou rodando no SQL Server antigo, isolado.
- **Segurança** fica para a **Fase 12 (última)**, por decisão do Wisley. Riscos aceitos até lá: tokens do Telegram/Z-API e senhas expostas no `config.py` do repositório público; cadastro aberto no painel com RLS liberada para qualquer usuário logado.

## Status geral

| Fase | Tema | Status |
|---|---|---|
| 1 | Banco de dados (estrutura limpa, sem dados) | ✅ Concluída — 42 tabelas + `configuracoes` aplicadas no Supabase, vazias. Pendente do Wisley: recadastrar as tarefas/pessoas especiais e preencher os IDs em `configuracoes`. |
| 2 | Refazer as telas iniciais (Quadro, Equipe, Tarefas) | 🟨 Próxima — as 3 telas atuais quebraram (29 erros de TypeScript), como previsto |
| 3 | Painel Operacional + Validação | ⬜ Não iniciada |
| 4 | Gestão de pessoas e gamificação | ⬜ Não iniciada |
| 5 | Metas e Financeiro | ⬜ Não iniciada |
| 6 | Agenda (Agendamentos) | ⬜ Não iniciada |
| 7 | Escala, Mapa e Pausas | ⬜ Não iniciada |
| 8 | RH (Onboarding, Comunicados, Documentos) | ⬜ Não iniciada |
| 9 | Estoque (+ telas mobile) | ⬜ Não iniciada |
| 10 | Rotinas automáticas sem Telegram (pg_cron / Edge Functions / WhatsApp) | ⬜ Não iniciada |
| 11 | Bot do Telegram e notificações Telegram | ⬜ Não iniciada |
| 12 | Segurança | ⬜ Não iniciada |

Legenda: ⬜ não iniciada · 🟨 em andamento · ✅ concluída · ⏸️ pausada

---

## Fase 1 — Banco de dados no Supabase (estrutura limpa, sem dados)
Base para todas as fases seguintes. Referência completa: `docs/DICIONARIO_BANCO.md`.
- [x] Obter a estrutura do SQL Server → backup `banco_teste.bak`, lido direto das páginas do backup.
- [x] Converter o schema para Postgres (42 tabelas, 40 FKs, índices, defaults, identity).
- [x] Decisão de IDs: chaves primárias **inteiras com numeração automática** (como no original, não UUID), começando do 1.
- [x] Decisão de nomes: nomes originais **em minúsculas, sem aspas** (`FuncionarioID` → `funcionarioid`, `TarefasAtribuidas` → `tarefasatribuidas`). Mantém o SQL do Python compatível para a Fase 11.
- [x] **Decisão: banco limpo — nenhum dado do sistema antigo será importado.** Arquivo único `estrutura_banco.sql` (pacote `fase1_estrutura_banco.zip`), testado em Postgres 16 vazio: 42 tabelas, 40 FKs.
- [x] Preparar o repositório para o VS Code: `.gitignore` (node_modules, .output, .env, logs, __pycache__), mover o Python antigo para `legado/`, `bun install` e `bun run dev` funcionando.
- [x] Definir acesso ao Supabase. **Não foi preciso criar projeto novo:** o Wisley tem acesso ao projeto `asgdynxdcdnjglgyyaek` (GameGB) pela própria conta. `.env` atualizado com a chave publishable nova e Supabase CLI adicionado ao projeto.
- [x] Aplicar `supabase/migrations/20260919000000_estrutura_banco.sql` (`supabase db push`) → conferidas 42 tabelas, 40 FKs, todas vazias e com RLS.
- [x] Regenerar `src/integrations/supabase/types.ts` (`supabase gen types typescript`).
- [x] Criar tabela `configuracoes` (chave/valor) para os parâmetros do `config.py` (taxa ponto→real 0.03, bônus, horários das rotinas). 18 chaves criadas.
- [ ] Como o banco é limpo, os IDs fixos do `config.py` **não existem mais**. Recadastrar as tarefas/pessoas especiais e guardar os novos IDs em `configuracoes`: TAREFA_ID_FEEDBACK_DIARIO (era 5), TAREFA_ID_LEITURA (38), TAREFA_MODELO_AGENDAMENTO_ID (92), TAREFA_ID_PONTOS_META (121), TAREFA_ID_NOTA_FISCAL (156), TAREFA_ID_GUARDAR_MERCADORIA_MODELO (157), ID_GESTOR_PADRAO (2), RESPONSAVEL_AGENDAMENTOS_ID (3). *As 8 chaves já existem em `configuracoes` com valor vazio; falta o Wisley recadastrar e preencher.*
- [x] Criar buckets no Storage: `entregas` (fotos), `notas-fiscais`, `documentos-rh`, `layout-loja`. Criados privados; URLs assinadas revistas na Fase 12.
- [x] RLS provisória (usuário logado); endurecimento por papel na Fase 12.

**Pronto quando:** as 42 tabelas existem no Supabase (vazias). ✅ Atingido em 19/09/2026.

**Achados do banco real:**
- Não existe tabela `Transacoes`: o saldo fica em `funcionarios.saldopontos` (e `pontostotal`).
- Tabela extra não prevista: `metasdiariasinstancias`. Existe `usuariosadmin` (login do painel Flask).
- Havia FKs duplicadas no SQL Server (ex.: 3 FKs entregas→tarefas); mantida só uma por par de colunas para não confundir o Supabase.
- Os arquivos de carga de dados gerados antes foram descartados (continham CPF, telefones e hashes de senha).

## Fase 2 — Refazer as telas iniciais (Quadro, Equipe, Tarefas)
- [ ] Refazer as telas Quadro/Equipe/Tarefas sobre as tabelas reais (`funcionarios`, `tarefas`, `tarefasatribuidas`, `entregas`) — param de funcionar após a Fase 1.
- [ ] Atribuir tarefa **não** deve criar entrega. Entrega nasce quando o funcionário envia (por enquanto: botão "Registrar entrega" no painel com upload de foto; depois pelo bot).
- [ ] Aprovação credita pontos em `funcionarios.saldopontos` de forma atômica (função SQL `aprovar_entrega`), como o `database.py` fazia.
- [ ] Recusa exige motivo (`motivo_recusa`).
- [ ] Mostrar foto da entrega na validação (Storage).
- [ ] Ranking: diário e mensal (não "de todos os tempos").
- [ ] Tarefas recorrentes: tela de atribuição com frequência (Única / Diária / Semanal / Mensal), data de agendamento e fim de vigência.
- [ ] Editar/desativar funcionários e tarefas.

**Estado em 19/09/2026 (fim da Fase 1):** `bun run build` falha com **29 erros de TypeScript**, todos nestas três telas, porque elas ainda usam as tabelas de teste do Lovable:
- `src/routes/_authenticated/tarefas.tsx` — 17 erros (usa a tabela `tarefas_atribuidas`, que agora se chama `tarefasatribuidas`, e as colunas `tarefa_id`/`funcionario_id`/`atribuicao_id`)
- `src/routes/_authenticated/funcionarios.tsx` — 10 erros (usa `id`, `nome` e `ativo`; agora são `funcionarioid`, `nomecompleto` e não existe `ativo`)
- `src/routes/_authenticated/painel.tsx` — 2 erros (usa `id` e `status_validacao`; agora são `entregaid` e `statusvalidacao`)

Nenhum outro arquivo do projeto quebrou.

## Fase 3 — Painel Operacional + Validação (substitui `painel.html` aba Operacional e aba "Validar Entregas")
- [ ] Barra de progresso do dia + "última atualização" (auto-refresh / Realtime).
- [ ] Pódio diário.
- [ ] Kanban: Para Fazer (Hoje) · Em Validação · Atividade Recente (feed).
- [ ] Resgates recentes.
- [ ] Próximos agendamentos (após Fase 6, deixar placeholder).
- [ ] Animação de fogos ao bater meta (existia no original).

## Fase 4 — Gestão de pessoas e gamificação (abas do `main.py`)
- [ ] Grupos (criar, membros).
- [ ] Catálogo de tarefas completo.
- [ ] Pendências e justificativas ("Não aplicável").
- [ ] Loja de recompensas e resgates.
- [ ] Conquistas (cadastro e atribuição).
- [ ] Feedbacks / canal confidencial / solicitações internas (visão do gestor).
- [ ] Relatórios e histórico por funcionário.
- [ ] Extrato de pontos (substitui `pontos_analyzer.py`).
- [ ] Dashboard com gráficos.

## Fase 5 — Metas e Financeiro (aba Financeiro + "Gestão de Metas")
- [ ] Meta de faturamento mensal (principal).
- [ ] Modelos de meta diária por dia da semana.
- [ ] Apuração diária (lançar vendas — substitui `/lancar` do bot nesta fase).
- [ ] Mostrar/ocultar valores do dia.
- [ ] Meta de lucro + histórico em barras.
- [ ] Pontos automáticos para equipe ao bater meta diária (função SQL).

## Fase 6 — Agenda (substitui `agendamentos_main.py` e aba Agenda)
- [ ] Calendário (mês/semana).
- [ ] CRUD de agendamento: funcionário, cliente, telefone, CPF, data, hora, tipo, pagamento, observações.
- [ ] Marcar pagamento.
- [ ] Documentos anexos do agendamento (upload/download/excluir).

## Fase 7 — Escala, Mapa e Pausas (substitui `escala_loja_main.py` e aba Mapa)
- [ ] Mapa da loja com marcadores de posição (imagem `layout_loja.png`).
- [ ] Configurar posições e setores.
- [ ] Escala diária: montar, copiar escala, freelancers.
- [ ] Picos diários e gráfico de fluxo de equipe por setor.
- [ ] Escala de hoje + pausas com relógio em tempo real.

## Fase 8 — RH (substitui `gestao_pessoas_main.py`)
- [ ] Onboarding / admissional (checklist por funcionário).
- [ ] Comunicados com destinatários e confirmação de leitura.
- [ ] Documentos pessoais com ciência/assinatura.
- [ ] Geração de recibo/comunicado em PDF (substitui `recibo_generator.py` / `comunicado_generator.py`).

## Fase 9 — Estoque (substitui `gestao_estoque_main.py` + telas mobile)
- [ ] Catálogo mestre e categorias.
- [ ] Fornecedores e vínculo produto-fornecedor (DE/PARA).
- [ ] Importar XML de NF-e (parse no navegador ou Edge Function).
- [ ] Contagem física (desktop) + **tela mobile de contagem** com leitura de código de barras.
- [ ] **Auditoria de EAN mobile**.
- [ ] Desmembrar caixa (produto normal x caixa).
- [ ] Sugestão de compra.
- [ ] Solicitações dos líderes.
- [ ] Consulta de NFs.

## Fase 10 — Rotinas automáticas sem Telegram
Rotinas do `agendador.py` / `agendador_lembretes.py` que não dependem do Telegram, via **pg_cron** + funções SQL ou Edge Functions:
- [ ] Geração diária das tarefas recorrentes.
- [ ] Fechamento mensal (dia 1, 08:00) + HistoricoRanking.
- [ ] Delegação de tarefas de folga (09:05).
- [ ] WhatsApp (Z-API) via Edge Function: confirmação de agendamento (10:00) e pós-venda (14:10).
- [ ] Download/armazenamento de evidências e NFs no Storage.

## Fase 11 — Bot do Telegram e notificações
- [ ] Decidir: (a) reescrever `database.py` para Postgres (psycopg) e manter bot Python no servidor, ou (b) reescrever bot como Edge Function com webhook. *Recomendação inicial: (a).*
- [ ] Se (a): traduzir T-SQL → Postgres (443 consultas; `GETDATE()`×68, `CONVERT`×47, `ISNULL`×42, `TOP`×32, `SCOPE_IDENTITY`×26, placeholders `?` → `%s`).
- [ ] Comandos do bot: /start, /tarefas, /ranking, /meuhistorico, /meusaldo, /loja, /documentos, /conquistas, /ajuda, /pendencias, /status_meta, /lancar, /id.
- [ ] Recebimento de foto (entrega e NF) com validação EXIF (MAX_DIFERENCA_FOTO_SEGUNDOS = 120) → Storage.
- [ ] Canal confidencial, solicitações compras/manutenção, abate de comanda.
- [ ] Notificações Telegram: início/fim de jornada, lembretes intermediários, tarefas de grupo, lembretes de comunicados, lembretes de agendamento (hoje/amanhã/semanal), recusa com motivo, meta batida.
- [ ] Grupos do Telegram: gestor, agendamentos, folga/atendimento, cozinha, todos.
- [ ] Desligar serviços antigos (`systemctl`) e SQL Server.

## Fase 12 — Segurança (última)
- [ ] Revogar token do bot no @BotFather (`/revoke`) — o token atual está público no `config.py`.
- [ ] Gerar novos tokens na Z-API (instance token + client token).
- [ ] Trocar senha do usuário `sa` do SQL Server e a senha de admin.
- [ ] Tornar o repositório GitHub **privado**.
- [ ] Remover segredos do `config.py` → variáveis de ambiente (`.env` fora do Git).
- [ ] **Desativar cadastro público** (`signUp` em `src/routes/auth.tsx`).
- [ ] Senhas e chaves nunca no código: usar `.env` (ignorado pelo Git).
- [ ] Criar tabela `user_roles` (admin / gestor / lider) + função `has_role()` e trocar as policies RLS `USING (true)` por checagem de papel em todas as tabelas.
- [ ] Revisar buckets do Storage (privados + URLs assinadas).

**Pronto quando:** nenhum segredo no repositório; só usuários autorizados acessam o painel.

---

## Como trabalhar cada fase
Ferramenta: **Claude Code no VS Code**, direto no repositório. Regras permanentes em `CLAUDE.md`; este plano fica em `docs/PLANO_MIGRACAO.md` (cópia no projeto Claude "Game GB").
1. Começar a sessão pedindo: "Leia o CLAUDE.md e o docs/PLANO_MIGRACAO.md e continue a próxima fase pendente."
2. Claude Code implementa um item por vez, lendo o código Python original em `legado/` como referência de regra de negócio.
3. Wisley testa em `bun run dev` (http://localhost:8080) e aprova.
4. Claude Code marca os checkboxes, atualiza o Status e faz commit.

## Registro de decisões
| Data | Decisão |
|---|---|
| 18/09/2026 | Reconstruir o painel no Lovable (React + Supabase), aposentando Flask e Tkinter. |
| 18/09/2026 | Integrações com o bot do Telegram ficam para a Fase 11. |
| 18/09/2026 | Banco: nomes originais em minúsculas (compatibilidade com o Python) e chaves inteiras automáticas. |
| 18/09/2026 | Banco limpo: só estrutura e relacionamentos; nenhum dado antigo importado. IDs fixos do `config.py` passam para a tabela `configuracoes`. |
| 18/09/2026 | Desenvolvimento sai do Lovable e passa para Claude Code no VS Code. Python antigo movido para `legado/` como referência. |
| 18/09/2026 | Segurança movida para a última fase (Fase 12), por decisão do Wisley, com os riscos registrados em "Regras de ordem". |
| 19/09/2026 | O projeto Supabase do Lovable (`asgdynxdcdnjglgyyaek`) é acessível pela conta do Wisley. Decidido mantê-lo em vez de criar um novo, e apagar as 4 tabelas de teste do Lovable, cujos nomes conflitavam com os reais. |
| 19/09/2026 | `.env` deixou de ser versionado (estava rastreado pelo Git apesar do `.gitignore`). |
| 19/09/2026 | A tabela `configuracoes` usa a coluna `atualizado_em` (com underscore), conforme especificado pelo Wisley — exceção à regra de nomes, que vale para as tabelas herdadas do SQL Server. |

## Referência rápida — mapa arquivo original → fase
| Arquivo original | Fase |
|---|---|
| `api_server.py`, `templates/painel.html`, `static/js/painel.js` | 3, 5, 6, 7 |
| `main.py` (14 abas) | 2, 4, 5 |
| `pontos_analyzer.py` | 4 |
| `agendamentos_main.py` | 6 |
| `escala_loja_main.py` | 7 |
| `gestao_pessoas_main.py`, `recibo_generator.py`, `comunicado_generator.py` | 8 |
| `gestao_estoque_main.py`, `templates/mobile_*.html` | 9 |
| `agendador.py`, `agendador_lembretes.py`, `notificador_whatsapp.py` | 10 / 11 |
| `telegram_bot.py`, `notificador_telegram.py`, `database.py` | 11 |
| `config.py` (segredos) | 12 |
