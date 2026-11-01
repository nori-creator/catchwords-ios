-- 撮った場所を学習者が直す（オーナー指示 2026-10-31「ユーザーが場所を直す機能もつけて。地図上で指定できるまたは
-- 場所の名前を変更できるように」）。location_custom = 学習者が書いた・選んだ名前（端末は座標から引き直さず、
-- location_name をそのまま出す）。点と名前は今ある lat / lng / location_name に書く（setCapturePlace）。
alter table public.stickers add column if not exists location_custom boolean not null default false;
alter table public.encounters add column if not exists location_custom boolean not null default false;
