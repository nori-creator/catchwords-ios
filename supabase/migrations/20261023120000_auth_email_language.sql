-- The auth emails (sign-up confirmation, password reset, email change) are written in the learner's display
-- language (owner, 2026-10-23: "A" — never mix languages). Supabase's email templates can read only the
-- account's user_metadata (`{{ .Data.ui_language }}`), so the profile's display language is copied there.
--
-- - A new account takes `ui_language` from the sign-up request's metadata when the app sent one (the
--   confirmation email goes out before the profile exists), else the column default.
-- - Every later change of `profiles.ui_language` is copied to `auth.users.raw_user_meta_data.ui_language`.
-- - Existing accounts are filled once below.
-- user_metadata is editable by its user; here it only picks the email's language, never access.

CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url, ui_language)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.raw_user_meta_data->>'avatar_url',
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'ui_language', ''), 'ja')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.sync_ui_language_to_auth() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  UPDATE auth.users
     SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                              || jsonb_build_object('ui_language', NEW.ui_language)
   WHERE id = NEW.id
     AND raw_user_meta_data->>'ui_language' IS DISTINCT FROM NEW.ui_language;
  RETURN NEW;
END; $$;

REVOKE ALL ON FUNCTION public.sync_ui_language_to_auth() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER profiles_sync_ui_language
  AFTER INSERT OR UPDATE OF ui_language ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.sync_ui_language_to_auth();

UPDATE auth.users u
   SET raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb)
                            || jsonb_build_object('ui_language', p.ui_language)
  FROM public.profiles p
 WHERE p.id = u.id
   AND u.raw_user_meta_data->>'ui_language' IS DISTINCT FROM p.ui_language;
