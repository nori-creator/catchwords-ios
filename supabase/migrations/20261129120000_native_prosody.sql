-- 発音コーチの「ネイティブの範囲」（2026-11-29、オーナー「本物の発音から分析して、この範囲で高さ・長さ・強さなどの
-- 要素で総合的に判定したい」）。設計は docs/pronunciation-coach.md、約束は server/src/lib/pronunciation.ts。
--
-- 台湾の人（オーナーの彼女・友達）が開発者の端末の「ネイティブの発音を録音」で読んだ単語の、端末が分析した数値と音声。
-- - 数値（take: 音節ごとの高さ・長さ・強さ、range: その人の声の範囲）は学習者のアプリが getNativeProsody で読む。
--   返すのは数値と話者の記号だけ（名前・連絡先は置かない。誰が録ったか・音声は返さない）。
-- - 音声（native-audio バケット、非公開）は、分析の手順を良くした時に測り直すためだけに置く。
-- - 読み書きはサーバの鍵（service role）だけ。利用者からは見えない・書けない（方針を置かない）。
-- - consent_at: 話者が「発音の手本を作るために声を保存する」ことに同意した時（同意なしでは保存しない）。

create table if not exists public.native_prosody (
  id uuid primary key default gen_random_uuid(),
  speaker text not null check (speaker ~ '^[A-Za-z0-9_-]{1,16}$'),
  gender text not null default 'unknown' check (gender in ('female', 'male', 'other', 'unknown')),
  headword text not null,
  zhuyin text,
  pattern text check (pattern is null or pattern ~ '^[1-5](-[1-5]){0,7}$'),
  syllables int not null check (syllables between 1 and 8),
  range_low double precision not null,
  range_high double precision not null,
  take jsonb not null,
  audio_path text,
  consent_at timestamptz not null,
  recorded_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists native_prosody_headword on public.native_prosody (headword, syllables);
create index if not exists native_prosody_pattern on public.native_prosody (pattern, syllables);

alter table public.native_prosody enable row level security;
revoke all on public.native_prosody from anon, authenticated;

insert into storage.buckets (id, name, public)
values ('native-audio', 'native-audio', false)
on conflict (id) do nothing;
