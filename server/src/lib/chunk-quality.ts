import {
  chunkMentionsHeadword,
  MAX_CHUNK_CHARS,
  MAX_CHUNK_CHARS_EN,
  MAX_CHUNK_CHARS_JA,
  MAX_CHUNK_PARTS,
  MAX_CHUNK_WORDS_EN,
  MAX_CHUNKS,
  type AiUsageChunk,
  type ChunkPart,
  type UsageChunk,
} from "./extras";
import { isBrokenUsageChunk, withoutSeparatorParts, DEGREE_CHOICES } from "./chunk-grammar";
import { isGenericChunk } from "./generic-chunks";
import { readerText } from "./note-language";
import { posGroup } from "./pos";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **使い方の型（チャンク）の門 — AI を呼ばずに、保存する前に落とす**（2026-10-15）。
 *
 * ## なぜ要るか（オーナー報告 2026-10-15）
 * > 「チャンクの 拿刷子刷牙 間違ってる。刷子（shuāzi）と言うと、掃除用や靴洗い用などの一般的な
 * >  ブラシを指すことがほとんどです。このようなチャンクのミスが起きないように徹底して。」
 * > 「チャンクのミスが多すぎる。今までのミス、考えられる起こりうるミスを考えて対策をして。」
 *
 * 本番の 60 日分（`words` 138 語・`word_explanations` 158 行・`generated_cards` 127 枚）の型を全部読んで、
 * 起きた間違いを種類に分けた。指示文は直したが（`ai.functions.ts` の `CHUNK_SENSE_RULE` ほか）、
 * **この app は「指示文に書いたことと返ってくる物は別」を何度も踏んでいる**ので、返ってきた物を
 * ここで見る。画面側の `refineUsageChunks`（web）・`refinedChunks`（iOS）は保存済みの語のための
 * 最後の網で、**ここは保存する前の門**。落とした理由は呼ぶ側が記録に残す。
 *
 * ## 落とす種類（本番で見つかった順に）
 * - `sense_conflict` … 見出し語を**別の物**の動作に当てた（刷子 → 拿刷子刷牙。歯を磨くのは牙刷 /
 *   貓眼（ドアスコープ）→ 宝石の猫目石の型 / 機車（スクーター）→ 「很機車 = 意地悪」の俗語の型）。
 *   意味の欄の言葉と、型の字・訳の言葉がぶつかる組を表で持つ（`SENSE_CONFLICTS`）。
 * - `blocklist` … 本番で見つかった崩れた型そのもの（`KNOWN_BAD_CHUNKS`）。表ではなく指示文と上の
 *   規則で止めるのが本筋で、これは**最後の網**。
 * - `self_check` … AI 自身が `fits: false` と答えた型（指示文で自己点検させる）。
 * - `headword_not_token` … 見出し語が**1つの札として**入っていない（桃 のカードに 買一盒桃子 /
 *   床 のカードに 起床 / 手 のカードに 手機 — 字は入っているが別の語）。
 * - `single_token` … 札が1つだけ（吃早午餐・電風扇・起床 — 語であって使い方ではない）。
 * - `compound_split` … 見出し語と1〜2字の名詞を並べただけ（門＋口・手＋機・楊桃＋汁・鬆餅＋機 — 1語を
 *   割った物。飲み物の注文の言い方 半糖・去冰 は除く）。
 * - `measure_word` / `redundant_measure` … 量詞が入る型（一束＋花束・再來一碗＋肉燥麵・買一台＋小冰箱）。
 *   量詞は別の欄で読む。`pos: "M"` の札は**量詞の形をしている時だけ**量詞と見る（剛出爐的 に M と
 *   付いた回に、良い型を落とさない）。
 * - `sentence` … 主語の付いた文（這個＋貓眼＋很＋漂亮・這間＋湯咖哩＋很＋有名）、句点のある物。
 * - `echo_verb` … 見出し語の字をそのまま動詞にして終わる型（用＋刷子＋刷 / 夾子＋夾）。目的語が無く、
 *   その語について何も教えない（オーナー報告 2026-10-15 の 用刷子刷）。
 * - `generic` / `broken` / `too_long` / `too_many_parts` … 既存の規則（`generic-chunks.ts`・`chunk-grammar.ts`）。
 * - `foreign_script` … 台湾華語の札に かな・英語の語が混ざる（pos を日本語で書いた回は**直して通す**）。
 * - `pos_as_text` … 札の字が品詞の記号そのもの（練手臂＋O）。その札を外し、残りを見る。
 * - `no_translation` / `translation_language` … 訳が無い・読む人の言語でない（同じ言語で読む人は除く）。
 * - `duplicate` / `duplicate_translation` … 同じ型・同じ訳の2つ目（擦＋凡士林 と 抹＋凡士林）。
 *
 * 外の世界に触れない（純粋）。試験は `chunk-quality.test.ts`（本番の失敗と、落としてはいけない 30 語）。
 */

