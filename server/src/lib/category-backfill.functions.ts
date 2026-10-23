import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { isAiCapError } from "./ai-cap";
import { isAiConsentError } from "./ai-consent";
import {
  RECLASSIFY_BATCH,
  ReclassifySchema,
  isUnclassifiedKey,
  planCategoryUpdates,
  reclassifyPrompt,
  ruleCategoryUpdates,
  type BackfillWordRow,
  type ReclassifyAnswer,
} from "./category-backfill";
import type { CategoryKey } from "./category";

/**
 * **「その他」のまま保存された語を、一度だけ分け直す**（決まりは `category-backfill.ts`）。
 *
 * 呼ぶ道（図鑑を開いた時、裏で1度だけ。`use-category-backfill.ts`）:
 * 1. 同意（`assertAiConsent`）— 無ければ何も送らずに `skipped: "consent"`（「その他」のまま）
 * 2. その人が札を持っている語だけ（他の人の語を勝手に分けさせない）
 * 3. 共有の語の今の鍵が other か空の語だけ（ほかの値は読んだ時点で外す）
 * 4. 見出し語の規則で分かる語は AI を呼ばずに書く
 * 5. 残りがあれば回数の枠（`category_fix`）を取って、速いモデルに一覧の鍵から選ばせる
 * 6. 書く時も「今が other か空なら」を条件にする（読んだ後に誰かが分けた語を上書きしない）
 *
 * `words` はブラウザから書けない共有の表（20261001100000_words_server_only_update.sql）なので、
 * カードの生成（`fillSharedWordFromCard`）と同じく service role で書く。`stickers.shelf_key`
 * （その人が選んだ棚）には触らない。
 */
export type ReclassifyResult = {
  updated: Array<{ id: string; category_key: CategoryKey }>;
  /** AI に聞いた語の数（費用の目安）。 */
  asked: number;
  skipped?: "consent" | "cap" | "none" | "ai";
};

export type ReclassifyDeps = {
  assertConsent: () => Promise<void>;
  reserveCap: () => Promise<void>;
  /** その人が札を持っている語の id（`wordIds` の中だけ）。 */
  ownedWordIds: (ids: string[]) => Promise<string[]>;
  readWords: (ids: string[]) => Promise<BackfillWordRow[]>;
  classify: (prompt: string) => Promise<ReclassifyAnswer>;
  /** 今が other か空の時だけ書く。書けたら true。 */
  writeIfUnclassified: (id: string, key: CategoryKey) => Promise<boolean>;
};

export async function reclassifyOtherWordsWith(
  deps: ReclassifyDeps,
  wordIds: readonly string[],
): Promise<ReclassifyResult> {
  const ids = [...new Set(wordIds)].slice(0, RECLASSIFY_BATCH);
  if (ids.length === 0) return { updated: [], asked: 0, skipped: "none" };
  try {
    await deps.assertConsent();
  } catch (e) {
    if (isAiConsentError(e)) return { updated: [], asked: 0, skipped: "consent" };
    throw e;
  }
  const owned = new Set(await deps.ownedWordIds(ids));
  const rows = (await deps.readWords(ids.filter((id) => owned.has(id)))).filter((r) =>
    isUnclassifiedKey(r.category_key),
  );
  if (rows.length === 0) return { updated: [], asked: 0, skipped: "none" };

  const updated: ReclassifyResult["updated"] = [];
  const write = async (plan: Array<{ id: string; category_key: CategoryKey }>) => {
    for (const u of plan) if (await deps.writeIfUnclassified(u.id, u.category_key)) updated.push(u);
  };

  const byRule = ruleCategoryUpdates(rows);
  await write(byRule);
  const ruled = new Set(byRule.map((u) => u.id));
  const rest = rows.filter((r) => !ruled.has(r.id));
  if (rest.length === 0) return { updated, asked: 0 };

  try {
    await deps.reserveCap();
  } catch (e) {
    if (isAiCapError(e)) return { updated, asked: 0, skipped: "cap" };
    throw e;
  }
  let answer: ReclassifyAnswer;
  try {
    answer = await deps.classify(
      reclassifyPrompt(
        rest.map((r, i) => ({
          i,
          headword: r.headword.slice(0, 40),
          meaning: (r.meaning_ja ?? "").slice(0, 80),
        })),
      ),
    );
  } catch (e) {
    // 分け直しはおまけ。失敗しても図鑑は「その他」のまま出る。
    console.warn("[category-backfill] AI の答えが読めない", e instanceof Error ? e.message : e);
    return { updated, asked: rest.length, skipped: "ai" };
  }
  await write(planCategoryUpdates(rest, answer));
  return { updated, asked: rest.length };
}

type LooseError = { message?: string } | null;

export const reclassifyOtherWords = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z.object({ wordIds: z.array(z.string().uuid()).min(1).max(RECLASSIFY_BATCH) }).parse(input),
  )
  .handler(async ({ data, context }): Promise<ReclassifyResult> => {
    const { supabase, userId } = context;
    return reclassifyOtherWordsWith(
      {
        // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らない。
        assertConsent: async () =>
          (await import("./ai-consent.server")).assertAiConsent(context.userId),
        reserveCap: async () =>
          (await import("./ai-provider.server")).assertWithinDailyCap(userId, "category_fix"),
        ownedWordIds: async (ids) => {
          const { data: rows, error } = (await supabase
            .from("stickers")
            .select("word_id")
            .eq("user_id", userId)
            .in("word_id", ids)) as {
            data: Array<{ word_id: string }> | null;
            error: LooseError;
          };
          if (error) throw new Error(error.message ?? "stickers");
          return (rows ?? []).map((r) => r.word_id);
        },
        readWords: async (ids) => {
          if (ids.length === 0) return [];
          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
          const { data: rows, error } = await supabaseAdmin
            .from("words")
            .select("id, headword, meaning_ja, category_key")
            .in("id", ids);
          if (error) throw new Error(error.message);
          return (rows ?? []) as BackfillWordRow[];
        },
        classify: async (prompt) => {
          const { getAiFor, generateStructured } = await import("./ai-provider.server");
          const ai = await getAiFor("lexicon", "category_backfill");
          return generateStructured({
            model: ai.gateway(ai.modelFast),
            prompt,
            schema: ReclassifySchema,
          });
        },
        writeIfUnclassified: async (id, key) => {
          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
          const { data: rows, error } = await supabaseAdmin
            .from("words")
            .update({ category_key: key })
            .eq("id", id)
            .or("category_key.is.null,category_key.eq.other")
            .select("id");
          if (error) {
            console.warn("[category-backfill] 書けない", error.message);
            return false;
          }
          return (rows ?? []).length > 0;
        },
      },
      data.wordIds,
    );
  });
