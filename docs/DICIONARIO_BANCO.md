# Dicionário do Banco — Game GB (Supabase)

> Estrutura extraída do backup `banco_teste.bak`. **Banco limpo: nenhum dado foi importado.** Nomes no Postgres = nomes originais em **minúsculas** (ex.: `FuncionarioID` → `funcionarioid`). IDs começam do 1.

## Modelo multi-empresa (Fase 2)
**Toda** tabela desta página tem, além das colunas listadas:

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | obrigatório; padrão `minha_conta()`; → `contas.contaid`. O front-end nunca informa. |
| lojaid | integer | obrigatório **só nas tabelas de nível loja**; → `lojas`, amarrado ao mesmo `contaid` |

**Nível conta** = compartilhado entre as lojas do cliente. **Nível loja** = cada loja tem os seus.

As chaves estrangeiras entre tabelas são **compostas com o `contaid`**: as duas pontas leem o mesmo `contaid` da mesma linha, então é impossível apontar para o registro de outra conta. Toda unicidade é por conta ou por loja — nunca global. (A única exceção, `grupos.chatidtelegram`, saiu com o Telegram em 04/10/2026.)

| Tabela | Nível | Chave | Referencia |
|---|---|---|---|
| `agendamentos` | **loja** | agendamentoid | funcionarios, tiposevento |
| `agendamentosanexos` | **loja** | anexoid | agendamentos |
| `agendamentoshistorico` | **loja** | historicoid | agendamentos |
| `avisosdispensados` | conta (por pessoa) | dispensaid | auth.users |
| `categoriasproduto` | conta | categoriaid |  |
| `configuracoesescala` | **loja** | configid |  |
| `configuracoessetores` | conta | setor |  |
| `configuracoes` | conta | (contaid, chave) |  |
| `configuracoeshistorico` | conta | historicoid | configuracoes |
| `diasgerados` | conta | (contaid, dia) |  |
| `fechamentosmensais` | conta | fechamentoid |  |
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
| `historicoranking` | **loja** (vazio = geral da conta) | historicoid | fechamentosmensais, funcionarios |
| `itenscontagemestoque` | **loja** | itemcontagemid | contagensestoque, produtosestoque |
| `itensnotafiscalentrada` | **loja** | itemnotaid | notasfiscaisentrada, produtosfornecedor |
| `justificativas` | **loja** | justificativaid | tarefasatribuidas, funcionarios |
| `lucromensalhistorico` | **loja** | historicoid |  |
| `metasdiariasapuracoes` | **loja** | apuracaoid | funcionarios, metasprincipais |
| `metasdiariasinstancias` | **loja** | metainstanciaid |  |
| `metasdiariasmodelos` | **loja** | diasemanaid |  |
| `metasalteracoes` | **loja** | alteracaoid |  |
| `metasdodia` | **loja** | metadodiaid |  |
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
| `produtosloja` | **conta** (o nome engana: é a loja de RECOMPENSAS, não uma loja física) | produtoid |  |
| `resgates` | conta | resgateid | funcionarios, produtosloja |
| `solicitacoeshistorico` | **loja** | historicoid | solicitacoesinternas |
| `solicitacoesinternas` | **loja** | solicitacaoid | funcionarios |
| `rotinasexecucoes` | conta | execucaoid |  |
| `fotosexpurgo` | conta | expurgoid | entregas |
| `tentativasacesso` | conta | tentativaid |  |
| `cargos` | conta | cargoid | — |
| `cargospermissoes` | conta | (contaid, cargoid, codigo) | cargos |
| `usuariosgerenciais` | conta | (contaid, userid) | contasusuarios, cargos, funcionarios |
| `usuarioslojas` | conta (a loja é o dado) | (userid, lojaid) | usuariosgerenciais, lojas |
| `permissoeshistorico` | conta | historicoid | — |
| `autores` | conta | autorid | — |
| `travaspin` | conta | (contaid, funcionarioid) | funcionarios |
| `pinliberacoes` | conta | liberacaoid | funcionarios |
| `codigosacesso` | conta | codigoid | funcionarios |
| `folhasacesso` | conta | folhaid | funcionarios, codigosacesso |
| `codigosantigos` | conta | codigo | contas |
| `anexosadmin` | conta (ou rede) | anexoid | contas / redes |
| `redes` | **plataforma** (sem conta) | redeid | — |
| `chamadasdoservidor` | **plataforma** (sem conta) | chamadaid | — |
| `jornadas` | conta | jornadaid | — |
| `jornadaslojas` | loja | (contaid, jornadaid, lojaid) | jornadas, lojas |
| `jornadasdias` | conta | (jornadaid, diasemana) | jornadas |
| `intervalosdomapa` | conta | (contaid, funcionarioid) | funcionarios |
| `senhasgestor` | conta (vazia no admin geral) | userid |  |
| `tarefasdodia` | **loja** | itemid | tarefasatribuidas, funcionarios, tarefas |
| `fotosdafila` | **loja** | (contaid, dia, atribuicaoid) | lojas |
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
| notificacaogestorenviada | boolean | padrão false |
| observacao | text | Observação de quem registrou a entrega |
| dataaprovacao | timestamptz | Quando foi aprovada. **O ranking usa esta data.** `dataenvio` guarda sempre o envio real |
| aprovadopor | uuid | → auth.users. Quem aprovou |
| datarecusa | timestamptz |  |
| recusadopor | uuid | → auth.users |
| dataestorno | timestamptz |  |
| estornadopor | uuid | → auth.users |
| motivoestorno | text | Obrigatório quando o status é Estornada |
| fotoaguardaremocaoem | timestamptz | Quando a foto passou do prazo e o arquivo entrou na fila para ser apagado (29/09/2026). Daí em diante a foto **não aparece em tela nenhuma** (a política promete que ela some depois do prazo) e a entrega diz "sendo apagada" |
| fotoexpiradaem | timestamptz | Quando a foto foi apagada por tempo (Etapa 1.12). **Desde 29/09/2026 só é gravada depois de o arquivo sair de verdade** (`expurgo_resultado`), nunca antes. A entrega, os pontos e o histórico continuam valendo; a tela mostra "foto removida por tempo" |

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
| cargo | varchar(100) |  |
| pontostotal | integer | padrão 0. Tudo o que a pessoa já ganhou (aprovações, bônus, estornos de entrega; resgates não contam). Só o gatilho do livro altera |
| horarionotificacao | time | **hora de entrada** (nome herdado do sistema antigo). Vazio = a pessoa não recebe as mensagens de jornada (Etapa 1.13B1). O padrão 08:00 foi retirado |
| horariosaida | time | hora de saída. Vazio = entrada + 8h20. Menor que a entrada = turno da noite, que atravessa a meia-noite |
| diadefolga | integer | obrigatório; padrão 0 |
| saldopontos | integer | obrigatório; padrão 0. O que a pessoa tem para gastar. **Sempre a soma de `movimentospontos`**; só o gatilho do livro altera. Pode ficar negativo por estorno de entrega, nunca por resgate |
| verificadorcpf | varchar(3) |  |
| senhahash | varchar(256) |  |
| isgestor | boolean | padrão false |
| ~~posicaopadraoid~~ | — | removida na Fase 2: o lugar padrão passou a ser por loja, em `funcionarioslojas` |
| nivelacesso | varchar(50) | padrão 'Funcionario' |
| cpf | varchar(14) | guardado só com números (11 dígitos), validado com os verificadores; aceita digitação com pontos. É o login do colaborador. **Único por conta** entre os ativos |
| pinhash | char(64) | PIN do tablet embaralhado pelo servidor (HMAC com chave fora do banco). Único por conta entre os ativos. O número nunca é guardado. **Ninguém lê pelo navegador, nem o master** |
| senhahashapp | text | Resumo da senha do app (PBKDF2 com sal por pessoa, calculado no servidor). Vazio = ainda não criou senha. **Ninguém lê pelo navegador** |
| primeiroacessoem | timestamptz | vazio = nunca entrou no app |
| acessoredefinidoem / acessoredefinidopor | timestamptz / uuid | quem redefiniu o acesso e quando |
| telefonewhatsapp | varchar(20) |  |
| setor | varchar(50) |  |
| domingofolgamensal | integer | padrão 0 |
| datainicioafastamento | date |  |
| datafimafastamento | date |  |
| ativo | boolean | obrigatório; padrão true. Acrescentada em 21/09/2026: `false` = desligado definitivamente. As datas de afastamento valem só para afastamento temporário. |

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
| lojaid | integer | → lojas; **vazio = ranking geral da conta** (Etapa 1.11) |
| fechamentoid | integer | obrigatório; → fechamentosmensais (a versão do fechamento) |
| pontosregulares | integer | pontos das tarefas regulares (confiabilidade) |
| confiabilidade | numeric(6,2) | % |
| esforco | numeric(6,2) | % |
| nota | numeric(6,2) | metade confiabilidade + metade esforço |

