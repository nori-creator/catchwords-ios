import { createServerFn } from "@tanstack/react-start";
import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";
import {
  DEFAULT_LOVABLE_IMAGE_MODEL,
  higgsfieldImageInput,
  imagePrompt,
  pickOpenRouterImage,
  readImageConfig,
  resolveImageConfig,
  type ImageConfig,
} from "./image-provider";
import { MAX_PROXY_IMAGE_BYTES, readCappedBytes } from "./byte-cap";
import { isAiCapError } from "./ai-cap";
import { AI_CONSENT_CHECK_FAILED, isAiConsentError } from "./ai-consent";
import { cleanImageQuery, heroSearchQuery, imageQueryOf } from "./hero-image";
import {
  hasNonSubjectSignals,
  hasOffSenseSignals,
  hasPosterSignals,
  isConfidentMatch,
  selectImageCandidates,
  type RankContext,
} from "./image-search-rank";
import {
  SEARCH_BUDGET_MS,
  SOURCE_TIMEOUT_MS,
  VERIFY_MAX_IMAGES,
  VERIFY_MIN_MS,
  VERIFY_TIMEOUT_MS,
  applyVerdict,
  cleanAvoidTerms,
  isStrictSense,
  needsSenseResolution,
  needsVerification,
  type ImageSense,
} from "./image-sense";
import {
  dedupeImages,
  isWeakHeadword,
  learningForms,
  learningMatch,
  mergeLanes,
  wantsLearningLane,
  type ImageSearchProvider,
  type LaneHit,
  type ProviderIO,
  type RankedImage,
} from "./image-sources";
import { enabledProviders, searchLane } from "./image-providers";
import type { ImageSenseDeps } from "./image-sense.server";
import { ALLOWED_IMAGE_MIME, IMAGE_FETCH_USER_AGENT, fetchAllowedImage } from "./image-proxy";

export type ImageCandidate = {
  url: string;
  thumb: string;
  /** 出所（`unsplash` `commons` `openverse` `ai`。画面は字のまま持つ）。 */
  source: "unsplash" | "commons" | "openverse" | "ai" | (string & {});
  credit?: { name: string; link: string };
};

const SearchInput = z.object({
  query: z.string().min(1).max(120),
  language: z.string().default(DEFAULT_TARGET_LANGUAGE),
  purpose: z.enum(["text-catch", "candidates"]).default("candidates"),
  /**
   * その語の棚（`category_key`。例 `vegetable`）。候補を並べ直す手がかり
   * （`image-search-rank.ts`）。古い呼び出し（iOS）は送らないので任意。
   */
  category: z.string().max(40).nullish(),
  /**
   * **その語そのもの**（見出し語）と、学ぶ人の意味（オーナー報告 2026-10-08 ②「レンコンを
   * 調べたのに蓮の花」）。`query` が英語でない（意味の欄の日本語）時、サーバがこの2つから
   * 英語の検索語と避ける語を決めてから探す（`image-sense.ts`）。絵を確かめる時にも使う。
   * 古い呼び出し（iOS）は送らないので任意。
   */
  headword: z.string().max(80).nullish(),
  meaning: z.string().max(200).nullish(),
  /** 写っていたら外れの英語（`extras.image_avoid`。例 `flower` `pond`）。 */
  avoid: z.array(z.string().max(40)).max(12).nullish(),
});

/**
 * 写真の出所に多めに頼む数。並べ直して上から {@link MAX_CANDIDATES} 枚を返す
 * （外れの写真を後ろへ回す余地を持つ）。
 */
const FETCH_PER_SOURCE = 12;
const MAX_CANDIDATES = 6;

/** 並べ直しの間だけ持つ説明の字（題・説明・タグ）。返す前に落とす。 */
type TextCandidate = ImageCandidate & { text?: string };

/**
 * 絵を1枚作る前に、その人の枠を確保する（`image_gen`。`ai-cap.ts`）。
 *
 * **監査 2026-10-03 H3**: 前は絵の生成（1枚ごとに料金がかかる）に上限が無く、
 * `purpose: "text-catch"` を送れば（iOS の `/api/native-fn` からも）何枚でも作らせられた。
 * 今はその人の 24 時間の上限（登録した人 20 枚・匿名の人 2 枚）と、全体の 1 日の枠に数える。
 */
function imageGenReserver(userId: string): () => Promise<void> {
  return async () => {
    // 検索語を外部の絵の AI へ送る前に、同意を確かめる（無ければ作らずに写真だけで続ける）。
    const { assertAiConsent } = await import("./ai-consent.server");
    await assertAiConsent(userId);
    const { assertWithinDailyCap } = await import("./ai-provider.server");
    await assertWithinDailyCap(userId, "image_gen");
  };
}

