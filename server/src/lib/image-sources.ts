/**
 * **学習言語で探す**写真の出所と、集めた候補の「その語そのものか」の判定・重複の除去（純粋な部分）。
 *
 * ## オーナー報告 2026-10-09
 * > 「嘴邊肉の画像が明らかに英語で検索された画像が表示される。必ず学習言語で検索して。
 * >  また学習者が知りたい学びたいその単語が表示される画像にして。」
 *
 * 文字検索「豚の口の周りの肉」→ 嘴邊肉（台湾の黑白切の豚の頬・口の周りの肉）を選ぶと、札の絵の
 * 候補は大鍋の煮込み・パエリア（2回）・皿の牛肉や鴨・たれの掛かった煮込みだった。
 * 探していたのは英語の `pork cheek` だけで、英語の写真の出所（Unsplash・コモンズの英語）は
 * 「pork cheek が材料に入った西洋の料理」を返す。題に `pork cheek` が入っていたので
 * 「説明で確か」と見なされ、絵の確かめ（`image-sense.ts`）も走らなかった。同じ写真も2回並んだ。
 *
 * ## 直し方（ここに置く物）
 * 1. **学習言語の見出し語そのもので探す出所**（中国語の題・説明・分類・タグを持つ所）:
 *    - Wikimedia Commons（ファイルの題・説明・分類を `"嘴邊肉"` で）
 *    - その言語の Wikipedia の、見出し語の記事の**先頭の絵**（Commons に在る自由な物だけ）
 *    - Openverse（CC の写真の索引。Flickr の台湾の料理の写真に中国語の題・タグが付いている）
 *    英語の出所は**足りない時の補い**（並べる時は必ず後ろ）。
 * 2. **「その語そのもの」の判定**（`learningMatch`）: 見出し語が字の切れ目で出てくる物だけを
 *    「確か」（exact）とする。`臭豆腐` の中の `豆腐`、`嘴邊肉麵` の中の `嘴邊肉` は別の物なので
 *    「近い」（related）止まり — 絵を見て確かめる。
 * 3. **重複を除く**（`dedupeImages`）: 同じ URL・同じ写真の番号（Unsplash・Flickr・Commons の
 *    ファイル名）・同じ作者の同じ説明。
 *
 * 新しい出所（有料のウェブ画像検索など — 費用と著作権はオーナーの判断が要る）は
 * `ImageSearchProvider` を1つ書いて `image-providers.ts` の一覧に足し、環境変数
 * `IMAGE_SEARCH_PROVIDERS` で有効にする。ここには外の世界に触れる物を入れない。
 */

/** 候補（並べ直しの間だけ説明の字 `text` を持つ）。 */
export type SourcedImage = {
  url: string;
  thumb: string;
  source: string;
  credit?: { name: string; link: string };
  text?: string;
};

/** 学習言語の出所の候補。`lead` は見出し語の記事の先頭の絵（記事の題が見出し語そのもの）。 */
export type LaneHit = SourcedImage & { lane: "learning" | "english"; lead?: boolean };

/** 判定の済んだ候補。 */
export type RankedImage = SourcedImage & {
  /** 学習言語の見出し語そのものの写真と言える（字の切れ目で出てくる・記事の先頭の絵）。 */
  exact?: boolean;
};

/** 出所に渡す問い。 */
export type ProviderQuery = {
  /** 学習言語の出所: 見出し語と同じ語の別の書き方（簡体字など）。英語の出所: 英語の検索語。 */
  terms: string[];
  /** 学習言語の、意味を絞る語（`黑白切`）。無ければ無し。 */
  context?: string | null;
  /** 学習言語（`zh-TW`）。 */
  language: string;
  limit: number;
};

/** 出所が外へ出る時の道具（試験で差し替える）。 */
export type ProviderIO = {
  fetch: (url: string, init?: RequestInit) => Promise<Response>;
  /** この出所に許す時間（ms）。 */
  timeoutMs: number;
  env: Record<string, string | undefined>;
};

