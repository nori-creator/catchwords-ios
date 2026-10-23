/**
 * **その語の「どの意味の写真か」**を決め、確かめる（純粋な部分）。
 *
 * ## オーナー報告 2026-10-08 ②
 * > 「レンコンを文字検索したのに、蓮の花の画像しか出てこない。ユーザーが検索した日本語から
 * >  正確にユーザーが見たい、ユーザーが調べてる単語と完全に一致するものを画像表示して。」
 *
 * 調べると、文字で調べた語の札の絵は**カードの AI が答える前に**探し始めていた
 * （候補を押すとすぐカードの画面に移り、`useTextStickerImage` が語だけを鍵に1回だけ探す）。
 * その時はまだ `extras.image_query`（`lotus root`）が無いので、意味の欄の日本語
 * （`レンコン` / `蓮根`）で探していた。英語の説明で引く写真の出所では `蓮` → `lotus` の花に
 * 当たる。後からカードが届いても探し直さず、外れの1枚がそのまま札・図鑑の仮画像になった。
 *
 * ## 直し方（3段）
 * 1. **探す前に意味を決める**（`resolve`）: 英語の検索語が無い時は、サーバで
 *    (a) 共有の語の行（`words.extras.image_query`）→ (b) 小さな AI の呼び出し、の順に
 *    英語の検索語と**避ける語**（`flower` `pond` …）を決めてから探す。覚えておく。
 * 2. **説明で並べ・捨てる**（`image-search-rank.ts`）。
 * 3. **説明で言い切れない時だけ絵を見る**（`verify`）: 上位の小さな絵（最大 6 枚）を
 *    写真の読める AI に見せ、「その意味の物が写っているか」を答えさせる。外れは捨てる。
 *    失敗・時間切れ（約 4 秒）なら 2. の順のまま。
 *
 * ## オーナー報告 2026-10-09「嘴邊肉の画像が明らかに英語で検索された画像」
 * - 先に**学習言語の見出し語そのもの**で探す（`image-sources.ts` / `image-providers.ts`）。
 * - 食べ物・料理（と棚の分からない語）は英語の題を「確か」と見なさない（`isStrictSense`）。
 *   学習言語の見出し語そのものでない写真は必ず絵を見て確かめ、確かめられない物は出さない。
 * - 確かめの指示は「**主役が**その物そのものか」（材料として入っている別の料理は外れ）。
 * - 全体の持ち時間（`SEARCH_BUDGET_MS`）の中で確かめる。
 *
 * AI を使う所はどちらも、同意（`assertAiConsent`）と回数の枠（`image_sense`）を通る。
 * 通らなければ AI を使わずに 2. だけで続ける（画像の節は止めない）。
 *
 * ここには外の世界に触れるものを入れない（文を組む・読む・覚えるだけ）。呼ぶのは
 * `image-sense.server.ts`、使うのは `images.functions.ts`。
 */

import { cleanImageQuery } from "./hero-image";
import { isConfidentMatch, type RankContext, type RankableImage } from "./image-search-rank";

/** その語の写真の意味。 */
export type ImageSense = {
  /** 写真の出所に投げる英語（1〜4語）。 */
  query: string;
  /** 写っていたら外れの英語（花・池など）。 */
  avoid: string[];
  /** 絵を確かめる時に AI に渡す、写っているべき物の短い説明（英語）。 */
  sense?: string;
  /**
   * 学習言語の、意味を絞る短い語（嘴邊肉 → `黑白切`）。学習言語の出所を引き直す時と、
   * 絵を確かめる時に使う（オーナー報告 2026-10-09）。無ければ無し（古い覚えの形もそのまま読める）。
   */
  context?: string;
  /** 学習言語での同じ語の別の書き方（簡体字 `嘴边肉` など。最大2つ）。 */
  variants?: string[];
};

/** 避ける語の上限（多すぎると正しい写真まで落ちる）。 */
export const MAX_AVOID_TERMS = 8;
/** 絵を見て確かめる枚数の上限（AI に送る絵の数 = 費用と待ち時間）。 */
export const VERIFY_MAX_IMAGES = 6;
/** 絵を見て確かめるのに待つ上限（ms）。過ぎたら確かめずに返す。 */
export const VERIFY_TIMEOUT_MS = 4_000;
/** 意味を決める AI を待つ上限（ms）。 */
export const RESOLVE_TIMEOUT_MS = 3_500;
/**
 * 1回の検索の全体の持ち時間（ms）。画面は最大 8 秒待つ（`CATCH_IMAGE_WAIT_MS`）ので、
 * サーバはその手前で必ず返す。確かめ（`verify`）はこの残りの時間しか使わない。
 */
