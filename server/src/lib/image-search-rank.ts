/**
 * ネットの画像の候補を**学ぶ人が思い浮かべる物の順に**並べ直す。
 *
 * ## オーナー報告 2026-10-08
 * > 「牛蒡（ゴボウ）を検索すると、自動の画像も候補も花の写真しか出ない。」
 *
 * 2つ重なっていた:
 * 1. 探す言葉が意味の欄の日本語（`ゴボウ`）そのままで、写真の出所（Unsplash・コモンズ）は
 *    英語の説明で引くので、植物としてのゴボウ（花・野草）に当たっていた。
 *    → カードを作る時に AI が**画像検索用の短い英語**（`extras.image_query`、例
 *    `burdock root`）も返すようにした（同じ呼び出しに1欄足すだけ。追加の AI 呼び出しは無い）。
 * 2. 返ってきた順に並べていたので、外れの写真が先頭（自動の1枚）になっていた。
 *    → 返ってきた説明・題・タグを見て、**探した言葉に合う物を前へ、花・図版を後ろへ**。
 *
 * ## 特定の語に合わせない
 * 「牛蒡なら花を落とす」のような語ごとの表は持たない。見るのは
 * - 探した言葉（とその語の棚 `category_key`）が説明に出てくるか
 * - 探した言葉も棚も「花・植物」と言っていないのに、花の写真か
 * - 写真でない図版（標本・挿絵・図）か
 * だけ。花を探している語（`桜` の棚 `flower`、`cauliflower`）は花を下げない。
 *
 * ## オーナー報告 2026-10-08 ②「レンコンを文字検索したのに蓮の花の画像しか出てこない」
 * 足りなかった物:
 * - **外れを後ろへ回すだけで、捨てなかった。** 出所が花の写真しか返さないと、後ろへ回した
 *   花がそのまま先頭（自動の1枚）になる。→ 外れの手がかりがはっきり在る物は**捨てる**
 *   （`selectImageCandidates`）。残りが無ければ、別の出所（コモンズ）・AI の絵に回す。
 * - **語ごとの「違う物」を知らなかった。** 花の語だけを見ていたので、`lotus pond`（池）や
 *   `bamboo forest`（竹林）は外れにならなかった。→ AI が返す**避ける語**（`image_avoid`。
 *   レンコンなら `flower` `pond` `petal`）と、棚ごとの「食べ物なのに畑・池・林の写真」を見る。
 * - **語の組（`lotus root`）を語ごとにしか数えなかった。** `lotus` だけの写真（花）も半分の点を
 *   もらっていた。→ 組がそのまま出てくる物に上乗せし、組の語が揃っている物だけを
 *   「確か」（`isConfidentMatch`）と見る。確かな物が無い時だけ、絵を見て確かめる
 *   （`image-sense.ts`）。
 *
 * 外の世界に触れるものを入れない（試験から素の値で確かめる）。
 */

/** 並べ直す前の候補。`text` は題・説明・タグをつないだ物（無ければ空）。 */
export type RankableImage = { text?: string };

export type RankContext = {
  /** 実際に投げた検索語。 */
  query: string;
  /** その語の棚（`category.ts` の `CATEGORY_KEYS`）。分からなければ無し。 */
  category?: string | null;
  /**
   * **写っていたら外れ**の英語（`extras.image_avoid`。レンコンなら `flower` `pond`）。
   * 検索語に入っている語は数えない（花を探す語で花を落とさない）。
   */
  avoid?: ReadonlyArray<string> | null;
};

/** 花・植物そのものを写していてよい棚。ここでは花の写真を下げない。 */
const PLANT_CATEGORIES = new Set(["plant", "flower", "nature", "decoration", "art", "color"]);

/** 食べ物の棚。畑・池・林・木に生えている姿は「食べる物」の写真ではない。 */
const FOOD_CATEGORIES = new Set(["vegetable", "fruit", "food", "dessert", "drink"]);

