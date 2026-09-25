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
          aceitawhatsapp: boolean
          agendamentoid: number
          atualizadoem: string
          canceladoem: string | null
          canceladopor: string | null
          contaid: number
          cpfcliente: string | null
          datacriacao: string
          dataevento: string
          funcionarioid: number
          lojaid: number
          motivocancelamento: string | null
          msgconfirmacaoenviada: string | null
          msgcriacaoenviada: string | null
          msgposvendaenviada: string | null
          nomecliente: string
          observacoes: string | null
          realizadoem: string | null
          realizadopor: string | null
          registradopor: string | null
          statusagendamento: string
          statuspagamento: string
          telefonecliente: string | null
          tipoevento: string
          tipoeventoid: number | null
          valor: number | null
        }
        Insert: {
          aceitawhatsapp?: boolean
          agendamentoid?: number
          atualizadoem?: string
          canceladoem?: string | null
          canceladopor?: string | null
          contaid?: number
          cpfcliente?: string | null
          datacriacao?: string
          dataevento: string
          funcionarioid: number
          lojaid: number
          motivocancelamento?: string | null
          msgconfirmacaoenviada?: string | null
          msgcriacaoenviada?: string | null
          msgposvendaenviada?: string | null
          nomecliente: string
          observacoes?: string | null
          realizadoem?: string | null
          realizadopor?: string | null
          registradopor?: string | null
          statusagendamento?: string
          statuspagamento?: string
          telefonecliente?: string | null
          tipoevento: string
          tipoeventoid?: number | null
          valor?: number | null
        }
        Update: {
          aceitawhatsapp?: boolean
          agendamentoid?: number
          atualizadoem?: string
          canceladoem?: string | null
          canceladopor?: string | null
          contaid?: number
          cpfcliente?: string | null
          datacriacao?: string
          dataevento?: string
          funcionarioid?: number
          lojaid?: number
          motivocancelamento?: string | null
          msgconfirmacaoenviada?: string | null
          msgcriacaoenviada?: string | null
          msgposvendaenviada?: string | null
          nomecliente?: string
          observacoes?: string | null
          realizadoem?: string | null
          realizadopor?: string | null
          registradopor?: string | null
          statusagendamento?: string
          statuspagamento?: string
          telefonecliente?: string | null
          tipoevento?: string
          tipoeventoid?: number | null
          valor?: number | null
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
          {
            foreignKeyName: "agendamentos_responsavel_trabalha_na_loja"
            columns: ["funcionarioid", "lojaid"]
            isOneToOne: false
            referencedRelation: "funcionarioslojas"
            referencedColumns: ["funcionarioid", "lojaid"]
          },
          {
            foreignKeyName: "agendamentos_tipo_fk"
            columns: ["contaid", "tipoeventoid"]
            isOneToOne: false
            referencedRelation: "tiposevento"
            referencedColumns: ["contaid", "tipoeventoid"]
          },
        ]
      }
      agendamentosanexos: {
        Row: {
          agendamentoid: number
          anexoid: number
          caminho: string
          contaid: number
          enviadoem: string
          enviadopor: string | null
          lojaid: number
          nomearquivo: string
          removidoem: string | null
          removidopor: string | null
          tamanho: number
          tipoarquivo: string
        }
        Insert: {
          agendamentoid: number
          anexoid?: number
          caminho: string
          contaid?: number
          enviadoem?: string
          enviadopor?: string | null
          lojaid: number
          nomearquivo: string
          removidoem?: string | null
          removidopor?: string | null
          tamanho: number
          tipoarquivo: string
        }
        Update: {
          agendamentoid?: number
          anexoid?: number
          caminho?: string
          contaid?: number
          enviadoem?: string
          enviadopor?: string | null
          lojaid?: number
          nomearquivo?: string
          removidoem?: string | null
          removidopor?: string | null
          tamanho?: number
          tipoarquivo?: string
        }
        Relationships: [
          {
            foreignKeyName: "agendamentosanexos_agendamento_fk"
            columns: ["contaid", "agendamentoid"]
            isOneToOne: false
            referencedRelation: "agendamentos"
            referencedColumns: ["contaid", "agendamentoid"]
          },
          {
            foreignKeyName: "agendamentosanexos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "agendamentosanexos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      agendamentoshistorico: {
        Row: {
          acao: string
          agendamentoid: number
          alteradoem: string
          alteradopor: string | null
          contaid: number
          historicoid: number
          lojaid: number
          motivo: string | null
          valoranterior: string | null
          valornovo: string | null
        }
        Insert: {
          acao: string
          agendamentoid: number
          alteradoem?: string
          alteradopor?: string | null
          contaid?: number
          historicoid?: number
          lojaid: number
          motivo?: string | null
          valoranterior?: string | null
          valornovo?: string | null
        }
        Update: {
          acao?: string
          agendamentoid?: number
          alteradoem?: string
          alteradopor?: string | null
          contaid?: number
          historicoid?: number
          lojaid?: number
          motivo?: string | null
          valoranterior?: string | null
          valornovo?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agendamentoshistorico_agendamento_fk"
            columns: ["contaid", "agendamentoid"]
            isOneToOne: false
            referencedRelation: "agendamentos"
            referencedColumns: ["contaid", "agendamentoid"]
          },
          {
            foreignKeyName: "agendamentoshistorico_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "agendamentoshistorico_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      avisossistema: {
        Row: {
          avisoid: number
          contaid: number
          criadoem: string
          lidoem: string | null
          texto: string
          tipo: string
        }
        Insert: {
          avisoid?: number
          contaid?: number
          criadoem?: string
          lidoem?: string | null
          texto: string
          tipo: string
        }
        Update: {
          avisoid?: number
          contaid?: number
          criadoem?: string
          lidoem?: string | null
          texto?: string
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "avisossistema_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
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
      codigosacesso: {
        Row: {
          canceladoem: string | null
          codigohash: string
          codigoid: number
          contaid: number
          criadoem: string
          criadopor: string | null
          expiraem: string
          funcionarioid: number
          usadoem: string | null
        }
        Insert: {
          canceladoem?: string | null
          codigohash: string
          codigoid?: number
          contaid: number
          criadoem?: string
          criadopor?: string | null
          expiraem: string
          funcionarioid: number
          usadoem?: string | null
        }
        Update: {
          canceladoem?: string | null
          codigohash?: string
          codigoid?: number
          contaid?: number
          criadoem?: string
          criadopor?: string | null
          expiraem?: string
          funcionarioid?: number
          usadoem?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "codigosacesso_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "codigosacesso_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
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
      configuracoeshistorico: {
        Row: {
          alteradoem: string
          alteradopor: string | null
          chave: string
          contaid: number
          historicoid: number
          valoranterior: string | null
          valornovo: string | null
        }
        Insert: {
          alteradoem?: string
          alteradopor?: string | null
          chave: string
          contaid?: number
          historicoid?: number
          valoranterior?: string | null
          valornovo?: string | null
        }
        Update: {
          alteradoem?: string
          alteradopor?: string | null
          chave?: string
          contaid?: number
          historicoid?: number
          valoranterior?: string | null
          valornovo?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "configuracoeshistorico_config_fk"
            columns: ["contaid", "chave"]
            isOneToOne: false
            referencedRelation: "configuracoes"
            referencedColumns: ["contaid", "chave"]
          },
          {
            foreignKeyName: "configuracoeshistorico_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
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
          ativa: boolean
          conquistaid: number
          contaid: number
          contardesde: string | null
          criadoem: string
          criteriodias: number | null
          criteriotipo: string
          criteriovalor: number
          descricao: string
          icone: string | null
          nome: string
          pontosbonus: number | null
        }
        Insert: {
          ativa?: boolean
          conquistaid?: number
          contaid?: number
          contardesde?: string | null
          criadoem?: string
          criteriodias?: number | null
          criteriotipo: string
          criteriovalor: number
          descricao: string
          icone?: string | null
          nome: string
          pontosbonus?: number | null
        }
        Update: {
          ativa?: boolean
          conquistaid?: number
          contaid?: number
          contardesde?: string | null
          criadoem?: string
          criteriodias?: number | null
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
          pontosbonus: number
        }
        Insert: {
          conquistafuncionarioid?: number
          conquistaid: number
          contaid?: number
          dataconquista?: string | null
          funcionarioid: number
          pontosbonus?: number
        }
        Update: {
          conquistafuncionarioid?: number
          conquistaid?: number
          contaid?: number
          dataconquista?: string | null
          funcionarioid?: number
          pontosbonus?: number
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
          codigo: string
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
          codigo: string
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
          codigo?: string
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
          criadopor: string | null
          funcionarioid: number | null
          lojaid: number | null
          papel: string
          userid: string
        }
        Insert: {
          contaid: number
          criadoem?: string
          criadopor?: string | null
          funcionarioid?: number | null
          lojaid?: number | null
          papel?: string
          userid: string
        }
        Update: {
          contaid?: number
          criadoem?: string
          criadopor?: string | null
          funcionarioid?: number | null
          lojaid?: number | null
          papel?: string
          userid?: string
        }
        Relationships: [
          {
            foreignKeyName: "contasusuarios_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "contasusuarios_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      denunciasanonimas: {
        Row: {
          contaid: number
          dataregistro: string
          denunciaid: number
          mensagem: string
          protocolohash: string | null
          respondidoem: string | null
          resposta: string | null
          status: string
          tratadoem: string | null
          tratadopor: string | null
        }
        Insert: {
          contaid?: number
          dataregistro?: string
          denunciaid?: number
          mensagem: string
          protocolohash?: string | null
          respondidoem?: string | null
          resposta?: string | null
          status?: string
          tratadoem?: string | null
          tratadopor?: string | null
        }
        Update: {
          contaid?: number
          dataregistro?: string
          denunciaid?: number
          mensagem?: string
          protocolohash?: string | null
          respondidoem?: string | null
          resposta?: string | null
          status?: string
          tratadoem?: string | null
          tratadopor?: string | null
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
      diasgerados: {
        Row: {
          contaid: number
          dia: string
          geradoem: string
          recuperado: boolean
        }
        Insert: {
          contaid?: number
          dia: string
          geradoem?: string
          recuperado?: boolean
        }
        Update: {
          contaid?: number
          dia?: string
          geradoem?: string
          recuperado?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "diasgerados_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      documentos: {
        Row: {
          alvo: string
          arquivadoem: string | null
          arquivadopor: string | null
          atualizadoem: string
          contaid: number
          conteudo: string
          criadopor: string | null
          datacriacao: string | null
          documentoid: number
          funcionariocriadorid: number | null
          pontosporciencia: number
          primeiracienciaem: string | null
          status: string
          telegramfileidfoto: string | null
          titulo: string
        }
        Insert: {
          alvo?: string
          arquivadoem?: string | null
          arquivadopor?: string | null
          atualizadoem?: string
          contaid?: number
          conteudo: string
          criadopor?: string | null
          datacriacao?: string | null
          documentoid?: number
          funcionariocriadorid?: number | null
          pontosporciencia?: number
          primeiracienciaem?: string | null
          status?: string
          telegramfileidfoto?: string | null
          titulo: string
        }
        Update: {
          alvo?: string
          arquivadoem?: string | null
          arquivadopor?: string | null
          atualizadoem?: string
          contaid?: number
          conteudo?: string
          criadopor?: string | null
          datacriacao?: string | null
          documentoid?: number
          funcionariocriadorid?: number | null
          pontosporciencia?: number
          primeiracienciaem?: string | null
          status?: string
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
      documentosacessos: {
        Row: {
          acao: string
          acessadoem: string
          acessoid: number
          caminho: string
          canal: string
          contaid: number
          documentoid: number | null
          funcionarioid: number | null
          usuario: string | null
        }
        Insert: {
          acao: string
          acessadoem?: string
          acessoid?: number
          caminho: string
          canal?: string
          contaid?: number
          documentoid?: number | null
          funcionarioid?: number | null
          usuario?: string | null
        }
        Update: {
          acao?: string
          acessadoem?: string
          acessoid?: number
          caminho?: string
          canal?: string
          contaid?: number
          documentoid?: number | null
          funcionarioid?: number | null
          usuario?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "documentosacessos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "documentosacessos_documento_fk"
            columns: ["contaid", "documentoid"]
            isOneToOne: false
            referencedRelation: "documentospessoais"
            referencedColumns: ["contaid", "documentoid"]
          },
          {
            foreignKeyName: "documentosacessos_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
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
          desfeitaem: string | null
          desfeitapor: string | null
          documentoid: number
          funcionarioid: number
          motivodesfazer: string | null
          origem: string | null
          pontospagos: number
          registradopor: string | null
          statusassinatura: string
        }
        Insert: {
          assinaturaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          desfeitaem?: string | null
          desfeitapor?: string | null
          documentoid: number
          funcionarioid: number
          motivodesfazer?: string | null
          origem?: string | null
          pontospagos?: number
          registradopor?: string | null
          statusassinatura?: string
        }
        Update: {
          assinaturaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          desfeitaem?: string | null
          desfeitapor?: string | null
          documentoid?: number
          funcionarioid?: number
          motivodesfazer?: string | null
          origem?: string | null
          pontospagos?: number
          registradopor?: string | null
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
      documentoslojas: {
        Row: {
          contaid: number
          documentoid: number
          lojaid: number
        }
        Insert: {
          contaid?: number
          documentoid: number
          lojaid: number
        }
        Update: {
          contaid?: number
          documentoid?: number
          lojaid?: number
        }
        Relationships: [
          {
            foreignKeyName: "documentoslojas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "documentoslojas_documento_fk"
            columns: ["contaid", "documentoid"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["contaid", "documentoid"]
          },
          {
            foreignKeyName: "documentoslojas_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      documentospessoais: {
        Row: {
          arquivadoem: string | null
          arquivadopor: string | null
          caminhoarquivo: string
          contaid: number
          dataupload: string | null
          descricao: string | null
          documentoid: number
          enviadopor: string | null
          excluidoem: string | null
          excluidopor: string | null
          funcionarioid: number
          mesano: string | null
          motivoexclusao: string | null
          nomearquivo: string | null
          situacao: string
          substituidoem: string | null
          substituidopor: number | null
          tamanho: number | null
          tipoarquivo: string | null
          tipodocumento: string
        }
        Insert: {
          arquivadoem?: string | null
          arquivadopor?: string | null
          caminhoarquivo: string
          contaid?: number
          dataupload?: string | null
          descricao?: string | null
          documentoid?: number
          enviadopor?: string | null
          excluidoem?: string | null
          excluidopor?: string | null
          funcionarioid: number
          mesano?: string | null
          motivoexclusao?: string | null
          nomearquivo?: string | null
          situacao?: string
          substituidoem?: string | null
          substituidopor?: number | null
          tamanho?: number | null
          tipoarquivo?: string | null
          tipodocumento: string
        }
        Update: {
          arquivadoem?: string | null
          arquivadopor?: string | null
          caminhoarquivo?: string
          contaid?: number
          dataupload?: string | null
          descricao?: string | null
          documentoid?: number
          enviadopor?: string | null
          excluidoem?: string | null
          excluidopor?: string | null
          funcionarioid?: number
          mesano?: string | null
          motivoexclusao?: string | null
          nomearquivo?: string | null
          situacao?: string
          substituidoem?: string | null
          substituidopor?: number | null
          tamanho?: number | null
          tipoarquivo?: string | null
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
          {
            foreignKeyName: "documentospessoais_substituto_fk"
            columns: ["contaid", "substituidopor"]
            isOneToOne: false
            referencedRelation: "documentospessoais"
            referencedColumns: ["contaid", "documentoid"]
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
          origem: string | null
          registradopor: string | null
          status: string
        }
        Insert: {
          cienciaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid: number
          funcionarioid: number
          origem?: string | null
          registradopor?: string | null
          status?: string
        }
        Update: {
          cienciaid?: number
          contaid?: number
          dataciencia?: string | null
          dataenvio?: string | null
          documentoid?: number
          funcionarioid?: number
          origem?: string | null
          registradopor?: string | null
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
          avisochatid: number | null
          avisomsgid: number | null
          canalenvio: string
          canalvalidacao: string | null
          contaid: number
          dataaprovacao: string | null
          dataenvio: string
          dataestorno: string | null
          datarecusa: string | null
          entregaid: number
          estornadopor: string | null
          fileidtelegram: string | null
          fotoexpiradaem: string | null
          fotoidunico: string | null
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
          validadorfuncionarioid: number | null
        }
        Insert: {
          aprovadopor?: string | null
          atribuicaoid?: number | null
          avisochatid?: number | null
          avisomsgid?: number | null
          canalenvio?: string
          canalvalidacao?: string | null
          contaid?: number
          dataaprovacao?: string | null
          dataenvio?: string
          dataestorno?: string | null
          datarecusa?: string | null
          entregaid?: number
          estornadopor?: string | null
          fileidtelegram?: string | null
          fotoexpiradaem?: string | null
          fotoidunico?: string | null
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
          validadorfuncionarioid?: number | null
        }
        Update: {
          aprovadopor?: string | null
          atribuicaoid?: number | null
          avisochatid?: number | null
          avisomsgid?: number | null
          canalenvio?: string
          canalvalidacao?: string | null
          contaid?: number
          dataaprovacao?: string | null
          dataenvio?: string
          dataestorno?: string | null
          datarecusa?: string | null
          entregaid?: number
          estornadopor?: string | null
          fileidtelegram?: string | null
          fotoexpiradaem?: string | null
          fotoidunico?: string | null
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
          validadorfuncionarioid?: number | null
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
          {
            foreignKeyName: "entregas_validador_fk"
            columns: ["contaid", "validadorfuncionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
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
      fechamentosmensais: {
        Row: {
          ano: number
          atualizadoem: string | null
          contaid: number
          definitivoem: string | null
          fechadoem: string
          fechadopor: string | null
          fechamentoid: number
          mes: number
          motivo: string | null
          origem: string
          situacao: string
          substituidoem: string | null
          versao: number
        }
        Insert: {
          ano: number
          atualizadoem?: string | null
          contaid?: number
          definitivoem?: string | null
          fechadoem?: string
          fechadopor?: string | null
          fechamentoid?: number
          mes: number
          motivo?: string | null
          origem: string
          situacao: string
          substituidoem?: string | null
          versao?: number
        }
        Update: {
          ano?: number
          atualizadoem?: string | null
          contaid?: number
          definitivoem?: string | null
          fechadoem?: string
          fechadopor?: string | null
          fechamentoid?: number
          mes?: number
          motivo?: string | null
          origem?: string
          situacao?: string
          substituidoem?: string | null
          versao?: number
        }
        Relationships: [
          {
            foreignKeyName: "fechamentosmensais_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      feedbacks: {
        Row: {
          anuladoem: string | null
          anuladopor: string | null
          comentario: string | null
          contaid: number
          criadoem: string
          datafeedback: string
          feedbackid: number
          funcionarioid: number
          motivoanulacao: string | null
          notadia: number
          origem: string
          pontosbonus: number
          registradopor: string | null
        }
        Insert: {
          anuladoem?: string | null
          anuladopor?: string | null
          comentario?: string | null
          contaid?: number
          criadoem?: string
          datafeedback: string
          feedbackid?: number
          funcionarioid: number
          motivoanulacao?: string | null
          notadia: number
          origem?: string
          pontosbonus?: number
          registradopor?: string | null
        }
        Update: {
          anuladoem?: string | null
          anuladopor?: string | null
          comentario?: string | null
          contaid?: number
          criadoem?: string
          datafeedback?: string
          feedbackid?: number
          funcionarioid?: number
          motivoanulacao?: string | null
          notadia?: number
          origem?: string
          pontosbonus?: number
          registradopor?: string | null
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
      fotosexpurgo: {
        Row: {
          caminho: string
          contaid: number
          criadoem: string
          entregaid: number
          erro: string | null
          expurgoid: number
          removidoem: string | null
          tentativas: number
        }
        Insert: {
          caminho: string
          contaid?: number
          criadoem?: string
          entregaid: number
          erro?: string | null
          expurgoid?: number
          removidoem?: string | null
          tentativas?: number
        }
        Update: {
          caminho?: string
          contaid?: number
          criadoem?: string
          entregaid?: number
          erro?: string | null
          expurgoid?: number
          removidoem?: string | null
          tentativas?: number
        }
        Relationships: [
          {
            foreignKeyName: "fotosexpurgo_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "fotosexpurgo_entrega_fk"
            columns: ["contaid", "entregaid"]
            isOneToOne: false
            referencedRelation: "entregas"
            referencedColumns: ["contaid", "entregaid"]
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
          acessoredefinidoem: string | null
          acessoredefinidopor: string | null
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
          horariosaida: string | null
          isgestor: boolean | null
          nomecompleto: string
          pinhash: string | null
          pontostotal: number | null
          primeiroacessoem: string | null
          saldopontos: number
          senhahashapp: string | null
          setor: string | null
          telefonewhatsapp: string | null
        }
        Insert: {
          acessoredefinidoem?: string | null
          acessoredefinidopor?: string | null
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
          horariosaida?: string | null
          isgestor?: boolean | null
          nomecompleto: string
          pinhash?: string | null
          pontostotal?: number | null
          primeiroacessoem?: string | null
          saldopontos?: number
          senhahashapp?: string | null
          setor?: string | null
          telefonewhatsapp?: string | null
        }
        Update: {
          acessoredefinidoem?: string | null
          acessoredefinidopor?: string | null
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
          horariosaida?: string | null
          isgestor?: boolean | null
          nomecompleto?: string
          pinhash?: string | null
          pontostotal?: number | null
          primeiroacessoem?: string | null
          saldopontos?: number
          senhahashapp?: string | null
          setor?: string | null
          telefonewhatsapp?: string | null
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
          validador: boolean
        }
        Insert: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          funcionarioid: number
          lojaid: number
          posicaopadraoid?: number | null
          validador?: boolean
        }
        Update: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          funcionarioid?: number
          lojaid?: number
          posicaopadraoid?: number | null
          validador?: boolean
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
          confiabilidade: number
          contaid: number
          esforco: number
          fechamentoid: number
          funcionarioid: number
          historicoid: number
          lojaid: number | null
          mes: number
          nomefuncionario: string
          nota: number
          percentualdesempenho: number
          pontosganhos: number
          pontospossiveis: number
          pontosregulares: number
          posicao: number
        }
        Insert: {
          ano: number
          confiabilidade?: number
          contaid?: number
          esforco?: number
          fechamentoid: number
          funcionarioid: number
          historicoid?: number
          lojaid?: number | null
          mes: number
          nomefuncionario: string
          nota?: number
          percentualdesempenho: number
          pontosganhos: number
          pontospossiveis: number
          pontosregulares?: number
          posicao: number
        }
        Update: {
          ano?: number
          confiabilidade?: number
          contaid?: number
          esforco?: number
          fechamentoid?: number
          funcionarioid?: number
          historicoid?: number
          lojaid?: number | null
          mes?: number
          nomefuncionario?: string
          nota?: number
          percentualdesempenho?: number
          pontosganhos?: number
          pontospossiveis?: number
          pontosregulares?: number
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
            foreignKeyName: "historicoranking_fechamento_fk"
            columns: ["contaid", "fechamentoid"]
            isOneToOne: false
            referencedRelation: "fechamentosmensais"
            referencedColumns: ["contaid", "fechamentoid"]
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
      justificativas: {
        Row: {
          atribuicaoid: number
          contaid: number
          decididoem: string | null
          decididopor: string | null
          dia: string
          funcionarioid: number
          justificativaid: number
          lojaid: number
          motivo: string
          motivorecusa: string | null
          origem: string
          registradoem: string
          registradopor: string | null
          status: string
        }
        Insert: {
          atribuicaoid: number
          contaid?: number
          decididoem?: string | null
          decididopor?: string | null
          dia: string
          funcionarioid: number
          justificativaid?: number
          lojaid: number
          motivo: string
          motivorecusa?: string | null
          origem?: string
          registradoem?: string
          registradopor?: string | null
          status?: string
        }
        Update: {
          atribuicaoid?: number
          contaid?: number
          decididoem?: string | null
          decididopor?: string | null
          dia?: string
          funcionarioid?: number
          justificativaid?: number
          lojaid?: number
          motivo?: string
          motivorecusa?: string | null
          origem?: string
          registradoem?: string
          registradopor?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "justificativas_atribuicao_fk"
            columns: ["contaid", "atribuicaoid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: ["contaid", "atribuicaoid"]
          },
          {
            foreignKeyName: "justificativas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "justificativas_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "justificativas_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
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
          mostrarvalorestv: boolean
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
          mostrarvalorestv?: boolean
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
          mostrarvalorestv?: boolean
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
      mensagensfila: {
        Row: {
          automatica: boolean
          chatid: number
          chave: string | null
          contaid: number
          conteudo: Json
          criadoem: string
          enviadoem: string | null
          erro: string | null
          filaid: number
          funcionarioid: number | null
          juntarchave: string | null
          lojaid: number | null
          naoreenviar: boolean
          proximaem: string
          referencia: number | null
          status: string
          tentativas: number
          tipo: string
        }
        Insert: {
          automatica?: boolean
          chatid: number
          chave?: string | null
          contaid: number
          conteudo: Json
          criadoem?: string
          enviadoem?: string | null
          erro?: string | null
          filaid?: number
          funcionarioid?: number | null
          juntarchave?: string | null
          lojaid?: number | null
          naoreenviar?: boolean
          proximaem?: string
          referencia?: number | null
          status?: string
          tentativas?: number
          tipo: string
        }
        Update: {
          automatica?: boolean
          chatid?: number
          chave?: string | null
          contaid?: number
          conteudo?: Json
          criadoem?: string
          enviadoem?: string | null
          erro?: string | null
          filaid?: number
          funcionarioid?: number | null
          juntarchave?: string | null
          lojaid?: number | null
          naoreenviar?: boolean
          proximaem?: string
          referencia?: number | null
          status?: string
          tentativas?: number
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "mensagensfila_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "mensagensfila_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "mensagensfila_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      mensagensrotinas: {
        Row: {
          alteradoem: string
          alteradopor: string | null
          ativo: boolean
          contaid: number
          lojaid: number
          rotina: string
        }
        Insert: {
          alteradoem?: string
          alteradopor?: string | null
          ativo?: boolean
          contaid?: number
          lojaid: number
          rotina: string
        }
        Update: {
          alteradoem?: string
          alteradopor?: string | null
          ativo?: boolean
          contaid?: number
          lojaid?: number
          rotina?: string
        }
        Relationships: [
          {
            foreignKeyName: "mensagensrotinas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "mensagensrotinas_loja_fk"
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
          atualizadoem: string
          atualizadopor: string | null
          contaid: number
          dataapuracao: string
          descricaometa: string | null
          funcionarioid_lancamento: number | null
          lancadoem: string
          lancadopor: string | null
          lojaid: number
          metaprincipalid: number | null
          origemmeta: string | null
          pontosmetadia: number
          pontosmetadiariaganhos: number | null
          valordia: number
          valormetadia: number | null
        }
        Insert: {
          apuracaoid?: number
          atualizadoem?: string
          atualizadopor?: string | null
          contaid?: number
          dataapuracao: string
          descricaometa?: string | null
          funcionarioid_lancamento?: number | null
          lancadoem?: string
          lancadopor?: string | null
          lojaid: number
          metaprincipalid?: number | null
          origemmeta?: string | null
          pontosmetadia?: number
          pontosmetadiariaganhos?: number | null
          valordia: number
          valormetadia?: number | null
        }
        Update: {
          apuracaoid?: number
          atualizadoem?: string
          atualizadopor?: string | null
          contaid?: number
          dataapuracao?: string
          descricaometa?: string | null
          funcionarioid_lancamento?: number | null
          lancadoem?: string
          lancadopor?: string | null
          lojaid?: number
          metaprincipalid?: number | null
          origemmeta?: string | null
          pontosmetadia?: number
          pontosmetadiariaganhos?: number | null
          valordia?: number
          valormetadia?: number | null
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
      metasespeciais: {
        Row: {
          contaid: number
          criadoem: string
          data: string
          descricao: string
          lojaid: number
          metaespecialid: number
          pontospremio: number
          valormeta: number
        }
        Insert: {
          contaid?: number
          criadoem?: string
          data: string
          descricao: string
          lojaid: number
          metaespecialid?: number
          pontospremio?: number
          valormeta: number
        }
        Update: {
          contaid?: number
          criadoem?: string
          data?: string
          descricao?: string
          lojaid?: number
          metaespecialid?: number
          pontospremio?: number
          valormeta?: number
        }
        Relationships: [
          {
            foreignKeyName: "metasespeciais_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metasespeciais_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      metashistorico: {
        Row: {
          alteradoem: string
          alteradopor: string | null
          apuracaoid: number
          contaid: number
          dataapuracao: string
          historicoid: number
          lojaid: number
          motivo: string | null
          valoranterior: number | null
          valornovo: number
        }
        Insert: {
          alteradoem?: string
          alteradopor?: string | null
          apuracaoid: number
          contaid?: number
          dataapuracao: string
          historicoid?: number
          lojaid: number
          motivo?: string | null
          valoranterior?: number | null
          valornovo: number
        }
        Update: {
          alteradoem?: string
          alteradopor?: string | null
          apuracaoid?: number
          contaid?: number
          dataapuracao?: string
          historicoid?: number
          lojaid?: number
          motivo?: string | null
          valoranterior?: number | null
          valornovo?: number
        }
        Relationships: [
          {
            foreignKeyName: "metashistorico_apuracao_fk"
            columns: ["contaid", "apuracaoid"]
            isOneToOne: false
            referencedRelation: "metasdiariasapuracoes"
            referencedColumns: ["contaid", "apuracaoid"]
          },
          {
            foreignKeyName: "metashistorico_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metashistorico_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      metaspremiacoes: {
        Row: {
          apuracaoid: number | null
          contaid: number
          estornadoem: string | null
          lojaid: number
          metaprincipalid: number | null
          pagoem: string
          pontos: number
          premiacaoid: number
          tipo: string
        }
        Insert: {
          apuracaoid?: number | null
          contaid?: number
          estornadoem?: string | null
          lojaid: number
          metaprincipalid?: number | null
          pagoem?: string
          pontos: number
          premiacaoid?: number
          tipo: string
        }
        Update: {
          apuracaoid?: number | null
          contaid?: number
          estornadoem?: string | null
          lojaid?: number
          metaprincipalid?: number | null
          pagoem?: string
          pontos?: number
          premiacaoid?: number
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "metaspremiacoes_apuracao_fk"
            columns: ["contaid", "apuracaoid"]
            isOneToOne: false
            referencedRelation: "metasdiariasapuracoes"
            referencedColumns: ["contaid", "apuracaoid"]
          },
          {
            foreignKeyName: "metaspremiacoes_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "metaspremiacoes_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "metaspremiacoes_meta_fk"
            columns: ["contaid", "metaprincipalid"]
            isOneToOne: false
            referencedRelation: "metasprincipais"
            referencedColumns: ["contaid", "metaprincipalid"]
          },
        ]
      }
      metasprincipais: {
        Row: {
          atualizadoem: string
          contaid: number
          criadopor: string | null
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
          atualizadoem?: string
          contaid?: number
          criadopor?: string | null
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
          atualizadoem?: string
          contaid?: number
          criadopor?: string | null
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
      missoesaceites: {
        Row: {
          aceiteid: number
          aceitoem: string
          atribuicaoid: number
          canal: string
          contaid: number
          dia: string
          funcionarioid: number
          motivorevogacao: string | null
          novaatribuicaoid: number | null
          revogadoem: string | null
          revogadopor: string | null
        }
        Insert: {
          aceiteid?: number
          aceitoem?: string
          atribuicaoid: number
          canal?: string
          contaid: number
          dia: string
          funcionarioid: number
          motivorevogacao?: string | null
          novaatribuicaoid?: number | null
          revogadoem?: string | null
          revogadopor?: string | null
        }
        Update: {
          aceiteid?: number
          aceitoem?: string
          atribuicaoid?: number
          canal?: string
          contaid?: number
          dia?: string
          funcionarioid?: number
          motivorevogacao?: string | null
          novaatribuicaoid?: number | null
          revogadoem?: string | null
          revogadopor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "missoesaceites_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "missoesaceites_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "missoesaceites_missao_fk"
            columns: ["contaid", "atribuicaoid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: ["contaid", "atribuicaoid"]
          },
        ]
      }
      movimentospontos: {
        Row: {
          assinaturaid: number | null
          conquistafuncionarioid: number | null
          contaid: number
          criadopor: string | null
          datamovimento: string
          descricao: string
          entregaid: number | null
          feedbackid: number | null
          funcionarioid: number
          lojaid: number | null
          movimentoid: number
          pontos: number
          premiacaoid: number | null
          resgateid: number | null
          tipo: string
        }
        Insert: {
          assinaturaid?: number | null
          conquistafuncionarioid?: number | null
          contaid?: number
          criadopor?: string | null
          datamovimento?: string
          descricao: string
          entregaid?: number | null
          feedbackid?: number | null
          funcionarioid: number
          lojaid?: number | null
          movimentoid?: number
          pontos: number
          premiacaoid?: number | null
          resgateid?: number | null
          tipo: string
        }
        Update: {
          assinaturaid?: number | null
          conquistafuncionarioid?: number | null
          contaid?: number
          criadopor?: string | null
          datamovimento?: string
          descricao?: string
          entregaid?: number | null
          feedbackid?: number | null
          funcionarioid?: number
          lojaid?: number | null
          movimentoid?: number
          pontos?: number
          premiacaoid?: number | null
          resgateid?: number | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "movimentospontos_ciencia_fk"
            columns: ["contaid", "assinaturaid"]
            isOneToOne: false
            referencedRelation: "documentosassinaturas"
            referencedColumns: ["contaid", "assinaturaid"]
          },
          {
            foreignKeyName: "movimentospontos_conquista_fk"
            columns: ["contaid", "conquistafuncionarioid"]
            isOneToOne: false
            referencedRelation: "conquistasfuncionarios"
            referencedColumns: ["contaid", "conquistafuncionarioid"]
          },
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
            foreignKeyName: "movimentospontos_feedback_fk"
            columns: ["contaid", "feedbackid"]
            isOneToOne: false
            referencedRelation: "feedbacks"
            referencedColumns: ["contaid", "feedbackid"]
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
            foreignKeyName: "movimentospontos_premiacao_fk"
            columns: ["contaid", "premiacaoid"]
            isOneToOne: false
            referencedRelation: "metaspremiacoes"
            referencedColumns: ["contaid", "premiacaoid"]
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
      onboardingetapas: {
        Row: {
          ativo: boolean
          contaid: number
          criadoem: string
          etapaid: number
          nome: string
          ordem: number
        }
        Insert: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          etapaid?: number
          nome: string
          ordem?: number
        }
        Update: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          etapaid?: number
          nome?: string
          ordem?: number
        }
        Relationships: [
          {
            foreignKeyName: "onboardingetapas_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      onboardingitens: {
        Row: {
          concluidoem: string | null
          concluidopor: string | null
          contaid: number
          criadoem: string
          documentoid: number | null
          etapaid: number
          funcionarioid: number
          itemid: number
          observacao: string | null
        }
        Insert: {
          concluidoem?: string | null
          concluidopor?: string | null
          contaid?: number
          criadoem?: string
          documentoid?: number | null
          etapaid: number
          funcionarioid: number
          itemid?: number
          observacao?: string | null
        }
        Update: {
          concluidoem?: string | null
          concluidopor?: string | null
          contaid?: number
          criadoem?: string
          documentoid?: number | null
          etapaid?: number
          funcionarioid?: number
          itemid?: number
          observacao?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "onboardingitens_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "onboardingitens_documento_fk"
            columns: ["contaid", "documentoid"]
            isOneToOne: false
            referencedRelation: "documentospessoais"
            referencedColumns: ["contaid", "documentoid"]
          },
          {
            foreignKeyName: "onboardingitens_etapa_fk"
            columns: ["contaid", "etapaid"]
            isOneToOne: false
            referencedRelation: "onboardingetapas"
            referencedColumns: ["contaid", "etapaid"]
          },
          {
            foreignKeyName: "onboardingitens_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "onboardingstatus"
            referencedColumns: ["contaid", "funcionarioid"]
          },
        ]
      }
      onboardingstatus: {
        Row: {
          concluidoem: string | null
          contaid: number
          funcionarioid: number
          iniciadoem: string
          iniciadopor: string | null
          statusworkflow: string
        }
        Insert: {
          concluidoem?: string | null
          contaid?: number
          funcionarioid: number
          iniciadoem?: string
          iniciadopor?: string | null
          statusworkflow?: string
        }
        Update: {
          concluidoem?: string | null
          contaid?: number
          funcionarioid?: number
          iniciadoem?: string
          iniciadopor?: string | null
          statusworkflow?: string
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
      rotinasexecucoes: {
        Row: {
          contaid: number
          detalhe: Json | null
          erro: string | null
          execucaoid: number
          iniciadoem: string
          origem: string
          recuperado: boolean
          referencia: string | null
          resultado: string
          rotina: string
          terminadoem: string | null
        }
        Insert: {
          contaid?: number
          detalhe?: Json | null
          erro?: string | null
          execucaoid?: number
          iniciadoem?: string
          origem?: string
          recuperado?: boolean
          referencia?: string | null
          resultado: string
          rotina: string
          terminadoem?: string | null
        }
        Update: {
          contaid?: number
          detalhe?: Json | null
          erro?: string | null
          execucaoid?: number
          iniciadoem?: string
          origem?: string
          recuperado?: boolean
          referencia?: string | null
          resultado?: string
          rotina?: string
          terminadoem?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "rotinasexecucoes_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      senhasgestor: {
        Row: {
          atualizadoem: string
          contaid: number | null
          senhahashapp: string
          userid: string
        }
        Insert: {
          atualizadoem?: string
          contaid?: number | null
          senhahashapp: string
          userid: string
        }
        Update: {
          atualizadoem?: string
          contaid?: number | null
          senhahashapp?: string
          userid?: string
        }
        Relationships: [
          {
            foreignKeyName: "senhasgestor_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      solicitacoeshistorico: {
        Row: {
          alteradoem: string
          alteradopor: string | null
          contaid: number
          historicoid: number
          lojaid: number
          observacao: string | null
          solicitacaoid: number
          statusanterior: string | null
          statusnovo: string
        }
        Insert: {
          alteradoem?: string
          alteradopor?: string | null
          contaid?: number
          historicoid?: number
          lojaid: number
          observacao?: string | null
          solicitacaoid: number
          statusanterior?: string | null
          statusnovo: string
        }
        Update: {
          alteradoem?: string
          alteradopor?: string | null
          contaid?: number
          historicoid?: number
          lojaid?: number
          observacao?: string | null
          solicitacaoid?: number
          statusanterior?: string | null
          statusnovo?: string
        }
        Relationships: [
          {
            foreignKeyName: "solicitacoeshistorico_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "solicitacoeshistorico_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "solicitacoeshistorico_solicitacao_fk"
            columns: ["contaid", "solicitacaoid"]
            isOneToOne: false
            referencedRelation: "solicitacoesinternas"
            referencedColumns: ["contaid", "solicitacaoid"]
          },
        ]
      }
      solicitacoesinternas: {
        Row: {
          atualizadoem: string
          caminhofoto: string | null
          categoria: string | null
          contaid: number
          dataconclusao: string | null
          datasolicitacao: string
          descricao: string | null
          funcionarioid: number | null
          lojaid: number
          motivorecusa: string | null
          quantidade: number | null
          registradopor: string | null
          solicitacaoid: number
          status: string
          tipo: string
          unidade: string | null
        }
        Insert: {
          atualizadoem?: string
          caminhofoto?: string | null
          categoria?: string | null
          contaid?: number
          dataconclusao?: string | null
          datasolicitacao?: string
          descricao?: string | null
          funcionarioid?: number | null
          lojaid: number
          motivorecusa?: string | null
          quantidade?: number | null
          registradopor?: string | null
          solicitacaoid?: number
          status?: string
          tipo: string
          unidade?: string | null
        }
        Update: {
          atualizadoem?: string
          caminhofoto?: string | null
          categoria?: string | null
          contaid?: number
          dataconclusao?: string | null
          datasolicitacao?: string
          descricao?: string | null
          funcionarioid?: number | null
          lojaid?: number
          motivorecusa?: string | null
          quantidade?: number | null
          registradopor?: string | null
          solicitacaoid?: number
          status?: string
          tipo?: string
          unidade?: string | null
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
          compartilhada: boolean
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
          compartilhada?: boolean
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
          compartilhada?: boolean
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
            foreignKeyName: "tarefasatribuidas_agendamento_fk"
            columns: ["contaid", "agendamentoid"]
            isOneToOne: false
            referencedRelation: "agendamentos"
            referencedColumns: ["contaid", "agendamentoid"]
          },
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
      tarefasdodia: {
        Row: {
          atribuicaoid: number
          atualizadoem: string | null
          contaid: number
          dia: string
          funcionarioid: number
          geradoem: string
          itemid: number
          lojaid: number
          passadaatribuicaoid: number | null
          passadaem: string | null
          passadapara: number | null
          passadapor: string | null
          pontos: number
          recuperado: boolean
          situacao: string
          tarefaid: number
          tipofrequencia: string
        }
        Insert: {
          atribuicaoid: number
          atualizadoem?: string | null
          contaid?: number
          dia: string
          funcionarioid: number
          geradoem?: string
          itemid?: number
          lojaid: number
          passadaatribuicaoid?: number | null
          passadaem?: string | null
          passadapara?: number | null
          passadapor?: string | null
          pontos: number
          recuperado?: boolean
          situacao: string
          tarefaid: number
          tipofrequencia: string
        }
        Update: {
          atribuicaoid?: number
          atualizadoem?: string | null
          contaid?: number
          dia?: string
          funcionarioid?: number
          geradoem?: string
          itemid?: number
          lojaid?: number
          passadaatribuicaoid?: number | null
          passadaem?: string | null
          passadapara?: number | null
          passadapor?: string | null
          pontos?: number
          recuperado?: boolean
          situacao?: string
          tarefaid?: number
          tipofrequencia?: string
        }
        Relationships: [
          {
            foreignKeyName: "tarefasdodia_atribuicao_fk"
            columns: ["contaid", "atribuicaoid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: ["contaid", "atribuicaoid"]
          },
          {
            foreignKeyName: "tarefasdodia_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "tarefasdodia_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "tarefasdodia_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
          {
            foreignKeyName: "tarefasdodia_passadaatribuicao_fk"
            columns: ["contaid", "passadaatribuicaoid"]
            isOneToOne: false
            referencedRelation: "tarefasatribuidas"
            referencedColumns: ["contaid", "atribuicaoid"]
          },
          {
            foreignKeyName: "tarefasdodia_passadapara_fk"
            columns: ["contaid", "passadapara"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "tarefasdodia_tarefa_fk"
            columns: ["contaid", "tarefaid"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["contaid", "tarefaid"]
          },
        ]
      }
      acessoslojaeventos: {
        Row: { contaid: number; em: string; evento: string; eventoid: number; lojaid: number; userid: string | null }
        Insert: { contaid?: number; em?: string; evento: string; eventoid?: number; lojaid: number; userid?: string | null }
        Update: { contaid?: number; em?: string; evento?: string; eventoid?: number; lojaid?: number; userid?: string | null }
        Relationships: []
      }
      tarefascandidatos: {
        Row: { atribuicaoid: number; contaid: number; funcionarioid: number }
        Insert: { atribuicaoid: number; contaid?: number; funcionarioid: number }
        Update: { atribuicaoid?: number; contaid?: number; funcionarioid?: number }
        Relationships: []
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
      telegramconvites: {
        Row: {
          canceladoem: string | null
          codigohash: string
          contaid: number
          conviteid: number
          criadoem: string
          criadopor: string | null
          expiraem: string
          funcionarioid: number | null
          lojaid: number | null
          papelgrupo: string | null
          tipo: string
          usadoem: string | null
          userid: string | null
        }
        Insert: {
          canceladoem?: string | null
          codigohash: string
          contaid?: number
          conviteid?: number
          criadoem?: string
          criadopor?: string | null
          expiraem: string
          funcionarioid?: number | null
          lojaid?: number | null
          papelgrupo?: string | null
          tipo: string
          usadoem?: string | null
          userid?: string | null
        }
        Update: {
          canceladoem?: string | null
          codigohash?: string
          contaid?: number
          conviteid?: number
          criadoem?: string
          criadopor?: string | null
          expiraem?: string
          funcionarioid?: number | null
          lojaid?: number | null
          papelgrupo?: string | null
          tipo?: string
          usadoem?: string | null
          userid?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "telegramconvites_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "telegramconvites_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "telegramconvites_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      telegramvinculos: {
        Row: {
          ativo: boolean
          bloqueadoem: string | null
          chatid: number
          contaid: number
          desligadoem: string | null
          desligadopor: string | null
          funcionarioid: number | null
          lojaid: number | null
          nometelegram: string | null
          papelgrupo: string | null
          tipo: string
          userid: string | null
          vinculadoem: string
          vinculoid: number
        }
        Insert: {
          ativo?: boolean
          bloqueadoem?: string | null
          chatid: number
          contaid?: number
          desligadoem?: string | null
          desligadopor?: string | null
          funcionarioid?: number | null
          lojaid?: number | null
          nometelegram?: string | null
          papelgrupo?: string | null
          tipo: string
          userid?: string | null
          vinculadoem?: string
          vinculoid?: number
        }
        Update: {
          ativo?: boolean
          bloqueadoem?: string | null
          chatid?: number
          contaid?: number
          desligadoem?: string | null
          desligadopor?: string | null
          funcionarioid?: number | null
          lojaid?: number | null
          nometelegram?: string | null
          papelgrupo?: string | null
          tipo?: string
          userid?: string | null
          vinculadoem?: string
          vinculoid?: number
        }
        Relationships: [
          {
            foreignKeyName: "telegramvinculos_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "telegramvinculos_funcionario_fk"
            columns: ["contaid", "funcionarioid"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["contaid", "funcionarioid"]
          },
          {
            foreignKeyName: "telegramvinculos_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
      tentativasacesso: {
        Row: {
          chave: string
          contaid: number | null
          em: string
          origem: string
          sucesso: boolean
          tentativaid: number
          tipo: string
        }
        Insert: {
          chave: string
          contaid?: number | null
          em?: string
          origem: string
          sucesso: boolean
          tentativaid?: number
          tipo: string
        }
        Update: {
          chave?: string
          contaid?: number | null
          em?: string
          origem?: string
          sucesso?: boolean
          tentativaid?: number
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "tentativasacesso_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      tiposevento: {
        Row: {
          ativo: boolean
          contaid: number
          criadoem: string
          nome: string
          tipoeventoid: number
        }
        Insert: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          nome: string
          tipoeventoid?: number
        }
        Update: {
          ativo?: boolean
          contaid?: number
          criadoem?: string
          nome?: string
          tipoeventoid?: number
        }
        Relationships: [
          {
            foreignKeyName: "tiposevento_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
        ]
      }
      usomensagens: {
        Row: {
          canal: string
          contaid: number
          dia: string
          lojaid: number | null
          quantidade: number
          tipo: string
        }
        Insert: {
          canal: string
          contaid: number
          dia: string
          lojaid?: number | null
          quantidade?: number
          tipo: string
        }
        Update: {
          canal?: string
          contaid?: number
          dia?: string
          lojaid?: number | null
          quantidade?: number
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "usomensagens_contaid_fkey"
            columns: ["contaid"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["contaid"]
          },
          {
            foreignKeyName: "usomensagens_loja_fk"
            columns: ["contaid", "lojaid"]
            isOneToOne: false
            referencedRelation: "lojas"
            referencedColumns: ["contaid", "lojaid"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      abrir_solicitacao: {
        Args: {
          p_categoria: string
          p_descricao: string
          p_funcionarioid: number
          p_lojaid: number
          p_quantidade?: number
          p_tipo: string
          p_unidade?: string
        }
        Returns: number
      }
      acesso_por_email: { Args: { p_email: string }; Returns: Json }
      agenda_para_painel: {
        Args: { p_contaid: number; p_lojaid: number; p_tv: boolean }
        Returns: Json
      }
      agendamento_para_mudar: {
        Args: { p_agendamentoid: number }
        Returns: {
          aceitawhatsapp: boolean
          agendamentoid: number
          atualizadoem: string
          canceladoem: string | null
          canceladopor: string | null
          contaid: number
          cpfcliente: string | null
          datacriacao: string
          dataevento: string
          funcionarioid: number
          lojaid: number
          motivocancelamento: string | null
          msgconfirmacaoenviada: string | null
          msgcriacaoenviada: string | null
          msgposvendaenviada: string | null
          nomecliente: string
          observacoes: string | null
          realizadoem: string | null
          realizadopor: string | null
          registradopor: string | null
          statusagendamento: string
          statuspagamento: string
          telefonecliente: string | null
          tipoevento: string
          tipoeventoid: number | null
          valor: number | null
        }
        SetofOptions: {
          from: "*"
          to: "agendamentos"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      alcance_do_comunicado: {
        Args: { p_documentoid: number }
        Returns: number[]
      }
      alterar_configuracao: {
        Args: { p_chave: string; p_valor: string }
        Returns: string
      }
      alterar_pagamento_agendamento: {
        Args: { p_agendamentoid: number; p_status: string; p_valor?: number }
        Returns: undefined
      }
      analise_de_tarefas: {
        Args: { p_ate: string; p_de: string; p_lojaid?: number }
        Returns: Json
      }
      anular_feedback: {
        Args: { p_feedbackid: number; p_motivo: string }
        Returns: undefined
      }
      apos_aprovar_entrega: {
        Args: { p_entregaid: number }
        Returns: undefined
      }
      aprovar_entrega: { Args: { p_entregaid: number }; Returns: number }
      arquivar_comunicado: {
        Args: { p_documentoid: number }
        Returns: undefined
      }
      arquivar_documento_pessoal: {
        Args: { p_documentoid: number }
        Returns: undefined
      }
      atribuir_tarefa: {
        Args: {
          p_dataagendamento?: string
          p_funcionarios: number[] | null
          p_horariodisparo?: string
          p_lojaid: number
          p_tarefaid: number
          p_tipofrequencia: string
          p_valorfrequencia?: number
        }
        Returns: number
      }
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
      avaliar_conquistas: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: number
      }
      bot_abertas_da_pessoa: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: Json
      }
      bot_chat_da_pessoa: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: number
      }
      bot_chat_do_grupo: {
        Args: { p_contaid: number; p_lojaid: number; p_papel: string }
        Returns: number
      }
      bot_ciencia: {
        Args: { p_assinaturaid: number; p_chatid: number }
        Returns: Json
      }
      bot_ciencia_documento: {
        Args: { p_chatid: number; p_documentoid: number }
        Returns: Json
      }
      bot_comanda: {
        Args: { p_chatid: number; p_valor: number }
        Returns: Json
      }
      bot_comanda_iniciar: { Args: { p_chatid: number }; Returns: Json }
      bot_conferir_foto: {
        Args: { p_chatid: number; p_fotoidunico: string }
        Returns: Json
      }
      bot_consulta: {
        Args: { p_chatid: number; p_item: string }
        Returns: Json
      }
      bot_contexto_confiavel: { Args: never; Returns: boolean }
      bot_documento: {
        Args: { p_chatid: number; p_documentoid: number; p_tipochat: string }
        Returns: Json
      }
      bot_enfileirar: {
        Args: {
          p_chatid: number
          p_contaid: number
          p_conteudo: Json
          p_lojaid: number
          p_referencia: number
          p_tipo: string
        }
        Returns: undefined
      }
      bot_enfileirar_ex: {
        Args: {
          p_chatid: number
          p_chave: string
          p_contaid: number
          p_conteudo: Json
          p_funcionarioid: number
          p_juntarchave: string
          p_lojaid: number
          p_naoreenviar: boolean
          p_quando: string
          p_referencia: number
          p_tipo: string
        }
        Returns: number
      }
      bot_entrar: {
        Args: { p_contaid: number; p_funcionarioid: number; p_userid: string }
        Returns: undefined
      }
      bot_entrar_pessoa: { Args: { p_chatid: number }; Returns: Json }
      bot_enviadas_hoje: {
        Args: { p_agora: string; p_contaid: number; p_funcionarioid: number }
        Returns: number
      }
      bot_erro: { Args: { p_mensagem: string }; Returns: Json }
      bot_escolher_conta: {
        Args: { p_chatid: number; p_contaid: number }
        Returns: Json
      }
      bot_estado: {
        Args: { p_chatid: number; p_usuarioid: number }
        Returns: Json
      }
      bot_falta_feedback_ontem: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: boolean
      }
      bot_feedback: {
        Args: { p_chatid: number; p_nota: number; p_quando: string }
        Returns: Json
      }
      bot_fila_disparar: { Args: never; Returns: undefined }
      bot_fila_pegar: { Args: { p_limite: number }; Returns: Json }
      bot_fila_resultado: {
        Args: {
          p_erro: string
          p_esperar: number
          p_filaid: number
          p_msgid: number
          p_ok: boolean
        }
        Returns: undefined
      }
      bot_grupo: { Args: { p_chatid: number }; Returns: Json }
      bot_guardar_estado: {
        Args: {
          p_chatid: number
          p_contaid: number
          p_dados: Json
          p_estado: string
          p_minutos: number
          p_usuarioid: number
        }
        Returns: undefined
      }
      bot_html: { Args: { p_texto: string }; Returns: string }
      bot_iniciar_entrega: {
        Args: { p_atribuicaoid: number; p_chatid: number }
        Returns: Json
      }
      bot_janela: {
        Args: { p_agora: string; p_contaid: number; p_funcionarioid: number }
        Returns: Json
      }
      bot_lancar: {
        Args: {
          p_chatgrupo: number
          p_motivo: string
          p_usuario: number
          p_valor: number
        }
        Returns: Json
      }
      bot_legenda_entrega: { Args: { p_entregaid: number }; Returns: Json }
      bot_limpar_estado: {
        Args: { p_chatid: number; p_usuarioid: number }
        Returns: undefined
      }
      bot_lista_tarefas: { Args: { p_itens: Json }; Returns: Json }
      bot_marcar_bloqueio: {
        Args: { p_chatid: number; p_contaid: number; p_erro: string }
        Returns: undefined
      }
      bot_nao_aplicavel: {
        Args: { p_chatid: number; p_motivo: string }
        Returns: Json
      }
      bot_nao_aplicavel_iniciar: {
        Args: { p_atribuicaoid: number; p_chatid: number }
        Returns: Json
      }
      bot_pegar_folga: {
        Args: { p_atribuicaoid: number; p_chatgrupo: number; p_usuario: number }
        Returns: Json
      }
      bot_pegar_missao: {
        Args: { p_atribuicaoid: number; p_chatgrupo: number; p_usuario: number }
        Returns: Json
      }
      bot_pendencias: {
        Args: { p_chatgrupo: number; p_usuario: number }
        Returns: Json
      }
      bot_pessoa_do_chat: { Args: { p_chatid: number }; Returns: Json }
      bot_pessoa_do_grupo: {
        Args: { p_chatgrupo: number; p_usuario: number }
        Returns: Json
      }
      bot_quem: { Args: { p_chatid: number }; Returns: Json }
      bot_recusa_guardar: {
        Args: {
          p_chatgrupo: number
          p_entregaid: number
          p_msgid: number
          p_usuario: number
        }
        Returns: undefined
      }
      bot_recusa_motivo: {
        Args: {
          p_chatgrupo: number
          p_motivo: string
          p_respostaa: number
          p_usuario: number
        }
        Returns: Json
      }
      bot_recusa_pedir: {
        Args: { p_chatgrupo: number; p_entregaid: number; p_usuario: number }
        Returns: Json
      }
      bot_registrar_entrega: {
        Args: {
          p_atribuicaoid: number
          p_caminho: string
          p_chatid: number
          p_fileid: string
          p_fotoidunico: string
        }
        Returns: Json
      }
      bot_registrar_update: { Args: { p_updateid: number }; Returns: boolean }
      bot_registrar_uso: {
        Args: { p_chatid: number; p_qtd: number; p_tipo: string }
        Returns: undefined
      }
      bot_resgatar: {
        Args: { p_chatid: number; p_produtoid: number }
        Returns: Json
      }
      bot_resumo_ausencia: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: Json
      }
      bot_status_meta: {
        Args: { p_chatgrupo: number; p_usuario: number }
        Returns: Json
      }
      bot_tarefas: { Args: { p_chatid: number }; Returns: Json }
      bot_texto_grupo: {
        Args: { p_chatgrupo: number; p_referencia: number; p_tipo: string }
        Returns: Json
      }
      bot_texto_juntado: { Args: { p_conteudos: Json }; Returns: string }
      bot_texto_rotina: {
        Args: {
          p_contaid: number
          p_funcionarioid: number
          p_referencia: number
          p_tipo: string
        }
        Returns: Json
      }
      bot_usar_convite: {
        Args: {
          p_chatid: number
          p_codigo: string
          p_nome: string
          p_tipochat: string
        }
        Returns: Json
      }
      bot_validador: {
        Args: { p_chatgrupo: number; p_usuario: number }
        Returns: Json
      }
      bot_validar: {
        Args: {
          p_aprovar: boolean
          p_chatgrupo: number
          p_entregaid: number
          p_motivo?: string
          p_usuario: number
        }
        Returns: Json
      }
      bot_visto: { Args: { p_chatid: number }; Returns: undefined }
      canal_atual: { Args: never; Returns: string }
      cancelar_agendamento: {
        Args: { p_agendamentoid: number; p_motivo: string }
        Returns: undefined
      }
      cancelar_troca: {
        Args: { p_motivo: string; p_resgateid: number }
        Returns: undefined
      }
      concluir_troca: { Args: { p_resgateid: number }; Returns: undefined }
      conflitos_agendamento: {
        Args: { p_dataevento: string; p_ignorar?: number; p_lojaid: number }
        Returns: Json
      }
      consultar_relato: {
        Args: { p_contaid: number; p_protocolo: string }
        Returns: Json
      }
      conta_do_bot: { Args: never; Returns: number }
      conta_do_codigo: { Args: { p_codigo: string }; Returns: number }
      cpf_valido: { Args: { p_cpf: string }; Returns: boolean }
      cria_configuracoes_padrao: {
        Args: { p_contaid: number }
        Returns: undefined
      }
      cria_etapas_onboarding_padrao: {
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
      cria_tipos_evento_padrao: {
        Args: { p_contaid: number }
        Returns: undefined
      }
      criar_acesso_colaborador: {
        Args: {
          p_contaid: number
          p_funcionarioid: number
          p_pinhash: string
          p_quem: string
          p_userid: string
        }
        Returns: boolean
      }
      criar_acesso_loja: {
        Args: {
          p_contaid: number
          p_lojaid: number
          p_quem: string
          p_userid: string
        }
        Returns: undefined
      }
      criar_agendamento: {
        Args: {
          p_aceitawhatsapp?: boolean
          p_cpf?: string
          p_dataevento: string
          p_lojaid: number
          p_nomecliente: string
          p_observacoes?: string
          p_pagamento?: string
          p_responsavelid?: number
          p_telefone?: string
          p_tipoeventoid: number
          p_valor?: number
        }
        Returns: number
      }
      criar_codigo_acesso: {
        Args: {
          p_codigohash: string
          p_contaid: number
          p_dias: number
          p_funcionarioid: number
          p_quem: string
        }
        Returns: undefined
      }
      criar_conquista: {
        Args: {
          p_bonus: number
          p_descricao: string
          p_dias: number
          p_icone: string
          p_nome: string
          p_retroativa: boolean
          p_tipo: string
          p_valor: number
        }
        Returns: Json
      }
      criar_convite_grupo: {
        Args: { p_lojaid: number; p_papel: string }
        Returns: string
      }
      criar_convite_meu_telegram: { Args: never; Returns: string }
      criar_convite_telegram: {
        Args: { p_funcionarioid: number }
        Returns: string
      }
      criar_link_tv: {
        Args: { p_lojaid: number; p_nome: string }
        Returns: string
      }
      criterio_disponivel: { Args: { p_tipo: string }; Returns: boolean }
      decidir_justificativa: {
        Args: {
          p_aceitar: boolean
          p_justificativaid: number
          p_motivo?: string
        }
        Returns: undefined
      }
      definir_horario_equipe: {
        Args: { p_entrada: string; p_funcionarios: number[]; p_saida: string }
        Returns: number
      }
      definir_pin: {
        Args: {
          p_contaid: number
          p_funcionarioid: number
          p_pinhash: string
          p_provisorio?: boolean
        }
        Returns: undefined
      }
      definir_rotina_mensagem: {
        Args: { p_ativo: boolean; p_lojaid: number; p_rotina: string }
        Returns: undefined
      }
      definir_senha_app: {
        Args: { p_contaid: number; p_funcionarioid: number; p_hash: string }
        Returns: undefined
      }
      definir_senha_gestor: {
        Args: { p_contaid: number; p_hash: string; p_userid: string }
        Returns: undefined
      }
      desfazer_ciencia: {
        Args: { p_assinaturaid: number; p_motivo: string }
        Returns: undefined
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
      desligar_telegram: { Args: { p_vinculoid: number }; Returns: undefined }
      dia_de_trabalho: {
        Args: {
          p_dia: string
          p_diadefolga: number
          p_domingofolga: number
          p_fimafast: string
          p_inicioafast: string
        }
        Returns: boolean
      }
      dia_em_sao_paulo: { Args: { p_instante: string }; Returns: string }
      diagnostico_do_sistema: { Args: never; Returns: Json }
      dias_guardar_foto: { Args: { p_contaid: number }; Returns: number }
      documento_rh_liberado: {
        Args: { p_acao: string; p_nome: string }
        Returns: boolean
      }
      editar_agendamento: {
        Args: {
          p_aceitawhatsapp: boolean
          p_agendamentoid: number
          p_cpf: string
          p_nomecliente: string
          p_observacoes: string
          p_telefone: string
          p_tipoeventoid: number
        }
        Returns: undefined
      }
      editar_comunicado: {
        Args: {
          p_conteudo: string
          p_documentoid: number
          p_pontos: number
          p_titulo: string
        }
        Returns: undefined
      }
      eh_admin_geral: { Args: never; Returns: boolean }
      entrar_na_visao: {
        Args: {
          p_canal: string
          p_contaid: number
          p_funcionarioid: number
          p_lojaid: number
        }
        Returns: undefined
      }
      equipe_da_meta: {
        Args: { p_contaid: number; p_dia: string; p_lojaid: number }
        Returns: number[]
      }
      estornar_entrega: {
        Args: { p_entregaid: number; p_motivo: string }
        Returns: number
      }
      estornar_premio_meta: {
        Args: { p_motivo: string; p_premiacaoid: number }
        Returns: undefined
      }
      estornar_troca: {
        Args: { p_motivo: string; p_resgateid: number }
        Returns: undefined
      }
      excluir_documento_por_engano: {
        Args: { p_documentoid: number; p_motivo: string }
        Returns: string
      }
      exige_master_editavel: { Args: never; Returns: number }
      expurgo_pegar: { Args: { p_limite?: number }; Returns: Json }
      expurgo_resultado: {
        Args: { p_erro?: string; p_ids: number[] }
        Returns: undefined
      }
      extrato_pontos: {
        Args: { p_ate: string; p_de: string; p_funcionarioid: number }
        Returns: Json
      }
      fechamento_calcular: {
        Args: { p_contaid: number; p_fechamentoid: number }
        Returns: number
      }
      fora_do_comunicado: { Args: { p_documentoid: number }; Returns: Json }
      fotos_expurgo_disparar: { Args: never; Returns: undefined }
      funcionario_do_bot: { Args: never; Returns: number }
      historico_da_pessoa: {
        Args: { p_funcionarioid: number; p_limite?: number }
        Returns: Json
      }
      incluir_destinatarios: {
        Args: { p_documentoid: number; p_funcionarios: number[] }
        Returns: number
      }
      iniciar_onboarding: { Args: { p_funcionarioid: number }; Returns: number }
      instante_local: {
        Args: { p_dia: string; p_hora: string }
        Returns: string
      }
      item_tratado: {
        Args: {
          p_atribuicaoid: number
          p_dia: string
          p_passadapara: number
          p_tipo: string
        }
        Returns: boolean
      }
      jornada_da_pessoa: {
        Args: { p_contaid: number; p_dia: string; p_funcionarioid: number }
        Returns: {
          fim: string
          inicio: string
          temhorario: boolean
          trabalha: boolean
        }[]
      }
      justificaveis: {
        Args: { p_dia: string; p_funcionarioid: number }
        Returns: Json
      }
      lancar_venda_do_dia: {
        Args: {
          p_dia: string
          p_lojaid: number
          p_motivo?: string
          p_valor: number
        }
        Returns: number
      }
      liberar_documento_pessoal: {
        Args: { p_documentoid: number }
        Returns: string
      }
      limpar_senha_gestor: { Args: { p_userid: string }; Returns: undefined }
      lista_candidatos: {
        Args: { p_contaid: number; p_dia: string }
        Returns: {
          atribuicaoid: number
          funcionarioid: number
          lojaid: number
          pontos: number
          situacao: string
          tarefaid: number
          tipofrequencia: string
        }[]
      }
      lista_do_dia_gerar: {
        Args: {
          p_contaid: number
          p_dia: string
          p_hoje: string
          p_recuperado: boolean
        }
        Returns: Json
      }
      listar_trocas: { Args: { p_limite?: number }; Returns: Json }
      loja_da_visao: { Args: never; Returns: number }
      maior_sequencia: {
        Args: {
          p_diadefolga: number
          p_domingofolga: number
          p_feitos: string[]
          p_fimafast: string
          p_inicioafast: string
          p_neutros: string[]
        }
        Returns: number
      }
      marcar_agendamento_realizado: {
        Args: { p_agendamentoid: number }
        Returns: undefined
      }
      marcar_aviso_lido: { Args: { p_avisoid: number }; Returns: undefined }
      marcar_etapa_onboarding: {
        Args: {
          p_documentoid?: number
          p_feito: boolean
          p_itemid: number
          p_observacao?: string
        }
        Returns: undefined
      }
      marcar_senha_trocada: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: undefined
      }
      meta_do_dia: {
        Args: { p_dia: string; p_lojaid: number }
        Returns: {
          descricao: string
          origem: string
          pontospremio: number
          valormeta: number
        }[]
      }
      meta_para_painel: {
        Args: { p_contaid: number; p_lojaid: number; p_tv: boolean }
        Returns: Json
      }
      metas_do_mes: { Args: { p_lojaid: number; p_mes: string }; Returns: Json }
      meu_acesso: { Args: never; Returns: Json }
      minha_conta: { Args: never; Returns: number }
      minha_conta_editavel: { Args: never; Returns: number }
      minha_politica_de_uso: { Args: never; Returns: Json }
      minha_taxa: { Args: never; Returns: number }
      montar_painel: {
        Args: { p_contaid: number; p_lojaid: number; p_tv: boolean }
        Returns: Json
      }
      mudar_situacao_solicitacao: {
        Args: {
          p_observacao?: string
          p_solicitacaoid: number
          p_status: string
        }
        Returns: undefined
      }
      no_silencio: {
        Args: { p_contaid: number; p_hora: string }
        Returns: boolean
      }
      nome_curto: { Args: { p_nome: string }; Returns: string }
      origem_da_acao: { Args: { p_origem_bot: string }; Returns: string }
      pagar_premio_meta: {
        Args: {
          p_apuracaoid: number
          p_contaid: number
          p_descricao: string
          p_dia: string
          p_lojaid: number
          p_metaprincipalid: number
          p_pontos: number
          p_tipo: string
        }
        Returns: number
      }
      painel_da_loja: { Args: { p_lojaid: number }; Returns: Json }
      painel_da_tv: { Args: { p_codigo: string }; Returns: Json }
      painel_inicio: { Args: { p_lojaid?: number }; Returns: Json }
      passada_hoje: {
        Args: { p_atribuicaoid: number; p_dia: string }
        Returns: boolean
      }
      passar_tarefa_de_folga: {
        Args: { p_atribuicaoid: number; p_funcionarioid: number }
        Returns: number
      }
      pasta_de_agendamento_minha: {
        Args: { p_editavel: boolean; p_nome: string }
        Returns: boolean
      }
      fila_da_loja: {
        Args: { p_lojaid: number }
        Returns: {
          aberta: boolean
          agora: string
          atrasada: boolean
          atribuicaoid: number
          disponiveldesde: string | null
          donoid: number | null
          entregarid: number | null
          pegaem: string | null
          pontos: number
          quempegou: number | null
          quempegounome: string | null
          rodizio: boolean
          situacao: string
          tipofrequencia: string
          titulo: string
        }[]
      }
      rodizio_espera: {
        Args: {
          p_atribuicaoid: number
          p_contaid: number
          p_funcionarioid: number
          p_lojaid: number
        }
        Returns: number
      }
      elegiveis_da_tarefa: {
        Args: { p_atribuicaoid: number; p_contaid: number }
        Returns: number
      }
      pegar_tarefa: {
        Args: { p_atribuicaoid: number; p_funcionarioid: number }
        Returns: number
      }
      revogar_aceite: {
        Args: { p_atribuicaoid: number; p_dia: string; p_motivo: string }
        Returns: undefined
      }
      tarefas_nao_pegas: {
        Args: { p_lojaid?: number }
        Returns: {
          atribuicaoid: number
          atribuidos: string
          loja: string
          lojaid: number
          pontos: number
          titulo: string
        }[]
      }
      tarefas_pegas_da_pessoa: {
        Args: { p_ate: string; p_de: string; p_funcionarioid: number }
        Returns: {
          dia: string
          entregue: boolean
          loja: string | null
          pontos: number
          revogadoem: string | null
          titulo: string
        }[]
      }
      visao_fila: {
        Args: { p_contaid: number; p_lojaid: number }
        Returns: Json
      }
      visao_pessoa_do_pin: {
        Args: { p_contaid: number; p_lojaid: number; p_pinhash: string }
        Returns: Json
      }
      visao_pegar: {
        Args: {
          p_atribuicaoid: number
          p_contaid: number
          p_funcionarioid: number
          p_lojaid: number
        }
        Returns: number
      }
      visao_entregar: {
        Args: {
          p_atribuicaoid: number
          p_caminho: string | null
          p_contaid: number
          p_funcionarioid: number
          p_lojaid: number
          p_observacao: string | null
        }
        Returns: number
      }
      fechamento_valendo: {
        Args: { p_ano: number; p_mes: number }
        Returns: number
      }
      ficha_dos_tablets: {
        Args: { p_contaid: number }
        Returns: Json
      }
      registrar_evento_acesso_loja: {
        Args: { p_contaid: number; p_evento: string; p_lojaid: number; p_quem: string }
        Returns: undefined
      }
      tentativa_abrir_ex: {
        Args: { p_chave: string; p_contaid: number; p_origem: string; p_tipo: string }
        Returns: Json
      }
      marcar_senha_amao: {
        Args: { p_amao: boolean; p_contaid: number; p_userid: string }
        Returns: undefined
      }
      erros_de_login: {
        Args: { p_chaves: string[] }
        Returns: Json
      }
      pegar_missao: {
        Args: { p_atribuicaoid: number; p_funcionarioid: number }
        Returns: number
      }
      pendencias_da_pessoa: {
        Args: { p_ate: string; p_de: string; p_funcionarioid: number }
        Returns: Json
      }
      pessoa_cumpre_conquista: {
        Args: {
          p_conquistaid: number
          p_contaid: number
          p_funcionarioid: number
        }
        Returns: boolean
      }
      politica_dar_ciencia: {
        Args: {
          p_assinaturaid: number
          p_contaid: number
          p_funcionarioid: number
        }
        Returns: boolean
      }
      politica_documento: { Args: { p_contaid: number }; Returns: number }
      politica_pendente: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: boolean
      }
      preparar_envio_documento: {
        Args: { p_funcionarioid: number; p_nomearquivo: string }
        Returns: string
      }
      primeiro_dia_editavel_meta: { Args: never; Returns: string }
      publicar_comunicado: {
        Args: {
          p_alvo: string
          p_conteudo: string
          p_funcionarios?: number[]
          p_lojas?: number[]
          p_pontos: number
          p_titulo: string
        }
        Returns: number
      }
      publicar_politica_de_uso: {
        Args: { p_conteudo: string }
        Returns: number
      }
      quem_trabalha_hoje: { Args: { p_lojaid: number }; Returns: Json }
      ranking_mensal: {
        Args: { p_ano: number; p_lojaid?: number; p_mes: number }
        Returns: {
          confiabilidade: number
          esforco: number
          funcionarioid: number
          nomecompleto: string
          nota: number
          pontosganhos: number
          pontospossiveis: number
          pontosregulares: number
        }[]
      }
      ranking_mensal_da_conta: {
        Args: {
          p_ano: number
          p_contaid: number
          p_fim: string
          p_lojaid: number
          p_mes: number
        }
        Returns: {
          confiabilidade: number
          esforco: number
          funcionarioid: number
          nomecompleto: string
          nota: number
          pontosganhos: number
          pontospossiveis: number
          pontosregulares: number
        }[]
      }
      ranking_pontos: {
        Args: { p_ate: string; p_de: string; p_lojaid?: number }
        Returns: {
          entregas: number
          funcionarioid: number
          nomecompleto: string
          pontos: number
        }[]
      }
      reabrir_agendamento: {
        Args: { p_agendamentoid: number; p_motivo: string }
        Returns: undefined
      }
      reais: { Args: { p_valor: number }; Returns: string }
      reavaliar_meta_do_dia: {
        Args: { p_apuracaoid: number }
        Returns: undefined
      }
      reavaliar_meta_do_mes: {
        Args: { p_contaid: number; p_lojaid: number; p_mes: string }
        Returns: undefined
      }
      recibo_ciencia: { Args: { p_assinaturaid: number }; Returns: Json }
      recibo_resgate: { Args: { p_resgateid: number }; Returns: Json }
      recusar_entrega: {
        Args: { p_entregaid: number; p_motivo: string }
        Returns: undefined
      }
      redefinir_acesso: {
        Args: {
          p_contaid: number
          p_funcionarioid: number
          p_pinhash: string
          p_quem: string
        }
        Returns: boolean
      }
      refazer_fechamento: {
        Args: { p_ano: number; p_mes: number; p_motivo: string }
        Returns: number
      }
      registra_agenda: {
        Args: {
          p_acao: string
          p_agendamentoid: number
          p_antes: string
          p_contaid: number
          p_depois: string
          p_lojaid: number
          p_motivo: string
        }
        Returns: undefined
      }
      registrar_anexo_agendamento: {
        Args: {
          p_agendamentoid: number
          p_caminho: string
          p_nomearquivo: string
          p_tamanho: number
          p_tipo: string
        }
        Returns: number
      }
      registrar_ciencia: { Args: { p_assinaturaid: number }; Returns: boolean }
      registrar_ciencia_documento: {
        Args: { p_documentoid: number }
        Returns: boolean
      }
      registrar_documento_pessoal: {
        Args: {
          p_caminho: string
          p_descricao: string
          p_funcionarioid: number
          p_nomearquivo: string
          p_referencia: string
          p_substitui?: number
          p_tamanho: number
          p_tipo: string
          p_tipoarquivo: string
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
      registrar_feedback: {
        Args: {
          p_comentario?: string
          p_dia: string
          p_funcionarioid: number
          p_nota: number
        }
        Returns: number
      }
      registrar_justificativa: {
        Args: {
          p_aceitar: boolean
          p_atribuicaoid: number
          p_dia: string
          p_motivo: string
        }
        Returns: number
      }
      registrar_relato: {
        Args: { p_contaid: number; p_mensagem: string }
        Returns: string
      }
      registrar_troca: {
        Args: {
          p_entregar?: boolean
          p_funcionarioid: number
          p_lojaid?: number
          p_produtoid: number
        }
        Returns: number
      }
      registrar_troca_por_valor: {
        Args: {
          p_entregar?: boolean
          p_funcionarioid: number
          p_lojaid?: number
          p_valorreais: number
        }
        Returns: number
      }
      remarcar_agendamento: {
        Args: { p_agendamentoid: number; p_motivo?: string; p_novadata: string }
        Returns: undefined
      }
      remover_anexo_agendamento: {
        Args: { p_anexoid: number }
        Returns: string
      }
      responsavel_valido: {
        Args: { p_contaid: number; p_funcionarioid: number; p_lojaid: number }
        Returns: boolean
      }
      resumo_das_lojas: { Args: never; Returns: Json }
      revogar_link_tv: { Args: { p_linktvid: number }; Returns: undefined }
      rodar_geracao_hoje: { Args: never; Returns: Json }
      rotina_conferencia_livro: {
        Args: { p_agora: string; p_contaid: number }
        Returns: Json
      }
      rotina_expurgo_fotos: {
        Args: { p_agora: string; p_contaid: number }
        Returns: Json
      }
      rotina_fechamento_mensal: {
        Args: { p_agora: string; p_contaid: number }
        Returns: Json
      }
      rotina_hora_local: {
        Args: { p_agora: string; p_fuso?: string }
        Returns: {
          dia: string
          hora: string
        }[]
      }
      rotina_horario: {
        Args: { p_chave: string; p_contaid: number; p_padrao: string }
        Returns: string
      }
      rotina_ligada: {
        Args: { p_contaid: number; p_lojaid: number; p_rotina: string }
        Returns: boolean
      }
      rotina_ligada_pessoa: {
        Args: { p_contaid: number; p_funcionarioid: number; p_rotina: string }
        Returns: boolean
      }
      rotina_limpeza: {
        Args: { p_agora: string; p_contaid: number }
        Returns: Json
      }
      rotina_lista_do_dia: {
        Args: { p_agora: string; p_contaid: number; p_origem: string }
        Returns: Json
      }
      rotina_mensagens: {
        Args: { p_agora: string; p_contaid: number }
        Returns: Json
      }
      rotina_registrar: {
        Args: {
          p_contaid: number
          p_detalhe: Json
          p_erro: string
          p_inicio: string
          p_origem: string
          p_recuperado?: boolean
          p_referencia: string
          p_resultado: string
          p_rotina: string
        }
        Returns: undefined
      }
      rotinas_despachar: { Args: { p_agora?: string }; Returns: Json }
      rotinas_resumo_admin: {
        Args: never
        Returns: {
          contaid: number
          rotina: string
          situacao: string
          ultimaem: string
        }[]
      }
      salvar_meta_do_mes: {
        Args: {
          p_descricao?: string
          p_lojaid: number
          p_mes: string
          p_nome: string
          p_pontos: number
          p_valor: number
        }
        Returns: number
      }
      senha_app_de: {
        Args: { p_contaid: number; p_cpf: string }
        Returns: Json
      }
      senha_app_do_funcionario: {
        Args: { p_contaid: number; p_funcionarioid: number }
        Returns: Json
      }
      situacao_dos_acessos: {
        Args: never
        Returns: {
          codigoexpiraem: string
          codigopendente: boolean
          funcionarioid: number
          nuncaentrou: boolean
          redefinidoem: string
          sempin: boolean
          semsenha: boolean
          temacesso: boolean
        }[]
      }
      so_digitos: { Args: { p_texto: string }; Returns: string }
      sou_master: { Args: never; Returns: boolean }
      tarefa_cai_no_dia: {
        Args: {
          p_dataagendamento: string
          p_dia: string
          p_tipofrequencia: string
          p_valorfrequencia: number
        }
        Returns: boolean
      }
      tarefa_da_agenda_entregue: {
        Args: { p_atribuicaoid: number }
        Returns: boolean
      }
      tarefas_de_folga_hoje: { Args: { p_lojaid: number }; Returns: Json }
      taxa_da_conta: { Args: { p_contaid: number }; Returns: number }
      telegram_hash: { Args: { p_codigo: string }; Returns: string }
      telegram_novo_codigo: { Args: never; Returns: string }
      tem_justificativa: {
        Args: {
          p_atribuicaoid: number
          p_dia: string
          p_so_aceita: boolean
          p_tipo: string
        }
        Returns: boolean
      }
      tentativa_abrir: {
        Args: {
          p_chave: string
          p_contaid: number
          p_origem: string
          p_tipo: string
        }
        Returns: number
      }
      tentativa_fechar: {
        Args: { p_sucesso: boolean; p_tentativaid: number }
        Returns: undefined
      }
      texto_da_tarefa_agenda: {
        Args: { p_dataevento: string; p_tipo: string }
        Returns: string
      }
      tratar_relato: {
        Args: { p_denunciaid: number; p_resposta?: string; p_status: string }
        Returns: undefined
      }
      trocar_cpf: {
        Args: { p_contaid: number; p_cpf: string; p_funcionarioid: number }
        Returns: undefined
      }
      trocar_responsavel_agendamento: {
        Args: { p_agendamentoid: number; p_funcionarioid: number }
        Returns: undefined
      }
      usar_codigo_acesso: {
        Args: { p_codigohash: string; p_contaid: number; p_cpf: string }
        Returns: Json
      }
      usar_mensagens: {
        Args: {
          p_canal: string
          p_contaid: number
          p_lojaid: number
          p_qtd: number
          p_tipo: string
        }
        Returns: undefined
      }
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