/**
 * 写真の出所1つ。`lane` が `learning` の物は学習言語の語で、`english` の物は英語の検索語で引く。
 * 失敗しても投げない（空を返す）。
 */
export type ImageSearchProvider = {
  id: string;
  lane: "learning" | "english";
  search: (q: ProviderQuery, io: ProviderIO) => Promise<LaneHit[]>;
};

const HAN_OR_KANA = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

const HAN_ONLY = /^\p{Script=Han}$/u;

/** 漢字1字（`桃` `杯`）。 */
function isSingleHan(s: string): boolean {
  const chars = [...s.trim()];
  return chars.length === 1 && HAN_ONLY.test(chars[0]);
}

/**
 * **1字の見出し語**（オーナー報告 2026-10-09「桃の写真になぜか鳩の画像が出る」）。
 *
 * `桃` で引くと、学習言語の出所は `桃園市信鴿協會`（桃園の鳩の協会の貼り紙）や、`桃` という
 * 名前の人の写真を返す。Openverse は漢字を1字ずつ引き、Commons の題・タグにも1字は
 * 他の意味（地名・人の名前）でよく出てくる。1字の語は題・タグで「その語そのもの」と言えないので、
 * どの写真も絵を見て確かめる（`images.functions.ts`）。意味を決める AI がくれた2字以上の
 * 言い方（`桃子` `水蜜桃`）で引き直す。
 */
export function isWeakHeadword(headword: string): boolean {
  return isSingleHan(headword);
}

/** 学習言語の語で探す意味がある（英語を学ぶ人の英語の見出しは、英語の出所で足りる）。 */
export function wantsLearningLane(word: { headword: string; language?: string | null }): boolean {
  const lang = (word.language ?? "").toLowerCase();
  if (!word.headword.trim()) return false;
  if (HAN_OR_KANA.test(word.headword)) return true;
  return !!lang && !lang.startsWith("en");
}

/** Wikipedia の言語の頭（`zh-TW` → `zh`）。使えない形なら null。 */
export function wikiLanguage(language: string | null | undefined): string | null {
  const base = (language ?? "").toLowerCase().split(/[-_]/)[0];
  return /^[a-z]{2,3}$/.test(base) ? base : null;
}

/** 字を比べる形にそろえる（全角・半角、大文字・小文字、空白）。 */
function norm(s: string): string {
  return s.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\-]/g, "\\$&");
}

/** 見出し語の別の書き方（簡体字など）を揃える。見出し語と同じ物・長すぎる物は落とす。 */
export function learningForms(headword: string, variants?: ReadonlyArray<string> | null): string[] {
  const out: string[] = [];
  for (const raw of [headword, ...(variants ?? [])]) {
    const v = norm(raw ?? "");
    if (!v || v.length > 24 || out.includes(v)) continue;
    out.push(v);
  }
  return out;
}

/**
 * その説明に、見出し語が**どの強さで**出てくるか。
 *
 * - `exact`: 字の切れ目で出てくる（前後が漢字・かなでない。題 `嘴邊肉.jpg`・タグ `嘴邊肉`・
 *   分類 `Category:嘴邊肉`・`台南 / 嘴邊肉`）。英字の語は語の切れ目で。
 * - `related`: 他の語の中に入っている（`臭豆腐` の `豆腐`）・意味を絞る語（`黑白切`）だけ出てくる
 * - `none`: 出てこない（Openverse は漢字を1字ずつ引くので `肉` だけ合った物も返る — それは捨てる）
 *
 * 1字の語（`桃`）は単独で出てきても `related` 止まり、長い語の中（`桃園`）なら `none`。
 */
