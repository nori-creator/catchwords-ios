-- Baseline, part 2 of 3 (see part 1 for how the baseline was made). Tables, keys, indexes, triggers, policies.

CREATE TABLE public.stickers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    word_id uuid NOT NULL,
    language text DEFAULT 'zh-TW'::text NOT NULL,
    object_image_url text,
    cutout_image_url text,
    selfie_image_url text,
    caption text,
    location_name text,
    lat double precision,
    lng double precision,
    taken_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    visibility text DEFAULT 'private'::text NOT NULL,
    encounter_count integer DEFAULT 0 NOT NULL,
    capture_type text DEFAULT 'photo'::text NOT NULL,
    placeholder_image_url text,
    placeholder_credit jsonb,
    branch_plan jsonb,
    shelf_key text,
    speaking_scaffold jsonb,
    hero_role text,
    voice_video_url text,
    album_hidden boolean DEFAULT false NOT NULL,
    album_order bigint,
    album_size text,
    album_x double precision,
    album_y double precision,
    album_scale double precision,
    album_rot double precision,
    CONSTRAINT stickers_album_placement_check CHECK ((((album_x IS NULL) OR ((album_x >= (0)::double precision) AND (album_x <= (1)::double precision))) AND ((album_y IS NULL) OR ((album_y >= (0)::double precision) AND (album_y <= (8)::double precision))) AND ((album_scale IS NULL) OR ((album_scale >= (0.45)::double precision) AND (album_scale <= (2.6)::double precision))) AND ((album_rot IS NULL) OR ((album_rot >= ('-180'::integer)::double precision) AND (album_rot <= (180)::double precision))))),
    CONSTRAINT stickers_album_size_check CHECK (((album_size IS NULL) OR (album_size = ANY (ARRAY['small'::text, 'portrait'::text, 'landscape'::text, 'large'::text])))),
    CONSTRAINT stickers_capture_type_check CHECK ((capture_type = ANY (ARRAY['photo'::text, 'text'::text, 'voice'::text]))),
    CONSTRAINT stickers_hero_role_valid CHECK (((hero_role IS NULL) OR (hero_role = ANY (ARRAY['object'::text, 'cutout'::text, 'selfie'::text, 'placeholder'::text])))),
    CONSTRAINT stickers_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'friends'::text, 'public'::text])))
);

CREATE TABLE public.usage_events (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.usage_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.usage_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.user_roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role public.app_role NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.user_shelves (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    key text NOT NULL,
    label text NOT NULL,
    emoji text DEFAULT '📦'::text NOT NULL,
    room_key text NOT NULL,
    room_label text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_shelves_emoji_len CHECK (((char_length(emoji) >= 1) AND (char_length(emoji) <= 8))),
    CONSTRAINT user_shelves_key_shape CHECK ((key ~ '^[a-z][a-z0-9_]{1,38}$'::text)),
    CONSTRAINT user_shelves_label_len CHECK ((((char_length(label) >= 1) AND (char_length(label) <= 24)) AND ((char_length(room_label) >= 1) AND (char_length(room_label) <= 24)))),
    CONSTRAINT user_shelves_room_key_shape CHECK ((room_key ~ '^[a-z][a-z0-9_]{1,38}$'::text))
);

CREATE TABLE public.word_explanations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    word_id uuid NOT NULL,
    explain_lang text NOT NULL,
    l1 text NOT NULL,
    meaning text DEFAULT ''::text NOT NULL,
    example_translation text,
    extras jsonb DEFAULT '{}'::jsonb NOT NULL,
    source text DEFAULT 'ai'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT word_explanations_source_check CHECK ((source = ANY (ARRAY['seed'::text, 'verified'::text, 'ai'::text])))
);

CREATE TABLE public.wordbook_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    wordbook_id uuid NOT NULL,
    user_id uuid NOT NULL,
    headword text NOT NULL,
    reading_zhuyin text,
    pinyin text,
    meaning_ja text,
    ease numeric DEFAULT 2.5 NOT NULL,
    interval_days integer DEFAULT 0 NOT NULL,
    repetitions integer DEFAULT 0 NOT NULL,
    due_at timestamp with time zone DEFAULT now() NOT NULL,
    last_reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.wordbooks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.words (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    language text DEFAULT 'zh-TW'::text NOT NULL,
    headword text NOT NULL,
    reading_zhuyin text,
    pinyin text,
    meaning_ja text NOT NULL,
    part_of_speech text,
    level text,
    category_key text,
    example_sentence text,
    example_translation text,
    source text DEFAULT 'seed'::text NOT NULL,
    silhouette_emoji text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    extras jsonb DEFAULT '{}'::jsonb NOT NULL,
    entry_type text DEFAULT 'word'::text NOT NULL,
    reading_primary text,
    reading_alt text,
    CONSTRAINT words_entry_type_check CHECK ((entry_type = ANY (ARRAY['word'::text, 'phrase'::text])))
);