function isConsentRefusal(e: unknown): boolean {
  return isAiConsentError(e) || (e instanceof Error && e.message.includes(AI_CONSENT_CHECK_FAILED));
}

/**
 * 写真の候補に添える1枚（おまけ）。枠に届いた・数えられない時は**作らずに**写真の候補
 * だけで続ける（画面の節は止めない）。
 */
async function optionalAiImage(
  query: string,
  reserve: () => Promise<void>,
): Promise<ImageCandidate | null> {
  try {
    return await generateOneAiImage(query, reserve);
  } catch (e) {
    if (isAiCapError(e) || isConsentRefusal(e)) {
      console.warn(
        "image generation skipped (cap/consent)",
        e instanceof Error ? e.message.slice(0, 40) : "",
      );
      return null;
    }
    throw e;
  }
}

/**
 * Search Unsplash for image candidates representing the given word.
 * Falls back to AI generation when Unsplash is unavailable or yields no result.
 */
export const searchImageCandidates = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => SearchInput.parse(input))
  .handler(async ({ data, context }) => {
    // 意味を決める・絵を確かめる AI（同意と枠で守る。`image-sense.server.ts`）。
    const { imageSenseDepsFor } = await import("./image-sense.server");
    return searchImagesWith(
      data,
      imageGenReserver(context.userId),
      imageSenseDepsFor(context.userId),
    );
  });

/**
 * AI に見せる小さな絵。Unsplash は幅を指定して縮め、コモンズは決まった幅（250px）にする。
 * 形が違えばそのまま。
 */
export function verifyThumb(url: string): string {
  try {
    const u = new URL(url);
    if (u.hostname.endsWith("unsplash.com")) {
      u.searchParams.set("w", "256");
      return u.toString();
    }
  } catch {
    return url;
  }
  return url.replace(/\/\d+px-/, "/250px-");
}

/** 学習言語の見出し語そのものの写真がこれだけ在れば、学習言語で引き直さない。 */
const ENOUGH_EXACT = 3;

/**
 * **英語の出所**（補い）。厳しい棚では全部を同時に引く（英語の題は信じないので、どの出所の写真も
 * 絵を見て確かめる）。それ以外は今までどおり、Unsplash に説明で確かな写真が無い時だけコモンズも引く。
 */
async function searchEnglish(
  ctx: RankContext,
  providers: ReadonlyArray<ImageSearchProvider>,
  strict: boolean,
  io: () => ProviderIO,
): Promise<TextCandidate[]> {
  const english = providers.filter((p) => p.lane === "english");
  const q = { terms: [ctx.query], language: "en", limit: FETCH_PER_SOURCE };
  if (strict) return searchLane(english, q, io());
  const fallback = english.filter((p) => p.id === "commons-en");
  const first = await searchLane(
    english.filter((p) => p.id !== "commons-en"),
    q,
    io(),
  );
  if (first.some((c) => isConfidentMatch(c.text, ctx)) || fallback.length === 0) return first;
  return [...first, ...(await searchLane(fallback, q, io()))];
}

/**
 * 候補を集める本体（試験から `reserve` を差し替えて呼べるように分けてある）。
 * `reserve` は絵を作る直前に呼ぶ枠の確保（`imageGenReserver`）。
 */