export function learningMatch(
  text: string | undefined,
  forms: ReadonlyArray<string>,
  context?: string | null,
): "exact" | "related" | "none" {
  const t = norm(text ?? "");
  if (!t) return "none";
  let related = false;
  for (const f of forms) {
    if (!f) continue;
    if (/^[a-z0-9' -]+$/.test(f)) {
      if (new RegExp(`(^|[^a-z0-9])${escapeRe(f)}($|[^a-z0-9])`, "i").test(t)) return "exact";
      continue;
    }
    // 1字の語（`桃`）は、題・タグに単独で出てきても「確か」と言わない（人の名前・地名の略・
    // 1字ずつ切ったタグのことが多い）。長い語の中（`桃園`）に在る物は手がかりにもしない。
    const single = isSingleHan(f);
    let from = 0;
    for (;;) {
      const i = t.indexOf(f, from);
      if (i < 0) break;
      const before = i > 0 ? t[i - 1] : "";
      const after = t.slice(i + f.length, i + f.length + 1);
      const bounded = !HAN_OR_KANA.test(before) && !HAN_OR_KANA.test(after);
      if (bounded && !single) return "exact";
      if (bounded || !single) related = true;
      from = i + 1;
    }
  }
  const c = norm(context ?? "");
  if (c && t.includes(c)) related = true;
  return related ? "related" : "none";
}

/** 写真の正体の番号（同じ写真が別の URL・大きさで来ても同じになる）。分からなければ null。 */
export function photoIdentity(url: string): string | null {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  const host = u.hostname.toLowerCase();
  const path = decodeURIComponent(u.pathname);
  if (host.endsWith("unsplash.com")) {
    const m = /\/((?:premium_)?photo-[\w-]+)/.exec(path);
    if (m) return `unsplash:${m[1].replace(/^premium_/, "")}`;
  }
  if (host === "upload.wikimedia.org") {
    const last = path.split("/").filter(Boolean).pop() ?? "";
    // 縮小版（`960px-名前.jpg`）と原寸（`名前.jpg`）を同じに。
    const name = last.replace(/^\d+px-/, "").toLowerCase();
    if (name) return `commons:${name}`;
  }
  if (host.endsWith("staticflickr.com")) {
    const m = /\/(\d+)_[0-9a-f]+/.exec(path);
    if (m) return `flickr:${m[1]}`;
  }
  if (host === "api.openverse.org") {
    const m = /\/images\/([0-9a-f-]{16,})/i.exec(path);
    if (m) return `openverse:${m[1].toLowerCase()}`;
  }
  return `${host}${u.pathname}`;
}

/** 同じ作者の同じ説明（同じ写真の別の版・ほとんど同じ写真）を見分ける鍵。短すぎれば null。 */
function lookalikeKey(c: SourcedImage): string | null {
  const who = norm(c.credit?.name ?? "").replace(/\s*\/.*$/, "");
  const what = norm(c.text ?? "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .slice(0, 80);
  if (!who || what.length < 12) return null;
  return `${who}\u0000${what}`;
}

/**
 * 重複を除く（先に来た物を残す）。オーナー報告 2026-10-09「同じパエリアが2回」。
 * 同じ URL・同じ写真の番号・同じ作者の同じ説明は1枚に。
 */
export function dedupeImages<T extends SourcedImage>(list: ReadonlyArray<T>): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const c of list) {
    const keys = [
      `url:${c.url.split("?")[0]}`,
      photoIdentity(c.url),
      c.thumb ? photoIdentity(c.thumb) : null,
      lookalikeKey(c),
    ].filter((k): k is string => !!k);
    if (keys.some((k) => seen.has(k))) continue;
    for (const k of keys) seen.add(k);
    out.push(c);
  }
  return out;
}

/**
 * 学習言語の候補と英語の候補を1つの列にする。
 *
 * 1. 見出し語そのもの（`exact`）: 記事の先頭の絵 → 出所の順
 * 2. 学習言語で近い物（`related`）
 * 3. 英語の出所の物（もう並べ直してある順。説明に見出し語が切れ目で出てくれば 1. へ）
 *
 * 学習言語の出所で見出し語も絞る語も出てこない物は捨てる（1字ずつ当たっただけ）。
 * `dropLearning` が真の物（違う物の手がかりが在る）は、見出し語そのものでなければ捨てる。
 */
