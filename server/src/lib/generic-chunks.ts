import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";

/**
 * **どの名詞にも付く組み合わせを、型として教えない。**
 *
 * ## オーナー指示 2026-08-28 ③
 * > 「「買う（買）」や好きのような、どの名詞にも使える汎用的な組み合わせでは、
 * >  実践的なスピーキング力は養えません。ネイティブの脳内にある
 * >  「語彙のネットワーク」と「構文の型（公式）」をそのまま引き出し、
 * >  反射的に口から出る状態を作る。」
 *
 * ## 何が問題か
 * 「珍珠奶茶」の型として `買珍珠奶茶` `喜歡珍珠奶茶` が出る。文としては
 * 正しいが、**その語について何も教えていない** — 買/喜歡 はどんな名詞にも
 * 付くので、覚えても「珍珠奶茶が言えるようになった」ことにならない。
 * 覚える価値があるのは `半糖少冰` `加珍珠` のような、**その語とだけ強く
 * 結び付いている**組み合わせ。
 *
 * 一方 `喝珍珠奶茶` は落とさない。喝 は飲み物にしか付かないので、
 * 「これは飲む物だ」という情報がある。**「どんな語にも付くか」**が境目。
 *
 * ## 指示文だけに頼らない
 * この app は「書いてあることと返ってくる物は別」を何度も踏んでいる。
 * 指示文でも頼むが、**返ってきた物のほうを見て落とす**。
 *
 * ## 落としすぎないための線
 * 表は**短く、厳密一致**にする。「なんとなく汎用的」まで広げると、
 * 「很+状態動詞」のような**教えるべき型**まで落ちる（很 はどんな状態動詞
 * にも付くが、それこそが台湾華語で最初に覚える公式）。
 */

/**
 * どんな名詞にも付く「軽い」語。**これだけしか足していない型は落とす。**
 *
 * 入れる基準は1つ:「その語を知らなくても、名詞さえあれば言える」か。
 * 迷ったら**入れない** — 落としすぎるほうが害が大きい（型が1つも
 * 出なくなる）。
 */
export const LIGHT_WORDS: Record<string, readonly string[]> = {
  // **短く保つ。** 迷った語は入れない。`帶雨傘`(傘は「持って行く」物)の
  // ように、一見どこにでも付きそうで実は相手が決まっている動詞が多く、
  // 広げると**教えるべき型**まで落ちる。
  "zh-TW": ["買", "賣", "有", "沒有", "要", "想要", "喜歡", "不喜歡", "討厭", "愛", "是"],
  // get / take / make / bring は句動詞やコロケーションの核になるので入れない
  // (`take a photo` `get a haircut` は落としてはいけない型)。
  en: ["buy", "sell", "have", "has", "want", "wants", "like", "likes", "love", "hate", "need"],
  // 日本語(2026-10-01)。「買う」「好き」だけを足した型はその語について何も教えない。
  // 「使う」「持つ」は入れない — 「傘を持つ」「箸を使う」は相手の決まった型になり得る。
  ja: ["買う", "売る", "ある", "ない", "欲しい", "好き", "嫌い", "大好き", "いる", "要る"],
};

/**
 * それだけでは中身にならない語（人称・冠詞・助詞）。
 *
 * 「我的手機」の 我 と 的 のように、**どの型にも付きうる骨組み**。
 * 中身を数えるときは外に置く — 置かないと、骨組みが1つ混ざっただけで
 * 「汎用ではない」と判定されてしまう。
 */
export const FRAME_WORDS: Record<string, readonly string[]> = {
  "zh-TW": [
    "我",
    "你",
    "妳",
    "他",
    "她",
    "它",
    "我們",
    "你們",
    "他們",
    "的",
    "了",
    "嗎",
    "呢",
    "吧",
    "這",
    "那",
    "個",
    "一",
  ],
  en: [
    "a",
    "an",
    "the",
    "my",
    "your",
    "his",
    "her",
    "its",
    "our",
    "their",
    "this",
    "that",
    "these",
    "those",
    "i",
    "you",
    "he",
    "she",
    "we",
    "they",
    "it",
    "to",
    "of",
  ],
  // 日本語の骨組み(助詞・人称・指示語・です/だ)。どの型にも付きうる。
  ja: [
    "を",
    "が",
    "は",
    "に",
    "で",
    "の",
    "も",
    "と",
    "へ",
    "私",
    "僕",
    "あなた",
    "この",
    "その",
    "あの",
    "です",
    "だ",
  ],
};

