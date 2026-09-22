# Plano do Produto — Game GB (plataforma multi-empresa)

> **Documento-guia do projeto.** Toda sessão de trabalho começa lendo este plano e termina atualizando o **Status geral** e o **Registro de decisões**.
> Repositório: https://github.com/wisleyandersonvieira/game-gb · Supabase: `asgdynxdcdnjglgyyaek`
> Versão 2, de 21/09/2026: o projeto deixou de ser o sistema de uma loja e virou um **produto vendável (SaaS)**.


> **Numeração nova (21/09/2026).** O projeto tem **FASE 1 — Lançamento** e **FASE 2 — Expansão (adiada)**, e o que antes se chamava "fase" agora é **etapa**. O **registro de decisões e os commits anteriores usam a numeração antiga**:
>
> | Antiga | Nova | | Antiga | Nova |
> |---|---|---|---|---|
> | Fases 1 a 7 | Etapas 1.1 a 1.7 | | Fase 11 (RH) | Etapa 1.10 |
> | Fase 8 (Metas e financeiro) | Etapa 1.8 (só faturamento) + Etapa 2.3 (lucro) | | Fase 12 (Estoque) | **Etapa 2.2** |
> | Fase 9 (Agenda) | Etapa 1.9 | | Fase 13 (Rotinas) | Etapa 1.11 |
> | Fase 10 (Escala, mapa e pausas) | **Etapa 2.1** | | Fase 14 (Publicação + Stripe) | **Etapa 2.0** (saiu da Fase 1 em 23/09/2026) |
> | | | | Fase 15 (Telegram e WhatsApp) | Etapa 1.13 |
> | | | | Fase 16 (Segurança final) | Etapa 1.14 |

---

## Objetivo
Transformar o sistema de gamificação e gestão da Gela Boca num **produto vendido para várias empresas**:

- **Administrador geral (Wisley, `wisley_anderson@hotmail.com`):** dono da plataforma. Cadastra os clientes (usuários master), define quantas lojas cada um pode ter e, no futuro, cobra via Stripe.
- **Usuário master (cliente):** dono de uma empresa. Cadastra as próprias lojas, até o limite contratado, e gerencia equipe, tarefas, metas, agenda, escala, RH e estoque delas.
- **Isolamento total:** um master **nunca** vê dados de outro. Isso é garantido pelo banco (RLS), não só pelas telas.

Todas as funções do sistema antigo (painel Flask, programas Tkinter, rotinas automáticas, bot do Telegram) voltam a funcionar dentro desse modelo.

## Hierarquia

```
Administrador geral (Wisley)
 └── Conta (cliente = usuário master)      ← limite de lojas, status, no futuro assinatura Stripe
      ├── Lojas (1..limite)
      ├── Funcionários (da conta)  ──┐  um funcionário pode trabalhar em várias lojas
      ├── Tarefas (da conta)       ──┤  uma tarefa vale para uma ou várias lojas
      └── Dados operacionais ────────┘  entregas, escala, metas, agenda… (sempre de uma loja)
```

## Regras de ordem
1. **Fundação multi-empresa primeiro (Etapa 1.2).** Toda tela construída depois já nasce separando os dados por conta e por loja. Refazer depois custaria muito mais.
2. **O isolamento entre contas é construído agora, não no fim.** Num produto vendido, a separação dos dados de cada cliente faz parte da função principal. A Etapa 1.14 (Segurança) continua no fim, mas só com o *endurecimento*: tokens antigos, revisão geral, papéis extras.
3. **Stripe e Telegram ficam para o fim da Fase 1** (Etapas 1.12 e 1.13), nesta ordem, porque a cobrança do Telegram depende do Stripe.
4. Banco limpo: nenhum dado do sistema antigo é importado.
5. **A Fase 2 (Expansão) é adiada.** Nada dela é construído sem pedido explícito do Wisley. As tabelas existem no banco, mas ficam sem tela.

## Status geral

| Etapa | Tema | Status |
|---|---|---|
| **FASE 1** | **Lançamento** | |
| 1.1 | Banco de dados (estrutura do sistema antigo) | ✅ Concluída |
| 1.2 | **Fundação multi-empresa** (contas, lojas, isolamento, acesso) | ✅ Concluída |
| 1.3 | **Painel do administrador geral** | ✅ Concluída |
| 1.4 | **Gestão do usuário master** (lojas e seletor de loja) | ✅ Concluída |
| 1.5 | Telas iniciais: Equipe, Tarefas, Quadro | ✅ Concluída — o projeto inteiro compila sem nenhum erro de TypeScript |
| 1.6 | Painel operacional por loja + validação (dashboard da loja) | ✅ Concluída |
| 1.7 | Gestão de pessoas e gamificação | ✅ Concluída (22/09/2026) — partes 1, 2 e 3 |
| 1.8 | Metas de faturamento | ✅ Concluída (22/09/2026) |
| 1.9 | Agenda (agendamentos) | ✅ Concluída (22/09/2026) |
| 1.10 | RH (onboarding, comunicados, documentos) | ✅ Concluída (22/09/2026) |
| 1.10B | Reestruturação visual (tema, layout único, celular, tela Início) | ✅ Concluída |
| 1.11 | Rotinas automáticas sem Telegram | ✅ Concluída (22/09/2026) |
| 1.12 | **Visões LOJA e COLABORADOR** (tablet da loja e celular do colaborador) | 🟨 Proposta em análise (23/09/2026); nada programado |
| 1.13 | **Telegram e WhatsApp da plataforma** + cobrança por uso | 🟨 1.13A e 1.13B1 prontas (22/09/2026), aguardando o teste na loja · 1.13B2 e 1.13C a fazer |
| 1.14 | Segurança final (endurecimento) | ⬜ |
| **FASE 2** | **Expansão — adiada** | Nada daqui é construído sem pedido explícito do Wisley |
| 2.0 | **Comercialização:** publicação online + Stripe (era 1.12) | ⏸️ Adiada |
| 2.1 | Escala, mapa e pausas | ⏸️ Adiada |
| 2.2 | Estoque (+ telas de celular) | ⏸️ Adiada |
| 2.3 | Financeiro (meta de lucro, histórico de lucro, relatórios) | ⏸️ Adiada |

Legenda: ⬜ não iniciada · 🟨 em andamento · ✅ concluída · ⏸️ adiada

---

## FASE 1 — Lançamento

### Etapa 1.1 — Banco de dados (estrutura do sistema antigo) ✅
- [x] Estrutura extraída do backup `banco_teste.bak` e convertida para Postgres: 42 tabelas, 40 FKs, índices.
- [x] Nomes originais em minúsculas (`FuncionarioID` → `funcionarioid`); chaves inteiras automáticas.
- [x] Banco limpo, sem dados antigos.
- [x] Repositório preparado para o VS Code; Python antigo em `legado/`.
- [x] Aplicado no Supabase; `types.ts` gerado.
- [x] Tabela `configuracoes` (18 chaves) e buckets `entregas`, `notas-fiscais`, `documentos-rh`, `layout-loja`.
- [x] Chaves primárias naturais nas 5 tabelas sem PK; `funcionarios.ativo`; `configuracoes.atualizadoem`.
- ⚠️ Vários itens desta fase **mudam na Etapa 1.2**: chaves e unicidades passam a ser por conta/loja, e `configuracoes` passa a ser por conta.

### Etapa 1.2 — Fundação multi-empresa
O banco ainda está vazio, então as mudanças são baratas agora. Tudo aqui é migração nova em `supabase/migrations/`, testada num Postgres descartável antes de ir para o Supabase.

**2.1 Tabelas novas**
- [x] `contas`: `contaid`, `nome` (nome do cliente/empresa), `email`, `telefone`, `cidade`, `limitelojas` (int, padrão 1), `status` (`ativa` / `suspensa` / `cancelada`), `observacoes`, `criadoem`.
- [x] `contasusuarios`: `contaid`, `userid` (→ `auth.users`), `papel` (hoje só `master`; no futuro `gerente`). PK (`contaid`, `userid`). **Regra: um login pertence a uma única conta.**
- [x] `lojas`: `lojaid`, `contaid`, `nome`, `cidade`, `endereco`, `ativa`, `criadoem`.
- [x] `funcionarioslojas`: (`funcionarioid`, `lojaid`). Liga um funcionário a várias lojas.
- [x] `tarefaslojas`: (`tarefaid`, `lojaid`). Define em quais lojas a tarefa vale.

**2.2 Coluna de conta e de loja nas tabelas existentes**
- [x] Todas as tabelas do sistema ganham `contaid NOT NULL` (→ `contas`), com padrão `minha_conta()`, para o front-end nunca precisar informar.
- [x] As tabelas que pertencem a uma loja ganham também `lojaid` (→ `lojas`). **Antes de migrar, o Claude Code apresenta ao Wisley uma tabela "tabela → nível (conta ou loja)" para aprovação.** Sugestão inicial:
  - **Nível conta (compartilhado entre as lojas):** funcionarios, tarefas, conquistas, conquistasfuncionarios, produtosloja (loja de recompensas), resgates, feedbacks, feedbacksolicitacoes, denunciasanonimas, documentos, documentosassinaturas, documentospessoais, documentospessoaisciencia, onboardingstatus, categoriasproduto, fornecedores, produtosestoque, produtosfornecedor, configuracoes, configuracoessetores, historicoranking.
  - **Nível loja:** tarefasatribuidas, entregas, grupos (grupos do Telegram são da loja), funcionariosgrupos, escaladiaria, configuracoesescala, posicoesloja, picodiario, freelancers, agendamentos, metasprincipais, metasdiariasmodelos, metasdiariasapuracoes, metasdiariasinstancias, lucromensalhistorico, contagensestoque, itenscontagemestoque, notasfiscais, notasfiscaisentrada, itensnotafiscalentrada, solicitacoesinternas.
- [x] Refazer chaves e unicidades para serem **por conta/loja**, por exemplo: `configuracoessetores` (contaid, setor); `metasdiariasmodelos` e `picodiario` (lojaid, diasemanaid); `configuracoes` (contaid, chave); nomes únicos de grupos, conquistas e categorias, EAN de produto, CNPJ de fornecedor e `lucromensalhistorico`, todos únicos **dentro da conta**, não no sistema inteiro.
- [x] Garantias no banco: um funcionário só pode ser ligado a lojas da própria conta (o mesmo vale para tarefas e para toda FK entre tabelas); lojas ativas ≤ `contas.limitelojas`; conta `suspensa` fica só leitura.
- [x] `usuariosadmin` (login do painel Flask antigo) fica obsoleto: remover.

**2.3 Isolamento (RLS)**
- [x] Função `eh_admin_geral()`: verdadeiro somente para o login `wisley_anderson@hotmail.com` com e-mail confirmado. **Fixa no banco.**
- [x] Função `minha_conta()`: a conta do usuário logado (via `contasusuarios`).
- [x] Trocar **todas** as policies `USING (true)` por `contaid = minha_conta()`. `contas` e `contasusuarios`: o admin geral pode tudo; o master só lê a própria conta.
- [x] Storage: arquivos gravados em `<contaid>/<lojaid>/...`, com policies por pasta.
- [x] **Teste automático de isolamento:** cria 2 contas com 2 usuários e prova que A não lê, altera nem apaga nada de B, em todas as tabelas. Esse teste roda de novo a cada migração futura.

**2.4 Acesso e navegação**
- [x] Desligar o cadastro público (tela e configuração do Supabase Auth). Só entra quem foi convidado.
- [x] Depois do login: admin geral → `/admin`; master → `/gestao`; login sem conta → tela "sem acesso".
- [x] `client.ts` lendo URL e chave do `.env`. A chave `service_role` fica **só** em variável de servidor, nunca `VITE_`.
- [x] Atualizar `CLAUDE.md` e `docs/DICIONARIO_BANCO.md` com o modelo novo.

**Feito em 21/09/2026 (2.1 a 2.3):** 47 tabelas, nenhuma sem RLS, 201 policies, nenhuma liberada, banco vazio. O teste de isolamento (`supabase/tests/rodar.sh`) roda 30 checagens com duas contas e passa. Ele já pegou um bug antes de ir para o Supabase: as policies de Storage da Etapa 1.1 não eram removidas e, como policies se somam, vazavam arquivos entre contas.

