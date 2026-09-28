# Mapa de permissões — Etapa 0 (para aprovação do Wisley)

> **APROVADO pelo Wisley em 29/09/2026**, com os ajustes da seção
> "Decisões aprovadas" no fim deste arquivo. Onde o texto abaixo e as decisões
> discordarem, **valem as decisões**.

Levantado em 29/09/2026 **a partir do banco, não da memória das telas**: todas as
migrações aplicadas num Postgres de teste, e o próprio banco respondeu
(1) quais funções quem está logado pode chamar, (2) em quais tabelas pode gravar
direto, coluna por coluna, e (3) quais funções de servidor gravam com a chave de
servidor. Depois cada uma foi ligada à tela que a chama.

**Números:** 146 funções liberadas para quem está logado (65 gravam dado; o resto
só lê ou calcula). 36 tabelas com escrita direta liberada. 20 funções de servidor
de gestão. Fora disso ficam as operações do admin geral, do tablet, do celular do
colaborador e do bot: elas não são do gestor e não entram no mapa.

**Como é hoje:** existem dois papéis de gestão no banco, `master` e `gerente`. O
`gerente` já existe na estrutura, mas nenhuma tela cria um. Os dois entram pela
mesma porta (`minha_conta`), então **hoje um gerente faria tudo o que o master
faz**, menos as cerca de 30 operações que já conferem "é o master?" (22 funções do banco e as do servidor da Equipe e do tablet).

Legenda da coluna "Permissão": **(sua)** = estava na sua lista · **(FALTOU)** =
não estava e o sistema faz · **(só master)** = proposta de não delegar.

---

## a) + b) Toda operação que grava, por tela, e a permissão que a cobre

### Início
| Operação | Onde está no sistema | Permissão |
|---|---|---|
| Ver o Início (cartões, contagens, "tarefas de hoje") | `painel_inicio`, `tarefas_nao_pegas` | Início: ver (sua) |
| Bolinhas vermelhas do menu | `contagem_do_menu` | cada bolinha conta só o que a pessoa pode abrir (regra 4) |

### Painel da loja (FALTOU a tela inteira)
| Ver o painel operacional da loja | `painel_da_loja` | Painel da loja: ver (FALTOU) |

### Quadro
| Operação | Onde | Permissão |
|---|---|---|
| Ver quadro de validação, fila do dia, fila de outro dia | `quadro_validacao`, `atribuicoes_para_entregar`, `fila_da_loja`, `fila_de_um_dia`, `alcance_da_fila` | Quadro: ver (sua) |
| Registrar entrega em nome de alguém | `registrar_entrega` | Quadro: registrar entrega (sua) |
| Aprovar entrega (dá pontos) | `aprovar_entrega` | Quadro: aprovar (sua) |
| Recusar entrega | `recusar_entrega` | Quadro: recusar (sua) |
| **Estornar entrega aprovada (tira os pontos)** | `estornar_entrega` | Quadro: estornar (FALTOU) |
| **Revogar o aceite de alguém** (a tarefa volta para a fila) | `revogar_aceite` | Quadro: revogar aceite (FALTOU) |
| **Passar a tarefa de quem está de folga** para outra pessoa | `passar_tarefa_de_folga`, `tarefas_de_folga_hoje`, `quem_trabalha_hoje` | Quadro: passar tarefa de folga (FALTOU) |

### Tarefas
| Operação | Onde | Permissão |
|---|---|---|
| Ver catálogo e atribuições | `catalogo_de_tarefas`, `atribuicoes_da_loja` | Tarefas: ver (sua) |
| Atribuir tarefa a pessoas | `atribuir_tarefa` | Tarefas: criar e atribuir (sua) |
| Mudar a hora de uma atribuição | `alterar_hora_da_atribuicao` | Tarefas: criar e atribuir (sua) |
| Encerrar uma atribuição (para de valer daqui em diante) | escrita direta em `tarefasatribuidas` | Tarefas: desativar (sua) |
| Ativar/desativar tarefa do catálogo | escrita direta em `tarefas` (ativa) | Tarefas: desativar (sua) |
| Criar tarefa nova no catálogo, editar título/pontos/lojas | escrita direta em `tarefas` e `tarefaslojas` | Tarefas: editar catálogo (sua) |

