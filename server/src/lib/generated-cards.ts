/**
 * **サーバが作った語の中身の控え**（監査 2026-10-03 H2 / M3）。
 *
 * 共有の語（`words`）と読む人ごとの解説（`word_explanations`）は全員が同じ行を見る。
 * 前はその中身を**画面が送ってきた文**で書いていた（`saveSticker` → `upsertWord` の
 * 新しい語の行、`updateWordExtras` の `extras` / `reader_meaning` / `patch`）。
 * アプリを通さずに呼べば、誰でも好きな文を共有の行に置けた。
 *
 * いまは**サーバが自分で作った物だけ**を共有の行に書く:
 *
 * 1. 中身を作るサーバの関数（`generateCard`・候補を出す `suggestWords` /
 *    `suggestWordCandidates` / `detectScan`・チュートリアルのカード）が、作った物をここに
 *    控える（`generated_cards`、サーバの鍵でしか読み書きできない表）
 * 2. 保存の道（`upsertWord`・`applyWordExtrasUpdate`）は、画面の送った文ではなく
 *    この控えを読んで書く。画面は今までどおり同じ物を送ってくるが、使われない
 *
 * 控えは**誰が作らせたかを問わない**（中身はどれもサーバのプロンプトで作った物で、
 * 人が書いた文ではない）。個人の材料（一言・場所・日記）は、ここに来る生成には一切
 * 渡していない（`runSectionRegen` の注、H1）。
 *
 * 表がまだ無い環境（移行待ち）では `available: false` を返す — 呼ぶ側は前の動き
 * （画面の送った物で空の所だけ埋める）に戻る。**移行を当てるまで穴は開いたまま**なので、
 * 移行 `20261003130100_generated_cards.sql` を先に当てること。
 */

import { alignExampleExtras, guardExampleColumns, sameSentence } from "./example-patterns";
import { normDexHeadword } from "./dex-catalog";
import {
  claimSharedRowLanguage,
  fillEmptySharedColumns,
  fillEmptySharedExtras,
  sharedColumnsFromCard,
} from "./shared-word-guard";

/** 控えを使う期間。過ぎた物は使わず、時々消す。 */
export const GENERATED_CARD_TTL_MS = 14 * 24 * 60 * 60 * 1000;

/** `card` = カード全体（`generateCard` など） / `candidate` = 候補の意味と読みだけ。 */
export type GeneratedCardKind = "card" | "candidate";

/**
 * **カードを作った時の入力の印**（`generateCard` が控えに付ける。2026-10-15）。同じ入力のカードを作り直さずに
 * 返す（`pickReusableCard`）ための物で、共有の行には書かない（`sharedColumnsFromCard` は列の名前で選ぶ）。
 */
export type CardGenKey = {
  /** 作り方の版（指示を変えたら `CARD_REUSE_VERSION` を上げる — 古い控えは使わない）。 */
  v: number;
  /** 級（現在 > 目標）。例文・チャンクの難しさが変わる。 */
  levels: string;
  /** 頼んだ AI（管理者が AI を替えたら作り直す）。 */
  model: string;
  /** Pro の AI で作ったか。 */
  pro: boolean;
  /** 頼んだ節（`null` = 全部）。 */
  sections: string[] | null;
};

/** 控えの中身（共有の行に書いてよい所だけ）。 */
export type TrustedCard = {
  meaning_ja?: string;
  reading_zhuyin?: string;
  pinyin?: string;
  part_of_speech?: string;
  level?: string;
  category_key?: string;
  example_sentence?: string;
  example_translation?: string;
  extras?: Record<string, unknown>;
  /** カードの見出し語（打った語が母語でも学習言語の語。共有の列ではない）。 */
  headword_zh?: string;
  /** 作った時の入力の印（共有の列ではない）。 */
  gen?: CardGenKey;
};

export type GeneratedCardLookup =
  | { available: false }
  | { available: true; card: TrustedCard | null; kind: GeneratedCardKind | null };

const TABLE = "generated_cards";

const TEXT_KEYS = [
  "meaning_ja",
  "reading_zhuyin",
  "pinyin",
  "part_of_speech",
  "level",
  "category_key",
  "example_sentence",
  "example_translation",
] as const;