/**
 * 食べ物の語で外れになる、生えている所・草木の姿の手がかり。葉（`cabbage leaves`）・`林檎` の
 * 林は外れではないので入れない。
 */
const GROWING_WORDS =
  /\b(ponds?|fields?|forests?|groves?|gardens?|meadows?|orchards?|plantations?|trees?|shrubs?|seedlings?|wild ?plants?|plants?(?!-based))\b|池|畑|竹林|森林|の木/iu;

/** 道具・機械の棚。動物の写真は外れ（マウス → ネズミ）。 */
const ARTIFACT_CATEGORIES = new Set([
  "tech",
  "gadget",
  "appliance",
  "tool",
  "stationery",
  "furniture",
  "kitchenware",
  "vehicle",
  "transport",
  "toy",
  "instrument",
]);

/** 動物の写真の手がかり。 */
const ANIMAL_WORDS =
  /\b(animals?|rodents?|wildlife|pets?|mammals?|fur|furry|whiskers?|rats?|mice)\b|動物|ネズミ|老鼠/iu;

/** 花の写真の手がかり（英語の説明と、日本語・中国語の説明）。 */
const FLOWER_WORDS =
  /\b(flowers?|flowering|blossoms?|blooms?|blooming|inflorescences?|wildflowers?|petals?|florets?)\b|の花|花序|開花|花朵|花卉|野花/iu;

/** 写真でない図版の手がかり。札の主役に据えると何の絵か読めない。 */
const NOT_A_PHOTO_WORDS =
  /\b(herbarium|specimens?|illustrations?|engravings?|drawings?|diagrams?|lithographs?|botanical art)\b|標本|挿絵|図譜|植物画/iu;

/**
 * **主役が物ではない写真**の手がかり（オーナー報告 2026-10-09「桃の写真になぜか鳩の画像が出る」）。
 * 貼り紙・チラシ・看板・催し・団体の告知（`桃園市信鴿協會`）と、人を写した写真（人物・少女）。
 * 語そのものが人・表示・文書の語（棚・検索語）なら数えない。
 */
const POSTER_WORDS =
  /\b(posters?|flyers?|leaflets?|banners?|logos?|screenshots?|signboards?|billboards?|announcements?|association|competition|racing)\b|海報|傳單|宣傳|協會|協会|公告|告示|比賽|大會|大会|活動|ポスター|チラシ|看板/iu;
const PEOPLE_WORDS =
  /\b(portraits?|girls?|boys?|wom[ae]n|m[ae]n|lady|ladies|people|persons?|selfies?|cosplay|cosplayer|models?|actress|actor|idol)\b|少女|女孩|女生|男孩|美女|人物|肖像|寫真|写真集|自拍|模特|コスプレ|女の子|男の子/iu;
const PEOPLE_CATEGORIES = new Set(["person", "family", "job", "face", "body", "hand", "character"]);
const TEXT_CATEGORIES = new Set(["sign", "document", "book", "symbol", "shop", "art"]);

/** 貼り紙・催し・団体の告知の手がかりが在るか。語が表示・文書の語なら数えない。 */
export function hasPosterSignals(text: string | undefined, ctx: RankContext): boolean {
  const t = (text ?? "").toLowerCase();
  if (!t.trim()) return false;
  const category = (ctx.category ?? "").trim().toLowerCase();
  return !TEXT_CATEGORIES.has(category) && !POSTER_WORDS.test(ctx.query) && POSTER_WORDS.test(t);
}

/**
 * 主役が物ではない（貼り紙・催し・人の写真）手がかりが在るか。語がそれ自体を指す時は数えない。
 * 人の写真の手がかりは**学習言語の題・タグ**に使う（`桃` という名前の人の写真）。英語の写真の
 * 説明（`a woman jogging`）は動作の語の正しい写真のことがあるので、そちらは絵を見て確かめる。
 */
