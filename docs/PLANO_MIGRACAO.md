# Plano do Produto — Game GB (plataforma multi-empresa)

> **Documento-guia do projeto.** Toda sessão de trabalho começa lendo este plano e termina atualizando o **Status geral** e o **Registro de decisões**.
> Repositório: https://github.com/wisleyandersonvieira/game-gb · Supabase: `asgdynxdcdnjglgyyaek`
> Versão 2, de 21/09/2026: o projeto deixou de ser o sistema de uma loja e virou um **produto vendável (SaaS)**.

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
1. **Fundação multi-empresa primeiro (Fase 2).** Toda tela construída depois já nasce separando os dados por conta e por loja. Refazer depois custaria muito mais.
2. **O isolamento entre contas é construído agora, não no fim.** Num produto vendido, a separação dos dados de cada cliente faz parte da função principal. A Fase 16 (Segurança) continua no fim, mas só com o *endurecimento*: tokens antigos, revisão geral, papéis extras.
3. **Stripe e Telegram ficam para o fim** (Fases 14 e 15), nesta ordem, porque a cobrança do Telegram depende do Stripe.
4. Banco limpo: nenhum dado do sistema antigo é importado.

## Status geral

| Fase | Tema | Status |
|---|---|---|
| 1 | Banco de dados (estrutura do sistema antigo) | ✅ Concluída |
| 2 | **Fundação multi-empresa** (contas, lojas, isolamento, acesso) | ✅ Concluída |
| 3 | **Painel do administrador geral** | ✅ Concluída |
| 4 | **Gestão do usuário master** (lojas e seletor de loja) | ✅ Concluída |
| 5 | Telas iniciais: Equipe, Tarefas, Quadro | 🟨 Próxima — Equipe pronta (com lojas). Faltam Tarefas e Quadro: 18 erros de TypeScript, ainda nas tabelas de teste do Lovable |
| 6 | Painel operacional por loja + validação (dashboard da loja) | ⬜ |
| 7 | Gestão de pessoas e gamificação | ⬜ |
| 8 | Metas e financeiro | ⬜ |
| 9 | Agenda (agendamentos) | ⬜ |
| 10 | Escala, mapa e pausas | ⬜ |
| 11 | RH (onboarding, comunicados, documentos) | ⬜ |
| 12 | Estoque (+ telas de celular) | ⬜ |
| 13 | Rotinas automáticas sem Telegram | ⬜ |
| 14 | **Comercialização:** publicação online + Stripe | ⬜ |
| 15 | **Telegram e WhatsApp da plataforma** + cobrança por uso | ⬜ |
| 16 | Segurança final (endurecimento) | ⬜ |

Legenda: ⬜ não iniciada · 🟨 em andamento · ✅ concluída · ⏸️ pausada

---

## Fase 1 — Banco de dados (estrutura do sistema antigo) ✅
- [x] Estrutura extraída do backup `banco_teste.bak` e convertida para Postgres: 42 tabelas, 40 FKs, índices.
- [x] Nomes originais em minúsculas (`FuncionarioID` → `funcionarioid`); chaves inteiras automáticas.
- [x] Banco limpo, sem dados antigos.
- [x] Repositório preparado para o VS Code; Python antigo em `legado/`.
- [x] Aplicado no Supabase; `types.ts` gerado.
- [x] Tabela `configuracoes` (18 chaves) e buckets `entregas`, `notas-fiscais`, `documentos-rh`, `layout-loja`.
- [x] Chaves primárias naturais nas 5 tabelas sem PK; `funcionarios.ativo`; `configuracoes.atualizadoem`.
- ⚠️ Vários itens desta fase **mudam na Fase 2**: chaves e unicidades passam a ser por conta/loja, e `configuracoes` passa a ser por conta.

## Fase 2 — Fundação multi-empresa
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

**Feito em 21/09/2026 (2.1 a 2.3):** 47 tabelas, nenhuma sem RLS, 201 policies, nenhuma liberada, banco vazio. O teste de isolamento (`supabase/tests/rodar.sh`) roda 30 checagens com duas contas e passa. Ele já pegou um bug antes de ir para o Supabase: as policies de Storage da Fase 1 não eram removidas e, como policies se somam, vazavam arquivos entre contas.

**Feito em 21/09/2026 (2.4):** cadastro público desligado na tela e no Supabase Auth (`disable_signup`). URL do site e lista de redirecionamentos apontando para `http://localhost:8080`. A porta de entrada (`/`) encaminha conforme o banco responde: admin geral → `/admin`, master → `/gestao`, login sem conta → `/sem-acesso`. Rota `/definir-senha` criada para o link do convite.

**Pronto quando:** o teste de isolamento passa e cada tipo de usuário cai na sua área.