**Feito em 21/09/2026 (2.4):** cadastro público desligado na tela e no Supabase Auth (`disable_signup`). URL do site e lista de redirecionamentos apontando para `http://localhost:8080`. A porta de entrada (`/`) encaminha conforme o banco responde: admin geral → `/admin`, master → `/gestao`, login sem conta → `/sem-acesso`. Rota `/definir-senha` criada para o link do convite.

**Pronto quando:** o teste de isolamento passa e cada tipo de usuário cai na sua área.

### Etapa 1.3 — Painel do administrador geral (só o Wisley)
- [x] Rota `/admin`, visível e acessível somente se `eh_admin_geral()`. A proteção vale na tela e no banco.
- [x] Cadastro de usuários master (contas): nome, e-mail, telefone, cidade, **quantidade de lojas liberadas**, status, observações.
- [x] Criar o master envia um **convite por e-mail** para ele definir a senha (função de servidor com `service_role`).
- [x] Editar, suspender, reativar, reenviar convite.
- [x] Lista com lojas usadas / lojas liberadas por cliente.
- [x] Decisão registrada: o admin geral **não** vê os dados operacionais dos clientes (equipe, tarefas etc.), só o cadastro da conta. *(Rever se precisar de suporte: modo "ver como cliente" com registro de acesso.)*

**Feito em 21/09/2026.** As funções de servidor ficam em `src/servidor/contas.ts`. A chave `service_role` é lida em `client.server.ts` a partir de `process.env` (sem `VITE_`), por import dinâmico dentro do handler, para não entrar no pacote que vai para o navegador. **Toda** função confere `eh_admin_geral()` no servidor, com o token de quem chamou — esconder o botão na tela não é proteção. Se o convite falhar, a conta recém-criada é desfeita, para não sobrar cadastro pela metade. Criar um cliente já semeia as configurações padrão dele.

⚠️ Para o convite funcionar, `STGAME_SERVICE_ROLE_KEY` precisa estar preenchida no `.env` (modelo em `.env.example`) e, na publicação, nos Secrets do Lovable. Sem ela a tela abre e lista, mas o cadastro dá erro.

### Etapa 1.4 — Gestão do usuário master
- [x] Rota `/gestao`: dados da conta e contador "X de Y lojas usadas".
- [x] Cadastro de lojas (criar, editar, desativar). O botão "Nova loja" fica bloqueado quando atinge o limite, com a mensagem "fale com o suporte para ampliar".
- [x] **Seletor de loja** no topo do app (loja ativa lembrada no navegador). Telas de nível loja mostram só a loja selecionada; telas de nível conta mostram tudo, com filtro por loja.
- [x] Criar uma conta nova preenche automaticamente as `configuracoes` padrão (taxa 0,03, bônus, horários).
- [x] Espaço reservado para o **dashboard por loja** (preenchido na Etapa 1.6).

**Feito em 21/09/2026.** O seletor de loja fica no menu do topo (`src/lojas/loja-ativa.tsx`), lembra a escolha no navegador e, se a loja lembrada for desativada, cai para a primeira em vez de deixar a tela sem loja. Com uma loja só, ela aparece como texto, sem seletor. Sem loja nenhuma, as telas do app mostram "Cadastre sua primeira loja" com link para a gestão.

As regras de limite já valiam no banco desde a Etapa 1.2 e foram **provadas por teste**, não só pela tela: loja desativada não ocupa vaga, desativar é sempre permitido (mesmo no limite), reativar acima do limite é recusado, e desativar não apaga nada — as atribuições e entregas daquela loja continuam inteiras. A tela apenas reflete isso: o botão "Nova loja" some no limite e o "Reativar" fica bloqueado quando não há vaga.

### Etapa 1.5 — Telas iniciais: Equipe, Tarefas, Quadro
- [x] Equipe: listar, cadastrar, editar, ativar/desativar, dia de folga, filtro de inativos. *(Feita antes da Etapa 1.2)*
- [x] Equipe: campo **lojas** (seleção múltipla; o funcionário pode estar em várias) e filtro por loja.
- [x] Tarefas: cadastrar, editar, desativar, com **seleção das lojas onde a tarefa vale**.
- [x] Atribuição: só permite atribuir a funcionários que trabalham numa loja onde a tarefa vale. Registra a loja.
- [x] Atribuir tarefa **não** cria entrega. A entrega nasce quando o funcionário envia (por enquanto, botão "Registrar entrega" com foto; depois, pelo bot).
- [x] Recorrência: mostrar ao Wisley os tipos de frequência do sistema antigo (`legado/`) e como funcionavam, **antes** de implementar.
- [x] Quadro (validação): aprovar, com crédito atômico de pontos pela função SQL `aprovar_entrega`; recusar, com motivo obrigatório; foto da entrega.
- [x] Ranking diário e mensal, por loja e geral da conta.
- [x] Remover `ID_GESTOR_PADRAO` e `RESPONSAVEL_AGENDAMENTOS_ID` como IDs soltos: viram campos escolhidos na tela (por loja).
- [x] Recadastrar as tarefas especiais do sistema (feedback diário, leitura, nota fiscal, pontos da meta, guardar mercadoria, modelo de agendamento) como **tarefas do sistema criadas automaticamente em cada conta nova**, com os IDs registrados em `configuracoes`.

**Feito em 21/09/2026 (parte 1: Tarefas e atribuição).** A tela Tarefas tem duas abas: o **Catálogo** (cadastrar, editar, desativar, escolhendo em quais lojas a tarefa vale) e as **Atribuições da loja** (dentro da loja escolhida no seletor do topo).

As frequências oferecidas são as quatro individuais do sistema antigo: **Única, Diária, Semanal e Mensal**. Na Semanal dá para marcar vários dias; o banco guarda uma linha por dia, mas a tela mostra uma linha só ("Toda Seg, Qua, Sex") e o botão Encerrar encerra todos os dias juntos. Encerrar preenche a data de fim de vigência — nunca apaga.

**O que o banco garante, e não só a tela:** a tarefa tem que valer naquela loja, a pessoa tem que trabalhar naquela loja (chaves compostas da Etapa 1.2), as 4 tarefas de bônus não podem ser atribuídas a ninguém, e tarefa do sistema não pode ser apagada. A função `tarefa_cai_no_dia()` centraliza a regra de quando uma tarefa recorrente aparece, para a tela e as rotinas automáticas nunca discordarem.

**Feito em 21/09/2026 (parte 2: entregas, validação e ranking).**

- **Registrar entrega** (enquanto o bot não existe): no Quadro, escolhe-se uma atribuição que cai hoje ou está atrasada, com foto e observação opcionais, e a opção "registrar já aprovada". A foto vai para `entregas/<contaid>/<lojaid>/...`, e o banco recusa foto fora da pasta da própria loja.
- **Quadro** da loja ativa em três colunas: Pendentes, Aprovadas e Recusadas/estornadas (histórico de 7 dias). A foto aparece por link temporário de 1 hora; o bucket é privado.
- **Aprovar / Recusar / Estornar** só pelas funções `aprovar_entrega`, `recusar_entrega` e `estornar_entrega`. Cada uma trava a linha da entrega, confere o status e faz tudo numa transação: aprovar duas vezes não credita em dobro, estornar duas vezes não desconta em dobro. Recusa e estorno exigem motivo, e o banco recusa sem ele. O estorno registra quem, quando e por quê, e pode deixar o saldo negativo (a tela avisa em destaque).
- **Sem entrega duplicada:** no máximo uma pendente ou aprovada por atribuição por dia (fuso de São Paulo). Recusada ou estornada libera outra.
- **Ninguém mexe em pontos por fora.** O navegador não grava mais direto em `entregas`, nem em `saldopontos`/`pontostotal`. Só as funções mexem.
- **Ranking** diário e mensal, da loja ativa ou de todas, pela soma dos pontos aprovados na data da aprovação.
- **Gestor e responsável pelos agendamentos** viraram campos de cada loja (`lojas.gestorid`, `lojas.responsavelagendamentosid`), escolhidos na Gestão entre quem trabalha ali. O banco garante isso pela chave composta pessoa + loja. As duas chaves soltas saíram de `configuracoes`.
- Na aba Atribuições, filtro "mostrar também as encerradas".

⚠️ **Correção de segurança feita nesta fase.** As funções `cria_configuracoes_padrao` e `cria_tarefas_do_sistema` (Etapa 1.5, parte 1) rodavam com poder total, não conferiam quem chamou e ficaram executáveis por qualquer um — o Supabase dá permissão automática a `anon` e `authenticated` em toda função nova, e o `REVOKE ... FROM public` não tirava isso. Um cliente, ou até um visitante sem login, conseguiria chamá-las com o número de outra conta. Corrigido: só o servidor executa. O ambiente de teste passou a imitar essas permissões automáticas do Supabase, e o teste de isolamento ganhou uma checagem que reprova qualquer função com poder total executável por quem não confere o chamador.

### Etapa 1.6 — Painel operacional por loja + validação (dashboard da loja)
Substitui a aba Operacional do `painel.html`. É também o **dashboard por loja** da gestão.
- [x] Barra de progresso do dia e hora da última atualização (Realtime).
- [x] Pódio diário.
- [x] Kanban: Para Fazer (hoje) · Em Validação · Atividade Recente.
- [x] Resgates recentes — espaço reservado; preenchido na Etapa 1.7.
- [x] Próximos agendamentos — espaço reservado; preenchido na Etapa 1.9.
- [x] Fogos ao completar 100% das tarefas do dia. A meta de faturamento entra junto na Etapa 1.8.
- [x] Na `/gestao`: resumo de todas as lojas lado a lado.
- [x] **Modo TV** com link por loja.

**Feito em 21/09/2026.**

- **Painel** (item novo no menu, `/operacional`): barra do dia em duas cores (verde = aprovado; faixa clara = entregue esperando validação), pódio do dia, e as colunas Para fazer hoje, Em validação e Atividade recente. Espaços reservados para Meta do dia (Etapa 1.8), Resgates recentes (Etapa 1.7) e Próximos agendamentos (Etapa 1.9).
- **Tempo real**: o painel logado se atualiza na hora em que alguém registra, aprova ou recusa (Realtime do Supabase em `entregas` e `tarefasatribuidas`, sempre respeitando a RLS), com uma conferência a cada 60 segundos.
- **Barra do dia corrigida** em relação ao sistema antigo: só as tarefas de hoje (a antiga somava pendências de semanas atrás), sem bônus (a antiga contava feedback e nota fiscal como tarefa), e recusada/estornada volta para "a fazer". Só conta quem está ativo e continua naquela loja.
- **Uma só fonte de dados**: a função interna `montar_painel` alimenta o painel logado, a TV e o resumo da Gestão. Ela nunca devolve id, foto, observação, telefone ou CPF.
- **Gestão**: um cartão por loja com o progresso, as entregas esperando validação e o líder do dia. Clicar leva ao painel daquela loja.
- **Modo TV** (`/tv/<código>`): criado na Gestão, mostrado uma única vez (o banco guarda só a impressão digital sha256). Sem login, só lê, letras grandes, tela cheia ao tocar, tenta manter a tela acesa, atualiza a cada 30 segundos, nomes como "Ana S.". Mostra "Painel indisponível" se o link for revogado, a loja desativada ou a conta suspensa/cancelada — sempre a mesma resposta, sem dizer o motivo. Registra o último uso, e a Gestão mostra "no ar agora" / "usado há X min".

⚠️ **Duas correções de segurança nesta fase, pegas pelo teste antes de ir para produção:**
1. `montar_painel` recebe o `contaid` como parâmetro e tinha ficado executável por qualquer cliente logado — um cliente conseguiria ler o painel de outro passando o número dele. Mesma causa do furo da Etapa 1.5: o Supabase dá permissão automática em toda função nova.
2. Para não depender mais de lembrar: **funções agora nascem negadas para todo mundo**, e cada migração libera explicitamente o que precisa. Regra registrada no `CLAUDE.md`. Detalhe técnico que custou uma rodada: a permissão padrão de `PUBLIC` em funções só pode ser retirada de forma global — com `IN SCHEMA` o Postgres aceita o comando e não faz nada.