> Precisa da sua palavra: "criar" uma tarefa nova no catálogo eu pus em **editar
> catálogo**, e "criar e atribuir" ficou só atribuir. É isso?

### Solicitações
| Ver solicitações e histórico | leitura de `solicitacoesinternas` | Solicitações: ver (sua) |
|---|---|---|
| **Abrir uma solicitação pelo painel** | `abrir_solicitacao` | Solicitações: abrir (FALTOU) |
| Mudar para "em andamento" / concluir | `mudar_situacao_solicitacao` | Solicitações: concluir (sua) |
| Recusar | `mudar_situacao_solicitacao` | Solicitações: recusar (sua) |

### Relatórios (FALTOU a tela inteira)
| Ver análise de tarefas, histórico e pendências da pessoa | `analise_de_tarefas`, `historico_da_pessoa`, `pendencias_da_pessoa`, `tarefas_pegas_da_pessoa` | Relatórios: ver (FALTOU) |
|---|---|---|
| Registrar justificativa a partir do relatório | `registrar_justificativa` | Justificativas: registrar (FALTOU) |

### Equipe
| Operação | Onde | Permissão |
|---|---|---|
| Ver a equipe | leitura de `funcionarios` | Equipe: ver (sua) |
| Cadastrar pessoa | escrita direta em `funcionarios` e `funcionarioslojas` | Equipe: criar pessoa (sua) |
| Editar pessoa (nome, cargo, folga, afastamento, telefone, lojas) | escrita direta em `funcionarios` e `funcionarioslojas` | Equipe: editar (sua) |
| **Desativar / reativar pessoa** (derruba o login dela na hora) | servidor `desativarColaborador` | Equipe: desativar (FALTOU) |
| Criar acesso, gerar código, PDF da folha, ver situação dos acessos | servidor `criarAcessoColaborador`, `gerarCodigoDeAcesso`, `emitirFolhasDeAcesso`; `situacao_dos_acessos` | Equipe: criar acesso (sua) |
| **Redefinir acesso** (apaga senha e PIN) e **trocar CPF** (muda o login) | servidor `redefinirAcessoColaborador`, `trocarCpfDoColaborador` | Equipe: redefinir acesso (FALTOU) |
| **Liberar PIN do tablet** | `liberar_pin`, `travas_do_pin` | Equipe: liberar PIN (FALTOU) |
| Convite do Telegram da pessoa | `criar_convite_telegram` | fica para a Etapa 1.13 (hoje só master) |
| Marcar "validador" da loja (aprova pelo Telegram) | coluna `validador` em `funcionarioslojas` | fica para a Etapa 1.13 (é uma permissão paralela, do Telegram) |
| Vincular jornada à pessoa | `vincular_jornada` | Jornada: criar e editar (sua) |

### Jornada
| Ver jornadas | leitura | Jornada: ver (sua) |
|---|---|---|
| Criar, editar, apagar jornada; vincular pessoas | `salvar_jornada`, `vincular_jornada`, escrita direta em `jornadas` (apagar) | Jornada: criar e editar (sua) |
| Intervalo do mapa (planejamento) | `salvar_intervalo_do_mapa` | Jornada: criar e editar (sua) |
| Ver o Mapa e exportar PDF | `mapa_da_jornada`, `mapa_da_semana` | Jornada: mapa e exportar (sua) |

### Feedbacks (FALTOU a tela inteira)
| Ver feedbacks | leitura | Feedbacks: ver (FALTOU) |
|---|---|---|
| **Registrar feedback** (pode dar pontos) | `registrar_feedback` | Feedbacks: registrar (FALTOU) |
| **Anular feedback** (desfaz os pontos) | `anular_feedback` | Feedbacks: anular (FALTOU) |

### Justificativas (FALTOU a tela inteira)
| Ver | `justificaveis` | Justificativas: ver (FALTOU) |
|---|---|---|
| Registrar em nome da pessoa | `registrar_justificativa` | Justificativas: registrar (FALTOU) |
| Aceitar / recusar | `decidir_justificativa` | Justificativas: decidir (FALTOU) |