export function mergeLanes(input: {
  learning: ReadonlyArray<LaneHit>;
  english: ReadonlyArray<SourcedImage>;
  forms: ReadonlyArray<string>;
  context?: string | null;
  dropLearning?: (c: SourcedImage) => boolean;
}): RankedImage[] {
  const lead: RankedImage[] = [];
  const exact: RankedImage[] = [];
  const related: RankedImage[] = [];
  const english: RankedImage[] = [];
  const strip = (c: LaneHit | SourcedImage): SourcedImage => ({
    url: c.url,
    thumb: c.thumb,
    source: c.source,
    ...(c.credit ? { credit: c.credit } : {}),
    ...(c.text !== undefined ? { text: c.text } : {}),
  });
  for (const h of input.learning) {
    const level = h.lead ? "exact" : learningMatch(h.text, input.forms, input.context);
    if (level === "none") continue;
    if (level === "exact") (h.lead ? lead : exact).push({ ...strip(h), exact: true });
    else if (!input.dropLearning?.(h)) related.push(strip(h));
  }
  for (const c of input.english) {
    if (input.forms.length && learningMatch(c.text, input.forms) === "exact")
      exact.push({ ...strip(c), exact: true });
    else english.push(strip(c));
  }
  return dedupeImages([...lead, ...exact, ...related, ...english]);
}

// ---------------------------------------------------------------------------
// 出所ごとの URL と答えの読み替え（取りに行くのは `image-providers.ts`）
// ---------------------------------------------------------------------------