export async function searchImagesWith(
  data: z.infer<typeof SearchInput>,
  reserve: () => Promise<void>,
  /** 意味を決める・絵を確かめる AI（無ければ説明の並べ替えだけ）。 */
  senseDeps?: ImageSenseDeps | null,
): Promise<{ candidates: ImageCandidate[] }> {
  // Typed catches use an original generated illustration, never stock photos.
  // 枠に届いた時は理由（上限の印）をそのまま返す（iOS は 429 になる）。
  if (data.purpose === "text-catch") {
    const ai = await generateOneAiImage(data.query, reserve);
    return { candidates: ai ? [ai] : [] };
  }

  /**
   * **探す前に意味を決める**（オーナー報告 2026-10-08 ②「レンコンを調べたのに蓮の花」）。
   * 英語の検索語（`extras.image_query`）がまだ無い時（カードの AI が答える前の文字検索・
   * 古いカード）は、意味の欄の日本語で探すと別の物（蓮の花）に当たる。見出し語と意味から
   * 英語の検索語と避ける語を決める。決められなければ今までどおり（日本語で探す）。
   */
  const started = Date.now();
  const deadline = started + SEARCH_BUDGET_MS;
  const remaining = () => deadline - Date.now();
  const word = data.headword?.trim()
    ? { headword: data.headword.trim(), meaning: data.meaning ?? null, language: data.language }
    : null;
  /**
   * 1字の見出し語（`桃`）は題・タグで「その語そのもの」と言えない（オーナー報告 2026-10-09
   * 「桃の写真になぜか鳩の画像が出る」— `桃園市信鴿協會` の貼り紙・`桃` という名前の人）。
   * どの写真も絵を見て確かめ、確かめられない写真は出さない（`isWeakHeadword`）。
   */
  const weak = !!word && isWeakHeadword(word.headword);
  /** 食べ物・料理（と棚の分からない語）は英語の題を信じない（オーナー報告 2026-10-09）。 */
  const strict = !!word && (isStrictSense(data.category) || weak);
  let sense: ImageSense = { query: data.query, avoid: cleanAvoidTerms(data.avoid ?? []) };
  const englishKnown = !needsSenseResolution(data.query);
  const learning = word && wantsLearningLane(word) ? word : null;

  /**
   * **探す前に意味を決める**（オーナー報告 2026-10-08 ②「レンコンを調べたのに蓮の花」）。
   * 英語の検索語（`extras.image_query`）がまだ無い時は、見出し語と意味から英語の検索語と
   * 避ける語を決める。厳しい棚の学習言語の語では、英語の検索語が在っても学習言語の絞る語
   * （`黑白切`）と写っているべき物の説明を聞く（覚えと共有の語の行に在れば AI は呼ばない）。
   * 学習言語の出所は見出し語だけで引けるので、**決めるのを待たずに同時に始める**。
   */
  const wantResolve = !!word && !!senseDeps && (!englishKnown || (strict && !!learning));
  const resolveP: Promise<ImageSense | null> =
    wantResolve && word && senseDeps
      ? senseDeps.resolveSense(word).catch(() => null)
      : Promise.resolve(null);
  const applyResolved = (resolved: ImageSense | null) => {
    if (!resolved) return;
    if (!englishKnown && resolved.query) {
      sense = { ...resolved, avoid: cleanAvoidTerms([...resolved.avoid, ...sense.avoid]) };
    } else {
      // 英語の検索語は呼んだ側の物のまま。説明・絞る語・別の書き方・避ける語だけ足す。
      sense = {
        ...sense,
        avoid: cleanAvoidTerms([...sense.avoid, ...resolved.avoid]),
        ...(resolved.sense ? { sense: resolved.sense } : {}),
        ...(resolved.context ? { context: resolved.context } : {}),
        ...(resolved.variants?.length ? { variants: resolved.variants } : {}),
      };
    }
  };

  const providers = enabledProviders(process.env);
  const learningProviders = providers.filter((p) => p.lane === "learning");
  const io = (ms: number): ProviderIO => ({
    fetch: (u, init) => fetch(u, init),
    timeoutMs: Math.max(300, Math.min(SOURCE_TIMEOUT_MS, ms)),
    env: process.env,
  });

  /**
   * **学習言語で先に探す**（オーナー報告 2026-10-09「必ず学習言語で検索して」）。
   * Wikipedia の記事の先頭の絵・Commons・Openverse を見出し語そのもので引く。
   */
  const learningA: Promise<LaneHit[]> = learning
    ? searchLane(
        // 1字の語は記事の先頭の絵だけ先に引く（Commons・Openverse を `桃` で引くと `桃園` ばかり）。
        weak ? learningProviders.filter((p) => p.id === "wikipedia") : learningProviders,
        { terms: [learning.headword], language: learning.language, limit: FETCH_PER_SOURCE },
        io(remaining()),
      )
    : Promise.resolve([]);

  // **英語の出所は補い**（並べる時は必ず後ろ）。英語の検索語が決まってから引く。
  const englishP: Promise<TextCandidate[]> = (async () => {
    if (!englishKnown) applyResolved(await resolveP);
    return searchEnglish(
      { query: sense.query, category: data.category, avoid: sense.avoid },
      providers,
      strict,
      () => io(remaining()),
    );
  })();

  const [hitsA, resolvedLate] = await Promise.all([learningA, resolveP]);
  if (englishKnown) applyResolved(resolvedLate);
  const forms = learning ? learningForms(learning.headword, sense.variants) : [];
  const isExact = (h: LaneHit) => h.lead || learningMatch(h.text, forms, sense.context) === "exact";

  /**
   * 見出し語そのものの写真が足りず、意味を決める AI が別の書き方（簡体字）や絞る語（`黑白切`）を
   * くれた時だけ、学習言語でもう1回引く（時間が残っている時だけ）。
   */
  let learningHits = hitsA;
  const exactCount = hitsA.filter(isExact).length;
  /** 1字の語は、意味を決める AI がくれた2字以上の言い方（`桃子` `水蜜桃`）で引く。 */
  const longForms = weak ? forms.filter((f) => !isWeakHeadword(f)) : [];
  if (
    learning &&
    (weak || (exactCount < ENOUGH_EXACT && (sense.variants?.length || sense.context))) &&
    remaining() > SOURCE_TIMEOUT_MS + VERIFY_MIN_MS
  ) {
    const more = await searchLane(
      weak ? learningProviders.filter((p) => p.id !== "wikipedia") : learningProviders,
      {
        terms: weak
          ? longForms.length
            ? longForms
            : [learning.headword]
          : sense.variants?.length
            ? forms
            : [learning.headword],
        context: weak || sense.variants?.length ? null : sense.context,
        language: learning.language,
        limit: FETCH_PER_SOURCE,
      },
      io(remaining() - VERIFY_MIN_MS),
    );
    learningHits = [...hitsA, ...more];
  }

  const rankContext: RankContext = {
    query: sense.query,
    category: data.category,
    avoid: sense.avoid,
  };
  const english = await englishP;
  // 探した物に合う写真を前へ、**外れと分かる物（花・避ける語）は捨てる**（`image-search-rank.ts`）。
  // 同じ点なら Unsplash が先（写真がきれい）。
  const englishRanked = selectImageCandidates(english, rankContext);
  let ranked: RankedImage[] = learning
    ? mergeLanes({
        learning: learningHits,
        english: englishRanked,
        forms,
        context: sense.context,
        // 違う物・貼り紙・人の写真の手がかりが在る学習言語の写真は捨てる。
        dropLearning: (c) =>
          hasOffSenseSignals(c.text, rankContext) || hasNonSubjectSignals(c.text, rankContext),
      })
    : dedupeImages(englishRanked);
  if (weak) {
    /**
     * 1字の語: 題・タグの一致は「確か」と見なさない（全部、絵を見て確かめる）。説明で確かな写真
     * （記事の先頭の絵・`水蜜桃` の題・`peach` の説明）を先に、学習言語の近い物を後ろへ —
     * 確かめる上位（`VERIFY_MAX_IMAGES` 枚）に、当たりそうな写真が入るように。
     */
    const likely = (c: RankedImage) => !!c.exact || isConfidentMatch(c.text, rankContext);
    // 人の写真の手がかりは学習言語の題・タグだけで見る（英語の `a woman running` は 跑 の正しい写真）。
    const fromEnglish = new Set(englishRanked.map((c) => c.url));
    ranked = [...ranked.filter(likely), ...ranked.filter((c) => !likely(c))]
      .filter((c) =>
        fromEnglish.has(c.url)
          ? !hasPosterSignals(c.text, rankContext)
          : !hasNonSubjectSignals(c.text, rankContext),
      )
      .map(({ exact: _exact, ...c }) => c);
  }

  /**
   * **絵を見て確かめる**（`image-sense.ts`）。上位が全部学習言語の見出し語そのものなら呼ばない。
   * 厳しい棚では英語の題が合っていても確かめ、**確かめられなかった英語の写真は出さない**
   * （外れの写真より、語の札・Pro の「AI で絵を作る」のほうがいい）。
   */
  if (word && needsVerification(ranked, rankContext, strict)) {
    const left = remaining();
    const top = ranked.slice(0, VERIFY_MAX_IMAGES);
    const result =
      senseDeps && left >= VERIFY_MIN_MS
        ? await senseDeps
            .verify({
              word,
              sense,
              images: top.map((c) => ({ url: c.url, thumb: verifyThumb(c.thumb || c.url) })),
              timeoutMs: Math.min(VERIFY_TIMEOUT_MS, left - 200),
            })
            .catch(() => null)
        : null;
    if (result) {
      ranked = applyVerdict(ranked, result.checked, result.matched, {
        duplicates: result.duplicates,
        ...(strict ? { keepUnchecked: (c: RankedImage) => !!c.exact } : {}),
      });
    } else if (strict) {
      // 確かめられない（同意・枠・時間切れ）: 見出し語そのものと、説明で確かな物だけ。
      ranked = ranked.filter((c) => c.exact || isConfidentMatch(c.text, rankContext));
    }
  }
  const candidates: TextCandidate[] = [];
  // **AI を先に**（`IMAGE_SEARCH_MODE=ai-first`）。1枚作って先頭に置き、
  // 後ろに写真の候補も並べる（AI が失敗しても写真で選べる）。
  if (readImageConfig(process.env).mode === "ai-first") {
    const ai = await optionalAiImage(sense.query, reserve);
    if (ai) candidates.push(ai);
  }
  candidates.push(...ranked.map(({ exact: _exact, ...c }) => c));
  const query = sense.query;

  // Always offer at least one AI fallback option so user has a choice when
  // photo search returns nothing or is unconfigured.
  // **写真は在ったが全部外れだった時は作らない**（オーナー報告 2026-10-09）。画面は語の札にし、
  // Pro の人は「AI で絵を作る」を押して作る（勝手に作らない）。
  if (candidates.length === 0 && learningHits.length + english.length === 0) {
    const ai = await optionalAiImage(query, reserve);
    if (ai) candidates.push(ai);
  }

  // 説明の字は並べ直しのためだけの物。画面へは送らない。
  return {
    candidates: candidates.slice(0, MAX_CANDIDATES).map(({ text: _text, ...c }) => c),
  };
}

