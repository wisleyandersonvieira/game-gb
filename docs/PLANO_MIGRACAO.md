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
| 2 | **Fundação multi-empresa** (contas, lojas, isolamento, acesso) | ⬜ Próxima |
| 3 | **Painel do administrador geral** | ⬜ |
| 4 | **Gestão do usuário master** (lojas e seletor de loja) | ⬜ |
| 5 | Telas iniciais: Equipe, Tarefas, Quadro | 🟨 Equipe feita sem lojas; precisa ajuste |
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
- [ ] `contas`: `contaid`, `nome` (nome do cliente/empresa), `email`, `telefone`, `cidade`, `limitelojas` (int, padrão 1), `status` (`ativa` / `suspensa` / `cancelada`), `observacoes`, `criadoem`.
- [ ] `contasusuarios`: `contaid`, `userid` (→ `auth.users`), `papel` (hoje só `master`; no futuro `gerente`). PK (`contaid`, `userid`). **Regra: um login pertence a uma única conta.**
- [ ] `lojas`: `lojaid`, `contaid`, `nome`, `cidade`, `endereco`, `ativa`, `criadoem`.
- [ ] `funcionarioslojas`: (`funcionarioid`, `lojaid`). Liga um funcionário a várias lojas.
- [ ] `tarefaslojas`: (`tarefaid`, `lojaid`). Define em quais lojas a tarefa vale.

**2.2 Coluna de conta e de loja nas tabelas existentes**
- [ ] Todas as tabelas do sistema ganham `contaid NOT NULL` (→ `contas`), com padrão `minha_conta()`, para o front-end nunca precisar informar.
- [ ] As tabelas que pertencem a uma loja ganham também `lojaid` (→ `lojas`). **Antes de migrar, o Claude Code apresenta ao Wisley uma tabela "tabela → nível (conta ou loja)" para aprovação.** Sugestão inicial:
  - **Nível conta (compartilhado entre as lojas):** funcionarios, tarefas, conquistas, conquistasfuncionarios, produtosloja (loja de recompensas), resgates, feedbacks, feedbacksolicitacoes, denunciasanonimas, documentos, documentosassinaturas, documentospessoais, documentospessoaisciencia, onboardingstatus, categoriasproduto, fornecedores, produtosestoque, produtosfornecedor, configuracoes, configuracoessetores, historicoranking.
  - **Nível loja:** tarefasatribuidas, entregas, grupos (grupos do Telegram são da loja), funcionariosgrupos, escaladiaria, configuracoesescala, posicoesloja, picodiario, freelancers, agendamentos, metasprincipais, metasdiariasmodelos, metasdiariasapuracoes, metasdiariasinstancias, lucromensalhistorico, contagensestoque, itenscontagemestoque, notasfiscais, notasfiscaisentrada, itensnotafiscalentrada, solicitacoesinternas.
- [ ] Refazer chaves e unicidades para serem **por conta/loja**, por exemplo: `configuracoessetores` (contaid, setor); `metasdiariasmodelos` e `picodiario` (lojaid, diasemanaid); `configuracoes` (contaid, chave); nomes únicos de grupos, conquistas e categorias, EAN de produto, CNPJ de fornecedor e `lucromensalhistorico`, todos únicos **dentro da conta**, não no sistema inteiro.
- [ ] Garantias no banco: um funcionário só pode ser ligado a lojas da própria conta (o mesmo vale para tarefas e para toda FK entre tabelas); lojas ativas ≤ `contas.limitelojas`; conta `suspensa` fica só leitura.
- [ ] `usuariosadmin` (login do painel Flask antigo) fica obsoleto: remover.

**2.3 Isolamento (RLS)**
- [ ] Função `eh_admin_geral()`: verdadeiro somente para o login `wisley_anderson@hotmail.com` com e-mail confirmado. **Fixa no banco.**
- [ ] Função `minha_conta()`: a conta do usuário logado (via `contasusuarios`).
- [ ] Trocar **todas** as policies `USING (true)` por `contaid = minha_conta()`. `contas` e `contasusuarios`: o admin geral pode tudo; o master só lê a própria conta.
- [ ] Storage: arquivos gravados em `<contaid>/<lojaid>/...`, com policies por pasta.
- [ ] **Teste automático de isolamento:** cria 2 contas com 2 usuários e prova que A não lê, altera nem apaga nada de B, em todas as tabelas. Esse teste roda de novo a cada migração futura.

**2.4 Acesso e navegação**
- [ ] Desligar o cadastro público (tela e configuração do Supabase Auth). Só entra quem foi convidado.
- [ ] Depois do login: admin geral → `/admin`; master → `/gestao`; login sem conta → tela "sem acesso".
- [ ] `client.ts` lendo URL e chave do `.env`. A chave `service_role` fica **só** em variável de servidor, nunca `VITE_`.
- [ ] Atualizar `CLAUDE.md` e `docs/DICIONARIO_BANCO.md` com o modelo novo.

**Pronto quando:** o teste de isolamento passa e cada tipo de usuário cai na sua área.

## Fase 3 — Painel do administrador geral (só o Wisley)
- [ ] Rota `/admin`, visível e acessível somente se `eh_admin_geral()`. A proteção vale na tela e no banco.
- [ ] Cadastro de usuários master (contas): nome, e-mail, telefone, cidade, **quantidade de lojas liberadas**, status, observações.
- [ ] Criar o master envia um **convite por e-mail** para ele definir a senha (função de servidor com `service_role`).
- [ ] Editar, suspender, reativar, reenviar convite.
- [ ] Lista com lojas usadas / lojas liberadas por cliente.
- [ ] Decisão registrada: o admin geral **não** vê os dados operacionais dos clientes (equipe, tarefas etc.), só o cadastro da conta. *(Rever se precisar de suporte: modo "ver como cliente" com registro de acesso.)*

## Fase 4 — Gestão do usuário master
- [ ] Rota `/gestao`: dados da conta e contador "X de Y lojas usadas".
- [ ] Cadastro de lojas (criar, editar, desativar). O botão "Nova loja" fica bloqueado quando atinge o limite, com a mensagem "fale com o suporte para ampliar".
- [ ] **Seletor de loja** no topo do app (loja ativa lembrada no navegador). Telas de nível loja mostram só a loja selecionada; telas de nível conta mostram tudo, com filtro por loja.
- [ ] Criar uma conta nova preenche automaticamente as `configuracoes` padrão (taxa 0,03, bônus, horários).
- [ ] Espaço reservado para o **dashboard por loja** (preenchido na Fase 6).

## Fase 5 — Telas iniciais: Equipe, Tarefas, Quadro
- [x] Equipe: listar, cadastrar, editar, ativar/desativar, dia de folga, filtro de inativos. *(Feita antes da Fase 2)*
- [ ] Equipe: campo **lojas** (seleção múltipla; o funcionário pode estar em várias) e filtro por loja.
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
- **Vínculo por código:** cada funcionário recebe um link `t.me/<bot>?start=<código>`. Ao abrir, o `chat_id` fica ligado àquele funcionário, e com isso à conta e às lojas dele. Os grupos de cada loja são ligados com um comando `/vincular <código>` no grupo.
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