/**
 * **指し示すだけの語**（この・その・あの + 量詞）。見出し語にこれだけを足した型は
 * 汎用として落とす。
 *
 * オーナー報告 2026-09-30（保溫瓶）: 使い方チャンクが `這款 + 保溫瓶`（この保温ボトル）
 * の1つだけになっていた。「この〜」はどの名詞にも付くので、ネイティブがその語を使う
 * 形を何も教えない。
 *
 * **量詞付きの物だけ**にする。`這` `那` 単独は `那時候` `這邊` のような決まった言い方を
 * 作るので落とさない。`這麼` `這樣` も入れない（`這麼好吃` は状態動詞の型そのもの）。
 * 英語は `this morning` `so that` のように指示語と組んだ決まった言い方が多いので置かない。
 */
const DETERMINERS: Record<string, RegExp> = {
  "zh-TW":
    /^[這那哪](?:個|款|種|些|支|隻|張|本|台|臺|輛|件|條|位|家|間|把|杯|瓶|顆|塊|份|雙|頂|盒|包|碗|盤|部|套)$/u,
};

// **既定の言語を直に書かない。** 正は `target-lang.ts` の定数1つで、
// そこを見る門が `target-lang.test.ts` に立っている(実際この門が、
// 最初の版が既定を直に書いていたのを捕まえた)。
const listFor = (table: Record<string, readonly string[]>, language?: string | null) =>
  new Set(table[normalizeTargetLanguage(language)] ?? table[DEFAULT_TARGET_LANGUAGE]);

/** 比べるための形（英語は大小を無視し、前後の飾りを落とす）。 */
function normalize(text: string): string {
  return (text ?? "")
    .trim()
    .toLowerCase()
    .replace(/^[「『（(]+|[」』）)，、。,.!?！？]+$/gu, "");
}

/**
 * その型が**その語について何も教えていない**か。
 *
 * 見出し語と骨組みの語を外して残った物が、全部「軽い語」だったら真。
 *
 * ## 残りが空のときは**落とさない**
 * 「我去了」の 我・了 は骨組みだが、「了」を置く位置こそがこの型の
 * 教える中身。骨組みしか残らない型を機械的に落とすと、**文法の型が
 * 全部消える**（試験がこれを捕まえた）。見出し語しか無い型は
 * `refineUsageChunks` が別に落とすので、ここで重ねて見なくていい。
 */
export function isGenericChunk(
  parts: ReadonlyArray<{ text?: string | null } | null | undefined> | null | undefined,
  headword: string,
  language?: string | null,
): boolean {
  const light = listFor(LIGHT_WORDS, language);
  const frame = listFor(FRAME_WORDS, language);
  const head = normalize(headword);
  const determiner = DETERMINERS[normalizeTargetLanguage(language)] ?? null;
  const content: string[] = [];
  const others: string[] = [];
  for (const p of parts ?? []) {
    const text = normalize(p?.text ?? "");
    if (!text) continue;
    // 見出し語そのもの（`喝` + `珍珠奶茶` の後ろ側）は中身に数えない。
    if (head && (text === head || text.includes(head) || head.includes(text))) continue;
    others.push(text);
    if (frame.has(text)) continue;
    content.push(text);
  }
  // 「この〜」「あの〜」しか足していない型（`這款` + `保溫瓶`）。どの名詞にも付く。
  if (determiner && others.length > 0 && others.every((w) => determiner.test(w))) return true;
  if (content.length === 0) return false;
  return content.every((w) => light.has(w));
}

/** 汎用の型を落とす。 */
export function withoutGenericChunks<T extends { parts?: ReadonlyArray<{ text?: string | null }> }>(
  chunks: ReadonlyArray<T> | null | undefined,
  headword: string,
  language?: string | null,
): T[] {
  return (chunks ?? []).filter((c) => c && !isGenericChunk(c.parts, headword, language));
}