## Fase 3 — Painel do administrador geral (só o Wisley)
- [x] Rota `/admin`, visível e acessível somente se `eh_admin_geral()`. A proteção vale na tela e no banco.
- [x] Cadastro de usuários master (contas): nome, e-mail, telefone, cidade, **quantidade de lojas liberadas**, status, observações.
- [x] Criar o master envia um **convite por e-mail** para ele definir a senha (função de servidor com `service_role`).
- [x] Editar, suspender, reativar, reenviar convite.
- [x] Lista com lojas usadas / lojas liberadas por cliente.
- [x] Decisão registrada: o admin geral **não** vê os dados operacionais dos clientes (equipe, tarefas etc.), só o cadastro da conta. *(Rever se precisar de suporte: modo "ver como cliente" com registro de acesso.)*

**Feito em 21/09/2026.** As funções de servidor ficam em `src/servidor/contas.ts`. A chave `service_role` é lida em `client.server.ts` a partir de `process.env` (sem `VITE_`), por import dinâmico dentro do handler, para não entrar no pacote que vai para o navegador. **Toda** função confere `eh_admin_geral()` no servidor, com o token de quem chamou — esconder o botão na tela não é proteção. Se o convite falhar, a conta recém-criada é desfeita, para não sobrar cadastro pela metade. Criar um cliente já semeia as configurações padrão dele.

⚠️ Para o convite funcionar, `SUPABASE_SERVICE_ROLE_KEY` precisa estar preenchida no `.env` (modelo em `.env.example`). Sem ela a tela abre e lista, mas o cadastro dá erro.

## Fase 4 — Gestão do usuário master
- [x] Rota `/gestao`: dados da conta e contador "X de Y lojas usadas".
- [x] Cadastro de lojas (criar, editar, desativar). O botão "Nova loja" fica bloqueado quando atinge o limite, com a mensagem "fale com o suporte para ampliar".
- [x] **Seletor de loja** no topo do app (loja ativa lembrada no navegador). Telas de nível loja mostram só a loja selecionada; telas de nível conta mostram tudo, com filtro por loja.
- [x] Criar uma conta nova preenche automaticamente as `configuracoes` padrão (taxa 0,03, bônus, horários).
- [x] Espaço reservado para o **dashboard por loja** (preenchido na Fase 6).

**Feito em 21/09/2026.** O seletor de loja fica no menu do topo (`src/lojas/loja-ativa.tsx`), lembra a escolha no navegador e, se a loja lembrada for desativada, cai para a primeira em vez de deixar a tela sem loja. Com uma loja só, ela aparece como texto, sem seletor. Sem loja nenhuma, as telas do app mostram "Cadastre sua primeira loja" com link para a gestão.

As regras de limite já valiam no banco desde a Fase 2 e foram **provadas por teste**, não só pela tela: loja desativada não ocupa vaga, desativar é sempre permitido (mesmo no limite), reativar acima do limite é recusado, e desativar não apaga nada — as atribuições e entregas daquela loja continuam inteiras. A tela apenas reflete isso: o botão "Nova loja" some no limite e o "Reativar" fica bloqueado quando não há vaga.

## Fase 5 — Telas iniciais: Equipe, Tarefas, Quadro
- [x] Equipe: listar, cadastrar, editar, ativar/desativar, dia de folga, filtro de inativos. *(Feita antes da Fase 2)*
- [x] Equipe: campo **lojas** (seleção múltipla; o funcionário pode estar em várias) e filtro por loja.
- [ ] Tarefas: cadastrar, editar, desativar, com **seleção das lojas onde a tarefa vale**.
- [ ] Atribuição: só permite atribuir a funcionários que trabalham numa loja onde a tarefa vale. Registra a loja.
- [ ] Atribuir tarefa **não** cria entrega. A entrega nasce quando o funcionário envia (por enquanto, botão "Registrar entrega" com foto; depois, pelo bot).
- [ ] Recorrência: mostrar ao Wisley os tipos de frequência do sistema antigo (`legado/`) e como funcionavam, **antes** de implementar.
- [ ] Quadro (validação): aprovar, com crédito atômico de pontos pela função SQL `aprovar_entrega`; recusar, com motivo obrigatório; foto da entrega.
- [ ] Ranking diário e mensal, por loja e geral da conta.
- [ ] Remover `ID_GESTOR_PADRAO` e `RESPONSAVEL_AGENDAMENTOS_ID` como IDs soltos: viram campos escolhidos na tela (por loja).
- [ ] Recadastrar as tarefas especiais do sistema (feedback diário, leitura, nota fiscal, pontos da meta, guardar mercadoria, modelo de agendamento) como **tarefas do sistema criadas automaticamente em cada conta nova**, com os IDs registrados em `configuracoes`.