Só as funções da rotina gravam aqui (a tela só lê). Linha de fechamento definitivo ou substituído não muda nem se apaga.

## fechamentosmensais (Etapa 1.11)
| Coluna | Tipo | Obs |
|---|---|---|
| fechamentoid | integer | ID automático |
| ano, mes | integer | o mês fechado |
| versao | integer | 1 = rotina; +1 a cada "Refazer" |
| situacao | varchar | provisorio (dias 1 a 7), definitivo (dia 8), substituido |
| origem | varchar | rotina ou master |
| motivo | text | obrigatório quando o master refaz |
| fechadopor, fechadoem, definitivoem, substituidoem | | quem e quando |

Um fechamento valendo por mês (índice único fora os substituídos).

## tarefasdodia (Etapa 1.11) — lista do dia congelada
| Coluna | Tipo | Obs |
|---|---|---|
| itemid | integer | ID automático |
| lojaid, dia, atribuicaoid, funcionarioid, tarefaid | | o que a pessoa devia fazer no dia (único por conta, dia e atribuição) |
| tipofrequencia | varchar | copiado da atribuição |
| pontos | integer | **os do dia em que foi gerado** (não muda) |
| situacao | varchar | devida, folga, afastamento, cancelada |
| passadapara, passadaatribuicaoid, passadaem, passadapor | | repasse de quem estava de folga (uma vez por dia) |
| recuperado | boolean | gerado depois, numa volta de parada |

Só a situação (hoje) e o repasse mudam; dia passado nunca muda; item nunca se apaga.

## diasgerados (Etapa 1.11)
Dias em que a lista da conta foi gerada (`contaid`, `dia`, `recuperado`). Nunca é limpo: diz de onde vêm os números da nota (lista ou regra do cadastro).

`fotodafilaem` (timestamptz, 29/09/2026): a marca "registro completo" do filtro por dia do Quadro — quando a foto da fila daquele dia foi tirada. Vazia = o Quadro mostra "não registrado" em "para pegar". Cai junto quando a limpeza (ou qualquer outro caminho) apaga linhas da foto do dia.

## fotosdafila (29/09/2026)
Tabela **nova**, **nível loja**. A fila de cada loja como estava no **fim** de cada dia, tirada por `rotina_lista_do_dia` logo depois da meia-noite (só vale até as 03:00 do dia seguinte, e nunca de dia com lista recuperada depois de parada). Sai de `fila_no_dia`, a MESMA função da fila de hoje (`fila_da_loja`), com o fim do dia no lugar de "sem fim".

| Coluna | Tipo | Obs |
|---|---|---|
| contaid, lojaid | integer | obrigatórios; → lojas (junto com contaid) |
| dia | date | o dia fotografado |
| atribuicaoid | integer | a atribuição (sem FK: a foto se basta, com título e pontos daquele dia) |
| entregarid, titulo, pontos, tipofrequencia, aberta, donoid | | como na fila |
| quempegou, quempegounome, pegaem | | o aceite que valia no fim do dia |
| situacao | varchar(12) | `para_pegar`, `em_andamento` ou `feita` |
| atrasada | boolean | Única de dia anterior que continuava por fazer |
| feitapor, feitaem, feitasituacao | | a entrega que valia no fim do dia, com a situação daquele momento |
| tiradaem | timestamptz | quando a foto foi tirada |

Chave (contaid, dia, atribuicaoid). O navegador só lê (a escrita nem existe como permissão). Guardada desde `fila_alcance(hoje).guardardesde`: o alcance do filtro (mês corrente e anterior) mais um mês de margem — a limpeza e a tela tiram prazo e alcance da MESMA regra.

