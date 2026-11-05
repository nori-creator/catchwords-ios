-- 開発者の「分析」（2026-11-05、オーナー決定 C・D）。
--
-- 1) analytics_exclusions: 開発者が「この人を数えない」にした人（試験用の自分の別アカウントなど）。
--    読み書きはサーバの鍵（service role）だけ。利用者からは見えない・書けない（方針を置かない）。
-- 2) usage_events.meta: アプリが送る記録に添える小さな情報（1.0.5 から）。中身はサーバが決めた
--    鍵だけ（アプリの版・機種の種類・iOS の版・表示言語・画面の名前・段の名前・数）。
--    写真・単語・答え・場所・広告の識別子は入れない（`metrics.functions.ts` の AppEventMeta）。

create table if not exists public.analytics_exclusions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  reason text not null default 'admin',
  created_at timestamptz not null default now()
);
alter table public.analytics_exclusions enable row level security;
revoke all on public.analytics_exclusions from anon, authenticated;

alter table public.usage_events add column if not exists meta jsonb;