ALTER TABLE ONLY public.ai_consents
    ADD CONSTRAINT ai_consents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (key);

ALTER TABLE ONLY public.apple_tokens
    ADD CONSTRAINT apple_tokens_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (key);

ALTER TABLE ONLY public.corpus_pairs
    ADD CONSTRAINT corpus_pairs_pkey PRIMARY KEY (word_a, word_b, day, source);

ALTER TABLE ONLY public.corpus_stats
    ADD CONSTRAINT corpus_stats_pkey PRIMARY KEY (word, day, source);

ALTER TABLE ONLY public.daily_quests
    ADD CONSTRAINT daily_quests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.daily_quests
    ADD CONSTRAINT daily_quests_user_id_quest_date_target_word_key UNIQUE (user_id, quest_date, target_word);

ALTER TABLE ONLY public.dictionary_entries
    ADD CONSTRAINT dictionary_entries_language_headword_entry_type_key UNIQUE (language, headword, entry_type);

ALTER TABLE ONLY public.dictionary_entries
    ADD CONSTRAINT dictionary_entries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.encounters
    ADD CONSTRAINT encounters_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.entry_reports
    ADD CONSTRAINT entry_reports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_pkey PRIMARY KEY (follower_id, following_id);

ALTER TABLE ONLY public.generated_cards
    ADD CONSTRAINT generated_cards_pkey PRIMARY KEY (language, headword, explain_lang, l1);

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.lexicon_audits
    ADD CONSTRAINT lexicon_audits_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.model_shadow_predictions
    ADD CONSTRAINT model_shadow_predictions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_pkey PRIMARY KEY (post_id, user_id);

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.review_choices
    ADD CONSTRAINT review_choices_pkey PRIMARY KEY (word_id);

ALTER TABLE ONLY public.review_history
    ADD CONSTRAINT review_history_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_user_id_sticker_id_key UNIQUE (user_id, sticker_id);

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT scan_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.self_improve_runs
    ADD CONSTRAINT self_improve_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.stickers
    ADD CONSTRAINT stickers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.usage_events
    ADD CONSTRAINT usage_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_role_key UNIQUE (user_id, role);

ALTER TABLE ONLY public.user_shelves
    ADD CONSTRAINT user_shelves_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_shelves
    ADD CONSTRAINT user_shelves_user_id_key_key UNIQUE (user_id, key);

ALTER TABLE ONLY public.word_explanations
    ADD CONSTRAINT word_explanations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.word_explanations
    ADD CONSTRAINT word_explanations_word_id_explain_lang_l1_key UNIQUE (word_id, explain_lang, l1);

ALTER TABLE ONLY public.wordbook_entries
    ADD CONSTRAINT wordbook_entries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.wordbook_entries
    ADD CONSTRAINT wordbook_entries_wordbook_id_headword_key UNIQUE (wordbook_id, headword);

ALTER TABLE ONLY public.wordbooks
    ADD CONSTRAINT wordbooks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_language_headword_key UNIQUE (language, headword);

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_pkey PRIMARY KEY (id);

CREATE INDEX ai_consents_user_idx ON public.ai_consents USING btree (user_id, agreed_at DESC);

CREATE INDEX ai_runs_user_created_idx ON public.ai_runs USING btree (user_id, created_at DESC);

CREATE INDEX corpus_pairs_day_idx ON public.corpus_pairs USING btree (day DESC, count DESC);

CREATE INDEX corpus_stats_day_idx ON public.corpus_stats USING btree (day DESC, count DESC);

CREATE INDEX dictionary_entries_freq_idx ON public.dictionary_entries USING btree (language, freq_rank);

CREATE INDEX dictionary_entries_headword_idx ON public.dictionary_entries USING btree (language, headword);

CREATE INDEX dictionary_entries_level_idx ON public.dictionary_entries USING btree (language, level_step);

CREATE INDEX dictionary_entries_source_idx ON public.dictionary_entries USING btree (source);

CREATE INDEX encounters_sticker_created_idx ON public.encounters USING btree (sticker_id, created_at);

CREATE INDEX encounters_sticker_idx ON public.encounters USING btree (sticker_id, created_at DESC);

CREATE INDEX encounters_user_idx ON public.encounters USING btree (user_id, created_at DESC);

CREATE INDEX entry_reports_status_idx ON public.entry_reports USING btree (status, created_at DESC);

