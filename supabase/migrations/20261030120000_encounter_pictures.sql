-- A word photographed again (an `encounters` row with its own photo) gets the same picture tools as the first
-- photo on the word page (owner, 2026-10-30: 「2回目3回目だと、元の画像・自撮り・画像の変更・切り抜き・表示する写真の
-- 種類・撮り直しが無いから足して」).
--
-- - `selfie_path`: a selfie taken later for that photo (as `stickers.selfie_image_url`).
-- - `hero_role`: which picture shows that photo — 'object' | 'cutout' | 'selfie' | null (as `stickers.hero_role`).
-- - Its owner may update the row (replace the photo, add the cut-out or the selfie, pick the picture). Until now
--   the rows could only be inserted and read.
--
-- Additive only. The server function `editEncounter` reports `saved: false` while the columns are missing, and the
-- app reads the rows without them, so the function and the app can ship before this is applied.

ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS selfie_path text;
ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS hero_role text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'encounters_hero_role_check') THEN
    ALTER TABLE public.encounters
      ADD CONSTRAINT encounters_hero_role_check CHECK (hero_role IS NULL OR hero_role = ANY (ARRAY['object'::text, 'cutout'::text, 'selfie'::text]));
  END IF;
END $$;

DROP POLICY IF EXISTS encounters_update_own ON public.encounters;
CREATE POLICY encounters_update_own ON public.encounters FOR UPDATE TO authenticated
  USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
