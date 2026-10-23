/**
 * 開発者が選んだ会社で発音を作る（`tts-providers.ts` の表を使う）。
 *
 * - 設定は `app_config.key='tts_voice'`。呼ぶたびに DB へ行かないよう 30 秒ためる
 *   （`ai_models` と同じ）。
 * - **1回だけ・6秒で見切る。** 押した人を待たせないのが先。駄目なら呼び出し側が
 *   これまでの声に落とす（その音はこれまでの置き場所に貯める — 新しい声の
 *   置き場所に古い声を入れない）。
 */
import { findKey } from "./ai-provider.server";
import {
  azureSpeech,
  diagnoseGeminiWith,
  geminiSpeech,
  ttsPost,
  type SynthesizedAudio,
} from "./tts-synth";
import {
  choiceFor,
  elevenLabsBody,
  isVoiceLocked,
  providerInfo,
  voiceTag,
  type GeminiDiagnosis,
  type TtsChoice,
  type TtsVoiceConfig,
} from "./tts-providers";

let cache: { at: number; value: TtsVoiceConfig | null } = { at: 0, value: null };

export async function getTtsVoiceConfig(): Promise<TtsVoiceConfig | null> {
  const now = Date.now();
  if (now - cache.at < 30_000) return cache.value;
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const db = supabaseAdmin as unknown as {
      from: (t: string) => {
        select: (c: string) => {
          eq: (k: string, v: string) => { maybeSingle: () => Promise<{ data: unknown }> };
        };
      };
    };
    const { data } = await db
      .from("app_config")
      .select("value")
      .eq("key", "tts_voice")
      .maybeSingle();
    const value = ((data as { value?: TtsVoiceConfig } | null)?.value ??
      null) as TtsVoiceConfig | null;
    cache = { at: now, value };
    return value;
  } catch {
    cache = { at: now, value: null };
    return null;
  }
}

/** 保存した直後に、30 秒待たずに新しい声へ切り替える。 */
export function forgetTtsVoiceConfig(): void {
  cache = { at: 0, value: null };
}

export async function activeChoice(language: string): Promise<TtsChoice | null> {
  return choiceFor(await getTtsVoiceConfig(), language);
}

/** いまの声の札（置き場所の鍵に混ぜる）。 */
export async function currentVoiceTag(language: string): Promise<string> {
  return voiceTag(await activeChoice(language));
}

/** その言語の声が固定されているか（台湾の声。固定中は別の声・端末の声へ落とさない）。 */
export async function isLockedFor(language: string): Promise<boolean> {
  return isVoiceLocked(await getTtsVoiceConfig(), language);
}

/** 鍵が揃っているか（値は返さない）。Gemini は Google の鍵の別名も見る。 */
export function providerKeysPresent(id: string): boolean {
  const info = providerInfo(id);
  if (!info) return false;
  if (id === "gemini") return findKey("google") !== null;
  return info.keyEnvs.every((k) => Boolean(process.env[k]));
}

const post = ttsPost;

export type { SynthesizedAudio } from "./tts-synth";

/** 一時的な失敗（混雑・圏外・時間切れ）か。 */
function isTransient(e: unknown): boolean {
  const m = e instanceof Error ? `${e.name} ${e.message}` : String(e);
  return /TTS (429|5\d\d)|timeout|aborted|fetch failed|network/i.test(m);
}

/**
 * 選んだ会社で音を作る（MP3。Gemini は WAV）。鍵が無い・失敗したら投げる。
 * **一時的な失敗は同じ声で1回だけやり直す** — 台湾の声は別の声に切り替えないので、
 * 混んでいた時に黙って別の声にならないよう、同じ声をもう一度頼む。
 */
export async function synthesizeAudio(
  choice: TtsChoice,
  text: string,
  speed: number,
  language: string,
): Promise<SynthesizedAudio> {
  try {
    return await synthesizeOnce(choice, text, speed, language);
  } catch (e) {
    if (!isTransient(e)) throw e;
    await new Promise((r) => setTimeout(r, 400));
    return synthesizeOnce(choice, text, speed, language);
  }
}

async function synthesizeOnce(
  choice: TtsChoice,
  text: string,
  speed: number,
  language: string,
): Promise<SynthesizedAudio> {
  const info = providerInfo(choice.provider);
  if (!info) throw new Error(`TTS provider not connected: ${choice.provider}`);
  if (choice.provider === "gemini") {
    // 鍵の名前は別名も見る（`findKey("google")`）。値は表に出さない。
    const key = findKey("google");
    if (!key) throw new Error("TTS key missing: GEMINI_API_KEY");
    return geminiSpeech({
      key: key.value,
      model: choice.model || info.models[0],
      voice: choice.voice,
      text,
    });
  }
  const missing = info.keyEnvs.filter((k) => !process.env[k]);
  if (missing.length) throw new Error(`TTS key missing: ${missing.join(", ")}`);
  return { bytes: await synthesizeMp3Provider(choice, text, speed, language), mime: "audio/mpeg" };
}

async function synthesizeMp3Provider(
  choice: TtsChoice,
  text: string,
  speed: number,
  language: string,
): Promise<Uint8Array> {
  const info = providerInfo(choice.provider)!;

  if (choice.provider === "azure") {
    const made = await azureSpeech({
      key: process.env.AZURE_SPEECH_KEY!,
      region: process.env.AZURE_SPEECH_REGION!,
      voice: choice.voice,
      text,
      speed,
    });
    return made.bytes;
  }

  if (choice.provider === "elevenlabs") {
    const model = choice.model || info.models[0];
    const res = await post(
      `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(choice.voice)}?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: {
          "xi-api-key": process.env.ELEVENLABS_API_KEY!,
          "Content-Type": "application/json",
          Accept: "audio/mpeg",
        },
        body: JSON.stringify(elevenLabsBody(text, model, speed, language)),
      },
    );
    return new Uint8Array(await res.arrayBuffer());
  }

  throw new Error(`TTS provider not connected: ${choice.provider}`);
}

// ---- 診断（開発者だけ。鍵の値は返さない・課金しない） -----------------------------

/** 診断の中身は `tts-synth.ts`（確認用ページの聞き比べと同じ）。鍵は Lovable の Secrets。 */
export async function diagnoseGemini(): Promise<GeminiDiagnosis> {
  return diagnoseGeminiWith(findKey("google"));
}