CREATE INDEX entry_reports_word_idx ON public.entry_reports USING btree (word_id);

CREATE INDEX generated_cards_created_at_idx ON public.generated_cards USING btree (created_at);

CREATE UNIQUE INDEX journal_entries_user_date_unique ON public.journal_entries USING btree (user_id, entry_date);

CREATE INDEX journal_user_date_idx ON public.journal_entries USING btree (user_id, entry_date DESC);

CREATE INDEX lexicon_audits_created_idx ON public.lexicon_audits USING btree (created_at DESC);

CREATE INDEX model_shadow_predictions_task_created ON public.model_shadow_predictions USING btree (task, created_at DESC);

CREATE INDEX notifications_user_created_idx ON public.notifications USING btree (user_id, created_at DESC);

CREATE INDEX post_comments_post_idx ON public.post_comments USING btree (post_id, created_at);

CREATE INDEX posts_user_created_idx ON public.posts USING btree (user_id, created_at DESC);

CREATE INDEX posts_visibility_created_idx ON public.posts USING btree (visibility, created_at DESC);

CREATE INDEX review_history_sticker_idx ON public.review_history USING btree (sticker_id, reviewed_at DESC);

CREATE INDEX review_history_user_reviewed_at_idx ON public.review_history USING btree (user_id, reviewed_at DESC);

CREATE INDEX reviews_user_due_idx ON public.reviews USING btree (user_id, due_at);

CREATE INDEX scan_events_user_created_idx ON public.scan_events USING btree (user_id, created_at DESC);

CREATE INDEX scan_events_user_headword_idx ON public.scan_events USING btree (user_id, headword);

CREATE INDEX self_improve_runs_created_idx ON public.self_improve_runs USING btree (created_at DESC);

CREATE INDEX stickers_album_hidden_idx ON public.stickers USING btree (user_id) WHERE album_hidden;

CREATE INDEX stickers_user_album_order_idx ON public.stickers USING btree (user_id, album_order) WHERE (album_order IS NOT NULL);

CREATE INDEX stickers_user_idx ON public.stickers USING btree (user_id, created_at DESC);

CREATE INDEX usage_events_user_created_idx ON public.usage_events USING btree (user_id, created_at DESC);

CREATE INDEX usage_events_user_kind_created_idx ON public.usage_events USING btree (user_id, kind, created_at DESC);

CREATE INDEX user_shelves_user_idx ON public.user_shelves USING btree (user_id, created_at);

CREATE INDEX word_explanations_lookup_idx ON public.word_explanations USING btree (word_id, explain_lang, l1);

CREATE INDEX wordbook_entries_book_due_idx ON public.wordbook_entries USING btree (wordbook_id, due_at);

CREATE INDEX wordbook_entries_user_due_idx ON public.wordbook_entries USING btree (user_id, due_at);

CREATE INDEX wordbooks_user_created_idx ON public.wordbooks USING btree (user_id, created_at DESC);

CREATE TRIGGER dictionary_entries_set_updated_at BEFORE UPDATE ON public.dictionary_entries FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER follows_notify AFTER INSERT ON public.follows FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();

CREATE TRIGGER post_comments_count_del AFTER DELETE ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.bump_post_comment_count();

CREATE TRIGGER post_comments_count_ins AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.bump_post_comment_count();

CREATE TRIGGER post_comments_notify AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.notify_on_comment();

CREATE TRIGGER post_likes_count_del AFTER DELETE ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.bump_post_like_count();

CREATE TRIGGER post_likes_count_ins AFTER INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.bump_post_like_count();

CREATE TRIGGER post_likes_notify AFTER INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.notify_on_like();

CREATE TRIGGER posts_updated BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER profiles_guard_plan BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.guard_profile_plan();

CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER reviews_set_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER stickers_create_review AFTER INSERT ON public.stickers FOR EACH ROW EXECUTE FUNCTION public.create_review_for_new_sticker();

CREATE TRIGGER trg_enforce_words_source BEFORE INSERT ON public.words FOR EACH ROW EXECUTE FUNCTION public.enforce_words_source();

CREATE TRIGGER trg_preserve_post_counters BEFORE UPDATE ON public.posts FOR EACH ROW WHEN ((current_setting('role'::text, true) <> 'service_role'::text)) EXECUTE FUNCTION public.preserve_post_counters();