export const SEARCH_BUDGET_MS = 6_800;
/** 出所1つに許す時間（ms）。 */
export const SOURCE_TIMEOUT_MS = 2_500;
/** 残りがこれより短ければ絵を確かめない（間に合わない）。 */
export const VERIFY_MIN_MS = 1_500;

/**
 * **英語の説明で「確か」と言わない棚**（オーナー報告 2026-10-09「嘴邊肉 → パエリア」）。
 * 食べ物・料理は、英語の題に材料の名前（`pork cheek`）が入っていても別の料理のことが多い。
 * この棚（と、棚の分からない語）は、学習言語の見出し語そのものの写真でなければ必ず絵を見て確かめ、
 * 確かめられない写真は出さない。
 */
const STRICT_CATEGORIES = new Set(["food", "dessert", "drink", "vegetable", "fruit"]);

export function isStrictSense(category: string | null | undefined): boolean {
  const c = (category ?? "").trim().toLowerCase();
  return !c || c === "other" || STRICT_CATEGORIES.has(c);
}

/** 英語の検索語ではない（漢字・かな・ハングルなどが入っている）か。 */
export function needsSenseResolution(query: string): boolean {
  const q = query.trim();
  if (!q) return false;
  return /[^\p{Script=Latin}\p{N}\p{P}\p{Z}\p{S}]/u.test(q) || !/[a-z]/i.test(q);
}

/** 避ける語を揃える（英小文字・短い語句だけ・重複なし・上限まで）。 */
export function cleanAvoidTerms(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const v of raw) {
    if (typeof v !== "string") continue;
    const t = v
      .toLowerCase()
      .replace(/["'“”‘’]/g, "")
      .replace(/\s+/g, " ")
      .trim();
    if (t.length < 2 || t.length > 24 || !/^[a-z][a-z -]*$/.test(t) || t.split(" ").length > 2)
      continue;
    if (!out.includes(t)) out.push(t);
    if (out.length >= MAX_AVOID_TERMS) break;
  }
  return out;
}

/** 札の extras から避ける語（`image_avoid`）を読む。形が違えば空。 */
export function imageAvoidOf(extras: unknown): string[] {
  if (!extras || typeof extras !== "object") return [];
  return cleanAvoidTerms((extras as { image_avoid?: unknown }).image_avoid);
}

/** AI の答え（JSON を読んだ物）から意味を取り出す。使えなければ null。 */
export function parseImageSense(raw: unknown): ImageSense | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as { query?: unknown; avoid?: unknown; sense?: unknown };
  const query = cleanImageQuery(typeof r.query === "string" ? r.query : "");
  if (!query || needsSenseResolution(query)) return null;
  const sense =
    typeof r.sense === "string" ? r.sense.replace(/\s+/g, " ").trim().slice(0, 160) : "";
  const context = cleanLearningTerm((raw as { context?: unknown }).context);
  const variants = Array.isArray((raw as { variants?: unknown }).variants)
    ? [
        ...new Set(
          ((raw as { variants: unknown[] }).variants ?? [])
            .map(cleanLearningTerm)
            .filter((v): v is string => !!v),
        ),
      ].slice(0, 2)
    : [];
  return {
    query,
    avoid: cleanAvoidTerms(r.avoid),
    ...(sense ? { sense } : {}),
    ...(context ? { context } : {}),
    ...(variants.length ? { variants } : {}),
  };
}