export type ChunkDropReason =
  | "self_check"
  | "shape"
  | "single_token"
  | "too_many_parts"
  | "too_long"
  | "sentence"
  | "foreign_script"
  | "headword_not_token"
  | "compound_split"
  | "measure_word"
  | "redundant_measure"
  | "generic"
  | "broken"
  | "echo_verb"
  | "no_translation"
  | "translation_language"
  | "sense_conflict"
  | "blocklist"
  | "duplicate"
  | "duplicate_translation";

export type ChunkGateContext = {
  headword: string;
  language?: string | null;
  /** 読む人の言語（訳の確かめ）。無ければ訳は見ない。 */
  readerLang?: string | null;
  /** このカードの意味の欄（読む人の言語）。意味とぶつかる型を見つけるのに使う。 */
  meaning?: string | null;
  /** 量詞の欄（同じ字の型を落とす）。 */
  measureWords?: ReadonlyArray<{ word?: string } | null | undefined> | null;
};

export type ChunkGateResult = {
  kept: UsageChunk[];
  dropped: Array<{ text: string; reason: ChunkDropReason }>;
};

/** 台湾の詞類表の記号以外で書かれた pos を、記号に直す（日本語・英語の品詞名）。 */
const POS_ALIASES: ReadonlyArray<readonly [RegExp, string]> = [
  [/^(量詞|数量詞|數量詞|measure word( phrase)?|classifier)$/i, "M"],
  [/^(名詞|noun|名詞句)$/i, "N"],
  [/^(代名詞|代詞|pronoun)$/i, "Pron"],
  [/^(状態動詞|狀態動詞|形容詞|adjective|adj)$/i, "Vs"],
  [/^(助動詞|auxiliary( verb)?|aux)$/i, "Vaux"],
  [/^(動詞|verb|v)$/i, "V"],
  [/^(副詞|adverb|adv|time adverb)$/i, "Adv"],
  [/^(介詞|前置詞|preposition|prep)$/i, "Prep"],
  [/^(連詞|接続詞|接續詞|conjunction|conj)$/i, "Conj"],
  [/^(助詞|particle|part|語気詞|語氣詞)$/i, "Ptc"],
  [/^(限定詞|指示詞|determiner|det)$/i, "Det"],
];

/** `pos` を記号に直す（記号ならそのまま）。 */
export function normalizeChunkPos(pos: string | null | undefined): string {
  const p = (pos ?? "").trim();
  if (!p) return "";
  for (const [re, tag] of POS_ALIASES) if (re.test(p)) return tag;
  return p;
}

/** 品詞の記号そのもの（札の字として来た回に外す）。 */
const POS_TAG_AS_TEXT = /^(S|V|O|M|C|N|P|Ptc|Adv|Prep|Det|Vs|Vi|Vst|Vaux|Vp|Conj|Pron|Aux)$/;

/** 文末の約物（`extras.ts` と同じ）。 */
const SENTENCE_END = /[。．.!！?？…]/u;

