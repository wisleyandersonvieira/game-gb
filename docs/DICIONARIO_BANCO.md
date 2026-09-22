# Dicionário do Banco — Game GB (Supabase)

> Estrutura extraída do backup `banco_teste.bak`. **Banco limpo: nenhum dado foi importado.** Nomes no Postgres = nomes originais em **minúsculas** (ex.: `FuncionarioID` → `funcionarioid`). IDs começam do 1.

## Modelo multi-empresa (Fase 2)
**Toda** tabela desta página tem, além das colunas listadas:

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | obrigatório; padrão `minha_conta()`; → `contas.contaid`. O front-end nunca informa. |
| lojaid | integer | obrigatório **só nas tabelas de nível loja**; → `lojas`, amarrado ao mesmo `contaid` |

**Nível conta** = compartilhado entre as lojas do cliente. **Nível loja** = cada loja tem os seus.

As chaves estrangeiras entre tabelas são **compostas com o `contaid`**: as duas pontas leem o mesmo `contaid` da mesma linha, então é impossível apontar para o registro de outra conta. Toda unicidade é por conta ou por loja — nunca global, com uma exceção: `grupos.chatidtelegram`, único no sistema inteiro porque um único bot do Telegram atende todas as contas (Fase 15).

| Tabela | Nível | Chave | Referencia |
|---|---|---|---|
| `agendamentos` | **loja** | agendamentoid | funcionarios, tiposevento |
| `agendamentosanexos` | **loja** | anexoid | agendamentos |
| `agendamentoshistorico` | **loja** | historicoid | agendamentos |
| `categoriasproduto` | conta | categoriaid |  |
| `configuracoesescala` | **loja** | configid |  |
| `configuracoessetores` | conta | setor |  |
| `configuracoes` | conta | (contaid, chave) |  |
| `configuracoeshistorico` | conta | historicoid | configuracoes |
| `conquistas` | conta | conquistaid |  |
| `conquistasfuncionarios` | conta | conquistafuncionarioid | conquistas, funcionarios |
| `contagensestoque` | **loja** | contagemid | funcionarios |
| `denunciasanonimas` | conta | denunciaid |  |
| `documentos` | conta | documentoid | funcionarios |
| `documentosacessos` | conta | acessoid | documentospessoais |
| `documentoslojas` | **loja** | (documentoid, lojaid) | documentos, lojas |
| `documentosassinaturas` | conta | assinaturaid | documentos, funcionarios |
| `documentospessoais` | conta | documentoid | funcionarios |
| `documentospessoaisciencia` | conta | cienciaid | documentospessoais, funcionarios |
| `entregas` | **loja** | entregaid | funcionarios, tarefas |
| `escaladiaria` | **loja** | escalaid | freelancers, funcionarios, posicoesloja |
| `feedbacksolicitacoes` | conta | solicitacaoid | funcionarios |
| `feedbacks` | conta | feedbackid | funcionarios |
| `fornecedores` | conta | fornecedorid |  |
| `freelancers` | conta | freelancerid |  |
| `funcionarios` | conta | funcionarioid | posicoesloja |
| `funcionariosgrupos` | **loja** | funcionarioid + grupoid | funcionarios, grupos |
| `grupos` | **loja** | grupoid |  |
| `historicoranking` | **loja** | historicoid | funcionarios |
| `itenscontagemestoque` | **loja** | itemcontagemid | contagensestoque, produtosestoque |
| `itensnotafiscalentrada` | **loja** | itemnotaid | notasfiscaisentrada, produtosfornecedor |
| `justificativas` | **loja** | justificativaid | tarefasatribuidas, funcionarios |
| `lucromensalhistorico` | **loja** | historicoid |  |
| `metasdiariasapuracoes` | **loja** | apuracaoid | funcionarios, metasprincipais |
| `metasdiariasinstancias` | **loja** | metainstanciaid |  |
| `metasdiariasmodelos` | **loja** | diasemanaid |  |
| `metasespeciais` | **loja** | metaespecialid |  |
| `metashistorico` | **loja** | historicoid | metasdiariasapuracoes |
| `metaspremiacoes` | **loja** | premiacaoid | metasdiariasapuracoes, metasprincipais |
| `metasprincipais` | **loja** | metaprincipalid |  |
| `notasfiscais` | **loja** | notafiscalid | funcionarios |
| `notasfiscaisentrada` | **loja** | notaid | fornecedores |
| `onboardingetapas` | conta | etapaid |  |
| `onboardingitens` | conta | itemid | onboardingstatus, onboardingetapas, documentospessoais |
| `onboardingstatus` | conta | funcionarioid | funcionarios |
| `picodiario` | **loja** | diasemanaid |  |
| `posicoesloja` | **loja** | posicaoid |  |
| `produtosestoque` | conta | produtoid |  |
| `produtosfornecedor` | conta | produtofornecedorid | fornecedores, produtosestoque |
| `produtosloja` | conta | produtoid |  |
| `resgates` | conta | resgateid | funcionarios, produtosloja |
| `solicitacoeshistorico` | **loja** | historicoid | solicitacoesinternas |
| `solicitacoesinternas` | **loja** | solicitacaoid | funcionarios |
| `tarefas` | conta | tarefaid |  |
| `tiposevento` | conta | tipoeventoid |  |
| `tarefasatribuidas` | **loja** | atribuicaoid | funcionarios, grupos, tarefas, tarefasatribuidas |

## agendamentos
| Coluna | Tipo | Obs |
|---|---|---|
| agendamentoid | integer | ID automático; obrigatório |
| nomecliente | varchar(200) | obrigatório |
| cpfcliente | varchar(20) |  |
| telefonecliente | varchar(50) |  |
| tipoevento | varchar(100) | obrigatório |
| dataevento | timestamptz | obrigatório |
| statusagendamento | varchar(50) | obrigatório; padrão 'Confirmado' |
| statuspagamento | varchar(50) | obrigatório; padrão 'Pendente' |
| funcionarioid | integer | obrigatório; **o responsável**. → funcionarioslojas (junto com lojaid): tem de trabalhar na loja |
| observacoes | text |  |
| datacriacao | timestamptz | obrigatório; padrão now() |
| msgcriacaoenviada | timestamptz | quando a confirmação por WhatsApp foi enviada (Etapa 1.13) |
| msgconfirmacaoenviada | timestamptz | quando o lembrete da véspera foi enviado (1.13) |
| msgposvendaenviada | timestamptz | quando o pós-venda foi enviado (1.13) |
| tipoeventoid | integer | → tiposevento (junto com contaid). `tipoevento` guarda o nome |
| valor | numeric(12,2) | valor combinado, opcional |
| aceitawhatsapp | boolean | obrigatório; padrão false. Consentimento do cliente para mensagens |
| registradopor | uuid | quem cadastrou |
| atualizadoem | timestamptz | obrigatório; padrão now() |
| realizadoem / realizadopor | timestamptz / uuid | ao marcar Realizado |
| canceladoem / canceladopor / motivocancelamento | timestamptz / uuid / text | ao cancelar (motivo obrigatório) |

`statusagendamento`: `Confirmado`, `Realizado` ou `Cancelado` (Confirmado → Realizado/Cancelado; Realizado → Confirmado; Cancelado é final). `statuspagamento`: `Pendente`, `Sinal pago` ou `Pago`. CPF só com 11 números. **Nada se apaga.** Entra e muda só pelas funções da agenda. A tarefa gerada fica em `tarefasatribuidas.agendamentoid`.

## tiposevento
Tabela **nova** (Etapa 1.9), **nível conta**. Tipos de evento da agenda, editáveis pelo cliente. Conta nova começa só com "Evento".

| Coluna | Tipo | Obs |
|---|---|---|
| tipoeventoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| nome | varchar(100) | obrigatório; único na conta (sem diferenciar maiúsculas) |
| ativo | boolean | obrigatório; padrão true. Desativado sai da lista de novos agendamentos |
| criadoem | timestamptz | obrigatório; padrão now() |

