import { z } from "zod";
import { ChunkPartSchema } from "./extras";
import { readerText } from "./note-language";
import { looksLikeTargetLanguage } from "./text-language";
import { targetProfile } from "./target-profile";

/**
 * **例文は「その語が使われる場面のパターン」から作る**（オーナー報告 2026-10-15）。
 *
 * > 眼鏡の例文「我戴眼鏡。」の上に「友達が眼鏡をしていないことに気づいたとき」と出た — 場面と文が全く合わない。
 * > ネイティブがその語をよく使う状況・場面・気持ちをパターンに分け、パターンごとにその場面で実際に言う一番自然な
 * > 一文を書く。1つの状況でしか使わない語なら例文は1つでいい。場面の札はその文を言う状況そのものにする。
 * > 文の語彙・文法は設定したレベルに合わせる。
 *
 * ## 食い違いが起きていた2つの道
 * 1. **作る時**: 例文（`example_sentence`）と場面（`extras.example_scene`）を別の欄として頼んでいたので、
 *    モデルが場面を文とは別に考えることがあった。今は1つのパターンの中で「状況 → 文 → その文のための札 →
 *    確かめ」の順に書かせ、札と文を同じ要素に置く（`example_patterns`）。
 * 2. **保存する時**: 共有の行（`words` / `word_explanations`）は**空の欄だけ**埋める。前から在った例文
 *    （「我戴眼鏡。」）の横に、2026-10-14 に足した場面の欄（空だった）だけが**別の生成の札**で埋まっていた。
 *    今は札に「どの文のために書いたか」（`example_scene_for`）を付け、文が違う所には札・パーツ・訳を入れない
 *    （`alignExampleExtras` / `exampleMatchesSentence`）。
 *
 * 確かめのために **AI をもう1回呼ばない**（オーナー 2026-10-14「カードの表示が遅くなるからやめて」）。
 * 同じ呼び出しの中で自己点検させ（`scene_fits`）、サーバは形だけを機械的に確かめる（`pickExamplePatterns`）。
 */

/** この版の例文の作り方（`extras.example_v`）。古いカードは持っていない（= 1）。 */
export const EXAMPLE_PROMPT_VERSION = 3;
/** パターンの上限（メインの例文を含む）。 */
export const MAX_EXAMPLE_PATTERNS = 4;

/** モデルが返すパターン1つ（`example_patterns` の要素）。型違いは落とさず空にする。 */
export const ExamplePatternSchema = z.object({
  situation: z.string().catch(""),
  share: z.coerce.number().catch(0),
  sentence: z.string().catch(""),
  translation: z.string().catch(""),
  scene: z.string().catch(""),
  chunks: z.array(ChunkPartSchema).catch([]),
  /** 自己点検の結果。**無ければ確かめていないだけ**なので落とさない（`false` だけ落とす）。 */
  scene_fits: z
    .union([z.boolean(), z.string().transform((s) => !/^(false|no|いいえ|否)$/i.test(s.trim()))])
    .optional()
    .catch(undefined),
});
export type ExamplePattern = z.infer<typeof ExamplePatternSchema>;

/**
 * **場面の札の長さの上限**（読む人の言語ごと、2026-10-15 オーナー「場面の説明は短く1行で」）。
 * 超えた札は区切り（読点・空白）で短くする（`shortScene`）。
 */
export const SCENE_MAX_CHARS = { ja: 24, zh: 18, en: 60 } as const;

export function sceneMaxChars(readerLang: string | null | undefined): number {
  const l = (readerLang ?? "").toLowerCase();
  if (l.startsWith("zh")) return SCENE_MAX_CHARS.zh;
  if (l.startsWith("en")) return SCENE_MAX_CHARS.en;
  return SCENE_MAX_CHARS.ja;
}

/**
 * 札を上限まで短くする。上限の中に区切り（、，,・空白）があればそこで切り、無ければ上限で切る。
 * 末尾の読点・句点は落とす。
 */
export function shortScene(scene: string, readerLang: string | null | undefined): string {
  const max = sceneMaxChars(readerLang);
  const s = scene
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[。.、，,]+$/u, "");
  if ([...s].length <= max) return s;
  const head = [...s].slice(0, max).join("");
  const cut = Math.max(
    head.lastIndexOf("、"),
    head.lastIndexOf("，"),
    head.lastIndexOf(","),
    head.lastIndexOf(" "),
  );
  return (cut >= Math.floor(max / 2) ? head.slice(0, cut) : head).trim();
}