/** 学習言語の短い語（絞る語・別の書き方）。英字だけ・長い・文の物は使わない。 */
function cleanLearningTerm(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const t = raw
    .replace(/["'“”‘’「」『』]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!t || t.length > 12 || /[。.!?！？,，、]/.test(t)) return null;
  if (!/[^\p{Script=Latin}\p{N}\p{P}\p{Z}\p{S}]/u.test(t)) return null;
  return t;
}

/** 意味を決める AI への指示。 */
export function imageSensePrompt(word: {
  headword: string;
  meaning?: string | null;
  language?: string | null;
}): string {
  const meaning = (word.meaning ?? "").trim();
  return [
    "You choose stock-photo search terms for a vocabulary flashcard.",
    `Word: "${word.headword}" (language: ${word.language || "unknown"}).`,
    meaning ? `The learner's own gloss of the word: "${meaning}".` : "",
    "Decide the exact everyday sense the learner means (for plants eaten as food, the edible part as it is sold or cooked — e.g. レンコン/蓮藕 → lotus root, not the lotus flower; 牛蒡 → burdock root; 竹筍 → bamboo shoot; 落花生 → peanuts; マウス meaning a computer device → computer mouse).",
    "The gloss may be written with the same characters as the word (Japanese 桃 for Chinese 桃) — that is not a hint about the sense. A single-character word means its most common everyday concrete thing (桃 → peach fruit; 杯 → cup), never a place name that contains it (桃園 Taoyuan), a person's name or an organisation.",
    "Return ONLY one JSON object:",
    '{"query": "English photo search terms, 1-4 words, naming that exact thing", ' +
      '"avoid": ["up to 6 lowercase English words that describe look-alike WRONG photos a search would return, e.g. flower, blossom, pond, petal"], ' +
      '"sense": "one short English sentence: what the photo must show (for a dish or food, how it is typically served where the word is used)", ' +
      `"context": "optional: one short term IN THE WORD'S OWN LANGUAGE naming the cuisine/category it belongs to, only if it helps tell it apart in a photo search (e.g. 嘴邊肉 → 黑白切, 滷肉飯 → 小吃); otherwise empty", ` +
      `"variants": ["optional: up to 2 other spellings of the same word in its own language (e.g. simplified 嘴边肉 for traditional 嘴邊肉). If the word is a single character, instead give the everyday multi-character word(s) for this sense in the same language (桃 → 桃子, 水蜜桃; 杯 → 杯子)"]}`,
    'If the word cannot be shown in a photo (abstract or grammatical), return {"query": "", "avoid": [], "sense": ""}.',
  ]
    .filter(Boolean)
    .join("\n");
}

/** 絵を確かめる AI への指示（絵は 0 から順に続けて添える）。 */
export function imageVerifyPrompt(word: {
  headword?: string | null;
  meaning?: string | null;
  language?: string | null;
  sense: ImageSense;
  count: number;
}): string {
  const what = word.sense.sense || word.sense.query;
  return [
    `You check photos for a vocabulary flashcard. ${word.count} images follow, numbered 0 to ${word.count - 1} in order.`,
    word.headword
      ? `The learner is learning the word "${word.headword}"${word.language ? ` (${word.language})` : ""}` +
        (word.meaning ? ` and understands it as "${word.meaning}" (their own gloss).` : ".")
      : "",
    `Target: ${what}` +
      (word.sense.context ? ` (context in the learning language: ${word.sense.context})` : "") +
      ".",
    word.sense.avoid.length
      ? `Reject photos whose main subject is instead: ${word.sense.avoid.join(", ")}.`
      : "",
    "An image matches ONLY if its MAIN subject is exactly this target, as a learner of that word would picture it. " +
      "Reject it if the target is merely an ingredient or a small part of a different dish or thing " +
      "(e.g. a paella, stew, sandwich or platter that happens to contain it), if it shows a different dish or a similar-looking but different thing, " +
      "if it is a menu, sign or text only, a drawing or diagram, or anything unrelated. " +
      "Also reject posters, flyers, banners, notices and event or association pictures (even when the word appears in a place or organisation name, e.g. 桃 in 桃園), " +
      "and photos whose main subject is a person or people (portraits, models, a girl holding something) unless the target is a person, a body part or an action people do.",
    'If two matching images are the same photo or near-identical, put only the first in "match" and the others in "duplicate".',
    'Return ONLY JSON: {"match": [indices of matching images], "duplicate": [indices]}',
  ]
    .filter(Boolean)
    .join("\n");
}

/** 確かめた答えを読む（`{"match":[0,2]}`）。読めなければ null（確かめなかった扱い）。 */
export function parseVerifyVerdict(raw: unknown, count: number): Set<number> | null {
  if (!raw || typeof raw !== "object") return null;
  const m = (raw as { match?: unknown }).match;
  if (!Array.isArray(m)) return null;
  const out = new Set<number>();
  for (const v of m) {
    const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
    if (Number.isInteger(n) && n >= 0 && n < count) out.add(n);
  }
  return out;
}

/** 確かめた答えの「同じ写真」（`{"duplicate":[3]}`）。無ければ空。 */
export function parseVerifyDuplicates(raw: unknown, count: number): Set<number> {
  const d = raw && typeof raw === "object" ? (raw as { duplicate?: unknown }).duplicate : null;
  const out = new Set<number>();
  if (!Array.isArray(d)) return out;
  for (const v of d) {
    const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
    if (Number.isInteger(n) && n >= 0 && n < count) out.add(n);
  }
  return out;
}

/**
 * 絵を見て確かめる必要があるか（オーナー報告 2026-10-09 から）。
 *
 * - 上位が**全部学習言語の見出し語そのもの**（`exact`）なら要らない
 * - 厳しい棚（食べ物・料理・棚の分からない語。`isStrictSense`）では、それ以外なら必ず確かめる
 *   （英語の題の `pork cheek` は「パエリアの材料」のことがある）
 * - それ以外の棚は今までどおり: 先頭が説明で確かなら要らない
 */
export function needsVerification(
  ranked: ReadonlyArray<RankableImage & { source?: string; exact?: boolean }>,
  ctx: RankContext,
  strict: boolean,
): boolean {
  const photos = ranked.filter((c) => c.source !== "ai");
  if (photos.length === 0) return false;
  if (photos.slice(0, VERIFY_MAX_IMAGES).every((c) => c.exact)) return false;
  if (strict) return true;
  return !photos[0].exact && !isConfidentMatch(photos[0].text, ctx);
}

/**
 * 絵を見て確かめる必要があるか。**説明で確かと言える写真が先頭に在れば要らない**
 * （AI を呼ばない — 費用と待ち時間を、言い切れない語だけに使う）。
 */
export function shouldVerify(
  ranked: ReadonlyArray<RankableImage & { source?: string }>,
  ctx: RankContext,
): boolean {
  const photos = ranked.filter((c) => c.source !== "ai");
  if (photos.length === 0) return false;
  return !isConfidentMatch(photos[0].text, ctx);
}

/**
 * 確かめた答えで並べ直す: **合っていた物を先に**（元の順のまま）、確かめていない物を後ろに、
 * 外れと言われた物は捨てる。`checked` は確かめた候補（先頭からの位置）、`matched` は合っていた物。
 */
export function applyVerdict<T>(
  candidates: ReadonlyArray<T>,
  checked: ReadonlyArray<number>,
  matched: ReadonlySet<number>,
  opts: {
    /** 確かめていない物を残すか（無ければ全部残す）。厳しい棚では見出し語そのものだけ残す。 */
    keepUnchecked?: (c: T) => boolean;
    /** 同じ写真と言われた物（捨てる）。 */
    duplicates?: ReadonlySet<number>;
  } = {},
): T[] {
  const checkedSet = new Set(checked);
  const ok: T[] = [];
  const rest: T[] = [];
  candidates.forEach((c, i) => {
    if (opts.duplicates?.has(i)) return;
    if (!checkedSet.has(i)) {
      if (!opts.keepUnchecked || opts.keepUnchecked(c)) rest.push(c);
    } else if (matched.has(i)) ok.push(c);
  });
  return [...ok, ...rest];
}

/** 小さな覚え（古い物から捨てる）。サーバの1つの実行の間だけ持つ。 */
export class SmallCache<V> {
  private map = new Map<string, { at: number; v: V }>();
  constructor(
    private max = 500,
    private ttlMs = 24 * 60 * 60 * 1000,
  ) {}
  get(key: string, now = Date.now()): V | undefined {
    const hit = this.map.get(key);
    if (!hit) return undefined;
    if (now - hit.at > this.ttlMs) {
      this.map.delete(key);
      return undefined;
    }
    // 使った物を新しい側へ。
    this.map.delete(key);
    this.map.set(key, hit);
    return hit.v;
  }
  set(key: string, v: V, now = Date.now()): void {
    this.map.delete(key);
    this.map.set(key, { at: now, v });
    while (this.map.size > this.max) {
      const oldest = this.map.keys().next().value;
      if (oldest === undefined) break;
      this.map.delete(oldest);
    }
  }
  clear(): void {
    this.map.clear();
  }
}

/** 意味の覚えの鍵（言語・語・意味）。 */
export function senseKey(word: {
  headword: string;
  meaning?: string | null;
  language?: string | null;
}): string {
  return `${word.language ?? ""}\u0000${word.headword.trim()}\u0000${(word.meaning ?? "").trim()}`;
}

/** 絵の確かめの覚えの鍵（どの語の・何を探したか・どの絵か）。 */
export function verdictKey(sense: ImageSense, url: string, headword?: string | null): string {
  return `${(headword ?? "").trim()}\u0000${sense.query}\u0000${sense.avoid.join(",")}\u0000${url}`;
}