O visitante sem login (`anon`) agora só chama `painel_da_tv` e **não tem acesso a nenhuma tabela**. Antes a RLS já impedia a leitura, mas o acesso existia. Conferido de fora, pela internet, em produção.

- [x] **Rodízio de telas no Modo TV**: painel da loja, meta do dia (Etapa 1.8) e agenda (Etapa 1.9), 30 s cada, só as telas com conteúdo. O mapa entra só na Etapa 2.1. *(22/09/2026)*

### Etapa 1.7 — Gestão de pessoas e gamificação (abas do `main.py`)
> Dividida em partes: **parte 1** prêmios, resgates, comanda e extrato · **parte 2** conquistas, nota do ranking mensal, relatórios e configurações · **parte 3** feedbacks, canal confidencial, solicitações e justificativas. Os **grupos** foram para a Etapa 1.13, junto com o Telegram.
- [x] Pendências e justificativas ("Não se aplica"). *(parte 3, 22/09/2026)*
- [x] Loja de recompensas e resgates. *(parte 1, 21/09/2026)*
- [x] Abate na comanda (pontos usados como dinheiro). *(parte 1)*
- [x] Conquistas. *(parte 2, 22/09/2026)* Critérios de feedback, comunicados e grupos ficam cadastráveis e passam a valer quando esses módulos existirem.
- [x] Feedbacks, canal confidencial e solicitações internas (visão do gestor). *(parte 3)*
- [x] Menu agrupado (Operação, Pessoas, Gamificação, Relatórios, Gestão), com versão para celular. *(parte 3)*
- [x] Relatórios e histórico por funcionário. *(parte 2)*
- [x] **Nota híbrida do ranking mensal**: 50% confiabilidade (pontos das tarefas atribuídas ÷ pontos possíveis no mês, travado em 100%, sem os bônus) + 50% esforço (pontos aprovados ÷ os de quem mais fez, em cima de 100). *(parte 2)*
- [x] **Configurações** da conta (taxa ponto→real, bônus, horários das rotinas), com validação, só o master altera e histórico de mudanças. *(parte 2)*
- [x] Nomes neutros nos endereços da loja de prêmios (bloqueadores de anúncio). *(parte 2)*
- [x] Extrato de pontos (substitui `pontos_analyzer.py`). *(parte 1)*

**Feito em 21/09/2026 (parte 1).**

- **Livro de movimentos** (`movimentospontos`): toda entrada e saída de pontos vira uma linha que nunca se altera nem se apaga. O saldo é atualizado **só** por um gatilho desse livro; qualquer outro caminho que tente mudar `saldopontos` ou `pontostotal` é recusado pelo banco — navegador, função com poder total, servidor e até o dono do banco. A migração criou o livro a partir das entregas já existentes; em produção o saldo bateu sem nenhum ajuste.
- **Prêmios** (item novo no menu): catálogo (estoque em branco = ilimitado, 0 = esgotado), registrar resgate e lista de resgates com Entregar, Cancelar e Estornar. O gestor registra já como "Entregue", ou marca "entregar depois" (Pendente).
- **Resgate atômico** (`registrar_resgate`): trava a pessoa e o prêmio, confere saldo e estoque e desconta os dois de uma vez. Resgate nunca deixa o saldo negativo. Provado com duas conexões simultâneas de verdade: uma espera a outra e é recusada.
- **Situações**: Pendente → Entregue; Pendente → Cancelado; Entregue → Estornado. Cancelar e estornar exigem motivo, devolvem pontos e estoque, e só funcionam uma vez.
- **Abate na comanda** (`registrar_abate_comanda`): prêmio do sistema escondido do catálogo. O banco lê a taxa da conta, arredonda para cima e confere o saldo na hora. O resgate guarda R$, pontos e a taxa usada: mudar a taxa só vale para comandas novas.
- **Extrato** (item novo no menu): pessoa e período, saldo inicial, saldo final, saldo atual (em pontos e em R$ pela taxa atual), e cada movimento com data, loja, pontos e saldo após. Mostra se o saldo bate com a soma dos movimentos.

**Feito em 22/09/2026 (parte 2).**

- **Conquistas** (item novo no menu): criar com ícone, nome, regra, quantidade e bônus. Regras que já valem: total de tarefas aprovadas, "N tarefas em X dias" (o X é escolhido na conquista) e dias seguidos com tarefa entregue. Na criação o gestor escolhe **"vale para o histórico"** (quem já cumpre ganha na hora) ou **"só a partir de hoje"**; essa escolha e a regra não mudam depois (o banco recusa). Nome, ícone, descrição, bônus e ativa/desativada podem mudar. Aba "Quem ganhou".
- **Uma vez por pessoa, garantido pelo banco** (`UNIQUE (funcionarioid, conquistaid)`), inclusive com duas aprovações ao mesmo tempo — provado com duas conexões simultâneas. O bônus entra pelo livro de pontos (movimento "bônus" com a conquista ligada) e aparece no extrato. Estornar uma tarefa não tira a conquista. Só contam tarefas atribuídas e aprovadas, pelo dia do envio.
- **Sequência de dias**: folga semanal, domingo de folga e afastamento (férias/atestado) não quebram a sequência nem contam como dia feito. É a mesma função (`dia_de_trabalho`) da nota do mês.
- **Nota do mês** (Ranking → "Nota do mês", com escolha do mês): confiabilidade pelo dia do envio, contando só os dias em que a tarefa cai (mesma regra de `tarefa_cai_no_dia`), dentro da vigência, e só dias de trabalho da pessoa. Mês corrente vai até ontem. Bônus de conquista não entra.
- **Relatórios** (item novo no menu): *Por pessoa* — saldo, total ganho, conquistas, o que ficou por fazer (dia a dia, até ontem, sem folga/afastamento, no máximo 3 meses por vez) e as últimas entregas. *Por tarefa* — aprovadas, recusadas, estornadas e aguardando, com as mais recusadas no topo.
- **Configurações** (item novo no menu): taxa do ponto, bônus e horários das rotinas. O banco valida (taxa maior que zero e no máximo R$ 10; bônus inteiro de 0 a 10.000; horário HH:MM), só o master altera (gerente e conta suspensa não), e cada mudança fica registrada com quem, quando, valor antigo e novo. Os IDs das tarefas do sistema não aparecem nem se alteram pela tela. Ninguém altera a tabela direto: só pela função `alterar_configuracao`.
- **Nomes neutros**: `registrar_troca`, `registrar_troca_por_valor`, `concluir_troca`, `cancelar_troca`, `estornar_troca` e `listar_trocas` (a lista não lê mais a tabela `resgates` pelo endereço). Todos os 66 endereços do app (funções, tabelas, arquivos, páginas, login) passaram por 8 listas de bloqueio (EasyList, EasyPrivacy, EasyList Português, uBlock, uBlock Privacy, AdGuard Base, AdGuard Tracking, Fanboy Annoyance — 528 mil regras): **nenhum é barrado**.

⚠️ **Deadlock evitado nesta parte.** A primeira versão da concessão de conquistas travava a pessoa com `FOR UPDATE` depois de gravar no livro; duas aprovações simultâneas da mesma pessoa se travavam mutuamente e uma falhava. O teste de concorrência pegou; a trava virou `FOR NO KEY UPDATE`, o mesmo nível do gatilho do saldo.

**Feito em 22/09/2026 (parte 3). Etapa 1.7 fechada.**

- **Feedbacks** (Pessoas → Feedbacks): nota de 0 a 10 e comentário opcional, **um por pessoa por dia** (índice único no banco, provado com duas conexões ao mesmo tempo), só **hoje ou ontem**, marcado "registrado pelo gestor". O bônus (`PONTOS_BONUS_FEEDBACK_DIARIO`) entra pelo livro, ligado ao feedback, e aparece no extrato. A nota **não se altera nem se apaga**; se foi erro, o gestor **anula com motivo** e o bônus é estornado pelo livro (movimento novo `estorno_bonus`); a conquista fica. Anulado libera o dia para o lançamento certo. Bônus de feedback fica **fora do ranking**. Lista com filtro e média por pessoa.
- **Conquistas de "dias seguidos com feedback" passam a valer**, com folga, domingo de folga e afastamento neutros.
- **Justificativas** (Pessoas → Justificativas, e o botão "Não se aplica" em Relatórios → O que ficou por fazer): só para dia de trabalho em que a tarefa caía e não foi entregue; uma por tarefa e dia; nunca dia futuro. Dois botões: **"Registrar e aceitar"** e **"Registrar para decidir depois"** (aba "Para decidir", com Aceitar/Recusar; recusar exige motivo). **Aceita:** sai das pendências, sai dos pontos possíveis da nota do mês, some do Painel/Quadro do dia e **vira dia neutro na sequência de dias** (não quebra nem soma). **Pendente:** a tarefa sai da lista do que entregar naquele dia (o banco recusa a entrega), mas ainda conta na nota. **Recusada:** conta normalmente. A análise por tarefa ganhou a coluna "não se aplica".
- **Solicitações internas** (Pessoas → Solicitações, por loja): Compra (categoria, item, quantidade e unidade) e Manutenção (categoria e descrição). Situações **Aberta → Em andamento → Concluída**, ou **Recusada** com motivo; Concluída e Recusada são finais. O banco recusa qualquer outra transição, até para o dono. **Histórico** (`solicitacoeshistorico`) gravado por gatilho em cada mudança: de, para, quem, quando e observação; nunca muda nem se apaga. Por enquanto o gestor registra indicando quem pediu; os líderes pedem pelo bot na 1.13 (com a foto da manutenção).
- **Canal confidencial** (Pessoas → Canal confidencial): **só o master lê** (policy com `sou_master()`; gerente não vê nada). O relato guarda só texto, **dia (sem hora)** e situação (Nova, Em análise, Tratada); **sem loja** e sem nenhuma coluna de quem enviou. **Protocolo aleatório** (XXXX-XXXX-XXXX): o banco guarda só a impressão digital; com ele, quem enviou consulta a resposta sem se identificar. **Entrada só pelo servidor** (`registrar_relato`, que o navegador não consegue chamar, nem o master). Texto, dia e protocolo nunca mudam; nada se apaga. O master marca em análise/tratado e responde. O teste de isolamento reprova qualquer coluna nova na tabela, qualquer gatilho ou chave que ligue o relato a outra tabela, qualquer outra função que grave relato e qualquer permissão de escrita pelo navegador. Um relato de exemplo ("[EXEMPLO criado pelo suporte…]") foi gravado na conta Premier Lojas para testar a tela.
- **Menu agrupado**: Operação (Painel, Quadro, Tarefas), Pessoas (Equipe, Feedbacks, Justificativas, Solicitações, Canal confidencial), Gamificação (Ranking, Conquistas, Prêmios, Extrato), Relatórios e Gestão (Lojas, Configurações). No computador, listas suspensas; no celular, um botão "☰" abre o menu inteiro em duas colunas. Conferido em 390 px de largura sem rolagem para os lados.
- **Bloqueadores:** os 82 endereços do app passaram pelas 8 listas (528 mil regras): nenhum barrado.

**Problemas do sistema antigo corrigidos (parte 3):** feedback duplicado era possível (checagem só no programa) e o bônus somava o saldo por fora de qualquer livro; `feedbacksolicitacoes` estava morta (duas funções com o mesmo nome); o canal guardava a hora exata e um protocolo sequencial, e ninguém conseguia tratá-lo; as solicitações não tinham como mudar de situação nem registro de quem mudou; o "Não aplicável" valia sem ninguém aprovar, ficava escondido no campo de recusa e **derrubava a confiabilidade** como se a tarefa não tivesse sido feita.

**Problemas do sistema antigo corrigidos:** o estoque nunca era conferido nem descontado; recusar um resgate duas vezes devolvia os pontos em dobro; a comanda não conferia o saldo no banco (podia deixá-lo negativo) e arredondava a favor do funcionário; o extrato não batia com o saldo (resgates pendentes e ajustes manuais ficavam de fora).

