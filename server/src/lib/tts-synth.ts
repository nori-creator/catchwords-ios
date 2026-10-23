/**
 * **Azure と Gemini に音を頼む所**（鍵は呼ぶ側が渡す。ここは環境変数も DB も読まない）。
 *
 * 2か所から使う:
 *  - アプリのサーバ（`tts-provider.server.ts`）— Lovable の Secrets の鍵
 *  - 確認用ページの聞き比べ（`netlify/functions/tts-compare.mts`）— Netlify の環境変数の鍵
 * 同じ頼み方を1か所に置き、確認用ページで聞いた声と本番の声が食い違わないようにする。
 * 重い道具（AI の SDK・画面の辞書）を読み込まないので、Netlify の関数にもそのまま入る。
 */
import {
  azureSsml,
  geminiAudioFrom,
  geminiBody,
  providerInfo,
  type GeminiDiagnosis,
  type GeminiVoiceInfo,
} from "./tts-providers";

export type SynthesizedAudio = { bytes: Uint8Array; mime: string };

/**
 * Gemini（Google）の鍵として見る名前。アプリの AI の鍵（`ai-provider.server.ts` の
 * `KEY_ALIASES.google`）と同じ並び。
 */
export const GEMINI_KEY_ENVS = [
  "GEMINI_API_KEY",
  "GOOGLE_API_KEY",
  "GOOGLE_GENERATIVE_AI_API_KEY",
  "GOOGLE_AI_STUDIO_API_KEY",
  "GEMINI_KEY",
] as const;

/** 環境変数から Gemini の鍵を探す（名前と値。値は画面にもログにも出さない）。 */
export function geminiKeyFrom(
  env: Record<string, string | undefined>,
): { env: string; value: string } | null {
  for (const name of GEMINI_KEY_ENVS) {
    const v = env[name];
    if (v && v.trim()) return { env: name, value: v.trim() };
  }
  return null;
}

export const TTS_TIMEOUT_MS = 6000;
/** Gemini は文を読み終えてから返すので、Azure などより余裕を持たせる。 */
export const GEMINI_TIMEOUT_MS = 12_000;

export async function ttsPost(
  url: string,
  init: RequestInit,
  timeoutMs = TTS_TIMEOUT_MS,
): Promise<Response> {
  const res = await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`TTS ${res.status} ${body.slice(0, 160)}`);
  }
  return res;
}

/** Azure AI Speech（MP3）。`https://<region>.tts.speech.microsoft.com/cognitiveservices/v1` */
export async function azureSpeech(opts: {
  key: string;
  region: string;
  voice: string;
  text: string;
  speed: number;
}): Promise<SynthesizedAudio> {
  const res = await ttsPost(
    `https://${encodeURIComponent(opts.region)}.tts.speech.microsoft.com/cognitiveservices/v1`,
    {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": opts.key,
        "Content-Type": "application/ssml+xml",
        "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
        "User-Agent": "catchwords",
      },
      body: azureSsml(opts.text, opts.voice, opts.speed),
    },
  );
  return { bytes: new Uint8Array(await res.arrayBuffer()), mime: "audio/mpeg" };
}

/** Gemini TTS（3.8 は WAV）。鍵は URL ではなく見出しに置く（URL はログに残りやすい）。 */
export async function geminiSpeech(opts: {
  key: string;
  model?: string;
  voice: string;
  text: string;
}): Promise<SynthesizedAudio> {
  const model = opts.model || providerInfo("gemini")?.models[0] || "gemini-3.8-flash-lite-tts";
  const res = await ttsPost(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": opts.key, "Content-Type": "application/json" },
      body: JSON.stringify(geminiBody(opts.text, opts.voice)),
    },
    GEMINI_TIMEOUT_MS,
  );
  return geminiAudioFrom(await res.json());
}

// ---- 診断（開発者だけ。鍵の値は返さない・課金しない） -----------------------------

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";

/** 返事の1件から、画面に出す最小の項目だけ取る（形が違っても落ちない）。 */
export function readGeminiVoice(raw: unknown): GeminiVoiceInfo | null {
  const v = raw as Record<string, unknown> | null;
  if (!v || typeof v !== "object") return null;
  const str = (k: string[]) => {
    for (const key of k) if (typeof v[key] === "string" && v[key]) return v[key] as string;
    return "";
  };
  const id = str(["name", "voiceName", "voice_name", "id"]);
  if (!id) return null;
  const langs = (v.languageCodes ?? v.language_codes ?? v.languages) as unknown;
  return {
    id: id.replace(/^voices\//, ""),
    name: str(["displayName", "display_name", "title"]) || id.replace(/^voices\//, ""),
    gender: str(["gender", "genderPresentation"]),
    accent: str(["accent"]),
    languages: Array.isArray(langs) ? langs.filter((x): x is string => typeof x === "string") : [],
  };
}

/**
 * Gemini の TTS が使えるかを、**課金の無い問い合わせだけ**で確かめる:
 * ① 鍵が在るか（名前だけ）、② 3.8 の2つのモデルが見えるか、③ 拡張の声のライブラリに
 * 台湾（zh-TW）の声が男女それぞれ在るか。実際に鳴らすのは「試しに鳴らす」（少額の課金）。
 */
export async function diagnoseGeminiWith(
  key: { env: string; value: string } | null,
): Promise<GeminiDiagnosis> {
  const out: GeminiDiagnosis = {
    keyPresent: key !== null,
    keyEnv: key?.env ?? null,
    models: [],
    voices: { female: [], male: [] },
    voicesError: null,
  };
  if (!key) return out;
  const headers = { "x-goog-api-key": key.value };
  const get = (path: string) =>
    fetch(`${GEMINI_BASE}${path}`, { headers, signal: AbortSignal.timeout(10_000) });
  const models = providerInfo("gemini")?.models ?? [];
  out.models = await Promise.all(
    models.map(async (id) => {
      try {
        const r = await get(`/models/${encodeURIComponent(id)}`);
        return { id, ok: r.ok, status: r.status };
      } catch {
        return { id, ok: false, status: 0 };
      }
    }),
  );
  for (const gender of ["female", "male"] as const) {
    try {
      const r = await get(`/voices?language_code=zh-TW&gender=${gender}&page_size=50`);
      if (!r.ok) {
        const body = await r.text().catch(() => "");
        out.voicesError = `HTTP ${r.status} ${body.slice(0, 140).replace(/\s+/g, " ")}`;
        continue;
      }
      const json = (await r.json()) as { voices?: unknown[] };
      out.voices[gender] = (json.voices ?? [])
        .map(readGeminiVoice)
        .filter((x): x is GeminiVoiceInfo => x !== null)
        .slice(0, 50);
    } catch (e) {
      out.voicesError = e instanceof Error ? e.message.slice(0, 140) : "voices request failed";
    }
  }
  return out;
}

// ---- 確認用ページの聞き比べ（`netlify/functions/tts-compare.mts`） --------------------

/**
 * 聞き比べで読む文。**決まった文だけ**（好きな文を読ませると、確認用ページの住所を
 * 知った人に鍵を読み上げ機として使われる）。設定の「試しに鳴らす」の文（先頭）も含む。
 */
export const TTS_COMPARE_SAMPLES = [
  "你好，很高興認識你。",
  "我要一杯珍珠奶茶，半糖少冰。",
  "請問捷運站怎麼走？",
  "腳踏車",
] as const;
