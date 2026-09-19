# Dicionário do Banco — Game GB (Supabase)

> Estrutura extraída do backup `banco_teste.bak`. **Banco limpo: nenhum dado foi importado.** Nomes no Postgres = nomes originais em **minúsculas** (ex.: `FuncionarioID` → `funcionarioid`). IDs começam do 1.

| Tabela | Chave | Referencia |
|---|---|---|
| `agendamentos` | agendamentoid | funcionarios |
| `categoriasproduto` | categoriaid |  |
| `configuracoesescala` | configid |  |
| `configuracoessetores` |  |  |
| `conquistas` | conquistaid |  |
| `conquistasfuncionarios` | conquistafuncionarioid | conquistas, funcionarios |
| `contagensestoque` | contagemid | funcionarios |
| `denunciasanonimas` | denunciaid |  |
| `documentos` | documentoid | funcionarios |
| `documentosassinaturas` | assinaturaid | documentos, funcionarios |
| `documentospessoais` | documentoid | funcionarios |
| `documentospessoaisciencia` | cienciaid | documentospessoais, funcionarios |
| `entregas` | entregaid | funcionarios, tarefas |
| `escaladiaria` | escalaid | freelancers, funcionarios, posicoesloja |
| `feedbacksolicitacoes` | solicitacaoid | funcionarios |
| `feedbacks` | feedbackid | funcionarios |
| `fornecedores` | fornecedorid |  |
| `freelancers` | freelancerid |  |
| `funcionarios` | funcionarioid | posicoesloja |
| `funcionariosgrupos` |  | funcionarios, grupos |
| `grupos` | grupoid |  |
| `historicoranking` | historicoid | funcionarios |
| `itenscontagemestoque` | itemcontagemid | contagensestoque, produtosestoque |
| `itensnotafiscalentrada` | itemnotaid | notasfiscaisentrada, produtosfornecedor |
| `lucromensalhistorico` | historicoid |  |
| `metasdiariasapuracoes` | apuracaoid | funcionarios, metasprincipais |
| `metasdiariasinstancias` | metainstanciaid |  |
| `metasdiariasmodelos` |  |  |
| `metasprincipais` | metaprincipalid |  |
| `notasfiscais` | notafiscalid | funcionarios |
| `notasfiscaisentrada` | notaid | fornecedores |
| `onboardingstatus` |  | funcionarios |
| `picodiario` |  |  |
| `posicoesloja` | posicaoid |  |
| `produtosestoque` | produtoid |  |
| `produtosfornecedor` | produtofornecedorid | fornecedores, produtosestoque |
| `produtosloja` | produtoid |  |
| `resgates` | resgateid | funcionarios, produtosloja |
| `solicitacoesinternas` | solicitacaoid | funcionarios |
| `tarefas` | tarefaid |  |
| `tarefasatribuidas` | atribuicaoid | funcionarios, grupos, tarefas, tarefasatribuidas |
| `usuariosadmin` | usuarioid |  |

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
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| observacoes | text |  |
| datacriacao | timestamptz | obrigatório; padrão now() |
| msgcriacaoenviada | integer | padrão 0 |
| msgconfirmacaoenviada | integer | padrão 0 |
| msgposvendaenviada | integer | padrão 0 |

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
| setor | varchar(50) | obrigatório |
| descricaopadrao | text |  |

## conquistas
| Coluna | Tipo | Obs |
|---|---|---|
| conquistaid | integer | ID automático; obrigatório |
| nome | varchar(100) | obrigatório |
| descricao | varchar(255) | obrigatório |
| icone | varchar(10) |  |
| criteriotipo | varchar(50) | obrigatório |
| criteriovalor | integer | obrigatório |
| pontosbonus | integer | padrão 0 |

## conquistasfuncionarios
| Coluna | Tipo | Obs |
|---|---|---|
| conquistafuncionarioid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| conquistaid | integer | obrigatório; → conquistas.conquistaid |
| dataconquista | timestamptz | padrão now() |

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
| mensagem | text | obrigatório |
| dataregistro | timestamptz | padrão now() |
| status | varchar(50) | padrão 'Pendente' |

## documentos
| Coluna | Tipo | Obs |
|---|---|---|
| documentoid | integer | ID automático; obrigatório |
| titulo | varchar(255) | obrigatório |
| conteudo | text | obrigatório |
| pontosporciencia | integer | obrigatório; padrão 0 |
| datacriacao | timestamptz | padrão now() |
| funcionariocriadorid | integer | → funcionarios.funcionarioid |
| telegramfileidfoto | varchar(255) |  |

