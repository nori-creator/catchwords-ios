-- Baseline, part 3 of 3 (see part 1). Remaining policies, privileges, storage buckets and policies, auth trigger.

CREATE POLICY "follows self write" ON public.follows FOR INSERT TO authenticated WITH CHECK ((auth.uid() = follower_id));

ALTER TABLE public.generated_cards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.lexicon_audits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "likes delete own" ON public.post_likes FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "likes insert own" ON public.post_likes FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.can_see_post(post_id, auth.uid())));

CREATE POLICY "likes visible if post visible" ON public.post_likes FOR SELECT TO authenticated USING (public.can_see_post(post_id, auth.uid()));

ALTER TABLE public.model_shadow_predictions ENABLE ROW LEVEL SECURITY;

CREATE POLICY model_shadow_predictions_insert_own ON public.model_shadow_predictions FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY model_shadow_predictions_select_own ON public.model_shadow_predictions FOR SELECT TO authenticated USING ((auth.uid() = user_id));

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications own delete" ON public.notifications FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "notifications own select" ON public.notifications FOR SELECT TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "notifications own update" ON public.notifications FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "own journal" ON public.journal_entries USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

CREATE POLICY "own quests" ON public.daily_quests USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "posts delete own" ON public.posts FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "posts insert own" ON public.posts FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "posts update own" ON public.posts FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "posts visible" ON public.posts FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (visibility = 'public'::text) OR ((visibility = 'friends'::text) AND public.are_mutual_followers(auth.uid(), user_id))));

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_insert_self ON public.profiles FOR INSERT TO authenticated WITH CHECK ((auth.uid() = id));

CREATE POLICY profiles_select_own ON public.profiles FOR SELECT TO authenticated USING ((auth.uid() = id));

CREATE POLICY profiles_update_self ON public.profiles FOR UPDATE TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));

ALTER TABLE public.review_choices ENABLE ROW LEVEL SECURITY;

CREATE POLICY review_choices_no_write ON public.review_choices TO authenticated USING (false) WITH CHECK (false);

CREATE POLICY review_choices_select_own_words ON public.review_choices FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.stickers s
  WHERE ((s.word_id = review_choices.word_id) AND (s.user_id = auth.uid())))));

ALTER TABLE public.review_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY review_history_insert_own ON public.review_history FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY review_history_select_own ON public.review_history FOR SELECT TO authenticated USING ((user_id = auth.uid()));

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY reviews_delete_own ON public.reviews FOR DELETE TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY reviews_insert_own ON public.reviews FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY reviews_select_own ON public.reviews FOR SELECT TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY reviews_update_own ON public.reviews FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.scan_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.self_improve_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.stickers ENABLE ROW LEVEL SECURITY;

CREATE POLICY stickers_delete_own ON public.stickers FOR DELETE TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY stickers_insert_own ON public.stickers FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY stickers_select_own ON public.stickers FOR SELECT TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY stickers_update_own ON public.stickers FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.usage_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY usage_events_insert_own ON public.usage_events FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY usage_events_select_own ON public.usage_events FOR SELECT TO authenticated USING ((auth.uid() = user_id));

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_shelves ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_shelves_delete_own ON public.user_shelves FOR DELETE TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY user_shelves_insert_own ON public.user_shelves FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY user_shelves_select_own ON public.user_shelves FOR SELECT TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY user_shelves_update_own ON public.user_shelves FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.word_explanations ENABLE ROW LEVEL SECURITY;

CREATE POLICY word_explanations_no_client_write ON public.word_explanations TO authenticated USING (false) WITH CHECK (false);

CREATE POLICY word_explanations_select_all ON public.word_explanations FOR SELECT TO authenticated USING (true);

ALTER TABLE public.wordbook_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY wordbook_entries_delete_own ON public.wordbook_entries FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY wordbook_entries_insert_own ON public.wordbook_entries FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY wordbook_entries_select_own ON public.wordbook_entries FOR SELECT TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY wordbook_entries_update_own ON public.wordbook_entries FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.wordbooks ENABLE ROW LEVEL SECURITY;

CREATE POLICY wordbooks_delete_own ON public.wordbooks FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY wordbooks_insert_own ON public.wordbooks FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY wordbooks_select_own ON public.wordbooks FOR SELECT TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY wordbooks_update_own ON public.wordbooks FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.words ENABLE ROW LEVEL SECURITY;

CREATE POLICY words_select_all ON public.words FOR SELECT USING (true);