## agendamentoshistorico
Tabela **nova** (Etapa 1.9), **nível loja**. Cada mudança de um agendamento. **Nunca muda nem se apaga.**

| Coluna | Tipo | Obs |
|---|---|---|
| historicoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| agendamentoid | integer | obrigatório; → agendamentos (junto com contaid) |
| acao | varchar(20) | `criado`, `editado`, `remarcado`, `responsavel`, `pagamento`, `realizado`, `reaberto`, `cancelado`, `anexo`, `anexo_removido` |
| valoranterior / valornovo | text | ex.: data antiga e nova. A edição não copia CPF nem telefone |
| motivo | text | obrigatório em cancelar e reabrir |
| alteradopor / alteradoem | uuid / timestamptz | quem e quando |

## agendamentosanexos
Tabela **nova** (Etapa 1.9), **nível loja**. Arquivos do bucket privado `agendamentos`, pasta `<contaid>/<lojaid>/<agendamentoid>/`.

| Coluna | Tipo | Obs |
|---|---|---|
| anexoid | integer | ID automático; chave primária |
| contaid / lojaid / agendamentoid | integer | obrigatórios; → agendamentos (junto com contaid) |
| caminho | text | obrigatório; único |
| nomearquivo | varchar(200) | obrigatório |
| tipoarquivo | varchar(50) | `application/pdf`, `image/jpeg` ou `image/png` |
| tamanho | integer | até 10 MB |
| enviadopor / enviadoem | uuid / timestamptz | |
| removidoem / removidopor | timestamptz / uuid | ao remover (o arquivo sai do Storage) |

## categoriasproduto
| Coluna | Tipo | Obs |
|---|---|---|
| categoriaid | integer | ID automático; obrigatório |
| nomecategoria | varchar(100) | obrigatório |

## configuracoesescala
| Coluna | Tipo | Obs |
|---|---|---|
| configid | integer | ID automático; obrigatório |
| maxhorassempausa | integer | obrigatório |
| duracaointervalo | integer | obrigatório |
| dataatualizacao | timestamptz | padrão now() |
| duracaojornadapadrao | numeric(10,2) |  |

## configuracoessetores
| Coluna | Tipo | Obs |
|---|---|---|
| setor | varchar(50) | obrigatório; chave primária **(contaid, setor)** |
| descricaopadrao | text |  |

## conquistas
| Coluna | Tipo | Obs |
|---|---|---|
| conquistaid | integer | ID automático; obrigatório |
| nome | varchar(100) | obrigatório |
| descricao | varchar(255) | obrigatório |
| icone | varchar(10) |  |
| criteriotipo | varchar(50) | obrigatório |
| criteriovalor | integer | obrigatório; maior que zero |
| pontosbonus | integer | padrão 0; 0 ou mais |
| criteriodias | integer | o X de "N tarefas em X dias" (1 a 366); só nesse tipo, e obrigatório nele |
| ativa | boolean | obrigatório; padrão true |
| contardesde | timestamptz | vazio = vale para o histórico; preenchido = "só a partir de hoje" (só contam tarefas enviadas depois) |
| criadoem | timestamptz | obrigatório; padrão now() |

`criteriotipo`: `total_tarefas_aprovadas`, `tarefas_aprovadas_periodo`, `sequencia_dias_tarefas` (já valem) e `sequencia_feedback_diario`, `total_comunicados_cientes`, `tarefas_grupo_competitivo_aceitas` (cadastráveis; valem quando os módulos existirem). **A regra (tipo, valor, dias, contardesde) não muda depois de criada** — o banco recusa, até para o dono. Criação só por `criar_conquista`; o navegador altera só nome, descrição, ícone, bônus e ativa.

## conquistasfuncionarios
| Coluna | Tipo | Obs |
|---|---|---|
| conquistafuncionarioid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| conquistaid | integer | obrigatório; → conquistas.conquistaid |
| dataconquista | timestamptz | padrão now() |
| pontosbonus | integer | obrigatório; padrão 0. O bônus pago na concessão (mudar o bônus da conquista depois não muda este) |

**Única (funcionarioid, conquistaid)**: cada pessoa ganha cada conquista uma vez só. O navegador só lê; quem grava é o banco, na aprovação.

## contagensestoque
| Coluna | Tipo | Obs |
|---|---|---|
| contagemid | integer | ID automático; obrigatório |
| datacontagem | date | obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| dataregistro | timestamptz | padrão now() |
| nomecontagem | varchar(100) | padrão 'Geral' |

## denunciasanonimas
| Coluna | Tipo | Obs |
|---|---|---|
| denunciaid | integer | ID automático; obrigatório |
| mensagem | text | obrigatório; 1 a 4.000 caracteres |
| dataregistro | **date** | obrigatório; padrão hoje (São Paulo). **Só o dia, sem hora** |
| status | varchar(50) | obrigatório; `Nova`, `Em análise` ou `Tratada` |
| protocolohash | char(64) | único. Impressão digital (sha256) do protocolo; o protocolo em si só quem enviou recebe |
| resposta | text | resposta do master (quem enviou lê pelo protocolo) |
| respondidoem | date | dia da resposta |
| tratadopor | uuid | o master que tratou (nunca quem enviou) |
| tratadoem | timestamptz | quando foi tratado |

**Canal confidencial (anonimato real).** Nível conta, **sem loja**. Nenhuma coluna aponta para quem enviou. **Só o master lê** (policy `contaid = minha_conta() AND sou_master()`); gerente e qualquer papel futuro não. Ninguém grava pelo navegador: a entrada é `registrar_relato`, só do servidor. Texto, dia e protocolo nunca mudam; nada se apaga. O teste de isolamento confere a lista exata de colunas, gatilhos, chaves e funções que tocam esta tabela.

## documentos
Os **comunicados** (Etapa 1.10). Nível conta.

| Coluna | Tipo | Obs |
|---|---|---|
| documentoid | integer | ID automático; obrigatório |
| titulo | varchar(255) | obrigatório |
| conteudo | text | obrigatório |
| pontosporciencia | integer | obrigatório; 0 a 10.000. Padrão sugerido: os pontos da tarefa do sistema "Leitura de comunicado" |
| datacriacao | timestamptz | quando foi publicado |
| funcionariocriadorid | integer | sem uso (quem publicou está em `criadopor`) |
| telegramfileidfoto | varchar(255) | sem uso (imagem via Telegram, Etapa 1.13) |
| status | varchar(10) | obrigatório; `Publicado` ou `Arquivado` (final) |
| alvo | varchar(12) | obrigatório; `conta`, `lojas` (ver `documentoslojas`) ou `funcionarios` |
| criadopor | uuid | quem publicou |
| atualizadoem | timestamptz | |
| primeiracienciaem | timestamptz | preenchido na primeira ciência: a partir daí **título, texto e pontos travam** (gatilho) |
| arquivadoem / arquivadopor | timestamptz / uuid | |

Nunca se apaga. Entra e muda só pelas funções (`publicar_comunicado`, `editar_comunicado`, `arquivar_comunicado`). Arquivado não aceita ciência nova nem destinatário novo, e guarda o histórico e os recibos.

## documentoslojas
Tabela **nova** (Etapa 1.10), **nível loja**. As lojas escolhidas quando o alvo do comunicado é `lojas`. Chave (documentoid, lojaid); FKs compostas com documentos e lojas. O navegador só lê.

## documentosassinaturas
As **ciências** dos comunicados (um destinatário por linha). Nível conta.