/** 作った物から、控えに残す所だけを取り出す（知らない鍵・文字列でない値は捨てる）。 */
export function trustedCardFrom(raw: unknown): TrustedCard {
  const out: TrustedCard = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  const r = raw as Record<string, unknown>;
  for (const k of TEXT_KEYS) {
    const v = r[k];
    if (typeof v === "string" && v.trim()) out[k] = v.trim();
  }
  const ex = r.extras;
  if (ex && typeof ex === "object" && !Array.isArray(ex)) {
    out.extras = ex as Record<string, unknown>;
  }
  if (typeof r.headword_zh === "string" && r.headword_zh.trim()) {
    out.headword_zh = r.headword_zh.trim();
  }
  const gen = readGenKey(r.gen);
  if (gen) out.gen = gen;
  return out;
}

function readGenKey(raw: unknown): CardGenKey | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const g = raw as Record<string, unknown>;
  if (typeof g.v !== "number" || typeof g.levels !== "string" || typeof g.model !== "string")
    return null;
  const sections =
    g.sections === null
      ? null
      : Array.isArray(g.sections) && g.sections.every((x) => typeof x === "string")
        ? (g.sections as string[])
        : undefined;
  if (sections === undefined) return null;
  return { v: g.v, levels: g.levels, model: g.model, pro: g.pro === true, sections };
}

/**
 * 作り方の版。`generateCard` の指示・形を変えたら上げる（上げると、それより前の控えは作り直さずに返す対象から外れる）。
 * 1 = 2026-10-15（語源・部首を作らない・カテゴリーの読み直し）。
 * 2 = 2026-10-16（前から在るメインの例文に札を付けて作る — `applyFixedMainExample`）。
 */
export const CARD_REUSE_VERSION = 2;

/**
 * **作り直さずに返す期間**（2026-10-15 オーナー報告: 同じ 草莓蛋糕 のカードが 20 分で3回作られた — 保存の
 * やり直しのたびに 5〜7 秒）。同じ語・学習言語・読む人の言語・母語・級・AI・作り方の版なら、控えのカードを
 * そのまま返す。控え自体は 14 日残る（保存の道が読む）が、返すのは作ってから1日以内の物だけ。
 */
export const CARD_REUSE_WINDOW_MS = 24 * 60 * 60 * 1000;

/** 頼まれた節（`requested`）が、控えを作った時に頼んだ節（`stored`）に全部入っているか。 */
function coversSections(stored: string[] | null, requested: readonly string[] | null): boolean {
  if (stored === null) return true;
  if (requested === null) return false;
  return requested.every((id) => stored.includes(id));
}

const filledList = (v: unknown) => Array.isArray(v) && v.length > 0;
const filledString = (v: unknown) => typeof v === "string" && v.trim().length > 0;

/**
 * **同じ入力で作ったカードを、作り直さずに返してよいか**（純粋関数）。返してよい物の中で新しい物を1つ。
 *
 * - カード全体（`kind: "card"`）・同じ読む人の言語と母語・`CARD_REUSE_WINDOW_MS` 以内
 * - 作った時の印（`gen`）が同じ: 作り方の版・級・AI。Pro の人には Pro の AI で作った物だけ
 * - 頼まれた節が、作った時に頼んだ節に全部入っている（全部を頼んで作った物は、どの頼み方にも使える）
 * - 中身がそろっている（意味・例文・使う場面、頼まれていればチャンク・関連語）— 欠けたカードを返し続けない
 */
export function pickReusableCard(
  rows: readonly GeneratedCardRow[] | null | undefined,
  opts: {
    explainLang: string;
    l1: string;
    gen: CardGenKey;
    now?: number;
  },
): (TrustedCard & { created_at: string }) | null {
  const now = opts.now ?? Date.now();
  const want = (id: string) => opts.gen.sections === null || opts.gen.sections.includes(id);
  const usable = (rows ?? [])
    .filter((r) => r.kind === "card" && r.explain_lang === opts.explainLang && r.l1 === opts.l1)
    .filter((r) => {
      const t = Date.parse(r.created_at);
      return Number.isFinite(t) && now - t >= 0 && now - t <= CARD_REUSE_WINDOW_MS;
    })
    .map((r) => ({ row: r, card: trustedCardFrom(r.card) }))
    .filter(({ card }) => {
      const g = card.gen;
      if (!g || g.v !== CARD_REUSE_VERSION) return false;
      if (g.levels !== opts.gen.levels || g.model !== opts.gen.model) return false;
      if (opts.gen.pro && !g.pro) return false;
      if (!coversSections(g.sections, opts.gen.sections)) return false;
      const ex = card.extras ?? {};
      if (!filledString(card.meaning_ja) || !filledString(card.example_sentence)) return false;
      if (!filledString(ex.usage_context)) return false;
      if (want("usage_chunks") && !filledList(ex.usage_chunks)) return false;
      if (want("related_words") && !filledList(ex.related_words)) return false;
      return true;
    })
    .sort((a, b) => Date.parse(b.row.created_at) - Date.parse(a.row.created_at));
  const best = usable[0];
  return best ? { ...best.card, created_at: best.row.created_at } : null;
}

