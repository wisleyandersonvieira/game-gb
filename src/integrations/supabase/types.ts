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
          cpfcliente: string | null
          datacriacao: string
          dataevento: string
          funcionarioid: number
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
          cpfcliente?: string | null
          datacriacao?: string
          dataevento: string
          funcionarioid: number
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
          cpfcliente?: string | null
          datacriacao?: string
          dataevento?: string
          funcionarioid?: number
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
            foreignKeyName: "agendamentos_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      categoriasproduto: {
        Row: {
          categoriaid: number
          nomecategoria: string
        }
        Insert: {
          categoriaid?: number
          nomecategoria: string
        }
        Update: {
          categoriaid?: number
          nomecategoria?: string
        }
        Relationships: []
      }
      configuracoes: {
        Row: {
          atualizadoem: string
          chave: string
          descricao: string | null
          valor: string | null
        }
        Insert: {
          atualizadoem?: string
          chave: string
          descricao?: string | null
          valor?: string | null
        }
        Update: {
          atualizadoem?: string
          chave?: string
          descricao?: string | null
          valor?: string | null
        }
        Relationships: []
      }
      configuracoesescala: {
        Row: {
          configid: number
          dataatualizacao: string | null
          duracaointervalo: number
          duracaojornadapadrao: number | null
          maxhorassempausa: number
        }
        Insert: {
          configid?: number
          dataatualizacao?: string | null
          duracaointervalo: number
          duracaojornadapadrao?: number | null
          maxhorassempausa: number
        }
        Update: {
          configid?: number
          dataatualizacao?: string | null
          duracaointervalo?: number
          duracaojornadapadrao?: number | null
          maxhorassempausa?: number
        }
        Relationships: []
      }
      configuracoessetores: {
        Row: {
          descricaopadrao: string | null
          setor: string
        }
        Insert: {
          descricaopadrao?: string | null
          setor: string
        }
        Update: {
          descricaopadrao?: string | null
          setor?: string
        }
        Relationships: []
      }
      conquistas: {
        Row: {
          conquistaid: number
          criteriotipo: string
          criteriovalor: number
          descricao: string
          icone: string | null
          nome: string
          pontosbonus: number | null
        }
        Insert: {
          conquistaid?: number
          criteriotipo: string
          criteriovalor: number
          descricao: string
          icone?: string | null
          nome: string
          pontosbonus?: number | null
        }
        Update: {
          conquistaid?: number
          criteriotipo?: string
          criteriovalor?: number
          descricao?: string
          icone?: string | null
          nome?: string
          pontosbonus?: number | null
        }
        Relationships: []
      }
      conquistasfuncionarios: {
        Row: {
          conquistafuncionarioid: number
          conquistaid: number
          dataconquista: string | null
          funcionarioid: number
        }
        Insert: {
          conquistafuncionarioid?: number
          conquistaid: number
          dataconquista?: string | null
          funcionarioid: number
        }
        Update: {
          conquistafuncionarioid?: number
          conquistaid?: number
          dataconquista?: string | null
          funcionarioid?: number
        }
        Relationships: [
          {
            foreignKeyName: "conquistasfuncionarios_conquistaid_fkey"
            columns: ["conquistaid"]
            isOneToOne: false
            referencedRelation: "conquistas"
            referencedColumns: ["conquistaid"]
          },
          {
            foreignKeyName: "conquistasfuncionarios_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      contagensestoque: {
        Row: {
          contagemid: number
          datacontagem: string
          dataregistro: string | null
          funcionarioid: number
          nomecontagem: string | null
        }
        Insert: {
          contagemid?: number
          datacontagem: string
          dataregistro?: string | null
          funcionarioid: number
          nomecontagem?: string | null
        }
        Update: {
          contagemid?: number
          datacontagem?: string
          dataregistro?: string | null
          funcionarioid?: number
          nomecontagem?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contagensestoque_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      denunciasanonimas: {
        Row: {
          dataregistro: string | null
          denunciaid: number
          mensagem: string
          status: string | null
        }
        Insert: {
          dataregistro?: string | null
          denunciaid?: number
          mensagem: string
          status?: string | null
        }
        Update: {
          dataregistro?: string | null
          denunciaid?: number
          mensagem?: string
          status?: string | null
        }
        Relationships: []
      }
      documentos: {
        Row: {
          conteudo: string
          datacriacao: string | null
          documentoid: number
          funcionariocriadorid: number | null
          pontosporciencia: number
          telegramfileidfoto: string | null
          titulo: string
        }
        Insert: {
          conteudo: string
          datacriacao?: string | null
          documentoid?: number
          funcionariocriadorid?: number | null
          pontosporciencia?: number
          telegramfileidfoto?: string | null
          titulo: string
        }
        Update: {
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
            foreignKeyName: "documentos_funcionariocriadorid_fkey"
            columns: ["funcionariocriadorid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      documentosassinaturas: {
        Row: {
          assinaturaid: number
          dataciencia: string | null
          dataenvio: string | null
          documentoid: number
          funcionarioid: number
          statusassinatura: string
        }
        Insert: {
          assinaturaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid: number
          funcionarioid: number
          statusassinatura?: string
        }
        Update: {
          assinaturaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid?: number
          funcionarioid?: number
          statusassinatura?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentosassinaturas_documentoid_fkey"
            columns: ["documentoid"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["documentoid"]
          },
          {
            foreignKeyName: "documentosassinaturas_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      documentospessoais: {
        Row: {
          caminhoarquivo: string
          dataupload: string | null
          documentoid: number
          funcionarioid: number
          mesano: string
          tipodocumento: string
        }
        Insert: {
          caminhoarquivo: string
          dataupload?: string | null
          documentoid?: number
          funcionarioid: number
          mesano: string
          tipodocumento: string
        }
        Update: {
          caminhoarquivo?: string
          dataupload?: string | null
          documentoid?: number
          funcionarioid?: number
          mesano?: string
          tipodocumento?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentospessoais_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      documentospessoaisciencia: {
        Row: {
          cienciaid: number
          dataciencia: string | null
          dataenvio: string | null
          documentoid: number
          funcionarioid: number
          status: string
        }
        Insert: {
          cienciaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid: number
          funcionarioid: number
          status?: string
        }
        Update: {
          cienciaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid?: number
          funcionarioid?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentospessoaisciencia_documentoid_fkey"
            columns: ["documentoid"]
            isOneToOne: false
            referencedRelation: "documentospessoais"
            referencedColumns: ["documentoid"]
          },
          {
            foreignKeyName: "documentospessoaisciencia_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      entregas: {
        Row: {
          atribuicaoid: number | null
          dataenvio: string | null
          entregaid: number
          fileidtelegram: string | null
          funcionarioid: number
          motivorecusa: string | null
          notificacaogestorenviada: boolean | null
          pathfotoevidencia: string | null
          pontosganhos: number | null
          statusvalidacao: string | null
          tarefaid: number
        }
        Insert: {
          atribuicaoid?: number | null
          dataenvio?: string | null
          entregaid?: number
          fileidtelegram?: string | null
          funcionarioid: number
          motivorecusa?: string | null
          notificacaogestorenviada?: boolean | null
          pathfotoevidencia?: string | null
          pontosganhos?: number | null
          statusvalidacao?: string | null
          tarefaid: number
        }
        Update: {
          atribuicaoid?: number | null
          dataenvio?: string | null
          entregaid?: number
          fileidtelegram?: string | null
          funcionarioid?: number
          motivorecusa?: string | null
          notificacaogestorenviada?: boolean | null
          pathfotoevidencia?: string | null
          pontosganhos?: number | null
          statusvalidacao?: string | null
          tarefaid?: number
        }
        Relationships: [
          {
            foreignKeyName: "entregas_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "entregas_tarefaid_fkey"
            columns: ["tarefaid"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["tarefaid"]
          },
        ]
      }
      escaladiaria: {
        Row: {
          dataescala: string
          escalaid: number
          fimintervalo: string | null
          focododia: string | null
          freelancerid: number | null
          funcionarioid: number | null
          horarioentrada: string | null
          horariosaida: string | null
          iniciointervalo: string | null
          posicaoid: number
          statusconfirmacao: string | null
        }
        Insert: {
          dataescala: string
          escalaid?: number
          fimintervalo?: string | null
          focododia?: string | null
          freelancerid?: number | null
          funcionarioid?: number | null
          horarioentrada?: string | null
          horariosaida?: string | null
          iniciointervalo?: string | null
          posicaoid: number
          statusconfirmacao?: string | null
        }
        Update: {
          dataescala?: string
          escalaid?: number
          fimintervalo?: string | null
          focododia?: string | null
          freelancerid?: number | null
          funcionarioid?: number | null
          horarioentrada?: string | null
          horariosaida?: string | null
          iniciointervalo?: string | null
          posicaoid?: number
          statusconfirmacao?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "escaladiaria_freelancerid_fkey"
            columns: ["freelancerid"]
            isOneToOne: false
            referencedRelation: "freelancers"
            referencedColumns: ["freelancerid"]
          },
          {
            foreignKeyName: "escaladiaria_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "escaladiaria_posicaoid_fkey"
            columns: ["posicaoid"]
            isOneToOne: false
            referencedRelation: "posicoesloja"
            referencedColumns: ["posicaoid"]
          },
        ]
      }
      feedbacks: {
        Row: {
          comentario: string | null
          datafeedback: string
          feedbackid: number
          funcionarioid: number
          notadia: number
        }
        Insert: {
          comentario?: string | null
          datafeedback: string
          feedbackid?: number
          funcionarioid: number
          notadia: number
        }
        Update: {
          comentario?: string | null
          datafeedback?: string
          feedbackid?: number
          funcionarioid?: number
          notadia?: number
        }
        Relationships: [
          {
            foreignKeyName: "feedbacks_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      feedbacksolicitacoes: {
        Row: {
          dataresposta: string | null
          datasolicitacao: string
          funcionarioid: number
          solicitacaoid: number
          status: string
          textoassunto: string
          textoresposta: string | null
        }
        Insert: {
          dataresposta?: string | null
          datasolicitacao?: string
          funcionarioid: number
          solicitacaoid?: number
          status?: string
          textoassunto: string
          textoresposta?: string | null
        }
        Update: {
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
            foreignKeyName: "feedbacksolicitacoes_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      fornecedores: {
        Row: {
          cnpj: string
          fornecedorid: number
          nomefantasia: string
        }
        Insert: {
          cnpj: string
          fornecedorid?: number
          nomefantasia: string
        }
        Update: {
          cnpj?: string
          fornecedorid?: number
          nomefantasia?: string
        }
        Relationships: []
      }
      freelancers: {
        Row: {
          freelancerid: number
          habilidadeprincipal: string | null
          nome: string
          telefone: string | null
        }
        Insert: {
          freelancerid?: number
          habilidadeprincipal?: string | null
          nome: string
          telefone?: string | null
        }
        Update: {
          freelancerid?: number
          habilidadeprincipal?: string | null
          nome?: string
          telefone?: string | null
        }
        Relationships: []
      }
      funcionarios: {
        Row: {
          ativo: boolean
          cargo: string | null
          chatidtelegram: string | null
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
          posicaopadraoid: number | null
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
          posicaopadraoid?: number | null
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
          posicaopadraoid?: number | null
          saldopontos?: number
          senhahash?: string | null
          setor?: string | null
          telefonewhatsapp?: string | null
          verificadorcpf?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "funcionarios_posicaopadraoid_fkey"
            columns: ["posicaopadraoid"]
            isOneToOne: false
            referencedRelation: "posicoesloja"
            referencedColumns: ["posicaoid"]
          },
        ]
      }
      funcionariosgrupos: {
        Row: {
          funcionarioid: number
          grupoid: number
        }
        Insert: {
          funcionarioid: number
          grupoid: number
        }
        Update: {
          funcionarioid?: number
          grupoid?: number
        }
        Relationships: [
          {
            foreignKeyName: "funcionariosgrupos_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "funcionariosgrupos_grupoid_fkey"
            columns: ["grupoid"]
            isOneToOne: false
            referencedRelation: "grupos"
            referencedColumns: ["grupoid"]
          },
        ]
      }
      grupos: {
        Row: {
          chatidtelegram: string | null
          grupoid: number
          nomegrupo: string
        }
        Insert: {
          chatidtelegram?: string | null
          grupoid?: number
          nomegrupo: string
        }
        Update: {
          chatidtelegram?: string | null
          grupoid?: number
          nomegrupo?: string
        }
        Relationships: []
      }
      historicoranking: {
        Row: {
          ano: number
          funcionarioid: number
          historicoid: number
          mes: number
          nomefuncionario: string
          percentualdesempenho: number
          pontosganhos: number
          pontospossiveis: number
          posicao: number
        }
        Insert: {
          ano: number
          funcionarioid: number
          historicoid?: number
          mes: number
          nomefuncionario: string
          percentualdesempenho: number
          pontosganhos: number
          pontospossiveis: number
          posicao: number
        }
        Update: {
          ano?: number
          funcionarioid?: number
          historicoid?: number
          mes?: number
          nomefuncionario?: string
          percentualdesempenho?: number
          pontosganhos?: number
          pontospossiveis?: number
          posicao?: number
        }
        Relationships: [
          {
            foreignKeyName: "historicoranking_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      itenscontagemestoque: {
        Row: {
          contagemid: number
          eanavulso: string | null
          itemcontagemid: number
          nomeavulso: string | null
          produtoid: number | null
          quantidadecontada: number
        }
        Insert: {
          contagemid: number
          eanavulso?: string | null
          itemcontagemid?: number
          nomeavulso?: string | null
          produtoid?: number | null
          quantidadecontada: number
        }
        Update: {
          contagemid?: number
          eanavulso?: string | null
          itemcontagemid?: number
          nomeavulso?: string | null
          produtoid?: number | null
          quantidadecontada?: number
        }
        Relationships: [
          {
            foreignKeyName: "itenscontagemestoque_contagemid_fkey"
            columns: ["contagemid"]
            isOneToOne: false
            referencedRelation: "contagensestoque"
            referencedColumns: ["contagemid"]
          },
          {
            foreignKeyName: "itenscontagemestoque_produtoid_fkey"
            columns: ["produtoid"]
            isOneToOne: false
            referencedRelation: "produtosestoque"
            referencedColumns: ["produtoid"]
          },
        ]
      }
      itensnotafiscalentrada: {
        Row: {
          itemnotaid: number
          notaid: number
          precocustounitario: number
          produtofornecedorid: number
          quantidade: number
        }
        Insert: {
          itemnotaid?: number
          notaid: number
          precocustounitario: number
          produtofornecedorid: number
          quantidade: number
        }
        Update: {
          itemnotaid?: number
          notaid?: number
          precocustounitario?: number
          produtofornecedorid?: number
          quantidade?: number
        }
        Relationships: [
          {
            foreignKeyName: "itensnotafiscalentrada_notaid_fkey"
            columns: ["notaid"]
            isOneToOne: false
            referencedRelation: "notasfiscaisentrada"
            referencedColumns: ["notaid"]
          },
          {
            foreignKeyName: "itensnotafiscalentrada_produtofornecedorid_fkey"
            columns: ["produtofornecedorid"]
            isOneToOne: false
            referencedRelation: "produtosfornecedor"
            referencedColumns: ["produtofornecedorid"]
          },
        ]
      }
      lucromensalhistorico: {
        Row: {
          ano: number
          dataregistro: string | null
          historicoid: number
          mes: number
          percentuallucro: number
        }
        Insert: {
          ano: number
          dataregistro?: string | null
          historicoid?: number
          mes: number
          percentuallucro: number
        }
        Update: {
          ano?: number
          dataregistro?: string | null
          historicoid?: number
          mes?: number
          percentuallucro?: number
        }
        Relationships: []
      }
      metasdiariasapuracoes: {
        Row: {
          apuracaoid: number
          dataapuracao: string
          funcionarioid_lancamento: number | null
          metaprincipalid: number | null
          pontosmetadiariaganhos: number | null
          valordia: number
        }
        Insert: {
          apuracaoid?: number
          dataapuracao: string
          funcionarioid_lancamento?: number | null
          metaprincipalid?: number | null
          pontosmetadiariaganhos?: number | null
          valordia: number
        }
        Update: {
          apuracaoid?: number
          dataapuracao?: string
          funcionarioid_lancamento?: number | null
          metaprincipalid?: number | null
          pontosmetadiariaganhos?: number | null
          valordia?: number
        }
        Relationships: [
          {
            foreignKeyName: "metasdiariasapuracoes_funcionarioid_lancamento_fkey"
            columns: ["funcionarioid_lancamento"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "metasdiariasapuracoes_metaprincipalid_fkey"
            columns: ["metaprincipalid"]
            isOneToOne: false
            referencedRelation: "metasprincipais"
            referencedColumns: ["metaprincipalid"]
          },
        ]
      }
      metasdiariasinstancias: {
        Row: {
          data: string
          metainstanciaid: number
          metamodeloid: number | null
          status: string | null
          valoratingido: number | null
          valormeta: number
        }
        Insert: {
          data: string
          metainstanciaid?: number
          metamodeloid?: number | null
          status?: string | null
          valoratingido?: number | null
          valormeta: number
        }
        Update: {
          data?: string
          metainstanciaid?: number
          metamodeloid?: number | null
          status?: string | null
          valoratingido?: number | null
          valormeta?: number
        }
        Relationships: []
      }
      metasdiariasmodelos: {
        Row: {
          diasemanaid: number
          nomedia: string
          pontospremio: number
          valormeta: number
        }
        Insert: {
          diasemanaid: number
          nomedia: string
          pontospremio: number
          valormeta: number
        }
        Update: {
          diasemanaid?: number
          nomedia?: string
          pontospremio?: number
          valormeta?: number
        }
        Relationships: []
      }
      metasprincipais: {
        Row: {
          datafim: string
          datainicio: string
          descricao: string | null
          metaprincipalid: number
          nomemeta: string
          pontospremio: number
          setoralvo: string | null
          status: string | null
          valormetatotal: number
        }
        Insert: {
          datafim: string
          datainicio: string
          descricao?: string | null
          metaprincipalid?: number
          nomemeta: string
          pontospremio: number
          setoralvo?: string | null
          status?: string | null
          valormetatotal: number
        }
        Update: {
          datafim?: string
          datainicio?: string
          descricao?: string | null
          metaprincipalid?: number
          nomemeta?: string
          pontospremio?: number
          setoralvo?: string | null
          status?: string | null
          valormetatotal?: number
        }
        Relationships: []
      }
      notasfiscais: {
        Row: {
          datarecebimento: string | null
          fileidtelegram: string
          funcionarioid: number
          notafiscalid: number
          pathfoto: string | null
          status: string | null
        }
        Insert: {
          datarecebimento?: string | null
          fileidtelegram: string
          funcionarioid: number
          notafiscalid?: number
          pathfoto?: string | null
          status?: string | null
        }
        Update: {
          datarecebimento?: string | null
          fileidtelegram?: string
          funcionarioid?: number
          notafiscalid?: number
          pathfoto?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notasfiscais_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      notasfiscaisentrada: {
        Row: {
          dataemissao: string
          dataimportacao: string | null
          fornecedorid: number
          notaid: number
          numeronf: string
          valortotalnf: number
        }
        Insert: {
          dataemissao: string
          dataimportacao?: string | null
          fornecedorid: number
          notaid?: number
          numeronf: string
          valortotalnf: number
        }
        Update: {
          dataemissao?: string
          dataimportacao?: string | null
          fornecedorid?: number
          notaid?: number
          numeronf?: string
          valortotalnf?: number
        }
        Relationships: [
          {
            foreignKeyName: "notasfiscaisentrada_fornecedorid_fkey"
            columns: ["fornecedorid"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["fornecedorid"]
          },
        ]
      }
      onboardingstatus: {
        Row: {
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
            foreignKeyName: "onboardingstatus_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: true
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      picodiario: {
        Row: {
          diasemanaid: number
          horabloqueiofim: string | null
          horabloqueioinicio: string | null
          nomedia: string
        }
        Insert: {
          diasemanaid: number
          horabloqueiofim?: string | null
          horabloqueioinicio?: string | null
          nomedia: string
        }
        Update: {
          diasemanaid?: number
          horabloqueiofim?: string | null
          horabloqueioinicio?: string | null
          nomedia?: string
        }
        Relationships: []
      }
      posicoesloja: {
        Row: {
          ativo: boolean | null
          coordx: number
          coordy: number
          nomeposicao: string
          posicaoid: number
          setor: string | null
        }
        Insert: {
          ativo?: boolean | null
          coordx: number
          coordy: number
          nomeposicao: string
          posicaoid?: number
          setor?: string | null
        }
        Update: {
          ativo?: boolean | null
          coordx?: number
          coordy?: number
          nomeposicao?: string
          posicaoid?: number
          setor?: string | null
        }
        Relationships: []
      }
      produtosestoque: {
        Row: {
          categoria: string | null
          estoqueminimo: number | null
          nomeproduto: string
          produtoid: number
          unidademedida: string
        }
        Insert: {
          categoria?: string | null
          estoqueminimo?: number | null
          nomeproduto: string
          produtoid?: number
          unidademedida: string
        }
        Update: {
          categoria?: string | null
          estoqueminimo?: number | null
          nomeproduto?: string
          produtoid?: number
          unidademedida?: string
        }
        Relationships: []
      }
      produtosfornecedor: {
        Row: {
          codigofornecedor: string | null
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
            foreignKeyName: "produtosfornecedor_fornecedorid_fkey"
            columns: ["fornecedorid"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["fornecedorid"]
          },
          {
            foreignKeyName: "produtosfornecedor_produtoid_fkey"
            columns: ["produtoid"]
            isOneToOne: false
            referencedRelation: "produtosestoque"
            referencedColumns: ["produtoid"]
          },
        ]
      }
      produtosloja: {
        Row: {
          ativo: boolean
          custoempontos: number
          descricao: string | null
          estoquedisponivel: number | null
          nome: string
          produtoid: number
        }
        Insert: {
          ativo?: boolean
          custoempontos: number
          descricao?: string | null
          estoquedisponivel?: number | null
          nome: string
          produtoid?: number
        }
        Update: {
          ativo?: boolean
          custoempontos?: number
          descricao?: string | null
          estoquedisponivel?: number | null
          nome?: string
          produtoid?: number
        }
        Relationships: []
      }
      resgates: {
        Row: {
          dataaprovacao: string | null
          datasolicitacao: string
          funcionarioid: number
          gestorid_aprovacao: number | null
          pontosgastos: number
          produtoid: number
          resgateid: number
          status: string
        }
        Insert: {
          dataaprovacao?: string | null
          datasolicitacao?: string
          funcionarioid: number
          gestorid_aprovacao?: number | null
          pontosgastos: number
          produtoid: number
          resgateid?: number
          status?: string
        }
        Update: {
          dataaprovacao?: string | null
          datasolicitacao?: string
          funcionarioid?: number
          gestorid_aprovacao?: number | null
          pontosgastos?: number
          produtoid?: number
          resgateid?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "resgates_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "resgates_produtoid_fkey"
            columns: ["produtoid"]
            isOneToOne: false
            referencedRelation: "produtosloja"
            referencedColumns: ["produtoid"]
          },
        ]
      }
      solicitacoesinternas: {
        Row: {
          caminhofoto: string | null
          categoria: string | null
          dataconclusao: string | null
          datasolicitacao: string | null
          descricao: string | null
          funcionarioid: number | null
          motivorecusa: string | null
          quantidade: number | null
          solicitacaoid: number
          status: string | null
          tipo: string
        }
        Insert: {
          caminhofoto?: string | null
          categoria?: string | null
          dataconclusao?: string | null
          datasolicitacao?: string | null
          descricao?: string | null
          funcionarioid?: number | null
          motivorecusa?: string | null
          quantidade?: number | null
          solicitacaoid?: number
          status?: string | null
          tipo: string
        }
        Update: {
          caminhofoto?: string | null
          categoria?: string | null
          dataconclusao?: string | null
          datasolicitacao?: string | null
          descricao?: string | null
          funcionarioid?: number | null
          motivorecusa?: string | null
          quantidade?: number | null
          solicitacaoid?: number
          status?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "solicitacoesinternas_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
        ]
      }
      tarefas: {
        Row: {
          ativa: boolean | null
          datacriacao: string | null
          descricao: string | null
          pontos: number
          setor: string | null
          tarefaid: number
          titulo: string
        }
        Insert: {
          ativa?: boolean | null
          datacriacao?: string | null
          descricao?: string | null
          pontos: number
          setor?: string | null
          tarefaid?: number
          titulo: string
        }
        Update: {
          ativa?: boolean | null
          datacriacao?: string | null
          descricao?: string | null
          pontos?: number
          setor?: string | null
          tarefaid?: number
          titulo?: string
        }
        Relationships: []
      }
      tarefasatribuidas: {
        Row: {
          agendamentoid: number | null
          atribuicaoid: number
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
          origematribuicaoid: number | null
          statustarefagrupo: string | null
          tarefaid: number
          tipofrequencia: string
          valorfrequencia: number | null
        }
        Insert: {
          agendamentoid?: number | null
          atribuicaoid?: number
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
          origematribuicaoid?: number | null
          statustarefagrupo?: string | null
          tarefaid: number
          tipofrequencia?: string
          valorfrequencia?: number | null
        }
        Update: {
          agendamentoid?: number | null
          atribuicaoid?: number
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
          origematribuicaoid?: number | null
          statustarefagrupo?: string | null
          tarefaid?: number
          tipofrequencia?: string
          valorfrequencia?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tarefasatribuidas_funcionarioid_fkey"
            columns: ["funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_funcionarioresponsavelid_fkey"
            columns: ["funcionarioresponsavelid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["funcionarioid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_grupoid_fkey"
            columns: ["grupoid"]
            isOneToOne: false
            referencedRelation: "grupos"
            referencedColumns: ["grupoid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_origematribuicaoid_fkey"
            columns: ["origematribuicaoid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: ["atribuicaoid"]
          },
          {
            foreignKeyName: "tarefasatribuidas_tarefaid_fkey"
            columns: ["tarefaid"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["tarefaid"]
          },
        ]
      }
      usuariosadmin: {
        Row: {
          login: string
          nivelacesso: number | null
          nomeexibicao: string | null
          senhahash: string
          usuarioid: number
        }
        Insert: {
          login: string
          nivelacesso?: number | null
          nomeexibicao?: string | null
          senhahash: string
          usuarioid?: number
        }
        Update: {
          login?: string
          nivelacesso?: number | null
          nomeexibicao?: string | null
          senhahash?: string
          usuarioid?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
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