/**
 * AI で1枚作る。**どこで作るかは設定で切り替える**（`image-provider.ts`）。
 * どこで失敗しても `null` — 画面は写真の候補だけで続ける。
 *
 * `reserve` は**料金のかかる窓口を呼ぶ直前に**1回だけ呼ぶ（枠の確保）。投げたら作らない
 * （その失敗はそのまま投げる）。生成を切ってある（`off`）時は確保しない。
 */
/** 開発者が選んだ画像の会社（`app_config.image_generation`）。読めなければ null（環境変数の既定）。 */
async function readImageOverride(): Promise<{ provider?: string; model?: string } | null> {
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await supabaseAdmin
      .from("app_config")
      .select("value")
      .eq("key", "image_generation")
      .maybeSingle();
    return (data as { value?: { provider?: string; model?: string } } | null)?.value ?? null;
  } catch (error) {
    console.warn("image config unavailable; using environment default", error);
    return null;
  }
}

async function generateOneAiImage(
  query: string,
  reserve: () => Promise<void>,
  given?: ImageConfig,
): Promise<ImageCandidate | null> {
  const config = given ?? resolveImageConfig(process.env, await readImageOverride());
  if (config.provider === "off") return null;
  await reserve();
  if (config.provider === "openrouter") return generateWithOpenRouter(query, config.model);
  if (config.provider === "higgsfield") {
    const r = await generateWithHiggsfield(query, config.model);
    if (r.ok) return r.candidate;
    console.warn("higgsfield image failed", r.reason);
    // Higgsfield が駄目でも、Lovable の口で1枚は作る（画面を空にしない）。
    return generateWithLovable(query, DEFAULT_LOVABLE_IMAGE_MODEL);
  }
  if (config.provider === "google") return generateWithGoogle(query, config.model);
  if (config.provider === "openai") return generateWithOpenAI(query, config.model);
  return generateWithLovable(query, config.model);
}

