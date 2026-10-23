import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/**
 * **例文の字ごとの読み**（2026-10-22 オーナー「例文の漢字にピンインまたは注音をすべて書いて」）。
 * iOS の単語のページと復習の答え合わせが、見せる例文をまとめて送る。AI は呼ばない（`sentence-readings.server.ts`）。
 *
 * - `words`: その単語のカードが持つ読み（見出し・型の札）。文の中のその語の位置に、辞書より先に当てる。
 */
const Input = z.object({
  sentences: z.array(z.string().max(300)).max(24),
  words: z
    .array(z.object({ text: z.string().max(40), pinyin: z.string().max(160) }))
    .max(40)
    .optional(),
});

export const readSentences = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => Input.parse(input))
  .handler(async ({ data }) => {
    const { readSentence } = await import("./sentence-readings.server");
    return {
      readings: data.sentences.map((sentence) => ({
        sentence,
        units: readSentence(sentence, data.words ?? []),
      })),
    };
  });