## rotinasexecucoes (Etapa 1.11)
| Coluna | Tipo | Obs |
|---|---|---|
| execucaoid | integer | ID automático |
| rotina | varchar | lista_do_dia, fechamento_mensal, conferencia_livro, limpeza, mensagens, expurgo_fotos, foto_da_fila |
| referencia | date | o dia a que se refere |
| origem | varchar | agendada ou manual ("Rodar agora") |
| recuperado | boolean | dia recuperado depois de parada |
| iniciadoem, terminadoem | timestamptz | |
| resultado | varchar | ok ou erro |
| detalhe | jsonb | contagens (sem dados pessoais) |
| erro | text | mensagem do erro (só o master da conta lê) |

Apagado depois de 180 dias pela própria rotina.

## codigosacesso (Etapa 1.12)
Código de primeiro acesso do colaborador. Nível conta.

| Coluna | Tipo | Obs |
|---|---|---|
| codigoid | integer | ID automático |
| contaid / funcionarioid | integer | de quem é o código |
| codigohash | char(64) | o código **embaralhado pelo servidor**; é o que confere a entrada |
| codigocifrado | text | o código **cifrado pelo servidor** (AES-GCM, chave fora do banco, amarrado à conta e à pessoa), só para reimprimir a folha. Vazio nos códigos de antes de 27/09/2026 |
| expiraem | timestamptz | padrão: 7 dias |
| usadoem / canceladoem | timestamptz | uso único; gerar outro cancela o anterior |
| criadopor / criadoem | uuid / timestamptz | |

**Ninguém lê pelo navegador.** É assim que a pessoa entra da primeira vez: **não existe senha padrão**. Desativar a pessoa cancela o código pendente. Funções: `criar_codigo_acesso` e `usar_codigo_acesso` (só o servidor).

**Só para o PRIMEIRO acesso (27/09/2026):** o banco não gera código para quem já tem senha ou PIN, e o código não abre a conta de quem já tem. Para dar código novo a quem já entrou, o caminho é redefinir o acesso (apaga senha e PIN e derruba as sessões antes).

## folhasacesso (27/09/2026)
Cada folha de instruções de acesso (PDF) emitida. Nível conta. A folha em si não é guardada: é gerada na hora, no navegador.

| Coluna | Tipo | Obs |
|---|---|---|
| folhaid | integer | ID automático |
| contaid / funcionarioid | integer | de quem é a folha (FK composta: mesma conta) |
| codigoid | integer | o código impresso nela (FK composta: mesma conta) |
| redefiniu | boolean | esta folha redefiniu o acesso (senha e PIN anteriores deixaram de valer) |
| emitidaem / emitidapor | timestamptz / uuid | quem imprimiu e quando |

Só o master da conta lê; ninguém escreve pelo navegador — quem registra é o servidor, na mesma chamada que monta a folha (`registrar_folha_de_acesso`). Os dados da folha saem numa consulta só: `folha_de_acesso` (só o servidor).

## senhasgestor (Etapa 1.12)
Resumo da senha do master, do administrador geral e do tablet da loja (o colaborador guarda o dele em `funcionarios.senhahashapp`).

| Coluna | Tipo | Obs |
|---|---|---|
| userid | uuid | → auth.users; chave primária |
| contaid | integer | vazio no administrador geral |
| senhahashapp | text | PBKDF2 com sal por pessoa, calculado no servidor |
| atualizadoem | timestamptz | |

**Por que existe:** se a senha ficasse só no Supabase, qualquer um poderia tentá-la direto lá, pulando a nossa trava de tentativas. Agora a senha do Supabase é um valor interno que ninguém digita, e quem confere a senha digitada somos nós. Quem ainda não tem resumo guardado entra uma última vez pela senha antiga, e ela é convertida nesse momento.

## tentativasacesso (Etapa 1.12)
Tentativas de entrar (senha) e de usar o PIN no tablet. Nível conta (vazio só nas tentativas de senha do master, antes de se saber a conta).

| Coluna | Tipo | Obs |
|---|---|---|
| tentativaid | bigint | ID automático |
| contaid | integer | → contas |
| tipo | varchar(10) | `senha` ou `pin` |
| chave | char(64) | CPF/e-mail **embaralhado pelo servidor**. O que foi digitado nunca é guardado |
| origem | varchar(40) | de onde veio (tela de login, tablet) |
| sucesso | boolean | |
| em | timestamptz | padrão now() |

**Ninguém lê pelo navegador.** Conferir e registrar são **a mesma operação** (`tentativa_abrir`, que tranca a chave): sem isso, uma rajada de pedidos simultâneos passava toda de uma vez. PIN: 5 erros em 1 minuto travam, contados por pessoa e por tablet, **mais um teto de 30 tentativas por dia** (é o que impede usar a tela do PIN como adivinhador). **Desde 29/09/2026 o PIN do tablet não usa mais esta tabela:** a trava é por pessoa, em `travaspin`. Senha: 5 erros em 15 minutos e teto de 50 por dia, contados pelo CPF/e-mail **e** pela origem, que é definida pelo servidor. O que passa de 7 dias é apagado. Funções: `acesso_travado` e `registrar_tentativa` (só o servidor).

## Permissões dos usuários gerenciais (29/09/2026, parte 1)
O mapa e as decisões estão em `docs/MAPA_PERMISSOES.md`. O **catálogo** do que existe para marcar não é tabela: é a função `catalogo_de_permissoes()` (é o mesmo para toda conta; mudar é migração nova). Quem decide é **uma função só**, `pode(codigo, loja)`: o master pode todo o catálogo nas lojas dele; o gerente só se o cargo tem o código **e** a loja está na lista dele; código fora do catálogo, ninguém. `lojas_onde_posso(codigo)` devolve as lojas (para as leituras). Nenhuma das tabelas abaixo aceita escrita de quem está logado: só as funções da página de Usuários (parte 5).

