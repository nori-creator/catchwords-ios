-- Who shares a word's example sentences and chunks (owner, 2026-10-25; docs/sharing-rules.md S1–S8).
--
-- - Readers of the same display language share every section of a word. Example sentences and chunks are
--   shared only when the current-level band and the goal band are both the same (TOCFL 1–2 = A, 3–4 = B,
--   5–6 = C). Readers of another display language share nothing.
-- - `word_level_content` holds the example sentences and chunks, keyed (word, display language, native
--   language, band). Every other section stays in `word_explanations`.
-- - `stickers.level_band` is the band a word was saved with ("A>B"). Saved words keep it when the level is
--   changed later. Every sticker that exists now is marked 'legacy': it keeps reading its examples and chunks
--   as before (saved words are never remade by themselves — owner decision 2026-10-23).
--
-- Additive only. The server function that reads these must tolerate their absence (it then treats everyone
-- as 'legacy'), so the function can be deployed first and this applied after it.

CREATE TABLE IF NOT EXISTS public.word_level_content (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    word_id uuid NOT NULL REFERENCES public.words(id) ON DELETE CASCADE,
    explain_lang text NOT NULL,
    l1 text NOT NULL,
    level_band text NOT NULL,
    example_sentence text,
    example_translation text,
    extras jsonb DEFAULT '{}'::jsonb NOT NULL,
    source text DEFAULT 'ai'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT word_level_content_key UNIQUE (word_id, explain_lang, l1, level_band),
    CONSTRAINT word_level_content_band_check CHECK (level_band ~ '^[A-C]>[A-C]$'),
    CONSTRAINT word_level_content_source_check CHECK (source = ANY (ARRAY['seed'::text, 'verified'::text, 'ai'::text]))
);

ALTER TABLE public.word_level_content ENABLE ROW LEVEL SECURITY;

-- Same as word_explanations: readable by signed-in users, written only by the server (service role).
DROP POLICY IF EXISTS word_level_content_no_client_write ON public.word_level_content;
CREATE POLICY word_level_content_no_client_write ON public.word_level_content TO authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS word_level_content_select_all ON public.word_level_content;
CREATE POLICY word_level_content_select_all ON public.word_level_content FOR SELECT TO authenticated USING (true);

REVOKE ALL ON TABLE public.word_level_content FROM anon;
REVOKE ALL ON TABLE public.word_level_content FROM authenticated;
GRANT SELECT ON TABLE public.word_level_content TO authenticated;
GRANT ALL ON TABLE public.word_level_content TO service_role;

ALTER TABLE public.stickers ADD COLUMN IF NOT EXISTS level_band text;
-- Everything saved before this rule keeps its old examples and chunks.
UPDATE public.stickers SET level_band = 'legacy' WHERE level_band IS NULL;
ALTER TABLE public.stickers DROP CONSTRAINT IF EXISTS stickers_level_band_check;
ALTER TABLE public.stickers ADD CONSTRAINT stickers_level_band_check
    CHECK (level_band IS NULL OR level_band = 'legacy' OR level_band ~ '^[A-C]>[A-C]$');
