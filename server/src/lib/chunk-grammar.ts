import { posGroup, type PosGroup } from "./pos";
import { normalizeTargetLanguage } from "./target-lang";
import type { ChunkPart } from "./extras";

/**
 * **返ってきた型を、画面に出す前に正す**（オーナー指示 2026-09-29「チャンクの動詞の加熱が
 * なぜか点線になってる。点線は汎用性があるチャンクのなかの入れ替え可能な具体的なものにする」
 * 「滷味＋入味 很がない。実際にネイティブが使う形で表示して。これは文法的に正しくない。
 * これは致命的」）。
 *
 * 指示文でも頼んでいるが（`ai.functions.ts` の `formulaChunkRule`）、**保存済みの語**と
 * **指示が守られなかった回**の両方に効くよう、描く直前にもここを通す。
 */

/**
 * 入れ替えてよい所の品詞 — **具体的な物**（名詞）と、その数え方（量詞）。
 * これに加えて台湾華語の**程度の語**（`DEGREE_CHOICES`）も入れ替えられる
 * （チャンクの表示ルール C5。iOS `docs/chunk-rules.md`）。
 */
const SWAPPABLE: ReadonlySet<PosGroup> = new Set(["n", "m"]);

/**
 * **程度の語の入れ替え候補**（オーナー指示 2026-10-01「マンゴーだったら基本的に甘いって
 * よく言うよね。でもとても甘いのか、少し甘いのかは置き換え可能だよね。このように程度も
 * 変更できるようにして」）。よく使う順。否定（不・不太）は入れない — 「とても甘い」の
 * 1語を替えても「甘くない」にはならず、訳が壊れる。
 */
export const DEGREE_CHOICES = ["很", "超", "非常", "有點", "蠻"] as const;

/** 程度の語の意味（読む人の言語）。型の訳の中で、その語に当たる部分と同じ書き方。 */
const DEGREE_GLOSS: Record<string, { ja: string; en: string }> = {
  很: { ja: "とても", en: "very" },
  超: { ja: "すごく", en: "super" },
  非常: { ja: "非常に", en: "extremely" },
  有點: { ja: "ちょっと", en: "a little" },
  蠻: { ja: "わりと", en: "pretty" },
  好: { ja: "すごく", en: "so" },
};

/** 中国語を読む人には、その語そのもの（訳すと同じ字になる）。 */
export function degreeGloss(word: string, reader?: string | null): string {
  const w = word.trim();
  const g = DEGREE_GLOSS[w];
  if (!g) return "";
  if (reader === "en") return g.en;
  if (reader && normalizeTargetLanguage(reader).startsWith("zh")) return w;
  return g.ja;
}

function isDegreeChoice(part: ChunkPart): boolean {
  return (DEGREE_CHOICES as readonly string[]).includes(part.text.trim());
}

/**
 * 点線（入れ替え可能）として描いてよいか。
 *
 * - 名詞・量詞であること（動詞・形容詞・副詞は入れ替えの枠にしない — 「加熱」が点線に
 *   なっていたのは AI が動詞に `slot` を付けたため）
 * - ほかの具体語（`alts`）が1つ以上あること（押しても何も出ない点線は作らない）
 */
export function isSwappableSlot(part: ChunkPart, language?: string | null): boolean {
  if (!part.slot) return false;
  const alts = (part.alts ?? []).filter((a) => a.text.trim() && a.text.trim() !== part.text.trim());
  if (!alts.length) return false;
  const pos = (part.pos ?? "").trim();
  // 品詞が空の古い札は、alts が在れば入れ替えの札として扱う（前の見た目を保つ）。
  if (!pos) return true;
  if (SWAPPABLE.has(posGroup(pos))) return true;
  // 程度の語（很 → 超・非常・有點・蠻）。動詞・形容詞・ほかの副詞は入れ替えない（C5）。
  return normalizeTargetLanguage(language).startsWith("zh") && isDegreeChoice(part);
}