| Coluna | Tipo | Obs |
|---|---|---|
| assinaturaid | integer | ID automático; obrigatório |
| documentoid | integer | obrigatório; → documentos (junto com contaid) |
| funcionarioid | integer | obrigatório; → funcionarios (junto com contaid) |
| statusassinatura | varchar(50) | obrigatório; `Pendente` ou `Ciente` |
| dataenvio | timestamptz | quando entrou como destinatário |
| dataciencia | timestamptz | data e hora da ciência |
| origem | varchar(12) | `gestor` (hoje) ou `funcionario` (portal/bot no futuro) |
| registradopor | uuid | quem registrou |
| pontospagos | integer | obrigatório; pontos pagos pela ciência que vale |
| desfeitaem / desfeitapor / motivodesfazer | timestamptz / uuid / text | última vez que a ciência foi desfeita (só o master) |

**Única (documentoid, funcionarioid).** Só funcionário ativo da mesma conta entra. Ciência por `registrar_ciencia` (atômica: trava a linha, paga pelo livro uma vez; segundo clique não faz nada). Desfazer por `desfazer_ciencia` (estorno pelo livro). Não muda de comunicado nem de pessoa; não se apaga.

## documentospessoais
Holerites, recibos, contratos, atestados etc. Nível conta (é da pessoa). **Só o master lê.**

| Coluna | Tipo | Obs |
|---|---|---|
| documentoid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios (junto com contaid) |
| tipodocumento | varchar(100) | obrigatório; `Holerite`, `Recibo`, `Contrato`, `Atestado`, `Advertência`, `Cartão de ponto`, `Documento de admissão` ou `Outro` |
| mesano | date | referência (mês), opcional |
| caminhoarquivo | varchar(500) | obrigatório; único. `<contaid>/funcionarios/<funcionarioid>/<arquivo>` no bucket privado `documentos-rh` |
| dataupload | timestamptz | quando foi enviado |
| descricao | varchar(200) | |
| nomearquivo / tipoarquivo / tamanho | | nome original; `application/pdf`, `image/jpeg` ou `image/png`; até 10 MB |
| enviadopor | uuid | |
| situacao | varchar(12) | obrigatório; `Ativo`, `Substituido`, `Arquivado` ou `Excluido` |
| substituidopor / substituidoem | integer / timestamptz | a nova versão (→ documentospessoais) |
| arquivadoem / arquivadopor | | |
| excluidoem / excluidopor / motivoexclusao | | exclusão "por engano" |

**Nunca se apaga.** Excluir "por engano" só sem ciência e até 7 dias do envio (o arquivo sai do Storage; o registro fica). Fora disso: nova versão (a anterior fica guardada como substituída e acessível) ou arquivar (sai das listas). Pessoa desativada: os documentos continuam guardados. Entra e muda só pelas funções.

## documentospessoaisciencia
Ciência de recebimento de um documento pessoal. **Única por documento.** Só o master lê.

| Coluna | Tipo | Obs |
|---|---|---|
| cienciaid | integer | ID automático |
| documentoid | integer | obrigatório; → documentospessoais |
| funcionarioid | integer | obrigatório |
| status | varchar(50) | `Pendente` ou `Ciente` |
| dataenvio / dataciencia | timestamptz | |
| origem | varchar(12) | `gestor` ou `funcionario` (futuro) |
| registradopor | uuid | |

## documentosacessos
Tabela **nova** (Etapa 1.10). Registro de acesso aos documentos pessoais (LGPD): cada envio, cada link gerado e cada exclusão. **Só o master lê; nunca muda nem se apaga.**

| Coluna | Tipo | Obs |
|---|---|---|
| acessoid | integer | ID automático |
| contaid | integer | obrigatório |
| documentoid | integer | → documentospessoais (vazio no envio, antes de registrar) |
| caminho | text | obrigatório |
| acao | varchar(12) | `envio`, `visualizacao` ou `exclusao` |
| usuario | uuid | quem |
| acessadoem | timestamptz | quando |

O Storage `documentos-rh` só deixa ler, enviar ou apagar um arquivo se houver um registro desses, do mesmo usuário, há menos de 2 minutos (função `documento_rh_liberado`). Assim ninguém abre um documento sem deixar rastro.

## entregas
| Coluna | Tipo | Obs |
|---|---|---|
| entregaid | integer | ID automático; obrigatório |
| tarefaid | integer | obrigatório; → tarefas.tarefaid |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| dataenvio | timestamptz | padrão now() |
| pathfotoevidencia | varchar(255) |  |
| statusvalidacao | varchar(50) | padrão 'Pendente' |
| pontosganhos | integer | padrão 0 |
| motivorecusa | text |  |
| atribuicaoid | integer |  |
| fileidtelegram | varchar(255) |  |
| notificacaogestorenviada | boolean | padrão false |
| observacao | text | Observação de quem registrou a entrega |
| dataaprovacao | timestamptz | Quando foi aprovada. **O ranking usa esta data.** `dataenvio` guarda sempre o envio real |
| aprovadopor | uuid | → auth.users. Quem aprovou |
| datarecusa | timestamptz |  |
| recusadopor | uuid | → auth.users |
| dataestorno | timestamptz |  |
| estornadopor | uuid | → auth.users |
| motivoestorno | text | Obrigatório quando o status é Estornada |

**Regras de `entregas`:** `statusvalidacao` é `Pendente`, `Aprovada`, `Recusada` ou `Estornada`. Recusada exige `motivorecusa` e Estornada exige `motivoestorno` (o banco recusa sem). No máximo uma entrega Pendente ou Aprovada por atribuição por dia, no fuso de São Paulo. A entrega aponta para a sua atribuição e tem de concordar com ela em tarefa, pessoa e loja. **O navegador não grava nesta tabela:** tudo passa por `registrar_entrega`, `aprovar_entrega`, `recusar_entrega` e `estornar_entrega`.

## escaladiaria
| Coluna | Tipo | Obs |
|---|---|---|
| escalaid | integer | ID automático; obrigatório |
| dataescala | date | obrigatório |
| posicaoid | integer | obrigatório; → posicoesloja.posicaoid |
| funcionarioid | integer | → funcionarios.funcionarioid |
| freelancerid | integer | → freelancers.freelancerid |
| horarioentrada | time |  |
| horariosaida | time |  |
| iniciointervalo | time |  |
| fimintervalo | time |  |
| focododia | text |  |
| statusconfirmacao | varchar(20) | padrão 'Pendente' |

## feedbacksolicitacoes
| Coluna | Tipo | Obs |
|---|---|---|
| solicitacaoid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| datasolicitacao | timestamptz | obrigatório; padrão now() |
| textoassunto | text | obrigatório |
| status | varchar(50) | obrigatório; padrão 'Pendente' |
| dataresposta | timestamptz |  |
| textoresposta | text |  |

## feedbacks
| Coluna | Tipo | Obs |
|---|---|---|
| feedbackid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| datafeedback | date | obrigatório |
| notadia | integer | obrigatório; 0 a 10 |
| comentario | varchar(500) |  |
| origem | varchar(10) | obrigatório; `gestor` (registrado pelo gestor) ou `bot` |
| registradopor | uuid | → auth.users |
| criadoem | timestamptz | obrigatório; padrão now() |
| pontosbonus | integer | obrigatório; o bônus pago (vem de `PONTOS_BONUS_FEEDBACK_DIARIO`) |
| anuladoem | timestamptz | preenchido ao anular |
| anuladopor | uuid | → auth.users |
| motivoanulacao | text | obrigatório ao anular |

**Único (funcionarioid, datafeedback)** entre os não anulados. Entra só por `registrar_feedback` (hoje ou ontem); a nota não se altera nem se apaga — corrige-se anulando com motivo (`anular_feedback`), que estorna o bônus pelo livro.

## fornecedores
| Coluna | Tipo | Obs |
|---|---|---|
| fornecedorid | integer | ID automático; obrigatório |
| cnpj | varchar(18) | obrigatório |
| nomefantasia | varchar(255) | obrigatório |

## freelancers
| Coluna | Tipo | Obs |
|---|---|---|
| freelancerid | integer | ID automático; obrigatório |
| nome | varchar(100) | obrigatório |
| telefone | varchar(20) |  |
| habilidadeprincipal | varchar(100) |  |