### Etapa 1.8 — Metas de faturamento (por loja)
Só o faturamento. Meta de lucro, histórico de lucro e relatórios financeiros foram para a Etapa 2.3.
- [x] Meta de faturamento mensal. *(22/09/2026)*
- [x] Metas diárias (modelos de meta diária por dia da semana) e **metas especiais** por data.
- [x] Lançamento do valor vendido no dia (apuração diária; substitui o `/lancar` do bot).
- [x] Mostrar/ocultar valores do dia.
- [x] Pontos automáticos para a equipe da loja ao bater a meta diária (pelo livro de movimentos).
- [x] Meta do dia no painel da loja e na TV (o espaço já está reservado na Etapa 1.6), com os fogos ao bater a meta, como no sistema antigo.

**Feito em 22/09/2026.**

- **Tela Metas** (Operação → Metas, por loja), com as abas Lançar venda, Meta do mês, Por dia da semana, Metas especiais e Histórico.
- **Meta do dia:** valor fixo por dia da semana, por loja, com R$ e pontos. Uma **meta especial** para uma data (feriado, data comemorativa) substitui o modelo naquela data. A meta fica **guardada no lançamento**: mudar o modelo ou a especial depois não muda os dias já lançados.
- **Meta do mês:** uma por loja por mês do calendário, com valor e pontos de prêmio (0 = sem prêmio). A tela mostra a soma das metas diárias do mês ao lado da meta do mês, e a projeção (média dos dias lançados × dias do mês).
- **Lançamento:** o total vendido no dia, que substitui o anterior. Um por loja por dia. Hoje ou dias passados, **só do mês atual e do anterior**; mais antigo, o banco recusa. **Correção exige motivo**. Nada se apaga: para zerar, corrige para R$ 0. Todo lançamento e toda correção vão para `metashistorico` (quem, quando, valor antigo, valor novo, motivo), que nunca muda.
- **Pontos pelo livro**, um movimento por pessoa ligado ao prêmio (`metaspremiacoes`). **No máximo um prêmio valendo por dia por loja** e um por mês, garantido por índice único e provado com dois lançamentos ao mesmo tempo. Ganha a meta do dia quem está ligado à loja, ativo e, **no dia da venda** (não no dia em que o valor foi lançado), não está de folga semanal, de domingo de folga nem afastado. Ganha a meta do mês quem está ligado e ativo quando ela bateu.
- **Correção:** subiu ou desceu e continua batida, nada muda. Passou a bater, paga. Deixou de bater, **estorno automático, pelo livro, de exatamente quem recebeu** (o saldo pode ficar negativo). Voltou a bater, paga de novo. Vale também para a meta do mês.
- **Bônus de meta fora do ranking e da nota do mês.**
- **Painel da loja:** o cartão "Meta do dia" mostra % do dia e do mês, os valores em R$, a projeção e o botão 👁️ para ocultar os valores (lembrado em cada aparelho).
- **TV:** só porcentagem por padrão. Em Gestão → Lojas, cada loja tem **"Mostrar valores em R$ da meta na TV"** (desligado). Com a opção desligada, **o banco não envia nenhum valor em reais** para a TV, e o teste confere o conteúdo devolvido. **Rodízio:** a TV alterna painel ↔ tela da meta a cada 30 segundos (só quando a loja tem meta). Conferido no celular (390 px, sem rolar para os lados).
- **Fogos na TV e no painel** ao bater a meta do dia, uma vez por dia por loja em cada tela, separados dos fogos de 100% das tarefas.
- **Bloqueadores:** 90 endereços do app, 8 listas, nenhum barrado.

**Problemas do sistema antigo corrigidos:** quem ganhava era quem tinha o texto do "setor" no cargo, mesmo de folga ou inativo; o prêmio podia sair duas vezes e o saldo era somado por fora do histórico; o estorno tirava pontos de quem **hoje** tem o cargo, não de quem recebeu; excluir um lançamento não devolvia os pontos; "quem lançou" era sempre o funcionário nº 2; não havia histórico de correções; o prêmio do mês dependia de o gestor abrir a tela e confirmar; e a trava de modelos era "um por dia da semana por conta" (só uma loja do cliente teria meta de segunda-feira) — agora é por loja.

### Etapa 1.9 — Agenda (por loja)
- [x] Calendário (mês) e lista. *(22/09/2026)*
- [x] Cadastro de agendamento: responsável, cliente, telefone, CPF, data, hora, tipo, pagamento, observações.
- [x] Marcar pagamento; documentos anexos.

**Feito em 22/09/2026.**

- **Tela Agenda** (Operação → Agenda, por loja): lista (Próximos, Realizados, Cancelados, Todos), **calendário do mês**, novo agendamento e **tipos de evento**. Os tipos são uma lista por conta, editável; **conta nova começa só com "Evento"**. Os 3 tipos antigos ("Carrinho de Sorvete", "Festa de Aniversario", "Reserva de Tortas de Sorvete") foram colocados só na conta de teste atual (Premier Lojas), por fora da migração.
- **Responsável:** vem o responsável pelos agendamentos da loja, e pode ser outro, desde que trabalhe na loja (o banco garante).
- **Situações:** Confirmado → Realizado (marcado à mão; pode voltar para Confirmado com motivo) ou → Cancelado (motivo obrigatório, final). Nada se apaga; remarcar, trocar o responsável, editar e cancelar só em Confirmado. **Pagamento:** Pendente, Sinal pago ou Pago, com valor combinado opcional.
- **Mesmo horário:** a tela avisa quando já há agendamento confirmado na loja a menos de 2 horas e pergunta se quer agendar assim mesmo (não bloqueia).
- **A tarefa acompanha:** criar gera "Atender agendamento" (Única, no dia do evento) para o responsável, com o texto "15:00 — Tipo", **sem dados do cliente**. Remarcou, muda de dia; trocou o responsável, muda de pessoa; cancelou, é encerrada. Se já tinha sido entregue, nada muda nem duplica. Essa tarefa não se mexe por fora da agenda, e ninguém a atribui na mão.
- **Histórico** (`agendamentoshistorico`, nunca muda): criação, edição (sem copiar CPF/telefone), remarcação com data antiga e nova, responsável, pagamento, realizado, reaberto, cancelado, anexos — sempre com quem e quando.
- **Anexos:** bucket privado `agendamentos` (até 10 MB; PDF, JPG ou PNG), pasta `<conta>/<loja>/<agendamento>/`; o Storage só aceita e só mostra arquivos de agendamento da própria conta e loja. Abrir gera **link temporário de 5 minutos**. Remover fica no histórico.
- **CPF** mascarado nas listas (`***.***.123-45`) e completo só no detalhe; CPF e telefone guardados só com números.
- **Painel da loja:** "Próximos agendamentos" com hora, tipo e primeiro nome. **TV:** só hora e tipo ("15h — Aniversário"); o banco não envia nome, CPF, telefone, observações nem valor, e o teste confere. **Rodízio da TV:** painel → meta → agenda, 30 s cada.
- **WhatsApp (1.13):** as marcas `msg*enviada` viraram "enviada em" (data e hora), vazias; novo campo "cliente aceita receber WhatsApp" (consentimento). Nada é enviado.
- **Dados de conta nova:** conferido que nada com a marca Gela Boca é criado automaticamente (tarefas do sistema, prêmio "Abate na comanda" e configurações são genéricos; os valores padrão das configurações são só números editáveis).
- **Bloqueadores:** 109 endereços do app, 8 listas, nenhum barrado.

**Problemas do sistema antigo corrigidos:** remarcar e excluir chamavam funções que não existiam (a tarefa ficava na data antiga ou órfã); cancelar era apagar; a tarefa ia sempre para um responsável fixo e levava nome, telefone e observações do cliente; o painel da loja mostrava nome e telefone; as rotas de agendamento não pediam login (qualquer um na rede listava CPF e telefone); "quem cadastrou" ficava no lugar do responsável.

### Etapa 1.10 — RH
- [x] Onboarding / admissional. *(22/09/2026)*
- [x] Comunicados com destinatários e confirmação de leitura.
- [x] Documentos pessoais com ciência (assinatura com validade jurídica fica para depois).
- [x] PDFs de recibo e comunicado.

**Feito em 22/09/2026.**

- **Menu RH:** Comunicados, Documentos pessoais e Onboarding. Ainda não há portal do funcionário: o gestor faz tudo, e o banco guarda a **origem** (`gestor` ou `funcionario`) para o portal ou o bot no futuro, sem refazer tabelas.
- **Comunicados:** alvo toda a conta, lojas escolhidas ou pessoas escolhidas. Destinatários fixados na publicação (só ativos da conta); acréscimo manual depois, com o aviso "X funcionários ativos entraram depois" e botão para incluir. Título, texto e pontos editáveis só até a primeira ciência. Nunca se apaga; **arquivado** não aceita ciência nem destinatário novo, mas guarda histórico e recibos.
- **Ciência:** o gestor registra com data e hora. Pontos pelo livro (**uma vez**, provado com duas conexões ao mesmo tempo), padrão sugerido pelos pontos da tarefa do sistema "Leitura de comunicado" (ID em `configuracoes`), fora do ranking e da nota. **Desfazer só o master**, com motivo, estorno pelo livro; a conquista fica. A conquista **"comunicados lidos"** passou a valer.
- **Documentos pessoais (só o master):** bucket privado `documentos-rh`, pasta `<conta>/funcionarios/<pessoa>/`, PDF/JPG/PNG até 10 MB com o **tipo real conferido pelos primeiros bytes** (também nos anexos da agenda). Link temporário de 5 minutos. **Cada envio, cada link gerado e cada exclusão ficam registrados** (`documentosacessos`, só o master lê); o Storage só libera o arquivo com esse registro feito há menos de 2 minutos. Excluir "enviado por engano" só sem ciência e até 7 dias (o arquivo sai; o registro fica). Fora disso: **nova versão** (a anterior fica guardada e acessível) ou **arquivar**. Pessoa desativada: documentos guardados, com filtro para ver.
- **Onboarding:** 6 etapas genéricas por conta (a de teste recebeu as mesmas), editáveis (renomear, ordenar, desativar — nunca apagar); checklist por pessoa com observação e documento ligado; concluído quando todas as etapas estão feitas. Os dados pessoais do questionário antigo foram removidos da tabela (LGPD).
- **PDFs** gerados na hora, no navegador (não ficam guardados): comunicado, recibo de ciência e **recibo de resgate a partir do livro de pontos** (botão na tela Prêmios). Cabeçalho com o nome da conta (e da loja no recibo de resgate), rodapé "Gerado em dd/mm/aaaa hh:mm por <usuário>". Nenhum leva CPF.
- **Não trazido agora:** assinatura com validade jurídica, envio por Telegram/WhatsApp, bloqueio do bot até o admissional, questionário de dados pessoais, lembretes automáticos de ciência pendente, imagem no comunicado.
- **Bloqueadores:** 137 endereços do app, 8 listas, nenhum barrado.

**Problemas do sistema antigo corrigidos:** ciência com dois toques podia pagar duas vezes; o mesmo comunicado podia ir duas vezes para a mesma pessoa; excluir comunicado apagava as provas de leitura; o ID da tarefa de leitura era fixo no código; o download de documento pessoal **não pedia login** e aceitava trocar o número no endereço; um segundo arquivo do mesmo mês sobrescrevia o primeiro; o onboarding guardava cônjuge, filhos e CPFs sem necessidade.

