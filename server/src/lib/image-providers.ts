/**
 * **写真の出所**（外の世界に触れる部分）。何を・なぜ探すかは `image-sources.ts`。
 *
 * 学習言語の出所（`lane: "learning"`。見出し語そのもので引く）:
 *  - `wikipedia` … その言語の Wikipedia の見出し語の記事の先頭の絵（Commons に在る自由な物だけ）
 *  - `commons`   … Wikimedia Commons のファイルを見出し語で（題・説明・分類）
 *  - `openverse` … Openverse（CC の写真の索引。Flickr など）。鍵が無くても使えるが、匿名は
 *                  回数が少ない。`OPENVERSE_CLIENT_ID` / `OPENVERSE_CLIENT_SECRET` が在れば
 *                  登録した利用者として引く（回数が増える）。429 が返ったらしばらく休む。
 *
 * 英語の出所（`lane: "english"`。補い）: `unsplash`（`UNSPLASH_ACCESS_KEY`）・`commons-en`。
 *
 * **出所を足す・止める**: `IMAGE_SEARCH_PROVIDERS`（カンマ区切りの id。無ければ全部）。
 * 有料のウェブ画像検索（Brave・Google など）は費用と著作権の判断がオーナーに要るので入れていない。
 * 足す時は `ImageSearchProvider` を1つ書いて `ALL_PROVIDERS` に並べ、この変数で有効にする。
 *
 * どの出所も、失敗・時間切れでは投げずに空を返す（画像の節を止めない）。
 */
import {
  commonsCandidates,
  commonsSearchUrl,
  COMMONS_IMAGE_WIDTH,
  type CommonsResponse,
} from "./commons-images";
import { ALLOWED_IMAGE_HOSTS, IMAGE_FETCH_USER_AGENT } from "./image-proxy";
import {
  commonsFileInfoUrl,
  commonsLearningSearch,
  openverseCandidates,
  openverseSearchUrl,
  readWikiLead,
  wikiLanguage,
  wikiLeadUrl,
  type ImageSearchProvider,
  type LaneHit,
  type ProviderIO,
} from "./image-sources";

/** 持ち時間の残り（`started` から数えて）だけを許す道具。 */
function rest(io: ProviderIO, started: number): ProviderIO {
  return { ...io, timeoutMs: Math.max(300, io.timeoutMs - (Date.now() - started)) };
}

function isAllowedHost(url: string): boolean {
  try {
    const u = new URL(url);
    return u.protocol === "https:" && ALLOWED_IMAGE_HOSTS.has(u.hostname.toLowerCase());
  } catch {
    return false;
  }
}

