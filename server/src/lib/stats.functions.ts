import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { countStreak } from "@/lib/streak";
import { dueNowOrFilter } from "@/lib/srs";
import { taipeiDay } from "./taipei-day";
import { readAllPages } from "./pagination";

export type UserStats = {
  xp: number;
  level: number;
  /**
   * **撮った**日が何日続いているか。
   * 以前はこれを単に `streak` と呼んでいたが、要望の「連続何日」は
   * **復習**のほうを指していた。名前で取り違えるので、両方を別の欄で持つ。
   */
  capture_streak: number;
  /** **復習した**日が何日続いているか(`review_history` を数える)。 */
  review_streak: number;
  captured_total: number;
  reviews_due: number;
  reviews_done_today: number;
};

function taipeiDateString(d: Date): string {
  return taipeiDay(d);
}

export const getMyStats = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<UserStats> => {
    const { supabase, userId } = context;
    const nowIso = new Date().toISOString();

    // **PostgREST は1回に1000行で切る**（2026-10-03 監査）。札・復習済みの札は上限なしで
    // 読んでいたので 1000 枚で黙って止まり、撮った数と XP が少なく出ていた。記録は
    // `.limit(3000)` でも 1000 行しか来ず、連続日数が途中で切れていた。全部
    // `readAllPages` で 1000 行ずつ読む（並びは id で決める。順番は数えるのに使わない）。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabase as any;
    const [stickersRes, reviewsDueRes, reviewsAllRes, questsRes, historyRes] = await Promise.all([
      readAllPages<{ id: string; created_at: string }>((a, b) =>
        db
          .from("stickers")
          .select("id, created_at")
          .eq("user_id", userId)
          .order("created_at", { ascending: false })
          .order("id")
          .range(a, b),
      ),
      supabase
        .from("reviews")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        // 期限は「最後の復習 + 180 日」で頭打ち（`dueNowOrFilter`）。
        .or(dueNowOrFilter(Date.parse(nowIso))),
      readAllPages<{ id: string; last_score: number | null; last_reviewed_at: string | null }>(
        (a, b) =>
          db
            .from("reviews")
            .select("id, last_score, last_reviewed_at")
            .eq("user_id", userId)
            .not("last_reviewed_at", "is", null)
            .order("id")
            .range(a, b),
      ),
      supabase
        .from("daily_quests")
        .select("reward_xp, completed_at")
        .eq("user_id", userId)
        .not("completed_at", "is", null),
      // **復習の連続と「今日やった数」はここだけを見る。**
      // `reviews.last_reviewed_at` は1枚につき1行しか持たないので、
      // 同じ日に2回やっても1回に潰れる。1日の上限
      // (`reviews.functions.ts`)は `review_history` を数えているので、
      // 別の出所で数えると**同じ「今日の復習」が画面と上限で食い違う**。
      readAllPages<{ reviewed_at: string }>((a, b) =>
        db
          .from("review_history")
          .select("reviewed_at")
          .eq("user_id", userId)
          .order("reviewed_at", { ascending: false })
          .order("id")
          .range(a, b),
      ),
    ]);

    const stickers = stickersRes.rows;
    const reviewsAll = reviewsAllRes.rows;
    const quests = questsRes.data ?? [];

    // **先に台北の暦日へ落としてから数える。** 日にちの計算に時差を
    // 持ち込まないための決まりごと(`lib/streak.ts` に理由)。
    const today = taipeiDateString(new Date());
    const history = historyRes.rows;
    const captureStreak = countStreak(
      stickers.map((s) => taipeiDateString(new Date(s.created_at))),
      today,
    );
    const reviewStreak = countStreak(
      history.map((h) => taipeiDateString(new Date(h.reviewed_at))),
      today,
    );
    const reviewsDoneToday = history.filter(
      (h) => taipeiDateString(new Date(h.reviewed_at)) === today,
    ).length;

    const xpFromStickers = stickers.length * 10;
    const xpFromReviews = reviewsAll.reduce((sum, r) => sum + (r.last_score ?? 0) * 2, 0);
    const xpFromQuests = quests.reduce((sum, q) => sum + (q.reward_xp ?? 0), 0);
    const xp = xpFromStickers + xpFromReviews + xpFromQuests;
    const level = Math.max(1, Math.floor(Math.sqrt(xp / 50)) + 1);

    return {
      xp,
      level,
      capture_streak: captureStreak,
      review_streak: reviewStreak,
      captured_total: stickers.length,
      reviews_due: reviewsDueRes.count ?? 0,
      reviews_done_today: reviewsDoneToday,
    };
  });