/** 状態動詞の前に立つ程度・否定の語。これが既に在れば 很 を足さない。 */
const DEGREE = [
  "很",
  "好",
  "超",
  "太",
  "真",
  "非常",
  "蠻",
  "滿",
  "挺",
  "比較",
  "更",
  "最",
  "有點",
  "有一點",
  "不",
  "沒",
  "還",
  "特別",
  "相當",
  "越來越",
  "這麼",
  "那麼",
  "多",
];

/** 述語になる状態動詞か（限定用法だけの `Vs-attr`、目的語を取る `Vst` は除く）。 */
function isPredicateStative(pos: string): boolean {
  const p = pos.trim();
  if (p === "Vs-attr" || p === "Vst") return false;
  return posGroup(p) === "vs";
}

function startsWithDegree(text: string): boolean {
  const t = text.trim();
  return DEGREE.some((d) => t.startsWith(d));
}

/**
 * **台湾華語の「名詞＋形容詞」の型に 很 を補う。**
 *
 * 台湾華語では形容詞（状態動詞）を述語にするとき、裸では言わない — 「滷味入味」は
 * 対比の含みが付いた不自然な形で、ネイティブは「滷味很入味」と言う。型が
 * 「名詞 ＋ 状態動詞」で終わっていて、間に程度・否定の語が無いときだけ 很 を入れる。
 *
 * 狭く当てる: 最後の札が述語の状態動詞で、その直前が名詞のときだけ。
 * 「好吃的＋滷味」（限定用法）や「滷味＋很＋入味」（既に在る）は触らない。
 */
export function withDegreeAdverb(parts: ChunkPart[], language?: string | null): ChunkPart[] {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return parts;
  if (parts.length < 2) return parts;
  const last = parts[parts.length - 1];
  const prev = parts[parts.length - 2];
  if (!isPredicateStative(last.pos ?? "")) return parts;
  if (posGroup(prev.pos ?? "") !== "n") return parts;
  if (startsWithDegree(last.text)) return parts;
  if (parts.some((p) => posGroup(p.pos ?? "") === "adv")) return parts;
  return [...parts.slice(0, -1), { text: "很", pos: "Adv" }, last];
}

/**
 * **1語として使われる語を分けない**（チャンクの表示ルール C7。オーナー指示 2026-10-01
 * 「芒果冰のようにひとかたまりとして普段扱われるものはチャンクを分けなくていい」）。
 *
 * 台湾華語で学ぶ語と隣り合った名詞は1語になる（芒果＋冰 → 芒果冰、台灣＋芒果 → 台灣芒果）。
 * 四角が1つだけになった型は「語」であって使い方ではない — `refineUsageChunks` が落とす。
 */
export function mergeCompounds(
  parts: ChunkPart[],
  headword: string,
  language?: string | null,
): ChunkPart[] {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return parts;
  const head = headword.trim();
  if (!head) return parts;
  const out: ChunkPart[] = [];
  for (const p of parts) {
    const last = out[out.length - 1];
    if (
      last &&
      // 名詞の記号（N…）どうしだけ。古い役割の記号（S/O）は名詞句なので合わせない。
      /^N/i.test((last.pos ?? "").trim()) &&
      /^N/i.test((p.pos ?? "").trim()) &&
      (last.text.includes(head) || p.text.includes(head)) &&
      [...(last.text + p.text)].length <= 6
    ) {
      out[out.length - 1] = { text: last.text + p.text, pos: last.pos };
    } else {
      out.push(p);
    }
  }
  return out;
}

/**
 * 程度の語を入れ替えられる札にする（C5）。AI が候補を付けていない回（補った 很 を含む）は、
 * よく使う程度の語と、その意味（読む人の言語）を付ける。学ぶ語そのものには付けない（C2）。
 */
function withDegreeSlots(
  parts: ChunkPart[],
  headword: string,
  reader?: string | null,
): ChunkPart[] {
  return parts.map((p) => {
    if (!isDegreeChoice(p) || (headword && p.text.includes(headword))) return p;
    const text = p.text.trim();
    return {
      ...p,
      slot: true,
      ja: p.ja?.trim() ? p.ja : degreeGloss(text, reader),
      alts: p.alts?.length
        ? p.alts
        : DEGREE_CHOICES.filter((d) => d !== text).map((d) => ({
            text: d,
            ja: degreeGloss(d, reader),
          })),
    };
  });
}