/**
 * その語の控えの行を全部読む（`pickReusableCard` に渡す）。**投げない** — 読めなければ空（作り直す）。
 */
export async function loadGeneratedCardRows(
  admin: unknown,
  opts: { language: string; headword: string; now?: number },
): Promise<GeneratedCardRow[]> {
  const headword = (opts.headword ?? "").trim();
  if (!headword || headword.length > 100) return [];
  try {
    const db = admin as LooseDb;
    const q = db.from(TABLE) as {
      select: (c: string) => {
        eq: (
          k: string,
          v: string,
        ) => {
          eq: (
            k: string,
            v: string,
          ) => {
            gte: (
              k: string,
              v: string,
            ) => PromiseLike<{ data: GeneratedCardRow[] | null; error: LooseError }>;
          };
        };
      };
    };
    const now = opts.now ?? Date.now();
    const { data, error } = await q
      .select("language, headword, explain_lang, l1, kind, card, created_at")
      .eq("language", opts.language)
      .eq("headword", headword)
      .gte("created_at", new Date(now - CARD_REUSE_WINDOW_MS).toISOString());
    if (error) {
      if (!isMissingGeneratedCardsTable(error))
        console.warn("[generated-cards] 控えを読めない", error.message);
      return [];
    }
    return data ?? [];
  } catch (e) {
    console.warn("[generated-cards] 控えを読めない", e instanceof Error ? e.message : e);
    return [];
  }
}

/**
 * 控えのカードを、**いまの共有のメインの例文**のまま返してよいか（PR #189 の点検 P2）。カードは決まった文に
 * 札を付けて作るので、控えた後に共有の文が変わっていたら（作り直し・直し）、古い文と札を返さない。
 * 見出し語が入力と変わったカード（手紙 → 信）は入力の語の文を使わないので、比べない。
 */
export function reusableForMainSentence(
  card: { example_sentence?: string; headword_zh?: string },
  opts: { inputHeadword: string; currentMain: string | null; language: string },
): boolean {
  if (!opts.currentMain) return true;
  const head = (card.headword_zh ?? "").trim();
  if (head && !sameHeadword(head, opts.inputHeadword, opts.language)) return true;
  return sameSentence(card.example_sentence ?? "", opts.currentMain);
}

/**
 * 同じ見出し語か（学習言語ごとの比べ方 — 図鑑と同じ `normDexHeadword`: 大文字小文字・前後の空白・英語の冠詞・
 * かなの違いは同じ語）。`Apple` と `apple` を別の語として、決まった文を外さない（PR #189 の点検）。
 */
export function sameHeadword(a: string, b: string, language: string): boolean {
  const x = normDexHeadword(a, language);
  return x.length > 0 && x === normDexHeadword(b, language);
}

/**
 * `sameHeadword` が同じ語と言う書き方を、行を引くために並べる（語の行は見出し語そのままで引くので）。
 * 打った形・小文字・図鑑の比べ方の形（`normDexHeadword`）に加えて、英語は冠詞つき（a / an / the）、
 * 日本語はひらがなとカタカナの両方。比べ方と引き方を同じ物（`normDexHeadword`）から作るので、ずれない。
 */
export function headwordVariants(headword: string, language: string): string[] {
  const h = headword.trim();
  const core = normDexHeadword(h, language);
  const out = [h, h.toLowerCase(), core];
  if (core && language === "en") out.push(`a ${core}`, `an ${core}`, `the ${core}`);
  if (core && language === "ja") {
    out.push(core.replace(/[ぁ-ゖ]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 0x60)));
  }
  return [...new Set(out.filter((x) => x.length > 0))];
}

/**
 * **共有の語にもう在るメインの例文**（`generateCard`、2026-10-16 冰淇淋）。共有の行の例文は空の時だけ埋まるので、
 * 在る文は保存の後も残る — カードはその文に札を付けて作る。**投げない** — 読めなければ null（今までどおり作る）。
 */