### Etapa 1.10B — Reestruturação visual
Só visual e navegação: não muda regras de negócio, tabelas nem permissões (exceto funções de leitura do dashboard). O Modo TV não muda.
- [x] Tema claro por padrão, com botão para o escuro; preferência salva por usuário (vale no próximo login). Cores centralizadas em variáveis de tema: azul principal; verde = sucesso/meta batida; amarelo = pendente; vermelho = erro/recusa/estorno; bom contraste nos dois temas.
- [x] Layout único para todas as telas do master (e o mesmo estilo no painel do admin geral): menu lateral fixo e agrupado (Início, Operação, Pessoas, Metas, Agenda, RH, Configurações), item atual destacado, opção de recolher; topo com nome da conta, seletor de loja, botão de tema e usuário/sair.
- [x] Celular (a partir de 360 px): barra inferior fixa (Início, Quadro, Equipe, Metas, Mais); tabelas viram cartões; formulários em uma coluna; botões com área de toque grande; nada de rolagem para o lado.
- [x] Componentes reutilizáveis: cartão de número, tabela/cartão responsivo, cabeçalho de página, botões, estados vazio/carregando/erro.
- [x] Tela **Início** (aberta após o login): cartões de números, gráficos e listas curtas da loja ativa, com opção "Todas as lojas". Números vindos de funções do banco (bloqueadas por padrão, no teste de isolamento). Nada de CPF, telefone ou documentos pessoais.
- [x] Prints das telas principais em 1280 px e 375 px, nos dois temas (pasta `prints/1.10B/`, fora do Git).
- [x] **Meu perfil** (master e admin geral): nome de exibição e tema. O nome aparece no topo e nos PDFs.
- [x] Todas as telas conferidas a 360 px: nada passa da borda.

### Etapa 1.11 — Rotinas automáticas sem Telegram
Via **pg_cron** (a cada 5 minutos, função interna `rotinas_despachar`), **rodando para todas as contas ativas**, cada uma no seu horário em `configuracoes`, no fuso de São Paulo. Uma conta com erro não trava as outras; rodar duas vezes não duplica.
- [x] **Lista do dia congelada** (`tarefasdodia`), gerada no `HORARIO_GERACAO_TAREFAS` e ajustada a cada 5 minutos durante o dia (acrescenta, cancela, atualiza folga), sem mexer em item entregue, justificado ou passado. Dias passados nunca mudam. Pontos do dia em que foi gerado. Parada: recupera até 7 dias, marcados como "recuperado". A nota do mês, as pendências e as justificativas usam a lista a partir do primeiro dia gerado. "Rodar agora" em Configurações.
- [x] **Fechamento mensal** (`fechamentosmensais` + `historicoranking`): dia 1 no `HORARIO_FECHAMENTO_MENSAL`, provisório até o dia 7 (refeito todo dia), definitivo no dia 8. Por loja e geral. "Refazer fechamento" só pelo master, com motivo, guardando a versão anterior. Sem pontos automáticos. Tela: Ranking → Meses fechados. Não fecha meses anteriores à criação da conta: o primeiro mês fechado é o mês em que ela foi criada.
- [x] **Tarefas de quem está de folga hoje** no Quadro: o gestor passa para quem trabalha hoje na mesma loja (tarefa única de hoje, mesmos pontos, esforço extra). O repasse automático com "o primeiro que clicar" fica para a 1.13.
- [x] **Conferência diária do livro de pontos** (`HORARIO_CONFERENCIA_LIVRO`): nunca corrige, só registra a diferença (master vê; admin vê "diferença" na lista de contas).
- [x] **Limpeza** do registro de execuções com mais de 180 dias (nunca toca em `documentosacessos` nem em `movimentospontos`).
- [x] **Registro de execuções** (`rotinasexecucoes`): master vê o da própria conta (Configurações e Início); admin geral vê só ok/erro/diferença por conta.
- [x] Avisos no Início: agendamentos que já passaram e continuam Confirmados; comunicados sem ciência há mais de 24 h.

### Etapa 1.12 — Visões LOJA e COLABORADOR
> **Proposta em análise (23/09/2026). Nada foi programado.** O Claude Code só começa a parte A depois do "pode fazer" do Wisley.
> Motivo da etapa: reduzir risco trabalhista. O sistema **nunca** vai atrás do funcionário — nenhuma notificação, e-mail ou mensagem para a visão COLABORADOR.

**O modelo**
- **Visão LOJA:** um acesso por loja (dentro do limite contratado), num tablet no balcão. Só painel e atividades. Não aprova entrega, não mostra CPF, documento pessoal, dinheiro, relatório nem canal confidencial.
- **Visão COLABORADOR:** entra pelo CPF, no celular da própria pessoa, quando ela quiser. Sem notificação de espécie alguma.
- **Aceitar no tablet:** a pessoa toca em "Aceitar" e digita só o PIN de 6 dígitos; o sistema descobre quem é e atribui na hora.

**Decisões fechadas (23/09/2026)**
- [x] Senha e PIN iniciais = **6 primeiros dígitos do CPF** (o Supabase não aceita senha com menos de 6). Troca obrigatória no primeiro acesso.
- [x] **PIN único na conta inteira** (cobre também quem trabalha em várias lojas). Erro genérico: "escolha outro número".
- [x] Entrada do colaborador: **link/QR da empresa** (caminho principal) **e** campo "código da empresa" na tela de login (alternativa).
- [x] Senha do acesso da LOJA: **o sistema gera e mostra uma vez** (como o link da TV), com botão "Redefinir senha da loja", que **derruba os tablets pareados**.
- [x] Extras que entram agora: **checklist de abertura e fechamento** e **aviso de tarefa parada no tablet**. "Passar tarefa para colega" fica para depois do piloto; QR da tarefa no local, mais tarde.
- [x] Trava de tentativas **também no login do master** (hoje não existe nenhuma), contada por CPF/e-mail e por origem, com a mesma mensagem sempre ("CPF ou senha inválidos"), sem revelar se o CPF existe.
- [x] Senha: mínimo 6 para o colaborador e 8 para o master; recusar senha igual aos 6 dígitos do CPF, sequência (123456) e repetição (111111). Mesma regra para o PIN.
- [x] Apagar as colunas mortas `funcionarios.senhahash`, `verificadorcpf` e `nivelacesso` (conferido: nenhuma função nem tela usa). A coluna `cpf` fica e passa a ser usada.
- [x] `minha_conta()` responde **nulo** para os acessos de loja e de colaborador: as ~200 regras de acesso que já existem passam a negar tudo para eles, sem serem reescritas. As visões novas leem e gravam **só por funções**, que entram num contexto de servidor (o mesmo desenho do bot).
- [x] Telegram (1.13) fica pronto no sistema, porém **desligado por padrão**; 1.13B2 e 1.13C pausadas. Nada do bot é apagado.

**Divisão do trabalho**
- [x] Texto da política de uso recebido (23/09/2026): `docs/politica-de-uso.md`. Vira comunicado com ciência no primeiro acesso, publicado com **0 pontos**. O arquivo lista o que precisa ser ajustado antes de publicar (ver a frase sobre guardar fotos).
- [ ] **A — Acesso** (grande, risco alto): CPF na Equipe, os dois acessos novos, papéis, senha provisória, "Redefinir acesso", travas de tentativa, isolamento e teste.
- [ ] **B — Tablet** (grande): painel, fila do dia, PIN, aceitar, entregar com foto, mural com ciência, feedback, justificativa, solicitação, modo quiosque, pareamento e corte de tablet.
- [ ] **C — Celular** (médio): minhas tarefas, entrega com foto, saldo, extrato, conquistas, nota, ranking com "Nome I.", pedido de resgate, comunicados, documentos, canal confidencial, perfil.
- [ ] **D — Extras** (pequeno): checklist de abertura/fechamento e aviso de tarefa parada.

**Decisão de negócio ainda em aberto:** hoje a tarefa nasce **com dono** (o gestor atribui). A fila "livre para aceitar" supõe o contrário. Caminho proposto: continua como hoje e **só o que o gestor marcar como "livre" entra na fila de aceitar** (a missão da equipe, da 1.13B1, já funciona assim).

### Etapa 1.13 — Telegram e WhatsApp da plataforma + cobrança por uso
> Dividida em três partes, cada uma testada na loja antes da próxima: **1.13A** base do bot · **1.13B** rotinas com mensagens · **1.13C** WhatsApp (API oficial da Meta) e onboarding pelo bot. Bot: **@STGameAppBot**, um só para todas as contas.

**1.13A — Base do bot (22/09/2026)**
- [x] Webhook (Edge Function `telegram-webhook`, `verify_jwt = false`): confere o cabeçalho `X-Telegram-Bot-Api-Secret-Token` em toda chamada, com comparação de tempo constante; sem ele ou errado, **401 e nada acontece** (nem abre o banco). Responde 200 na hora e trabalha em segundo plano. Cada `update_id` é tratado uma vez só.
- [x] Vínculo: pessoa (link + QR na tela Equipe), grupos da loja (equipe e gestão, com `/vincular@STGameAppBot <código>` na tela Lojas) e o Telegram do master (Meu perfil). Convite de 48 h, uso único, código de 64 caracteres aleatórios (só o hash fica no banco); gerar outro cancela o anterior. 5 códigos errados em 1 hora bloqueiam o chat.
- [x] Aviso de vínculo novo para o master, no sistema (Início, "marcar como lido") e no Telegram dele. Ícone "Telegram" na Equipe e botão "Desligar Telegram" por pessoa e por grupo.
- [x] Quem não tem vínculo recebe só "Peça o convite ao seu gestor." (nada da empresa ou de pessoas). Grupo sem vínculo recebe só "Grupo não vinculado."; ali só `/vincular` com código válido funciona.
- [x] Menu do funcionário: tarefas do dia, entrega com foto, "não se aplica" (vira justificativa pendente), saldo, histórico, conquistas, ranking, meta em %, prêmios, comanda, feedback do dia, ciência de comunicado e documentos pessoais (só na conversa privada, link de 5 minutos, com registro de acesso).
- [x] Foto da entrega: só dentro de 10 minutos depois de "Enviar foto"; encaminhada, repetida (mesmo `file_unique_id`) ou mandada como arquivo é recusada. A foto vai para o Storage em `<contaid>/<lojaid>/`.
- [x] Trava (b): resgate e comanda só depois do feedback de ontem (se ontem foi dia de trabalho). O resto funciona.
- [x] Grupo de gestão: foto da entrega com Aprovar/Recusar (motivo respondendo à pergunta do bot, guardado no banco), `/pendencias`, `/lancar`, `/status_meta`. Só o master e quem é **validador daquela loja** (marca nova na Equipe); os outros recebem "Sem permissão." e nada muda. Fica gravado quem validou e por qual canal. Duas aprovações ao mesmo tempo: vale uma.
- [x] Avisos imediatos pela fila: entrega aprovada/recusada (com motivo) no privado, conquista desbloqueada, meta batida no grupo da equipe e vínculo novo para o master. Validação feita pelo sistema também atualiza a mensagem do grupo.
- [x] Fila central (`mensagensfila` + Edge Function `telegram-fila`, chamada pelo banco na hora e a cada 15 s pelo pg_cron, com o cabeçalho `x-fila-segredo`): até 18 por minuto por grupo, espera o `retry_after` do Telegram, tenta de novo com intervalo crescente (5 vezes). Linhas enviadas somem em 7 dias.
- [x] Medição de uso (`usomensagens`): conta, loja, canal, tipo e dia, sem texto. Respostas diretas e avisos da fila contam. A cobrança fica para a Etapa 2.0.
- [x] O bot chama as **mesmas funções** das telas (entrega, aprovar, recusar, resgate, comanda, feedback, justificativa, ciência com `origem = 'funcionario'`). Todo ponto passa pelo livro.
- [x] Teste de isolamento (seção 39, 87 conferências) + concorrência (duas aprovações juntas) + teste Deno do segredo (401), todos no `bash supabase/tests/rodar.sh`.
- [ ] **Teste na loja com dois celulares (funcionário e gestor).**