## funcionarios
| Coluna | Tipo | Obs |
|---|---|---|
| funcionarioid | integer | ID automático; obrigatório |
| nomecompleto | varchar(255) | obrigatório |
| chatidtelegram | varchar(100) |  |
| cargo | varchar(100) |  |
| pontostotal | integer | padrão 0. Tudo o que a pessoa já ganhou (aprovações, bônus, estornos de entrega; resgates não contam). Só o gatilho do livro altera |
| horarionotificacao | time | padrão '08:00' |
| diadefolga | integer | obrigatório; padrão 0 |
| saldopontos | integer | obrigatório; padrão 0. O que a pessoa tem para gastar. **Sempre a soma de `movimentospontos`**; só o gatilho do livro altera. Pode ficar negativo por estorno de entrega, nunca por resgate |
| verificadorcpf | varchar(3) |  |
| senhahash | varchar(256) |  |
| isgestor | boolean | padrão false |
| ~~posicaopadraoid~~ | — | removida na Fase 2: o lugar padrão passou a ser por loja, em `funcionarioslojas` |
| nivelacesso | varchar(50) | padrão 'Funcionario' |
| cpf | varchar(14) |  |
| telefonewhatsapp | varchar(20) |  |
| setor | varchar(50) |  |
| domingofolgamensal | integer | padrão 0 |
| datainicioafastamento | date |  |
| datafimafastamento | date |  |
| ativo | boolean | obrigatório; padrão true. Acrescentada em 21/09/2026: `false` = desligado definitivamente. As datas de afastamento valem só para afastamento temporário. |

## funcionariosgrupos
| Coluna | Tipo | Obs |
|---|---|---|
| funcionarioid | integer | obrigatório; chave primária composta; → funcionarios.funcionarioid |
| grupoid | integer | obrigatório; chave primária composta; → grupos.grupoid |

## grupos
| Coluna | Tipo | Obs |
|---|---|---|
| grupoid | integer | ID automático; obrigatório |
| nomegrupo | varchar(100) | obrigatório |
| chatidtelegram | varchar(50) |  |

## historicoranking
| Coluna | Tipo | Obs |
|---|---|---|
| historicoid | integer | ID automático; obrigatório |
| ano | integer | obrigatório |
| mes | integer | obrigatório |
| posicao | integer | obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| nomefuncionario | varchar(255) | obrigatório |
| pontosganhos | integer | obrigatório |
| pontospossiveis | integer | obrigatório |
| percentualdesempenho | numeric(5,2) | obrigatório |

## itenscontagemestoque
| Coluna | Tipo | Obs |
|---|---|---|
| itemcontagemid | integer | ID automático; obrigatório |
| contagemid | integer | obrigatório; → contagensestoque.contagemid |
| produtoid | integer | → produtosestoque.produtoid |
| quantidadecontada | numeric(10,3) | obrigatório |
| nomeavulso | varchar(255) |  |
| eanavulso | varchar(50) |  |

## itensnotafiscalentrada
| Coluna | Tipo | Obs |
|---|---|---|
| itemnotaid | integer | ID automático; obrigatório |
| notaid | integer | obrigatório; → notasfiscaisentrada.notaid |
| produtofornecedorid | integer | obrigatório; → produtosfornecedor.produtofornecedorid |
| quantidade | numeric(10,3) | obrigatório |
| precocustounitario | numeric(10,4) | obrigatório |

## lucromensalhistorico
| Coluna | Tipo | Obs |
|---|---|---|
| historicoid | integer | ID automático; obrigatório |
| ano | integer | obrigatório |
| mes | integer | obrigatório |
| percentuallucro | numeric(5,2) | obrigatório |
| dataregistro | timestamptz | padrão now() |

## metasdiariasapuracoes
| Coluna | Tipo | Obs |
|---|---|---|
| apuracaoid | integer | ID automático; obrigatório |
| metaprincipalid | integer | → metasprincipais.metaprincipalid |
| dataapuracao | date | obrigatório |
| valordia | numeric(18,2) | obrigatório |
| funcionarioid_lancamento | integer | → funcionarios.funcionarioid. Sem uso (o antigo gravava sempre o nº 2); quem lançou está em `lancadopor` |
| pontosmetadiariaganhos | integer | padrão 0. Sem uso; os prêmios estão em `metaspremiacoes` |
| valormetadia | numeric(18,2) | a meta daquele dia, **guardada no primeiro lançamento** (especial ou modelo) |
| pontosmetadia | integer | obrigatório; os pontos daquela meta, guardados junto |
| origemmeta | varchar(10) | `especial` ou `semana` |
| descricaometa | text | nome da meta especial ou do dia da semana |
| lancadopor / lancadoem | uuid / timestamptz | quem e quando lançou |
| atualizadopor / atualizadoem | uuid / timestamptz | última correção |

**Um por loja por dia** (`UNIQUE (lojaid, dataapuracao)`). O valor é o total do dia (substitui). Entra e muda só por `lancar_venda_do_dia`: hoje ou dias passados, só do mês atual e do anterior; correção exige motivo; nada se apaga. `metaprincipalid` liga o dia à meta do mês, quando existe.

## metasdiariasinstancias
| Coluna | Tipo | Obs |
|---|---|---|
| metainstanciaid | integer | ID automático; obrigatório |
| metamodeloid | integer |  |
| data | date | obrigatório |
| valormeta | numeric(10,2) | obrigatório |
| valoratingido | numeric(10,2) |  |
| status | varchar(20) | padrão 'Pendente' |

**Sem uso** (o sistema antigo também nunca gravou nela). Fica sem tela.

## metasdiariasmodelos
| Coluna | Tipo | Obs |
|---|---|---|
| diasemanaid | integer | obrigatório; chave primária **(lojaid, diasemanaid)** |
| nomedia | varchar(50) | obrigatório |
| valormeta | numeric(18,2) | obrigatório; 0 ou mais (0 = sem meta nesse dia) |
| pontospremio | integer | obrigatório; 0 a 10.000 |

`diasemanaid` 1 = domingo … 7 = sábado. Único por loja (a trava antiga era por conta e impedia duas lojas de terem meta no mesmo dia da semana). O navegador grava direto (RLS da conta).

## metasespeciais
Tabela **nova** (Etapa 1.8), **nível loja**. Meta de uma data específica (feriado, data comemorativa), que substitui o modelo do dia da semana naquela data.

| Coluna | Tipo | Obs |
|---|---|---|
| metaespecialid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| data | date | obrigatório; **única por loja** |
| descricao | varchar(100) | obrigatório (ex.: "Dia das Mães") |
| valormeta | numeric(18,2) | obrigatório; 0 ou mais |
| pontospremio | integer | obrigatório; 0 a 10.000 |
| criadoem | timestamptz | obrigatório; padrão now() |

## metashistorico
Tabela **nova** (Etapa 1.8), **nível loja**. Cada lançamento e correção de venda. **Nunca muda nem se apaga**, nem para o dono.

| Coluna | Tipo | Obs |
|---|---|---|
| historicoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| apuracaoid | integer | obrigatório; → metasdiariasapuracoes (junto com contaid) |
| dataapuracao | date | obrigatório; o dia da venda |
| valoranterior | numeric(18,2) | vazio no primeiro lançamento |
| valornovo | numeric(18,2) | obrigatório |
| motivo | text | obrigatório nas correções |
| alteradopor / alteradoem | uuid / timestamptz | quem e quando |

## metaspremiacoes
Tabela **nova** (Etapa 1.8), **nível loja**. Cada prêmio de meta pago. Quem recebeu está no livro (`movimentospontos.premiacaoid`).