export async function readExistingMainSentence(
  admin: unknown,
  opts: { language: string; headword: string },
): Promise<string | null> {
  const headword = (opts.headword ?? "").trim();
  if (!headword || headword.length > 100) return null;
  // 同じ語の書き方（`headwordVariants` — 大文字小文字・英語の冠詞・かな）で引き、`sameHeadword` が同じ語と
  // 言う行だけを使う。打った形の行が在ればそれを先に。
  const candidates = headwordVariants(headword, opts.language);
  try {
    const q = (admin as LooseDb).from("words") as {
      select: (c: string) => {
        eq: (
          k: string,
          v: string,
        ) => {
          in: (
            k: string,
            v: string[],
          ) => PromiseLike<{
            data: Array<{ headword?: string | null; example_sentence?: string | null }> | null;
            error: LooseError;
          }>;
        };
      };
    };
    const { data, error } = await q
      .select("headword, example_sentence")
      .eq("language", opts.language)
      .in("headword", candidates);
    if (error || !data) return null;
    // 同じ語の行のうち、並べた順（打った形 → 小文字 → 比べ方の形 → ほか）で先の物。
    const rank = (h: string | null | undefined) => {
      const i = candidates.indexOf(h ?? "");
      return i < 0 ? candidates.length : i;
    };
    const pick = data
      .filter((r) => sameHeadword(r.headword ?? "", headword, opts.language))
      .sort((a, b) => rank(a.headword) - rank(b.headword))[0];
    const s = (pick?.example_sentence ?? "").trim();
    return s || null;
  } catch {
    return null;
  }
}

export type GeneratedCardRow = {
  language: string;
  headword: string;
  explain_lang: string;
  l1: string;
  kind: string;
  card: unknown;
  created_at: string;
};

/**
 * 控えの行から1つを選ぶ（純粋関数）。
 *
 * - 期限（`GENERATED_CARD_TTL_MS`）を過ぎた物は使わない
 * - 鍵（`explainLang` / `l1`）を渡したら、その鍵のカード全体だけ
 * - 渡さなければ、カード全体を候補より優先し、その中で新しい物
 */
export function pickGeneratedCard(
  rows: readonly GeneratedCardRow[] | null | undefined,
  opts: { explainLang?: string; l1?: string; preferExplainLang?: string; now?: number } = {},
): { card: TrustedCard; kind: GeneratedCardKind } | null {
  const now = opts.now ?? Date.now();
  const fresh = (rows ?? []).filter((r) => {
    const t = Date.parse(r.created_at);
    return Number.isFinite(t) && now - t <= GENERATED_CARD_TTL_MS;
  });
  const keyed =
    opts.explainLang !== undefined
      ? fresh.filter(
          (r) =>
            r.kind === "card" && r.explain_lang === opts.explainLang && r.l1 === (opts.l1 ?? ""),
        )
      : fresh;
  // 呼んだ人の解説の言語のカード > その言語の候補 > 別の言語のカード > 言語の分からない候補。
  // 新しい共有の行は、最初に作った人の言語の行になる（`mayWriteSharedReaderText`）ので、その人の言語の
  // 物を先に使う — 別の言語の行になると、作った本人の画面には自分の解説ができるまで意味が出ない。
  const mine = (r: GeneratedCardRow) =>
    !!opts.preferExplainLang &&
    (r.kind === "card" ? r.explain_lang : candidateLanguage(r.card)) === opts.preferExplainLang;
  const rank = (r: GeneratedCardRow) =>
    r.kind === "card" ? (mine(r) ? 4 : 2) : mine(r) ? 3 : candidateLanguage(r.card) ? 1 : 0;
  const best = [...keyed].sort(
    (a, b) => rank(b) - rank(a) || Date.parse(b.created_at) - Date.parse(a.created_at),
  )[0];
  if (!best) return null;
  return {
    card: trustedCardFrom(best.card),
    kind: best.kind === "card" ? "card" : "candidate",
  };
}

/**
 * **候補の控え**（意味と読みだけ）。候補の行の鍵には言語が無い（`recordGeneratedCards` は候補の
 * `explain_lang` を空にする）ので、意味を書いた言語を中身の `extras.explain_lang` に刻む。共有の行を
 * この控えから作る時、意味と目印が同じ言語になる（2026-10-20、言語が混ざらないように）。
 */
