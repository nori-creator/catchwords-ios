-- 2026-11-03 点検 S18: 連鎖削除（ON DELETE CASCADE）の外部キーに索引が無く、単語の削除・退会が表全体を読んでいた。
-- 手元で 1,000 人 × 1,000 語（復習 100 万行・履歴 300 万行）では、1 人分の退会が 276 秒（索引を足すと 0.05 秒未満）。
-- reviews.sticker_id → stickers（ON DELETE CASCADE）。reviews の一意の鍵 (user_id, sticker_id) は sticker_id から引けない。
create index if not exists reviews_sticker_id_idx on public.reviews using btree (sticker_id);
-- review_history.review_id → reviews（ON DELETE CASCADE）。
create index if not exists review_history_review_id_idx on public.review_history using btree (review_id);
