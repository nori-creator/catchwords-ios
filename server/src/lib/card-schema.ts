import { z } from "zod";
import { coerceCategoryKey } from "./category";
import { ExtrasSchema, emptyExtras } from "./extras";
import { ExamplePatternSchema } from "./example-patterns";

/**
 * AIが返す「カード1枚」の形。
 *
 * ## なぜ別のファイルに出したか(2026-08-20)
 * オーナー指摘が2度:「単語の文字入力がエラーが出て、機能してない」。
 * 画面に出ていたのは **"AI did not return a structured card"** の1行だけ。
 * 日本語の画面に英語で、しかも**何が起きたのかを一切言わない**。
 *
 * 原因は2つ重なっていた:
 *
 * 1. `category_key` が `z.enum(CATEGORY_KEYS)` の素置きで、54個の外の棚名
 *    (「electronics」など)が返るたびに**カードが丸ごと落ちていた**。
 *    同じファイルの `new_shelf` には「1項目の型違いでカード生成が丸ごと
 *    失敗すると、棚が増えないどころか語が取れない」と**既に書いてあった** —
 *    その教訓が隣の項目に伝わっていなかった。
 * 2. 呼び出し側が `catch {}` で理由を握り潰していたので、どの項目が
 *    なぜ落ちたのかが誰にも見えなかった(`learnLexiconEntries` で辞書の
 *    蓄積が2か月死んでいたのと同じ形)。
 *
 * 形は独立して試せる物なので、ここに出して**わざと壊した入力**で
 * 試験を書く(`card-schema.test.ts`)。
 */
/**
 * カードの**形**が合わなかったことを表す。
 * 通信の失敗や上限とは扱いが違う(やり直す価値がある)ので、種類を分ける。
 */
export class CardShapeError extends Error {}

export const CardSchema = z.object({
  // 入力が日本語だった場合に解決された台湾華語の見出し語(繁体字)。
  headword_zh: z.string().default(""),
  reading_zhuyin: z.string().default(""),
  pinyin: z.string().default(""),
  meaning_ja: z.string(),
  part_of_speech: z.string().default("名詞"),
  level: z.string().default("TOCFL-2"),
  /**
   * **1項目の型違いでカードを丸ごと落とさない。**
   *
   * ここは `z.enum(CATEGORY_KEYS)` を素で置いていた。54個の外の棚名
   * (「electronics」など)が返るたびに `parse` が投げ、`genOnce` の
   * `catch` がそれを飲んで **"AI did not return a structured card"** だけを
   * 残していた。オーナーが2度「文字入力が機能してない」と言ったのは
   * これで、画面には英語の1行しか出ないので原因が誰にも見えなかった。
   *
   * 棚は**しまう場所**の話で、語そのものではない。決められなければ
   * `other` に置けばよく、`new_shelf` という逃げ道も既にある。
   * 例文も同じで、無くてもカードは使える。
   *
   * **`meaning_ja` だけは既定を置かない** — 意味の無いカードはカードでは
   * ないので、そこは正直に失敗させる。
   */
  // 「home / furniture」・番号・カテゴリーの名前も鍵1つに読む（`coerceCategoryKey`、2026-10-15）。
  category_key: z
    .unknown()
    .optional()
    .transform((v) => coerceCategoryKey(v)),
  example_sentence: z.string().catch(""),
  example_translation: z.string().catch(""),
  /**
   * どの棚にも当てはまらないときの**新しい棚の提案**。
   *
   * `category_key` は既定の54個に縛ったまま残す — 提案が使えなかったとき
   * (形が壊れている・既存と同じ・DBが受け付けない)に**必ず戻る先**が要る。
   * 提案は「あれば嬉しい」もので、無くてもキャッチは成立する。
   * ここを緩く受けるのは、生成物が必ず想定外を出すから。形を直すのも
   * 諦めるのも `shelf-proposal.ts` で完結させる。
   */
  new_shelf: z
    .object({
      // 型が違うものは**投げずに落とす**。1項目の型違いでカード生成が
      // 丸ごと失敗すると、棚が増えないどころか語が取れない。
      key: z.string().optional().catch(undefined),
      label: z.string().optional().catch(undefined),
      emoji: z.string().optional().catch(undefined),
      room_key: z.string().optional().catch(undefined),
      room_label: z.string().optional().catch(undefined),
    })
    .nullish()
    .catch(null),
  extras: ExtrasSchema.default(() => emptyExtras()),
});

export type GeneratedCard = z.infer<typeof CardSchema>;

/**
 * AI の返事の形 = カード + **場面のパターンごとの例文**（2026-10-15、`example-patterns.ts`）。
 * サーバが確かめて `example_sentence` / `extras.example_scene` / `extras.examples_extra` に写し、
 * 配列そのものは返さない・控えない（画面とiOSが受け取る形は `CardSchema` のまま）。
 * 壊れていても例文が無いだけでカードは使えるので、落とさず空にする。
 */
export const CardReplySchema = CardSchema.extend({
  example_patterns: z.array(ExamplePatternSchema).catch([]).default([]),
  /**
   * メインの例文がもう決まっている語（前から在る共有の文）の、**その文のための札**（2026-10-16 冰淇淋、
   * `mainExampleLabelRule`）。確かめるのは `checkMainExampleLabel`。返さない・控えない。
   */
  example_main: z.unknown().optional().catch(undefined),
  /**
   * 決まった文がある時の**予備の例文**（見出し語が入力と変わった回 — 手紙 → 信 — にだけメインにする）。
   * 返さない・控えない。壊れていれば無いのと同じ。
   */
  example_fallback: ExamplePatternSchema.optional().catch(undefined),
});

export type GeneratedCardReply = z.infer<typeof CardReplySchema>;