export function candidateCard(
  card: Record<string, string | undefined>,
  explainLang: string,
): Record<string, unknown> {
  return { ...card, extras: { explain_lang: explainLang } };
}

/** 候補の控えの、意味を書いた言語（2026-10-20 より前の控えは目印が無く `null`）。 */
export function candidateLanguage(raw: unknown): string | null {
  const ex = trustedCardFrom(raw).extras;
  const v = ex?.explain_lang;
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

type LooseError = { message?: string; code?: string } | null;

/** 表がまだ無い（移行待ち）か。 */
export function isMissingGeneratedCardsTable(error: LooseError): boolean {
  if (!error) return false;
  if (error.code === "PGRST205" || error.code === "42P01") return true;
  return new RegExp(TABLE).test(error.message ?? "");
}

type LooseDb = {
  from: (t: string) => unknown;
};

/**
 * 控えを残す。**投げない**（控えが残らないと、その語は保存の時に中身なしになるだけ）。
 * 同じ鍵の控えは新しい物で置き換える。
 */
export async function recordGeneratedCards(
  admin: unknown,
  entries: ReadonlyArray<{
    language: string;
    headword: string;
    explainLang?: string;
    l1?: string;
    kind: GeneratedCardKind;
    card: unknown;
  }>,
  now: Date = new Date(),
): Promise<boolean> {
  const seen = new Set<string>();
  const rows = [];
  for (const e of entries) {
    const headword = (e.headword ?? "").trim();
    const language = (e.language ?? "").trim();
    if (!headword || !language || headword.length > 100) continue;
    const explain_lang = e.kind === "card" ? (e.explainLang ?? "") : "";
    const l1 = e.kind === "card" ? (e.l1 ?? "") : "";
    const k = `${language}\u0000${headword}\u0000${explain_lang}\u0000${l1}`;
    if (seen.has(k)) continue;
    seen.add(k);
    const card = trustedCardFrom(e.card);
    if (!card.meaning_ja && !card.extras) continue;
    rows.push({
      language,
      headword,
      explain_lang,
      l1,
      kind: e.kind,
      card,
      created_at: now.toISOString(),
    });
  }
  if (rows.length === 0) return false;
  try {
    const db = admin as LooseDb;
    const t = db.from(TABLE) as {
      upsert: (r: unknown, o: unknown) => PromiseLike<{ error: LooseError }>;
    };
    const { error } = await t.upsert(rows, { onConflict: "language,headword,explain_lang,l1" });
    if (error) {
      if (isMissingGeneratedCardsTable(error)) {
        console.warn("[generated-cards] 表がまだ無い（移行待ち）", error.message);
      } else {
        console.warn("[generated-cards] 控えを残せない", error.message);
      }
      return false;
    }
    // 古い控えを時々消す（毎回は消さない — 消すのはおまけ）。
    if (Math.random() < 0.02) {
      const cutoff = new Date(now.getTime() - GENERATED_CARD_TTL_MS).toISOString();
      const d = db.from(TABLE) as {
        delete: () => { lt: (c: string, v: string) => PromiseLike<{ error: LooseError }> };
      };
      const { error: delErr } = await d.delete().lt("created_at", cutoff);
      if (delErr) console.warn("[generated-cards] 古い控えを消せない", delErr.message);
    }
    return true;
  } catch (e) {
    console.warn("[generated-cards] 控えを残せない", e instanceof Error ? e.message : e);
    return false;
  }
}

/**
 * 控えを引く。表が無ければ `available: false`（呼ぶ側は前の動きに戻る）。
 * 読めない（通信の失敗など）ときは `available: true, card: null` — **画面の文に戻らない**。
 */
export async function findGeneratedCard(
  admin: unknown,
  opts: {
    language: string;
    headword: string;
    explainLang?: string;
    l1?: string;
    /** 鍵で絞らない時、この解説の言語のカードを先に選ぶ。 */
    preferExplainLang?: string;
    now?: number;
  },
): Promise<GeneratedCardLookup> {
  try {
    const db = admin as LooseDb;
    const q = db.from(TABLE) as {
      select: (c: string) => {
        eq: (
          k: string,
          v: string,
        ) => {
          eq: (
            k: string,
            v: string,
          ) => {
            gte: (
              k: string,
              v: string,
            ) => PromiseLike<{ data: GeneratedCardRow[] | null; error: LooseError }>;
          };
        };
      };
    };
    const now = opts.now ?? Date.now();
    const { data, error } = await q
      .select("language, headword, explain_lang, l1, kind, card, created_at")
      .eq("language", opts.language)
      .eq("headword", opts.headword)
      .gte("created_at", new Date(now - GENERATED_CARD_TTL_MS).toISOString());
    if (error) {
      if (isMissingGeneratedCardsTable(error)) return { available: false };
      console.warn("[generated-cards] 控えを読めない", error.message);
      return { available: true, card: null, kind: null };
    }
    const picked = pickGeneratedCard(data, {
      explainLang: opts.explainLang,
      preferExplainLang: opts.preferExplainLang,
      l1: opts.l1,
      now,
    });
    return picked
      ? { available: true, card: picked.card, kind: picked.kind }
      : { available: true, card: null, kind: null };
  } catch (e) {
    console.warn("[generated-cards] 控えを読めない", e instanceof Error ? e.message : e);
    return { available: true, card: null, kind: null };
  }
}

/**
 * **サーバが作ったカードで、既に在る共有の語の空の所を埋める**（`generateCard` から）。
 *
 * キャッチの画面は候補の意味だけでカードを先に出し、`generateCard` の完成を待たずに
 * 保存できる。その時に作られた語の行は、控え（候補）か辞書の分しか中身が無い。
 * カードが出来上がったら、その中身で**空の列・空の項目だけ**を埋める（`fillEmptySharedColumns`
 * / `fillEmptySharedExtras` — 埋まっている所と人が確かめた語は触らない）。
 * 投げない（埋まらなくても、単語の詳細を開いた時の自動生成が埋める）。
 */
export async function fillSharedWordFromCard(
  admin: unknown,
  /** `explainLang` = カードを書いた言語（読む人の言語）。別の言語の行の意味・訳・解説は埋めない。 */
  opts: { language: string; headwords: readonly string[]; card: TrustedCard; explainLang: string },
): Promise<number> {
  const heads = [...new Set(opts.headwords.map((h) => (h ?? "").trim()).filter(Boolean))];
  if (heads.length === 0) return 0;
  type WordRow = Record<string, unknown> & { id: string; source?: string | null };
  const db = admin as {
    from: (t: string) => {
      select: (c: string) => {
        eq: (
          k: string,
          v: string,
        ) => {
          in: (
            k: string,
            v: string[],
          ) => PromiseLike<{ data: WordRow[] | null; error: LooseError }>;
        };
      };
      update: (row: unknown) => {
        eq: (k: string, v: string) => PromiseLike<{ error: LooseError }>;
      };
    };
  };
  try {
    const { data: rows, error } = await db
      .from("words")
      .select(
        "id, source, extras, meaning_ja, reading_zhuyin, pinyin, part_of_speech, level, example_sentence, example_translation",
      )
      .eq("language", opts.language)
      .in("headword", heads);
    if (error) {
      console.warn("[generated-cards] 語を読めない", error.message);
      return 0;
    }
    let written = 0;
    for (const row of rows ?? []) {
      // 例文の訳・場面の札・パーツは**文と組で**埋める（2026-10-15 眼鏡、`example-patterns.ts`）。
      // 前から在る文の横に、別の文のために書いた訳・札を入れない。
      let update: Record<string, unknown> = guardExampleColumns(
        fillEmptySharedColumns(
          row as never,
          sharedColumnsFromCard(opts.card as Record<string, unknown>),
          { verified: row.source === "verified", lang: opts.explainLang },
        ),
        row as { example_sentence?: string | null },
        opts.card,
      );
      const sentence =
        (update.example_sentence as string | undefined) ??
        (row.example_sentence as string | null | undefined);
      const extras = fillEmptySharedExtras(
        row.extras,
        alignExampleExtras(opts.card.extras ?? null, sentence),
        row as never,
      );
      if (extras) update.extras = extras;
      update = claimSharedRowLanguage(update, row as never, opts.explainLang);
      if (Object.keys(update).length === 0) continue;
      const { error: upErr } = await db.from("words").update(update).eq("id", row.id);
      if (upErr) console.warn("[generated-cards] 語を埋められない", upErr.message);
      else written++;
    }
    return written;
  } catch (e) {
    console.warn("[generated-cards] 語を埋められない", e instanceof Error ? e.message : e);
    return 0;
  }
}