/** 量詞に付く数・指示詞。 */
const MEASURE_LEAD = "[一二兩两三四五六七八九十幾几半這那哪每数數0-9０-９]";
/** よく使う量詞（1字）。数・指示詞の後ろに立てば量詞。 */
const CLASSIFIERS =
  "個杯碗盤份隻張支條瓶罐把台臺件雙顆塊包盒本頂副束棵朵片根座間家位輛部套袋碟串節斤滴粒頭匹尾封幅扇道堆";
/** 単独でも量詞としか読めない字（頭・家・片・塊 のように名詞にもなる字は入れない）。 */
// 把（介詞の 把 と同じ字）は入れない — 「把＋手帕＋拿出來」を量詞の型と取り違える。
const BARE_CLASSIFIERS =
  "個杯碗盤份隻張支條瓶罐台臺件雙顆包盒本頂副束棵朵座間輛部套袋碟串斤滴粒匹尾封幅扇";
/** 「一碗」「這台」「兩杯」— 数・指示詞 ＋ 量詞。札の中に入っていれば量詞の型。 */
const MEASURE_IN_TEXT = new RegExp(`${MEASURE_LEAD}[${CLASSIFIERS}]`, "u");
/** 札全体が量詞（「一碗」「碗」「這台」）。 */
const MEASURE_ONLY = new RegExp(`^(${MEASURE_LEAD}+[${CLASSIFIERS}]|[${BARE_CLASSIFIERS}])$`, "u");

/** 飲み物の注文の言い方（名詞の後ろに置く）。2字の名詞と並んでも「1語を割った」とは見ない。 */
const ORDER_PHRASES = new Set([
  "半糖",
  "少糖",
  "微糖",
  "無糖",
  "全糖",
  "去冰",
  "少冰",
  "微冰",
  "多冰",
  "正常",
  "熱的",
  "冰的",
  "溫的",
  "加珍珠",
  "加料",
  "外帶",
  "內用",
]);

/** 文の頭に立つ主語（これ＋見出し語＋述語 は文であって型ではない）。 */
const SUBJECT_HEAD =
  /^(這|那|哪)(個|些|款|種|台|臺|隻|張|支|本|件|杯|瓶|碗|盤|家|間|位|部|輛|套|顆|塊)?$|^(我|你|妳|他|她|它|我們|你們|他們|她們)(的)?$/u;

/**
 * **意味の欄とぶつかる型**。`gloss` は意味の欄（読む人の言語）か見出し語に当て、`forbid` は型の字と
 * 訳を continued で当てる。当たれば `sense_conflict`。**狭く・確かな組だけ**を置く（広げると良い型が落ちる）。
 */
export const SENSE_CONFLICTS: ReadonlyArray<{
  /** 何の組か（記録用）。 */
  id: string;
  gloss: RegExp;
  forbid: RegExp;
  /** この見出し語には当てない（その物そのものの語）。 */
  unless?: RegExp;
}> = [
  {
    // 刷子（掃除・靴洗いのブラシ）に 刷牙（歯ブラシ 牙刷 の動作）・梳頭（櫛・梳子 の動作）。
    id: "brush",
    gloss: /ブラシ|たわし|刷子|\bbrush(es)?\b|\bscrub(bing)? brush\b/iu,
    forbid: /刷牙|牙刷|歯を磨|歯磨|tooth|teeth|梳頭|梳髮|梳子|\bcomb\b|hairbrush|hair brush/iu,
    unless: /^(牙刷|梳子|髮刷)$/u,
  },
  {
    // 牙刷（歯ブラシ）に 刷鞋・刷地（掃除のブラシの動作）。
    id: "toothbrush",
    gloss: /歯ブラシ|toothbrush|牙刷/iu,
    forbid: /刷鞋|洗鞋|刷地|刷馬桶|刷油漆|scrub the floor|shoes|toilet|paint/iu,
  },
  {
    // 貓眼（ドアスコープ）に 宝石（猫目石）・首飾りの型。
    id: "peephole",
    gloss: /ドアスコープ|のぞき穴|覗き穴|peephole|door viewer|door scope|門上的小孔/iu,
    forbid: /寶石|宝石|猫目石|\bgem|jewel|necklace|項鍊|戒指|\bring\b|bracelet|手鍊|耳環|earring/iu,
  },
  {
    // 機車（スクーター）に 俗語の「很機車（意地悪・面倒）」の型。
    id: "scooter",
    gloss: /スクーター|バイク|原付|scooter|motorbike|motorcycle|moped|摩托車/iu,
    forbid:
      /(很|太|超|好|這麼|那麼|真|蠻|有點)機車|機車(了|的人|個性)|意地|感じが悪|めんどくさ|annoying|picky|fussy|difficult person|難搞/iu,
  },
  {
    // 尺（定規）に 長さの単位の 尺（一尺・三尺）の型。
    id: "ruler",
    gloss: /定規|ものさし|\bruler\b/iu,
    forbid: /長さの単位|unit of length|[一二兩三四五六七八九十幾]尺|公尺|英尺|feet|inch/iu,
  },
  {
    // 手（手）に 手機（スマホ）を割った型。
    id: "hand",
    gloss: /^手$|^(手|て)（|^hand$|\bhand\b/iu,
    forbid: /手機|mobile phone|smartphone|スマホ|携帯/iu,
    unless: /^(手機|手錶|手鍊)$/u,
  },
];