-- Privileges. The hosted project grants everything on new public objects to anon / authenticated /
-- service_role (pg_default_acl). The migrations narrowed that afterwards, so start from nothing and
-- grant exactly what the replayed migrations ended with.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

REVOKE ALL ON FUNCTION public.apply_main_example_label(p_word_id uuid, p_explain_lang text, p_l1 text, p_sentence text, p_scene text, p_chunks jsonb, p_stale_chunks jsonb, p_drop text[], p_recount boolean, p_translation text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.apply_main_example_label(p_word_id uuid, p_explain_lang text, p_l1 text, p_sentence text, p_scene text, p_chunks jsonb, p_stale_chunks jsonb, p_drop text[], p_recount boolean, p_translation text) TO service_role;

REVOKE ALL ON FUNCTION public.are_mutual_followers(_a uuid, _b uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.are_mutual_followers(_a uuid, _b uuid) TO authenticated;
GRANT ALL ON FUNCTION public.are_mutual_followers(_a uuid, _b uuid) TO service_role;

REVOKE ALL ON FUNCTION public.bump_post_comment_count() FROM PUBLIC;
GRANT ALL ON FUNCTION public.bump_post_comment_count() TO service_role;

REVOKE ALL ON FUNCTION public.bump_post_like_count() FROM PUBLIC;
GRANT ALL ON FUNCTION public.bump_post_like_count() TO service_role;

REVOKE ALL ON FUNCTION public.can_see_post(_post_id uuid, _user uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.can_see_post(_post_id uuid, _user uuid) TO authenticated;
GRANT ALL ON FUNCTION public.can_see_post(_post_id uuid, _user uuid) TO service_role;

REVOKE ALL ON FUNCTION public.create_review_for_new_sticker() FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_review_for_new_sticker() TO service_role;

REVOKE ALL ON FUNCTION public.enforce_words_source() FROM PUBLIC;
GRANT ALL ON FUNCTION public.enforce_words_source() TO service_role;

REVOKE ALL ON FUNCTION public.get_leaderboard(_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_leaderboard(_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.get_leaderboard(_limit integer) TO service_role;

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.profiles TO anon;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;

GRANT SELECT(id) ON TABLE public.profiles TO authenticated;
GRANT SELECT(id) ON TABLE public.profiles TO anon;

GRANT SELECT(display_name),UPDATE(display_name) ON TABLE public.profiles TO authenticated;
GRANT SELECT(display_name) ON TABLE public.profiles TO anon;

GRANT SELECT(avatar_url),UPDATE(avatar_url) ON TABLE public.profiles TO authenticated;
GRANT SELECT(avatar_url) ON TABLE public.profiles TO anon;

GRANT UPDATE(native_language) ON TABLE public.profiles TO authenticated;

GRANT UPDATE(ui_language) ON TABLE public.profiles TO authenticated;

GRANT UPDATE(target_language) ON TABLE public.profiles TO authenticated;

GRANT UPDATE(level_goal) ON TABLE public.profiles TO authenticated;

GRANT UPDATE(pronunciation_strictness) ON TABLE public.profiles TO authenticated;

GRANT SELECT(onboarded),UPDATE(onboarded) ON TABLE public.profiles TO authenticated;

GRANT SELECT(created_at) ON TABLE public.profiles TO authenticated;
GRANT SELECT(created_at) ON TABLE public.profiles TO anon;

GRANT UPDATE(updated_at) ON TABLE public.profiles TO authenticated;

GRANT UPDATE(album_bg) ON TABLE public.profiles TO authenticated;

GRANT UPDATE(review_mode) ON TABLE public.profiles TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_profile() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_profile() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_profile() TO service_role;

GRANT ALL ON FUNCTION public.guard_profile_plan() TO anon;
GRANT ALL ON FUNCTION public.guard_profile_plan() TO authenticated;
GRANT ALL ON FUNCTION public.guard_profile_plan() TO service_role;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;

REVOKE ALL ON FUNCTION public.has_role(_user_id uuid, _role public.app_role) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_role(_user_id uuid, _role public.app_role) TO authenticated;
GRANT ALL ON FUNCTION public.has_role(_user_id uuid, _role public.app_role) TO service_role;

REVOKE ALL ON FUNCTION public.main_example_label_patch(p_extras jsonb, p_sentence text, p_scene text, p_chunks jsonb, p_stale_chunks jsonb, p_drop text[], p_recount boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.main_example_label_patch(p_extras jsonb, p_sentence text, p_scene text, p_chunks jsonb, p_stale_chunks jsonb, p_drop text[], p_recount boolean) TO service_role;

REVOKE ALL ON FUNCTION public.main_example_label_writable(p_extras jsonb, p_sentence text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.main_example_label_writable(p_extras jsonb, p_sentence text) TO service_role;

REVOKE ALL ON FUNCTION public.notify_on_comment() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_on_comment() TO service_role;

REVOKE ALL ON FUNCTION public.notify_on_follow() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_on_follow() TO service_role;

REVOKE ALL ON FUNCTION public.notify_on_like() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_on_like() TO service_role;

REVOKE ALL ON FUNCTION public.preserve_post_counters() FROM PUBLIC;
GRANT ALL ON FUNCTION public.preserve_post_counters() TO service_role;

REVOKE ALL ON FUNCTION public.reserve_usage_event(p_user_id uuid, p_kind text, p_limit integer, p_since timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reserve_usage_event(p_user_id uuid, p_kind text, p_limit integer, p_since timestamp with time zone) TO service_role;

REVOKE ALL ON FUNCTION public.save_album_layout(p_items jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.save_album_layout(p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.save_album_layout(p_items jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_updated_at() TO service_role;

GRANT ALL ON TABLE public.ai_consents TO service_role;
GRANT SELECT ON TABLE public.ai_consents TO authenticated;

GRANT ALL ON TABLE public.ai_runs TO anon;
GRANT ALL ON TABLE public.ai_runs TO authenticated;
GRANT ALL ON TABLE public.ai_runs TO service_role;

GRANT ALL ON TABLE public.app_config TO anon;
GRANT ALL ON TABLE public.app_config TO authenticated;
GRANT ALL ON TABLE public.app_config TO service_role;

GRANT ALL ON TABLE public.apple_tokens TO service_role;

GRANT ALL ON TABLE public.categories TO anon;
GRANT ALL ON TABLE public.categories TO authenticated;
GRANT ALL ON TABLE public.categories TO service_role;

GRANT ALL ON TABLE public.corpus_pairs TO anon;
GRANT ALL ON TABLE public.corpus_pairs TO authenticated;
GRANT ALL ON TABLE public.corpus_pairs TO service_role;

GRANT ALL ON TABLE public.corpus_stats TO anon;
GRANT ALL ON TABLE public.corpus_stats TO authenticated;
GRANT ALL ON TABLE public.corpus_stats TO service_role;

GRANT ALL ON TABLE public.daily_quests TO anon;
GRANT ALL ON TABLE public.daily_quests TO authenticated;
GRANT ALL ON TABLE public.daily_quests TO service_role;

GRANT ALL ON TABLE public.dictionary_entries TO anon;
GRANT ALL ON TABLE public.dictionary_entries TO authenticated;
GRANT ALL ON TABLE public.dictionary_entries TO service_role;

GRANT ALL ON TABLE public.encounters TO anon;
GRANT ALL ON TABLE public.encounters TO authenticated;
GRANT ALL ON TABLE public.encounters TO service_role;

GRANT ALL ON TABLE public.entry_reports TO anon;
GRANT ALL ON TABLE public.entry_reports TO authenticated;
GRANT ALL ON TABLE public.entry_reports TO service_role;

GRANT ALL ON TABLE public.follows TO anon;
GRANT ALL ON TABLE public.follows TO authenticated;
GRANT ALL ON TABLE public.follows TO service_role;

GRANT ALL ON TABLE public.generated_cards TO service_role;

GRANT ALL ON TABLE public.journal_entries TO anon;
GRANT ALL ON TABLE public.journal_entries TO authenticated;
GRANT ALL ON TABLE public.journal_entries TO service_role;

GRANT ALL ON TABLE public.lexicon_audits TO anon;
GRANT ALL ON TABLE public.lexicon_audits TO authenticated;
GRANT ALL ON TABLE public.lexicon_audits TO service_role;

GRANT ALL ON TABLE public.model_shadow_predictions TO anon;
GRANT ALL ON TABLE public.model_shadow_predictions TO authenticated;
GRANT ALL ON TABLE public.model_shadow_predictions TO service_role;

GRANT ALL ON SEQUENCE public.model_shadow_predictions_id_seq TO anon;
GRANT ALL ON SEQUENCE public.model_shadow_predictions_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.model_shadow_predictions_id_seq TO service_role;

GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;

GRANT ALL ON TABLE public.post_comments TO anon;
GRANT ALL ON TABLE public.post_comments TO authenticated;
GRANT ALL ON TABLE public.post_comments TO service_role;

GRANT ALL ON TABLE public.post_likes TO anon;
GRANT ALL ON TABLE public.post_likes TO authenticated;
GRANT ALL ON TABLE public.post_likes TO service_role;

GRANT ALL ON TABLE public.posts TO anon;
GRANT ALL ON TABLE public.posts TO authenticated;
GRANT ALL ON TABLE public.posts TO service_role;

GRANT REFERENCES,TRIGGER ON TABLE public.review_choices TO anon;
GRANT SELECT,REFERENCES,TRIGGER ON TABLE public.review_choices TO authenticated;
GRANT ALL ON TABLE public.review_choices TO service_role;

GRANT ALL ON TABLE public.review_history TO anon;
GRANT ALL ON TABLE public.review_history TO authenticated;
GRANT ALL ON TABLE public.review_history TO service_role;

GRANT ALL ON TABLE public.reviews TO anon;
GRANT ALL ON TABLE public.reviews TO authenticated;
GRANT ALL ON TABLE public.reviews TO service_role;

GRANT ALL ON TABLE public.scan_events TO anon;
GRANT ALL ON TABLE public.scan_events TO authenticated;
GRANT ALL ON TABLE public.scan_events TO service_role;

GRANT ALL ON TABLE public.self_improve_runs TO anon;
GRANT ALL ON TABLE public.self_improve_runs TO authenticated;
GRANT ALL ON TABLE public.self_improve_runs TO service_role;

GRANT ALL ON TABLE public.stickers TO anon;
GRANT ALL ON TABLE public.stickers TO authenticated;
GRANT ALL ON TABLE public.stickers TO service_role;

GRANT ALL ON TABLE public.usage_events TO anon;
GRANT ALL ON TABLE public.usage_events TO authenticated;
GRANT ALL ON TABLE public.usage_events TO service_role;

GRANT ALL ON SEQUENCE public.usage_events_id_seq TO anon;
GRANT ALL ON SEQUENCE public.usage_events_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.usage_events_id_seq TO service_role;

GRANT ALL ON TABLE public.user_roles TO anon;
GRANT ALL ON TABLE public.user_roles TO authenticated;
GRANT ALL ON TABLE public.user_roles TO service_role;

GRANT ALL ON TABLE public.user_shelves TO anon;
GRANT ALL ON TABLE public.user_shelves TO authenticated;
GRANT ALL ON TABLE public.user_shelves TO service_role;

GRANT REFERENCES,TRIGGER ON TABLE public.word_explanations TO anon;
GRANT SELECT,REFERENCES,TRIGGER ON TABLE public.word_explanations TO authenticated;
GRANT ALL ON TABLE public.word_explanations TO service_role;

GRANT ALL ON TABLE public.wordbook_entries TO anon;
GRANT ALL ON TABLE public.wordbook_entries TO authenticated;
GRANT ALL ON TABLE public.wordbook_entries TO service_role;

GRANT ALL ON TABLE public.wordbooks TO anon;
GRANT ALL ON TABLE public.wordbooks TO authenticated;
GRANT ALL ON TABLE public.wordbooks TO service_role;

GRANT SELECT,REFERENCES,TRIGGER ON TABLE public.words TO anon;
GRANT SELECT,REFERENCES,TRIGGER ON TABLE public.words TO authenticated;
GRANT ALL ON TABLE public.words TO service_role;




-- Storage buckets, as configured on the Lovable Cloud project (2026-10-20).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('stickers', 'stickers', false, NULL, NULL),
  ('tts', 'tts', false, NULL, NULL),
  ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']);

-- Storage policies and the auth.users trigger (outside the public schema, so not in the dump above).
CREATE POLICY avatars_delete_own ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_insert_own ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_update_own ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY stickers_read_visible ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'stickers'::text) AND ((storage.foldername(name))[1] IS NOT NULL) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR (EXISTS ( SELECT 1
   FROM (public.stickers s
     JOIN public.posts p ON ((p.sticker_id = s.id)))
  WHERE (((s.cutout_image_url = objects.name) OR (s.object_image_url = objects.name)) AND ((storage.foldername(objects.name))[1] = (s.user_id)::text) AND ((storage.foldername(objects.name))[1] = (p.user_id)::text) AND ((p.visibility = 'public'::text) OR ((p.visibility = 'friends'::text) AND public.are_mutual_followers(auth.uid(), p.user_id)) OR (p.user_id = auth.uid()))))))));
CREATE POLICY stickers_storage_delete_own ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'stickers'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY stickers_storage_insert_own ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'stickers'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY stickers_storage_read_own ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'stickers'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY stickers_storage_update_own ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'stickers'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY tts_read_authenticated ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING ((bucket_id = 'tts'::text));
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