| Tabela | O que guarda |
|---|---|
| cargos | cargoid, contaid, nome (único por conta), criadoem, criadopor |
| cargospermissoes | um código do catálogo por linha (contaid, cargoid, codigo). Sem linha = não pode. Código que não existe é recusado |
| usuariosgerenciais | userid (login com papel `gerente` da mesma conta), cargoid, funcionarioid (quem ele é na equipe, quando também é da equipe; um por pessoa), ativo, criadoem, criadopor |
| usuarioslojas | em quais lojas cada usuário gerencial age (userid, lojaid) |
| permissoeshistorico | quem mudou o quê: contaid, em, quem, tabela, acao, antes, depois (JSON). Gravado por gatilho em cargos, cargospermissoes, usuariosgerenciais, usuarioslojas e nos logins master/gerente. **Nunca muda nem se apaga**, nem pelo dono do banco |

**O último master ATIVO:** o gatilho `contasusuarios_ultimo_master` recusa apagar ou rebaixar o último master de uma conta, e os gatilhos `stgame_ultimo_master_apagar`/`stgame_ultimo_master_bloquear` em `auth.users` recusam apagar ou bloquear o login dele. Master com login bloqueado não conta como "outro master" (`outro_master_ativo`). As cinco tabelas acima só o master lê.

**Escrita direta fechada (29/09/2026):** as tabelas da Fase 2 sem tela (`configuracoesescala`, `configuracoessetores`, `escaladiaria`, `posicoesloja`, `picodiario`, `freelancers`, `contagensestoque`, `itenscontagemestoque`, `produtosestoque`, `fornecedores`, `produtosfornecedor`, `categoriasproduto`, `notasfiscais`, `notasfiscaisentrada`, `itensnotafiscalentrada`, `lucromensalhistorico`, `metasdiariasinstancias`, `feedbacksolicitacoes`) e a coluna `funcionarios.isgestor` não aceitam gravação de quem está logado, master inclusive. Quando a tela existir, nasce com função e permissão.

## autores (29/09/2026, parte 2)
O nome de cada login em cada momento, para "quem fez" nunca depender do login continuar existindo. Nível conta. Só recebe linha nova (quando o login nasce ou quando o e-mail, o nome da pessoa ou o nome da loja muda). `autor_em(login, instante)` devolve o nome daquela hora. Só o master lê.

| Coluna | Tipo | Obs |
|---|---|---|
| autorid | bigint | ID automático |
| contaid | integer | → contas |
| userid | uuid | o login |
| nome | text | gestor: o e-mail (nunca o nome de exibição, que o usuário edita); colaborador: o nome do cadastro; tablet: "Tablet da <loja>" |
| email | text | |
| desde | timestamptz | a partir de quando vale (relógio de verdade) |

**Login que já fez alguma coisa não se apaga** (gatilho `stgame_login_com_atos` em `auth.users`): se ele aparece em qualquer coluna "quem fez" ou no histórico de permissões, o apagamento é recusado — bloqueie o login em vez de apagar. `permissoeshistorico.quemnome` guarda o nome na hora (as linhas anteriores ficam vazias e se leem com `autor_em`).

## travaspin (29/09/2026)
A trava do PIN do tablet, **por pessoa**. Nível conta. Uma linha por pessoa que já errou.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | → contas |
| funcionarioid | integer | → funcionarios (junto com contaid); chave junto com contaid |
| erros | integer | erros seguidos (zera no acerto, na liberação e depois de 24 h sem errar) |
| nivel | integer | o degrau do bloqueio: 1 = 1 min, 2 = 3 min, 3 ou mais = 10 min (`pin_minutos_do_degrau`) |
| bloqueadoate | timestamptz | até quando está bloqueada |
| ultimoerro | timestamptz | |

**Só as funções escrevem** (`pin_conferir_pessoa`, pelo servidor do tablet, e `liberar_pin`, pelo gestor). O navegador só lê a da própria conta. 2 erros são tolerados; do 3º em diante bloqueia 1, 3 e no máximo 10 minutos. Tentar durante o bloqueio não muda nada. PIN de quem está de folga não conta.

## pinliberacoes (29/09/2026)
Quem liberou o PIN de quem (Pessoas → Equipe → "Liberar PIN agora"). Nível conta. Nunca muda.

| Coluna | Tipo | Obs |
|---|---|---|
| liberacaoid | integer | ID automático |
| contaid | integer | → contas |
| funcionarioid | integer | → funcionarios (junto com contaid) |
| liberadopor | uuid | o login do master que liberou |
| liberadoem | timestamptz | padrão now() |
| estavaate | timestamptz | até quando estava bloqueada |
| erros | integer | quantos erros seguidos tinha |

## fotosexpurgo (Etapa 1.12)
Fila do que precisa sair do Storage. Nível conta.

| Coluna | Tipo | Obs |
|---|---|---|
| expurgoid | integer | ID automático |
| contaid | integer | obrigatório |
| entregaid | integer | → entregas (junto com contaid) |
| caminho | text | caminho do arquivo no bucket `entregas`; único por conta |
| criadoem | timestamptz | padrão now() |
| removidoem | timestamptz | quando o arquivo saiu do Storage |
| tentativas | integer | para em 5 |
| erro | text | último erro da remoção |

**Ninguém lê pelo navegador** (RLS ligada e sem policy; sem GRANT para `anon` nem `authenticated`). SQL não apaga arquivo do Storage: a rotina `rotina_expurgo_fotos(conta, agora)` **só põe o caminho aqui** (nunca o arquivo que ainda serve a uma entrega no prazo); quando a remoção é confirmada, `expurgo_resultado` marca as entregas (`fotoexpiradaem`) e zera `pathfotoevidencia` — antes disso a entrega continua dizendo que a foto está guardada (29/09/2026). Fila parada (5 tentativas, ou mais de 2 dias) vira aviso `expurgo_preso`; a `/saude` mostra as vencidas ainda guardadas (`saude_das_rotinas`, `saude_da_minha_conta`); a Edge Function **expurgo-fotos** (cabeçalho `x-expurgo-segredo`, chamada por `fotos_expurgo_disparar()` via pg_net) apaga o arquivo e responde por `expurgo_pegar` / `expurgo_resultado`. Prazo por conta em `DIAS_GUARDAR_FOTO_ENTREGA` (padrão 180, mínimo 90, garantido também por `dias_guardar_foto`). **`fotoidunico` não é apagado**: é a marca que impede reenviar a mesma foto. **Documento de RH não entra aqui**: tem regra própria.

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

