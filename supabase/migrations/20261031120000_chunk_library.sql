-- 使い方チャンク v2 の書庫（owner 2026-10-30: チャンクを一から設計し直す。docs/chunk-rules.md の v2 の節）。
--
-- - `chunk_library`: 見出し語ごとの、2 社の AI が一致した（または片方が書き、もう片方が審査に通した）塊。
--   中国語の部分（塊・文・入れ替えの候補）は**表示言語をまたいで共有**する（owner 2026-10-30「中国語の部分は使い回してよい」—
--   10-25 の「表示言語が異なる場合は全く共有しない」の例外）。訳・解説は `chunk_library_text` に表示言語ごと。
-- - `chunk_runs`: 見出し語ごとの作った記録（進行中 / 済 / 失敗）。同じ語を同時に 2 人が撮っても、作るのは 1 回。
--
-- 追加だけ。サーバの関数はこれらが無くても落ちない（表が無ければ書庫なしで作って返す）。
-- 読むのは signed-in の利用者、書くのはサーバ（service_role）だけ — word_level_content と同じ。

CREATE TABLE IF NOT EXISTS public.chunk_library (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    language text NOT NULL,
    headword text NOT NULL,
    -- 塊の字（block をつないだ物）。
    zh text NOT NULL,
    -- 入れ替えの所を ＿ にした型の字（2 社の返事を比べた鍵）。
    frame text NOT NULL,
    -- 中国語の block: [{text, pos, slot, alts:[{text}], pinyin, zhuyin}]（訳は持たない）。
    blocks jsonb DEFAULT '[]'::jsonb NOT NULL,
    -- 見出し語の場所 {block, start, length}。
    head jsonb,
    pattern text DEFAULT ''::text NOT NULL,
    -- その塊を切り出した文（例文として出す）。
    sentence text DEFAULT ''::text NOT NULL,
    -- 並び（0 から）。
    rank integer DEFAULT 0 NOT NULL,
    -- 審査の頻度 1〜5（一致で決まった物は null のことがある）。
    frequency integer,
    -- どう決まったか: agreement（2 社の一致）/ judge（片方が書き、もう片方が合格）。
    decided_by text,
    status text DEFAULT 'approved'::text NOT NULL,
    source text DEFAULT 'ai'::text NOT NULL,
    -- 書いた会社（例 "google+anthropic"）。
    providers text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chunk_library_key UNIQUE (language, headword, zh),
    CONSTRAINT chunk_library_status_check CHECK (status = ANY (ARRAY['approved'::text, 'rejected'::text])),
    CONSTRAINT chunk_library_frequency_check CHECK (frequency IS NULL OR (frequency >= 1 AND frequency <= 5))
);

CREATE INDEX IF NOT EXISTS chunk_library_word_idx ON public.chunk_library USING btree (language, headword, status, rank);

CREATE TABLE IF NOT EXISTS public.chunk_library_text (
    library_id uuid NOT NULL REFERENCES public.chunk_library(id) ON DELETE CASCADE,
    explain_lang text NOT NULL,
    -- 塊の訳・文の訳・ひと言解説（その表示言語）。
    ja text DEFAULT ''::text NOT NULL,
    sentence_ja text DEFAULT ''::text NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    -- block ごとの意味: [{ja, alts_ja:[...]}]（blocks と同じ並び。入れ替えの所だけ中身がある）。
    blocks_ja jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chunk_library_text_key UNIQUE (library_id, explain_lang)
);

CREATE TABLE IF NOT EXISTS public.chunk_runs (
    language text NOT NULL,
    headword text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    providers text,
    approved integer DEFAULT 0 NOT NULL,
    error text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    CONSTRAINT chunk_runs_key UNIQUE (language, headword),
    CONSTRAINT chunk_runs_status_check CHECK (status = ANY (ARRAY['pending'::text, 'done'::text, 'failed'::text]))
);

ALTER TABLE public.chunk_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chunk_library_text ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chunk_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chunk_library_no_client_write ON public.chunk_library;
CREATE POLICY chunk_library_no_client_write ON public.chunk_library TO authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS chunk_library_select_all ON public.chunk_library;
CREATE POLICY chunk_library_select_all ON public.chunk_library FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS chunk_library_text_no_client_write ON public.chunk_library_text;
CREATE POLICY chunk_library_text_no_client_write ON public.chunk_library_text TO authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS chunk_library_text_select_all ON public.chunk_library_text;
CREATE POLICY chunk_library_text_select_all ON public.chunk_library_text FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS chunk_runs_no_client ON public.chunk_runs;
CREATE POLICY chunk_runs_no_client ON public.chunk_runs TO authenticated USING (false) WITH CHECK (false);

REVOKE ALL ON TABLE public.chunk_library FROM anon;
REVOKE ALL ON TABLE public.chunk_library FROM authenticated;
GRANT SELECT ON TABLE public.chunk_library TO authenticated;
GRANT ALL ON TABLE public.chunk_library TO service_role;

REVOKE ALL ON TABLE public.chunk_library_text FROM anon;
REVOKE ALL ON TABLE public.chunk_library_text FROM authenticated;
GRANT SELECT ON TABLE public.chunk_library_text TO authenticated;
GRANT ALL ON TABLE public.chunk_library_text TO service_role;

REVOKE ALL ON TABLE public.chunk_runs FROM anon;
REVOKE ALL ON TABLE public.chunk_runs FROM authenticated;
GRANT ALL ON TABLE public.chunk_runs TO service_role;