export function hasNonSubjectSignals(text: string | undefined, ctx: RankContext): boolean {
  if (hasPosterSignals(text, ctx)) return true;
  const t = (text ?? "").toLowerCase();
  if (!t.trim()) return false;
  const category = (ctx.category ?? "").trim().toLowerCase();
  return !PEOPLE_CATEGORIES.has(category) && !PEOPLE_WORDS.test(ctx.query) && PEOPLE_WORDS.test(t);
}

/** 点に数えない短い語・つなぎの語。 */
const STOP = new Set(["the", "and", "with", "for", "from", "of", "a", "an", "in", "on", "photo"]);

/**
 * 検索語の中で**語の正体を決めない**語（`sliced` `fresh` `vegetable`）。組が揃っているかを
 * 見る時は数えない（`lotus root vegetable sliced` の写真に `sliced` が無くても確か）。
 */
const DESCRIPTIVE = new Set([
  "fresh",
  "sliced",
  "slices",
  "raw",
  "cooked",
  "whole",
  "dish",
  "food",
  "vegetable",
  "vegetables",
  "fruit",
  "isolated",
  "closeup",
  "close-up",
  "japanese",
  "chinese",
  "taiwanese",
  "asian",
]);

/** 英字の語は語ごと、それ以外（漢字・かな）は検索語の塊ごとに数える。 */
function queryTerms(query: string): string[] {
  const q = query.toLowerCase();
  const latin = (q.match(/[a-z][a-z'-]+/g) ?? []).filter((w) => w.length >= 3 && !STOP.has(w));
  const other = q
    .replace(/[a-z0-9'-]+/g, " ")
    .split(/[\s、,，・/]+/u)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return [...new Set([...latin, ...other])];
}

/** 語の正体を決める語（組が揃っているかを見る語）。 */
function coreTerms(query: string): string[] {
  return queryTerms(query).filter((t) => !DESCRIPTIVE.has(t));
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\-]/g, "\\$&");
}

function hasWord(text: string, term: string): boolean {
  if (/^[a-z'-]+$/.test(term)) {
    // 複数形・活用の語尾までは同じ語と見る（root → roots）。
    return new RegExp(`\\b${escapeRe(term)}(s|es)?\\b`, "i").test(text);
  }
  return text.includes(term);
}

/** 英字の組（2語以上）がそのまま並んで出てくるか（`lotus root` → `lotus roots` も可）。 */
function hasPhrase(text: string, terms: string[]): boolean {
  const latin = terms.filter((t) => /^[a-z'-]+$/.test(t));
  if (latin.length < 2) return false;
  const re = latin.map((t) => `${escapeRe(t)}(s|es)?`).join("[\\s-]+");
  return new RegExp(`\\b${re}\\b`, "i").test(text);
}

/** 避ける語を、検索語に入っていない物だけに絞る（花を探す語で花を落とさない）。 */
function effectiveAvoid(ctx: RankContext): string[] {
  const q = ctx.query.toLowerCase();
  return (ctx.avoid ?? [])
    .map((a) => a.trim().toLowerCase())
    .filter((a) => a.length >= 2 && !q.includes(a));
}

/** その候補が「違う物」を写している手がかりの数（0 なら手がかり無し）。 */
function offSenseSignals(t: string, ctx: RankContext): number {
  const query = ctx.query.toLowerCase();
  const category = (ctx.category ?? "").trim().toLowerCase();
  let n = 0;
  const wantsFlowers =
    PLANT_CATEGORIES.has(category) || FLOWER_WORDS.test(query) || /flower|花/u.test(query);
  if (!wantsFlowers && FLOWER_WORDS.test(t)) n++;
  if (FOOD_CATEGORIES.has(category) && !GROWING_WORDS.test(query) && GROWING_WORDS.test(t)) n++;
  if (ARTIFACT_CATEGORIES.has(category) && !ANIMAL_WORDS.test(query) && ANIMAL_WORDS.test(t)) n++;
  for (const a of effectiveAvoid(ctx)) if (hasWord(t, a)) n++;
  return n;
}

/**
 * 候補1つの点。高いほど前に置く。
 *
 * - 探した言葉の語が説明に出てくる: +2 ずつ
 * - 探した語の組（`lotus root`）がそのまま出てくる: さらに +2
 * - 棚の名前（`vegetable` など。棚の鍵は英語）が出てくる: +1
 * - 違う物の手がかり（花・避ける語・食べ物なのに畑や池・道具なのに動物）: -3 ずつ
 * - 写真でない図版: -2
 */
export function imageRelevance(text: string | undefined, ctx: RankContext): number {
  const t = (text ?? "").toLowerCase();
  if (!t.trim()) return 0;
  const query = ctx.query.toLowerCase();
  const terms = queryTerms(query);
  let score = 0;
  for (const term of terms) if (hasWord(t, term)) score += 2;
  if (hasPhrase(t, coreTerms(query))) score += 2;
  const category = (ctx.category ?? "").trim().toLowerCase();
  const categoryWord = category.replace(/_/g, " ");
  if (categoryWord && categoryWord !== "other" && hasWord(t, categoryWord)) score += 1;
  score -= 3 * offSenseSignals(t, ctx);
  if (!NOT_A_PHOTO_WORDS.test(query) && NOT_A_PHOTO_WORDS.test(t)) score -= 2;
  return score;
}

/**
 * **確かにその物の写真か**（説明だけで言い切れるか）。語の正体を決める語が全部出てきて、
 * 違う物の手がかりが1つも無い。確かな物が1枚も無い時だけ、絵を見て確かめる
 * （`image-sense.ts`）・別の出所も探す（`images.functions.ts`）。
 */
export function isConfidentMatch(text: string | undefined, ctx: RankContext): boolean {
  const t = (text ?? "").toLowerCase();
  if (!t.trim()) return false;
  const core = coreTerms(ctx.query.toLowerCase());
  if (core.length === 0) return false;
  if (!core.every((term) => hasWord(t, term))) return false;
  if (offSenseSignals(t, ctx) > 0) return false;
  // 「peach」と書いてあっても、貼り紙・催しの写真は説明だけでは確かと言わない（絵を見て確かめる）。
  if (hasPosterSignals(t, ctx)) return false;
  return !(NOT_A_PHOTO_WORDS.test(t) && !NOT_A_PHOTO_WORDS.test(ctx.query.toLowerCase()));
}

/**
 * 点の高い順に並べ直す。**同じ点なら元の順**（出所は関連の高い順に返すので、それを崩さない）。
 * 説明が1つも無い出所（AI の絵）は 0 点で、元の位置の順を保つ。
 */
export function rankImageCandidates<T extends RankableImage>(
  candidates: ReadonlyArray<T>,
  ctx: RankContext,
): T[] {
  return candidates
    .map((c, i) => ({ c, i, s: imageRelevance(c.text, ctx) }))
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .map((x) => x.c);
}

/**
 * 並べ直して、**外れと分かる物を捨てる**（オーナー報告 2026-10-08 ②）。
 *
 * 捨てるのは点が負の物 — 違う物の手がかり（花・避ける語など）が、探した語に合う手がかりより
 * 強い物。`lotus root` を探して `pink lotus flower in a pond` は捨て、`lotus root and flower`
 * （根も写っている）は残す。説明の無い物（0 点）は捨てない（外れとは言えない）。
 */
export function selectImageCandidates<T extends RankableImage>(
  candidates: ReadonlyArray<T>,
  ctx: RankContext,
): T[] {
  return candidates
    .map((c, i) => ({ c, i, s: imageRelevance(c.text, ctx) }))
    .filter((x) => x.s >= 0)
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .map((x) => x.c);
}

/** 違う物の手がかり（花・避ける語・食べ物なのに畑・道具なのに動物）が在るか。 */
export function hasOffSenseSignals(text: string | undefined, ctx: RankContext): boolean {
  return offSenseSignals((text ?? "").toLowerCase(), ctx) > 0;
}
