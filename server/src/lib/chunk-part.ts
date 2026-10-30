import { z } from "zod";

/**
 * チャンクの札（block / part）の形。`extras.ts` と `chunks-v2.ts` の両方が使うので、どちらにも依らないここに置く
 * （`extras.ts` に置いたままだと v2 の形を `ExtrasSchema` に足す時に読み込みが輪になる）。
 */
export const ChunkPartSchema = z.object({
  text: z.string(),
  // 役割ラベル: S/V/V1/V2/O/M/C/Ptc など(復習の添削と同じ色体系で描画)
  pos: z.string().catch(""),
  /**
   * 入れ替えて使う所（公式の「人」「事」「someone」）。オーナー指示 2026-09-25
   * 「チャンクは公式、定理のように…跟＋人＋見面」。古いカードには無い。
   */
  slot: z.boolean().optional().catch(undefined),
  /**
   * 入れ替える所に、ネイティブがよく入れる**ほかの具体語**（頻度の高い順）。
   * オーナー指示 2026-09-27「汎用部分（人・もの）はタップすると、ネイティブ頻出の
   * 具体的単語が出る（跟+男朋友+吵架 → 女朋友・朋友…をスクロールで表示）。音声も全部」。
   * `ja` はその語の意味（読み手の言語）。古いカードには無い。
   */
  /**
   * 入れ替える所の**その語の意味**（読み手の言語）。語を入れ替えた時に、型の訳の中の
   * この部分を入れ替えた語の意味に差し替えて出す（R20「点線のなかのほかの単語をタップしたら、
   * もとの単語と同じように訳が表示され」）。古いカードには無い。
   */
  ja: z.string().optional().catch(undefined),
  /**
   * **札ごとの読み**（2026-10-15 オーナー「チャンクに拼音と注音を」）。台湾華語のカードだけ。
   * 拼音は声調記号つき・音節は空白区切り（`shuā zi`）、注音は音節を空白で区切り軽声は前に ˙
   * （`ㄕㄨㄚ ˙ㄗ`）。AI が書いた物をサーバが字ごとに検め、外れていれば辞書の読みに直す
   * （`chunk-readings.server.ts`）。**古いカードは持っていない**（作り直した時に付く）。
   */
  pinyin: z.string().optional().catch(undefined),
  zhuyin: z.string().optional().catch(undefined),
  alts: z
    .array(
      z.object({
        text: z.string(),
        ja: z.string().catch(""),
        // 入れ替える語の読み（台湾華語だけ。古いカードには無い）。
        pinyin: z.string().optional().catch(undefined),
        zhuyin: z.string().optional().catch(undefined),
      }),
    )
    .max(8)
    .optional()
    .catch(undefined),
});
export type ChunkPart = z.infer<typeof ChunkPartSchema>;
