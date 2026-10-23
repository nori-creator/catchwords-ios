import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { askJev, jevAvailable } from "./jev.server";
import { candidateQuestion, doubtfulTaiwanTerms, rankByWanted } from "./jev-tasks";

/**
 * スキャンで見つかった候補を「いちばん調べたい見込み」の高い順に並べる。
 *
 * （オーナー指示 2026-09-22「typesafe の JEV はユーザーが撮影した時に単語の
 *  候補の中でユーザーが調べたい単語は確率…に活用して」）
 *
 * 画面は結果を先に出し、**これは後から**頼む（スキャンの待ち時間を延ばさない）。
 * 鍵が無い・時間切れ・自信が低いときは `order: null`（並べ替えない）。
 * 並べ替えはその人の画面の中だけで、何も保存しない。
 */
export const rankScanCandidates = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        items: z
          .array(
            z.object({
              headword: z.string().min(1).max(40),
              meaning: z.string().max(80).nullish(),
              kind: z.string().max(12).nullish(),
              confidence: z.number().min(0).max(1).optional(),
              owned: z.boolean().optional(),
            }),
          )
          .min(2)
          .max(24),
      })
      .parse(input),
  )
  .handler(async ({ data, context }) => {
    if (!jevAvailable()) return { order: null, probs: null, doubtful: [] as number[] };
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。並べ替えはおまけなので、同意が無ければ
    // 送らずに**並べ替えないまま**返す（スキャンの画面は止めない）。
    try {
      await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    } catch (e) {
      const { isAiConsentError } = await import("./ai-consent");
      if (!isAiConsentError(e)) throw e;
      return { order: null, probs: null, doubtful: [] as number[] };
    }
    /**
     * **上限を掛ける**（監査 2026-10-03 M7）。前は外の AI（Jev）を何回でも呼べた。
     * その人の 24 時間の上限（`jev_rank`、`ai-cap.ts`）に数える。並べ替えはおまけなので、
     * 上限に届いた・数えられない時は**並べ替えずに**返す（スキャンの画面は止めない）。
     */
    const { assertWithinDailyCap } = await import("./ai-provider.server");
    try {
      await assertWithinDailyCap(context.userId, "jev_rank");
    } catch (e) {
      const { isAiCapError } = await import("./ai-cap");
      if (!isAiCapError(e)) throw e;
      return { order: null, probs: null, doubtful: [] as number[] };
    }
    // 「台湾の言い方として疑わしいか」は台湾の標準語かを問う問い。日本語を学ぶ人の
    // 候補に掛けると、かなの語がすべて「疑わしい」になって後ろへ回る(2026-10-01)。
    // 掛けるかどうかは学習言語の表が決める(`taiwanTermCheck`)。
    const { getUserTargetLanguage } = await import("./ai-provider.server");
    const { targetProfile } = await import("./target-profile");
    const checkTaiwan = targetProfile(await getUserTargetLanguage(context.userId)).capture
      .taiwanTermCheck;
    const q = candidateQuestion(data.items.map((it) => ({ ...it, kind: it.kind ?? undefined })));
    const res = await askJev(q.state, q.questions, { timeoutMs: 2500 });
    const ranked = rankByWanted(data.items, res?.answers.wanted);
    // 台湾の言い方として**はっきり疑わしい**候補（画面は後ろへ回し「?」を付ける）。
    const doubtful = checkTaiwan ? doubtfulTaiwanTerms(data.items.length, res?.answers) : [];
    return ranked
      ? { order: ranked.order, probs: ranked.probs, doubtful }
      : { order: null, probs: null, doubtful };
  });