/**
 * **本番で出た崩れた型そのもの**（見出し語 → 型の字）。指示文と上の規則で止めるのが本筋で、ここは
 * 最後の網 — 同じ物が二度と出ないことだけを約束する。字は札をつないだ物（＋は無し）。
 */
export const KNOWN_BAD_CHUNKS: ReadonlyArray<readonly [headword: string, text: string]> = [
  ["刷子", "拿刷子刷牙"],
  ["花束", "一束花束"],
  ["筆", "簽筆"],
  ["麻辣燙", "燙麻辣燙"],
  ["大拇指", "對大拇指"],
  ["桃子", "水蜜桃子"],
  ["桃子", "水蜜桃桃子"],
  ["嘴邊肉", "嘴邊肉切"],
  ["紙箱", "紙箱裝東西"],
  ["馬克杯", "裝熱水馬克杯"],
  ["手帕", "擦手帕"],
  ["手帕", "擦手帕汗水"],
  ["籃子", "裝籃子"],
  ["叉子", "用叉子"],
  ["尺", "量長度用尺"],
];

const KANA = /[ぁ-ゟァ-ヺ]/u;
const HAN = /\p{Script=Han}/u;

/** 札の字に、その言語でない文字が混ざっているか（台湾華語に かな・英語の語、英語に 漢字・かな）。 */
export function hasForeignScript(text: string, language: string | null | undefined): boolean {
  const lang = normalizeTargetLanguage(language);
  if (lang === "en") return HAN.test(text) || KANA.test(text);
  if (lang === "ja") return /[a-zA-Z]{3,}/u.test(text) || /[ㄅ-ㄩ]/u.test(text);
  // 台湾華語: かな・小文字の英語の語（T恤・Q彈・3C・USB の大文字1〜3字は語の一部）。
  return KANA.test(text) || /[a-z]{2,}/u.test(text) || /[A-Za-z]{4,}/u.test(text);
}

/** 量詞の札か（記号だけに頼らない — 付け忘れ・付け間違いの両方がある）。 */
function isMeasurePart(
  part: ChunkPart,
  measureCores: ReadonlySet<string>,
  language: string | null | undefined,
): boolean {
  if (!normalizeTargetLanguage(language).startsWith("zh")) {
    return normalizeChunkPos(part.pos) === "M";
  }
  const text = part.text.trim();
  if (ORDER_PHRASES.has(text)) return false;
  // 介詞・動詞の記号が付いた1字の札（把・用）は量詞ではない。
  const pos = normalizeChunkPos(part.pos);
  if ([...text].length === 1 && (pos === "Prep" || pos === "V" || pos === "C")) return false;
  if (measureCores.has(measureWordCore(text))) return true;
  if (MEASURE_ONLY.test(text)) return true;
  // 「再來一碗」「買一台」— 動詞に量詞がくっ付いた札。pos だけの M（剛出爐的/M）は量詞と見ない。
  return MEASURE_IN_TEXT.test(text);
}

