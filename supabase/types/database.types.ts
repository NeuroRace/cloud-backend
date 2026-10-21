export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      operadores: {
        Row: {
          criado_em: string
          email: string
        }
        Insert: {
          criado_em?: string
          email: string
        }
        Update: {
          criado_em?: string
          email?: string
        }
        Relationships: []
      }
      players: {
        Row: {
          created_at: string
          email: string | null
          id: string
          phone: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          email?: string | null
          id?: string
          phone?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          email?: string | null
          id?: string
          phone?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      premiacao_config: {
        Row: {
          carencia_min: number
          evento_atual: string
          id: boolean
          janela_min: number
          lembrete_min: number
          ligada_em: string | null
          limite_fila: number
          passar_sozinho: boolean
          pausa_geral: boolean
          piso_tempo_s: number
          premiacao_ligada: boolean
        }
        Insert: {
          carencia_min?: number
          evento_atual?: string
          id?: boolean
          janela_min?: number
          lembrete_min?: number
          ligada_em?: string | null
          limite_fila?: number
          passar_sozinho?: boolean
          pausa_geral?: boolean
          piso_tempo_s?: number
          premiacao_ligada?: boolean
        }
        Update: {
          carencia_min?: number
          evento_atual?: string
          id?: boolean
          janela_min?: number
          lembrete_min?: number
          ligada_em?: string | null
          limite_fila?: number
          passar_sozinho?: boolean
          pausa_geral?: boolean
          piso_tempo_s?: number
          premiacao_ligada?: boolean
        }
        Relationships: []
      }
      premiacao_registro: {
        Row: {
          acao: string
          antes: Json | null
          depois: Json | null
          detalhe: string | null
          em: string
          id: number
          operador: string
          premio_id: string | null
          round_id: string | null
        }
        Insert: {
          acao: string
          antes?: Json | null
          depois?: Json | null
          detalhe?: string | null
          em: string
          id?: never
          operador: string
          premio_id?: string | null
          round_id?: string | null
        }
        Update: {
          acao?: string
          antes?: Json | null
          depois?: Json | null
          detalhe?: string | null
          em?: string
          id?: never
          operador?: string
          premio_id?: string | null
          round_id?: string | null
        }
        Relationships: []
      }
      premiacao_rodadas: {
        Row: {
          corte_em: string
          evento: string
          fechada_em: string
          round_id: string
        }
        Insert: {
          corte_em: string
          evento: string
          fechada_em: string
          round_id: string
        }
        Update: {
          corte_em?: string
          evento?: string
          fechada_em?: string
          round_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "premiacao_rodadas_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: true
            referencedRelation: "ranking_windows"
            referencedColumns: ["id"]
          },
        ]
      }
      premios: {
        Row: {
          atualizado_em: string
          code: string | null
          criado_em: string
          display_name: string
          entregue_em: string | null
          evento: string
          id: string
          motivo: string | null
          posicao: number
          prazo: string | null
          race_player_id: string | null
          round_id: string
          score: number
          status: string
          user_id: string
        }
        Insert: {
          atualizado_em: string
          code?: string | null
          criado_em: string
          display_name: string
          entregue_em?: string | null
          evento: string
          id?: string
          motivo?: string | null
          posicao: number
          prazo?: string | null
          race_player_id?: string | null
          round_id: string
          score: number
          status: string
          user_id: string
        }
        Update: {
          atualizado_em?: string
          code?: string | null
          criado_em?: string
          display_name?: string
          entregue_em?: string | null
          evento?: string
          id?: string
          motivo?: string | null
          posicao?: number
          prazo?: string | null
          race_player_id?: string | null
          round_id?: string
          score?: number
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "premios_race_player_id_fkey"
            columns: ["race_player_id"]
            isOneToOne: false
            referencedRelation: "race_players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "premios_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: false
            referencedRelation: "premiacao_rodadas"
            referencedColumns: ["round_id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          display_name: string | null
          id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          id?: string
        }
        Relationships: []
      }
      race_players: {
        Row: {
          created_at: string
          finished_at: string | null
          id: string
          idempotency_key: string
          player_id: string
          player_slot: number
          race_id: string
          source: string
          started_at: string
        }
        Insert: {
          created_at?: string
          finished_at?: string | null
          id?: string
          idempotency_key: string
          player_id: string
          player_slot: number
          race_id: string
          source?: string
          started_at: string
        }
        Update: {
          created_at?: string
          finished_at?: string | null
          id?: string
          idempotency_key?: string
          player_id?: string
          player_slot?: number
          race_id?: string
          source?: string
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "race_players_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "race_players_race_id_fkey"
            columns: ["race_id"]
            isOneToOne: false
            referencedRelation: "races"
            referencedColumns: ["id"]
          },
        ]
      }
      races: {
        Row: {
          created_at: string
          id: string
          started_at: string
        }
        Insert: {
          created_at?: string
          id: string
          started_at: string
        }
        Update: {
          created_at?: string
          id?: string
          started_at?: string
        }
        Relationships: []
      }
      ranking_windows: {
        Row: {
          created_at: string
          ends_at: string
          id: string
          name: string
          starts_at: string
        }
        Insert: {
          created_at?: string
          ends_at: string
          id?: string
          name: string
          starts_at: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          id?: string
          name?: string
          starts_at?: string
        }
        Relationships: []
      }
      telegram_notifications: {
        Row: {
          chat_id: number
          kind: string
          ref: string
          sent_at: string
        }
        Insert: {
          chat_id: number
          kind: string
          ref: string
          sent_at?: string
        }
        Update: {
          chat_id?: number
          kind?: string
          ref?: string
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "telegram_notifications_chat_id_fkey"
            columns: ["chat_id"]
            isOneToOne: false
            referencedRelation: "telegram_subscriptions"
            referencedColumns: ["chat_id"]
          },
        ]
      }
      telegram_subscriptions: {
        Row: {
          chat_id: number
          created_at: string
          email: string
          updated_at: string
        }
        Insert: {
          chat_id: number
          created_at?: string
          email: string
          updated_at?: string
        }
        Update: {
          chat_id?: number
          created_at?: string
          email?: string
          updated_at?: string
        }
        Relationships: []
      }
      telemetry_points: {
        Row: {
          attention: number | null
          eeg_power: Json | null
          id: number
          meditation: number | null
          poor_signal_level: number | null
          race_player_id: string
          signal_status: string | null
          t: string
        }
        Insert: {
          attention?: number | null
          eeg_power?: Json | null
          id?: never
          meditation?: number | null
          poor_signal_level?: number | null
          race_player_id: string
          signal_status?: string | null
          t: string
        }
        Update: {
          attention?: number | null
          eeg_power?: Json | null
          id?: never
          meditation?: number | null
          poor_signal_level?: number | null
          race_player_id?: string
          signal_status?: string | null
          t?: string
        }
        Relationships: [
          {
            foreignKeyName: "telemetry_points_race_player_id_fkey"
            columns: ["race_player_id"]
            isOneToOne: false
            referencedRelation: "race_players"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_leaderboard: {
        Args: {
          p_from?: string
          p_limit?: number
          p_metric?: string
          p_to?: string
        }
        Returns: {
          display_name: string
          rank: number
          score: number
        }[]
      }
      get_my_prize: {
        Args: never
        Returns: {
          claim_deadline: string
          code: string
          delivered_at: string
          round_name: string
          status: string
        }[]
      }
      get_official_winners: {
        Args: never
        Returns: {
          display_name: string
          round_id: string
          round_name: string
          score: number
        }[]
      }
      ingest_race: { Args: { payload: Json }; Returns: Json }
      op_acao: {
        Args: { p_acao: string; p_motivo?: string; p_premio: string }
        Returns: Json
      }
      op_config: { Args: { p_mudancas: Json }; Returns: Json }
      op_painel: { Args: never; Returns: Json }
      op_validar_codigo: { Args: { p_codigo: string }; Returns: Json }
      premiacao_candidatos: {
        Args: { p_corte: string; p_round: string }
        Returns: {
          achieved_at: string
          display_name: string
          posicao: number
          race_player_id: string
          score: number
          user_id: string
        }[]
      }
      premiacao_mascara_contato: {
        Args: { p_email: string; p_phone: string }
        Returns: string
      }
      premiacao_op_acao: {
        Args: {
          p_acao: string
          p_agora: string
          p_motivo: string
          p_operador: string
          p_premio: string
        }
        Returns: Json
      }
      premiacao_op_config: {
        Args: { p_agora: string; p_mudancas: Json; p_operador: string }
        Returns: Json
      }
      premiacao_op_painel: { Args: { p_agora: string }; Returns: Json }
      premiacao_op_validar: {
        Args: { p_agora: string; p_codigo: string; p_operador: string }
        Returns: Json
      }
      premiacao_operador_atual: { Args: never; Returns: string }
      premiacao_registra_erro: {
        Args: {
          p_agora: string
          p_detalhe: string
          p_premio: string
          p_round: string
        }
        Returns: undefined
      }
      premiacao_tick: { Args: { p_agora?: string }; Returns: Json }
      premio_dar_vez: {
        Args: { p_agora: string; p_round: string }
        Returns: string
      }
      premio_dar_vez_ate: {
        Args: {
          p_agora: string
          p_limite: number
          p_round: string
          p_sortear: boolean
        }
        Returns: string
      }
      premio_novo_codigo: { Args: never; Returns: string }
      premio_passar: {
        Args: {
          p_agora: string
          p_motivo?: string
          p_novo_status: string
          p_operador: string
          p_premio: string
        }
        Returns: string
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