async function generateWithGoogle(query: string, model: string): Promise<ImageCandidate | null> {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return null;
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: "POST",
        headers: { "x-goog-api-key": key, "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: imagePrompt(query) }] }],
          generationConfig: { responseModalities: ["IMAGE"] },
        }),
        signal: AbortSignal.timeout(40_000),
      },
    );
    if (!res.ok) {
      console.warn("google image failed", res.status);
      return null;
    }
    const json = (await res.json()) as {
      candidates?: Array<{
        content?: { parts?: Array<{ inlineData?: { mimeType?: string; data?: string } }> };
      }>;
    };
    const part = json.candidates?.[0]?.content?.parts?.find((p) => p.inlineData?.data)?.inlineData;
    if (!part?.data) return null;
    const url = `data:${part.mimeType || "image/png"};base64,${part.data}`;
    return { url, thumb: url, source: "ai" };
  } catch (error) {
    console.warn("google image failed", error);
    return null;
  }
}

async function generateWithOpenAI(query: string, model: string): Promise<ImageCandidate | null> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) return null;
  try {
    const res = await fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        prompt: imagePrompt(query),
        size: "1024x1024",
        quality: "low",
      }),
      signal: AbortSignal.timeout(40_000),
    });
    if (!res.ok) {
      console.warn("openai image failed", res.status);
      return null;
    }
    const json = (await res.json()) as { data?: Array<{ b64_json?: string; url?: string }> };
    const first = json.data?.[0];
    const url = first?.b64_json ? `data:image/png;base64,${first.b64_json}` : first?.url;
    return url ? { url, thumb: url, source: "ai" } : null;
  } catch (error) {
    console.warn("openai image failed", error);
    return null;
  }
}