/** 量詞から数を落として本体だけにする（`extras.ts` と同じ）。 */
function measureWordCore(word: string): string {
  return word.trim().replace(/^[0-9０-９一二三四五六七八九十兩几幾半個]*(?=.)/u, "");
}

/** 量詞の字が見出し語に入っている（束 ⊂ 花束・杯 ⊂ 杯子）。 */
function isRedundantMeasure(part: ChunkPart, headword: string): boolean {
  const core = measureWordCore(part.text.trim());
  return [...core].length === 1 && [...headword].length >= 2 && headword.includes(core);
}

function chunkText(parts: ReadonlyArray<ChunkPart>, language: string | null | undefined): string {
  const sep = normalizeTargetLanguage(language) === "en" ? " " : "";
  return parts
    .map((p) => p.text.trim())
    .filter(Boolean)
    .join(sep);
}

function countWords(text: string): number {
  return text.split(/[\s'’-]+/u).filter(Boolean).length;
}

/** 読む人の言語が学ぶ言語と同じか（繁體中文で台湾華語を読む人の訳は空でよい）。 */
function readerIsTarget(
  readerLang: string | null | undefined,
  language: string | null | undefined,
) {
  const r = (readerLang ?? "").toLowerCase();
  const t = normalizeTargetLanguage(language).toLowerCase();
  if (!r) return false;
  return r.startsWith("zh") ? t.startsWith("zh") : r === t;
}

/** 訳を比べる形（空白・句点・括弧書きを落とす）。 */
function translationKey(ja: string): string {
  return ja
    .replace(/[（(][^）)]*[）)]/gu, "")
    .replace(/[\s。．.!！?？、,，]/gu, "")
    .toLowerCase();
}

/** 入れ替えられる札の品詞（名詞・量詞・台湾華語の程度の語）。それ以外の slot・alts は外す。 */
function swappable(part: ChunkPart, language: string | null | undefined): boolean {
  const pos = normalizeChunkPos(part.pos);
  if (!pos) return true;
  const g = posGroup(pos);
  if (g === "n" || g === "m") return true;
  return (
    normalizeTargetLanguage(language).startsWith("zh") &&
    (DEGREE_CHOICES as readonly string[]).includes(part.text.trim())
  );
}

/**
 * 保存する形に整える: 自己点検の欄を外し、見出し語の札と入れ替えられない札の slot・alts を外す。
 * （点線の判定は画面側にもあるが、保存する物から外しておけば iOS も同じ物を見る。）
 */
export function tidyForStorage(chunk: AiUsageChunk, ctx: ChunkGateContext): UsageChunk {
  const head = ctx.headword.trim();
  const parts = withoutSeparatorParts(chunk.parts ?? []).map((p) => {
    const text = p.text.trim();
    const out: ChunkPart = { ...p, text, pos: normalizeChunkPos(p.pos) };
    const isHead = text === head || (head && chunkMentionsHeadword(text, head, ctx.language));
    if (isHead || !swappable(out, ctx.language)) {
      delete out.slot;
      delete out.alts;
    }
    return out;
  });
  return { parts, ja: (chunk.ja ?? "").trim() };
}

/** 自己点検の欄だけを外す（形を変えない）。 */
export function stripChunkSelfCheck(chunk: AiUsageChunk): UsageChunk {
  const { fits: _fits, why: _why, ...rest } = chunk;
  void _fits;
  void _why;
  return rest;
}

/**
 * 最後の札が、見出し語の字を1字だけ使った動詞（刷子 → 刷、夾子 → 夾、剪刀 → 剪）で、その後ろに目的語が無い。
 * 「用刷子刷」「夾子夾」は道具の名前を動詞で言い直しただけ。
 */
export function endsWithEchoVerb(parts: ReadonlyArray<ChunkPart>, headword: string): boolean {
  if (parts.length < 2 || [...headword].length < 2) return false;
  const last = parts[parts.length - 1];
  const t = last.text.trim();
  if ([...t].length !== 1 || t === headword || !headword.includes(t)) return false;
  return posGroup(normalizeChunkPos(last.pos) || "V") === "v";
}

/** この型が意味の欄とぶつかるか（`SENSE_CONFLICTS`）。当たった組の id、無ければ null。 */
export function senseConflict(
  chunk: { parts?: ReadonlyArray<ChunkPart> | null; ja?: string | null },
  ctx: Pick<ChunkGateContext, "headword" | "meaning">,
): string | null {
  const head = ctx.headword.trim();
  const gloss = `${ctx.meaning ?? ""} ${head}`;
  const haystack = [
    ...(chunk.parts ?? []).map((p) => p.text),
    ...(chunk.parts ?? []).flatMap((p) => (p.alts ?? []).flatMap((a) => [a.text, a.ja])),
    chunk.ja ?? "",
  ].join(" ");
  for (const c of SENSE_CONFLICTS) {
    if (c.unless?.test(head)) continue;
    if (!c.gloss.test(gloss)) continue;
    if (c.forbid.test(haystack)) return c.id;
  }
  return null;
}

/**
 * **門。** 返ってきた型を1つずつ確かめ、通った物（保存する形）と落とした物（理由つき）を返す。
 * 順番は返ってきた順のまま（生成側は頻度の高い順に並べる）。上限は `MAX_CHUNKS`。
 */
export function gateUsageChunks(
  raw: ReadonlyArray<AiUsageChunk | null | undefined> | null | undefined,
  ctx: ChunkGateContext,
): ChunkGateResult {
  const head = ctx.headword.trim();
  const lang = normalizeTargetLanguage(ctx.language);
  const zh = lang.startsWith("zh");
  const isEnglish = lang === "en";
  const maxChars = lang === "ja" ? MAX_CHUNK_CHARS_JA : MAX_CHUNK_CHARS;
  const measureCores = new Set(
    (ctx.measureWords ?? []).map((m) => measureWordCore(m?.word ?? "")).filter((w) => w.length > 0),
  );
  const bad = new Set(
    KNOWN_BAD_CHUNKS.filter(([h]) => h === head).map(([, t]) => t.replace(/\s+/g, "")),
  );
  const seenText = new Set<string>();
  const seenJa = new Set<string>();
  const kept: UsageChunk[] = [];
  const dropped: ChunkGateResult["dropped"] = [];

  for (const c of raw ?? []) {
    if (!c) continue;
    const rawParts = (c.parts ?? []).filter((p) => p && typeof p.text === "string");
    const rawText = chunkText(rawParts, ctx.language);
    const drop = (reason: ChunkDropReason) => dropped.push({ text: rawText, reason });

    if (c.fits === false) {
      drop("self_check");
      continue;
    }
    // 品詞の記号そのものが札の字になった物（練手臂＋O）は、その札だけ外す。
    const parts = withoutSeparatorParts(
      rawParts.filter((p) => !(POS_TAG_AS_TEXT.test(p.text.trim()) && !HAN.test(p.text))),
    )
      .map((p) => ({ ...p, text: p.text.trim(), pos: normalizeChunkPos(p.pos) }))
      .filter((p) => p.text.length > 0);
    if (parts.length === 0) {
      drop("shape");
      continue;
    }
    if (parts.length > MAX_CHUNK_PARTS) {
      drop("too_many_parts");
      continue;
    }
    const text = chunkText(parts, ctx.language);
    if (SENTENCE_END.test(text)) {
      drop("sentence");
      continue;
    }
    if (!isEnglish && parts.length === 1) {
      drop("single_token");
      continue;
    }
    if (parts.some((p) => hasForeignScript(p.text, ctx.language))) {
      drop("foreign_script");
      continue;
    }
    if (isEnglish) {
      if (countWords(text) > MAX_CHUNK_WORDS_EN || text.length > MAX_CHUNK_CHARS_EN) {
        drop("too_long");
        continue;
      }
    } else if ([...text].length > maxChars) {
      drop("too_long");
      continue;
    }
    if (zh) {
      if (!parts.some((p) => p.text === head)) {
        drop("headword_not_token");
        continue;
      }
      if (parts.length >= 3 && SUBJECT_HEAD.test(parts[0].text) && parts[1].text === head) {
        drop("sentence");
        continue;
      }
      const measure = parts.find(
        (p) => p.text !== head && isMeasurePart(p, measureCores, ctx.language),
      );
      if (measure) {
        drop(isRedundantMeasure(measure, head) ? "redundant_measure" : "measure_word");
        continue;
      }
      if (
        parts.length === 2 &&
        parts.every((p) => posGroup(p.pos || "N") === "n") &&
        parts.some((p) => p.text !== head && [...p.text].length <= 2 && !ORDER_PHRASES.has(p.text))
      ) {
        drop("compound_split");
        continue;
      }
    } else {
      if (!chunkMentionsHeadword(chunkText(parts, " "), head, ctx.language)) {
        drop("headword_not_token");
        continue;
      }
      if (parts.some((p) => p.text !== head && isMeasurePart(p, measureCores, ctx.language))) {
        drop("measure_word");
        continue;
      }
    }
    if (isGenericChunk(parts, head, ctx.language)) {
      drop("generic");
      continue;
    }
    if (isBrokenUsageChunk({ parts, ja: c.ja }, head, ctx.language)) {
      drop("broken");
      continue;
    }
    if (zh && endsWithEchoVerb(parts, head)) {
      drop("echo_verb");
      continue;
    }
    if (senseConflict({ parts, ja: c.ja }, ctx)) {
      drop("sense_conflict");
      continue;
    }
    if (bad.has(text.replace(/\s+/g, ""))) {
      drop("blocklist");
      continue;
    }
    const ja = (c.ja ?? "").trim();
    if (ctx.readerLang && !readerIsTarget(ctx.readerLang, ctx.language)) {
      if (!ja) {
        drop("no_translation");
        continue;
      }
      // 型の字を写しただけの訳（の を抜いても同じ字 — 洗髒杯子）、読む人の言語でない訳。
      const bare = (x: string) => translationKey(x).replace(/的/gu, "");
      if (bare(ja) === bare(text) || !readerText(ja, ctx.readerLang, text)) {
        drop("translation_language");
        continue;
      }
    }
    if (seenText.has(text)) {
      drop("duplicate");
      continue;
    }
    const jaKey = translationKey(ja);
    if (jaKey && seenJa.has(jaKey)) {
      drop("duplicate_translation");
      continue;
    }
    seenText.add(text);
    if (jaKey) seenJa.add(jaKey);
    kept.push(tidyForStorage({ ...c, parts }, ctx));
    if (kept.length >= MAX_CHUNKS) break;
  }
  return { kept, dropped };
}

/** 記録用の一行（語・落とした数・理由）。語の中身は入れない。 */
export function describeChunkGate(result: ChunkGateResult): string {
  const reasons = new Map<ChunkDropReason, number>();
  for (const d of result.dropped) reasons.set(d.reason, (reasons.get(d.reason) ?? 0) + 1);
  const tail = [...reasons.entries()].map(([r, n]) => `${r}×${n}`).join(", ");
  return `kept ${result.kept.length}, dropped ${result.dropped.length}${tail ? ` (${tail})` : ""}`;
}

/**
 * 別の AI でもう一度見るか（`AI_CHUNK_VERIFY`。既定は off。`chunk-verify.server.ts` の注）。
 * ここ（純粋な所）に置くのは、画面の束にも入る `ai.functions.ts` から `.server.ts` を静的に読まないため。
 */
export type ChunkVerifyMode = "off" | "inline";

export function chunkVerifyMode(
  env: Record<string, string | undefined> = typeof process === "undefined" ? {} : process.env,
): ChunkVerifyMode {
  return (env.AI_CHUNK_VERIFY ?? "").trim().toLowerCase() === "inline" ? "inline" : "off";
}