| Coluna | Tipo | Obs |
|---|---|---|
| premiacaoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| tipo | varchar(3) | `dia` ou `mes` |
| apuracaoid | integer | no prêmio do dia; → metasdiariasapuracoes |
| metaprincipalid | integer | no prêmio do mês; → metasprincipais |
| pontos | integer | obrigatório; por pessoa |
| pagoem | timestamptz | obrigatório; padrão now() |
| estornadoem | timestamptz | preenchido quando a correção faz a meta deixar de bater |

**No máximo um prêmio valendo** (sem estorno) por lançamento do dia e por meta do mês: índices únicos parciais. O navegador só lê.

## metasprincipais
| Coluna | Tipo | Obs |
|---|---|---|
| metaprincipalid | integer | ID automático; obrigatório |
| nomemeta | varchar(200) | obrigatório |
| descricao | text |  |
| valormetatotal | numeric(18,2) | obrigatório |
| datainicio | date | obrigatório |
| datafim | date | obrigatório |
| pontospremio | integer | obrigatório |
| setoralvo | varchar(100) | Sem uso: quem ganha segue a regra da loja, não o texto do cargo |
| status | varchar(50) | padrão 'Ativa' |
| criadopor | uuid | → auth.users |
| atualizadoem | timestamptz | obrigatório; padrão now() |

**A meta do mês**: uma por loja por mês do calendário (`datainicio` = dia 1, `datafim` = último dia; `UNIQUE (lojaid, datainicio)`). Valor > 0; pontos 0 a 100.000 (0 = sem prêmio). Entra e muda só por `salvar_meta_do_mes` (do mês anterior em diante).

## notasfiscais
| Coluna | Tipo | Obs |
|---|---|---|
| notafiscalid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| fileidtelegram | varchar(255) | obrigatório |
| pathfoto | varchar(512) |  |
| status | varchar(50) | padrão 'Pendente' |
| datarecebimento | timestamptz | padrão now() |

## notasfiscaisentrada
| Coluna | Tipo | Obs |
|---|---|---|
| notaid | integer | ID automático; obrigatório |
| numeronf | varchar(50) | obrigatório |
| fornecedorid | integer | obrigatório; → fornecedores.fornecedorid |
| dataemissao | date | obrigatório |
| valortotalnf | numeric(10,2) | obrigatório |
| dataimportacao | timestamptz | padrão now() |

## onboardingstatus
Resumo do onboarding de cada pessoa. Nível conta; uma linha por funcionário.

| Coluna | Tipo | Obs |
|---|---|---|
| funcionarioid | integer | obrigatório; chave primária; → funcionarios (junto com contaid) |
| statusworkflow | varchar(50) | obrigatório; `Em andamento` ou `Concluído` |
| iniciadoem / iniciadopor | timestamptz / uuid | |
| concluidoem | timestamptz | quando todas as etapas foram feitas |

As colunas de dados pessoais do questionário antigo (escolaridade, estado civil, cônjuge, filhos, arquivos do Telegram, admissional) foram **removidas** na Etapa 1.10 (LGPD). O navegador só lê.

## onboardingetapas
Tabela **nova** (Etapa 1.10), **nível conta**. As etapas do checklist da conta. Conta nova começa com: Documentos pessoais recebidos, Exame admissional, Contrato assinado, Cadastro no sistema, Treinamento inicial, Apresentação à equipe.

| Coluna | Tipo | Obs |
|---|---|---|
| etapaid | integer | ID automático |
| contaid | integer | obrigatório |
| nome | varchar(120) | obrigatório; único na conta |
| ordem | integer | obrigatório |
| ativo | boolean | obrigatório; padrão true. **Desativar, nunca apagar** (os itens já marcados ficam) |
| criadoem | timestamptz | |

## onboardingitens
Tabela **nova** (Etapa 1.10), **nível conta**. O checklist de cada pessoa. **Único (funcionarioid, etapaid).**

| Coluna | Tipo | Obs |
|---|---|---|
| itemid | integer | ID automático |
| contaid / funcionarioid / etapaid | integer | → onboardingstatus e onboardingetapas (junto com contaid) |
| concluidoem / concluidopor | timestamptz / uuid | |
| observacao | text | |
| documentoid | integer | documento pessoal ligado à etapa (da mesma pessoa) |
| criadoem | timestamptz | |

## picodiario
| Coluna | Tipo | Obs |
|---|---|---|
| diasemanaid | integer | obrigatório; chave primária **(lojaid, diasemanaid)** |
| nomedia | varchar(20) | obrigatório |
| horabloqueioinicio | time |  |
| horabloqueiofim | time |  |

## posicoesloja
| Coluna | Tipo | Obs |
|---|---|---|
| posicaoid | integer | ID automático; obrigatório |
| nomeposicao | varchar(100) | obrigatório |
| coordx | double precision | obrigatório |
| coordy | double precision | obrigatório |
| ativo | boolean | padrão true |
| setor | varchar(50) |  |

## produtosestoque
| Coluna | Tipo | Obs |
|---|---|---|
| produtoid | integer | ID automático; obrigatório |
| nomeproduto | varchar(255) | obrigatório |
| unidademedida | varchar(10) | obrigatório |
| estoqueminimo | numeric(10,3) | padrão 0 |
| categoria | varchar(100) | padrão 'Geral' |

## produtosfornecedor
| Coluna | Tipo | Obs |
|---|---|---|
| produtofornecedorid | integer | ID automático; obrigatório |
| produtoid | integer | obrigatório; → produtosestoque.produtoid |
| fornecedorid | integer | obrigatório; → fornecedores.fornecedorid |
| descricaoxml | varchar(255) | obrigatório |
| datacriacao | timestamptz | padrão now() |
| codigofornecedor | varchar(60) |  |
| ean | varchar(14) |  |
| ncm | varchar(20) |  |
| fatorconversao | numeric(10,4) | padrão 1.0 |

## produtosloja
| Coluna | Tipo | Obs |
|---|---|---|
| produtoid | integer | ID automático; obrigatório |
| nome | varchar(150) | obrigatório |
| descricao | text |  |
| custoempontos | integer | obrigatório |
| estoquedisponivel | integer |  |
| ativo | boolean | obrigatório; padrão true |

## resgates
| Coluna | Tipo | Obs |
|---|---|---|
| resgateid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| produtoid | integer | obrigatório; → produtosloja.produtoid |
| pontosgastos | integer | obrigatório |
| datasolicitacao | timestamptz | obrigatório; padrão now() |
| status | varchar(50) | obrigatório; padrão 'Pendente' |
| gestorid_aprovacao | integer |  |
| dataaprovacao | timestamptz |  |

## solicitacoesinternas
| Coluna | Tipo | Obs |
|---|---|---|
| solicitacaoid | integer | ID automático; obrigatório |
| funcionarioid | integer | → funcionarios.funcionarioid |
| datasolicitacao | timestamptz | padrão now() |
| tipo | varchar(20) | obrigatório |
| categoria | varchar(50) |  |
| descricao | text |  |
| quantidade | numeric(10,2) |  |
| caminhofoto | varchar(255) |  |
| status | varchar(20) | obrigatório; `Aberta`, `Em andamento`, `Concluída` ou `Recusada` |
| motivorecusa | text | obrigatório quando Recusada |
| unidade | varchar(20) | só em Compra (ex.: litros) |
| registradopor | uuid | → auth.users |
| atualizadoem | timestamptz | obrigatório; padrão now() |

`tipo`: `Compra` ou `Manutencao`. Transições: Aberta → Em andamento/Concluída/Recusada; Em andamento → Concluída/Recusada. O pedido em si não muda; nada se apaga. Entra por `abrir_solicitacao` e muda por `mudar_situacao_solicitacao`. Cada mudança vai para `solicitacoeshistorico` por gatilho.
| dataconclusao | timestamptz |  |