## Fase 6 — Painel operacional por loja + validação (dashboard da loja)
Substitui a aba Operacional do `painel.html`. É também o **dashboard por loja** da gestão.
- [ ] Barra de progresso do dia e hora da última atualização (Realtime).
- [ ] Pódio diário.
- [ ] Kanban: Para Fazer (hoje) · Em Validação · Atividade Recente.
- [ ] Resgates recentes.
- [ ] Próximos agendamentos (depois da Fase 9).
- [ ] Animação de fogos ao bater a meta.
- [ ] Na `/gestao`: resumo de todas as lojas lado a lado.

## Fase 7 — Gestão de pessoas e gamificação (abas do `main.py`)
- [ ] Grupos (por loja).
- [ ] Pendências e justificativas ("Não aplicável").
- [ ] Loja de recompensas e resgates.
- [ ] Conquistas.
- [ ] Feedbacks, canal confidencial e solicitações internas (visão do gestor).
- [ ] Relatórios e histórico por funcionário.
- [ ] Extrato de pontos (substitui `pontos_analyzer.py`).

## Fase 8 — Metas e financeiro (por loja)
- [ ] Meta de faturamento mensal.
- [ ] Modelos de meta diária por dia da semana.
- [ ] Apuração diária (lançar vendas).
- [ ] Mostrar/ocultar valores do dia.
- [ ] Meta de lucro com histórico.
- [ ] Pontos automáticos para a equipe da loja ao bater a meta diária.

## Fase 9 — Agenda (por loja)
- [ ] Calendário (mês/semana).
- [ ] Cadastro de agendamento: funcionário, cliente, telefone, CPF, data, hora, tipo, pagamento, observações.
- [ ] Marcar pagamento; documentos anexos.

## Fase 10 — Escala, mapa e pausas (por loja)
- [ ] Mapa da loja: cada loja envia a própria planta; marcadores de posição.
- [ ] Posições e setores.
- [ ] Escala diária: montar, copiar, freelancers.
- [ ] Picos e gráfico de fluxo por setor.
- [ ] Escala de hoje e pausas com relógio.

## Fase 11 — RH
- [ ] Onboarding / admissional.
- [ ] Comunicados com destinatários e confirmação de leitura.
- [ ] Documentos pessoais com ciência/assinatura.
- [ ] PDFs de recibo e comunicado.

## Fase 12 — Estoque
- [ ] Catálogo e categorias (da conta); estoque e contagens (por loja).
- [ ] Fornecedores e vínculo DE/PARA.
- [ ] **Avaliar mover o EAN para o catálogo.** Hoje o código de barras fica em `produtosfornecedor`, porque era assim no sistema antigo e `produtosestoque` não tem coluna de EAN. Conceitualmente o EAN é do produto, não do fornecedor. Avaliar a mudança aqui, junto com as telas de estoque.
- [ ] Importação de XML de NF-e.
- [ ] Contagem física (computador e **celular**, com leitura de código de barras).
- [ ] Auditoria de EAN pelo celular.
- [ ] Desmembrar caixa; sugestão de compra; solicitações dos líderes; consulta de NFs.

## Fase 13 — Rotinas automáticas sem Telegram
Via **pg_cron** e funções SQL/Edge Functions, **rodando para todas as contas**, cada uma com seus horários em `configuracoes`:
- [ ] Geração diária das tarefas recorrentes.
- [ ] Fechamento mensal e histórico do ranking.
- [ ] Delegação de tarefas de folga.

## Fase 14 — Comercialização: publicação online + Stripe
- [ ] **Configurar SMTP próprio (ex.: Resend) antes de vender.** O e-mail embutido do Supabase só serve para teste: tem limite baixo de envios e não usa o nosso domínio. Sem isso, convite e recuperação de senha não são confiáveis para clientes de verdade.
- [ ] Publicar o app (hospedagem + domínio próprio), com ambientes de teste e produção separados.
- [ ] Nome e identidade do produto (hoje "Game GB", ligado à Gela Boca).
- [ ] Termos de uso e política de privacidade (LGPD: o app guarda CPF e telefone de funcionários dos clientes).
- [ ] **Stripe:** assinatura por quantidade de lojas (preço por loja). O webhook do Stripe atualiza `contas.limitelojas` e `contas.status` sozinho.
- [ ] Período de teste; portal do cliente Stripe (cartão, faturas, cancelamento).
- [ ] Inadimplência → conta `suspensa` (só leitura) → `cancelada` depois de X dias.
- [ ] O painel do admin mostra a situação da assinatura de cada cliente.