/**
 * **Higgsfield で1枚作る**。返ってくるのは Higgsfield の置き場の URL なので、
 * **サーバで取りに行って data URL にして返す**（Lovable の口と同じ形）。
 * こうすると保存の時にネットの画像の許可リスト（SSRF 除け）を広げなくて済む。
 */
async function generateWithHiggsfield(
  query: string,
  model: string,
): Promise<
  { ok: true; candidate: ImageCandidate; ms: number } | { ok: false; reason: string; ms: number }
> {
  const { runHiggsfield } = await import("./higgsfield.server");
  const r = await runHiggsfield(model, higgsfieldImageInput(model, imagePrompt(query)), {
    timeoutMs: 45_000,
  });
  if (!r.ok) return { ok: false, reason: r.reason, ms: r.ms };
  try {
    const img = await fetch(r.url, { signal: AbortSignal.timeout(20_000) });
    const ct = (img.headers.get("content-type") ?? "image/png").split(";")[0].trim();
    if (!img.ok || !ALLOWED_IMAGE_MIME.test(ct))
      return { ok: false, reason: "絵を受け取れませんでした", ms: r.ms };
    const b64 = Buffer.from(await readCappedBytes(img, MAX_PROXY_IMAGE_BYTES)).toString("base64");
    const url = `data:${ct};base64,${b64}`;
    return { ok: true, candidate: { url, thumb: url, source: "ai" }, ms: r.ms };
  } catch {
    return { ok: false, reason: "絵を受け取れませんでした", ms: r.ms };
  }
}

/**
 * **画像生成を実際に1回試す（開発者だけ）**（オーナー指示 2026-09-28「HIGGSFIELD の
 * api を lovable で設定したから実際に検査して」）。
 *
 * 設定の開発者欄（Web・iOS）の「試しに1枚作る」から呼ぶ。**本当に1枚作る**（残高を使う）。
 * 使う会社・モデルは、`provider`（と `model`）を送ればその**まだ保存していない選び方**
 * （保存と同じ確かめ。鍵の無い会社は 400）、送らなければ**本番と同じ**
 * （開発者の設定 `app_config.image_generation` → 環境変数）。どちらも保存はしない。
 * 返すのは: どこで作ったか・鍵を見つけた名前（値は返さない）・結果・かかった時間。
 * 形は `docs/admin-ai-api.md`。
 */
export const adminTestImage = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    (input: unknown) => (input ?? {}) as { query?: string; provider?: string; model?: string },
  )
  .handler(async ({ context, data: input }) => {
    const mod = await import("./admin-ai.server");
    await mod.loadAdminAiServerModules();
    // 管理者か・形・鍵の有無を確かめる（管理者でなければ Forbidden → 403）。
    const data = await mod.resolveAdminImageTest(mod.realAdminAiDeps(context), input);
    const config = resolveImageConfig(process.env, data.draft ?? (await readImageOverride()));
    const { higgsfieldCredentialSource } = await import("./higgsfield.server");
    const credentialName = config.provider === "higgsfield" ? higgsfieldCredentialSource() : null;
    const started = Date.now();
    if (config.provider === "higgsfield") {
      const r = await generateWithHiggsfield(data.query, config.model);
      return {
        provider: config.provider,
        model: config.model,
        credentialName,
        ok: r.ok,
        image: r.ok ? r.candidate.url : null,
        error: r.ok ? null : r.reason,
        ms: Date.now() - started,
      };
    }
    // 開発者の確かめ（管理者だけ）は利用者の枠に数えない。
    const one = await generateOneAiImage(data.query, async () => {}, config);
    return {
      provider: config.provider,
      model: config.model,
      credentialName,
      ok: !!one,
      image: one?.url ?? null,
      error: one
        ? null
        : config.provider === "off"
          ? "画像生成は停止中です"
          : "生成できませんでした",
      ms: Date.now() - started,
    };
  });

