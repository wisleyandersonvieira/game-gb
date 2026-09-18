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
      entregas: {
        Row: {
          atribuicao_id: string
          created_at: string
          data_envio: string
          foto_url: string | null
          funcionario_id: string
          id: string
          motivo_recusa: string | null
          observacao: string | null
          pontos_ganhos: number
          status_validacao: string
          tarefa_id: string
          updated_at: string
        }
        Insert: {
          atribuicao_id: string
          created_at?: string
          data_envio?: string
          foto_url?: string | null
          funcionario_id: string
          id?: string
          motivo_recusa?: string | null
          observacao?: string | null
          pontos_ganhos?: number
          status_validacao?: string
          tarefa_id: string
          updated_at?: string
        }
        Update: {
          atribuicao_id?: string
          created_at?: string
          data_envio?: string
          foto_url?: string | null
          funcionario_id?: string
          id?: string
          motivo_recusa?: string | null
          observacao?: string | null
          pontos_ganhos?: number
          status_validacao?: string
          tarefa_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "entregas_atribuicao_id_fkey"
            columns: ["atribuicao_id"]
            isOneToOne: false
            referencedRelation: "tarefas_atribuidas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entregas_funcionario_id_fkey"
            columns: ["funcionario_id"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entregas_tarefa_id_fkey"
            columns: ["tarefa_id"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["id"]
          },
        ]
      }
      funcionarios: {
        Row: {
          ativo: boolean
          cargo: string | null
          chat_id_telegram: string | null
          created_at: string
          id: string
          nome: string
          setor: string | null
          telefone: string | null
          updated_at: string
        }
        Insert: {
          ativo?: boolean
          cargo?: string | null
          chat_id_telegram?: string | null
          created_at?: string
          id?: string
          nome: string
          setor?: string | null
          telefone?: string | null
          updated_at?: string
        }
        Update: {
          ativo?: boolean
          cargo?: string | null
          chat_id_telegram?: string | null
          created_at?: string
          id?: string
          nome?: string
          setor?: string | null
          telefone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      tarefas: {
        Row: {
          created_at: string
          descricao: string | null
          id: string
          pontos: number
          setor: string | null
          titulo: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          descricao?: string | null
          id?: string
          pontos?: number
          setor?: string | null
          titulo: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          descricao?: string | null
          id?: string
          pontos?: number
          setor?: string | null
          titulo?: string
          updated_at?: string
        }
        Relationships: []
      }
      tarefas_atribuidas: {
        Row: {
          created_at: string
          data_agendamento: string | null
          data_fim_vigencia: string | null
          descricao_override: string | null
          funcionario_id: string
          id: string
          tarefa_id: string
          tipo_frequencia: string
          updated_at: string
          valor_frequencia: number | null
        }
        Insert: {
          created_at?: string
          data_agendamento?: string | null
          data_fim_vigencia?: string | null
          descricao_override?: string | null
          funcionario_id: string
          id?: string
          tarefa_id: string
          tipo_frequencia?: string
          updated_at?: string
          valor_frequencia?: number | null
        }
        Update: {
          created_at?: string
          data_agendamento?: string | null
          data_fim_vigencia?: string | null
          descricao_override?: string | null
          funcionario_id?: string
          id?: string
          tarefa_id?: string
          tipo_frequencia?: string
          updated_at?: string
          valor_frequencia?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tarefas_atribuidas_funcionario_id_fkey"
            columns: ["funcionario_id"]
            isOneToOne: false
            referencedRelation: "funcionarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tarefas_atribuidas_tarefa_id_fkey"
            columns: ["tarefa_id"]
            isOneToOne: false
            referencedRelation: "tarefas"
            referencedColumns: ["id"]
          },
        ]
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