## Fase 15 — Telegram e WhatsApp da plataforma + cobrança por uso
**Estratégia (a detalhar quando chegar a hora):**
- **Um único bot da plataforma** (token do Wisley), atendendo todas as contas, em vez de um bot por cliente. O cliente não precisa criar nada no Telegram.
- **Vínculo por código:** cada funcionário recebe um link `t.me/<bot>?start=<código>`. Ao abrir, o `chat_id` fica ligado àquele funcionário, e com isso à conta e às lojas dele.
- ⚠️ **A desenhar aqui:** `funcionarios.chatidtelegram` é único **só dentro da conta**, porque a mesma pessoa pode trabalhar para duas empresas clientes. Então o `chat_id` sozinho não identifica a conta: quando a pessoa aparece em mais de uma, o bot precisa perguntar de qual empresa ela está falando (ou manter uma conta ativa por conversa). `grupos.chatidtelegram` é único no sistema inteiro, então grupo não tem essa ambiguidade. Os grupos de cada loja são ligados com um comando `/vincular <código>` no grupo.
- **Bot reescrito como Edge Function (webhook) no Supabase**, e não mais o servidor Python. Isso muda a recomendação anterior (manter o Python): com várias contas, um serviço central na nuvem é mais simples e confiável. O `legado/telegram_bot.py` serve de especificação das funções.
- **Fila de envio central** (tabela + processamento), respeitando os limites do Telegram (≈30 msg/s no total, ≈20/min por grupo), para uma conta não atrasar as outras.
- **Medição de uso:** todo envio (Telegram/WhatsApp) é registrado em `usomensagens` (conta, loja, canal, tipo, data). O total do mês vai para o Stripe como **cobrança por uso** ou como franquia incluída no plano, com excedente.
- **WhatsApp (Z-API):** decidir entre um número da plataforma para todos ou um número por cliente (custo por instância repassado).
- Funções a portar: comandos (/start, /tarefas, /ranking, /meuhistorico, /meusaldo, /loja, /documentos, /conquistas, /ajuda, /pendencias, /status_meta, /lancar), recebimento de foto com validação EXIF, canal confidencial, solicitações, abate de comanda, notificações de jornada, lembretes, recusa com motivo, meta batida, confirmação e pós-venda por WhatsApp.
- Desligar os serviços antigos (`systemctl`) e o SQL Server.

## Fase 16 — Segurança final (endurecimento)
- [ ] **Já, sem esperar esta fase:** deixar o repositório GitHub privado (se ainda não foi) e revogar o token `sbp_` colado no chat.
- [ ] Revogar o token antigo do bot (@BotFather), os tokens da Z-API e as senhas antigas do `legado/config.py`; remover o `legado/config.py` do histórico.
- [ ] Papéis extras dentro da conta (gerente de loja com acesso só às suas lojas).
- [ ] Revisão completa das policies, do Storage (buckets privados + URLs assinadas) e das funções `security definer`.
- [ ] Registro de auditoria (quem alterou o quê) nas tabelas sensíveis.
- [ ] Backups e plano de recuperação.

---

## Decisões em aberto (perguntar ao Wisley quando a fase chegar)
| # | Pergunta | Sugestão padrão |
|---|---|---|
| 1 | Saldo de pontos e loja de recompensas: um saldo por funcionário na conta toda, ou separado por loja? | Um saldo por funcionário na conta toda |
| 2 | O master vai ter outros usuários (gerente de loja, líder) entrando no painel? | Sim, na Fase 16; por enquanto só o master |
| 3 | Uma mesma pessoa (e-mail) pode ser master de duas contas? | Não: um login, uma conta |
| 4 | O admin geral precisa ver os dados dos clientes para suporte? | Não; se precisar, "ver como cliente" com registro |
| 5 | Preço: por loja, por plano fechado, ou por loja + uso de mensagens? | Por loja + franquia de mensagens |

## Como trabalhar cada fase
Ferramenta: **Claude Code no VS Code**, direto no repositório. Regras permanentes em `CLAUDE.md`. Este plano fica em `docs/PLANO_MIGRACAO.md`, com cópia no projeto Claude "Game GB".
1. Começar a sessão com: "Leia o CLAUDE.md e o docs/PLANO_MIGRACAO.md e continue a próxima fase pendente."
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

## Referência — arquivo do sistema antigo → fase
| Arquivo em `legado/` | Fase |
|---|---|
| `api_server.py`, `templates/painel.html`, `static/js/painel.js` | 6, 8, 9, 10 |
| `main.py` (14 abas) | 5, 7, 8 |
| `pontos_analyzer.py` | 7 |
| `agendamentos_main.py` | 9 |
| `escala_loja_main.py` | 10 |
| `gestao_pessoas_main.py`, `recibo_generator.py`, `comunicado_generator.py` | 11 |
| `gestao_estoque_main.py`, `templates/mobile_*.html` | 12 |
| `agendador.py`, `agendador_lembretes.py` | 13, 15 |
| `telegram_bot.py`, `notificador_telegram.py`, `notificador_whatsapp.py` | 15 |
| `database.py` | referência de regras em todas as fases |
| `config.py` (tem segredos) | 16 |