async function generateWithOpenRouter(
  query: string,
  model: string,
): Promise<ImageCandidate | null> {
  const { findKey } = await import("./ai-provider.server");
  const key = findKey("openrouter")?.value;
  if (!key) return null;
  const headers = { Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  const prompt = imagePrompt(query);
  try {
    // Seedream のような絵だけの型は**専用の口**でしか受けない。
    let res = await fetch("https://openrouter.ai/api/v1/images", {
      method: "POST",
      headers,
      body: JSON.stringify({ model, prompt }),
      signal: AbortSignal.timeout(40_000),
    });
    // 専用の口が無い型（会話で絵も返す型）は、会話の口で頼み直す。
    if (!res.ok && res.status >= 400 && res.status < 500) {
      res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers,
        body: JSON.stringify({
          model,
          modalities: ["image", "text"],
          messages: [{ role: "user", content: prompt }],
        }),
        signal: AbortSignal.timeout(40_000),
      });
    }
    if (!res.ok) {
      console.warn("openrouter image failed", res.status);
      return null;
    }
    const url = pickOpenRouterImage(await res.json());
    return url ? { url, thumb: url, source: "ai" } : null;
  } catch (e) {
    console.warn("openrouter image failed", e);
    return null;
  }
}

async function generateWithLovable(
  prompt: string,
  model = DEFAULT_LOVABLE_IMAGE_MODEL,
): Promise<ImageCandidate | null> {
  const lovableKey = process.env.LOVABLE_API_KEY;
  if (!lovableKey) return null;
  try {
    const res = await fetch("https://ai.gateway.lovable.dev/v1/images/generations", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${lovableKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        prompt: imagePrompt(prompt),
        quality: "low",
        size: "1024x1024",
      }),
      signal: AbortSignal.timeout(40_000),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as { data?: Array<{ b64_json?: string; url?: string }> };
    const first = json.data?.[0];
    if (first?.b64_json) {
      const url = `data:image/png;base64,${first.b64_json}`;
      return { url, thumb: url, source: "ai" };
    }
    if (first?.url) {
      return { url: first.url, thumb: first.url, source: "ai" };
    }
    return null;
  } catch (e) {
    console.warn("AI image fallback failed", e);
    return null;
  }
}

/**
 * **Pro の人が、語の絵を AI で1枚作る**（オーナー指示 2026-10-07「Pro なら AI で
 * 単語の画像を作れるように」）。
 *
 * 写真の無い語の詳細の「別の画像」の列にボタンを出す（`StickerSheet`）。ここでは
 *  1. **サーバで** `profiles.plan = pro` を確かめる（画面の判定は信じない）
 *  2. 外部の AI へ送る**同意**を確かめる（`assertAiConsent`。`AI_CONSENT_FUNCTIONS` に載せてある）
 *  3. その人の枠を確保する（`pro_image`。`ai-cap.ts`。全体の枠にも数える）
 *  4. いつもの絵の道で作る（`generateOneAiImage` — Higgsfield が駄目なら Lovable）
 *  5. **data URL で返す** — 保存は差し替えと同じ道（`useAutoHero` → 仮画像）
 *
 * 判断の本体は `generateProImageWith`（試験から差し替えて呼べるように分けてある）。
 */
export const ProImageInput = z.union([
  z.object({ sticker_id: z.string().uuid() }),
  /**
   * **まだ保存していない札**（文字で調べた語の剥がす札。オーナー指示 2026-10-09「写真が
   * 残らなかった時、Pro の人には AI で絵を作るを出す」）。語は利用者が送る物だが、
   * Pro の確かめ・同意・枠（`pro_image`）は札の時と同じに通る。
   */
  z.object({
    headword: z.string().trim().min(1).max(80),
    meaning: z.string().max(200).nullish(),
    image_query: z.string().max(120).nullish(),
  }),
]);

export const PRO_ONLY_IMAGE_MESSAGE = "AI で絵を作るのは Pro 限定です";

export const generateProWordImage = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ProImageInput.parse(input))
  .handler(async ({ context, data }) => {
    const { supabase, userId } = context;
    return generateProImageWith({
      isPaidPro: async () => {
        // 開発者の「Pro 扱い」ではなく、**払っている人**だけ（`profiles.plan`）。
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data: row, error } = await supabaseAdmin
          .from("profiles")
          .select("plan")
          .eq("id", userId)
          .maybeSingle();
        // 読めない時は Pro と見なさない（課金の判定は開かない側に倒す）。
        if (error) return false;
        return (row as { plan?: string } | null)?.plan === "pro";
      },
      readWord: async () => {
        if (!("sticker_id" in data)) {
          return {
            headword: data.headword,
            meaning: data.meaning ?? null,
            imageQuery: cleanImageQuery(data.image_query) || null,
          };
        }
        // 自分の札だけ（他人の札の語で作らせない）。
        const { data: row } = await supabase
          .from("stickers")
          .select("words!inner(headword, meaning_ja, extras)")
          .eq("id", data.sticker_id)
          .eq("user_id", userId)
          .maybeSingle();
        const w = (
          row as {
            words?: { headword?: string; meaning_ja?: string | null; extras?: unknown };
          } | null
        )?.words;
        return w?.headword
          ? {
              headword: w.headword,
              meaning: w.meaning_ja ?? null,
              imageQuery: imageQueryOf(w.extras) || null,
            }
          : null;
      },
      // 語を外部の絵の AI へ送るので、送る前に同意を確かめる（他の AI の関数と同じ関所）。
      assertConsent: async () =>
        (await import("./ai-consent.server")).assertAiConsent(context.userId),
      reserve: async () => {
        const { assertWithinDailyCap } = await import("./ai-provider.server");
        await assertWithinDailyCap(userId, "pro_image");
      },
      generate: generateOneAiImage,
      toDataUrl: generatedImageAsDataUrl,
    });
  });