### Ranking, Conquistas, Extrato (FALTARAM)
| Ver ranking e meses fechados | `ranking_pontos`, `ranking_mensal`, `fechamento_valendo` | Ranking: ver (FALTOU) |
|---|---|---|
| **Refazer o fechamento de um mês** (recalcula prêmio de todos) | `refazer_fechamento` | **só master** (hoje já é) |
| Ver conquistas | leitura | Conquistas: ver (FALTOU) |
| Criar e editar conquista (dá pontos bônus) | `criar_conquista`, escrita direta em `conquistas` | Conquistas: editar (FALTOU) |
| Ver o extrato de pontos | `extrato_pontos` | Extrato: ver (FALTOU) |

### Prêmios
| Operação | Onde | Permissão |
|---|---|---|
| Ver trocas, recibos | `listar_trocas`, `recibo_resgate`, `minha_taxa` | Prêmios: ver (sua) |
| Registrar resgate (prêmio ou abate na comanda) | `registrar_troca`, `registrar_troca_por_valor` | Prêmios: registrar resgate (sua) |
| Entregar o resgate pedido | `concluir_troca` | Prêmios: aprovar resgate (sua) |
| **Cancelar resgate** (devolve os pontos) | `cancelar_troca` | Prêmios: cancelar resgate (FALTOU) |
| **Estornar resgate já entregue** | `estornar_troca` | Prêmios: estornar resgate (FALTOU) |
| Criar/editar/desativar prêmio do catálogo | escrita direta em `produtosloja` | Prêmios: editar catálogo (sua) |

### Metas
| Ver metas | `metas_do_mes`, `meta_do_dia` | Metas: ver (sua) |
|---|---|---|
| Lançar a venda do dia | `lancar_venda_do_dia` | Metas: lançar venda (sua) |
| Meta do mês e meta de cada dia da semana | `salvar_meta_do_mes`, escrita direta em `metasdiariasmodelos` | Metas: criar meta (sua) |
| Meta especial (criar, apagar) | escrita direta em `metasespeciais` | Metas: criar meta especial (sua) |

### Agenda (FALTOU a tela inteira)
| Ver agenda, conflitos | `conflitos_agendamento`, `agendamentos_sem_tarefa` | Agenda: ver (FALTOU) |
|---|---|---|
| Criar, editar, remarcar, trocar responsável, reabrir, cancelar, anexos, tipos de evento | `criar_agendamento`, `editar_agendamento`, `remarcar_agendamento`, `trocar_responsavel_agendamento`, `reabrir_agendamento`, `cancelar_agendamento`, `registrar_anexo_agendamento`, `remover_anexo_agendamento`, `recriar_tarefa_do_agendamento`, escrita direta em `tiposevento` | Agenda: criar e editar (FALTOU) |
| Marcar como realizado | `marcar_agendamento_realizado` | Agenda: marcar realizado (FALTOU) |
| **Pagamento do agendamento (R$)** | `alterar_pagamento_agendamento` | Agenda: pagamento (FALTOU) |

### Comunicados e Onboarding (FALTARAM)
| Ver comunicados e quem deu ciência | `recibo_ciencia`, `fora_do_comunicado` | Comunicados: ver (FALTOU) |
|---|---|---|
| Publicar, editar, arquivar, incluir destinatários | `publicar_comunicado`, `editar_comunicado`, `arquivar_comunicado`, `incluir_destinatarios` | Comunicados: publicar (FALTOU) |
| Registrar ciência em nome da pessoa | `registrar_ciencia` | Comunicados: publicar (FALTOU) |
| Desfazer ciência | `desfazer_ciencia` | **só master** (hoje já é) |
| Ver onboarding | leitura | Onboarding: ver (FALTOU) |
| Iniciar e marcar etapas de uma pessoa | `iniciar_onboarding`, `marcar_etapa_onboarding` | Onboarding: conduzir (FALTOU) |
| Editar as etapas do modelo | escrita direta em `onboardingetapas` | Onboarding: editar etapas (FALTOU) |