## metasdodia
Tabela **nova** (30/09/2026), **nível loja**. A meta de um dia de um mês. Vale entre a meta especial da data e o modelo do dia da semana: **a ordem mora só em `meta_do_dia`** (1º especial, 2º `metasdodia`, 3º modelo). Grava só pela `salvar_metas_do_mes_por_dia` (tudo ou nada; nunca em dia lançado, com especial ou fora da janela do lançamento — mês atual e anterior, desde 01/10/2026). Master lê pela regra da tabela; gerente, pela `metas_do_mes_por_dia`.

| Coluna | Tipo | Obs |
|---|---|---|
| metadodiaid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; → contas |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| data | date | obrigatório; única por loja |
| valormeta | numeric(18,2) | obrigatório; 0 ou mais (0 = dia sem meta) |
| pontospremio | integer | 0 a 10.000 |
| alteradopor / alteradoem | uuid / timestamptz | quem e quando mudou por último |

## metasalteracoes
Tabela **nova** (30/09/2026), **nível loja**. Toda mudança de meta: `tipo` = `mes` (meta do mês), `dia` (`metasdodia`), `semana` (modelo) ou `especial`; `referencia` em texto ("Meta do dia 05/10/2026"); `valorantes`/`valordepois` e `pontosantes`/`pontosdepois` (vazio = não existia / foi apagada); `alteradopor`/`alteradoem`. Grava só o gatilho `registrar_mudanca_de_meta` (nas quatro tabelas de meta, por qualquer caminho), e só quando o valor ou os pontos mudam. **Nunca muda nem se apaga.** Só o master lê; aparece na lista dos Estornos (`estornos_da_conta`, tipo "meta alterada").

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
> **O nome engana.** "Loja" aqui é a **loja de recompensas** (onde se trocam pontos), nome herdado do sistema antigo (`ProdutosLoja`). O prêmio vale para a **conta inteira**: não tem `lojaid`, e o `estoquedisponivel` é um só para todas as lojas. Por isso "editar catálogo de prêmios" não é delegável a gerente de loja (decisão de 29/09/2026). Conferido no mesmo dia: é a única tabela com "loja" no nome sem `lojaid`.

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
| sistema | varchar(40) | **Código interno.** Vazio nas tarefas criadas pelo master. Nas 6 que o sistema cria para cada conta diz qual é: `feedback_diario`, `leitura`, `pontos_meta`, `nota_fiscal`, `modelo_agendamento`, `guardar_mercadoria`. Único por conta. **Desde 28/09/2026 elas são tarefas comuns** (editáveis, desativáveis, atribuíveis à mão); o código **nunca muda** e o navegador não cria tarefa com código (gatilho `tarefas_protege_codigo`). **As rotinas acham a tarefa pelo código, nunca pelo nome:** `criar_agendamento` → `modelo_agendamento`; `publicar_comunicado` → `leitura` (pelo id em `configuracoes.TAREFA_ID_LEITURA`), só o padrão de pontos. As outras quatro não são usadas por rotina nenhuma. Tarefa desativada ou apagada: a rotina grava aviso `rotina_sem_tarefa` em `avisossistema` (Início e Saúde). A tela mantém a lista em `src/tarefas/rotinas.ts` |
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
| funcionarioresponsavelid | integer | → funcionarios.funcionarioid |
| horariodisparo | time |  |
| dataaceite | timestamptz |  |
| datainiciovigencia | date |  |
| datafimvigencia | date |  |
| agendamentoid | integer |  |
| dataagendamento | timestamptz |  |
| descricaooverride | text |  |
| origematribuicaoid | integer | → tarefasatribuidas.atribuicaoid |
| criadaem | timestamptz | **29/09/2026.** Quando a atribuição foi gravada. Gravada pelo banco (gatilho), ninguém reescreve. Vazia nas de antes dessa data |
| encerradaem | timestamptz | **29/09/2026.** Quando `datafimvigencia` foi preenchida. Gravada pelo banco; a foto da fila usa para saber se a atribuição ainda valia no fim do dia |
| compartilhada | boolean | padrão false. **Etapa 1.12 B1a.** Tarefa atribuída a várias pessoas: uma tarefa só, sem dono, e a lista de quem pode pegar está em `tarefascandidatos`. A primeira que pega ganha uma cópia no próprio nome (`origematribuicaoid` aponta para esta) |


---

## configuracoes
Tabela **nova**, não existia no SQL Server. Guarda os parâmetros que ficavam fixos no `legado/config.py`.

| Coluna | Tipo | Obs |
|---|---|---|
| chave | varchar(100) | obrigatório; chave primária **(contaid, chave)** |
| valor | text |  |
| descricao | text |  |
| atualizadoem | timestamptz | obrigatório; padrão now() |

O navegador só lê; altera por `alterar_configuracao` (só o master; os `TAREFA_*` não). Um gatilho valida todo caminho: taxa numérica > 0 e ≤ 10; `PONTOS_BONUS_*` inteiro de 0 a 10.000; `MAX_DIFERENCA_FOTO_SEGUNDOS` inteiro até 86.400; `DIAS_GUARDAR_FOTO_ENTREGA` inteiro de 90 a 3.650; `CONTATO_PRIVACIDADE` texto de até 200 letras; `HORARIO_*` no formato HH:MM.

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
| papel | varchar(20) | obrigatório; padrão 'master'. `master`, `gerente` (Etapa 1.14), `loja` (tablet) ou `colaborador` (celular) |
| lojaid | integer | só no papel `loja`; → lojas (junto com contaid) |
| funcionarioid | integer | só no papel `colaborador`; → funcionarios (junto com contaid) |
| criadopor | uuid | → auth.users. Quem criou o acesso |
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

## acessoslojaeventos (Etapa 1.12 B1) — histórico do acesso do tablet
Tabela **nova**, **nível loja**. Quando o acesso do tablet foi criado e cada vez que uma senha nova foi gerada.

| Coluna | Tipo | Obs |
|---|---|---|
| eventoid | integer | ID automático |
| contaid | integer | obrigatório; → contas; padrão `minha_conta()` |
| lojaid | integer | obrigatório; → lojas (junto com contaid) |
| evento | varchar(12) | `criado`, `senha_nova` (sorteada pelo sistema) ou `senha_amao` (digitada pelo gestor) |
| userid | uuid | → auth.users. Quem fez |
| em | timestamptz | padrão now() |

