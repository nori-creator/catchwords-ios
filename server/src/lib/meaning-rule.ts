/**
 * 「意味」と「使い分けの一言」を**要るときだけ**書かせる指示。
 *
 * オーナー指示 2026-08-25:
 * > 「母語の意味の説明は**1対1で明らかなら不要**。
 * >  1対1でない、または母語に無い場合だけ説明して」
 *
 * ## なぜ1箇所に置くか
 * 同じ判断が**2箇所**で要る:
 *
 * 1. 撮ったあとの**候補**の `distinction`（どれを選ぶかの手掛かり）
 * 2. カードの **`meaning_ja`**（この画面を開く理由の一行）
 *
 * 候補側には既に条件が書いてあったが、カード側は「意味（簡潔に）」の
 * 一言だけだった。**同じ原則を2箇所の散文に書くと必ず片方だけ古くなる。**
 * この作業場が繰り返している事故の、散文版。
 *
 * ## 何が「無いより悪い」か
 * 「その物全般を指す表現」のような**言い換え**は、読む人に何も足さない。
 * しかも全部の行に何か書いてあると、**本当に区別が要る行が埋もれる。**
 * だから「迷ったら書かない」を必ず添える。
 */

/** 言い換えを禁じる共通の一節。両方の指示がこれを含む。 */
export const NO_PADDING = [
  "**言い換えを書かない。** 「その物全般を指す表現」のように、意味を",
  "  言い直しただけの一言は読む人に何も足さない。",
  "  全部に何か書いてあると、**本当に説明が要る所が埋もれる。**",
  "  迷ったら書かない — 手掛かりにならない一言は、無いより悪い。",
].join("\n");

/**
 * カードの `meaning_ja` の指示。
 *
 * @param targetName 学習言語の呼び名（「台湾華語」「英語」）
 * @param explanationLanguageName 解説を書く言語の呼び名
 */
export function meaningRule(targetName: string, explanationLanguageName: string): string {
  return [
    `意味。**${explanationLanguageName}で書く。**`,
    `  **1対1で対応する語が${explanationLanguageName}に在るなら、その語だけ。**`,
    "  「傘」「タピオカミルクティー」のように、訳語を1つ置いて終わりにする。",
    `  説明を足すのは次の2つだけ:`,
    `  ・${explanationLanguageName}の1語では**意味が分かれてしまう**とき`,
    `    （どの意味かを短く添える）`,
    `  ・${explanationLanguageName}に**対応する語が無い**とき`,
    "    （その物・その事を短く言い表す）",
    // R17「湯咖哩の英語の…単語の意味が長すぎる」— 説明文の形で返る回があった。
    `  **長さの上限: 日本語・中国語なら15字、英語なら4語まで。** 文にしない（読点・コンマで続けない）。`,
    NO_PADDING,
  ].join("\n");
}

/** 意味として出してよい長さ（これを超えた物は、最初の区切りまでに縮める）。 */
const MAX_CJK = 18;
const MAX_LATIN = 32;
/**
 * 区切りまで縮めても、まだ長すぎる時の**最後の上限**（字数。末尾に「…」を付ける）。
 * 「ゴキブリ駆除用の毒餌（ベイト剤）。ゴキブリが好む成分と…」のように説明文で返り、
 * しかも区切りの手前がまだ長い回がある（オーナー報告 2026-10-05、iPhone の復習の4択）。
 */
const CAP_CJK = 20;
const CAP_LATIN = 40;

/** 英語の指示文に入れる長さの上限（`meaningRule` と同じ数）。チュートリアルの AI が使う。 */
export const MEANING_LENGTH_RULE_EN =
  "meaning_ja is a short gloss, not a definition: at most 15 characters in Japanese or Chinese, or at most 4 words in English. No sentences, no commas or 。 chaining, no parenthetical notes.";

function isLatinText(s: string): boolean {
  // ASCII 全域（制御文字を含む）と Latin-1 拡張だけでできた文か。制御文字を含めるのは意図。
  // eslint-disable-next-line no-control-regex
  return /^[\x00-\x7F\u00C0-\u024F\s]+$/.test(s);
}

/** 字数（サロゲートペアを1字と数える）で上限に収め、切った時だけ「…」を付ける。 */
function capLength(s: string, max: number): string {
  const chars = Array.from(s);
  if (chars.length <= max) return s;
  return `${chars
    .slice(0, max - 1)
    .join("")
    .trim()}…`;
}

/**
 * **意味を「語」の長さに縮める**（R17「湯咖哩の英語の単語の候補や単語の意味が長すぎる」）。
 *
 * 指示でも頼んでいるが、説明文（「Soup curry, a Japanese-style curry dish served in…」）で
 * 返る回が実際にある。長い時だけ、最初の区切り（、，,；;。(（:）の手前までにする。
 * 区切りの手前でもまだ長い・区切りが無い時は、上限で切って「…」を付ける
 * （2026-10-05: 前は区切りが無ければ触らず、4択の問いに2行の説明文がそのまま出ていた）。
 * 保存してある元の文は変えない — 画面に出す時・保存前に作り直すだけ。
 */
export function shortMeaning(text: string | null | undefined): string {
  const s = (text ?? "").trim();
  if (!s) return "";
  const latin = isLatinText(s);
  const cap = latin ? CAP_LATIN : CAP_CJK;
  if (s.length <= (latin ? MAX_LATIN : MAX_CJK)) return s;
  const cut = s.search(/[、，,；;。．(（:：—–]|\.\s/);
  const head = cut > 0 ? s.slice(0, cut).trim() : "";
  if (head.length >= (latin ? 2 : 1)) return capLength(head, cap);
  return capLength(s, cap);
}

/**
 * カードの意味を縮める（保存の前）。縮めて削れた説明は、**使い方の欄が空の時だけ**そこへ移す
 * （説明そのものは捨てない。単語の詳細の「使う場面」に出る）。
 */
export function withShortMeaning<
  T extends { meaning_ja: string; extras?: { usage_context?: string } | null },
>(card: T): T {
  const full = (card.meaning_ja ?? "").trim();
  const short = shortMeaning(full);
  if (short === full) return card;
  const extras = card.extras;
  if (extras && !(extras.usage_context ?? "").trim()) {
    return { ...card, meaning_ja: short, extras: { ...extras, usage_context: full } };
  }
  return { ...card, meaning_ja: short };
}

/**
 * 撮ったあとの候補の `distinction` の指示。
 *
 * @param targetName 学習言語の呼び名
 * @param examples その言語で実際に区別が要る語の例
 */
export function distinctionRule(targetName: string, examples: string): string {
  return [
    "**distinction(使い分けの一言)は、区別が要るときだけ書く:**",
    `書くのは「母語では1語なのに${targetName}では**別の語に分かれる**」場合だけ。`,
    "そのときだけ、見た人が**なぜこの語であって隣の語ではないのか**を選べる。",
    `- 書く例: ${examples}`,
    "- **書かない**: 母語と一対一で、迷いようがない語。そういう語は**空文字**にする。",
    NO_PADDING,
  ].join("\n");
}
