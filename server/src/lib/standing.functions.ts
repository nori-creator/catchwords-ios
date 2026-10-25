import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import { readAllPages } from "./pagination";
import { taipeiDay } from "./taipei-day";
import { countByUser, distinctDaysByUser, standingOf, type Standing } from "./standing";

/**
 * **全利用者の中での自分の位置**（iOS の「ほめる演出」。オーナー指示 2026-10-25）。
 *
 * iOS は語を集めた後、ほめる回（数回に1回より少ない。iOS の `PraiseSchedule`）にだけこれを呼ぶ。
 * 毎回は呼ばない（全員の札を読むので、撮るたびに呼ぶと重い）。
 *
 * 返すのは**自分の数と順位だけ**。ほかの人の id・名前・語・写真は返さない（数を数えるのに使うだけ）。
 * 全員の行を読むので、本人確認の後で service role の接続を使う（`admin-users.functions.ts` と同じ読み方）。
 *
 * - `words`: 集めた語の数（札の数）の順位
 * - `activeDays`: 使った日（撮った日か復習した日。台湾の暦日）の数の順位 — 「続けている」ことの順位
 * - `category`: 今集めた語と同じ分類（`category_key`）の語の数の順位（例: 食べ物）
 * - `firstCatcher`: 今集めた語を、自分より前に集めた人がいない（全利用者の中で最初）
 */

const Input = z.object({
  /** 今集めた語（`words.id`）。最初に集めた人か・同じ分類の順位を見る。 */
  word_id: z.string().uuid().optional(),
  language: z.string().default(DEFAULT_TARGET_LANGUAGE),
});

export type MyStanding = {
  words: (Standing & { count: number }) | null;
  activeDays: (Standing & { count: number }) | null;
  category: (Standing & { count: number; key: string }) | null;
  firstCatcher: boolean;
};

const READ = { maxRows: 1_000_000 };

export const getMyStanding = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => Input.parse(input ?? {}))
  .handler(async ({ context, data }): Promise<MyStanding> => {
    const { userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;

    // 今の語の分類（無ければ分類の順位は出さない）。
    let categoryKey: string | null = null;
    if (data.word_id) {
      const { data: w } = await db
        .from("words")
        .select("category_key")
        .eq("id", data.word_id)
        .maybeSingle();
      categoryKey = (w?.category_key as string | null) ?? null;
    }

    const [stickers, reviewed] = await Promise.all([
      readAllPages<{
        user_id: string;
        word_id: string;
        created_at: string;
        words: { category_key: string | null } | null;
      }>(
        (a, b) =>
          db
            .from("stickers")
            .select("user_id, word_id, created_at, words(category_key)")
            .eq("language", data.language)
            .order("id")
            .range(a, b),
        READ,
      ),
      readAllPages<{ user_id: string; reviewed_at: string }>(
        (a, b) => db.from("review_history").select("user_id, reviewed_at").order("id").range(a, b),
        READ,
      ),
    ]);
    if (stickers.truncated || reviewed.truncated) {
      console.warn("[getMyStanding] read was cut short; the ranks are approximate");
    }

    const wordCounts = countByUser(stickers.rows);
    const myWords = wordCounts.get(userId) ?? 0;

    const days = distinctDaysByUser([
      ...stickers.rows.map((s) => ({ user_id: s.user_id, day: taipeiDay(s.created_at) })),
      ...reviewed.rows.map((r) => ({ user_id: r.user_id, day: taipeiDay(r.reviewed_at) })),
    ]);
    const myDays = days.get(userId) ?? 0;

    let category: MyStanding["category"] = null;
    if (categoryKey) {
      const inCategory = countByUser(
        stickers.rows.filter((s) => s.words?.category_key === categoryKey),
      );
      const mine = inCategory.get(userId) ?? 0;
      const s = standingOf(mine, inCategory, userId);
      if (s) category = { ...s, count: mine, key: categoryKey };
    }

    // 最初に集めた人: 自分の最初の札より前に、ほかの誰もその語を集めていない。
    let firstCatcher = false;
    if (data.word_id) {
      const same = stickers.rows.filter((s) => s.word_id === data.word_id);
      const mineFirst = same
        .filter((s) => s.user_id === userId)
        .reduce<string | null>((m, s) => (m == null || s.created_at < m ? s.created_at : m), null);
      if (mineFirst != null) {
        firstCatcher = !same.some((s) => s.user_id !== userId && s.created_at < mineFirst);
      }
    }

    const ws = standingOf(myWords, wordCounts, userId);
    const ds = standingOf(myDays, days, userId);
    return {
      words: ws ? { ...ws, count: myWords } : null,
      activeDays: ds ? { ...ds, count: myDays } : null,
      category,
      firstCatcher,
    };
  });