**Só o master lê** (a policy exige `sou_master()`): nem o gerente, nem o tablet, nem o administrador geral. Entra por `registrar_evento_acesso_loja`, que é interna (recebe a conta).

A **senha do tablet não fica aqui nem em lugar nenhum**: o banco guarda só o resumo dela (PBKDF2 com sal, em `senhasgestor`). Não há como exibi-la de novo — quem perde usa "Gerar nova senha".

## tarefascandidatos (Etapa 1.12 B1a) — quem pode pegar a tarefa compartilhada
Tabela **nova**, **nível conta**. Sem linhas na missão da equipe: ali qualquer pessoa da loja pode pegar.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | obrigatório; → contas |
| atribuicaoid | integer | obrigatório; → tarefasatribuidas (junto com contaid) |
| funcionarioid | integer | obrigatório; → funcionarios (junto com contaid) |

Chave primária (`contaid`, `atribuicaoid`, `funcionarioid`). Entra por `atribuir_tarefa`.

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
| `rotinas_despachar(agora)` | **Interna, só o pg_cron.** A cada 5 min, para cada conta ativa: lista do dia, fechamento, conferência do livro e limpeza |
| `lista_do_dia_gerar(conta, dia, hoje, recuperado)` / `rotina_lista_do_dia` | **Internas.** Geram e ajustam a lista do dia; recuperam até 7 dias |
| `rotina_fechamento_mensal` / `fechamento_calcular` | **Internas.** Fechamento do mês anterior |
| `rotina_conferencia_livro` / `rotina_limpeza` | **Internas.** Conferência do livro (nunca corrige) e limpeza do registro |
| `ranking_mensal_da_conta(conta, ano, mes, loja, fim)` | Nota do mês (security invoker, filtra a conta): dias com lista usam a lista; os outros, a regra. `ranking_mensal` chama com a conta de quem está logado |
| `rodar_geracao_hoje()` | "Rodar agora" do master: gera ou ajusta a lista de hoje |
| `tarefas_de_folga_hoje(loja)` / `quem_trabalha_hoje(loja)` | Bloco de folga do Quadro |
| `passar_tarefa_de_folga(atribuicao, pessoa)` | Passa a tarefa de quem está de folga para quem trabalha hoje na mesma loja: tarefa única de hoje (`origematribuicaoid`), uma vez por dia |
| `refazer_fechamento(ano, mes, motivo)` | Só o master; nova versão, a anterior fica guardada |
| `rotinas_resumo_admin()` | Só o admin geral: ok/erro/diferença por conta e rotina, sem texto |
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


## Telegram: retirado em 04/10/2026

O sistema não usa Telegram (decisão do Wisley). Saíram as tabelas `telegramvinculos`, `telegramconvites`, `mensagensfila`, `mensagensrotinas`, `usomensagens`, `grupos` e `funcionariosgrupos`, o schema `bot` (`updates`, `tentativas`, `estados`, `contaativa`), as colunas `funcionarios.chatidtelegram`, `funcionarioslojas.validador`, `entregas.avisochatid`, `entregas.fileidtelegram`, `documentos.telegramfileidfoto`, `notasfiscais.fileidtelegram`, `tarefasatribuidas.grupoid` e `tarefasatribuidas.statustarefagrupo`, e as funções do bot (migração 20261004100000). Os dados saíram junto: o identificador de Telegram das pessoas é dado pessoal sem finalidade sem o bot. A seção 119 do teste de isolamento reprova se algo disso voltar.

**Ficam** de propósito: `avisossistema` (os avisos do Início; `marcar_aviso_lido`); as colunas de canal (`entregas.canalenvio`/`canalvalidacao`, `documentosacessos.canal`, `missoesaceites.canal`), em que linhas antigas dizem `telegram` (histórico); `entregas.validadorfuncionarioid` (sai na fatia 2); `bot_contexto_confiavel`, `conta_do_bot` e `funcionario_do_bot` (**não saem**: são o contexto do servidor, ver abaixo); e as 9 configurações que só o bot lia (`HORARIO_DELEGACAO_FOLGA`, `HORARIO_LEMBRETE_COMUNICADOS`, `HORARIO_LEMBRETE_DIARIO_AMANHA`, `HORARIO_LEMBRETE_HOJE`, `HORARIO_LEMBRETE_SEMANAL`, `HORARIO_SILENCIO_INICIO`, `HORARIO_SILENCIO_FIM`, `MAX_MENSAGENS_AUTOMATICAS_DIA`, `MAX_TAREFAS_FOLGA_POR_PESSOA`), com o histórico delas (`configuracoeshistorico` aponta para elas, ON DELETE RESTRICT, de propósito). **Desde 05/10/2026 a `descricao` delas diz "OBSOLETA"**: nada lê, nada mostra, conta nova não recebe, e **não se apagam** (decisão do Wisley: o histórico é auditoria).

Saíram em 05/10/2026 (migração 20261005100000): o intervalo da jornada (`jornadas.pausainicio/pausafim`) e `bot_falta_feedback_ontem` (o aviso "Você tem um feedback de ontem para responder" do aplicativo, sem onde responder).

### O contexto do SERVIDOR (o nome "bot" é histórico)
Não é tabela: é como o banco reconhece uma chamada do **servidor** do STGame. Corrigido em 05/10/2026 (antes, este dicionário dizia que era do bot e sairia).
- `bot_contexto_confiavel()`: verdadeira quando a chamada vem com a **chave de servidor** (`service_role`) ou é uma rotina do pg_cron (`postgres` sem papel). Quem está logado e o visitante nunca.
- `entrar_na_visao(conta, pessoa, loja, canal)`: a **única** que liga o contexto (`stgame.bot_conta`, `stgame.bot_funcionario`, `stgame.bot_canal`, `stgame.visao_loja`), só valendo na transação. Canais: `tablet` e `colaborador`. Chamada pelas funções `visao_*`, por `eu_*` que gravam e por `politica_dar_ciencia` (tablet e celular do colaborador).
- `conta_do_bot()` / `funcionario_do_bot()`: leem o contexto, só quando ele é confiável. `minha_conta`, `minha_conta_editavel` e `registrar_ciencia_documento` usam.
- 105 funções vivas usam alguma das três (tablet, celular, TV, acesso por código/PIN/senha, apagamento de fotos, rotinas).
- **Trava:** a seção 121 do teste de isolamento reprova se alguém além da chave de servidor puder executar as quatro, se outra função ligar o contexto ou se a lista de canais mudar (o WhatsApp, opção (a) de 05/10/2026, usa o token do próprio usuário e não entra nela).