**1.13B1 — Rotinas com mensagem: jornada, comunicados, folga e missões (22/09/2026)**
- [x] **Jornada por pessoa**: hora de entrada e de saída na tela Equipe, iguais todos os dias, com "aplicar a várias pessoas de uma vez". Saída em branco = entrada + 8h20. Saída menor que a entrada = turno da noite. O padrão 08:00 automático foi apagado: quem não tem horário não recebe as mensagens de jornada (só os avisos).
- [x] Início da jornada (tarefas do dia com o botão da foto), lembretes de 3 h e 6 h (só o que está em aberto; somem se já foi feito) e fim da jornada (resumo do dia + botão de avaliar o dia).
- [x] Comunicado novo com o botão "Estou ciente" e lembrete uma vez, 24 h depois, só dentro do turno.
- [x] Tarefas de quem está de folga e **missões da equipe** no grupo da equipe, com "o primeiro que clicar" (atômico, mesma função do "Passar para…"; a missão é uma tarefa sem dono, criada na tela Tarefas com hora de disparo). Limite de 3 tarefas extras por pessoa por dia.
- [x] **Configurações → Mensagens automáticas**: liga/desliga de cada rotina, loja por loja. Quem trabalha em duas lojas recebe se estiver ligado em pelo menos uma.
- [x] Proteções contra excesso: silêncio 22:00–07:00 ajustável (**não vale dentro do turno**, por causa do turno da noite), no máximo 8 mensagens automáticas por pessoa por dia, avisos de aprovação juntados numa mensagem só, lembrete cancelado se a tarefa já foi feita, uma mensagem só para quem está em duas lojas.
- [x] Folga e afastamento: nada é enviado; os avisos ficam guardados e viram **um resumo só** ("Enquanto você esteve fora: 3 comunicados, 5 entregas aprovadas") no próximo dia de trabalho, olhando no máximo 7 dias para trás.
- [x] Rotina nunca repete (etiqueta única no banco; se falhar, não é reenviada). Aviso do que aconteceu com a pessoa continua sendo reenviado.
- [x] **Bot bloqueado** (403): para de tentar, marca o vínculo, avisa o master no sistema e no Telegram, e volta sozinho quando a pessoa usar o bot de novo. A Equipe mostra "Bot bloqueado" ao lado do nome.
- [x] Testes: turno da noite atravessando a meia-noite, pessoa sem horário, folga, silêncio, limite diário, lembrete cancelado, duas lojas, resumo da volta de 20 dias, bot bloqueado, liga/desliga por loja, dois cliques simultâneos em "Eu aceito" (conexões de verdade) e isolamento entre contas.
- [ ] **Teste na loja com dois celulares.**

**1.13B2 — Agenda, pódio, canal confidencial e solicitações (a fazer)**
- [ ] Agenda de hoje, de amanhã e da semana no grupo de gestão (só primeiro nome, hora, tipo e pagamento; nunca telefone ou CPF).
- [ ] Aviso ao responsável quando um agendamento é criado, remarcado, cancelado ou troca de responsável.
- [ ] Fechamento do mês: pódio no grupo da equipe (posição e pontos, sem a nota) no dia 8, com texto de prêmio por posição editável em Configurações, e parabéns no privado.
- [ ] Canal confidencial pelo bot (o bot apaga a mensagem da conversa depois de gravar, avisando antes; o master recebe só "N relatos novos" às 08:00 do dia seguinte).
- [ ] Solicitações pelo bot, só com a marca "pode fazer solicitações", com foto no Storage.
- [ ] **Grupos por loja** (cadastro de grupos com membros, tabela `grupos`). Vieram da Etapa 1.7.

**1.13C — WhatsApp e onboarding pelo bot (a fazer)**
- [ ] WhatsApp pela API oficial da Meta (nada de Z-API).
- [ ] Onboarding pelo bot.

**Estratégia (escrita antes da 1.13A; o que mudou está acima):**
- **Um único bot da plataforma** (token do Wisley), atendendo todas as contas, em vez de um bot por cliente. O cliente não precisa criar nada no Telegram.
- **Vínculo por código:** cada funcionário recebe um link `t.me/<bot>?start=<código>`. Ao abrir, o `chat_id` fica ligado àquele funcionário, e com isso à conta e às lojas dele.
- ⚠️ **A desenhar aqui:** `funcionarios.chatidtelegram` é único **só dentro da conta**, porque a mesma pessoa pode trabalhar para duas empresas clientes. Então o `chat_id` sozinho não identifica a conta: quando a pessoa aparece em mais de uma, o bot precisa perguntar de qual empresa ela está falando (ou manter uma conta ativa por conversa). `grupos.chatidtelegram` é único no sistema inteiro, então grupo não tem essa ambiguidade. Os grupos de cada loja são ligados com um comando `/vincular <código>` no grupo.
- **Bot reescrito como Edge Function (webhook) no Supabase**, e não mais o servidor Python. Isso muda a recomendação anterior (manter o Python): com várias contas, um serviço central na nuvem é mais simples e confiável. O `legado/telegram_bot.py` serve de especificação das funções.
- **Fila de envio central** (tabela + processamento), respeitando os limites do Telegram (≈30 msg/s no total, ≈20/min por grupo), para uma conta não atrasar as outras.
- **Medição de uso:** todo envio (Telegram/WhatsApp) é registrado em `usomensagens` (conta, loja, canal, tipo, data). O total do mês vai para o Stripe como **cobrança por uso** ou como franquia incluída no plano, com excedente.
- **WhatsApp:** API oficial da Meta, na 1.13C (decisão de 22/09/2026; a Z-API foi descartada).
- ⚠️ **Canal confidencial no bot:** a entrada chama só `registrar_relato(conta, texto)` pelo servidor, sem nenhum dado de quem envia. O bot **não pode logar mensagem + `chat_id`** nesse fluxo (nem em nível DEBUG da biblioteca do Telegram), não guarda o texto no estado da conversa depois de enviar e **não avisa o gestor na hora** (aviso agrupado, uma vez por dia, sem horário), para ninguém cruzar horários. O protocolo vai só para quem enviou; a consulta usa `consultar_relato`.
- **Repasse automático das tarefas de folga ("drop"):** no `HORARIO_DELEGACAO_FOLGA`, o bot publica no grupo da loja as tarefas de quem está de folga (a lista do dia já diz quais são) e o primeiro que aceitar recebe, usando a mesma função do Quadro (`passar_tarefa_de_folga`: uma vez por dia, esforço extra). Veio da Etapa 1.11.
- **RH no bot:** ciência de comunicado e de documento pessoal pelo próprio funcionário (`origem = 'funcionario'`), entrega do holerite com link temporário (sempre com registro de acesso), lembrete de ciência pendente.
- Entradas que já existem no banco e esperam o bot: feedback (`origem = 'bot'`), justificativa (`origem = 'bot'`, fica pendente), solicitações dos líderes (com a foto da manutenção, em `<contaid>/<lojaid>/...`) e a trava "feedback de ontem antes da comanda".
- Funções a portar: comandos (/start, /tarefas, /ranking, /meuhistorico, /meusaldo, /loja, /documentos, /conquistas, /ajuda, /pendencias, /status_meta, /lancar), recebimento da foto da entrega com validação EXIF (a foto de nota fiscal fica na Etapa 2.2), canal confidencial, solicitações, abate de comanda, notificações de jornada, lembretes, recusa com motivo, meta batida, confirmação e pós-venda por WhatsApp.
- Desligar os serviços antigos (`systemctl`) e o SQL Server.

### Etapa 1.14 — Segurança final (endurecimento)
- [ ] **Já, sem esperar esta fase:** deixar o repositório GitHub privado (se ainda não foi) e revogar o token `sbp_` colado no chat.
- [ ] **Trocar as chaves antigas do Supabase (`eyJ...`) pelas novas (`sb_secret_...` / `sb_publishable_...`), também no Lovable.** O Lovable recusa Secrets com nomes `VITE_` e `SUPABASE_`: a chave secreta fica em `STGAME_SERVICE_ROLE_KEY` (Secrets do Lovable) e a URL + chave pública ficam em `src/integrations/supabase/config-publica.ts` (trocar lá a publishable, se mudar). Depois da troca, testar um convite de ponta a ponta.
- [x] Verificação automática no GitHub (`.github/workflows/verificacao.yml`): barra qualquer `.env` enviado ao repositório, exceto o `.env.example` (22/09/2026); barra `package-lock.json`/`yarn.lock`/`pnpm-lock.yaml` e roda o `bun run build` (22/09/2026).
- [ ] Revogar o token antigo do bot (@BotFather), os tokens da Z-API e as senhas antigas do `legado/config.py`; remover o `legado/config.py` do histórico.
- [ ] Papéis extras dentro da conta (gerente de loja com acesso só às suas lojas).
- [ ] Revisão completa das policies, do Storage (buckets privados + URLs assinadas) e das funções `security definer`.
- [ ] Registro de auditoria (quem alterou o quê) nas tabelas sensíveis.
- [ ] Backups e plano de recuperação.
- [ ] **Limpeza das contas de teste antes de vender:** apagar a conta de teste (hoje a conta 1, "Premier Lojas", com os 6 passos de onboarding e os 3 tipos de evento criados para ela) e os logins de teste do Supabase Auth. Os prints da Etapa 1.10B ("Sorveteria Exemplo") usaram respostas simuladas no navegador: nada foi gravado no Supabase.

---

## FASE 2 — Expansão (adiada)
> Não construir nada desta fase sem pedido explícito do Wisley. As tabelas já existem no banco (estrutura da Etapa 1.1), mas ficam sem tela.

### Etapa 2.0 — Comercialização: publicação online + Stripe
> Saiu da Fase 1 em 23/09/2026: primeiro as Visões (1.12), depois vender.
- [ ] **Configurar SMTP próprio (ex.: Resend) antes de vender.** O e-mail embutido do Supabase só serve para teste: tem limite baixo de envios e não usa o nosso domínio. Sem isso, convite e recuperação de senha não são confiáveis para clientes de verdade.
- [ ] Publicar o app (hospedagem + domínio próprio), com ambientes de teste e produção separados.
- [x] Nome e identidade do produto: **STGame** (22/09/2026). Marca aplicada no app; material em `docs/marca/`.
- [ ] Termos de uso e política de privacidade (LGPD: o app guarda CPF e telefone de funcionários dos clientes).
- [ ] **Stripe:** assinatura por quantidade de lojas (preço por loja). O webhook do Stripe atualiza `contas.limitelojas` e `contas.status` sozinho.
- [ ] Período de teste; portal do cliente Stripe (cartão, faturas, cancelamento).
- [ ] Inadimplência → conta `suspensa` (só leitura) → `cancelada` depois de X dias.
- [ ] O painel do admin mostra a situação da assinatura de cada cliente.

### Etapa 2.1 — Escala, mapa e pausas (por loja)
- [ ] Mapa da loja: cada loja envia a própria planta; marcadores de posição.
- [ ] Posições e setores.
- [ ] Escala diária: montar, copiar, freelancers.
- [ ] Picos e gráfico de fluxo por setor.
- [ ] Escala de hoje e pausas com relógio.

### Etapa 2.2 — Estoque
- [ ] Catálogo e categorias (da conta); estoque e contagens (por loja).
- [ ] Fornecedores e vínculo DE/PARA.
- [ ] **Avaliar mover o EAN para o catálogo.** Hoje o código de barras fica em `produtosfornecedor`, porque era assim no sistema antigo e `produtosestoque` não tem coluna de EAN. Conceitualmente o EAN é do produto, não do fornecedor. Avaliar a mudança aqui, junto com as telas de estoque.
- [ ] Importação de XML de NF-e.
- [ ] Contagem física (computador e **celular**, com leitura de código de barras).
- [ ] Auditoria de EAN pelo celular.
- [ ] Desmembrar caixa; sugestão de compra; solicitações dos líderes; consulta de NFs.
- [ ] **Envio de nota fiscal pelo bot**: foto com validação EXIF e bônus `PONTOS_BONUS_NOTA_FISCAL` pelo livro de pontos. Veio da Etapa 1.13.
- [ ] **Tarefa "guardar mercadoria"** gerada para cada nota fiscal aprovada (tarefa do sistema `guardar_mercadoria`).

### Etapa 2.3 — Financeiro (por loja)
- [ ] Meta de lucro (veio da antiga Etapa 1.8).
- [ ] Histórico de lucro mensal (`lucromensalhistorico`), com gráfico em barras.
- [ ] Relatórios financeiros.

---