async function getJson(io: ProviderIO, url: string, init: RequestInit = {}): Promise<Response> {
  return io.fetch(url, {
    ...init,
    headers: {
      "User-Agent": IMAGE_FETCH_USER_AGENT,
      Accept: "application/json",
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(io.timeoutMs),
  });
}

/** Commons の答えを学習言語の候補に。 */
function commonsHits(
  json: CommonsResponse,
  limit: number,
  lane: "learning" | "english",
): LaneHit[] {
  return commonsCandidates(json, limit).map((c) => ({ ...c, source: "commons", lane }));
}

const commonsLearning: ImageSearchProvider = {
  id: "commons",
  lane: "learning",
  async search(q, io) {
    const search = commonsLearningSearch(q.terms, q.context);
    if (!search) return [];
    try {
      const res = await getJson(io, commonsSearchUrl(search, q.limit));
      if (!res.ok) return [];
      return commonsHits((await res.json()) as CommonsResponse, q.limit, "learning");
    } catch (e) {
      console.warn(
        "commons (learning) search failed",
        e instanceof Error ? e.message.slice(0, 60) : e,
      );
      return [];
    }
  },
};

const wikipediaLead: ImageSearchProvider = {
  id: "wikipedia",
  lane: "learning",
  async search(q, io) {
    const lang = wikiLanguage(q.language);
    const title = q.terms[0];
    // 引き直す時（絞る語・別の書き方）は記事を見ない（同じ記事をもう見ている）。
    if (!lang || !title || q.context || q.terms.length !== 1) return [];
    const started = Date.now();
    try {
      const res = await getJson(io, wikiLeadUrl(lang, title));
      if (!res.ok) return [];
      const lead = readWikiLead(await res.json());
      if (!lead) return [];
      // 作者と使い方の条件は Commons に聞く（Commons に無い絵 = その版だけの絵は使わない）。
      // 2回目の問い合わせも、この出所の持ち時間の残りだけ（2回で倍の時間を使わない）。
      const info = await getJson(
        rest(io, started),
        commonsFileInfoUrl(lead.file, COMMONS_IMAGE_WIDTH),
      );
      if (!info.ok) return [];
      return commonsHits((await info.json()) as CommonsResponse, 1, "learning").map((c) => ({
        ...c,
        lead: lead.sameArticle,
        // 見出し語そのものの記事の絵なら、説明に見出し語を添える（判定に使う）。
        // 別の記事へ回された（`嘴邊肉` → `黑白切`）絵は添えない — 絵を見て確かめる。
        text: lead.sameArticle ? `${title} | ${c.text}` : c.text,
      }));
    } catch (e) {
      console.warn("wikipedia lead failed", e instanceof Error ? e.message.slice(0, 60) : e);
      return [];
    }
  },
};

// --- Openverse ---------------------------------------------------------------

/** 429 の後、ここまで Openverse を呼ばない（ms の時刻）。 */
let openverseRestUntil = 0;
let openverseToken: { value: string; until: number } | null = null;
/** 鍵の受け取りに失敗したら、しばらく匿名で引く（毎回失敗する受け取りで待たせない）。 */
let openverseTokenFailedUntil = 0;

/** 試験から Openverse の覚え（休み・鍵）を消す。 */
export function resetOpenverseState() {
  openverseRestUntil = 0;
  openverseToken = null;
  openverseTokenFailedUntil = 0;
}

const OPENVERSE_REST_MS = 5 * 60_000;

async function openverseAuth(io: ProviderIO): Promise<string | null> {
  const id = io.env.OPENVERSE_CLIENT_ID?.trim();
  const secret = io.env.OPENVERSE_CLIENT_SECRET?.trim();
  if (!id || !secret) return null;
  const now = Date.now();
  if (openverseToken && openverseToken.until > now) return openverseToken.value;
  if (openverseTokenFailedUntil > now) return null;
  try {
    const res = await io.fetch("https://api.openverse.org/v1/auth_tokens/token/", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": IMAGE_FETCH_USER_AGENT,
      },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: id,
        client_secret: secret,
      }).toString(),
      signal: AbortSignal.timeout(io.timeoutMs),
    });
    if (!res.ok) throw new Error(`token ${res.status}`);
    const json = (await res.json()) as { access_token?: string; expires_in?: number };
    if (!json.access_token) throw new Error("token missing");
    const ttl = Math.max(60, Math.min(json.expires_in ?? 3600, 12 * 3600)) * 1000;
    openverseToken = { value: json.access_token, until: now + ttl - 60_000 };
    return openverseToken.value;
  } catch (e) {
    console.warn("openverse token failed", e instanceof Error ? e.message.slice(0, 60) : e);
    openverseTokenFailedUntil = now + OPENVERSE_REST_MS;
    return null;
  }
}

const openverse: ImageSearchProvider = {
  id: "openverse",
  lane: "learning",
  async search(q, io) {
    if (Date.now() < openverseRestUntil) return [];
    if (q.terms.length === 0) return [];
    try {
      const started = Date.now();
      const token = await openverseAuth(io);
      const res = await getJson(
        rest(io, started),
        openverseSearchUrl(q.terms, q.context, q.limit),
        {
          headers: token ? { Authorization: `Bearer ${token}` } : {},
        },
      );
      if (res.status === 429) {
        // 回数の上限。言われた間（無ければ5分）休み、その間は他の出所だけで探す。
        const retry = Number(res.headers.get("retry-after"));
        openverseRestUntil =
          Date.now() +
          (Number.isFinite(retry) && retry > 0 ? Math.min(retry, 3600) * 1000 : OPENVERSE_REST_MS);
        console.warn("openverse rate limited");
        return [];
      }
      if (res.status === 401 || res.status === 403) openverseToken = null;
      if (!res.ok) return [];
      return openverseCandidates(await res.json(), isAllowedHost, q.limit);
    } catch (e) {
      console.warn("openverse search failed", e instanceof Error ? e.message.slice(0, 60) : e);
      return [];
    }
  },
};