/** 文字の2つ組（漢字・かなの言語）か語の2つ組（欧文）。似ているかを測る材料。 */
function grams(text: string): string[] {
  const t = text
    .toLowerCase()
    .replace(/[。．.!！?？、,，「」"'“”()（）]/g, " ")
    .trim();
  if (/[a-z]/.test(t) && !/[\u3040-\u30ff\u3400-\u9fff]/.test(t)) {
    const w = t.split(/\s+/).filter(Boolean);
    return w.length < 2 ? w : w.slice(1).map((x, i) => `${w[i]} ${x}`);
  }
  const c = [...t.replace(/\s+/g, "")];
  return c.length < 2 ? c : c.slice(1).map((x, i) => `${c[i]}${x}`);
}

/** 2つの文の似ている度合い（Dice 係数、0〜1）。 */
export function similarity(a: string, b: string): number {
  const x = grams(a);
  const y = grams(b);
  if (x.length === 0 || y.length === 0) return 0;
  const pool = new Map<string, number>();
  for (const g of y) pool.set(g, (pool.get(g) ?? 0) + 1);
  let hit = 0;
  for (const g of x) {
    const n = pool.get(g) ?? 0;
    if (n > 0) {
      hit++;
      pool.set(g, n - 1);
    }
  }
  return (2 * hit) / (x.length + y.length);
}

/** 札がこれ以上似ていたら同じ場面とみなす。 */
export const SCENE_DUPLICATE_AT = 0.6;
/** 文がこれ以上似ていたら同じ文型とみなす（名詞を入れ替えただけの文）。 */
export const SENTENCE_DUPLICATE_AT = 0.7;

/**
 * **似た場面を2つに分けない**（2026-10-15 オーナー「似たようなパターンは絶対に2つに分けない」）。
 * 札がよく似ている、または文の形がよく似ている（見出し語以外を入れ替えただけ）なら、同じパターン。
 */
export function nearDuplicateExample(
  a: { scene: string; sentence: string },
  b: { scene: string; sentence: string },
  headword = "",
): boolean {
  if (similarity(a.scene, b.scene) >= SCENE_DUPLICATE_AT) return true;
  const strip = (s: string) => (headword ? s.split(headword).join("＿") : s);
  const x = strip(a.sentence);
  const y = strip(b.sentence);
  if (similarity(x, y) >= SENTENCE_DUPLICATE_AT) return true;
  // 短い文は2つ組が少なく、1字（数・量詞・人称）を入れ替えただけでも似ていると出ない（我要一杯＿／我要兩杯＿）。
  // 見出し語の外で違うのが2割以下なら同じ文型。
  const ux = units(x);
  const uy = units(y);
  const longest = Math.max(ux.length, uy.length);
  return longest > 0 && editDistance(ux, uy) <= Math.max(1, Math.floor(longest * 0.2));
}

/** 比べる単位（欧文は語、それ以外は字。句読点・空白は落とす）。 */
function units(text: string): string[] {
  const t = text
    .toLowerCase()
    .replace(/[。．.!！?？、,，「」"'“”()（）]/g, " ")
    .trim();
  if (/[a-z]/.test(t) && !/[\u3040-\u30ff\u3400-\u9fff]/.test(t))
    return t.split(/\s+/).filter(Boolean);
  return [...t.replace(/\s+/g, "")];
}

function editDistance(a: readonly string[], b: readonly string[]): number {
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length];
}

/** 量詞の前に来る数・指示詞（「一束」「這束」「兩杯」「每個」）。 */
const MEASURE_LEAD = /[一二兩三四五六七八九十百千幾這那哪每半整好多]$/u;

/**
 * **量詞と見出し語の字が重なる文**（オーナー報告 2026-10-15: 花束の例文「他在畢業典禮上送了一束花束給女朋友。」—
 * 一束花束 は重ね言葉で、ネイティブは「送了一束花」と言う）。
 *
 * 数・指示詞 ＋ 量詞1字 ＋ 見出し語 で、見出し語がその量詞の字を含む（花束 ⊃ 束、杯子 ⊃ 杯、信封 ⊃ 封）。
 * 「一個花束」「這個杯子」は重ならない。見出し語が1字の語・漢字でない言語は見ない。
 */
export function redundantMeasure(sentence: string, headword: string): boolean {
  const head = (headword ?? "").trim();
  const text = sentence ?? "";
  if ([...head].length < 2 || !/^\p{Script=Han}+$/u.test(head)) return false;
  let from = 0;
  for (;;) {
    const at = text.indexOf(head, from);
    if (at < 0) return false;
    const before = [...text.slice(0, at)];
    const measure = before[before.length - 1];
    const lead = before.slice(0, -1).join("");
    if (measure && measure !== head && head.includes(measure) && MEASURE_LEAD.test(lead))
      return true;
    from = at + head.length;
  }
}

/** 例文1つ（画面に出す形）。 */
export type PickedExample = {
  sentence: string;
  translation: string;
  scene: string;
  chunks: z.infer<typeof ChunkPartSchema>[];
};

const norm = (s: string | null | undefined) =>
  (s ?? "").replace(/\s+/g, "").replace(/[。．.!！?？、,，「」"'“”]/g, "");

/** 2つの例文が同じ文か（空白・句読点の違いは同じとみなす）。 */
export function sameSentence(a: string | null | undefined, b: string | null | undefined): boolean {
  const x = norm(a);
  return x.length > 0 && x === norm(b);
}

/**
 * 返ってきたパターンを**機械的に**確かめて、よく使う順に並べる（AI は呼ばない）。
 *
 * 落とす物: 文が空・学習言語でない・（台湾華語）見出し語を含まない／札が空・読む人の言語でない／
 * 自己点検が `false`／同じ文の2つ目。残りを `share` の大きい順（同じなら返ってきた順）に並べ、
 * **似た場面・同じ文型の2つ目を落とし**（`nearDuplicateExample` — よく使う方を残す）、`max` 個まで。
 * 札は読む人の言語ごとの上限まで短くする（`shortScene`）。
 */
export function pickExamplePatterns(
  patterns: readonly ExamplePattern[] | null | undefined,
  opts: { headword: string; language: string; readerLang: string; max?: number },
): PickedExample[] {
  const max = Math.max(1, opts.max ?? MAX_EXAMPLE_PATTERNS);
  // 漢字の言語（台湾華語）は語形が変わらないので、見出し語がそのまま文に入っているはず。
  const literalHeadword = targetProfile(opts.language).scriptLang === "zh-Hant";
  const head = (opts.headword ?? "").trim();
  const seen = new Set<string>();
  const ok: Array<PickedExample & { share: number; i: number }> = [];
  (patterns ?? []).forEach((p, i) => {
    const sentence = (p.sentence ?? "").trim();
    if (!sentence || sentence.length > 160) return;
    if (!looksLikeTargetLanguage(sentence, opts.language)) return;
    // 入っていない文は別の語の例文。英語・日本語は活用で形が変わるので、ここでは見ない。
    if (literalHeadword && head && !sentence.includes(head)) return;
    // 量詞と見出し語の字が重なる文（一束花束）は不自然なので使わない（2026-10-15 花束）。
    if (literalHeadword && redundantMeasure(sentence, head)) return;
    const scene = shortScene(
      readerText((p.scene ?? "").trim(), opts.readerLang, sentence).trim(),
      opts.readerLang,
    );
    if (!scene) return;
    if (p.scene_fits === false) return;
    const key = norm(sentence);
    if (seen.has(key)) return;
    seen.add(key);
    ok.push({
      sentence,
      translation: readerText((p.translation ?? "").trim(), opts.readerLang, sentence).trim(),
      scene,
      chunks: p.chunks ?? [],
      share: Number.isFinite(p.share) ? p.share : 0,
      i,
    });
  });
  const kept: typeof ok = [];
  for (const e of ok.sort((a, b) => b.share - a.share || a.i - b.i)) {
    if (kept.some((k) => nearDuplicateExample(k, e, head))) continue;
    kept.push(e);
  }
  return kept
    .slice(0, max)
    .map(({ sentence, translation, scene, chunks }) => ({ sentence, translation, scene, chunks }));
}

/** 追加の例文の1つ（保存の形）。札には書いた文の目印（`scene_for`）を付ける — メインの例文と同じ確かめ方。 */
export function toExtraExample(e: PickedExample) {
  return {
    zh: e.sentence,
    ja: e.translation,
    scene: e.scene,
    scene_for: e.sentence,
    chunks: e.chunks,
  };
}

/**
 * **チュートリアルのカード**（`first-catch-ai.server.ts`、パターンを頼まない短い指示）の例文を、本番の
 * カードと同じ形にそろえる（2026-10-15）。AI が1つの要素の中に一緒に書いた文と札を組にする:
 *
 * - メインの例文に札（`extras.example_scene`）があれば `example_scene_for` = その文
 * - 追加の例文は札のある物に `scene_for` = その文。量詞が重なる文（一束花束）は落とす
 * - メインの例文の量詞が重なっていて、重ならない追加の例文があれば、それをメインに上げる
 *
 * 目印が無いと iOS は札を出さない（`WordExtras.shownExampleScene`）— チュートリアルのカードは控えを通して
 * 共有の語の中身になるので、ここで付ける。
 */
export function pairTutorialExamples<
  C extends {
    example_sentence: string;
    example_translation: string;
    extras: {
      example_scene?: string;
      example_scene_for?: string;
      example_chunks?: unknown[];
      examples_extra?: Array<{
        zh: string;
        ja: string;
        scene: string;
        scene_for?: string;
        chunks: unknown[];
      }>;
    };
  },
>(card: C, headword: string): C {
  const head = (headword ?? "").trim();
  const extras = { ...card.extras };
  let sentence = card.example_sentence;
  let translation = card.example_translation;
  const extra = (extras.examples_extra ?? []).filter(
    (e) => e && e.zh && !redundantMeasure(e.zh, head),
  );
  if (sentence && redundantMeasure(sentence, head) && extra.length > 0) {
    const [up] = extra.splice(0, 1);
    sentence = up.zh;
    translation = up.ja;
    extras.example_scene = up.scene;
    extras.example_chunks = up.chunks;
  }
  extras.examples_extra = extra.map((e) => (e.scene?.trim() ? { ...e, scene_for: e.zh } : e));
  if ((extras.example_scene ?? "").trim() && sentence) extras.example_scene_for = sentence;
  return { ...card, example_sentence: sentence, example_translation: translation, extras };
}

/**
 * 追加の例文の札を、その文と組で確かめる。`scene_for` が付いていて文と違う札は空にする（目印も外す）。
 * 目印の無い古い物はそのまま。
 */
export function alignExtraExamples<E extends { zh?: string; scene?: string; scene_for?: string }>(
  list: readonly E[] | null | undefined,
): E[] {
  return (list ?? []).map((e) =>
    e && typeof e.scene_for === "string" && e.scene_for.trim() && !sameSentence(e.scene_for, e.zh)
      ? { ...e, scene: "", scene_for: "" }
      : e,
  );
}

type CardLike = {
  example_sentence?: string;
  example_translation?: string;
  extras?: Record<string, unknown> | null;
};

/**
 * 確かめたパターンをカードの今までの欄に写す（保存の形・画面は変えない）。
 *
 * - 1つ目（いちばんよく使う場面）→ `example_sentence` / `example_translation` / `extras.example_scene` /
 *   `extras.example_chunks`。札には `example_scene_for`（その札を書いた文）を付ける。
 * - 2つ目から → `extras.examples_extra`（`withExtra` のとき）。`example_pattern_count` は見つかった数
 *   （1 なら「この語は1つの場面でしか使わない」— 追加の例文の節を作り直しに行かない）。
 * - 1つも残らなければ、カードは**そのまま**返す（例文の欄は空か、モデルが別に返した物のまま）。
 */
export function applyExamplePatterns<T extends CardLike>(
  card: T,
  picked: readonly PickedExample[],
  opts: { withExtra: boolean },
): T {
  if (picked.length === 0) return card;
  const [main, ...rest] = picked;
  const extras: Record<string, unknown> = {
    ...(card.extras ?? {}),
    example_scene: main.scene,
    example_chunks: main.chunks,
    example_scene_for: main.sentence,
    example_v: EXAMPLE_PROMPT_VERSION,
  };
  if (opts.withExtra) {
    extras.examples_extra = rest.map(toExtraExample);
    extras.example_pattern_count = picked.length;
  }
  return {
    ...card,
    example_sentence: main.sentence,
    example_translation: main.translation,
    extras,
  };
}

/** メインの例文に付く欄（文と一緒でなければ意味を持たない物）。 */
const PAIRED_EXTRAS = [
  "example_scene",
  "example_chunks",
  "example_scene_for",
  "example_v",
] as const;

/**
 * **文と札を組で扱う**。`extras` の札が別の文のために書かれていたら（`example_scene_for` が `sentence` と違う）、
 * 札・パーツ・目印を外した写しを返す。目印の無い古い extras はそのまま（確かめようがない）。
 *
 * 共有の行は「空の欄だけ埋める」ので、ここを通さないと、前から在った文の横に新しい生成の札だけが入る
 * （2026-10-15 眼鏡）。
 */
export function alignExampleExtras<E extends Record<string, unknown> | null | undefined>(
  extras: E,
  sentence: string | null | undefined,
): E {
  if (!extras || typeof extras !== "object") return extras;
  const forSentence = (extras as Record<string, unknown>).example_scene_for;
  if (typeof forSentence !== "string" || !forSentence.trim()) return extras;
  if (sameSentence(forSentence, sentence)) return extras;
  const out: Record<string, unknown> = { ...extras };
  for (const k of PAIRED_EXTRAS) delete out[k];
  /**
   * メインの例文が別の文に決まった（前から在る文が残る）時は、追加の例文もその文に合わせる（2026-10-16 冰淇淋）:
   * その文と同じ文を落とし、パターンの数を 1 + 残った数にする（数は別の文をメインとして数えていた）。
   */
  if (norm(sentence)) {
    const list = Array.isArray(out.examples_extra) ? (out.examples_extra as unknown[]) : null;
    if (list) {
      const kept = list.filter((x) => !sameSentence(extraAsExample(x).sentence, sentence));
      out.examples_extra = kept;
      if (typeof out.example_pattern_count === "number")
        out.example_pattern_count = 1 + kept.length;
    }
  }
  return out as E;
}

/**
 * 生成したカードの例文が、いま表示に使う文（`sentence`）と同じか。違えばそのカードの訳を使わない。
 * 文が空（まだ例文が無い）なら、カードの文がそのまま入るので「同じ」とみなす。
 */
export function exampleMatchesSentence(
  cardSentence: string | null | undefined,
  sentence: string | null | undefined,
): boolean {
  if (!norm(sentence)) return true;
  return sameSentence(cardSentence, sentence);
}

/**
 * 共有の列を埋める時、**訳だけ**が別の文のために書かれた物で埋まらないようにする。
 * 例文の列を一緒に埋めない回で、カードの文がいまの文と違えば、訳の列は書かない。
 */
export function guardExampleColumns<U extends Record<string, unknown>>(
  update: U,
  current: { example_sentence?: string | null },
  card: { example_sentence?: string | null } | null | undefined,
): U {
  if (!("example_translation" in update) || "example_sentence" in update) return update;
  if (exampleMatchesSentence(card?.example_sentence, current.example_sentence)) return update;
  const out: Record<string, unknown> = { ...update };
  delete out.example_translation;
  return out as U;
}

/**
 * 例文の作り方の指示（カード生成と例文の作り直しの `example_patterns`）。
 *
 * `max` = 返すパターンの上限。追加の例文の節を頼まない呼び出し（Web の既定）では 1（いちばんよく使う場面だけ）。
 * `sceneMax` = 札の字数の上限（読む人の言語ごと、`sceneMaxChars`）。
 */
export function examplePatternsRule(opts: {
  headword: string;
  targetName: string;
  nl: string;
  max: number;
  levelRule: string;
  sourceRule: string;
  chunkRoles: string;
  sceneMax?: number;
}): string {
  const { headword, targetName, nl, max, levelRule, sourceRule, chunkRoles } = opts;
  const sceneMax = opts.sceneMax ?? SCENE_MAX_CHARS.ja;
  const howMany =
    max <= 1
      ? `パターンを考えたうえで、**いちばんよく使うパターン1つだけ**を配列に入れて返す。`
      : `パターンは**よく使う順に1〜${max}個**。本当に別々の状況でよく使う時だけ複数にする。` +
        `その語がふだん1つの状況でしか使われないなら1個でよい。**数を合わせるために場面を作らない。**`;
  return [
    `- example_patterns: **例文は「ネイティブがその語をいちばんよく使う場面のパターン」から作る。** 次の順に考えて、配列で返す。`,
    `  1. ネイティブ（${targetName}の話し手）が「${headword}」を実際に口にする状況・場面・気持ちのうち、**いちばんよく使うもの**を思い浮かべ、パターンに分ける。`,
    `  2. **似たパターンは絶対に2つに分けない。** 同じ場所・同じ相手・同じ用件・同じ気持ちの状況は1つにまとめる` +
      `（✗「店で注文するとき」と「屋台で頼むとき」を別にする / ✗ 主語や名詞を入れ替えただけの同じ形の文を2つ書く）。`,
    `  3. ${howMany}`,
    `     share は、その語が使われる場面全体のうち、そのパターンが占める割合の目安（0〜100 の整数）。`,
    `  4. パターンごとに、**その場面でネイティブが実際にいちばん自然に言う一文**を1つだけ書く（sentence、${targetName}）。` +
      `教科書の作文・説明文にしない。「${headword}」を必ず含める。`,
    `     **重ね言葉にしない。** 見出し語がもう量詞・名詞の字を含む時、同じ字を量詞にして重ねない` +
      `（✗「送了一束花束」「這束花束」→ ○「送了一個花束」「這個花束好漂亮」/ ✗「一杯杯子」→ ○「一個杯子」）。` +
      `ネイティブが言わない言い回し・意味の重なる語の組み合わせを書かない。`,
    `  5. その一文の**ために** scene を書く: その文がまさに口にされる状況の**短い1行**（${nl}で${sceneMax}字以内。` +
      `誰が・どこで・何が起きて・どんな気持ちか が分かる言葉だけ）。画面で例文のすぐ上に出る。`,
    `     **scene と sentence は食い違ってはいけない。** ✗ sentence「我有鑰匙。」に scene「鍵をなくして困ったとき」` +
      `（その場面なら「我的鑰匙不見了！」と言う）→ ○ scene「家族に鍵を持ったか聞かれて」。`,
    `  6. 返す前に1つずつ確かめる: sentence だけを読んだネイティブが思い浮かべる場面と scene が同じか。` +
      `違えば scene（または sentence）を書き直す。scene_fits はこの確認の結果（直して合っていれば true）。` +
      `合わせられないパターン・ほかのパターンと似たパターンは配列に入れない。`,
    `  各要素: {share, sentence: ${targetName}の一文, translation: その文の自然な訳(${nl}), scene: 上の短い1行(${nl}), ` +
      `chunks: sentence をパーツ分解した [{text,pos}]（pos は ${chunkRoles}）, scene_fits: true/false}`,
    `  ${levelRule}`,
    `  ${sourceRule.replace(/\n/g, "\n  ")}`,
  ].join("\n");
}

/*
 * ---------------------------------------------------------------------------------------------
 * **前から在るメインの例文に、札だけを付ける**（オーナー報告 2026-10-16: 冰淇淋 の1つ目の例文
 * 「夏天吃冰淇淋。」に場面の札が無く、2つ目には有る）。
 *
 * 共有の行（`words.example_sentence`）は空の時だけ埋めるので、場面の札（2026-10-14）より前に出来た例文は
 * そのまま残る（オーナー決定: 古い例文の文そのものは作り直さない）。ところがカードを作るたびに AI は
 * **別の新しい文**をメインに書き、その札は保存の時に「別の文の札」として外される（`alignExampleExtras`）。
 * 一方で追加の例文と `example_pattern_count` は空の欄に入るので、古い文はパターン1つ目と数えられたまま、
 * 札が付かなかった。
 *
 * 直し方: メインの例文が決まっている時は、その文を**与えられた文**として指示に入れ、同じ呼び出しの中で
 * **その文のための札**（`example_main`）と、それ**以外の**パターンだけを書かせる。古い行は、単語の詳細を
 * 開いた時に札だけを書く小さな呼び出しで埋める（`example-scene-label.server.ts`）。
 * ---------------------------------------------------------------------------------------------
 */

/**
 * 番号として受け取ってよい物だけを番号にする（PR #189 の点検 P2）。0 以上の整数か、数字だけの文字列（"2"）。
 * `null` / `false` / `""` / 空白 / "1.5" / "x" は捨てる — `z.coerce.number()` はこれらを 0 にして、1つ目の
 * 追加の例文を「メインと同じ」として消していた。
 */
function strictIndex(x: unknown): number | null {
  if (typeof x === "number") return Number.isSafeInteger(x) && x >= 0 ? x : null;
  if (typeof x === "string" && /^\s*\d{1,4}\s*$/.test(x)) return Number(x.trim());
  return null;
}

/** 決まったメインの例文のために、モデルが返す札（`example_main`）。型違いは落とさず空にする。 */
export const MainExampleLabelSchema = z.object({
  scene: z.string().catch(""),
  translation: z.string().catch(""),
  chunks: z.array(ChunkPartSchema).catch([]),
  scene_fits: ExamplePatternSchema.shape.scene_fits,
  /** 追加の例文（番号つきで渡した物）のうち、メインの例文と同じパターンの物の番号。 */
  same_as_main: z
    .array(z.unknown())
    .catch([])
    .transform((xs) => xs.map(strictIndex).filter((n): n is number => n !== null)),
});
export type MainExampleLabel = z.infer<typeof MainExampleLabelSchema>;

/** 文を比べる形（空白・句読点・記号を除き、小文字に）。パーツをつないだ物と文を突き合わせる。 */
const chunkKey = (s: string) => s.replace(/[\s\p{P}\p{S}]/gu, "").toLowerCase();

/**
 * パーツ（`example_chunks`）が**その文を分けた物**か: パーツの文字をつなぐと文になる（空白・句読点・記号の違いは
 * 同じとみなす）。古い行のパーツは、AI が書いて保存で外れた別の文の物のことがある（本番 2026-10-16: 目印の無い
 * 144 行のうち 65 行 — 床「我的床很舒服。」に「我|昨天|太|累|了|…」）。
 */
export function chunksMatchSentence(chunks: unknown, sentence: string | null | undefined): boolean {
  if (!Array.isArray(chunks) || chunks.length === 0) return false;
  const joined = chunks.map((c) => String((c as { text?: unknown })?.text ?? "")).join("");
  const key = chunkKey(joined);
  return key.length > 0 && key === chunkKey(sentence ?? "");
}

/** 確かめた札（画面に出せる物）。 */
export type CheckedMainLabel = {
  scene: string;
  translation: string;
  chunks: z.infer<typeof ChunkPartSchema>[];
  sameAsMain: number[];
};

type ExtrasLike = Record<string, unknown> | null | undefined;

/**
 * メインの例文 `sentence` に、**その文のために書いた札**が無いか（`example_scene` が空、または
 * `example_scene_for` が違う文・無い）。文が無ければ札も要らない（false）。
 */
export function needsMainSceneLabel(
  sentence: string | null | undefined,
  extras: ExtrasLike,
): boolean {
  if (!norm(sentence)) return false;
  const e = (extras ?? {}) as Record<string, unknown>;
  const scene = typeof e.example_scene === "string" ? e.example_scene.trim() : "";
  const forSentence = typeof e.example_scene_for === "string" ? e.example_scene_for : "";
  return !(scene && sameSentence(forSentence, sentence));
}

/** `extras` の中で、メインの例文 `sentence` のために書かれた札（無ければ空）。 */
export function mainSceneFor(sentence: string | null | undefined, extras: ExtrasLike): string {
  if (needsMainSceneLabel(sentence, extras)) return "";
  return String((extras as Record<string, unknown>).example_scene ?? "").trim();
}

/**
 * 決まったメインの例文のための札を頼む指示（カード生成・例文の作り直し・札だけの呼び出しで共通）。
 * 札の決まりは `examplePatternsRule` の scene と同じ（短い1行・読む人の言語・字数の上限・文と食い違わない）。
 *
 * - `translation`: その文の訳も書かせる（読む人の行に訳が無い時・カード生成）
 * - `chunks`: その文のパーツ分解も書かせる（`chunkRoles` = pos の候補）
 * - `extras`: 追加の例文（番号つき）。同じパターンの物の番号を `same_as_main` に書かせる
 */
export function mainExampleLabelRule(opts: {
  sentence: string;
  headword: string;
  targetName: string;
  nl: string;
  sceneMax?: number;
  translation?: boolean;
  chunkRoles?: string;
  extras?: readonly string[];
}): string {
  const { sentence, headword, targetName, nl } = opts;
  const sceneMax = opts.sceneMax ?? SCENE_MAX_CHARS.ja;
  const fields = [
    `scene: その文の短い1行(${nl})`,
    opts.translation ? `translation: その文の自然な訳(${nl})` : "",
    opts.chunkRoles
      ? `chunks: その文をパーツ分解した [{text,pos}]（pos は ${opts.chunkRoles}）`
      : "",
    `scene_fits: true/false`,
    opts.extras && opts.extras.length > 0 ? `same_as_main: 番号の配列` : "",
  ].filter(Boolean);
  return [
    `- example_main: **「${headword}」のメインの例文はもう決まっている:「${sentence}」。この文は変えない**（書き直さない・別の文にしない・直した文を返さない）。`,
    `  この文の**ために** scene を書く: ネイティブ（${targetName}の話し手）がこの文をまさに口にする状況の**短い1行**` +
      `（${nl}で${sceneMax}字以内。誰が・どこで・何が起きて・どんな気持ちか が分かる言葉だけ）。画面でこの文のすぐ上に出る。`,
    `  **scene とこの文は食い違ってはいけない。** この文だけを読んだネイティブが思い浮かべる場面と scene が同じか確かめる。` +
      `scene_fits はこの確認の結果（直して合っていれば true）。`,
    ...(opts.extras && opts.extras.length > 0
      ? [
          `  次の追加の例文のうち、この文と**同じパターン**（同じ場所・同じ相手・同じ用件・同じ気持ちの状況、または名詞を入れ替えただけの同じ形の文）の物の番号を same_as_main に入れる（無ければ []）:`,
          ...opts.extras.map((s, i) => `    ${i}. ${s}`),
        ]
      : []),
    `  形: example_main = {${fields.join(", ")}}`,
  ].join("\n");
}

/**
 * 返ってきた札を**機械的に**確かめる（AI は呼ばない）。自己点検が false・札が空・読む人の言語でない物は使わない。
 * 札は読む人の言語ごとの上限まで短くする。訳も読む人の言語の物だけ。
 */
export function checkMainExampleLabel(
  raw: unknown,
  opts: { sentence: string; readerLang: string },
): CheckedMainLabel | null {
  const parsed = MainExampleLabelSchema.safeParse(raw ?? {});
  if (!parsed.success) return null;
  const l = parsed.data;
  if (l.scene_fits === false) return null;
  const scene = shortScene(
    readerText(l.scene.trim(), opts.readerLang, opts.sentence).trim(),
    opts.readerLang,
  );
  if (!scene) return null;
  return {
    scene,
    translation: readerText(l.translation.trim(), opts.readerLang, opts.sentence).trim(),
    // パーツはその文を分けた物だけ（AI が別の文・直した文を分けて返した回は使わない）。
    chunks: chunksMatchSentence(l.chunks, opts.sentence) ? l.chunks : [],
    sameAsMain: [...new Set(l.same_as_main)],
  };
}

/** メインの例文と同じパターンの追加の例文か（同じ文・似た場面・同じ文型、または AI が同じと言った物）。 */
function duplicatesMain(
  main: { sentence: string; scene: string },
  extra: { sentence: string; scene: string },
  headword: string,
): boolean {
  if (sameSentence(extra.sentence, main.sentence)) return true;
  // 札の無いメイン（札を作れなかった回）は、文の形だけで比べることになる（空の札は何とも似ない — `similarity`）。
  return nearDuplicateExample(main, extra, headword);
}

/**
 * **メインの例文が決まっている時**のカードの例文の欄（カード生成・例文の作り直し）。
 *
 * - `example_sentence` = 決まった文（変えない）。札があれば `example_scene` / `example_scene_for`（= その文）/
 *   `example_chunks`、訳があれば `example_translation`
 * - 札が無ければ（作れなかった回）、別の文の札・パーツを残さない（古い文に札が付かないだけ。次に開いた時に埋まる）
 * - 追加の例文（`withExtra`）: メインと同じパターンの物を落とし、上限まで。`example_pattern_count` = 1 + 残った数
 *   （メインはいつも別のパターンとして数える — 同じパターンの追加の例文は落としたので）
 */
export function applyFixedMainExample<T extends CardLike>(
  card: T,
  opts: {
    sentence: string;
    label: CheckedMainLabel | null;
    extras: readonly PickedExample[];
    withExtra: boolean;
    headword: string;
    max?: number;
  },
): T {
  const max = Math.max(1, opts.max ?? MAX_EXAMPLE_PATTERNS);
  const main = { sentence: opts.sentence, scene: opts.label?.scene ?? "" };
  const rest = opts.extras.filter((e) => !duplicatesMain(main, e, opts.headword)).slice(0, max - 1);
  const extras: Record<string, unknown> = { ...(card.extras ?? {}) };
  for (const k of PAIRED_EXTRAS) delete extras[k];
  if (opts.label) {
    extras.example_scene = opts.label.scene;
    extras.example_scene_for = opts.sentence;
    if (opts.label.chunks.length > 0) extras.example_chunks = opts.label.chunks;
  }
  extras.example_v = EXAMPLE_PROMPT_VERSION;
  if (opts.withExtra) {
    extras.examples_extra = rest.map(toExtraExample);
    extras.example_pattern_count = 1 + rest.length;
  }
  const keptTranslation = sameSentence(card.example_sentence, opts.sentence)
    ? (card.example_translation ?? "")
    : "";
  return {
    ...card,
    example_sentence: opts.sentence,
    example_translation: opts.label?.translation || keptTranslation,
    extras,
  };
}

/** 追加の例文1つ（保存の形）を、比べる形に。 */
function extraAsExample(e: unknown): { sentence: string; scene: string } {
  const x = (e ?? {}) as { zh?: unknown; scene?: unknown };
  return {
    sentence: typeof x.zh === "string" ? x.zh : "",
    scene: typeof x.scene === "string" ? x.scene : "",
  };
}

/**
 * **保存済みの行**のメインの例文に札を付ける差分（札だけの呼び出しの後、`example-scene-label.server.ts`）。
 *
 * - `example_scene` / `example_scene_for`（= その文）
 * - メインと同じパターンの追加の例文を落とす（`samePattern` の文・似た場面・同じ文型）。落とした時は
 *   `examples_extra` を入れ替える（`replaceKeys` に入る）
 * - AI が同じパターンと言った物は**文で**渡す（`samePattern`）。番号（`label.sameAsMain`）は AI に見せた
 *   一覧の中の位置で、読む人の行と共有の行では一覧が違うので、ここでは使わない（PR #189 の点検 P1）
 * - `example_pattern_count` は 1 + 残った数（数が在った行・落とした行だけ。無い行に新しく数を置かない）
 *
 * `label` が null（札は既に在る）なら、同じパターンの追加の例文を落とすだけ。変える物が無ければ null。
 */
export function mainExamplePatch(
  extras: ExtrasLike,
  opts: {
    sentence: string;
    headword: string;
    label: CheckedMainLabel | null;
    /** AI がメインと同じパターンと言った追加の例文の**文**（どの行の一覧でも、文で突き合わせる）。 */
    samePattern?: readonly string[];
  },
): { patch: Record<string, unknown>; replaceKeys: string[] } | null {
  const e = (extras ?? {}) as Record<string, unknown>;
  const scene = opts.label?.scene ?? mainSceneFor(opts.sentence, e);
  const main = { sentence: opts.sentence, scene };
  const list = Array.isArray(e.examples_extra) ? (e.examples_extra as unknown[]) : [];
  const same = (opts.samePattern ?? []).filter((x) => norm(x));
  const kept = list.filter((x) => {
    const ex = extraAsExample(x);
    if (same.some((s) => sameSentence(s, ex.sentence))) return false;
    return !duplicatesMain(main, ex, opts.headword);
  });
  const patch: Record<string, unknown> = {};
  const replaceKeys: string[] = [];
  if (opts.label) {
    patch.example_scene = opts.label.scene;
    patch.example_scene_for = opts.sentence;
    /**
     * 目印でこの文を正と記すので、パーツもこの文の物にそろえる（PR #189 の点検 P2）。在るパーツがこの文を
     * 分けた物なら残す。そうでなければ、札と一緒に書かせたパーツ（この文の物だけ — `checkMainExampleLabel`）に
     * 入れ替え、それも無ければ空にする（`replaceKeys` — 空で上書きする）。
     */
    if (!chunksMatchSentence(e.example_chunks, opts.sentence)) {
      const hadChunks = Array.isArray(e.example_chunks) && e.example_chunks.length > 0;
      if (opts.label.chunks.length > 0) {
        patch.example_chunks = opts.label.chunks;
      } else if (hadChunks) {
        patch.example_chunks = [];
        replaceKeys.push("example_chunks");
      }
    }
  }
  const dropped = kept.length < list.length;
  if (dropped) {
    patch.examples_extra = kept;
    replaceKeys.push("examples_extra");
  }
  const count = typeof e.example_pattern_count === "number" ? e.example_pattern_count : null;
  if ((dropped || count !== null) && count !== 1 + kept.length) {
    patch.example_pattern_count = 1 + kept.length;
  }
  return Object.keys(patch).length > 0 ? { patch, replaceKeys } : null;
}

/**
 * 札は既に在る行で、AI を呼ばずに直せる物が在るか（メインと同じパターンの追加の例文・合わないパターンの数）。
 */
export function mainExampleNeedsTidy(
  extras: ExtrasLike,
  sentence: string | null | undefined,
  headword: string,
): boolean {
  if (!norm(sentence) || needsMainSceneLabel(sentence, extras)) return false;
  return mainExamplePatch(extras, { sentence: sentence ?? "", headword, label: null }) !== null;
}

/**
 * **保存済みの行を直す引数**（`apply_main_example_label` に渡す。PR #189 の点検 P1）。
 *
 * 行を丸ごと書き戻さない — 書く時点の行に、名前を挙げた鍵だけを重ねる（ほかの処理が間に書いた鍵を消さない）。
 * だから「何を足す・何を落とす」を値で渡す:
 * - `scene`: 札（目印 = その文は SQL が付ける）。札が要らなければ null
 * - `chunks`: その文のパーツ（置き換える）。`staleChunks`: いまのパーツがこの値のままなら空にする
 * - `drop`: 落とす追加の例文の文（zh。読んだ行の文そのまま）
 * - `recount`: パターンの数を書く時点の 1 + 残った数にする
 *
 * 直す物が無ければ null。中身は `mainExamplePatch` と同じ決まり。
 */
export type MainExampleRepair = {
  scene: string | null;
  chunks: z.infer<typeof ChunkPartSchema>[] | null;
  staleChunks: unknown[] | null;
  drop: string[];
  recount: boolean;
};

export function mainExampleRepair(
  extras: ExtrasLike,
  opts: Parameters<typeof mainExamplePatch>[1],
): MainExampleRepair | null {
  const fix = mainExamplePatch(extras, opts);
  if (!fix) return null;
  const e = (extras ?? {}) as Record<string, unknown>;
  const list = Array.isArray(e.examples_extra) ? (e.examples_extra as unknown[]) : [];
  const kept = Array.isArray(fix.patch.examples_extra)
    ? (fix.patch.examples_extra as unknown[])
    : null;
  const drop = kept
    ? list
        .filter((x) => !kept.includes(x))
        .map((x) => extraAsExample(x).sentence)
        .filter((s) => s.length > 0)
    : [];
  const ch = fix.patch.example_chunks;
  const repair: MainExampleRepair = {
    scene: typeof fix.patch.example_scene === "string" ? fix.patch.example_scene : null,
    chunks: Array.isArray(ch) && ch.length > 0 ? (ch as MainExampleRepair["chunks"]) : null,
    staleChunks:
      Array.isArray(ch) && ch.length === 0 && Array.isArray(e.example_chunks)
        ? (e.example_chunks as unknown[])
        : null,
    drop: [...new Set(drop)],
    recount: "example_pattern_count" in fix.patch,
  };
  const empty =
    !repair.scene &&
    !repair.chunks &&
    !repair.staleChunks &&
    repair.drop.length === 0 &&
    !repair.recount;
  return empty ? null : repair;
}

/**
 * **その行のメインの例文に札を書いてよいか**（PR #189 の点検 — 行の札を消さない決まり）。書いてよいのは:
 * - 札が無い（`example_scene` が空）
 * - 札は在るが、目印（`example_scene_for`）が**別の文**を指している — 別の文の札だと分かる時だけ入れ替える
 *
 * 目印の無い札（人が書いた・目印より前の札）は、どの文の札か分からないので**入れ替えない**。その文の札が
 * もう在る行も書かない。人が確かめた行（verified）は呼ぶ側が外す（どんな札も入れ替えない）。
 * 同じ決まりは SQL の `apply_main_example_label` にもある（DB の側でも入れ替えない）。
 */
export function mayWriteMainLabel(
  sentence: string | null | undefined,
  extras: ExtrasLike,
): boolean {
  if (!norm(sentence)) return false;
  const e = (extras ?? {}) as Record<string, unknown>;
  const scene = typeof e.example_scene === "string" ? e.example_scene.trim() : "";
  if (!scene) return true;
  const forSentence = typeof e.example_scene_for === "string" ? e.example_scene_for.trim() : "";
  return !!forSentence && !sameSentence(forSentence, sentence);
}