### avisosdispensados (05/10/2026)
O **X** dos avisos do topo do Início, **nível conta, por pessoa**. Fechar é por **fato**: a chave diz o aviso e aquilo a que ele se refere, e o aviso do dia seguinte (ou de outra loja, ou com outro número) tem outra chave e volta.

| Coluna | Tipo | Obs |
|---|---|---|
| dispensaid | integer | ID automático; chave primária |
| contaid | integer | obrigatório; padrão `minha_conta()`; → contas |
| userid | uuid | quem fechou; → auth.users (apagado o login, vai junto) |
| chave | text | o fato, ex.: `vendaontem\|<loja>\|<dia>`, `livro\|<dia>`, `agenda\|<dia>\|<n>`, `comunicados\|<dia>\|<c>\|<p>`. Formato conferido pelo banco, até 200 letras |
| dispensadoem | timestamptz | |

Única por (contaid, userid, chave). Cada um lê só as suas linhas (regra `userid = auth.uid()`); ninguém grava direto. `dispensar_avisos(chaves)` (até 50; apaga as dele com mais de 60 dias), `reexibir_avisos(chaves)` (o "mostrar": apaga só as dele) e `avisos_dispensados()`. Master e gerente. A faixa vermelha do /admin não tem X.

### avisossistema
Avisos dentro do sistema, mostrados no Início. Colunas: `avisoid`, `contaid`, `tipo`, `texto` (300), `criadoem`, `lidoem` (preenchido por `marcar_aviso_lido`).

### missoesaceites
Quem pegou cada tarefa, em que dia e por onde. Desde a **Etapa 1.12 B1a** vale para os três casos: missão, tarefa compartilhada e tarefa com dono (entregar sem ter pegado grava o aceite).

Chave primária `aceiteid`; o que garante **o primeiro que pegar** é o índice único `(contaid, atribuicaoid, dia) WHERE revogadoem IS NULL`: dois toques no mesmo instante só deixam um passar, e o aceite **revogado** libera o dia sem apagar o histórico.

Colunas: `funcionarioid`, `novaatribuicaoid` (a cópia criada para quem pegou; vazia na tarefa com dono), `canal` (`app`/`telegram`/`tablet`), `aceitoem`, `revogadoem`, `revogadopor`, `motivorevogacao`.

### Missão da equipe e tarefa compartilhada
Não são tabelas novas: são linhas de **`tarefasatribuidas` sem `funcionarioid`**.
- **Missão da equipe:** com `horariodisparo` e sem candidatos — qualquer pessoa da loja que trabalha hoje pode pegar.
- **Tarefa compartilhada (Etapa 1.12 B1a):** `compartilhada = true` e a lista de quem pode pegar em `tarefascandidatos`.

Quem pega ganha uma tarefa `Unica` de hoje com `origematribuicaoid` apontando para a original. Desde a **Etapa 1.12 B1a**, ela conta nos **pontos possíveis de quem pegou** e a entrega aprovada conta na **confiabilidade** dela (antes era só esforço extra). Quem estava atribuído e não pegou fica neutro; o que ninguém pegou não entra na nota de ninguém. A tarefa recebida de quem está de folga continua sendo esforço extra: não tem aceite.

Entra por `pegar_tarefa(atribuicao, funcionario)` (`pegar_missao` é um atalho para ela) e sai por `revogar_aceite(atribuicao, dia, motivo)`.

### Configurações novas
`MINUTOS_RODIZIO_ACEITE` (10; 0 desliga) — rodízio no aceite: minutos que quem pegou a última tarefa disputada da loja espera antes de pegar outra; `MINUTOS_TAREFA_PARADA` (30) — a partir de quantos minutos o tablet marca a tarefa como parada; `HORARIO_SILENCIO_INICIO` (22:00) e `HORARIO_SILENCIO_FIM` (07:00) — o silêncio **não vale dentro do turno da pessoa**; `MAX_MENSAGENS_AUTOMATICAS_DIA` (8); `MAX_TAREFAS_FOLGA_POR_PESSOA` (3).

### Funções (todas internas ou só para o servidor)
`jornada_da_pessoa(conta, pessoa, dia)` (o turno que começa no dia; entende o turno da noite), `bot_janela(conta, pessoa, agora)` (pode mandar agora? senão, quando), `no_silencio`, `bot_enviadas_hoje`, `rotina_mensagens(conta, agora)` (chamada pelo despachante a cada 5 minutos), `bot_texto_rotina` (monta a mensagem na hora de enviar; devolve vazio quando não faz mais sentido), `bot_resumo_ausencia`, `bot_marcar_bloqueio`, `bot_visto(chat)`, `bot_pegar_folga` e `bot_pegar_missao` (grupo da equipe). Para as telas: `definir_horario_equipe(pessoas[], entrada, saida)` e `definir_rotina_mensagem(loja, rotina, ativo)`.

## contas — campos de 27/09/2026
| Coluna | Tipo | Obs |
|---|---|---|
| nome | varchar(200) | **razão social**: só em contrato e cobrança |
| nomefantasia | varchar(120) | **o que aparece no produto** (cabeçalho do gestor, celular, folha de acesso, recibos, Telegram). Quem já existia começou igual ao `nome` |
| responsavel | varchar(120) | nome do responsável |
| cnpj | varchar(20) | só os 14 dígitos, conferidos; vazio aceito; repetido, não |
| redeid | integer | → redes (sem rede = vazio) |
| codigo | varchar(30) | código da empresa. **Novo ou trocado:** apelido de 4 a 20 letras minúsculas e números, sugerido do nome fantasia; nunca sequencial. Os antigos continuam como estavam |

## codigosantigos (27/09/2026)
Código de empresa que foi trocado. **Abre a empresa por 30 dias** (os PDFs impressos e o link no mural continuam funcionando) e fica **reservado para ela para sempre**, para um papel velho nunca levar a outra empresa. Só o admin geral lê.

## redes (27/09/2026) — tabela da PLATAFORMA
Redes de franquia. Não tem `contaid`: reúne clientes, não pertence a nenhum. Só o admin geral lê e escreve.