// --- 英語の出所（補い） -------------------------------------------------------

type UnsplashResponse = {
  results?: Array<{
    urls: { regular: string; small: string };
    user: { name: string; links: { html: string } };
    alt_description?: string | null;
    description?: string | null;
    tags?: Array<{ title?: string | null } | null> | null;
  }>;
};

const unsplash: ImageSearchProvider = {
  id: "unsplash",
  lane: "english",
  async search(q, io) {
    const key = io.env.UNSPLASH_ACCESS_KEY;
    const query = q.terms[0];
    if (!key || !query) return [];
    try {
      const url = new URL("https://api.unsplash.com/search/photos");
      url.searchParams.set("query", query);
      url.searchParams.set("per_page", String(q.limit));
      url.searchParams.set("content_filter", "high");
      url.searchParams.set("orientation", "squarish");
      const res = await io.fetch(url.toString(), {
        headers: { Authorization: `Client-ID ${key}`, "Accept-Version": "v1" },
        signal: AbortSignal.timeout(io.timeoutMs),
      });
      if (!res.ok) return [];
      const json = (await res.json()) as UnsplashResponse;
      return (json.results ?? []).map((r) => ({
        url: r.urls.regular,
        thumb: r.urls.small,
        source: "unsplash",
        lane: "english" as const,
        credit: { name: r.user.name, link: r.user.links.html },
        text: [r.alt_description, r.description, ...(r.tags ?? []).map((t) => t?.title)]
          .filter(Boolean)
          .join(" "),
      }));
    } catch (e) {
      console.warn("unsplash search failed", e);
      return [];
    }
  },
};

const commonsEnglish: ImageSearchProvider = {
  id: "commons-en",
  lane: "english",
  async search(q, io) {
    const query = q.terms[0];
    if (!query) return [];
    try {
      // コモンズは名乗らない相手を弾くことがある。
      const res = await io.fetch(commonsSearchUrl(query, q.limit), {
        headers: { "User-Agent": IMAGE_FETCH_USER_AGENT },
        signal: AbortSignal.timeout(io.timeoutMs),
      });
      if (!res.ok) return [];
      return commonsHits((await res.json()) as CommonsResponse, q.limit, "english");
    } catch (e) {
      console.warn("commons search failed", e);
      return [];
    }
  },
};

/** 知っている出所の全部（並びは同じ点の時の順 — 先の物ほど前）。 */
export const ALL_PROVIDERS: ReadonlyArray<ImageSearchProvider> = [
  wikipediaLead,
  commonsLearning,
  openverse,
  unsplash,
  commonsEnglish,
];

/** 使う出所（`IMAGE_SEARCH_PROVIDERS` で絞る。無い・空なら全部）。 */
export function enabledProviders(
  env: Record<string, string | undefined>,
  all: ReadonlyArray<ImageSearchProvider> = ALL_PROVIDERS,
): ImageSearchProvider[] {
  const raw = (env.IMAGE_SEARCH_PROVIDERS ?? "").trim();
  if (!raw) return [...all];
  const want = new Set(
    raw
      .split(",")
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean),
  );
  return all.filter((p) => want.has(p.id));
}

/** 1つの道（学習言語・英語）の出所を同時に引いて、出所の順につなぐ。 */
export async function searchLane(
  providers: ReadonlyArray<ImageSearchProvider>,
  q: Parameters<ImageSearchProvider["search"]>[0],
  io: ProviderIO,
): Promise<LaneHit[]> {
  const lists = await Promise.all(providers.map((p) => p.search(q, io).catch(() => [])));
  return lists.flat();
}