### Lojas e links da TV
| Operação | Onde | Permissão |
|---|---|---|
| Ver lojas | `resumo_das_lojas` | Lojas: ver (sua) |
| Editar dados da loja (nome, endereço, fuso) | escrita direta em `lojas` | Lojas: editar (sua) |
| Configurar TV, criar/revogar link, parear TV | `salvar_tv_da_loja`, `criar_link_tv`, `revogar_link_tv`, `parear_tv` | Lojas: configurar TV (sua) |
| **Som do tablet** | `salvar_som_da_loja` | Lojas: configurar tablet (FALTOU) |
| **Senha do tablet** (criar acesso, redefinir, ficha) | servidor `criarAcessoLoja`, `redefinirSenhaLoja`, `definirSenhaDoTablet`, `fichaDosTablets` | Lojas: acesso do tablet (FALTOU; sensível: quem tem a senha opera a loja) |
| **Criar loja, ativar/desativar loja** | escrita direta em `lojas` | **só master** (mexe no limite contratado) |

### Valores em R$ (sua)
"Ver valores em R$" não é uma operação: é um **filtro de leitura** que tem de
existir em toda função que devolve dinheiro (metas, meta na TV, abate na comanda,
pagamento da agenda). Sem ele, a função devolve o percentual e não o R$. Já existe
a mesma ideia na TV ("mostrar valores"); vira uma regra única por pessoa.

### Configurações
| Usuários e cargos (a página nova) | — | **só master, nunca delegável** (sua) |
|---|---|---|
| Parâmetros da conta (pontos, minutos, IDs especiais) | `alterar_configuracao` | **só master** (proposta) |
| Mensagens automáticas, geração de rotinas, política de uso | `definir_rotina_mensagem`, `rodar_geracao_hoje`, `publicar_politica_de_uso` | **só master** (hoje já é) |
| Telegram do grupo e do próprio gestor | `criar_convite_grupo`, `criar_convite_meu_telegram`, `desligar_telegram`, `marcar_aviso_lido` | Etapa 1.13 |

### Sempre da própria pessoa (não é permissão)
Meu perfil, trocar a própria senha, ler a própria `/saude` e o próprio acesso
(`meu_acesso`, `meu_hoje`, `trocarMinhaSenha`). Todo usuário gerencial pode.

---

## c) O que sobrou SEM permissão nenhuma — os riscos

1. **20 tabelas aceitam escrita direta de qualquer gestor e não têm tela** (são
   da Fase 2: escala, estoque, notas fiscais, financeiro):
   `configuracoesescala`, `configuracoessetores`, `escaladiaria`, `posicoesloja`,
   `picodiario`, `freelancers`, `grupos`, `funcionariosgrupos`,
   `contagensestoque`, `itenscontagemestoque`, `produtosestoque`, `fornecedores`,
   `produtosfornecedor`, `categoriasproduto`, `notasfiscais`,
   `notasfiscaisentrada`, `itensnotafiscalentrada`, `lucromensalhistorico`,
   `metasdiariasinstancias`, `feedbacksolicitacoes`.
   Hoje só o master chega nelas, então o risco é pequeno. Com gestores, qualquer
   um poderia gravar ali chamando o banco por fora. **Proposta:** fechar a
   escrita (só master) até a tela existir. É exatamente o caso da regra 2.
2. **Colunas de `funcionarios` que a tela não usa, mas o banco deixa gravar
   direto:** `cpf` (o jeito certo de trocar é o "Trocar CPF", que muda o login
   junto), `isgestor` e `chatidtelegram`. **Proposta:** tirar essas três da
   escrita direta.
3. **As operações de servidor da Equipe e do tablet** (criar acesso, redefinir,
   trocar CPF, desativar, senha do tablet) conferem "é o master?" **no código do
   servidor**, não no banco. Para valer a regra 1, o servidor passa a perguntar
   **ao banco**, com o login da própria pessoa, "ela pode X na loja Y?", e o
   banco responde.
4. **`alterar_configuracao` é uma operação só para parâmetros muito diferentes**
   (pontos, minutos, IDs especiais). Por isso a proposta é deixar só com o master.