export type ProImageDeps = {
  isPaidPro: () => Promise<boolean>;
  readWord: () => Promise<{
    headword: string;
    meaning: string | null;
    /** 画像検索用の英語（`extras.image_query`）。古いカードは無い。 */
    imageQuery?: string | null;
  } | null>;
  /** 外部の AI へ送る同意（無ければ `AI_CONSENT_REQUIRED` で投げる）。 */
  assertConsent: () => Promise<void>;
  reserve: () => Promise<void>;
  generate: (query: string, reserve: () => Promise<void>) => Promise<ImageCandidate | null>;
  toDataUrl: (url: string) => Promise<string>;
};

export async function generateProImageWith(
  deps: ProImageDeps,
): Promise<{ url: string; source: "ai" }> {
  // 確かめる順番が大事: Pro でない人は**枠も数えない・作らない**。
  if (!(await deps.isPaidPro())) throw new Error(PRO_ONLY_IMAGE_MESSAGE);
  const word = await deps.readWord();
  if (!word) throw new Error("単語が見つかりません");
  const query = proImageQuery(word);
  // 送る直前に同意を確かめる（同意が無ければ枠も数えず、何も送らない）。
  await deps.assertConsent();
  const made = await deps.generate(query, deps.reserve);
  if (!made) throw new Error("絵を生成できませんでした。もう一度お試しください");
  const url = made.url.startsWith("data:") ? made.url : await deps.toDataUrl(made.url);
  return { url, source: "ai" };
}

/**
 * 絵の指示に渡す言葉。語そのものと、その意味の最初の1つ（`hero-image.ts` と同じ削り方）。
 * 語だけだと、読めない字の「形」を描かれることがある。画像検索用の英語
 * （`extras.image_query`）が在ればそちらを添える（牛蒡 → 花ではなく食べる根を描かせる）。
 */
export function proImageQuery(word: {
  headword: string;
  meaning: string | null;
  imageQuery?: string | null;
}): string {
  const head = word.headword.trim();
  const sense = heroSearchQuery({
    headword: head,
    meaning: word.meaning,
    imageQuery: word.imageQuery,
  });
  return sense && sense !== head ? `${head} (${sense})` : head;
}

/**
 * 作った絵が URL で返ってきた時（Lovable・OpenRouter）、サーバで取りに行って
 * data URL にする。行き先は絵を作った相手が返した物で、利用者が渡した物ではない。
 * 大きさの上限と画像の種類は確かめる。
 */
async function generatedImageAsDataUrl(url: string): Promise<string> {
  if (!url.startsWith("https://")) throw new Error("絵を受け取れませんでした");
  const res = await fetch(url, { signal: AbortSignal.timeout(20_000) });
  const ct = (res.headers.get("content-type") ?? "").split(";")[0].trim();
  if (!res.ok || !ALLOWED_IMAGE_MIME.test(ct)) throw new Error("絵を受け取れませんでした");
  const b64 = Buffer.from(await readCappedBytes(res, MAX_PROXY_IMAGE_BYTES)).toString("base64");
  return `data:${ct};base64,${b64}`;
}

/**
 * Download a remote image URL on the server (avoids browser CORS) and return
 * a base64 data URL ready for upload to Storage.
 */
const FetchInput = z.object({ url: z.string().url().max(2000) });

// 許可リスト・転送の辿り方・名乗りは `image-proxy.ts`（試験から呼べるように外へ出した）。
export const fetchImageAsDataUrl = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => FetchInput.parse(input))
  .handler(async ({ data }): Promise<{ dataUrl: string }> => fetchAllowedImage(data.url));
