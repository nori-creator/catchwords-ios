-- 2026-11-03 点検 S8: 共有の辞書（words）がログインなしで誰でも読めた（ポリシーにロールの指定が無く、anon に SELECT）。
-- アプリはログインしてからしか語を読まない（ログインの前の画面の見本は同梱の物）。読むのはログインした人だけにする。
DROP POLICY IF EXISTS words_select_all ON public.words;
DROP POLICY IF EXISTS words_select_signed_in ON public.words;
CREATE POLICY words_select_signed_in ON public.words FOR SELECT TO authenticated USING (true);
REVOKE SELECT ON TABLE public.words FROM anon;