/** Commons の検索に投げる字（`filetype:bitmap "嘴邊肉" OR "嘴边肉"`）。 */
export function commonsLearningSearch(terms: ReadonlyArray<string>, context?: string | null) {
  const quoted = terms
    .map((t) => t.replace(/["\\]/g, "").trim())
    .filter(Boolean)
    .map((t) => `"${t}"`);
  if (quoted.length === 0) return "";
  const c = (context ?? "").replace(/["\\]/g, "").trim();
  // 絞る語は引用しない（その語の写真の、言い換えた題も拾う）。
  return c ? `${quoted[0]} ${c}` : quoted.join(" OR ");
}

/** Wikipedia の記事の先頭の絵の名前を聞く URL（簡体字・繁体字の題は相手が読み替える）。 */
export function wikiLeadUrl(lang: string, title: string): string {
  const u = new URL(`https://${lang}.wikipedia.org/w/api.php`);
  u.searchParams.set("action", "query");
  u.searchParams.set("format", "json");
  u.searchParams.set("formatversion", "2");
  u.searchParams.set("prop", "pageimages");
  u.searchParams.set("piprop", "name");
  u.searchParams.set("titles", title);
  u.searchParams.set("redirects", "1");
  u.searchParams.set("converttitles", "1");
  return u.toString();
}

type WikiLeadResponse = {
  query?: {
    redirects?: Array<{ from?: string; to?: string }>;
    pages?: Array<{ title?: string; missing?: boolean; pageimage?: string }>;
  };
};

/**
 * 記事の先頭の絵のファイル名と、その記事が見出し語そのものの記事か
 * （別の記事へ回された — `嘴邊肉` → `黑白切` — なら見出し語そのものではない）。
 */
export function readWikiLead(
  json: WikiLeadResponse,
): { file: string; sameArticle: boolean } | null {
  const page = json.query?.pages?.[0];
  if (!page || page.missing || !page.pageimage) return null;
  return { file: page.pageimage, sameArticle: (json.query?.redirects ?? []).length === 0 };
}

/** Commons の1つのファイルの情報を聞く URL（作者と使い方の条件を読むため）。 */
export function commonsFileInfoUrl(file: string, width: number): string {
  const u = new URL("https://commons.wikimedia.org/w/api.php");
  u.searchParams.set("action", "query");
  u.searchParams.set("format", "json");
  u.searchParams.set("titles", `File:${file.replace(/^File:/i, "")}`);
  u.searchParams.set("prop", "imageinfo");
  u.searchParams.set("iiprop", "url|extmetadata");
  u.searchParams.set("iiurlwidth", String(width));
  return u.toString();
}

/** Openverse の検索の URL。**商用で使えて手を加えてよい**条件の物だけ（NC・ND を外す）。 */
export function openverseSearchUrl(
  terms: ReadonlyArray<string>,
  context: string | null | undefined,
  limit: number,
) {
  const quoted = terms
    .map((t) => t.replace(/["\\|]/g, "").trim())
    .filter(Boolean)
    .map((t) => `"${t}"`);
  const c = (context ?? "").replace(/["\\|]/g, "").trim();
  const q = c ? `${quoted[0] ?? ""} ${c}`.trim() : quoted.join(" | ");
  const u = new URL("https://api.openverse.org/v1/images/");
  u.searchParams.set("q", q.slice(0, 190));
  u.searchParams.set("page_size", String(Math.max(1, Math.min(20, limit))));
  u.searchParams.set("license_type", "commercial,modification");
  u.searchParams.set("mature", "false");
  return u.toString();
}

export type OpenverseResult = {
  id?: string;
  title?: string | null;
  url?: string | null;
  thumbnail?: string | null;
  creator?: string | null;
  license?: string | null;
  license_version?: string | null;
  foreign_landing_url?: string | null;
  tags?: Array<{ name?: string | null } | null> | null;
  mature?: boolean;
};

/** 帰属の要らない条件（作者が読めなくても出してよい）。 */
const NO_ATTRIBUTION = new Set(["cc0", "pdm"]);

function licenseLabel(license: string, version: string | null | undefined): string {
  const l = license.toLowerCase();
  if (l === "pdm") return "Public Domain Mark";
  if (l === "cc0") return "CC0";
  return `CC ${l.toUpperCase()}${version ? ` ${version}` : ""}`;
}

/** Flickr の写真は決まった大きさの版がある（`_w` = 幅 400）。一覧と AI にはそれを使う。 */
export function flickrSmall(url: string): string | null {
  const m = /^(https:\/\/live\.staticflickr\.com\/\d+\/\d+_[0-9a-f]+)(?:_[a-z])?\.jpg$/i.exec(url);
  return m ? `${m[1]}_w.jpg` : null;
}

/**
 * Openverse の答えを候補に直す。
 *
 * - 原寸の置き場が保存を許した置き場（`isAllowedHost`）なら原寸を、そうでなければ
 *   Openverse の縮小版（`api.openverse.org/.../thumb/`）を保存にも使う
 * - 作者の読めない物は、帰属の要らない条件（CC0・PDM）の時だけ残す
 */
export function openverseCandidates(
  json: { results?: OpenverseResult[] | null } | null | undefined,
  isAllowedHost: (url: string) => boolean,
  limit: number,
): LaneHit[] {
  const out: LaneHit[] = [];
  for (const r of json?.results ?? []) {
    if (!r || r.mature) continue;
    const license = (r.license ?? "").toLowerCase();
    if (!license || /nc|nd/.test(license)) continue;
    const creator = (r.creator ?? "").trim();
    if (!creator && !NO_ATTRIBUTION.has(license)) continue;
    const thumbApi =
      r.thumbnail && /^https:\/\/api\.openverse\.org\//.test(r.thumbnail) ? r.thumbnail : null;
    // 原寸を使うのは Flickr の決まった大きさの版だけ（`_o` の原寸・Commons の原寸は数十 MB のことがあり、
    // 保存の大きさの上限 `byte-cap.ts` で断られる）。他は Openverse の縮小版。
    const original =
      r.url && isAllowedHost(r.url) && flickrSmall(r.url) && !/_o\.jpg$/i.test(r.url)
        ? r.url
        : null;
    const url = original ?? thumbApi;
    if (!url) continue;
    const thumb = (original && flickrSmall(original)) || thumbApi || url;
    const tags = (r.tags ?? [])
      .map((t) => (t?.name ?? "").trim())
      .filter(Boolean)
      .slice(0, 30);
    const label = licenseLabel(license, r.license_version);
    out.push({
      url,
      thumb,
      source: "openverse",
      lane: "learning",
      credit: {
        name: creator ? `${creator} / ${label}` : label,
        link: r.foreign_landing_url || url,
      },
      text: [r.title ?? "", ...tags].join(" | ").slice(0, 600),
    });
    if (out.length >= limit) break;
  }
  return out;
}
