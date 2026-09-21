export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      agendamentos: {
        Row: {
          agendamentoid: number
          contaid: number
          cpfcliente: string | null
          datacriacao: string
          dataevento: string
          funcionarioid: number
          lojaid: number
          msgconfirmacaoenviada: number | null
          msgcriacaoenviada: number | null
          msgposvendaenviada: number | null
          nomecliente: string
          observacoes: string | null
          statusagendamento: string
          statuspagamento: string
          telefonecliente: string | null
          tipoevento: string
        }
        Insert: {
          agendamentoid?: number
          contaid?: number
          cpfcliente?: string | null
          datacriacao?: string
          dataevento: string
          funcionarioid: number
          lojaid: number
          msgconfirmacaoenviada?: number | null
          msgcriacaoenviada?: number | null
          msgposvendaenviada?: number | null
          nomecliente: string
          observacoes?: string | null
          statusagendamento?: string
          statuspagamento?: string
          telefonecliente?: string | null
          tipoevento: string
        }
        Update: {
          agendamentoid?: number
          contaid?: number
          cpfcliente?: string | null
          datacriacao?: string
          dataevento?: string
          funcionarioid?: number
          lojaid?: number
          msgconfirmacaoenviada?: number | null
          msgcriacaoenviada?: number | null
          msgposvendaenviada?: number | null
          nomecliente?: string
          observacoes?: string | null
          statusagendamento?: string
          statuspagamento?: string
          telefonecliente?: string | null
          tipoevento?: string
        }
        Relationships: [
          {
            foreignKeyName: "agendamentos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "agendamentos_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "agendamentos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      categoriasproduto: {
        Row: {
          categoriaid: number
          contaid: number
          nomecategoria: string
        }
        Insert: {
          categoriaid?: number
          contaid?: number
          nomecategoria: string
        }
        Update: {
          categoriaid?: number
          contaid?: number
          nomecategoria?: string
        }
        Relationships: [
          {
            foreignKeyName: "categoriasproduto_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      configuracoes: {
        Row: {
          atualizadoem: string
          chave: string
          contaid: number
          descricao: string | null
          valor: string | null
        }
        Insert: {
          atualizadoem?: string
          chave: string
          contaid?: number
          descricao?: string | null
          valor?: string | null
        }
        Update: {
          atualizadoem?: string
          chave?: string
          contaid?: number
          descricao?: string | null
          valor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "configuracoes_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      configuracoesescala: {
        Row: {
          configid: number
          contaid: number
          dataatualizacao: string | null
          duracaointervalo: number
          duracaojornadapadrao: number | null
          lojaid: number
          maxhorassempausa: number
        }
        Insert: {
          configid?: number
          contaid?: number
          dataatualizacao?: string | null
          duracaointervalo: number
          duracaojornadapadrao?: number | null
          lojaid: number
          maxhorassempausa: number
        }
        Update: {
          configid?: number
          contaid?: number
          dataatualizacao?: string | null
          duracaointervalo?: number
          duracaojornadapadrao?: number | null
          lojaid?: number
          maxhorassempausa?: number
        }
        Relationships: [
          {
            foreignKeyName: "configuracoesescala_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "configuracoesescala_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      configuracoessetores: {
        Row: {
          contaid: number
          descricaopadrao: string | null
          setor: string
        }
        Insert: {
          contaid?: number
          descricaopadrao?: string | null
          setor: string
        }
        Update: {
          contaid?: number
          descricaopadrao?: string | null
          setor?: string
        }
        Relationships: [
          {
            foreignKeyName: "configuracoessetores_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      conquistas: {
        Row: {
          conquistaid: number
          contaid: number
          criteriotipo: string
          criteriovalor: number
          descricao: string
          icone: string | null
          nome: string
          pontosbonus: number | null
        }
        Insert: {
          conquistaid?: number
          contaid?: number
          criteriotipo: string
          criteriovalor: number
          descricao: string
          icone?: string | null
          nome: string
          pontosbonus?: number | null
        }
        Update: {
          conquistaid?: number
          contaid?: number
          criteriotipo?: string
          criteriovalor?: number
          descricao?: string
          icone?: string | null
          nome?: string
          pontosbonus?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "conquistas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      conquistasfuncionarios: {
        Row: {
          conquistafuncionarioid: number
          conquistaid: number
          contaid: number
          dataconquista: string | null
          funcionarioid: number
        }
        Insert: {
          conquistafuncionarioid?: number
          conquistaid: number
          contaid?: number
          dataconquista?: string | null
          funcionarioid: number
        }
        Update: {
          conquistafuncionarioid?: number
          conquistaid?: number
          contaid?: number
          dataconquista?: string | null
          funcionarioid?: number
        }
        Relationships: [
          {
            foreignKeyName: "conquistasfuncionarios_conquistaid_fk"
            columns: ["contaid", "conquistaid"]
            isOneToOne: false
            referencedRelation: "conquistas"
            referencedColumns: ["contaid", "conquistaid"]
          },
          {
            foreignKeyName: "conquistasfuncionarios_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "conquistasfuncionarios_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      contagensestoque: {
        Row: {
          contagemid: number
          contaid: number
          datacontagem: string
          dataregistro: string | null
          funcionarioid: number
          lojaid: number
          nomecontagem: string | null
        }
        Insert: {
          contagemid?: number
          contaid?: number
          datacontagem: string
          dataregistro?: string | null
          funcionarioid: number
          lojaid: number
          nomecontagem?: string | null
        }
        Update: {
          contagemid?: number
          contaid?: number
          datacontagem?: string
          dataregistro?: string | null
          funcionarioid?: number
          lojaid?: number
          nomecontagem?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contagensestoque_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "contagensestoque_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "contagensestoque_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      contas: {
        Row: {
          cidade: string | null
          contaid: number
          criadoem: string
          email: string
          limitelojas: number
          nome: string
          observacoes: string | null
          status: string
          telefone: string | null
        }
        Insert: {
          cidade?: string | null
          contaid?: number
          criadoem?: string
          email: string
          limitelojas?: number
          nome: string
          observacoes?: string | null
          status?: string
          telefone?: string | null
        }
        Update: {
          cidade?: string | null
          contaid?: number
          criadoem?: string
          email?: string
          limitelojas?: number
          nome?: string
          observacoes?: string | null
          status?: string
          telefone?: string | null
        }
        Relationships: []
      }
      contasusuarios: {
        Row: {
          contaid: number
          criadoem: string
          papel: string
          userid: string
        }
        Insert: {
          contaid: number
          criadoem?: string
          papel?: string
          userid: string
        }
        Update: {
          contaid?: number
          criadoem?: string
          papel?: string
          userid?: string
        }
        Relationships: []
      }
      denunciasanonimas: {
        Row: {
          contaid: number
          dataregistro: string | null
          denunciaid: number
          mensagem: string
          status: string | null
        }
        Insert: {
          contaid?: number
          dataregistro?: string | null
          denunciaid?: number
          mensagem: string
          status?: string | null
        }
        Update: {
          contaid?: number
          dataregistro?: string | null
          denunciaid?: number
          mensagem?: string
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "denunciasanonimas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      documentos: {
        Row: {
          contaid: number
          conteudo: string
          datacriacao: string | null
          documentoid: number
          funcionariocriadorid: number | null
          pontosporciencia: number
          telegramfileidfoto: string | null
          titulo: string
        }
        Insert: {
          contaid?: number
          conteudo: string
          datacriacao?: string | null
          documentoid?: number
          funcionariocriadorid?: number | null
          pontosporciencia?: number
          telegramfileidfoto?: string | null
          titulo: string
        }
        Update: {
          contaid?: number
          conteudo?: string
          datacriacao?: string | null
          documentoid?: number
          funcionariocriadorid?: number | null
          pontosporciencia?: number
          telegramfileidfoto?: string | null
          titulo?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "documentos_funcionariocriadorid_fk"
            columns: ["contaid", "funcionariocriadorid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      documentosassinaturas: {
        Row: {
          assinaturaid: number
          contaid: number
          dataciencia: string | null
          dataenvio: string | null
          documentoid: number
          funcionarioid: number
          statusassinatura: string
        }
        Insert: {
          assinaturaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid: number
          funcionarioid: number
          statusassinatura?: string
        }
        Update: {
          assinaturaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid?: number
          funcionarioid?: number
          statusassinatura?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentosassinaturas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "documentosassinaturas_documentoid_fk"
            columns: ["contaid", "documentoid"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["contaid", "documentoid"]
          },
          {
            foreignKeyName: "documentosassinaturas_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      documentospessoais: {
        Row: {
          caminhoarquivo: string
          contaid: number
          dataupload: string | null
          documentoid: number
          funcionarioid: number
          mesano: string
          tipodocumento: string
        }
        Insert: {
          caminhoarquivo: string
          contaid?: number
          dataupload?: string | null
          documentoid?: number
          funcionarioid: number
          mesano: string
          tipodocumento: string
        }
        Update: {
          caminhoarquivo?: string
          contaid?: number
          dataupload?: string | null
          documentoid?: number
          funcionarioid?: number
          mesano?: string
          tipodocumento?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentospessoais_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "documentospessoais_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      documentospessoaisciencia: {
        Row: {
          cienciaid: number
          contaid: number
          dataciencia: string | null
          dataenvio: string | null
          documentoid: number
          funcionarioid: number
          status: string
        }
        Insert: {
          cienciaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid: number
          funcionarioid: number
          status?: string
        }
        Update: {
          cienciaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid?: number
          funcionarioid?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentospessoaisciencia_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "documentospessoaisciencia_documentoid_fk"
            columns: ["contaid", "documentoid"]
            isOneToOne: false
            referencedRelation: "documentospessoais"
            referencedColumns: ["contaid", "documentoid"]
          },
          {
            foreignKeyName: "documentospessoaisciencia_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      entregas: {
        Row: {
          aprovadopor: string | null
          atribuicaoid: number | null
          contaid: number
          dataaprovacao: string | null
          dataenvio: string
          dataestorno: string | null
          datarecusa: string | null
          entregaid: number
          estornadopor: string | null
          fileidtelegram: string | null
          funcionarioid: number
          lojaid: number
          motivoestorno: string | null
          motivorecusa: string | null
          notificacaogestorenviada: boolean | null
          observacao: string | null
          pathfotoevidencia: string | null
          pontosganhos: number | null
          recusadopor: string | null
          statusvalidacao: string
          tarefaid: number
        }
        Insert: {
          aprovadopor?: string | null
          atribuicaoid?: number | null
          contaid?: number
          dataaprovacao?: string | null
          dataenvio?: string
          dataestorno?: string | null
          datarecusa?: string | null
          entregaid?: number
          estornadopor?: string | null
          fileidtelegram?: string | null
          funcionarioid: number
          lojaid: number
          motivoestorno?: string | null
          motivorecusa?: string | null
          notificacaogestorenviada?: boolean | null
          observacao?: string | null
          pathfotoevidencia?: string | null
          pontosganhos?: number | null
          recusadopor?: string | null
          statusvalidacao?: string
          tarefaid: number
        }
        Update: {
          aprovadopor?: string | null
          atribuicaoid?: number | null
          contaid?: number
          dataaprovacao?: string | null
          dataenvio?: string
          dataestorno?: string | null
          datarecusa?: string | null
          entregaid?: number
          estornadopor?: string | null
          fileidtelegram?: string | null
          funcionarioid?: number
          lojaid?: number
          motivoestorno?: string | null
          motivorecusa?: string | null
          notificacaogestorenviada?: boolean | null
          observacao?: string | null
          pathfotoevidencia?: string | null
          pontosganhos?: number | null
          recusadopor?: string | null
          statusvalidacao?: string
          tarefaid?: number
        }
        Relationships: [
          {
            foreignKeyName: "entregas_atribuicao_fk"
            columns: ["atribuicaoid", "tarefaid", "funcionarioid", "lojaid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: [
              "atribuicaoid",
              "tarefaid",
              "funcionarioid",
              "lojaid",
            ]
          },
          {
            foreignKeyName: "entregas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "entregas_funcionario_na_loja_fk"
            columns: ["funcionarioid", "lojaid"]
            isOneToOne: false
            referencedRelation: "funcionarioslojas"
            referencedColumns: ["funcionarioid", "lojaid"]
          },
          {
            foreignKeyName: "entregas_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "entregas_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "entregas_tarefaid_fk"
            columns: ["contaid", "tarefaid"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["contaid", "tarefaid"]
          },
        ]
      }
      escaladiaria: {
        Row: {
          contaid: number
          dataescala: string
          escalaid: number
          fimintervalo: string | null
          focododia: string | null
          freelancerid: number | null
          funcionarioid: number | null
          horarioentrada: string | null
          horariosaida: string | null
          iniciointervalo: string | null
          lojaid: number
          posicaoid: number
          statusconfirmacao: string | null
        }
        Insert: {
          contaid?: number
          dataescala: string
          escalaid?: number
          fimintervalo?: string | null
          focododia?: string | null
          freelancerid?: number | null
          funcionarioid?: number | null
          horarioentrada?: string | null
          horariosaida?: string | null
          iniciointervalo?: string | null
          lojaid: number
          posicaoid: number
          statusconfirmacao?: string | null
        }
        Update: {
          contaid?: number
          dataescala?: string
          escalaid?: number
          fimintervalo?: string | null
          focododia?: string | null
          freelancerid?: number | null
          funcionarioid?: number | null
          horarioentrada?: string | null
          horariosaida?: string | null
          iniciointervalo?: string | null
          lojaid?: number
          posicaoid?: number
          statusconfirmacao?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "escaladiaria_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "escaladiaria_freelancerid_fk"
            columns: ["contaid", "freelancerid"]
            isOneToOne: false
            referencedRelation: "freelancers"
            referencedColumns: ["contaid", "freelancerid"]
          },
          {
            foreignKeyName: "escaladiaria_funcionario_na_loja_fk"
            columns: ["funcionarioid", "lojaid"]
            isOneToOne: false
            referencedRelation: "funcionarioslojas"
            referencedColumns: ["funcionarioid", "lojaid"]
          },
          {
            foreignKeyName: "escaladiaria_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "escaladiaria_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "escaladiaria_posicaoid_fk"
            columns: ["contaid", "posicaoid"]
            isOneToOne: false
            referencedRelation: "posicoesloja"
            referencedColumns: ["contaid", "posicaoid"]
          },
        ]
      }
      feedbacks: {
        Row: {
          comentario: string | null
          contaid: number
          datafeedback: string
          feedbackid: number
          funcionarioid: number
          notadia: number
        }
        Insert: {
          comentario?: string | null
          contaid?: number
          datafeedback: string
          feedbackid?: number
          funcionarioid: number
          notadia: number
        }
        Update: {
          comentario?: string | null
          contaid?: number
          datafeedback?: string
          feedbackid?: number
          funcionarioid?: number
          notadia?: number
        }
        Relationships: [
          {
            foreignKeyName: "feedbacks_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "feedbacks_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      feedbacksolicitacoes: {
        Row: {
          contaid: number
          dataresposta: string | null
          datasolicitacao: string
          funcionarioid: number
          solicitacaoid: number
          status: string
          textoassunto: string
          textoresposta: string | null
        }
        Insert: {
          contaid?: number
          dataresposta?: string | null
          datasolicitacao?: string
          funcionarioid: number
          solicitacaoid?: number
          status?: string
          textoassunto: string
          textoresposta?: string | null
        }
        Update: {
          contaid?: number
          dataresposta?: string | null
          datasolicitacao?: string
          funcionarioid?: number
          solicitacaoid?: number
          status?: string
          textoassunto?: string
          textoresposta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "feedbacksolicitacoes_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "feedbacksolicitacoes_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      fornecedores: {
        Row: {
          cnpj: string
          contaid: number
          fornecedorid: number
          nomefantasia: string
        }
        Insert: {
          cnpj: string
          contaid?: number
          fornecedorid?: number
          nomefantasia: string
        }
        Update: {
          cnpj?: string
          contaid?: number
          fornecedorid?: number
          nomefantasia?: string
        }
        Relationships: [
          {
            foreignKeyName: "fornecedores_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      freelancers: {
        Row: {
          contaid: number
          freelancerid: number
          habilidadeprincipal: string | null
          nome: string
          telefone: string | null
        }
        Insert: {
          contaid?: number
          freelancerid?: number
          habilidadeprincipal?: string | null
          nome: string
          telefone?: string | null
        }
        Update: {
          contaid?: number
          freelancerid?: number
          habilidadeprincipal?: string | null
          nome?: string
          telefone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "freelancers_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      funcionarios: {
        Row: {
          ativo: boolean
          cargo: string | null
          chatidtelegram: string | null
          contaid: number
          cpf: string | null
          datafimafastamento: string | null
          datainicioafastamento: string | null
          diadefolga: number
          domingofolgamensal: number | null
          funcionarioid: number
          horarionotificacao: string | null
          isgestor: boolean | null
          nivelacesso: string | null
          nomecompleto: string
          pontostotal: number | null
          saldopontos: number
          senhahash: string | null
          setor: string | null
          telefonewhatsapp: string | null
          verificadorcpf: string | null
        }
        Insert: {
          ativo?: boolean
          cargo?: string | null
          chatidtelegram?: string | null
          contaid?: number
          cpf?: string | null
          datafimafastamento?: string | null
          datainicioafastamento?: string | null
          diadefolga?: number
          domingofolgamensal?: number | null
          funcionarioid?: number
          horarionotificacao?: string | null
          isgestor?: boolean | null
          nivelacesso?: string | null
          nomecompleto: string
          pontostotal?: number | null
          saldopontos?: number
          senhahash?: string | null
          setor?: string | null
          telefonewhatsapp?: string | null
          verificadorcpf?: string | null
        }
        Update: {
          ativo?: boolean
          cargo?: string | null
          chatidtelegram?: string | null
          contaid?: number
          cpf?: string | null
          datafimafastamento?: string | null
          datainicioafastamento?: string | null
          diadefolga?: number
          domingofolgamensal?: number | null
          funcionarioid?: number
          horarionotificacao?: string | null
          isgestor?: boolean | null
          nivelacesso?: string | null
          nomecompleto?: string
          pontostotal?: number | null
          saldopontos?: number
          senhahash?: string | null
          setor?: string | null
          telefonewhatsapp?: string | null
          verificadorcpf?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "funcionarios_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      funcionariosgrupos: {
        Row: {
          contaid: number
          funcionarioid: number
          grupoid: number
          lojaid: number
        }
        Insert: {
          contaid?: number
          funcionarioid: number
          grupoid: number
          lojaid: number
        }
        Update: {
          contaid?: number
          funcionarioid?: number
          grupoid?: number
          lojaid?: number
        }
        Relationships: [
          {
            foreignKeyName: "funcionariosgrupos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "funcionariosgrupos_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "funcionariosgrupos_grupoid_fk"
            columns: ["contaid", "grupoid"]
            isOneToOne: false
            referencedRelation: "grupos"
            referencedColumns: ["contaid", "grupoid"]
          },
          {
            foreignKeyName: "funcionariosgrupos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      funcionarioslojas: {
        Row: {
          ativo: boolean
          contaid: number
          criadoem: string
          funcionarioid: number
          lojaid: number
          posicaopadraoid: number | null
        }
        Insert: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          funcionarioid: number
          lojaid: number
          posicaopadraoid?: number | null
        }
        Update: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          funcionarioid?: number
          lojaid?: number
          posicaopadraoid?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "funcionarioslojas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "funcionarioslojas_contaid_funcionarioid_fkey"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "funcionarioslojas_contaid_lojaid_fkey"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "funcionarioslojas_lojaid_posicaopadraoid_fkey"
            columns: ["lojaid", "posicaopadraoid"]
            isOneToOne: false
            referencedRelation: "posicoesloja"
            referencedColumns: ["lojaid", "posicaoid"]
          },
        ]
      }
      grupos: {
        Row: {
          chatidtelegram: string | null
          contaid: number
          grupoid: number
          lojaid: number
          nomegrupo: string
        }
        Insert: {
          chatidtelegram?: string | null
          contaid?: number
          grupoid?: number
          lojaid: number
          nomegrupo: string
        }
        Update: {
          chatidtelegram?: string | null
          contaid?: number
          grupoid?: number
          lojaid?: number
          nomegrupo?: string
        }
        Relationships: [
          {
            foreignKeyName: "grupos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "grupos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      historicoranking: {
        Row: {
          ano: number
          contaid: number
          funcionarioid: number
          historicoid: number
          lojaid: number
          mes: number
          nomefuncionario: string
          percentualdesempenho: number
          pontosganhos: number
          pontospossiveis: number
          posicao: number
        }
        Insert: {
          ano: number
          contaid?: number
          funcionarioid: number
          historicoid?: number
          lojaid: number
          mes: number
          nomefuncionario: string
          percentualdesempenho: number
          pontosganhos: number
          pontospossiveis: number
          posicao: number
        }
        Update: {
          ano?: number
          contaid?: number
          funcionarioid?: number
          historicoid?: number
          lojaid?: number
          mes?: number
          nomefuncionario?: string
          percentualdesempenho?: number
          pontosganhos?: number
          pontospossiveis?: number
          posicao?: number
        }
        Relationships: [
          {
            foreignKeyName: "historicoranking_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "historicoranking_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "historicoranking_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      itenscontagemestoque: {
        Row: {
          contagemid: number
          contaid: number
          eanavulso: string | null
          itemcontagemid: number
          lojaid: number
          nomeavulso: string | null
          produtoid: number | null
          quantidadecontada: number
        }
        Insert: {
          contagemid: number
          contaid?: number
          eanavulso?: string | null
          itemcontagemid?: number
          lojaid: number
          nomeavulso?: string | null
          produtoid?: number | null
          quantidadecontada: number
        }
        Update: {
          contagemid?: number
          contaid?: number
          eanavulso?: string | null
          itemcontagemid?: number
          lojaid?: number
          nomeavulso?: string | null
          produtoid?: number | null
          quantidadecontada?: number
        }
        Relationships: [
          {
            foreignKeyName: "itenscontagemestoque_contagemid_fk"
            columns: ["contaid", "contagemid"]
            isOneToOne: false
            referencedRelation: "contagensestoque"
            referencedColumns: ["contaid", "contagemid"]
          },
          {
            foreignKeyName: "itenscontagemestoque_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "itenscontagemestoque_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "itenscontagemestoque_produtoid_fk"
            columns: ["contaid", "produtoid"]
            isOneToOne: false
            referencedRelation: "produtosestoque"
            referencedColumns: ["contaid", "produtoid"]
          },
        ]
      }
      itensnotafiscalentrada: {
        Row: {
          contaid: number
          itemnotaid: number
          lojaid: number
          notaid: number
          precocustounitario: number
          produtofornecedorid: number
          quantidade: number
        }
        Insert: {
          contaid?: number
          itemnotaid?: number
          lojaid: number
          notaid: number
          precocustounitario: number
          produtofornecedorid: number
          quantidade: number
        }
        Update: {
          contaid?: number
          itemnotaid?: number
          lojaid?: number
          notaid?: number
          precocustounitario?: number
          produtofornecedorid?: number
          quantidade?: number
        }
        Relationships: [
          {
            foreignKeyName: "itensnotafiscalentrada_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "itensnotafiscalentrada_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "itensnotafiscalentrada_notaid_fk"
            columns: ["contaid", "notaid"]
            isOneToOne: false
            referencedRelation: "notasfiscaisentrada"
            referencedColumns: ["contaid", "notaid"]
          },
          {
            foreignKeyName: "itensnotafiscalentrada_produtofornecedorid_fk"
            columns: ["contaid", "produtofornecedorid"]
            isOneToOne: false
            referencedRelation: "produtosfornecedor"
            referencedColumns: ["contaid", "produtofornecedorid"]
          },
        ]
      }
      linkstv: {
        Row: {
          contaid: number
          criadoem: string
          criadopor: string | null
          linktvid: number
          lojaid: number
          nome: string
          revogadoem: string | null
          tokenhash: string
          ultimouso: string | null
        }
        Insert: {
          contaid?: number
          criadoem?: string
          criadopor?: string | null
          linktvid?: number
          lojaid: number
          nome: string
          revogadoem?: string | null
          tokenhash: string
          ultimouso?: string | null
        }
        Update: {
          contaid?: number
          criadoem?: string
          criadopor?: string | null
          linktvid?: number
          lojaid?: number
          nome?: string
          revogadoem?: string | null
          tokenhash?: string
          ultimouso?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "linkstv_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "linkstv_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      lojas: {
        Row: {
          ativa: boolean
          cidade: string | null
          contaid: number
          criadoem: string
          endereco: string | null
          gestorid: number | null
          lojaid: number
          nome: string
          responsavelagendamentosid: number | null
        }
        Insert: {
          ativa?: boolean
          cidade?: string | null
          contaid?: number
          criadoem?: string
          endereco?: string | null
          gestorid?: number | null
          lojaid?: number
          nome: string
          responsavelagendamentosid?: number | null
        }
        Update: {
          ativa?: boolean
          cidade?: string | null
          contaid?: number
          criadoem?: string
          endereco?: string | null
          gestorid?: number | null
          lojaid?: number
          nome?: string
          responsavelagendamentosid?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "lojas_gestor_trabalha_na_loja"
            columns: ["gestorid", "lojaid"]
            isOneToOne: false
            referencedRelation: "funcionarioslojas"
            referencedColumns: ["funcionarioid", "lojaid"]
          },
          {
            foreignKeyName: "lojas_responsavel_trabalha_na_loja"
            columns: ["responsavelagendamentosid", "lojaid"]
            isOneToOne: false
            referencedRelation: "funcionarioslojas"
            referencedColumns: ["funcionarioid", "lojaid"]
          },
        ]
      }
      lucromensalhistorico: {
        Row: {
          ano: number
          contaid: number
          dataregistro: string | null
          historicoid: number
          lojaid: number
          mes: number
          percentuallucro: number
        }
        Insert: {
          ano: number
          contaid?: number
          dataregistro?: string | null
          historicoid?: number
          lojaid: number
          mes: number
          percentuallucro: number
        }
        Update: {
          ano?: number
          contaid?: number
          dataregistro?: string | null
          historicoid?: number
          lojaid?: number
          mes?: number
          percentuallucro?: number
        }
        Relationships: [
          {
            foreignKeyName: "lucromensalhistorico_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "lucromensalhistorico_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      metasdiariasapuracoes: {
        Row: {
          apuracaoid: number
          contaid: number
          dataapuracao: string
          funcionarioid_lancamento: number | null
          lojaid: number
          metaprincipalid: number | null
          pontosmetadiariaganhos: number | null
          valordia: number
        }
        Insert: {
          apuracaoid?: number
          contaid?: number
          dataapuracao: string
          funcionarioid_lancamento?: number | null
          lojaid: number
          metaprincipalid?: number | null
          pontosmetadiariaganhos?: number | null
          valordia: number
        }
        Update: {
          apuracaoid?: number
          contaid?: number
          dataapuracao?: string
          funcionarioid_lancamento?: number | null
          lojaid?: number
          metaprincipalid?: number | null
          pontosmetadiariaganhos?: number | null
          valordia?: number
        }
        Relationships: [
          {
            foreignKeyName: "metasdiariasapuracoes_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metasdiariasapuracoes_funcionarioid_lancamento_fk"
            columns: ["contaid", "funcionarioid_lancamento"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "metasdiariasapuracoes_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "metasdiariasapuracoes_metaprincipalid_fk"
            columns: ["contaid", "metaprincipalid"]
            isOneToOne: false
            referencedRelation: "metasprincipais"
            referencedColumns: ["contaid", "metaprincipalid"]
          },
        ]
      }
      metasdiariasinstancias: {
        Row: {
          contaid: number
          data: string
          lojaid: number
          metainstanciaid: number
          metamodeloid: number | null
          status: string | null
          valoratingido: number | null
          valormeta: number
        }
        Insert: {
          contaid?: number
          data: string
          lojaid: number
          metainstanciaid?: number
          metamodeloid?: number | null
          status?: string | null
          valoratingido?: number | null
          valormeta: number
        }
        Update: {
          contaid?: number
          data?: string
          lojaid?: number
          metainstanciaid?: number
          metamodeloid?: number | null
          status?: string | null
          valoratingido?: number | null
          valormeta?: number
        }
        Relationships: [
          {
            foreignKeyName: "metasdiariasinstancias_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metasdiariasinstancias_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      metasdiariasmodelos: {
        Row: {
          contaid: number
          diasemanaid: number
          lojaid: number
          nomedia: string
          pontospremio: number
          valormeta: number
        }
        Insert: {
          contaid?: number
          diasemanaid: number
          lojaid: number
          nomedia: string
          pontospremio: number
          valormeta: number
        }
        Update: {
          contaid?: number
          diasemanaid?: number
          lojaid?: number
          nomedia?: string
          pontospremio?: number
          valormeta?: number
        }
        Relationships: [
          {
            foreignKeyName: "metasdiariasmodelos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metasdiariasmodelos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      metasprincipais: {
        Row: {
          contaid: number
          datafim: string
          datainicio: string
          descricao: string | null
          lojaid: number
          metaprincipalid: number
          nomemeta: string
          pontospremio: number
          setoralvo: string | null
          status: string | null
          valormetatotal: number
        }
        Insert: {
          contaid?: number
          datafim: string
          datainicio: string
          descricao?: string | null
          lojaid: number
          metaprincipalid?: number
          nomemeta: string
          pontospremio: number
          setoralvo?: string | null
          status?: string | null
          valormetatotal: number
        }
        Update: {
          contaid?: number
          datafim?: string
          datainicio?: string
          descricao?: string | null
          lojaid?: number
          metaprincipalid?: number
          nomemeta?: string
          pontospremio?: number
          setoralvo?: string | null
          status?: string | null
          valormetatotal?: number
        }
        Relationships: [
          {
            foreignKeyName: "metasprincipais_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metasprincipais_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      movimentospontos: {
        Row: {
          contaid: number
          criadopor: string | null
          datamovimento: string
          descricao: string
          entregaid: number | null
          funcionarioid: number
          lojaid: number | null
          movimentoid: number
          pontos: number
          resgateid: number | null
          tipo: string
        }
        Insert: {
          contaid?: number
          criadopor?: string | null
          datamovimento?: string
          descricao: string
          entregaid?: number | null
          funcionarioid: number
          lojaid?: number | null
          movimentoid?: number
          pontos: number
          resgateid?: number | null
          tipo: string
        }
        Update: {
          contaid?: number
          criadopor?: string | null
          datamovimento?: string
          descricao?: string
          entregaid?: number | null
          funcionarioid?: number
          lojaid?: number | null
          movimentoid?: number
          pontos?: number
          resgateid?: number | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "movimentospontos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "movimentospontos_entrega_fk"
            columns: ["contaid", "entregaid"]
            isOneToOne: false
            referencedRelation: "entregas"
            referencedColumns: ["contaid", "entregaid"]
          },
          {
            foreignKeyName: "movimentospontos_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "movimentospontos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "movimentospontos_resgate_fk"
            columns: ["contaid", "resgateid"]
            isOneToOne: false
            referencedRelation: "resgates"
            referencedColumns: ["contaid", "resgateid"]
          },
        ]
      }
      notasfiscais: {
        Row: {
          contaid: number
          datarecebimento: string | null
          fileidtelegram: string
          funcionarioid: number
          lojaid: number
          notafiscalid: number
          pathfoto: string | null
          status: string | null
        }
        Insert: {
          contaid?: number
          datarecebimento?: string | null
          fileidtelegram: string
          funcionarioid: number
          lojaid: number
          notafiscalid?: number
          pathfoto?: string | null
          status?: string | null
        }
        Update: {
          contaid?: number
          datarecebimento?: string | null
          fileidtelegram?: string
          funcionarioid?: number
          lojaid?: number
          notafiscalid?: number
          pathfoto?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notasfiscais_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "notasfiscais_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "notasfiscais_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      notasfiscaisentrada: {
        Row: {
          contaid: number
          dataemissao: string
          dataimportacao: string | null
          fornecedorid: number
          lojaid: number
          notaid: number
          numeronf: string
          valortotalnf: number
        }
        Insert: {
          contaid?: number
          dataemissao: string
          dataimportacao?: string | null
          fornecedorid: number
          lojaid: number
          notaid?: number
          numeronf: string
          valortotalnf: number
        }
        Update: {
          contaid?: number
          dataemissao?: string
          dataimportacao?: string | null
          fornecedorid?: number
          lojaid?: number
          notaid?: number
          numeronf?: string
          valortotalnf?: number
        }
        Relationships: [
          {
            foreignKeyName: "notasfiscaisentrada_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "notasfiscaisentrada_fornecedorid_fk"
            columns: ["contaid", "fornecedorid"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["contaid", "fornecedorid"]
          },
          {
            foreignKeyName: "notasfiscaisentrada_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      onboardingstatus: {
        Row: {
          contaid: number
          cpf_fileid: string | null
          cpfconjugue: string | null
          ctps_fileid: string | null
          dadosfilhos: string | null
          dataadmissional: string | null
          datacasamento: string | null
          escolaridade: string | null
          estadocivil: string | null
          funcionarioid: number
          nomeconjugue: string | null
          qtdfilhos: number | null
          rg_fileid: string | null
          statusadmissional: string
          statusworkflow: string
          tituloeleitor_fileid: string | null
          ultimaetapa: string | null
        }
        Insert: {
          contaid?: number
          cpf_fileid?: string | null
          cpfconjugue?: string | null
          ctps_fileid?: string | null
          dadosfilhos?: string | null
          dataadmissional?: string | null
          datacasamento?: string | null
          escolaridade?: string | null
          estadocivil?: string | null
          funcionarioid: number
          nomeconjugue?: string | null
          qtdfilhos?: number | null
          rg_fileid?: string | null
          statusadmissional?: string
          statusworkflow?: string
          tituloeleitor_fileid?: string | null
          ultimaetapa?: string | null
        }
        Update: {
          contaid?: number
          cpf_fileid?: string | null
          cpfconjugue?: string | null
          ctps_fileid?: string | null
          dadosfilhos?: string | null
          dataadmissional?: string | null
          datacasamento?: string | null
          escolaridade?: string | null
          estadocivil?: string | null
          funcionarioid?: number
          nomeconjugue?: string | null
          qtdfilhos?: number | null
          rg_fileid?: string | null
          statusadmissional?: string
          statusworkflow?: string
          tituloeleitor_fileid?: string | null
          ultimaetapa?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "onboardingstatus_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "onboardingstatus_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      picodiario: {
        Row: {
          contaid: number
          diasemanaid: number
          horabloqueiofim: string | null
          horabloqueioinicio: string | null
          lojaid: number
          nomedia: string
        }
        Insert: {
          contaid?: number
          diasemanaid: number
          horabloqueiofim?: string | null
          horabloqueioinicio?: string | null
          lojaid: number
          nomedia: string
        }
        Update: {
          contaid?: number
          diasemanaid?: number
          horabloqueiofim?: string | null
          horabloqueioinicio?: string | null
          lojaid?: number
          nomedia?: string
        }
        Relationships: [
          {
            foreignKeyName: "picodiario_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "picodiario_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      posicoesloja: {
        Row: {
          ativo: boolean | null
          contaid: number
          coordx: number
          coordy: number
          lojaid: number
          nomeposicao: string
          posicaoid: number
          setor: string | null
        }
        Insert: {
          ativo?: boolean | null
          contaid?: number
          coordx: number
          coordy: number
          lojaid: number
          nomeposicao: string
          posicaoid?: number
          setor?: string | null
        }
        Update: {
          ativo?: boolean | null
          contaid?: number
          coordx?: number
          coordy?: number
          lojaid?: number
          nomeposicao?: string
          posicaoid?: number
          setor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "posicoesloja_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "posicoesloja_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      produtosestoque: {
        Row: {
          categoria: string | null
          contaid: number
          estoqueminimo: number | null
          nomeproduto: string
          produtoid: number
          unidademedida: string
        }
        Insert: {
          categoria?: string | null
          contaid?: number
          estoqueminimo?: number | null
          nomeproduto: string
          produtoid?: number
          unidademedida: string
        }
        Update: {
          categoria?: string | null
          contaid?: number
          estoqueminimo?: number | null
          nomeproduto?: string
          produtoid?: number
          unidademedida?: string
        }
        Relationships: [
          {
            foreignKeyName: "produtosestoque_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      produtosfornecedor: {
        Row: {
          codigofornecedor: string | null
          contaid: number
          datacriacao: string | null
          descricaoxml: string
          ean: string | null
          fatorconversao: number | null
          fornecedorid: number
          ncm: string | null
          produtofornecedorid: number
          produtoid: number
        }
        Insert: {
          codigofornecedor?: string | null
          contaid?: number
          datacriacao?: string | null
          descricaoxml: string
          ean?: string | null
          fatorconversao?: number | null
          fornecedorid: number
          ncm?: string | null
          produtofornecedorid?: number
          produtoid: number
        }
        Update: {
          codigofornecedor?: string | null
          contaid?: number
          datacriacao?: string | null
          descricaoxml?: string
          ean?: string | null
          fatorconversao?: number | null
          fornecedorid?: number
          ncm?: string | null
          produtofornecedorid?: number
          produtoid?: number
        }
        Relationships: [
          {
            foreignKeyName: "produtosfornecedor_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "produtosfornecedor_fornecedorid_fk"
            columns: ["contaid", "fornecedorid"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["contaid", "fornecedorid"]
          },
          {
            foreignKeyName: "produtosfornecedor_produtoid_fk"
            columns: ["contaid", "produtoid"]
            isOneToOne: false
            referencedRelation: "produtosestoque"
            referencedColumns: ["contaid", "produtoid"]
          },
        ]
      }
      produtosloja: {
        Row: {
          ativo: boolean
          contaid: number
          custoempontos: number
          descricao: string | null
          estoquedisponivel: number | null
          nome: string
          produtoid: number
          sistema: string | null
        }
        Insert: {
          ativo?: boolean
          contaid?: number
          custoempontos: number
          descricao?: string | null
          estoquedisponivel?: number | null
          nome: string
          produtoid?: number
          sistema?: string | null
        }
        Update: {
          ativo?: boolean
          contaid?: number
          custoempontos?: number
          descricao?: string | null
          estoquedisponivel?: number | null
          nome?: string
          produtoid?: number
          sistema?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "produtosloja_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      resgates: {
        Row: {
          canceladopor: string | null
          contaid: number
          dataaprovacao: string | null
          datacancelamento: string | null
          dataentrega: string | null
          dataestorno: string | null
          datasolicitacao: string
          entreguepor: string | null
          estornadopor: string | null
          funcionarioid: number
          gestorid_aprovacao: number | null
          lojaid: number | null
          motivocancelamento: string | null
          motivoestorno: string | null
          pontosgastos: number
          produtoid: number
          registradopor: string | null
          resgateid: number
          status: string
          taxaconversao: number | null
          valorreais: number | null
        }
        Insert: {
          canceladopor?: string | null
          contaid?: number
          dataaprovacao?: string | null
          datacancelamento?: string | null
          dataentrega?: string | null
          dataestorno?: string | null
          datasolicitacao?: string
          entreguepor?: string | null
          estornadopor?: string | null
          funcionarioid: number
          gestorid_aprovacao?: number | null
          lojaid?: number | null
          motivocancelamento?: string | null
          motivoestorno?: string | null
          pontosgastos: number
          produtoid: number
          registradopor?: string | null
          resgateid?: number
          status?: string
          taxaconversao?: number | null
          valorreais?: number | null
        }
        Update: {
          canceladopor?: string | null
          contaid?: number
          dataaprovacao?: string | null
          datacancelamento?: string | null
          dataentrega?: string | null
          dataestorno?: string | null
          datasolicitacao?: string
          entreguepor?: string | null
          estornadopor?: string | null
          funcionarioid?: number
          gestorid_aprovacao?: number | null
          lojaid?: number | null
          motivocancelamento?: string | null
          motivoestorno?: string | null
          pontosgastos?: number
          produtoid?: number
          registradopor?: string | null
          resgateid?: number
          status?: string
          taxaconversao?: number | null
          valorreais?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "resgates_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "resgates_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "resgates_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "resgates_produtoid_fk"
            columns: ["contaid", "produtoid"]
            isOneToOne: false
            referencedRelation: "produtosloja"
            referencedColumns: ["contaid", "produtoid"]
          },
        ]
      }
      solicitacoesinternas: {
        Row: {
          caminhofoto: string | null
          categoria: string | null
          contaid: number
          dataconclusao: string | null
          datasolicitacao: string | null
          descricao: string | null
          funcionarioid: number | null
          lojaid: number
          motivorecusa: string | null
          quantidade: number | null
          solicitacaoid: number
          status: string | null
          tipo: string
        }
        Insert: {
          caminhofoto?: string | null
          categoria?: string | null
          contaid?: number
          dataconclusao?: string | null
          datasolicitacao?: string | null
          descricao?: string | null
          funcionarioid?: number | null
          lojaid: number
          motivorecusa?: string | null
          quantidade?: number | null
          solicitacaoid?: number
          status?: string | null
          tipo: string
        }
        Update: {
          caminhofoto?: string | null
          categoria?: string | null
          contaid?: number
          dataconclusao?: string | null
          datasolicitacao?: string | null
          descricao?: string | null
          funcionarioid?: number | null
          lojaid?: number
          motivorecusa?: string | null
          quantidade?: number | null
          solicitacaoid?: number
          status?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "solicitacoesinternas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "solicitacoesinternas_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "solicitacoesinternas_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      tarefas: {
        Row: {
          ativa: boolean | null
          contaid: number
          datacriacao: string | null
          descricao: string | null
          pontos: number
          setor: string | null
          sistema: string | null
          tarefaid: number
          titulo: string
        }
        Insert: {
          ativa?: boolean | null
          contaid?: number
          datacriacao?: string | null
          descricao?: string | null
          pontos: number
          setor?: string | null
          sistema?: string | null
          tarefaid?: number
          titulo: string
        }
        Update: {
          ativa?: boolean | null
          contaid?: number
          datacriacao?: string | null
          descricao?: string | null
          pontos?: number
          setor?: string | null
          sistema?: string | null
          tarefaid?: number
          titulo?: string
        }
        Relationships: [
          {
            foreignKeyName: "tarefas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      tarefasatribuidas: {
        Row: {
          agendamentoid: number | null
          atribuicaoid: number
          contaid: number
          dataaceite: string | null
          dataagendamento: string | null
          dataatribuicao: string | null
          datafimvigencia: string | null
          datainiciovigencia: string | null
          descricaooverride: string | null
          funcionarioid: number | null
          funcionarioresponsavelid: number | null
          grupoid: number | null
          horariodisparo: string | null
          lojaid: number
          origematribuicaoid: number | null
          statustarefagrupo: string | null
          tarefaid: number
          tipofrequencia: string
          valorfrequencia: number | null
        }
        Insert: {
          agendamentoid?: number | null
          atribuicaoid?: number
          contaid?: number
          dataaceite?: string | null
          dataagendamento?: string | null
          dataatribuicao?: string | null
          datafimvigencia?: string | null
          datainiciovigencia?: string | null
          descricaooverride?: string | null
          funcionarioid?: number | null
          funcionarioresponsavelid?: number | null
          grupoid?: number | null
          horariodisparo?: string | null
          lojaid: number
          origematribuicaoid?: number | null
          statustarefagrupo?: string | null
          tarefaid: number
          tipofrequencia?: string
          valorfrequencia?: number | null
        }
        Update: {
          agendamentoid?: number | null
          atribuicaoid?: number
          contaid?: number
          dataaceite?: string | null
          dataagendamento?: string | null
          dataatribuicao?: string | null
          datafimvigencia?: string | null
          datainiciovigencia?: string | null
          descricaooverride?: string | null
          funcionarioid?: number | null
          funcionarioresponsavelid?: number | null
          grupoid?: number | null
          horariodisparo?: string | null
          lojaid?: number
          origematribuicaoid?: number | null
          statustarefagrupo?: string | null
          tarefaid?: number
          tipofrequencia?: string
          valorfrequencia?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tarefasatribuidas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_funcionario_na_loja_fk"
            columns: ["funcionarioid", "lojaid"]
            isOneToOne: false
            referencedRelation: "funcionarioslojas"
            referencedColumns: ["funcionarioid", "lojaid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_funcionarioid_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_funcionarioresponsavelid_fk"
            columns: ["contaid", "funcionarioresponsavelid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_grupoid_fk"
            columns: ["contaid", "grupoid"]
            isOneToOne: false
            referencedRelation: "grupos"
            referencedColumns: ["contaid", "grupoid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_origematribuicaoid_fk"
            columns: ["contaid", "origematribuicaoid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: ["contaid", "atribuicaoid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_tarefa_na_loja_fk"
            columns: ["tarefaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "tarefaslojas"
            referencedColumns: ["tarefaid", "lojaid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_tarefaid_fk"
            columns: ["contaid", "tarefaid"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["contaid", "tarefaid"]
          },
        ]
      }
      tarefaslojas: {
        Row: {
          ativo: boolean
          contaid: number
          criadoem: string
          lojaid: number
          tarefaid: number
        }
        Insert: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          lojaid: number
          tarefaid: number
        }
        Update: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          lojaid?: number
          tarefaid?: number
        }
        Relationships: [
          {
            foreignKeyName: "tarefaslojas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "tarefaslojas_contaid_lojaid_fkey"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "tarefaslojas_contaid_tarefaid_fkey"
            columns: ["contaid", "tarefaid"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["contaid", "tarefaid"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      apos_aprovar_entrega: {
        Args: { p_entregaid: number }
        Returns: undefined
      }
      aprovar_entrega: { Args: { p_entregaid: number }; Returns: number }
      atribuicoes_para_entregar: {
        Args: { p_lojaid: number }
        Returns: {
          atrasada: boolean
          atribuicaoid: number
          funcionarioid: number
          nomecompleto: string
          pontos: number
          tipofrequencia: string
          titulo: string
        }[]
      }
      cancelar_resgate: {
        Args: { p_motivo: string; p_resgateid: number }
        Returns: undefined
      }
      cria_configuracoes_padrao: {
        Args: { p_contaid: number }
        Returns: undefined
      }
      cria_produtos_do_sistema: {
        Args: { p_contaid: number }
        Returns: undefined
      }
      cria_tarefas_do_sistema: {
        Args: { p_contaid: number }
        Returns: undefined
      }
      criar_link_tv: {
        Args: { p_lojaid: number; p_nome: string }
        Returns: string
      }
      desfazer_resgate: {
        Args: {
          p_de: string
          p_motivo: string
          p_para: string
          p_resgateid: number
        }
        Returns: undefined
      }
      dia_em_sao_paulo: { Args: { p_instante: string }; Returns: string }
      eh_admin_geral: { Args: never; Returns: boolean }
      entregar_resgate: { Args: { p_resgateid: number }; Returns: undefined }
      estornar_entrega: {
        Args: { p_entregaid: number; p_motivo: string }
        Returns: number
      }
      estornar_resgate: {
        Args: { p_motivo: string; p_resgateid: number }
        Returns: undefined
      }
      extrato_pontos: {
        Args: { p_ate: string; p_de: string; p_funcionarioid: number }
        Returns: Json
      }
      minha_conta: { Args: never; Returns: number }
      minha_conta_editavel: { Args: never; Returns: number }
      minha_taxa: { Args: never; Returns: number }
      montar_painel: {
        Args: { p_contaid: number; p_lojaid: number; p_tv: boolean }
        Returns: Json
      }
      nome_curto: { Args: { p_nome: string }; Returns: string }
      painel_da_loja: { Args: { p_lojaid: number }; Returns: Json }
      painel_da_tv: { Args: { p_codigo: string }; Returns: Json }
      ranking_pontos: {
        Args: { p_ate: string; p_de: string; p_lojaid?: number }
        Returns: {
          entregas: number
          funcionarioid: number
          nomecompleto: string
          pontos: number
        }[]
      }
      reais: { Args: { p_valor: number }; Returns: string }
      recusar_entrega: {
        Args: { p_entregaid: number; p_motivo: string }
        Returns: undefined
      }
      registrar_abate_comanda: {
        Args: {
          p_entregar?: boolean
          p_funcionarioid: number
          p_lojaid?: number
          p_valorreais: number
        }
        Returns: number
      }
      registrar_entrega: {
        Args: {
          p_aprovar?: boolean
          p_atribuicaoid: number
          p_observacao?: string
          p_pathfoto?: string
        }
        Returns: number
      }
      registrar_resgate: {
        Args: {
          p_entregar?: boolean
          p_funcionarioid: number
          p_lojaid?: number
          p_produtoid: number
        }
        Returns: number
      }
      resumo_das_lojas: { Args: never; Returns: Json }
      revogar_link_tv: { Args: { p_linktvid: number }; Returns: undefined }
      tarefa_cai_no_dia: {
        Args: {
          p_dataagendamento: string
          p_dia: string
          p_tipofrequencia: string
          p_valorfrequencia: number
        }
        Returns: boolean
      }
      taxa_da_conta: { Args: { p_contaid: number }; Returns: number }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
