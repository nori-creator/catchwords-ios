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
      ai_consents: {
        Row: {
          agreed_at: string
          created_at: string
          id: string
          revoked_at: string | null
          source: string
          user_id: string
          version: number
        }
        Insert: {
          agreed_at?: string
          created_at?: string
          id?: string
          revoked_at?: string | null
          source?: string
          user_id: string
          version: number
        }
        Update: {
          agreed_at?: string
          created_at?: string
          id?: string
          revoked_at?: string | null
          source?: string
          user_id?: string
          version?: number
        }
        Relationships: []
      }
      ai_runs: {
        Row: {
          accepted: number
          created_at: string
          id: string
          iterations: number
          loop: string
          meta: Json | null
          tokens_in: number | null
          tokens_out: number | null
          user_id: string
        }
        Insert: {
          accepted?: number
          created_at?: string
          id?: string
          iterations?: number
          loop: string
          meta?: Json | null
          tokens_in?: number | null
          tokens_out?: number | null
          user_id: string
        }
        Update: {
          accepted?: number
          created_at?: string
          id?: string
          iterations?: number
          loop?: string
          meta?: Json | null
          tokens_in?: number | null
          tokens_out?: number | null
          user_id?: string
        }
        Relationships: []
      }
      app_config: {
        Row: {
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: []
      }
      apple_tokens: {
        Row: {
          client_id: string | null
          created_at: string
          token: string
          token_type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string
          token: string
          token_type?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          client_id?: string | null
          created_at?: string
          token?: string
          token_type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      categories: {
        Row: {
          icon_emoji: string
          key: string
          label_ja: string
          sort_order: number
        }
        Insert: {
          icon_emoji?: string
          key: string
          label_ja: string
          sort_order?: number
        }
        Update: {
          icon_emoji?: string
          key?: string
          label_ja?: string
          sort_order?: number
        }
        Relationships: []
      }
      corpus_pairs: {
        Row: {
          count: number
          day: string
          source: string
          word_a: string
          word_b: string
        }
        Insert: {
          count?: number
          day: string
          source?: string
          word_a: string
          word_b: string
        }
        Update: {
          count?: number
          day?: string
          source?: string
          word_a?: string
          word_b?: string
        }
        Relationships: []
      }
      corpus_stats: {
        Row: {
          count: number
          day: string
          source: string
          word: string
        }
        Insert: {
          count?: number
          day: string
          source?: string
          word: string
        }
        Update: {
          count?: number
          day?: string
          source?: string
          word?: string
        }
        Relationships: []
      }
      daily_quests: {
        Row: {
          category_key: string | null
          completed_at: string | null
          created_at: string
          hint_ja: string
          id: string
          quest_date: string
          reward_xp: number
          sticker_id: string | null
          target_word: string
          user_id: string
        }
        Insert: {
          category_key?: string | null
          completed_at?: string | null
          created_at?: string
          hint_ja: string
          id?: string
          quest_date?: string
          reward_xp?: number
          sticker_id?: string | null
          target_word: string
          user_id: string
        }
        Update: {
          category_key?: string | null
          completed_at?: string | null
          created_at?: string
          hint_ja?: string
          id?: string
          quest_date?: string
          reward_xp?: number
          sticker_id?: string | null
          target_word?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "daily_quests_sticker_id_fkey"
            columns: ["sticker_id"]
            isOneToOne: false
            referencedRelation: "stickers"
            referencedColumns: ["id"]
          },
        ]
      }
      dictionary_entries: {
        Row: {
          audio_path: string | null
          created_at: string
          entry_type: string
          exam_tags: string[] | null
          forms: Json | null
          freq_rank: number | null
          headword: string
          id: string
          language: string
          level_step: number | null
          meaning_ja: string | null
          meanings: Json
          notes: string | null
          pinyin: string | null
          pos: string | null
          reading_alt: string | null
          reading_primary: string | null
          scene_tags: string[] | null
          source: string
          taiwan_usage: string | null
          tocfl_level: number | null
          updated_at: string
          usage_register: string | null
          zhuyin: string | null
        }
        Insert: {
          audio_path?: string | null
          created_at?: string
          entry_type?: string
          exam_tags?: string[] | null
          forms?: Json | null
          freq_rank?: number | null
          headword: string
          id?: string
          language?: string
          level_step?: number | null
          meaning_ja?: string | null
          meanings?: Json
          notes?: string | null
          pinyin?: string | null
          pos?: string | null
          reading_alt?: string | null
          reading_primary?: string | null
          scene_tags?: string[] | null
          source?: string
          taiwan_usage?: string | null
          tocfl_level?: number | null
          updated_at?: string
          usage_register?: string | null
          zhuyin?: string | null
        }
        Update: {
          audio_path?: string | null
          created_at?: string
          entry_type?: string
          exam_tags?: string[] | null
          forms?: Json | null
          freq_rank?: number | null
          headword?: string
          id?: string
          language?: string
          level_step?: number | null
          meaning_ja?: string | null
          meanings?: Json
          notes?: string | null
          pinyin?: string | null
          pos?: string | null
          reading_alt?: string | null
          reading_primary?: string | null
          scene_tags?: string[] | null
          source?: string
          taiwan_usage?: string | null
          tocfl_level?: number | null
          updated_at?: string
          usage_register?: string | null
          zhuyin?: string | null
        }
        Relationships: []
      }
      encounters: {
        Row: {
          created_at: string
          cutout_path: string | null
          id: string
          image_path: string | null
          lat: number | null
          lng: number | null
          location_name: string | null
          recalled: boolean | null
          sticker_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          cutout_path?: string | null
          id?: string
          image_path?: string | null
          lat?: number | null
          lng?: number | null
          location_name?: string | null
          recalled?: boolean | null
          sticker_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          cutout_path?: string | null
          id?: string
          image_path?: string | null
          lat?: number | null
          lng?: number | null
          location_name?: string | null
          recalled?: boolean | null
          sticker_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "encounters_sticker_id_fkey"
            columns: ["sticker_id"]
            isOneToOne: false
            referencedRelation: "stickers"
            referencedColumns: ["id"]
          },
        ]
      }
      entry_reports: {
        Row: {
          created_at: string
          headword: string
          id: string
          kind: string
          note: string
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          headword: string
          id?: string
          kind: string
          note?: string
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          headword?: string
          id?: string
          kind?: string
          note?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      follows: {
        Row: {
          created_at: string
          follower_id: string
          following_id: string
        }
        Insert: {
          created_at?: string
          follower_id: string
          following_id: string
        }
        Update: {
          created_at?: string
          follower_id?: string
          following_id?: string
        }
        Relationships: []
      }
      generated_cards: {
        Row: {
          card: Json
          created_at: string
          explain_lang: string
          headword: string
          kind: string
          l1: string
          language: string
        }
        Insert: {
          card?: Json
          created_at?: string
          explain_lang?: string
          headword: string
          kind?: string
          l1?: string
          language: string
        }
        Update: {
          card?: Json
          created_at?: string
          explain_lang?: string
          headword?: string
          kind?: string
          l1?: string
          language?: string
        }
        Relationships: []
      }
      journal_entries: {
        Row: {
          body_ja: string | null
          body_zh: string | null
          correction: string | null
          created_at: string
          entry_date: string
          feedback_ja: string | null
          id: string
          model: string | null
          native_phrases: Json | null
          used_sticker_ids: string[]
          user_draft: string | null
          user_id: string
        }
        Insert: {
          body_ja?: string | null
          body_zh?: string | null
          correction?: string | null
          created_at?: string
          entry_date?: string
          feedback_ja?: string | null
          id?: string
          model?: string | null
          native_phrases?: Json | null
          used_sticker_ids?: string[]
          user_draft?: string | null
          user_id: string
        }
        Update: {
          body_ja?: string | null
          body_zh?: string | null
          correction?: string | null
          created_at?: string
          entry_date?: string
          feedback_ja?: string | null
          id?: string
          model?: string | null
          native_phrases?: Json | null
          used_sticker_ids?: string[]
          user_draft?: string | null
          user_id?: string
        }
        Relationships: []
      }
      lexicon_audits: {
        Row: {
          applied: boolean
          confidence: number | null
          created_at: string
          entry_id: string | null
          headword: string
          id: string
          ok: boolean
          source: string
          suggestion: Json | null
        }
        Insert: {
          applied?: boolean
          confidence?: number | null
          created_at?: string
          entry_id?: string | null
          headword: string
          id?: string
          ok: boolean
          source: string
          suggestion?: Json | null
        }
        Update: {
          applied?: boolean
          confidence?: number | null
          created_at?: string
          entry_id?: string | null
          headword?: string
          id?: string
          ok?: boolean
          source?: string
          suggestion?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "lexicon_audits_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "dictionary_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          actor_id: string | null
          created_at: string
          id: string
          post_id: string | null
          read_at: string | null
          type: string
          user_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          id?: string
          post_id?: string | null
          read_at?: string | null
          type: string
          user_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          id?: string
          post_id?: string | null
          read_at?: string | null
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
        ]
      }
      post_comments: {
        Row: {
          body: string
          created_at: string
          id: string
          post_id: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          post_id: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "post_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
        ]
      }
      post_likes: {
        Row: {
          created_at: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "post_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
        ]
      }
      posts: {
        Row: {
          caption: string | null
          comment_count: number
          created_at: string
          id: string
          like_count: number
          sticker_id: string | null
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          caption?: string | null
          comment_count?: number
          created_at?: string
          id?: string
          like_count?: number
          sticker_id?: string | null
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          caption?: string | null
          comment_count?: number
          created_at?: string
          id?: string
          like_count?: number
          sticker_id?: string | null
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "posts_sticker_id_fkey"
            columns: ["sticker_id"]
            isOneToOne: false
            referencedRelation: "stickers"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          album_bg: string
          avatar_url: string | null
          created_at: string
          current_level: string | null
          display_name: string | null
          id: string
          level_goal: string
          native_language: string
          onboarded: boolean
          plan: string
          pronunciation_strictness: string
          review_daily_limit: number
          review_mode: string
          review_stage_focus: string
          target_language: string
          ui_language: string
          updated_at: string
        }
        Insert: {
          album_bg?: string
          avatar_url?: string | null
          created_at?: string
          current_level?: string | null
          display_name?: string | null
          id: string
          level_goal?: string
          native_language?: string
          onboarded?: boolean
          plan?: string
          pronunciation_strictness?: string
          review_daily_limit?: number
          review_mode?: string
          review_stage_focus?: string
          target_language?: string
          ui_language?: string
          updated_at?: string
        }
        Update: {
          album_bg?: string
          avatar_url?: string | null
          created_at?: string
          current_level?: string | null
          display_name?: string | null
          id?: string
          level_goal?: string
          native_language?: string
          onboarded?: boolean
          plan?: string
          pronunciation_strictness?: string
          review_daily_limit?: number
          review_mode?: string
          review_stage_focus?: string
          target_language?: string
          ui_language?: string
          updated_at?: string
        }
        Relationships: []
      }
      review_choices: {
        Row: {
          distractors: string[]
          generated_at: string
          word_id: string
        }
        Insert: {
          distractors?: string[]
          generated_at?: string
          word_id: string
        }
        Update: {
          distractors?: string[]
          generated_at?: string
          word_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "review_choices_word_id_fkey"
            columns: ["word_id"]
            isOneToOne: true
            referencedRelation: "words"
            referencedColumns: ["id"]
          },
        ]
      }
      review_history: {
        Row: {
          blur_seen: boolean
          correct: boolean
          ease_after: number
          id: string
          interval_days_after: number
          repetitions_after: number
          response_ms: number
          review_id: string
          reviewed_at: string
          score: number
          sticker_id: string
          user_id: string
        }
        Insert: {
          blur_seen?: boolean
          correct: boolean
          ease_after: number
          id?: string
          interval_days_after: number
          repetitions_after: number
          response_ms?: number
          review_id: string
          reviewed_at?: string
          score: number
          sticker_id: string
          user_id: string
        }
        Update: {
          blur_seen?: boolean
          correct?: boolean
          ease_after?: number
          id?: string
          interval_days_after?: number
          repetitions_after?: number
          response_ms?: number
          review_id?: string
          reviewed_at?: string
          score?: number
          sticker_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "review_history_review_id_fkey"
            columns: ["review_id"]
            isOneToOne: false
            referencedRelation: "reviews"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "review_history_sticker_id_fkey"
            columns: ["sticker_id"]
            isOneToOne: false
            referencedRelation: "stickers"
            referencedColumns: ["id"]
          },
        ]
      }
      reviews: {
        Row: {
          blur_seen: boolean
          created_at: string
          due_at: string
          ease: number
          id: string
          interval_days: number
          last_reviewed_at: string | null
          last_score: number | null
          repetitions: number
          sticker_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          blur_seen?: boolean
          created_at?: string
          due_at?: string
          ease?: number
          id?: string
          interval_days?: number
          last_reviewed_at?: string | null
          last_score?: number | null
          repetitions?: number
          sticker_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          blur_seen?: boolean
          created_at?: string
          due_at?: string
          ease?: number
          id?: string
          interval_days?: number
          last_reviewed_at?: string | null
          last_score?: number | null
          repetitions?: number
          sticker_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reviews_sticker_id_fkey"
            columns: ["sticker_id"]
            isOneToOne: false
            referencedRelation: "stickers"
            referencedColumns: ["id"]
          },
        ]
      }
      scan_events: {
        Row: {
          caught: boolean
          confidence: number | null
          created_at: string
          detect_ms: number | null
          headword: string
          id: string
          kind: string
          lat: number | null
          lng: number | null
          meaning_ja: string | null
          tap_to_audio_ms: number | null
          tapped: boolean
          user_id: string
        }
        Insert: {
          caught?: boolean
          confidence?: number | null
          created_at?: string
          detect_ms?: number | null
          headword: string
          id?: string
          kind: string
          lat?: number | null
          lng?: number | null
          meaning_ja?: string | null
          tap_to_audio_ms?: number | null
          tapped?: boolean
          user_id: string
        }
        Update: {
          caught?: boolean
          confidence?: number | null
          created_at?: string
          detect_ms?: number | null
          headword?: string
          id?: string
          kind?: string
          lat?: number | null
          lng?: number | null
          meaning_ja?: string | null
          tap_to_audio_ms?: number | null
          tapped?: boolean
          user_id?: string
        }
        Relationships: []
      }
      self_improve_runs: {
        Row: {
          created_at: string
          detail: Json | null
          id: string
          ok: boolean
          step: string
        }
        Insert: {
          created_at?: string
          detail?: Json | null
          id?: string
          ok: boolean
          step: string
        }
        Update: {
          created_at?: string
          detail?: Json | null
          id?: string
          ok?: boolean
          step?: string
        }
        Relationships: []
      }
      stickers: {
        Row: {
          album_order: number | null
          album_rot: number | null
          album_scale: number | null
          album_size: string | null
          album_x: number | null
          album_y: number | null
          branch_plan: Json | null
          caption: string | null
          capture_type: string
          created_at: string
          cutout_image_url: string | null
          encounter_count: number
          hero_role: string | null
          id: string
          language: string
          lat: number | null
          lng: number | null
          location_name: string | null
          object_image_url: string | null
          placeholder_credit: Json | null
          placeholder_image_url: string | null
          selfie_image_url: string | null
          shelf_key: string | null
          speaking_scaffold: Json | null
          taken_at: string
          user_id: string
          visibility: string
          voice_video_url: string | null
          word_id: string
        }
        Insert: {
          album_order?: number | null
          album_rot?: number | null
          album_scale?: number | null
          album_size?: string | null
          album_x?: number | null
          album_y?: number | null
          branch_plan?: Json | null
          caption?: string | null
          capture_type?: string
          created_at?: string
          cutout_image_url?: string | null
          encounter_count?: number
          hero_role?: string | null
          id?: string
          language?: string
          lat?: number | null
          lng?: number | null
          location_name?: string | null
          object_image_url?: string | null
          placeholder_credit?: Json | null
          placeholder_image_url?: string | null
          selfie_image_url?: string | null
          shelf_key?: string | null
          speaking_scaffold?: Json | null
          taken_at?: string
          user_id: string
          visibility?: string
          voice_video_url?: string | null
          word_id: string
        }
        Update: {
          album_order?: number | null
          album_rot?: number | null
          album_scale?: number | null
          album_size?: string | null
          album_x?: number | null
          album_y?: number | null
          branch_plan?: Json | null
          caption?: string | null
          capture_type?: string
          created_at?: string
          cutout_image_url?: string | null
          encounter_count?: number
          hero_role?: string | null
          id?: string
          language?: string
          lat?: number | null
          lng?: number | null
          location_name?: string | null
          object_image_url?: string | null
          placeholder_credit?: Json | null
          placeholder_image_url?: string | null
          selfie_image_url?: string | null
          shelf_key?: string | null
          speaking_scaffold?: Json | null
          taken_at?: string
          user_id?: string
          visibility?: string
          voice_video_url?: string | null
          word_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stickers_word_id_fkey"
            columns: ["word_id"]
            isOneToOne: false
            referencedRelation: "words"
            referencedColumns: ["id"]
          },
        ]
      }
      usage_events: {
        Row: {
          created_at: string
          id: number
          kind: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: never
          kind: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: never
          kind?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      user_shelves: {
        Row: {
          created_at: string
          emoji: string
          id: string
          key: string
          label: string
          room_key: string
          room_label: string
          user_id: string
        }
        Insert: {
          created_at?: string
          emoji?: string
          id?: string
          key: string
          label: string
          room_key: string
          room_label: string
          user_id: string
        }
        Update: {
          created_at?: string
          emoji?: string
          id?: string
          key?: string
          label?: string
          room_key?: string
          room_label?: string
          user_id?: string
        }
        Relationships: []
      }
      word_explanations: {
        Row: {
          created_at: string
          example_translation: string | null
          explain_lang: string
          extras: Json
          id: string
          l1: string
          meaning: string
          source: string
          updated_at: string
          word_id: string
        }
        Insert: {
          created_at?: string
          example_translation?: string | null
          explain_lang: string
          extras?: Json
          id?: string
          l1: string
          meaning?: string
          source?: string
          updated_at?: string
          word_id: string
        }
        Update: {
          created_at?: string
          example_translation?: string | null
          explain_lang?: string
          extras?: Json
          id?: string
          l1?: string
          meaning?: string
          source?: string
          updated_at?: string
          word_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "word_explanations_word_id_fkey"
            columns: ["word_id"]
            isOneToOne: false
            referencedRelation: "words"
            referencedColumns: ["id"]
          },
        ]
      }
      wordbook_entries: {
        Row: {
          created_at: string
          due_at: string
          ease: number
          headword: string
          id: string
          interval_days: number
          last_reviewed_at: string | null
          meaning_ja: string | null
          pinyin: string | null
          reading_zhuyin: string | null
          repetitions: number
          user_id: string
          wordbook_id: string
        }
        Insert: {
          created_at?: string
          due_at?: string
          ease?: number
          headword: string
          id?: string
          interval_days?: number
          last_reviewed_at?: string | null
          meaning_ja?: string | null
          pinyin?: string | null
          reading_zhuyin?: string | null
          repetitions?: number
          user_id: string
          wordbook_id: string
        }
        Update: {
          created_at?: string
          due_at?: string
          ease?: number
          headword?: string
          id?: string
          interval_days?: number
          last_reviewed_at?: string | null
          meaning_ja?: string | null
          pinyin?: string | null
          reading_zhuyin?: string | null
          repetitions?: number
          user_id?: string
          wordbook_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wordbook_entries_wordbook_id_fkey"
            columns: ["wordbook_id"]
            isOneToOne: false
            referencedRelation: "wordbooks"
            referencedColumns: ["id"]
          },
        ]
      }
      wordbooks: {
        Row: {
          created_at: string
          id: string
          title: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          title: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      words: {
        Row: {
          category_key: string | null
          created_at: string
          created_by: string | null
          entry_type: string
          example_sentence: string | null
          example_translation: string | null
          extras: Json
          headword: string
          id: string
          language: string
          level: string | null
          meaning_ja: string
          part_of_speech: string | null
          pinyin: string | null
          reading_alt: string | null
          reading_primary: string | null
          reading_zhuyin: string | null
          silhouette_emoji: string | null
          source: string
        }
        Insert: {
          category_key?: string | null
          created_at?: string
          created_by?: string | null
          entry_type?: string
          example_sentence?: string | null
          example_translation?: string | null
          extras?: Json
          headword: string
          id?: string
          language?: string
          level?: string | null
          meaning_ja: string
          part_of_speech?: string | null
          pinyin?: string | null
          reading_alt?: string | null
          reading_primary?: string | null
          reading_zhuyin?: string | null
          silhouette_emoji?: string | null
          source?: string
        }
        Update: {
          category_key?: string | null
          created_at?: string
          created_by?: string | null
          entry_type?: string
          example_sentence?: string | null
          example_translation?: string | null
          extras?: Json
          headword?: string
          id?: string
          language?: string
          level?: string | null
          meaning_ja?: string
          part_of_speech?: string | null
          pinyin?: string | null
          reading_alt?: string | null
          reading_primary?: string | null
          reading_zhuyin?: string | null
          silhouette_emoji?: string | null
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "words_category_key_fkey"
            columns: ["category_key"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["key"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      are_mutual_followers: {
        Args: { _a: string; _b: string }
        Returns: boolean
      }
      can_see_post: {
        Args: { _post_id: string; _user: string }
        Returns: boolean
      }
      get_leaderboard: {
        Args: { _limit?: number }
        Returns: {
          avatar_url: string
          display_name: string
          post_count: number
          sticker_count: number
          user_id: string
          xp: number
        }[]
      }
      get_my_profile: {
        Args: never
        Returns: {
          album_bg: string
          avatar_url: string | null
          created_at: string
          current_level: string | null
          display_name: string | null
          id: string
          level_goal: string
          native_language: string
          onboarded: boolean
          plan: string
          pronunciation_strictness: string
          review_daily_limit: number
          review_mode: string
          review_stage_focus: string
          target_language: string
          ui_language: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      reserve_usage_event: {
        Args: {
          p_kind: string
          p_limit: number
          p_since: string
          p_user_id: string
        }
        Returns: number
      }
      save_album_layout: { Args: { p_items: Json }; Returns: number }
    }
    Enums: {
      app_role: "admin" | "user"
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
    Enums: {
      app_role: ["admin", "user"],
    },
  },
} as const
