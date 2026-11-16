export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      audit_events: {
        Row: {
          action: string;
          actor_id: string | null;
          created_at: string;
          details: NonNullable<Json>;
          entity_id: string;
          entity_type: string;
          id: number;
          project_id: string;
          reason: string | null;
        };
        ComputedFields: never;
        Insert: {
          action: string;
          actor_id?: string | null;
          created_at?: string;
          details?: NonNullable<Json>;
          entity_id: string;
          entity_type: string;
          id?: never;
          project_id: string;
          reason?: string | null;
        };
        Update: {
          action?: string;
          actor_id?: string | null;
          created_at?: string;
          details?: NonNullable<Json>;
          entity_id?: string;
          entity_type?: string;
          id?: never;
          project_id?: string;
          reason?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "audit_events_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      baseline_reported_metrics: {
        Row: {
          baseline_id: string;
          mean: number;
          metric_definition_id: string;
          project_id: string;
          sample_count: number | null;
          stddev: number | null;
        };
        ComputedFields: never;
        Insert: {
          baseline_id: string;
          mean: number;
          metric_definition_id: string;
          project_id: string;
          sample_count?: number | null;
          stddev?: number | null;
        };
        Update: {
          baseline_id?: string;
          mean?: number;
          metric_definition_id?: string;
          project_id?: string;
          sample_count?: number | null;
          stddev?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "baseline_reported_metrics_project_id_baseline_id_fkey";
            columns: ["project_id", "baseline_id"];
            isOneToOne: false;
            referencedRelation: "baseline_versions";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "baseline_reported_metrics_project_id_metric_definition_id_fkey";
            columns: ["project_id", "metric_definition_id"];
            isOneToOne: false;
            referencedRelation: "metric_definitions";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      baseline_versions: {
        Row: {
          context_id: string | null;
          created_at: string;
          created_by: string;
          group_id: string | null;
          id: string;
          kind: Database["public"]["Enums"]["baseline_kind"];
          name: string;
          previous_baseline_id: string | null;
          project_id: string;
          reason: string;
          source: string | null;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          context_id?: string | null;
          created_at?: string;
          created_by: string;
          group_id?: string | null;
          id?: string;
          kind: Database["public"]["Enums"]["baseline_kind"];
          name: string;
          previous_baseline_id?: string | null;
          project_id: string;
          reason: string;
          source?: string | null;
          version: number;
        };
        Update: {
          context_id?: string | null;
          created_at?: string;
          created_by?: string;
          group_id?: string | null;
          id?: string;
          kind?: Database["public"]["Enums"]["baseline_kind"];
          name?: string;
          previous_baseline_id?: string | null;
          project_id?: string;
          reason?: string;
          source?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "baseline_versions_project_id_context_id_fkey";
            columns: ["project_id", "context_id"];
            isOneToOne: false;
            referencedRelation: "comparison_contexts";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "baseline_versions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "baseline_versions_project_id_group_id_context_id_fkey";
            columns: ["project_id", "group_id", "context_id"];
            isOneToOne: false;
            referencedRelation: "run_groups";
            referencedColumns: ["project_id", "id", "context_id"];
          },
          {
            foreignKeyName: "baseline_versions_project_id_previous_baseline_id_fkey";
            columns: ["project_id", "previous_baseline_id"];
            isOneToOne: false;
            referencedRelation: "baseline_versions";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      comparison_contexts: {
        Row: {
          created_at: string;
          created_by: string;
          dataset_fingerprint: string;
          evaluation_config: NonNullable<Json>;
          evaluation_version: string;
          id: string;
          name: string;
          project_id: string;
          sample_size: number;
          split_fingerprint: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by: string;
          dataset_fingerprint: string;
          evaluation_config?: NonNullable<Json>;
          evaluation_version: string;
          id?: string;
          name: string;
          project_id: string;
          sample_size: number;
          split_fingerprint: string;
        };
        Update: {
          created_at?: string;
          created_by?: string;
          dataset_fingerprint?: string;
          evaluation_config?: NonNullable<Json>;
          evaluation_version?: string;
          id?: string;
          name?: string;
          project_id?: string;
          sample_size?: number;
          split_fingerprint?: string;
        };
        Relationships: [
          {
            foreignKeyName: "comparison_contexts_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      context_metrics: {
        Row: {
          context_id: string;
          metric_definition_id: string;
          project_id: string;
          required: boolean;
        };
        ComputedFields: never;
        Insert: {
          context_id: string;
          metric_definition_id: string;
          project_id: string;
          required?: boolean;
        };
        Update: {
          context_id?: string;
          metric_definition_id?: string;
          project_id?: string;
          required?: boolean;
        };
        Relationships: [
          {
            foreignKeyName: "context_metrics_project_id_context_id_fkey";
            columns: ["project_id", "context_id"];
            isOneToOne: false;
            referencedRelation: "comparison_contexts";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "context_metrics_project_id_metric_definition_id_fkey";
            columns: ["project_id", "metric_definition_id"];
            isOneToOne: false;
            referencedRelation: "metric_definitions";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      experiment_revisions: {
        Row: {
          change_reason: string;
          changes: string;
          created_at: string;
          created_by: string;
          evaluation_plan: string;
          experiment_id: string;
          hypothesis: string;
          id: string;
          project_id: string;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          change_reason: string;
          changes: string;
          created_at?: string;
          created_by: string;
          evaluation_plan: string;
          experiment_id: string;
          hypothesis: string;
          id?: string;
          project_id: string;
          version: number;
        };
        Update: {
          change_reason?: string;
          changes?: string;
          created_at?: string;
          created_by?: string;
          evaluation_plan?: string;
          experiment_id?: string;
          hypothesis?: string;
          id?: string;
          project_id?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "experiment_revisions_project_id_experiment_id_fkey";
            columns: ["project_id", "experiment_id"];
            isOneToOne: false;
            referencedRelation: "experiments";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      experiments: {
        Row: {
          archived_at: string | null;
          created_at: string;
          created_by: string;
          current_revision_id: string | null;
          id: string;
          number: number;
          owner_id: string | null;
          previous_experiment_id: string | null;
          project_id: string;
          representative_group_id: string | null;
          title: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          archived_at?: string | null;
          created_at?: string;
          created_by: string;
          current_revision_id?: string | null;
          id?: string;
          number: number;
          owner_id?: string | null;
          previous_experiment_id?: string | null;
          project_id: string;
          representative_group_id?: string | null;
          title: string;
          updated_at?: string;
        };
        Update: {
          archived_at?: string | null;
          created_at?: string;
          created_by?: string;
          current_revision_id?: string | null;
          id?: string;
          number?: number;
          owner_id?: string | null;
          previous_experiment_id?: string | null;
          project_id?: string;
          representative_group_id?: string | null;
          title?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "experiments_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "experiments_project_id_id_current_revision_id_fkey";
            columns: ["project_id", "id", "current_revision_id"];
            isOneToOne: false;
            referencedRelation: "experiment_revisions";
            referencedColumns: ["project_id", "experiment_id", "id"];
          },
          {
            foreignKeyName: "experiments_project_id_id_representative_group_id_fkey";
            columns: ["project_id", "id", "representative_group_id"];
            isOneToOne: false;
            referencedRelation: "run_groups";
            referencedColumns: ["project_id", "experiment_id", "id"];
          },
          {
            foreignKeyName: "experiments_project_id_owner_id_fkey";
            columns: ["project_id", "owner_id"];
            isOneToOne: false;
            referencedRelation: "project_members";
            referencedColumns: ["project_id", "user_id"];
          },
          {
            foreignKeyName: "experiments_project_id_previous_experiment_id_fkey";
            columns: ["project_id", "previous_experiment_id"];
            isOneToOne: false;
            referencedRelation: "experiments";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      generation_outputs: {
        Row: {
          created_at: string;
          fingerprint: string;
          id: string;
          project_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          fingerprint: string;
          id?: string;
          project_id: string;
        };
        Update: {
          created_at?: string;
          fingerprint?: string;
          id?: string;
          project_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "generation_outputs_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      ingestion_tokens: {
        Row: {
          created_at: string;
          created_by: string;
          expires_at: string;
          id: string;
          name: string;
          project_id: string;
          revoked_at: string | null;
          token_hash: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by: string;
          expires_at: string;
          id?: string;
          name: string;
          project_id: string;
          revoked_at?: string | null;
          token_hash: string;
        };
        Update: {
          created_at?: string;
          created_by?: string;
          expires_at?: string;
          id?: string;
          name?: string;
          project_id?: string;
          revoked_at?: string | null;
          token_hash?: string;
        };
        Relationships: [
          {
            foreignKeyName: "ingestion_tokens_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      metric_definitions: {
        Row: {
          created_at: string;
          created_by: string;
          direction: Database["public"]["Enums"]["metric_direction"];
          id: string;
          name: string;
          project_id: string;
          target: number | null;
          unit: string;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by: string;
          direction: Database["public"]["Enums"]["metric_direction"];
          id?: string;
          name: string;
          project_id: string;
          target?: number | null;
          unit: string;
          version: number;
        };
        Update: {
          created_at?: string;
          created_by?: string;
          direction?: Database["public"]["Enums"]["metric_direction"];
          id?: string;
          name?: string;
          project_id?: string;
          target?: number | null;
          unit?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "metric_definitions_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      note_revisions: {
        Row: {
          body: string;
          created_at: string;
          created_by: string;
          id: string;
          note_id: string;
          project_id: string;
          reason: string;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          body: string;
          created_at?: string;
          created_by: string;
          id?: string;
          note_id: string;
          project_id: string;
          reason: string;
          version: number;
        };
        Update: {
          body?: string;
          created_at?: string;
          created_by?: string;
          id?: string;
          note_id?: string;
          project_id?: string;
          reason?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "note_revisions_project_id_note_id_fkey";
            columns: ["project_id", "note_id"];
            isOneToOne: false;
            referencedRelation: "notes";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      notes: {
        Row: {
          created_at: string;
          created_by: string;
          current_revision: number;
          experiment_id: string | null;
          id: string;
          project_id: string;
          run_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by: string;
          current_revision?: number;
          experiment_id?: string | null;
          id?: string;
          project_id: string;
          run_id?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string;
          current_revision?: number;
          experiment_id?: string | null;
          id?: string;
          project_id?: string;
          run_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "notes_project_id_experiment_id_fkey";
            columns: ["project_id", "experiment_id"];
            isOneToOne: false;
            referencedRelation: "experiments";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "notes_project_id_run_id_fkey";
            columns: ["project_id", "run_id"];
            isOneToOne: false;
            referencedRelation: "runs";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      project_members: {
        Row: {
          joined_at: string;
          project_id: string;
          role: Database["public"]["Enums"]["project_role"];
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          joined_at?: string;
          project_id: string;
          role: Database["public"]["Enums"]["project_role"];
          user_id: string;
        };
        Update: {
          joined_at?: string;
          project_id?: string;
          role?: Database["public"]["Enums"]["project_role"];
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_members_project_id_fkey";
            columns: ["project_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id"];
          },
        ];
      };
      projects: {
        Row: {
          archived_at: string | null;
          created_at: string;
          created_by: string;
          id: string;
          name: string;
        };
        ComputedFields: never;
        Insert: {
          archived_at?: string | null;
          created_at?: string;
          created_by: string;
          id?: string;
          name: string;
        };
        Update: {
          archived_at?: string | null;
          created_at?: string;
          created_by?: string;
          id?: string;
          name?: string;
        };
        Relationships: [];
      };
      run_group_exclusions: {
        Row: {
          group_id: string;
          project_id: string;
          reason: string;
          repetition: number;
        };
        ComputedFields: never;
        Insert: {
          group_id: string;
          project_id: string;
          reason: string;
          repetition: number;
        };
        Update: {
          group_id?: string;
          project_id?: string;
          reason?: string;
          repetition?: number;
        };
        Relationships: [
          {
            foreignKeyName: "run_group_exclusions_project_id_group_id_fkey";
            columns: ["project_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "run_groups";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      run_group_selections: {
        Row: {
          group_id: string;
          project_id: string;
          repetition: number;
          run_id: string;
        };
        ComputedFields: never;
        Insert: {
          group_id: string;
          project_id: string;
          repetition: number;
          run_id: string;
        };
        Update: {
          group_id?: string;
          project_id?: string;
          repetition?: number;
          run_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "run_group_selections_project_id_group_id_fkey";
            columns: ["project_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "run_groups";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "run_group_selections_project_id_run_id_fkey";
            columns: ["project_id", "run_id"];
            isOneToOne: false;
            referencedRelation: "runs";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
      run_groups: {
        Row: {
          config: NonNullable<Json>;
          context_id: string;
          created_at: string;
          created_by: string;
          expected_repetitions: number;
          experiment_id: string;
          finalized_at: string | null;
          finalized_by: string | null;
          id: string;
          project_id: string;
          revision_id: string;
          state: Database["public"]["Enums"]["group_state"];
        };
        ComputedFields: never;
        Insert: {
          config?: NonNullable<Json>;
          context_id: string;
          created_at?: string;
          created_by: string;
          expected_repetitions: number;
          experiment_id: string;
          finalized_at?: string | null;
          finalized_by?: string | null;
          id?: string;
          project_id: string;
          revision_id: string;
          state?: Database["public"]["Enums"]["group_state"];
        };
        Update: {
          config?: NonNullable<Json>;
          context_id?: string;
          created_at?: string;
          created_by?: string;
          expected_repetitions?: number;
          experiment_id?: string;
          finalized_at?: string | null;
          finalized_by?: string | null;
          id?: string;
          project_id?: string;
          revision_id?: string;
          state?: Database["public"]["Enums"]["group_state"];
        };
        Relationships: [
          {
            foreignKeyName: "run_groups_project_id_context_id_fkey";
            columns: ["project_id", "context_id"];
            isOneToOne: false;
            referencedRelation: "comparison_contexts";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "run_groups_project_id_experiment_id_revision_id_fkey";
            columns: ["project_id", "experiment_id", "revision_id"];
            isOneToOne: false;
            referencedRelation: "experiment_revisions";
            referencedColumns: ["project_id", "experiment_id", "id"];
          },
        ];
      };
      run_metrics: {
        Row: {
          context_id: string;
          metric_definition_id: string;
          project_id: string;
          reason: string | null;
          run_id: string;
          state: Database["public"]["Enums"]["metric_state"];
          value: number | null;
        };
        ComputedFields: never;
        Insert: {
          context_id: string;
          metric_definition_id: string;
          project_id: string;
          reason?: string | null;
          run_id: string;
          state: Database["public"]["Enums"]["metric_state"];
          value?: number | null;
        };
        Update: {
          context_id?: string;
          metric_definition_id?: string;
          project_id?: string;
          reason?: string | null;
          run_id?: string;
          state?: Database["public"]["Enums"]["metric_state"];
          value?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "run_metrics_project_id_context_id_metric_definition_id_fkey";
            columns: ["project_id", "context_id", "metric_definition_id"];
            isOneToOne: false;
            referencedRelation: "context_metrics";
            referencedColumns: ["project_id", "context_id", "metric_definition_id"];
          },
          {
            foreignKeyName: "run_metrics_project_id_run_id_context_id_fkey";
            columns: ["project_id", "run_id", "context_id"];
            isOneToOne: false;
            referencedRelation: "runs";
            referencedColumns: ["project_id", "id", "context_id"];
          },
        ];
      };
      runs: {
        Row: {
          attempt: number;
          config: NonNullable<Json>;
          context_id: string;
          created_at: string;
          finished_at: string | null;
          generation_output_id: string | null;
          group_id: string;
          id: string;
          ingestion_id: string;
          previous_run_id: string | null;
          project_id: string;
          repetition: number;
          request_payload: NonNullable<Json>;
          started_at: string | null;
          status: Database["public"]["Enums"]["run_status"];
        };
        ComputedFields: never;
        Insert: {
          attempt: number;
          config: NonNullable<Json>;
          context_id: string;
          created_at?: string;
          finished_at?: string | null;
          generation_output_id?: string | null;
          group_id: string;
          id?: string;
          ingestion_id: string;
          previous_run_id?: string | null;
          project_id: string;
          repetition: number;
          request_payload: NonNullable<Json>;
          started_at?: string | null;
          status: Database["public"]["Enums"]["run_status"];
        };
        Update: {
          attempt?: number;
          config?: NonNullable<Json>;
          context_id?: string;
          created_at?: string;
          finished_at?: string | null;
          generation_output_id?: string | null;
          group_id?: string;
          id?: string;
          ingestion_id?: string;
          previous_run_id?: string | null;
          project_id?: string;
          repetition?: number;
          request_payload?: NonNullable<Json>;
          started_at?: string | null;
          status?: Database["public"]["Enums"]["run_status"];
        };
        Relationships: [
          {
            foreignKeyName: "runs_project_id_generation_output_id_fkey";
            columns: ["project_id", "generation_output_id"];
            isOneToOne: false;
            referencedRelation: "generation_outputs";
            referencedColumns: ["project_id", "id"];
          },
          {
            foreignKeyName: "runs_project_id_group_id_context_id_fkey";
            columns: ["project_id", "group_id", "context_id"];
            isOneToOne: false;
            referencedRelation: "run_groups";
            referencedColumns: ["project_id", "id", "context_id"];
          },
          {
            foreignKeyName: "runs_project_id_previous_run_id_fkey";
            columns: ["project_id", "previous_run_id"];
            isOneToOne: false;
            referencedRelation: "runs";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
    };
    Views: {
      run_group_metric_summaries: {
        Row: {
          group_id: string;
          mean: number | null;
          metric_definition_id: string;
          project_id: string;
          sample_count: number | null;
          stddev: number | null;
          unavailable_count: number | null;
        };
        ComputedFields: never;
        Relationships: [
          {
            foreignKeyName: "run_group_selections_project_id_group_id_fkey";
            columns: ["project_id", "group_id"];
            isOneToOne: false;
            referencedRelation: "run_groups";
            referencedColumns: ["project_id", "id"];
          },
        ];
      };
    };
    Functions: {
      create_baseline_version: {
        Args: {
          p_context?: string;
          p_group?: string;
          p_kind: Database["public"]["Enums"]["baseline_kind"];
          p_metrics?: Json;
          p_name: string;
          p_project: string;
          p_reason: string;
          p_source?: string;
        };
        Returns: string;
      };
      create_comparison_context: {
        Args: {
          p_config?: Json;
          p_dataset: string;
          p_evaluation_version: string;
          p_metrics: Json;
          p_name: string;
          p_project: string;
          p_sample_size: number;
          p_split: string;
        };
        Returns: string;
      };
      create_experiment: {
        Args: {
          p_changes: string;
          p_hypothesis: string;
          p_number: number;
          p_owner?: string;
          p_plan: string;
          p_previous?: string;
          p_project: string;
          p_reason: string;
          p_title: string;
        };
        Returns: string;
      };
      create_note: {
        Args: {
          p_body: string;
          p_experiment?: string;
          p_project: string;
          p_reason: string;
          p_run?: string;
        };
        Returns: string;
      };
      create_project: { Args: { p_name: string }; Returns: string };
      create_run_group: {
        Args: {
          p_config?: Json;
          p_context: string;
          p_experiment: string;
          p_project: string;
          p_repetitions: number;
          p_revision: string;
        };
        Returns: string;
      };
      define_metric: {
        Args: {
          p_direction: Database["public"]["Enums"]["metric_direction"];
          p_name: string;
          p_project: string;
          p_target?: number;
          p_unit: string;
          p_version: number;
        };
        Returns: string;
      };
      finalize_run_group: {
        Args: {
          p_exclusions: Json;
          p_group: string;
          p_project: string;
          p_reason: string;
          p_selections: Json;
        };
        Returns: undefined;
      };
      issue_ingestion_token: {
        Args: { p_expires_at: string; p_name: string; p_project: string };
        Returns: {
          expires_at: string;
          token: string;
          token_id: string;
        }[];
      };
      read_comparison_run: { Args: { p_run_id: string }; Returns: Json };
      read_dashboard_comparison_release: { Args: Record<PropertyKey, never>; Returns: Json };
      read_selected_evaluations: { Args: Record<PropertyKey, never>; Returns: Json[] };
      record_run: {
        Args: {
          p_attempt: number;
          p_fingerprint: string;
          p_finished_at?: string;
          p_group: string;
          p_ingestion_id: string;
          p_metrics: Json;
          p_previous?: string;
          p_project: string;
          p_repetition: number;
          p_started_at?: string;
          p_status: Database["public"]["Enums"]["run_status"];
        };
        Returns: string;
      };
      register_ingested_evaluation: {
        Args: {
          p_attempt: number;
          p_finished_at: string;
          p_generation_id: string;
          p_generation_sha256: string;
          p_group_id: string;
          p_ingestion_id: string;
          p_metrics: Json;
          p_previous_run_id: string;
          p_repetition: number;
          p_started_at: string;
          p_token: string;
        };
        Returns: Json;
      };
      revise_experiment: {
        Args: {
          p_changes: string;
          p_expected_revision: number;
          p_experiment: string;
          p_hypothesis: string;
          p_plan: string;
          p_project: string;
          p_reason: string;
        };
        Returns: string;
      };
      revise_note: {
        Args: {
          p_body: string;
          p_expected_revision: number;
          p_note: string;
          p_project: string;
          p_reason: string;
        };
        Returns: number;
      };
      revoke_ingestion_token: { Args: { p_project: string; p_token_id: string }; Returns: boolean };
      set_project_member: {
        Args: {
          p_project: string;
          p_role: Database["public"]["Enums"]["project_role"];
          p_user: string;
        };
        Returns: undefined;
      };
      set_representative_result: {
        Args: { p_experiment: string; p_group: string; p_project: string; p_reason: string };
        Returns: undefined;
      };
    };
    Enums: {
      baseline_kind: "internal" | "reported";
      group_state: "draft" | "finalized";
      metric_direction: "higher" | "lower" | "target";
      metric_state: "measured" | "missing" | "error";
      project_role: "owner" | "editor" | "viewer";
      run_status: "queued" | "running" | "succeeded" | "failed" | "cancelled";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema["CompositeTypes"] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      baseline_kind: ["internal", "reported"],
      group_state: ["draft", "finalized"],
      metric_direction: ["higher", "lower", "target"],
      metric_state: ["measured", "missing", "error"],
      project_role: ["owner", "editor", "viewer"],
      run_status: ["queued", "running", "succeeded", "failed", "cancelled"],
    },
  },
} as const;