/**
 * 区切りの記号だけの札（`+` `＋` `・` `/` `／` `|`、空白）。札ではなく継ぎ目の書き方。
 */
const SEPARATOR_ONLY = /^[\s+＋・･/／|｜]*$/u;

/**
 * 区切りとしての `+` か。全角の `＋` はいつも区切り。半角の `+` は、隣が英字・数字・`+` の
 * 時は語の一部として残す（`C++` `Wi-Fi+` を割らない）。
 */
function isSeparatorPlus(text: string, i: number): boolean {
  const ch = text[i];
  if (ch === "＋") return true;
  if (ch !== "+") return false;
  const near = /[A-Za-z0-9+]/;
  return !near.test(text[i - 1] ?? "") && !near.test(text[i + 1] ?? "");
}

/** 区切りの `+` で切る。区切りが無ければ1つだけの配列（元の字のまま）。 */
function splitOnSeparatorPlus(text: string): string[] {
  const out: string[] = [];
  let cur = "";
  for (let i = 0; i < text.length; i++) {
    if (isSeparatorPlus(text, i)) {
      out.push(cur);
      cur = "";
    } else {
      cur += text[i];
    }
  }
  out.push(cur);
  return out.map((s) => s.trim()).filter((s) => s.length > 0);
}

/**
 * **「+」を札にしない**（オーナー報告 2026-10-08「使い方チャンクで 牛蒡 [+] 炒 のように
 * + が1つの札で出る」）。
 *
 * 指示文の例が「跟＋男朋友＋吵架」と `＋` で書いてあるので、AI がその `＋` を
 * パーツとして返す回がある。描く前に:
 * - 区切りの記号だけの札（`+` `＋` `・` `/` `／`、空白）は落とす
 * - 「牛蒡+炒」のように `+` を含む札は、そこで切って別々の札にする
 *   （切った札は品詞だけ受け継ぐ。入れ替えの候補・意味は元の札全体の物なので付けない）
 *
 * **保存済みの語**にも効くよう、生成の後ではなく描く直前（`tidyUsageParts`・
 * `refineUsageChunks`）に通す。何度通しても同じ結果。
 */
export function withoutSeparatorParts(parts: ReadonlyArray<ChunkPart>): ChunkPart[] {
  const out: ChunkPart[] = [];
  for (const p of parts) {
    if (!p) continue;
    const text = p.text ?? "";
    if (SEPARATOR_ONLY.test(text)) continue;
    const pieces = splitOnSeparatorPlus(text);
    if (pieces.length === 0) continue;
    if (pieces.length === 1) {
      // 端に付いた `+` だけを落とした（「炒+」）。札の中身は同じなので他の欄は残す。
      out.push(pieces[0] === text ? p : { ...p, text: pieces[0] });
      continue;
    }
    for (const piece of pieces) out.push({ text: piece, pos: p.pos ?? "" });
  }
  return out;
}

/** 使い方の型（`usage_chunks`）を画面・音声に出す前の形にする。何度通しても同じ結果。 */
export function tidyUsageParts(
  rawParts: ChunkPart[],
  language?: string | null,
  opts: { headword?: string; reader?: string | null } = {},
): ChunkPart[] {
  const zh = normalizeTargetLanguage(language).startsWith("zh");
  const parts = withoutSeparatorParts(rawParts);
  const merged = opts.headword ? mergeCompounds(parts, opts.headword, language) : parts;
  const withDegree = withDegreeAdverb(merged, language);
  return zh ? withDegreeSlots(withDegree, opts.headword ?? "", opts.reader) : withDegree;
}

/**
 * **語を入れ替えた型の訳**（R20「点線のなかのほかの単語をタップしたら、もとの単語と同じように
 * 訳が表示され」）。訳の中で元の語に当たる所を、入れ替えた語の意味に差し替える。
 *
 * 元の語に当たる所は、① その語の意味（`part.ja`。新しいカード）、② 語そのもの（「豆干の滷味を
 * 買う」のように訳にも同じ字で出る語）の順に探す。見つからない時は訳を作り替えず、
 * 「元の訳（元の語 → 入れ替えた語: 意味）」の形で、何を替えたかが分かるように出す。
 */