## tarefas
| Coluna | Tipo | Obs |
|---|---|---|
| tarefaid | integer | ID automático; obrigatório |
| sistema | varchar(40) | Vazio nas tarefas comuns. Nas 6 do sistema diz qual é: `feedback_diario`, `leitura`, `pontos_meta`, `nota_fiscal`, `modelo_agendamento`, `guardar_mercadoria`. Única por conta. Tarefa do sistema **não pode ser apagada**, e as 4 primeiras **não podem ser atribuídas** a ninguém. |
| titulo | varchar(255) | obrigatório |
| descricao | text |  |
| pontos | integer | obrigatório |
| datacriacao | timestamptz | padrão now() |
| ativa | boolean | padrão true |
| setor | varchar(100) |  |

## tarefasatribuidas
| Coluna | Tipo | Obs |
|---|---|---|
| atribuicaoid | integer | ID automático; obrigatório |
| tarefaid | integer | obrigatório; → tarefas.tarefaid |
| funcionarioid | integer | → funcionarios.funcionarioid |
| dataatribuicao | timestamptz | padrão now() |
| tipofrequencia | varchar(20) | obrigatório; padrão 'Unica' |
| valorfrequencia | integer |  |
| grupoid | integer | → grupos.grupoid |
| funcionarioresponsavelid | integer | → funcionarios.funcionarioid |
| horariodisparo | time |  |
| statustarefagrupo | varchar(50) |  |
| dataaceite | timestamptz |  |
| datainiciovigencia | date |  |
| datafimvigencia | date |  |
| agendamentoid | integer |  |
| dataagendamento | timestamptz |  |
| descricaooverride | text |  |
| origematribuicaoid | integer | → tarefasatribuidas.atribuicaoid |


---

## configuracoes
Tabela **nova**, não existia no SQL Server. Guarda os parâmetros que ficavam fixos no `legado/config.py`.

| Coluna | Tipo | Obs |
|---|---|---|
| chave | varchar(100) | obrigatório; chave primária **(contaid, chave)** |
| valor | text |  |
| descricao | text |  |
| atualizadoem | timestamptz | obrigatório; padrão now() |

O navegador só lê; altera por `alterar_configuracao` (só o master; os `TAREFA_*` não). Um gatilho valida todo caminho: taxa numérica > 0 e ≤ 10; `PONTOS_BONUS_*` inteiro de 0 a 10.000; `MAX_DIFERENCA_FOTO_SEGUNDOS` inteiro até 86.400; `HORARIO_*` no formato HH:MM.

## justificativas
Tabela **nova** (Etapa 1.7, parte 3), **nível loja**. "Não se aplica" de uma tarefa num dia.

| Coluna | Tipo | Obs |
|---|---|---|
| justificativaid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| atribuicaoid | integer | obrigatório; → tarefasatribuidas (junto com contaid) |
| funcionarioid | integer | obrigatório; → funcionarios (junto com contaid) |
| dia | date | obrigatório. Na tarefa Única, o dia marcado |
| motivo | text | obrigatório |
| status | varchar(10) | `Pendente`, `Aceita` ou `Recusada` |
| origem | varchar(10) | `gestor` ou `bot` |
| registradopor / registradoem | uuid / timestamptz | quem e quando registrou |
| decididopor / decididoem | uuid / timestamptz | quem e quando decidiu |
| motivorecusa | text | obrigatório quando Recusada |

Uma só por (atribuição, dia) enquanto Pendente ou Aceita. **Aceita:** sai das pendências, dos pontos possíveis da nota do mês e vira dia neutro na sequência de dias. **Pendente ou aceita:** o banco recusa entrega daquela tarefa naquele dia. Decidida não muda; nada se apaga. O navegador só lê.

## solicitacoeshistorico
Tabela **nova** (Etapa 1.7, parte 3), **nível loja**. Cada abertura e mudança de situação de uma solicitação, gravada por gatilho. **Nunca muda nem se apaga**, nem para o dono.

| Coluna | Tipo | Obs |
|---|---|---|
| historicoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| solicitacaoid | integer | obrigatório; → solicitacoesinternas (junto com contaid) |
| statusanterior | varchar(20) | vazio na abertura |
| statusnovo | varchar(20) | obrigatório |
| observacao | text | motivo da recusa ou observação |
| alteradopor | uuid | → auth.users |
| alteradoem | timestamptz | obrigatório; padrão now() |

## configuracoeshistorico
Tabela **nova** (Etapa 1.7, parte 2). Cada mudança de configuração, gravada por gatilho. O navegador só lê.

| Coluna | Tipo | Obs |
|---|---|---|
| historicoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| chave | varchar(100) | obrigatório; → configuracoes (junto com contaid) |
| valoranterior | text |  |
| valornovo | text |  |
| alteradopor | uuid | → auth.users |
| alteradoem | timestamptz | obrigatório; padrão now() |

---

# Tabelas do modelo multi-empresa

## contas
O cliente que comprou o produto. Criada pelo administrador geral.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | ID automático; chave primária |
| nome | varchar(200) | obrigatório; nome do cliente/empresa |
| email | varchar(255) | obrigatório; único (sem diferenciar maiúsculas) |
| telefone | varchar(50) |  |
| cidade | varchar(100) |  |
| limitelojas | integer | obrigatório; padrão 1. Quantas lojas ativas a conta pode ter |
| status | varchar(20) | obrigatório; padrão 'ativa'. `ativa` / `suspensa` / `cancelada`. Suspensa = somente leitura |
| observacoes | text |  |
| criadoem | timestamptz | obrigatório; padrão now() |

## contasusuarios
Liga um login do Supabase Auth a uma conta. **Um login pertence a uma única conta.**

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | obrigatório; chave primária composta; → contas.contaid |
| userid | uuid | obrigatório; chave primária composta; → auth.users.id; **único sozinho** |
| papel | varchar(20) | obrigatório; padrão 'master'. `master` / `gerente` (gerente só na Fase 16) |
| criadoem | timestamptz | obrigatório; padrão now() |

## lojas
| Coluna | Tipo | Obs |
|---|---|---|
| lojaid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas.contaid |
| nome | varchar(150) | obrigatório; único dentro da conta |
| cidade | varchar(100) |  |
| endereco | varchar(255) |  |
| ativa | boolean | obrigatório; padrão true. Lojas ativas ≤ `contas.limitelojas` |
| criadoem | timestamptz | obrigatório; padrão now() |
| gestorid | integer | Gestor da loja. → funcionarioslojas (junto com lojaid): tem de trabalhar nela |
| responsavelagendamentosid | integer | Quem recebe as tarefas de agendamento da loja. → funcionarioslojas (junto com lojaid) |
| mostrarvalorestv | boolean | obrigatório; padrão **false**. Se a TV mostra os valores em R$ da meta. Desligado, o banco só envia porcentagens para a TV |

## funcionarioslojas
Em quais lojas cada funcionário trabalha. Tirar alguém de uma loja = `ativo = false`; **nunca apagar**, para não perder o histórico.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | obrigatório; → contas.contaid |
| funcionarioid | integer | obrigatório; chave primária composta; → funcionarios (junto com contaid) |
| lojaid | integer | obrigatório; chave primária composta; → lojas (junto com contaid) |
| posicaopadraoid | integer | lugar padrão no mapa **daquela loja**; → posicoesloja (junto com lojaid) |
| ativo | boolean | obrigatório; padrão true |
| criadoem | timestamptz | obrigatório; padrão now() |

## tarefaslojas
Em quais lojas cada tarefa vale. Mesma regra: desativar, nunca apagar.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | obrigatório; → contas.contaid |
| tarefaid | integer | obrigatório; chave primária composta; → tarefas (junto com contaid) |
| lojaid | integer | obrigatório; chave primária composta; → lojas (junto com contaid) |
| ativo | boolean | obrigatório; padrão true |
| criadoem | timestamptz | obrigatório; padrão now() |

# Funções do banco