| Coluna | Tipo | Obs |
|---|---|---|
| redeid | integer | ID automático |
| nome | varchar(120) | único (sem diferenciar maiúscula) |
| responsavel, endereco, telefone, email | texto | contato |
| lojascontratadas | integer | o número **contratado**, digitado. O real (lojas ativas dos clientes da rede) é calculado em `redes_admin()` |
| logocaminho | text | logotipo no bucket privado `logos-redes` (PNG/JPG/WEBP, até 512 KB). Só o servidor grava |

Rede com cliente ligado não se apaga (o banco diz quantos são).

## chamadasdoservidor (30/09/2026) — tabela da PLATAFORMA
Cada vez que o banco chamou (ou **tentou** chamar) uma função do servidor, e o que ela respondeu. Hoje só `expurgo-fotos` (o apagamento das fotos vencidas). Não tem `contaid`: uma chamada apaga fotos de todas as contas. Ninguém lê pelo navegador; a /saude lê pela chave de servidor. Guarda 90 dias.

| Coluna | Tipo | Obs |
|---|---|---|
| chamadaid | integer | ID automático |
| funcao | text | `expurgo-fotos` |
| requestid | bigint | o número do pedido no `pg_net`; **vazio = não chamou** (o motivo fica em `erro`: falta segredo, cofre ou pg_net desligado) |
| pedidaem | timestamptz | quando |
| respondidaem, status, apagados, erro | | a resposta, copiada do `net._http_response` pelo despachante (a cada 5 minutos) antes de o `pg_net` jogar fora (ele guarda 6 horas). 200 = apagou `apagados`; 401 = segredo do cofre diferente do da função; 404 = função não publicada. Sem resposta em 7 horas: registrado como "sem resposta" |

## anexosadmin (27/09/2026)
Contratos da administração, de um cliente **ou** de uma rede. **Documento sigiloso**: o arquivo fica no bucket privado `administracao`, sem regra de acesso para ninguém (só o servidor, depois de conferir que é o admin geral); o link de abertura vale 5 minutos. PDF ou imagem, até 10 MB. Guarda quem subiu e quando.

**Remover (27/09/2026):** o arquivo sai de verdade do armazenamento (cliente errado, ou exclusão pedida pelo cliente — LGPD). Fica o registro: `removidoem` / `removidopor`, tipo, tamanho e datas; o **nome do arquivo sai junto** (ele pode carregar o nome de outra empresa ou de uma pessoa). Rede com anexo ativo não se apaga; apagada a rede, o registro dos anexos dela (já removidos) vai junto.

## jornadaslojas (30/09/2026)
Em que lojas cada jornada vale, como `tarefaslojas`. Grava só pela `salvar_jornada` (ninguém escreve direto). Regras garantidas pelo banco, por qualquer caminho:
- pessoa só se vincula (`funcionarios.jornadaid`) a jornada com **uma loja em comum** (gatilho `funcionarios_jornada_na_loja`); e ela não sai da única loja em comum ficando em outras (`funcionarioslojas_jornada_na_loja`); sair de todas (saída da empresa) passa;
- loja com gente dela vinculada não sai da jornada (`jornadaslojas_loja_com_gente`); a mensagem diz quantas pessoas e de qual loja.
As jornadas que existiam em 30/09/2026 ganharam **todas as lojas da conta** (ativas ou não). Loja criada depois não entra sozinha: o master a marca.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid | integer | conta |
| jornadaid | integer | FK (contaid, jornadaid) → jornadas; apagar a jornada leva as lojas junto |
| lojaid | integer | FK (contaid, lojaid) → lojas |

## jornadas e jornadasdias (27/09/2026)
Horários de **expediente** com nome ("Balcão manhã"), para o sistema saber **quando enviar tarefas e avisos**. **Não é controle de jornada** (CLAUDE.md): não há total de horas, carga semanal, banco de horas, marcação de entrada e saída, nem comparação entre previsto e feito.

| jornadas | Tipo | Obs |
|---|---|---|
| nome | varchar(80) | único na conta |
| observacao, ativa | | jornada inativa não aparece para vincular; com gente vinculada, não se desativa nem se apaga |

| jornadasdias | Tipo | Obs |
|---|---|---|
| diasemana | smallint | 1 = domingo ... 7 = sábado (igual a `funcionarios.diadefolga`) |
| entrada / saida | time | saída menor que a entrada = turno da noite. Dia sem linha = sem horário naquele dia |

`funcionarios.jornadaid` (vazio = sem jornada: não recebe as mensagens do dia) substituiu `horarionotificacao` e `horariosaida`, que foram migradas e **apagadas**. A **folga** continua sendo da pessoa. Quem lê: `jornada_da_pessoa` e `jornadas_da_tela`. **O intervalo de silêncio (`pausainicio`/`pausafim`) saiu em 05/10/2026**: sem o bot, não fazia nada (seção 120 do teste de isolamento). Quem grava: `salvar_jornada` (tudo ou nada) e `vincular_jornada`.

## intervalosdomapa (27/09/2026)
O **intervalo de PLANEJAMENTO** do Mapa da jornada ("Intervalo (planejamento, não afeta o sistema)"), **um por pessoa e por dia da semana** (desde 29/09/2026; antes era um só para todos os dias). Serve **só para enxergar e imprimir a escala**.

| Coluna | Tipo | Obs |
|---|---|---|
| contaid, funcionarioid, diasemana | integer | chave (diasemana: 1 = domingo ... 7 = sábado); → funcionarios (junto com contaid). Apagada a pessoa, vai junto |
| inicio / fim | time | fim menor que o começo = cruza a meia-noite |
| atualizadoem | timestamptz | |

**Não confundir com o antigo intervalo da jornada** (o silêncio do bot, que saiu em 05/10/2026). Este aqui **fica** e **não afeta nada**: não cala o bot, não mexe em tarefa, liberação, nota nem rodízio. **Só duas funções tocam a tabela:** `mapa_da_jornada` (lê, junto com a jornada e a folga, uma loja num dia da semana; `mapa_da_semana` a chama para os sete dias numa consulta só) e `salvar_intervalo_do_mapa(pessoa, dia, início, fim)` (grava, só o master). A seção 75 do teste de isolamento e `src/jornada/mapa-catraca.test.ts` reprovam qualquer outra leitura.