ALTER TABLE ONLY public.ai_consents
    ADD CONSTRAINT ai_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.ai_runs
    ADD CONSTRAINT ai_runs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.apple_tokens
    ADD CONSTRAINT apple_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.daily_quests
    ADD CONSTRAINT daily_quests_sticker_id_fkey FOREIGN KEY (sticker_id) REFERENCES public.stickers(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.daily_quests
    ADD CONSTRAINT daily_quests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.encounters
    ADD CONSTRAINT encounters_sticker_id_fkey FOREIGN KEY (sticker_id) REFERENCES public.stickers(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.encounters
    ADD CONSTRAINT encounters_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.entry_reports
    ADD CONSTRAINT entry_reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_following_id_fkey FOREIGN KEY (following_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.lexicon_audits
    ADD CONSTRAINT lexicon_audits_entry_id_fkey FOREIGN KEY (entry_id) REFERENCES public.dictionary_entries(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.model_shadow_predictions
    ADD CONSTRAINT model_shadow_predictions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_sticker_id_fkey FOREIGN KEY (sticker_id) REFERENCES public.stickers(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.review_choices
    ADD CONSTRAINT review_choices_word_id_fkey FOREIGN KEY (word_id) REFERENCES public.words(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.review_history
    ADD CONSTRAINT review_history_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.reviews(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.review_history
    ADD CONSTRAINT review_history_sticker_id_fkey FOREIGN KEY (sticker_id) REFERENCES public.stickers(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.review_history
    ADD CONSTRAINT review_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_sticker_id_fkey FOREIGN KEY (sticker_id) REFERENCES public.stickers(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.scan_events
    ADD CONSTRAINT scan_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.stickers
    ADD CONSTRAINT stickers_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.stickers
    ADD CONSTRAINT stickers_word_id_fkey FOREIGN KEY (word_id) REFERENCES public.words(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.usage_events
    ADD CONSTRAINT usage_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_shelves
    ADD CONSTRAINT user_shelves_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.word_explanations
    ADD CONSTRAINT word_explanations_word_id_fkey FOREIGN KEY (word_id) REFERENCES public.words(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.wordbook_entries
    ADD CONSTRAINT wordbook_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.wordbook_entries
    ADD CONSTRAINT wordbook_entries_wordbook_id_fkey FOREIGN KEY (wordbook_id) REFERENCES public.wordbooks(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.wordbooks
    ADD CONSTRAINT wordbooks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_category_key_fkey FOREIGN KEY (category_key) REFERENCES public.categories(key);

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE POLICY "Anyone can read dictionary" ON public.dictionary_entries FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY "Users delete own scan events" ON public.scan_events FOR DELETE TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY "Users insert own scan events" ON public.scan_events FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY "Users read own scan events" ON public.scan_events FOR SELECT TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY "Users update own scan events" ON public.scan_events FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.ai_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY ai_consents_select_own ON public.ai_consents FOR SELECT TO authenticated USING ((auth.uid() = user_id));

ALTER TABLE public.ai_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY ai_runs_insert_own ON public.ai_runs FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY ai_runs_select_own ON public.ai_runs FOR SELECT TO authenticated USING ((auth.uid() = user_id));

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY app_config_select ON public.app_config FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE POLICY app_config_write ON public.app_config TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

ALTER TABLE public.apple_tokens ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY categories_select_all ON public.categories FOR SELECT USING (true);

CREATE POLICY "comments delete own" ON public.post_comments FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "comments insert own" ON public.post_comments FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.can_see_post(post_id, auth.uid())));

CREATE POLICY "comments visible if post visible" ON public.post_comments FOR SELECT TO authenticated USING (public.can_see_post(post_id, auth.uid()));

ALTER TABLE public.corpus_pairs ENABLE ROW LEVEL SECURITY;

CREATE POLICY corpus_pairs_read_authenticated ON public.corpus_pairs FOR SELECT TO authenticated USING (true);

ALTER TABLE public.corpus_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY corpus_stats_read_authenticated ON public.corpus_stats FOR SELECT TO authenticated USING (true);

ALTER TABLE public.daily_quests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.dictionary_entries ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.encounters ENABLE ROW LEVEL SECURITY;

CREATE POLICY encounters_insert_own ON public.encounters FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY encounters_select_own ON public.encounters FOR SELECT TO authenticated USING ((auth.uid() = user_id));

ALTER TABLE public.entry_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY entry_reports_insert_own ON public.entry_reports FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY entry_reports_select_own ON public.entry_reports FOR SELECT TO authenticated USING ((auth.uid() = user_id));

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "follows self delete" ON public.follows FOR DELETE TO authenticated USING ((auth.uid() = follower_id));

CREATE POLICY "follows self read" ON public.follows FOR SELECT TO authenticated USING (((auth.uid() = follower_id) OR (auth.uid() = following_id)));