| Função | O que faz |
|---|---|
| `minha_conta()` | A conta do usuário logado. Usada como padrão de `contaid` e em toda policy de leitura |
| `minha_conta_editavel()` | O mesmo, mas só se a conta estiver `ativa`. Usada nas policies de escrita |
| `eh_admin_geral()` | Verdadeiro só para `wisley_anderson@hotmail.com` com e-mail confirmado |
| `cria_configuracoes_padrao(contaid)` | Semeia as 18 configurações padrão numa conta nova |
| `cria_tarefas_do_sistema(contaid)` | Cria as 6 tarefas do sistema, grava os IDs em `configuracoes` e as liga a todas as lojas |
| `tarefa_cai_no_dia(tipo, valor, dataagendamento, dia)` | Quando uma tarefa recorrente aparece. Única acumula; Mensal com dia inexistente cai no último dia do mês |
| `dia_em_sao_paulo(instante)` | O dia de um instante no fuso da loja |
| `registrar_entrega(atribuicao, observacao, foto, aprovar)` | Registra uma entrega de atribuição que cai hoje ou está atrasada; se `aprovar`, já aprova na mesma transação |
| `aprovar_entrega(entrega)` | Só aprova Pendente. Credita os pontos da tarefa em `saldopontos` e `pontostotal`. Devolve os pontos |
| `recusar_entrega(entrega, motivo)` | Só recusa Pendente. Motivo obrigatório. A tarefa volta a aparecer |
| `estornar_entrega(entrega, motivo)` | Só estorna Aprovada. Motivo obrigatório. Desconta os pontos; o saldo pode ficar negativo. Devolve o saldo novo |
| `atribuicoes_para_entregar(loja)` | O que pode ser entregue hoje naquela loja |
| `ranking_pontos(de, ate, loja)` | Soma dos pontos aprovados no período, pela data da aprovação. Sem loja = geral da conta |
| `apos_aprovar_entrega(entrega)` | **Interna.** Chamada em toda aprovação; avalia as conquistas da pessoa |
| `nome_curto(nome)` | "Ana Souza" → "Ana S.". Usado na TV |
| `montar_painel(conta, loja, tv)` | **Interna, ninguém chama direto.** Monta o painel de uma loja (barra, pódio, colunas), sem ids, fotos, observações, telefone ou CPF |
| `painel_da_loja(loja)` | O painel para quem está logado; só lojas da própria conta |
| `resumo_das_lojas()` | Um cartão por loja ativa: progresso, pendentes e líder do dia |
| `painel_inicio(loja?)` | Tela Início (Etapa 1.10B). **Security invoker** (a RLS filtra a conta). Sem loja = todas as lojas ativas. Devolve cartões (metas do dia/mês, tarefas de hoje, aguardando validação, agenda de hoje, comunicados sem ciência, onboarding, solicitações, justificativas), vendas do mês dia a dia, pontos por semana (8 semanas, pelo livro), aprovadas × recusadas por semana, top 5 do mês, próximos agendamentos (hora, tipo, 1º nome do responsável), últimas entregas a validar e o guia de primeiros passos. Nada de CPF, telefone ou cliente final. Fuso America/Sao_Paulo |
| `criar_link_tv(loja, nome)` | Cria um link de TV e devolve o código **uma única vez** |
| `revogar_link_tv(link)` | Desliga um link de TV |
| `painel_da_tv(codigo)` | **A única função que um visitante sem login pode chamar.** Devolve o painel da loja do link com nomes curtos, ou `{"disponivel": false}` |
| `reais(valor)` | "R$ 15,50" |
| `minha_taxa()` | A taxa ponto → real da conta de quem está logado |
| `registrar_troca(pessoa, premio, loja, entregar)` | Resgate atômico: trava pessoa e prêmio, confere saldo e estoque, desconta os dois e grava o movimento. (Era `registrar_resgate`; nomes neutros por causa de bloqueadores de anúncio) |
| `registrar_troca_por_valor(pessoa, valor, loja, entregar)` | Abate na comanda: pontos = valor ÷ taxa, arredondado para cima; guarda R$, pontos e taxa |
| `concluir_troca(resgate)` | Pendente → Entregue |
| `cancelar_troca(resgate, motivo)` | Pendente → Cancelado; devolve pontos e estoque |
| `estornar_troca(resgate, motivo)` | Entregue → Estornado; devolve pontos e estoque |
| `listar_trocas(limite)` | Os resgates recentes com pessoa, prêmio e loja (a tela não lê a tabela `resgates` pelo endereço) |
| `extrato_pontos(pessoa, de, ate)` | Saldo inicial, final, atual, taxa e os movimentos do período com saldo após cada um |
| `dia_de_trabalho(folga, domingofolga, inicioafast, fimafast, dia)` | Falso na folga semanal, no N-ésimo domingo de folga e no afastamento. Usada pela nota do mês, pela sequência de dias e pelas pendências |
| `ranking_mensal(ano, mes, loja)` | Nota do mês: pontos ganhos, regulares, possíveis, confiabilidade, esforço e nota (50/50). Mês corrente até ontem |
| `criar_conquista(nome, descricao, icone, tipo, valor, dias, bonus, retroativa)` | Cria a conquista; se retroativa, concede na hora a quem já cumpre |
| `criterio_disponivel(tipo)` | Se a regra já é avaliada (os módulos de feedback, comunicados e grupos ainda não existem) |
| `pessoa_cumpre_conquista(conta, pessoa, conquista)` | **Interna.** Confere a regra |
| `avaliar_conquistas(conta, pessoa)` | **Interna.** Concede o que a pessoa passou a cumprir, uma vez só, e grava o bônus no livro |
| `pendencias_da_pessoa(pessoa, de, ate)` | Tarefas que caíam e não foram entregues, dia a dia, até ontem (no máximo 3 meses) |
| `historico_da_pessoa(pessoa, limite)` | Últimas entregas da pessoa em qualquer situação |
| `analise_de_tarefas(de, ate, loja)` | Por tarefa: aprovadas, recusadas, estornadas e pendentes |
| `registrar_feedback(pessoa, dia, nota, comentario)` | Só hoje ou ontem; um por dia; bônus pelo livro; avalia as conquistas |
| `anular_feedback(feedback, motivo)` | Anula uma vez só e estorna o bônus pelo livro; a conquista fica |
| `tem_justificativa(atribuicao, tipo, dia, so_aceita)` | Se a tarefa está justificada no dia (Única vale para qualquer dia) |
| `justificaveis(pessoa, dia)` | Tarefas que caíam naquele dia de trabalho e não foram entregues nem justificadas |
| `registrar_justificativa(atribuicao, dia, motivo, aceitar)` | Registra; já aceita ou fica pendente |
| `decidir_justificativa(justificativa, aceitar, motivo)` | Só Pendente; recusar exige motivo |
| `maior_sequencia(feitos, neutros, folga, domingofolga, inicioafast, fimafast)` | Maior sequência de dias; folga, afastamento e neutros não quebram nem somam |
| `sou_master()` | Se quem está logado é o master da conta |
| `registrar_relato(conta, texto)` | **Só o servidor (bot).** Grava o relato anônimo e devolve o protocolo uma única vez |
| `consultar_relato(conta, protocolo)` | **Só o servidor.** Situação e resposta pelo protocolo |
| `tratar_relato(relato, situacao, resposta)` | Só o master: em análise, tratado, resposta |
| `abrir_solicitacao(loja, pessoa, tipo, categoria, descricao, quantidade, unidade)` | Quem pediu precisa trabalhar na loja; nasce Aberta |
| `mudar_situacao_solicitacao(solicitacao, situacao, observacao)` | Só as transições permitidas; recusar exige motivo |
| `meta_do_dia(loja, dia)` | A meta de uma data: a especial, se houver; senão, o modelo do dia da semana |
| `primeiro_dia_editavel_meta()` | O dia 1 do mês anterior: antes dele, nada se lança nem se corrige |
| `lancar_venda_do_dia(loja, dia, valor, motivo)` | Lança ou corrige o total vendido; paga ou estorna a meta do dia e a do mês. Um de cada vez por loja e dia |
| `salvar_meta_do_mes(loja, mes, nome, valor, pontos, descricao)` | Cria ou altera a meta do mês e reavalia o prêmio |
| `metas_do_mes(loja, mes)` | Resumo do mês dia a dia para a tela Metas |
| `equipe_da_meta(conta, loja, dia)` | **Interna.** Quem ganha: ligado à loja, ativo e, no dia da venda, sem folga nem afastamento |
| `pagar_premio_meta(...)` / `estornar_premio_meta(premio, motivo)` | **Internas.** Pagam pelo livro e estornam exatamente de quem recebeu |
| `reavaliar_meta_do_dia(lancamento)` / `reavaliar_meta_do_mes(conta, loja, mes)` | **Internas.** Aplicam a regra de correção |
| `meta_para_painel(conta, loja, tv)` | **Interna.** Bloco da meta do painel; na TV sem a opção da loja, só porcentagens |
| `cria_tipos_evento_padrao(conta)` | **Só o servidor.** Conta nova começa com o tipo "Evento" |
| `criar_agendamento(loja, tipo, data, cliente, cpf, telefone, observacoes, valor, pagamento, responsavel, aceitawhatsapp)` | Cria e gera a tarefa "Atender agendamento" para o responsável |
| `remarcar_agendamento(ag, novadata, motivo)` / `trocar_responsavel_agendamento(ag, pessoa)` | Só Confirmado; a tarefa vai junto (se ainda não foi entregue) |
| `editar_agendamento(...)` / `alterar_pagamento_agendamento(ag, situacao, valor)` | Dados do cliente e pagamento |
| `marcar_agendamento_realizado(ag)` / `reabrir_agendamento(ag, motivo)` / `cancelar_agendamento(ag, motivo)` | Situações; cancelar encerra a tarefa |
| `conflitos_agendamento(loja, data, ignorar)` | Agendamentos confirmados a menos de 2 h (aviso) |
| `registrar_anexo_agendamento(...)` / `remover_anexo_agendamento(anexo)` | Anexos do Storage, com histórico |
| `pasta_de_agendamento_minha(caminho, editavel)` | Usada nas regras do Storage: a pasta tem de ser de um agendamento da conta e da loja |
| `agenda_para_painel(conta, loja, tv)` | **Interna.** Próximos agendamentos; na TV só hora e tipo |
| `publicar_comunicado(titulo, texto, pontos, alvo, lojas, pessoas)` | Publica e fixa os destinatários (só ativos da conta) |
| `editar_comunicado` / `arquivar_comunicado` / `incluir_destinatarios` / `fora_do_comunicado` | Editar só antes da primeira ciência; arquivar é final; acréscimo manual; quem o alvo alcança e ainda não está |
| `registrar_ciencia(ciencia)` / `desfazer_ciencia(ciencia, motivo)` | Atômicas; pontos e estorno pelo livro; desfazer só o master |
| `recibo_ciencia(ciencia)` / `recibo_resgate(resgate)` | Dados dos PDFs (o de resgate sai do livro de pontos) |
| `alcance_do_comunicado(comunicado)` / `exige_master_editavel()` | **Internas** |
| `preparar_envio_documento(pessoa, arquivo)` / `registrar_documento_pessoal(...)` | Envio de documento pessoal (só o master), com registro de acesso |
| `liberar_documento_pessoal(doc)` | Registra o acesso e libera o arquivo para gerar o link de 5 minutos |
| `registrar_ciencia_documento` / `arquivar_documento_pessoal` / `excluir_documento_por_engano` | Ciência, arquivar, excluir (só sem ciência e até 7 dias) |
| `documento_rh_liberado(caminho, acao)` | Usada nas regras do Storage `documentos-rh` |
| `cria_etapas_onboarding_padrao(conta)` | **Só o servidor.** As 6 etapas genéricas |
| `iniciar_onboarding(pessoa)` / `marcar_etapa_onboarding(item, feito, observacao, documento)` | Checklist do onboarding |
| `alterar_configuracao(chave, valor)` | Só o master; recusa os `TAREFA_*`; o gatilho valida e registra no histórico |