## documentosassinaturas
| Coluna | Tipo | Obs |
|---|---|---|
| assinaturaid | integer | ID automático; obrigatório |
| documentoid | integer | obrigatório; → documentos.documentoid |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| statusassinatura | varchar(50) | obrigatório; padrão 'Pendente' |
| dataenvio | timestamptz | padrão now() |
| dataciencia | timestamptz |  |

## documentospessoais
| Coluna | Tipo | Obs |
|---|---|---|
| documentoid | integer | ID automático; obrigatório |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| tipodocumento | varchar(100) | obrigatório |
| mesano | date | obrigatório |
| caminhoarquivo | varchar(500) | obrigatório |
| dataupload | timestamptz | padrão now() |

## documentospessoaisciencia
| Coluna | Tipo | Obs |
|---|---|---|
| cienciaid | integer | ID automático; obrigatório |
| documentoid | integer | obrigatório; → documentospessoais.documentoid |
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| status | varchar(50) | obrigatório; padrão 'Pendente' |
| dataenvio | timestamptz |  |
| dataciencia | timestamptz |  |

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
| notadia | integer | obrigatório |
| comentario | varchar(500) |  |

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
| pontostotal | integer | padrão 0 |
| horarionotificacao | time | padrão '08:00' |
| diadefolga | integer | obrigatório; padrão 0 |
| saldopontos | integer | obrigatório; padrão 0 |
| verificadorcpf | varchar(3) |  |
| senhahash | varchar(256) |  |
| isgestor | boolean | padrão false |
| posicaopadraoid | integer | → posicoesloja.posicaoid |
| nivelacesso | varchar(50) | padrão 'Funcionario' |
| cpf | varchar(14) |  |
| telefonewhatsapp | varchar(20) |  |
| setor | varchar(50) |  |
| domingofolgamensal | integer | padrão 0 |
| datainicioafastamento | date |  |
| datafimafastamento | date |  |

## funcionariosgrupos
| Coluna | Tipo | Obs |
|---|---|---|
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| grupoid | integer | obrigatório; → grupos.grupoid |

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
| funcionarioid_lancamento | integer | → funcionarios.funcionarioid |
| pontosmetadiariaganhos | integer | padrão 0 |

## metasdiariasinstancias
| Coluna | Tipo | Obs |
|---|---|---|
| metainstanciaid | integer | ID automático; obrigatório |
| metamodeloid | integer |  |
| data | date | obrigatório |
| valormeta | numeric(10,2) | obrigatório |
| valoratingido | numeric(10,2) |  |
| status | varchar(20) | padrão 'Pendente' |

## metasdiariasmodelos
| Coluna | Tipo | Obs |
|---|---|---|
| diasemanaid | integer | obrigatório |
| nomedia | varchar(50) | obrigatório |
| valormeta | numeric(18,2) | obrigatório |
| pontospremio | integer | obrigatório |

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
| setoralvo | varchar(100) |  |
| status | varchar(50) | padrão 'Ativa' |

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
| Coluna | Tipo | Obs |
|---|---|---|
| funcionarioid | integer | obrigatório; → funcionarios.funcionarioid |
| statusworkflow | varchar(50) | obrigatório; padrão 'Pendente' |
| ultimaetapa | varchar(100) |  |
| escolaridade | varchar(50) |  |
| estadocivil | varchar(50) |  |
| qtdfilhos | integer | padrão 0 |
| dadosfilhos | text |  |
| rg_fileid | varchar(255) |  |
| cpf_fileid | varchar(255) |  |
| ctps_fileid | varchar(255) |  |
| tituloeleitor_fileid | varchar(255) |  |
| datacasamento | varchar(10) |  |
| nomeconjugue | varchar(100) |  |
| cpfconjugue | varchar(14) |  |
| dataadmissional | timestamptz |  |
| statusadmissional | varchar(50) | obrigatório; padrão 'Pendente' |

## picodiario
| Coluna | Tipo | Obs |
|---|---|---|
| diasemanaid | integer | obrigatório |
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
| status | varchar(20) | padrão 'Pendente' |
| motivorecusa | text |  |
| dataconclusao | timestamptz |  |

## tarefas
| Coluna | Tipo | Obs |
|---|---|---|
| tarefaid | integer | ID automático; obrigatório |
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

## usuariosadmin
| Coluna | Tipo | Obs |
|---|---|---|
| usuarioid | integer | ID automático; obrigatório |
| login | varchar(50) | obrigatório |
| senhahash | varchar(64) | obrigatório |
| nomeexibicao | varchar(100) |  |
| nivelacesso | integer | padrão 1 |