export function swappedTranslation(
  translation: string | null | undefined,
  parts: ChunkPart[],
  pick: Record<number, number>,
): string {
  let out = (translation ?? "").trim();
  const notes: string[] = [];
  for (const [key, k] of Object.entries(pick)) {
    const i = Number(key);
    const part = parts[i];
    const alt = k >= 0 ? part?.alts?.[k] : undefined;
    if (!part || !alt) continue;
    const to = (alt.ja || alt.text).trim();
    const from = [part.ja?.trim(), part.text.trim()].find((f) => f && out.includes(f));
    if (from) out = out.replace(from, to);
    else notes.push(`${part.text} → ${alt.text}${alt.ja ? `: ${alt.ja}` : ""}`);
  }
  return notes.length ? `${out}（${notes.join("、")}）` : out;
}

/**
 * 目的語を取る動詞の後ろに付いて、その動詞を「裸」でなくする字（結果・方向・様態・アスペクト）。
 * これで終わる動詞（賣完・吃光・切好・煮熟）は「名詞＋動詞」でも話題の形として言える。
 */
const VERB_COMPLETION = /[了過著完好掉光到住走開起來去成熟爛死錯對滿夠]$/u;

/**
 * **崩れた型**か（オーナー報告 2026-10-09「嘴邊肉＋切 / 嘴邊肉をする」）。
 *
 * 屋台の頼み方「嘴邊肉切一盤」から、型に量詞を使わない決まりに合わせて「一盤」だけを抜いた
 * 形が返ってきた。中国語は「動詞＋目的語」の順なので、「嘴邊肉切」は成り立たない
 * （言うなら「切嘴邊肉」か「嘴邊肉切一盤」）。訳も見出し語を写した「嘴邊肉をする」だった。
 * 指示文でも頼んでいるが（`ai.functions.ts` の `CHUNK_INTEGRITY_RULE`）、保存済みの語にも
 * 効くよう表示の側でも落とす。**狭く当てる**:
 *
 * 1. 台湾華語で、札が2つだけ・前が学ぶ語の名詞・後ろが目的語を取る動詞（pos `V`）の裸の形
 *    （1〜2字で、結果・アスペクトの字で終わらない）。「芒果＋很＋甜」「跟＋朋友＋見面」
 *    「切＋嘴邊肉」「珍珠奶茶＋半糖少冰」は当たらない。
 * 2. 訳が訳になっていない: 学ぶ語をそのまま写して「をする」「する」「をやる」を付けただけ、
 *    または訳が学ぶ語そのもの（札が2つ以上ある型の訳として）。日本語を学ぶ語には当てない
 *    （日本語の語は訳の中にそのまま出てよい）。
 */
export function isBrokenUsageChunk(
  chunk: { parts?: ReadonlyArray<ChunkPart> | null; ja?: string | null },
  headword: string,
  language?: string | null,
): boolean {
  const head = headword.trim();
  if (!head) return false;
  const lang = normalizeTargetLanguage(language);
  const parts = withoutSeparatorParts(chunk.parts ?? []).filter((p) => p.text.trim());
  if (lang.startsWith("zh") && parts.length === 2) {
    const [noun, verb] = parts;
    const vText = verb.text.trim();
    if (
      noun.text.includes(head) &&
      posGroup(noun.pos ?? "") === "n" &&
      (verb.pos ?? "").trim() === "V" &&
      !vText.includes(head) &&
      [...vText].length <= 2 &&
      !VERB_COMPLETION.test(vText)
    )
      return true;
  }
  if (lang !== "ja" && parts.length >= 2) {
    const ja = (chunk.ja ?? "")
      .replace(/[（(][^）)]*[）)]/gu, "")
      .replace(/\s+/g, "")
      .replace(/[。．.!！]$/u, "");
    if (!ja) return false;
    if (ja === head) return true;
    const escaped = head.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (new RegExp(`^[〜~]?${escaped}(?:を|に)?(?:する|します|やる|行う|おこなう)$`, "u").test(ja))
      return true;
    if (/^[〜~…]+(?:を|に)?(?:する|します|やる)$/u.test(ja)) return true;
  }
  return false;
}