## Decisões em aberto (perguntar ao Wisley quando a fase chegar)
| # | Pergunta | Sugestão padrão |
|---|---|---|
| 1 | Saldo de pontos e loja de recompensas: um saldo por funcionário na conta toda, ou separado por loja? | Um saldo por funcionário na conta toda |
| 2 | O master vai ter outros usuários (gerente de loja, líder) entrando no painel? | Sim, na Etapa 1.14; por enquanto só o master |
| 3 | Uma mesma pessoa (e-mail) pode ser master de duas contas? | Não: um login, uma conta |
| 4 | O admin geral precisa ver os dados dos clientes para suporte? | Não; se precisar, "ver como cliente" com registro |
| 5 | Preço: por loja, por plano fechado, ou por loja + uso de mensagens? | Por loja + franquia de mensagens |

## Como trabalhar cada etapa
Ferramenta: **Claude Code no VS Code**, direto no repositório. Regras permanentes em `CLAUDE.md`. Este plano fica em `docs/PLANO_MIGRACAO.md`, com cópia no projeto Claude "Game GB".
1. Começar a sessão com: "Leia o CLAUDE.md e o docs/PLANO_MIGRACAO.md e continue a próxima etapa pendente da Fase 1."
2. O Claude Code implementa um item por vez, usando `legado/` como referência de regra de negócio.
3. Toda migração: testar num Postgres descartável → rodar o **teste de isolamento** → aplicar no Supabase → regenerar `types.ts`.
4. O Wisley testa em `bun run dev` (http://localhost:8080) e aprova.
5. O Claude Code marca os checkboxes, atualiza o Status e faz commit.

## Registro de decisões
| Data | Decisão |
|---|---|
| 18/09/2026 | Reconstruir o sistema em React + Supabase, aposentando Flask e Tkinter. |
| 18/09/2026 | Nomes do banco = originais em minúsculas; chaves inteiras automáticas. |
| 18/09/2026 | Banco limpo: nenhum dado antigo importado. |
| 18/09/2026 | Desenvolvimento com Claude Code no VS Code; Python antigo em `legado/`. |
| 19/09/2026 | Chaves naturais nas 5 tabelas sem PK; `funcionarios.ativo` para inativar. |
| 21/09/2026 | **O sistema vira produto multi-empresa (SaaS):** admin geral (Wisley) → contas master → lojas. Dados de cada conta totalmente isolados. |
| 21/09/2026 | Admin geral fixo no banco pelo e-mail `wisley_anderson@hotmail.com`. |
| 21/09/2026 | Cada conta tem limite de lojas definido pelo admin; depois, controlado pelo Stripe. |
| 21/09/2026 | Funcionário pode trabalhar em várias lojas; tarefa pode valer para várias lojas. |
| 21/09/2026 | Isolamento entre contas (RLS) é feito já na Fase 2. A "segurança por último" vale só para o endurecimento (Fase 16). |
| 21/09/2026 | Telegram/WhatsApp: um bot central da plataforma, com medição de uso por conta para cobrança. Bot reescrito como Edge Function (substitui a ideia de manter o Python). |
| 21/09/2026 | Classificação conta/loja aprovada. Duas correções à sugestão do plano: `historicoranking` é de **loja** (senão o ranking por loja do passado se perde) e `freelancers` é de **conta** (a mesma pessoa cobre lojas diferentes). |
| 21/09/2026 | `posicaopadraoid` saiu de `funcionarios` e foi para `funcionarioslojas`: o lugar padrão no mapa é de cada loja. |
| 21/09/2026 | `resgates` ganhou `lojaid` opcional, só para relatório. Comunicados (`documentos`) ficam na conta por enquanto. |
| 21/09/2026 | Saldo de pontos: **um só por funcionário na conta toda** (decisão em aberto nº 1 resolvida). |
| 21/09/2026 | `funcionarioslojas` e `tarefaslojas` têm `ativo`, e quem aponta para elas usa `ON DELETE RESTRICT`: tirar alguém de uma loja é desativar o vínculo, nunca apagar, para preservar o histórico. As telas só oferecem vínculos ativos em atribuições novas. |
| 21/09/2026 | `funcionarios.chatidtelegram` é único **só dentro da conta** — a mesma pessoa pode trabalhar para duas empresas clientes. `grupos.chatidtelegram` é único no sistema inteiro. O vínculo chat → conta fica para a Fase 15. |
| 21/09/2026 | O isolamento entre contas é feito por **chave estrangeira composta com o `contaid`**, não por trigger: as duas pontas leem o mesmo `contaid` da mesma linha, então apontar para outra conta é estruturalmente impossível. O mesmo truque garante que só se atribui tarefa a quem trabalha numa loja onde a tarefa vale. |
| 21/09/2026 | Policies usam `(select minha_conta())` (avaliado uma vez por consulta, não por linha). `minha_conta()`, `minha_conta_editavel()` e `eh_admin_geral()` são `security definer` com `search_path` fixo. |
| 21/09/2026 | EAN: fica em `produtosfornecedor` — `produtosestoque` não tem coluna de EAN. A unicidade é `(contaid, ean)` num índice parcial que ignora nulos e o marcador `'SEM EAN'` usado pelo sistema antigo. Avaliar movê-lo para o catálogo na Fase 12. |
| 21/09/2026 | As 18 linhas de `configuracoes` da Fase 1 não pertenciam a conta nenhuma: viraram a função `cria_configuracoes_padrao(contaid)`, chamada ao criar cada conta. |
| 21/09/2026 | Cadastro público desligado na tela e no Supabase Auth. Só entra quem foi convidado. |
| 21/09/2026 | O e-mail embutido do Supabase serve só para teste. SMTP próprio virou item da Fase 14, antes de vender. |
| 21/09/2026 | Frequências: ficam as quatro individuais (Única, Diária, Semanal, Mensal). **GrupoCompetitiva não será reconstruída** — nada no sistema antigo a criava há tempo; era sobra de uma versão anterior do "quem pegar primeiro", comportamento que hoje vem das frequências de grupo mais o clique de aceitar. |
| 21/09/2026 | As frequências **de grupo** (GrupoDiaria/GrupoSemanal/GrupoMensal) e a **delegação de folga** dependem de publicar num grupo do Telegram: ficam para as Fases 13/15. |
| 21/09/2026 | Tarefa **Única acumula**: se não for entregue no dia marcado, continua aparecendo até ser entregue. É o comportamento real do código antigo — o comentário dele dizia o contrário e estava desatualizado. |
| 21/09/2026 | Frequência **Mensal** com dia que não existe no mês (31 em abril, 30 em fevereiro) cai no **último dia do mês**. Regra na função `tarefa_cai_no_dia()`. |
| 21/09/2026 | As 6 tarefas do sistema são criadas automaticamente em cada cliente novo (`cria_tarefas_do_sistema`), marcadas pela coluna `tarefas.sistema`, ligadas a toda loja nova por gatilho, e **não podem ser apagadas**. As 4 de bônus (feedback, leitura, meta, nota fiscal) **não podem ser atribuídas a ninguém**: só recebem entregas automáticas. As 2 de modelo só viram tarefa pelos fluxos de agendamento e de nota fiscal. Nenhuma das 6 aparece na lista de atribuição manual. |
| 21/09/2026 | **Nota fiscal fica fora do cálculo de desempenho**, junto com leitura, feedback e meta. O sistema antigo excluía só os outros três — descuido dele. |
| 21/09/2026 | Aprovar credita em `saldopontos` **e** em `pontostotal`. No sistema antigo `pontostotal` era morta (nada escrevia nela). Agora `saldopontos` é o que a pessoa tem para gastar e `pontostotal` é o que ela já ganhou na vida, que só desce por estorno. |
| 21/09/2026 | `dataenvio` guarda o envio de verdade e `dataaprovacao` a aprovação. O sistema antigo sobrescrevia o envio na aprovação — o que apagava a hora real, necessária para conferir a foto pelo EXIF na Fase 15. O ranking usa a data da aprovação. |
| 21/09/2026 | Pontos da entrega são os da tarefa **na hora da aprovação**, como no sistema antigo: permite corrigir um valor errado antes de aprovar. |
| 21/09/2026 | Ranking do mês é a **soma simples** dos pontos aprovados. A nota híbrida do sistema antigo foi para a Fase 7. Os bônus contam no ranking (contavam no pódio antigo). |
| 21/09/2026 | **Estorno** de aprovação, com motivo obrigatório: desconta de `saldopontos` e `pontostotal`, registra quem, quando e por quê, e pode deixar o saldo negativo. O sistema antigo não tinha como desfazer uma aprovação. |
| 21/09/2026 | No máximo **uma entrega pendente ou aprovada por atribuição por dia**. Recusada ou estornada libera outra. O sistema antigo não impedia duplicatas, e a aprovação dele não conferia o status — aprovar duas vezes creditava duas vezes. |
| 21/09/2026 | Gestor e responsável pelos agendamentos viraram **campos de cada loja**, no lugar de `ID_GESTOR_PADRAO` e `RESPONSAVEL_AGENDAMENTOS_ID`. |
| 21/09/2026 | Conquistas ficam para a Fase 7, com o gancho `apos_aprovar_entrega()` já no lugar. |
| 21/09/2026 | O painel antigo era "o painel da TV", **sem login nenhum**: a função de exigir login existia no código mas nenhuma rota a usava. Qualquer um no Wi-Fi da loja lia tarefas, ranking, faturamento e a agenda de clientes. |
| 21/09/2026 | Barra do dia: só tarefas de hoje, sem bônus, em duas cores (aprovado / esperando validação). A coluna "Em validação" mostra todas as pendentes, mesmo antigas; só a barra se limita a hoje. |
| 21/09/2026 | Fogos ao completar 100% das tarefas do dia, uma vez por dia por loja em cada tela, só se houver tarefa. No sistema antigo os fogos eram da meta de faturamento — ela volta na Fase 8. |
| 21/09/2026 | **Modo TV por link de loja**, revogável, sem login e só leitura. O código aparece uma vez; o banco guarda só a impressão digital. Tudo passa por `painel_da_tv`, a única função que um visitante sem login pode chamar. A TV só recebe "Nome I.", título da tarefa, pontos e horários. |
| 21/09/2026 | Rodízio de telas na TV só quando existirem as outras telas (meta, agenda, mapa). |
| 21/09/2026 | **Funções SQL negadas por padrão**: toda função nova precisa de `GRANT` explícito. Função `security definer` que recebe `contaid`/`lojaid` nunca é liberada. |
| 21/09/2026 | **Livro de movimentos de pontos** (`movimentospontos`), mudando a regra antiga "não existe tabela de transações". Todo ponto passa por ele, na mesma operação que altera o saldo; o saldo é sempre a soma do livro. Regra permanente no `CLAUDE.md`. |
| 21/09/2026 | Resgate registrado pelo gestor, já "Entregue" por padrão, com opção "entregar depois". O pedido pelo próprio funcionário volta com o bot (Fase 15). Situações: Pendente, Entregue, Cancelado, Estornado. |
| 21/09/2026 | Estoque em branco = ilimitado; 0 = esgotado. |
| 21/09/2026 | Abate na comanda: prêmio do sistema escondido, pontos = valor ÷ taxa **arredondado para cima**; o resgate guarda R$, pontos e a taxa usada, então mudar a taxa só vale para comandas novas. |
| 21/09/2026 | A trava "precisa ter mandado o feedback de ontem" antes da comanda fica para a Fase 15, junto com o bot. |
| 21/09/2026 | **Plano dividido em FASE 1 (Lançamento) e FASE 2 (Expansão, adiada).** As antigas fases viraram etapas (1.1 a 1.14 e 2.1 a 2.3). Escala/mapa/pausas, estoque e financeiro (lucro) foram para a Fase 2 e não se constroem sem pedido explícito. Este registro mantém a numeração antiga; a tabela no topo traduz. |
| 21/09/2026 | Etapa 1.8 fica só com o faturamento; meta de lucro e histórico foram para a 2.3. |
| 21/09/2026 | A foto de nota fiscal pelo bot e a tarefa "guardar mercadoria" foram da Etapa 1.13 para a 2.2 (Estoque). |
| 21/09/2026 | Rodízio de telas no Modo TV: painel, meta (1.8) e agenda (1.9). O mapa entra só na 2.1. (Substitui a decisão anterior que incluía o mapa.) |
| 22/09/2026 | Nota do mês **pula** folga semanal, domingo de folga e afastamento; confiabilidade pelo **dia do envio**; no mês corrente conta **até ontem**. |
| 22/09/2026 | Conquistas: estorno **não retira** a conquista; bônus de conquista **não conta** no ranking; "N tarefas em X dias" com X escolhido na conquista; "vale para o histórico" ou "só a partir de hoje" escolhido na criação, sem mudar depois (a regra também não muda). Sequência de dias não quebra em folga, domingo de folga nem afastamento (mesma regra da nota do mês). |
| 22/09/2026 | Configurações só mudam pela função `alterar_configuracao` (só o master), com validação no banco e histórico (`configuracoeshistorico`). Taxa > 0 e ≤ R$ 10. |
| 22/09/2026 | Feedback: só hoje ou ontem; a nota não se altera (erro → anular com motivo, bônus estornado pelo livro, conquista fica); bônus de feedback fora do ranking; `feedbacksolicitacoes` sem tela. |
| 22/09/2026 | **Canal confidencial:** só o dia (sem hora), protocolo aleatório, sem loja, **só o master lê** — nenhum papel futuro (gerente, líder) terá acesso. Entrada só pelo servidor, sem identificar quem envia; nenhum log guarda o texto junto com quem mandou. Regra permanente no `CLAUDE.md`. |
| 22/09/2026 | Justificativa: dois botões ("Registrar e aceitar" / "Registrar para decidir depois"). Aceita sai das pendências e dos pontos possíveis e é **dia neutro** na sequência de dias (como a folga). |
| 22/09/2026 | Foto da manutenção fica para a 1.13 (vem pelo bot). Menu agrupado em Operação, Pessoas, Gamificação, Relatórios e Gestão. |
| 22/09/2026 | **Metas (1.8):** meta do dia fixa por dia da semana, com **meta especial** por data que substitui o modelo. Ganha quem está ligado à loja, ativo e no **dia da venda** sem folga nem afastamento; meta do mês: ligado e ativo quando bateu. Correção: deixou de bater → estorno automático de quem recebeu; voltou a bater → paga de novo. Lançar ou corrigir **só no mês atual e no anterior**. Bônus de meta fora do ranking e da nota. TV só em %, com a opção por loja "mostrar valores". Rodízio painel ↔ meta, 30 s. Tela "Metas" em Operação. |
| 22/09/2026 | **Agenda (1.9):** mesmo horário só avisa (2 h), sem bloquear; tipos de evento por conta, editáveis — conta nova começa com "Evento", os 3 antigos só na conta de teste; pagamento Pendente / Sinal pago / Pago com valor opcional; Realizado à mão, podendo voltar para Confirmado com motivo; Cancelado final; remarcar e cancelar só em Confirmado; painel logado com o primeiro nome, TV só hora e tipo; "Agenda" em Operação. |
| 22/09/2026 | **RH (1.10):** pontos de ciência fora do ranking e da nota; colunas de dados pessoais do `onboardingstatus` removidas; 6 etapas genéricas de onboarding (também na conta de teste); tipos de documento pessoal fixos e genéricos (lista editável por conta fica para a Fase 2); documento pessoal só se exclui "por engano" sem ciência e até 7 dias — senão nova versão ou arquivar (provas trabalhistas); 10 MB, só PDF/JPG/PNG com tipo real conferido; destinatários fixados na publicação, com aviso e botão para incluir quem entrou depois; arquivado não aceita ciência nem destinatário novo; título, texto e pontos travam na primeira ciência; desativar etapa nunca apaga itens; registro de cada acesso a documento pessoal (só o master lê); rodapé "Gerado em … por …" nos PDFs; desfazer ciência só o master. |
| 22/09/2026 | Funções da loja de prêmios com **nomes neutros** (`*_troca`), por causa de bloqueadores de anúncio. Endereços novos passam pelas listas de bloqueio antes de entrar. |
| 21/09/2026 | Grupos foram da Etapa 1.7 para a 1.13, junto com o Telegram. A Etapa 1.7 tem três partes: 1) prêmios, resgates, comanda e extrato; 2) conquistas, nota do ranking mensal, relatórios e configurações; 3) feedbacks, canal confidencial, solicitações e justificativas. |
| 22/09/2026 | **Etapa 1.10B:** azul cobalto (#1D4ED8 no claro, #60A5FA no escuro); tema claro padrão, escuro opcional; TV continua escura. Gráficos com Recharts. |
| 22/09/2026 | Menu: Início · Operação (Painel da loja, Quadro, Tarefas, Solicitações, Relatórios) · Pessoas (Equipe, Feedbacks, Justificativas) · Gamificação (Ranking, Conquistas, Prêmios, Extrato) · Metas · Agenda · RH (Comunicados, Documentos pessoais, Onboarding, Canal confidencial) · Configurações (Lojas e links da TV, Configurações, Meu perfil). No celular: Início, Quadro, Equipe, Metas, Mais. |
| 22/09/2026 | O master entra pela tela **Início** (antes: Gestão). Números de `painel_inicio` (security invoker, no teste de isolamento); atualiza a cada 1 minuto e ao voltar para a aba. |
| 22/09/2026 | Nome de exibição e tema ficam no `user_metadata` do Supabase Auth, **só para exibir**. Nenhuma policy ou função usa `user_metadata` (o teste de isolamento reprova). |
| 22/09/2026 | Pontos por semana: "entraram" = aprovações + bônus, já sem os estornos; "saíram" = resgates, já sem cancelamentos e estornos de resgate. Conta nova vê o guia de primeiros passos no lugar dos gráficos. |
| 22/09/2026 | **Etapa 1.11:** a delegação de folga fica em duas partes: agora, o repasse manual no Quadro; na 1.13, o repasse automático pelo bot com "o primeiro que clicar" (corrige o conflito com a decisão de 21/09). |
| 22/09/2026 | Lista do dia congelada: mudanças de hoje ajustam só a lista de hoje; dias passados nunca mudam; pontos do dia da geração; recupera até 7 dias ("recuperado"). A nota ao vivo e o fechamento usam a lista a partir do primeiro dia gerado; dias sem lista usam a regra do cadastro. |
| 22/09/2026 | Tarefa recebida de quem está de folga é esforço extra: conta nos pontos ganhos (esforço), não nos possíveis nem na confiabilidade. Uma tarefa só é passada uma vez por dia. |
| 22/09/2026 | Fechamento mensal: provisório nos dias 1 a 7, definitivo no dia 8; "Refazer" só pelo master, com motivo, guardando versões. Por loja, cada ponto conta na loja em que a tarefa foi feita; o geral soma todas. Sem pontos automáticos. |
| 22/09/2026 | Conferência do livro nunca corrige sozinha. Limpeza só do registro de rotinas (180 dias). O papel do pg_cron ignora a RLS: toda função de rotina filtra a conta em todas as consultas e não é liberada para o navegador. |
| 22/09/2026 | Produto renomeado para STGame; identidade visual aplicada (tokens em `src/styles/stgame-theme.css`). |
| 23/09/2026 | **Comercialização + Stripe saiu da Fase 1 e virou a Etapa 2.0.** A Etapa 1.12 passa a ser as **Visões LOJA e COLABORADOR**; Telegram continua 1.13 (pausado e desligado por padrão) e Segurança continua 1.14. |
| 23/09/2026 | **Etapa 1.12:** visão LOJA (tablet, um acesso por loja) e visão COLABORADOR (celular, login por CPF), **sem nenhuma notificação**, para reduzir risco trabalhista. Aceite de tarefa no tablet por PIN de 6 dígitos, único na conta, guardado com HMAC de chave só do servidor (busca direta, sem comparar um a um). Senha e PIN iniciais = 6 primeiros dígitos do CPF. `minha_conta()` responde nulo para os acessos novos, que só leem e gravam por funções em contexto de servidor. |
| 22/09/2026 | Publicação no Lovable: o build volta a usar `@lovable.dev/vite-tanstack-config` + `nitro`, que empacota o servidor inteiro para o Cloudflare (sem isso, "internal server error": módulo `h3-v2` não encontrado). Só o bun (`bun.lock`); `package-lock.json` (criado por um `npm install` em 19/09) apagado e barrado no `.gitignore` e na verificação do GitHub. Versões fixas (sem `^`) dos pacotes `@tanstack/*`, `vite`, `nitro`, `react` e do Supabase. Removido o `index.html` da raiz, que fazia o nitro tratar o app como site estático. |
| 22/09/2026 | O Lovable não recebe o `.env` nem aceita Secrets `VITE_`/`SUPABASE_`. URL e chave **pública** do Supabase ficam no código (`src/integrations/supabase/config-publica.ts`), usadas pelo navegador e pelo servidor. A chave secreta fica só no Secret `STGAME_SERVICE_ROLE_KEY` (o `SUPABASE_SERVICE_ROLE_KEY` do `.env` vale só em desenvolvimento, porque o Lovable pode preencher esse nome com a chave de outro projeto). |
| 22/09/2026 | **Etapa 1.13A:** um bot só (@STGameAppBot). O webhook confere o `secret_token` (tempo constante) e chama só funções `bot_*`, liberadas apenas para a chave de servidor; elas entram num "contexto do bot" que um usuário logado não consegue ativar, e usam as mesmas funções de negócio das telas. Aprovação pelo Telegram só pelo master e por quem é validador da loja. Trava (b): resgate e comanda depois do feedback de ontem. Fotos: janela de 10 min, sem encaminhada, repetida ou arquivo. Convite de 48 h, uso único. Respostas à ação da própria pessoa saem direto do webhook; a fila é só para avisos e rotinas. Divisão: 1.13A base, 1.13B rotinas, 1.13C WhatsApp (API oficial da Meta) e onboarding. |
| 22/09/2026 | No Telegram, o funcionário pode estar em mais de uma empresa: o bot pergunta com qual quer falar (`/empresa` troca). Master pelo Telegram age como o próprio login. Documentos pessoais nunca em grupo. |

| 22/09/2026 | **Etapa 1.13B1:** jornada por pessoa (entrada e saída iguais todos os dias; a escala por dia fica para a Fase 2); o padrão 08:00 foi apagado e quem não tem horário não recebe jornada. Silêncio 22:00–07:00 que **não vale dentro do turno** (turno da noite recebe normalmente). Limite de 8 mensagens automáticas por pessoa por dia e 3 tarefas extras por pessoa por dia. Na folga nada é enviado: vira um resumo só na volta, de no máximo 7 dias. Rotina tem etiqueta única e não é reenviada se falhar; aviso da pessoa continua sendo reenviado. Bot bloqueado para os envios e aparece na Equipe. Missão da equipe = tarefa sem dono, com hora de disparo, que o primeiro a clicar leva (esforço extra). A 1.13B foi dividida em B1 (feita) e B2 (agenda, pódio, canal confidencial e solicitações). |

## Referência — arquivo do sistema antigo → etapa
| Arquivo em `legado/` | Etapa |
|---|---|
| `api_server.py`, `templates/painel.html`, `static/js/painel.js` | 1.6, 1.8, 1.9, 2.1 |
| `main.py` (14 abas) | 1.5, 1.7, 1.8 |
| `pontos_analyzer.py` | 1.7 |
| `agendamentos_main.py` | 1.9 |
| `escala_loja_main.py` | 2.1 |
| `gestao_pessoas_main.py`, `recibo_generator.py`, `comunicado_generator.py` | 1.10 |
| `gestao_estoque_main.py`, `templates/mobile_*.html` | 2.2 |
| `agendador.py`, `agendador_lembretes.py` | 1.11, 1.13 |
| `telegram_bot.py`, `notificador_telegram.py`, `notificador_whatsapp.py` | 1.13 (nota fiscal: 2.2) |
| `database.py` | referência de regras em todas as etapas |
| `config.py` (tem segredos) | 1.14 |