Todas têm `search_path` fixo. As de entrega e as de identificação são `security definer` e **conferem por conta própria** quem chamou. `cria_configuracoes_padrao` e `cria_tarefas_do_sistema` também são, mas **só o servidor** as executa. `ranking_pontos`, `atribuicoes_para_entregar`, `ranking_mensal`, `listar_trocas` e os relatórios rodam com a RLS de quem chamou.

## linkstv
Links de TV de cada loja (**nível loja**). O código em si nunca é guardado.

| Coluna | Tipo | Obs |
|---|---|---|
| linktvid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| nome | varchar(100) | obrigatório (ex.: "TV do balcão") |
| tokenhash | char(64) | obrigatório; único. Impressão digital (sha256) do código. **Ninguém lê esta coluna pelo navegador, nem o dono** |
| criadoem | timestamptz | obrigatório; padrão now() |
| criadopor | uuid | → auth.users |
| revogadoem | timestamptz | preenchida ao revogar; o link para na hora |
| ultimouso | timestamptz | última vez que a TV buscou o painel (gravada no máximo uma vez por minuto) |

O navegador só lê esta tabela; criar e revogar passam pelas funções.

## movimentospontos
O livro de pontos (**nível conta**; a loja é opcional). Cada entrada e saída de pontos é uma linha. **Nunca se altera nem se apaga** — corrige-se com outro movimento. Gravar aqui é o único jeito de mudar o saldo.

| Coluna | Tipo | Obs |
|---|---|---|
| movimentoid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| funcionarioid | integer | obrigatório; → funcionarios (junto com contaid) |
| lojaid | integer | opcional; → lojas (junto com contaid) |
| datamovimento | timestamptz | obrigatório; padrão now() |
| tipo | varchar(30) | `aprovacao`, `estorno_entrega`, `bonus`, `estorno_bonus`, `resgate`, `cancelamento_resgate`, `estorno_resgate`, `ajuste_abertura` |
| pontos | integer | obrigatório; diferente de zero. Positivo entra, negativo sai |
| descricao | text | obrigatório. O que aparece no extrato |
| entregaid | integer | → entregas (junto com contaid), quando veio de uma entrega |
| resgateid | integer | → resgates (junto com contaid), quando veio de um resgate |
| conquistafuncionarioid | integer | → conquistasfuncionarios (junto com contaid), quando é bônus de conquista |
| feedbackid | integer | → feedbacks (junto com contaid), quando é bônus de feedback ou o estorno dele |
| assinaturaid | integer | → documentosassinaturas (junto com contaid), quando é bônus de ciência ou o estorno dele |
| premiacaoid | integer | → metaspremiacoes (junto com contaid), quando é prêmio de meta ou o estorno dele |
| criadopor | uuid | → auth.users |

O navegador só lê. Os tipos `aprovacao`, `estorno_entrega`, `bonus` e `estorno_bonus` também somam em `pontostotal`.

## Mudanças da Fase 7 em tabelas existentes

**produtosloja** ganhou `sistema` (`abate_comanda`, o prêmio do sistema escondido do catálogo; único por conta, não pode ser apagado). Estoque em branco = ilimitado, 0 = esgotado; custo > 0 nos prêmios comuns. O navegador cadastra e edita só nome, descrição, custo, estoque e ativo.

**resgates**: `status` é `Pendente`, `Entregue`, `Cancelado` ou `Estornado`. Novas colunas: `valorreais` e `taxaconversao` (comanda), `registradopor`, `dataentrega`/`entreguepor`, `datacancelamento`/`canceladopor`/`motivocancelamento`, `dataestorno`/`estornadopor`/`motivoestorno`. Cancelado e Estornado exigem motivo. O navegador só lê; tudo muda pelas funções. As colunas antigas `gestorid_aprovacao` e `dataaprovacao` ficaram sem uso.