5. **As leituras hoje filtram só por conta, nunca por loja.** A regra 4 ("não
   pode ver um número que não consegue abrir") obriga a refazer as leituras das
   telas de gestão: Início, bolinhas do menu, Quadro, fila, painel da loja,
   relatórios, metas. **É a maior parte do trabalho**, maior que as escritas.
6. **As escritas diretas em tabela** (`tarefas`, `lojas`, `funcionarios`,
   `produtosloja`, `metasespeciais`...) só conferem a conta. Para conferir a
   permissão **e** a loja no banco, elas passam a ter a trava na própria regra da
   tabela, ou viram funções. **Proposta:** virar funções. É mais fácil de testar,
   e o teste "operação nova nasce negada" fica possível (item abaixo).
7. **Algumas regras de escrita no banco estão sem efeito** (`entregas`,
   `agendamentos`, `resgates`, `documentos` e outras têm regra de escrita, mas a
   escrita direta não é liberada). Não é falha: hoje tudo passa por função. Entram
   na limpeza.

---

## d) O que NÃO pode ser delegado nunca

- **Configurações → Usuários e cargos** (criar, editar, apagar usuário gerencial
  e cargo). Regra 3.
- **Canal confidencial** (`tratar_relato`). Já está escrito no CLAUDE.md: só o
  master, nenhum papel futuro.
- **Documentos pessoais** (RH: registrar, liberar, arquivar, apagar por engano).
  Hoje já é só master. Proposta: continua.
- **Criar loja, ativar e desativar loja** (mexe no limite contratado).
- **Refazer fechamento do mês** e **desfazer ciência** (hoje já são só master).
- **Parâmetros da conta, mensagens automáticas, geração de rotinas, política de
  uso.**
- **Medir desempenho / diagnóstico.**
- Tudo do **admin geral** (fica fora da conta, como hoje).

---

## e) Como o usuário gerencial recebe o acesso — proposta

**E-mail e senha, por convite.** É o mesmo caminho do master, que já existe e
foi testado (`criarContaEConvidar` + `/definir-senha`):

1. O master, em Configurações → Usuários, digita nome, e-mail, cargo e lojas.
2. O sistema manda o convite para o e-mail. A pessoa abre o link e cria a
   própria senha. O master nunca vê nem escolhe a senha.
3. O convite vence em alguns dias, e o master pode reenviar.
4. Desativar o usuário derruba o login na hora (como já acontece na Equipe).

Por que não a folha de acesso da equipe: ela usa CPF e código impresso, que é
feita para quem não tem e-mail e usa o celular. Gestor vê R$ e aprova pontos. E-mail
e senha própria deixa o rastro de "quem fez" amarrado a uma pessoa, e a
recuperação de senha já existe.

**Decisão sua:** a mesma pessoa pode ser **funcionária** (faz tarefa, ganha
ponto, entra pelo CPF) **e gerente**? Hoje um login pertence a uma conta com um
papel só. Minha proposta: **dois logins separados** (CPF para o celular, e-mail
para a gestão). Assim o gerente nunca aprova a própria entrega pelo mesmo login.
Proposta extra: se um dia o usuário gerencial for ligado a um funcionário, o
banco recusa que ele aprove a própria entrega.

---

## Como a trava fica no banco (resumo técnico, para conferência)

- Tabelas novas: `cargos`, `cargospermissoes` (cargo × código da permissão),
  `usuarioslojas` (usuário × loja), `permissoes` (o **catálogo**: código, tela,
  descrição), e um **histórico** que só recebe linhas novas: quem criou o
  usuário, quem mudou o cargo dele, quem mudou as permissões do cargo, e quando.
- Uma função só decide: `pode(permissao, loja)`. O master responde sempre sim.
  O gerente responde sim só se o cargo tem a permissão **e** a loja está na lista
  dele. Toda operação de gestão chama essa função **na hora**, a cada escrita, sem
  guardar em cache. Por isso tirar a permissão vale na ação seguinte (regra 5).
- **Nasce negada (regra 2):** permissão não marcada é "não". O cargo "Acesso
  total" também **não** ganha sozinho uma permissão nova. E uma trava no teste
  lista toda função que grava e é liberada para quem está logado: cada uma tem de
  chamar `pode(...)` com um código que existe no catálogo, ou estar numa lista
  fechada (só master, própria pessoa). Função nova fora disso reprova o teste.
- **Virada (regra 7):** todo master continua master (tem tudo, sem cargo). O
  cargo "Acesso total" nasce com todas as permissões delegáveis e todas as lojas,
  e todo login `gerente` que existir vai para ele.

---

## Decisões que preciso de você

1. **Aprovar a lista** (as suas + as FALTOU) e os "só master".
2. **Tarefas:** "criar tarefa nova" fica em "editar catálogo"? E "desativar"
   cobre encerrar a atribuição **e** desativar a tarefa do catálogo?
3. **O que é da conta, não da loja** (catálogo de tarefas, prêmios, conquistas,
   comunicados, jornadas): um gerente das lojas A e B que edita o catálogo mexe
   em todas as lojas. Pode, com a permissão marcada? Ou catálogo fica só master?
4. **Quem o gerente enxerga na Equipe:** só as pessoas ligadas às lojas dele
   (proposta), ou a equipe toda da conta?
5. **Funcionário que também é gerente:** dois logins (proposta)?
6. **Fechar as 20 tabelas sem tela** e as 3 colunas de `funcionarios` já na
   primeira entrega (proposta: sim).

---

## Decisões aprovadas (Wisley, 29/09/2026)

**Antes de tudo:** o papel "gerente" que já existia foi **fechado**
(`20260929247000_fechar_papel_gerente.sql`): sem conta para as regras de acesso
e sem login, até a permissão por cargo existir.

1. **Lista aprovada**, com três acréscimos:
   - **Trocar CPF é só master.** É a única operação que muda quem é a pessoa no
     sistema. "Equipe: redefinir acesso" fica só com o redefinir.
   - **Lista de estornos para o master:** estorno de entrega, cancelamento e
     estorno de resgate, e feedback anulado aparecem numa lista com quem fez e
     quando. (O livro de pontos já guarda, mas ninguém olha o livro.)
   - O resto dos "só master" aprovado como proposto.
2. **Tarefas:** criar tarefa nova fica em "editar catálogo". "Desativar" separa em
   dois: **"encerrar atribuição"** (operação do dia, de uma loja) e
   **"desativar tarefa do catálogo"**, que vai junto com "editar catálogo".
   Régua: o que é de catálogo anda com catálogo; o que é do dia, com o dia.
3. **Catálogo da conta: o gerente só mexe em item cujo alcance cabe inteiro
   dentro das lojas dele.** Criar só para as lojas dele: pode. Editar item que
   alcança uma loja fora da lista dele: não pode, nem o título. Item sem alcance
   por loja: só master por ora. Como está hoje:

   | Catálogo | Tem alcance por loja? | Consequência |
   |---|---|---|
   | Tarefas | **Sim** (`tarefaslojas`) | delegável com a régua acima |
   | Comunicados | **Depende do alvo:** "lojas" tem (`documentoslojas`); "pessoas" tem, pelas lojas das pessoas escolhidas; "conta inteira" alcança todas as lojas | delegável quando o alvo é "lojas" ou "pessoas" dentro das lojas dele; "conta inteira" só master |
   | Prêmios | **Não** (o prêmio é da conta) | editar catálogo **só master** por ora |
   | Conquistas | **Não** | editar **só master** por ora |
   | Jornadas | **Não** (a jornada é um modelo da conta, usado por pessoas) | criar e editar o modelo **só master** por ora; ligar uma pessoa das lojas dele a uma jornada que já existe continua sendo "editar pessoa" (a confirmar) |
4. **Equipe: só as pessoas das lojas dele.** Pessoa que trabalha em A e C: o
   gerente de A marca e desmarca só as lojas DELE na lista dela, nunca a C.
   Desativar pessoa (derruba o login) só se TODAS as lojas dela estão dentro das
   dele.
5. **Dois logins, e o vínculo é obrigatório:** quando o usuário gerencial também
   é da equipe, o master aponta qual funcionário ele é, e o banco recusa que ele
   registre, aprove ou estorne a PRÓPRIA entrega.
6. **Fechar as 20 tabelas sem tela e as 3 colunas** (`cpf`, `isgestor`,
   `chatidtelegram`) na primeira entrega.

**As três escolhas confirmadas**, com um acréscimo: a página de Usuários avisa
quando existe permissão nova que nenhum cargo recebeu ("3 permissões novas
aguardando"). Negar em silêncio vira quebra em silêncio.

**O botão "criar usuário gerencial" é a ÚLTIMA chave a ser ligada.** Não existe
meia permissão: uma única leitura sem filtro de loja já mostra ao gerente a loja
que ele não pode abrir.

**Testes exigidos:**
- trava de ESCRITA: toda função que grava e é liberada para quem está logado
  chama `pode(...)` com código do catálogo, ou está numa lista fechada;
- trava de LEITURA: gerente da loja A, com dado em A e B, e nenhuma leitura
  devolve nada de B; e reprova se existir função de leitura de gestão fora da
  lista testada;
- sabotagens, todas reprovando: trava só na tela; gerente editando o próprio
  cargo; gerente agindo na loja B; gerente criando usuário com mais poder; apagar
  o último master; gerente aprovando a própria entrega; gerente editando item de
  catálogo que alcança loja fora da lista dele;
- desempenho: `pode(...)` em toda escrita e a lista de lojas em toda leitura,
  com o índice **provado em uso** (o erro do PIN); toda tela abaixo de 1,5 s;
- sem permissão da tela: o item some do menu, e quem entra pelo endereço
  direto vê uma mensagem clara, nunca tela branca nem erro.

**Anotado ao fechar o papel gerente:** o teste de isolamento já tinha um gerente
de mentira em 6 checagens do tipo "o gerente não mexe em X (só o master)"
(configurações, canal confidencial, desfazer ciência, documentos pessoais, teto
de pontos por ciência). Com o papel fechado, elas passam porque o gerente não tem
acesso a nada, e não mais porque a função confere "é o master?". **Voltam a
valer na etapa dos cargos**, com um gerente de "Acesso total", e entram na lista
das operações que nunca se delegam.

---

## Segunda rodada de decisões e a parte 1 (29/09/2026)

- **Jornada (aprovado):** ligar uma pessoa das lojas dele a uma jornada que já
  existe fica com o gerente (`jornada.vincular`: é editar a pessoa), com as
  bordas da decisão 4. Criar e editar a jornada em si: só master, junto com
  conquistas.
- **`produtosloja` engana no nome.** "Loja" ali é a **loja de recompensas**
  (nome herdado do sistema antigo, `ProdutosLoja`), não uma loja física. O
  prêmio e o estoque dele valem para a conta inteira. Continua só master.
  Conferido no banco: é a **única** tabela com "loja" no nome sem `lojaid`.
  Anotado no dicionário e num comentário na própria tabela.
- **Pela mesma régua (catálogo sem alcance por loja = só master), mais dois
  ficam fora do catálogo:** as etapas do modelo de onboarding
  (`onboardingetapas`) e os tipos de evento da agenda (`tiposevento`). São
  listas da conta, sem loja. "Onboarding: conduzir" e "Agenda: criar e editar"
  continuam delegáveis, sem mexer nessas listas.
- **CPF na Equipe (desvio da decisão 6, explicado):** fechar a coluna `cpf`
  agora quebraria o "Editar" da Equipe, que grava o CPF de quem ainda não tem
  login. O perigo de verdade (trocar o CPF de quem JÁ entra pelo CPF) o banco
  já barra desde 27/09 (`funcionarios_protege_cpf`): só o "Trocar CPF", que é
  só master, passa. Na parte 2 a gravação da Equipe vira função, e o CPF de
  quem já existe fica só com o master.
- **As 8 checagens do gerente de mentira** (eram 8, não 6) estão marcadas como
  PULADAS, com o motivo dentro do teste. Toda rodada mostra "N checagens ok, 8
  PULADAS" e a lista.
- **Fraqueza antiga achada por uma sabotagem:** a checagem "toda policy filtra
  por conta" (seção 14) aceitou uma regra `contaid = minha_conta() OR
  cargoid > 0` — o filtro por conta estava lá, mas o `OR` o anula. Quem pegou
  foi a trava nova. A seção 14 precisa recusar `OR` que anule o filtro
  (proposto para a parte 2).

---

## Auditoria das regras de acesso e ajustes da parte 1 (29/09/2026)

**As regras de hoje, pela checagem endurecida:** 240 regras de acesso
(`public` e `storage`), 287 expressões (USING e WITH CHECK). **287 passam, 0
furadas.** Âncoras: 175 `contaid = minha_conta_editavel()`, 85
`contaid = minha_conta()`, 18 pasta do Storage começando pela conta, 9 admin
geral. A checagem nova (seção 14) parte cada expressão nos termos ligados por
E, recusa OU no nível de cima e exige a âncora exata; foi vista recusando 8
formas furadas (OU no topo, só citar a função, `<>`, NOT, outra coluna, segunda
pasta do Storage, OU só no WITH CHECK, admin OU outra coisa) e aceitando 2
seguras — a checagem antiga aceitaria as 8. Nova trava de comportamento (seção
92): 13 logins × 94 tabelas + Storage, nenhuma linha de outra conta. Limite: o
teste tem dado de mais de uma conta em 33 das 94 tabelas; nas outras, quem
garante é a checagem das regras.

**As sabotagens da parte 1, revistas:** 1, 2, 3 e 5 abriram portas de verdade.
**A 4 ("próprio cargo") NÃO abriu:** o cargo não mudou, e o teste reprovou só
porque esperava um erro. O teste passou a tentar a mudança de verdade (subir de
cargo, ganhar loja e permissão, virar master) e conferir o resultado. Refeita
com a porta aberta de verdade, reprovou pelo resultado. A 4 antiga agora passa,
e deve: não muda nada.

**Histórico:** só o master lê (a regra exige o master, não depende mais de o
gerente estar sem conta). Sobrevive ao apagamento: apagados o cargo, o usuário
gerencial e até o login, as linhas continuam (não há ligação que as apague).
Guarda a linha inteira de ANTES e de DEPOIS (o nome antigo do cargo, qual
permissão foi tirada, que lojas o usuário tinha).

**Último master:** a trava agora cobre também o LOGIN: apagar ou bloquear
("Ban user" no Supabase) o login do último master ATIVO é recusado, e um
segundo master com login bloqueado não conta como outro master.

**Achado, para decisão (não mexido):** 48 colunas "quem fez" (aprovou,
estornou, registrou, cancelou, lançou…) apontam para o login com "SET NULL":
se um login for apagado no Supabase, essas colunas viram vazio e o "quem fez"
some das entregas, resgates, feedbacks, metas, agenda, livro de pontos. Hoje o
sistema nunca apaga login de gestor; só o painel do Supabase faria. (No livro
de pontos o apagamento já é barrado, por acaso: o livro não aceita alteração.)
Proposta: login que já fez algo nunca se apaga, só se desativa — com a trava no
banco, como a do último master.

---

## Três pedidos antes da parte 2 (29/09/2026)

**1. As 61 tabelas cegas:** a seção 92 agora dá a TODA tabela com conta dados
de pelo menos duas contas (copia uma linha existente para a outra conta, ou
monta uma linha mínima coluna por coluna, respeitando as listas de valores), e
desfaz tudo no fim. **94 de 94 cobertas.** Tabela nova que o gerador não
conseguir preencher reprova com o nome e o motivo. Provado: um vazamento em
`fornecedores` (antes vazia no teste), com a checagem de texto desligada, foi
pego por 13 logins.

**2. Negações pelo resultado:** antes, **386** testes de negação provavam só
com "deu erro" (382 sozinhos + 4 "deu erro E o saldo não mudou"). Depois, **0**:
347 conferem que o banco inteiro não mudou e 39 que nada voltou. Nenhum passou a
reprovar (nenhuma porta nova). Provado: sem a trava do CPF, o teste convertido
reprovou; com a foto cega, passou (e o seguinte pegou) — é a foto que decide.
Catraca `src/ui/negacao-catraca.test.ts`, também provada reprovando. Os 27
`toThrow` dos testes das telas são de funções puras (validar senha, foto): lá a
recusa É o resultado, não há estado.

**3. Login que já fez alguma coisa não se apaga, só se desativa (aprovado).**
Condições decididas, para construir no começo da parte 2:
- (a) o histórico guarda o NOME de quem fez no momento, não só o apontamento;
- (b) **exclusão de dados (LGPD), em duas linhas:**
  1. o pedido é atendido por uma função do admin que APAGA os dados pessoais
     (nome, e-mail, CPF, telefone) do cadastro e do login, bloqueia o login e
     troca o nome guardado nos registros por "pessoa removida";
  2. os ATOS continuam (o que foi feito, quando, quantos pontos), presos a um
     identificador sem dado pessoal — a trava impede apagar o ato, nunca
     impede atender o pedido.
