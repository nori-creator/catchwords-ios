import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";
import { orderForReader, type UsageChunkV2 } from "./chunks-v2";

/**
 * **単語の頁の「使い方チャンク」を取りに来る口**（v2。`docs/chunk-rules.md`）。
 *
 * iOS は単語の頁を開いた時、帯の語で v2 のチャンクが無ければここを呼ぶ。書庫に有れば即、無ければ作って
 * （2 社に書かせて照合、最長で十数秒）返す。`word_id` が分かれば、その人の帯の行（`word_level_content`）にも書く —
 * 次に開いた時は帯の行から読める。読む人の目標レベルで並べ替える（`orderForReader`）。
 */
const Input = z.object({
  headword: z.string().min(1).max(100),
  targetLanguage: z.string().default(DEFAULT_TARGET_LANGUAGE),
  word_id: z.string().uuid().optional(),
  /** ↻: 書庫を無視して作り直す。 */
  force: z.boolean().optional(),
  /** 他の人が作っている最中を待つ上限（ms）。既定 20 秒（自分で作る時は作り終わるまで）。 */
  wait_ms: z.number().int().min(0).max(60_000).optional(),
});

export type GetWordChunksResult = {
  status: "ready" | "pending" | "none";
  chunks: UsageChunkV2[];
  from_library: boolean;
};

export const getWordChunks = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => Input.parse(input))
  .handler(async ({ context, data }): Promise<GetWordChunksResult> => {
    const language = normalizeTargetLanguage(data.targetLanguage);
    const headword = data.headword.trim();
    const [{ supabaseAdmin }, provider, chunksServer] = await Promise.all([
      import("@/integrations/supabase/client.server"),
      import("./ai-provider.server"),
      import("./chunks-v2.server"),
    ]);
    const [explainLang, l1, levelGoal] = await Promise.all([
      provider.getExplanationLanguage(context.userId),
      provider.getLearnerL1(context.userId),
      provider.getUserLevelGoal(context.userId),
    ]);
    const job = data.force
      ? await chunksServer.startChunksV2Job(supabaseAdmin, { language, headword, explainLang, force: true })
      : await chunksServer.awaitChunksV2(supabaseAdmin, { language, headword, explainLang }, data.wait_ms ?? 20_000);

    if (job.status === "ready" && data.word_id) {
      // その人の帯の行にも置く（次に開いた時は帯の行から）。帯の無い古い語（legacy）には書かない。
      try {
        const lc = await import("./level-content.server");
        const band = await lc.callerLevelBand(supabaseAdmin, context.userId, data.word_id);
        if (band) {
          await lc.mergeIntoLevelContent(
            supabaseAdmin,
            data.word_id,
            { explainLang, l1: l1.code },
            band,
            { extras: { usage_chunks_v2: job.chunks }, replaceKeys: ["usage_chunks_v2"] },
          );
        }
      } catch (e) {
        console.warn("getWordChunks: 帯の行に書けない", (e as Error)?.message);
      }
    }
    return {
      status: job.status,
      chunks: job.status === "ready" ? orderForReader(job.chunks, { levelGoal, headword, language }) : [],
      from_library: job.fromLibrary,
    };
  });
