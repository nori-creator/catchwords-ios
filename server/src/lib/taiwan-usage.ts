/**
 * `dictionary_entries.taiwan_usage` に入れてよい値を決める所。
 *
 * ## なぜ要るか(2026-08-19に見つけた不具合)
 * この列には制約が付いている:
 *
 *     taiwan_usage text check (taiwan_usage in ('common','written','spoken','rare'))
 *
 * ところが2箇所が**日本語の自由文**を入れていた —
 * `ai.functions.ts` は `extras.usage_context`(「スーパーや夜市でよく見かける」)、
 * `lexicon.server.ts` の日常語生成は `w.usage`(「使う場面、日本語1文」)。
 *
 * そして `learnLexiconEntries` は失敗を `catch {}` で飲む。`upsert` は一括なので、
 * **1行でも制約に当たるとその回の語が1つも学ばれない。**
 * 「ユーザーが1人でも使えば毎日賢くなる」と書いてある仕組みが、
 * 実際には何も貯めていなかった。黙って飲むから気づけなかった。
 *
 * ## 何から決めるか
 * **地の文を読んで当てにいかない。** 生成側は既に**形の決まった欄**を持っている:
 * `register_tag`(「口語」「書面」「口語・書面」)と `frequency_level`(1〜5)。
 * そちらから写すのが正しい。地の文を見るのは、形の決まった欄が無い経路
 * (日常語生成)だけで、しかも**紛れの無い言い方が出たときに限る**。
 * 決められなければ null を返す — **当てずっぽうで埋めない。**
 *
 * この列は「文体(書き/話し)」と「頻度(よく/まれ)」という別々の軸を
 * 1つに詰め込んでいる。どちらも読めるときは**文体を優先する** —
 * そちらのほうが語について多くを言っているから。
 */

export type TaiwanUsage = "common" | "written" | "spoken" | "rare";

const SPOKEN = /口語|話し言葉|会話|チャット|SNS|くだけ|スラング|日常会話/;
const WRITTEN = /書面|書き言葉|文章|新聞|ニュース|報道|論文|公文|硬い|かたい表現/;
const RARE = /まれ|稀|めった|ほとんど使わ|あまり使わ|古語|古い言い方|廃れ/;
const COMMON = /よく使う|よく見かける|日常的|頻繁|一般的|定番/;

/** 地の文から文体を読む。両方出たら決めない(片方だけのときが手がかり)。 */
function registerFromProse(prose: string): TaiwanUsage | null {
  const spoken = SPOKEN.test(prose);
  const written = WRITTEN.test(prose);
  if (spoken === written) return null; // 両方 or どちらも無い
  return spoken ? "spoken" : "written";
}

/**
 * 分かっている手がかりから、制約に通る1語を決める。
 * 決められなければ null(列は nullable なので、埋めないのが正しい姿)。
 */
export function taiwanUsageFrom(hints: {
  /** 「口語」「書面」「口語・書面」など、生成側の形の決まった欄。 */
  registerTag?: string | null;
  /** 1〜5(5=毎日レベル)。 */
  frequencyLevel?: number | null;
  /** 使う場面の地の文。形の決まった欄が無い経路のためだけに見る。 */
  prose?: string | null;
}): TaiwanUsage | null {
  const tag = (hints.registerTag ?? "").trim();
  if (tag) {
    const spoken = SPOKEN.test(tag);
    const written = WRITTEN.test(tag);
    // 「口語・書面」は両方 = 文体では絞れない。頻度の側へ落とす。
    if (spoken && !written) return "spoken";
    if (written && !spoken) return "written";
  }

  const prose = (hints.prose ?? "").trim();
  if (prose) {
    const byRegister = registerFromProse(prose);
    if (byRegister) return byRegister;
  }

  const level = hints.frequencyLevel;
  if (typeof level === "number" && Number.isFinite(level)) {
    if (level >= 4) return "common";
    if (level <= 1) return "rare";
    // 2〜3 は「どちらとも言えない」。埋めない。
    return null;
  }

  if (prose) {
    if (RARE.test(prose)) return "rare";
    if (COMMON.test(prose)) return "common";
  }
  return null;
}
