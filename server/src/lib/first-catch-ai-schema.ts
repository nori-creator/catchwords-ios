import { NAME_REGISTERS, normalizeNameRegister } from "./candidate-register";
import { z } from "zod";
import { coerceCategoryKey } from "./category";
import { LearningPreferencesSchema } from "./learning-preferences";
import { UI_LANGS } from "./i18n";
import { TARGET_LANGUAGES } from "./target-lang";

export const PersonalLessonSchema = z.object({
  senses: z
    .array(z.object({ meaning: z.string().min(1).max(700), note: z.string().max(700) }))
    .min(1)
    .max(4),
  examples: z
    .array(
      z.object({
        sentence: z.string().min(1).max(700),
        translation: z.string().max(700),
        situation: z.string().max(500),
        explanation: z.string().max(900),
      }),
    )
    .min(1)
    .max(3),
});
export type PersonalLesson = z.infer<typeof PersonalLessonSchema>;
export const FirstCatchSuggestionsSchema = z.object({
  suggestions: z
    .array(
      z.object({
        headword: z.string().min(1).max(100),
        /**
         * 表示言語の意味。**空もある** — 表示言語で書かれた意味が無い時は、別の言語の意味を
         * 出さずに空にする（`first-catch-meaning.ts`、実物確認 2026-10-03）。鍵の名前は昔のまま。
         */
        meaning_ja: z.string().max(500).default(""),
        reading_zhuyin: z.string().default(""),
        pinyin: z.string().default(""),
        // 「home / furniture」・番号・カテゴリーの名前も鍵1つに読む（`coerceCategoryKey`、2026-10-15）。
        category_key: z
          .unknown()
          .optional()
          .transform((v) => coerceCategoryKey(v)),
        distinction: z.string().default(""),
        /**
         * どんな言い方か（`candidate-register.ts` の5つ、2026-10-15）。チュートリアルの候補は写真の物ごとに
         * 1語（ふだんの名前）なので、無い・読めない時は一般的な言い方。
         */
        register: z.preprocess(
          (v) => normalizeNameRegister(v) ?? undefined,
          z.enum(NAME_REGISTERS).catch("common"),
        ),
        /** 写真のタグ（表示言語の一般的な呼び名、2026-10-15）。チュートリアルは意味の最初の言い方を使うので空でよい。 */
        object_label: z.string().catch("").default(""),
      }),
    )
    // **0件も形としては正しい**（暗い・何も写っていない写真）。0件を形の誤りとして
    // 落とすと「処理できませんでした」になり、撮り直しても同じ所で止まる
    // （βテスト 2026-09-30、父の報告）。0件は画面で「近づいて撮り直す」と言う。
    .max(5),
});
const common = {
  uiLanguage: z.enum(UI_LANGS),
  targetLanguage: z.enum(TARGET_LANGUAGES),
  preferences: LearningPreferencesSchema,
  /**
   * この端末で同意した「外部の AI へ送る」同意の版（`ai-consent.ts`）。登録前は記録する
   * 相手が居ないので、画面がこれを付ける。無い・古い版ならサーバは何も送らずに断る。
   */
  aiConsentVersion: z.number().int().min(0).max(1000).optional(),
};
export const FirstCatchAIInput = z.discriminatedUnion("action", [
  z.object({
    ...common,
    action: z.literal("suggest"),
    photo: z
      .string()
      .min(100)
      .max(4_000_000)
      .regex(/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/),
  }),
  z.object({ ...common, action: z.literal("card"), headword: z.string().min(1).max(100) }),
  z.object({
    ...common,
    action: z.literal("lesson"),
    headword: z.string().min(1).max(100),
    meaning: z.string().max(1500),
  }),
]);
export type FirstCatchAIRequest = z.infer<typeof FirstCatchAIInput>;
