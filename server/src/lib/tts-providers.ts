/**
 * **発音の声を出す会社を、開発者が選べるようにする。**（オーナー指示 2026-09-23
 * 「台湾華語の発音が機械音で気に入らないから、Azure、VoAI 絕好聲創、ATEN 優聲學、
 *  ElevenLabs v3など、開発者の私だけ、apiを設定できるようにして」）
 * （2026-10-03 オーナー決定で、ある1社の読み上げは外した。保存済みの設定に
 *  その会社が残っていても、表に無い会社は `choiceFor`/`cleanTtsConfig` が捨てて
 *  既定の声に戻る。）
 *
 * ここは**表と純粋な関数だけ**（試験から触れるように）。実際に外へ頼むのは
 * `tts-provider.server.ts`。
 *
 * ## OpenRouter を通さない
 * 発音は押してから鳴るまでの速さが命。間に1社挟むと往復が1つ増える。
 * さらに（2026-09 時点）OpenRouter の読み上げは GPT-4o mini TTS・Gemini TTS・
 * Voxtral など自社の一覧の物だけで、Azure・ElevenLabs・VoAI・ATEN は
 * 選べない。各社へ直に頼む。
 *
 * ## 鍵は DB に置かない
 * `ai_models` と同じ決まり。DB（`app_config.key='tts_voice'`）には
 * 「どの会社の・どの声・どのモデル」だけを置き、鍵は環境変数の名前で引く。
 *
 * ## 声を変えたら、貯めた音も替わる
 * 音はサーバ（Storage）にも端末（IndexedDB）にも貯めてあり、置き場所の鍵に
 * **声の札**（`voiceTag`）を混ぜる。札が変われば別の置き場所になるので、
 * 古い声が残って鳴り続けることは無い。何も選んでいない時の札は、これまでの
 * `alloy` のまま（今ある音をそのまま使い続けるため）。
 */

import { TTS_VOICE_DEFAULT } from "./tts-cache";
import { DEFAULT_TARGET_LANGUAGE, TARGET_LANGUAGES } from "./target-lang";

export type TtsProviderId = "azure" | "gemini" | "elevenlabs";

export type TtsProviderInfo = {
  id: TtsProviderId;
  label: string;
  /** 鍵の環境変数（全部そろって使える）。 */
  keyEnvs: string[];
  /** 選べるモデル（先頭が既定）。空ならモデルの指定は無い。 */
  models: string[];
  /** 学習言語ごとの声の候補（先頭が既定）。空なら声の ID を手で入れる。 */
  voices: Partial<Record<string, string[]>>;
  note: string;
};

/**
 * 選べる会社（どれも繋いである物だけ）。VoAI 絕好聲創・ATEN 優聲學は公式の API 仕様を
 * 取れず未接続のまま選べない項目として並んでいたので、2026-10-09 に一覧から外した
 * （契約して仕様書を受け取ったら、ここに足して `tts-provider.server.ts` に頼み方を書く）。
 */
export const TTS_PROVIDERS: TtsProviderInfo[] = [
  {
    id: "azure",
    label: "Azure AI Speech",
    keyEnvs: ["AZURE_SPEECH_KEY", "AZURE_SPEECH_REGION"],
    models: [],
    voices: {
      "zh-TW": ["zh-TW-HsiaoChenNeural", "zh-TW-YunJheNeural", "zh-TW-HsiaoYuNeural"],
      en: ["en-US-AvaMultilingualNeural", "en-US-AndrewMultilingualNeural", "en-US-JennyNeural"],
      // 日本語(2026-10-01)。Microsoft の一覧にある ja-JP の声。
      ja: ["ja-JP-NanamiNeural", "ja-JP-KeitaNeural", "ja-JP-AoiNeural"],
    },
    note: "台湾華語（zh-TW）専用の声がある。",
  },
  {
    id: "gemini",
    label: "Gemini TTS（3.8）",
    // 鍵の名前は別名も見る（`tts-provider.server.ts` の `providerKeysPresent`）。
    keyEnvs: ["GEMINI_API_KEY"],
    // 先頭が既定。Flash-Lite は速く安い日常の読み上げ向け、Flash は表現力・方言・長文向け
    // （公式の各モデルのページ）。
    models: ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts"],
    voices: {},
    note: "台湾の声は「診断」で出る zh-TW の声の一覧から選ぶ（声の名前は言語を決めない。台湾なまりは声で決まる）。",
  },
  {
    id: "elevenlabs",
    label: "ElevenLabs",
    keyEnvs: ["ELEVENLABS_API_KEY"],
    // Flash が最速。v3 は表現が豊かだが、会社自身がリアルタイム向けではないと言っている。
    models: ["eleven_flash_v2_5", "eleven_turbo_v2_5", "eleven_multilingual_v2", "eleven_v3"],
    voices: {},
    note: "声の ID は ElevenLabs の Voice Library からコピーして入れる。",
  },
];

export function providerInfo(id: string | undefined | null): TtsProviderInfo | null {
  return TTS_PROVIDERS.find((p) => p.id === id) ?? null;
}

/** 1つの学習言語に使う声。 */
export type TtsChoice = {
  provider: TtsProviderId;
  voice: string;
  model?: string;
};

export type TaiwanGender = "female" | "male";

/**
 * **アプリ全体で使う1つの台湾の声**（オーナー指示 2026-09-29「音声は必ず台湾人で、男性か女性かは
 * 選べるようにし、アプリ全体で1つの同一の音声を使う」）。
 *
 * 決めるのは会社・性別だけ。声そのものは会社ごとに:
 *  - Azure … 台湾の声の決まった表（`TAIWAN_AZURE_VOICES`。zh-TW の声だけ）
 *  - Gemini … 診断で出た zh-TW の声から、性別ごとに開発者が選んだ物（`voices`）
 * これが決まっている間、**学習言語 zh-TW の読み上げはすべてこの声**。ほかの声（前の
 * 「これまでの声」や端末の声）へは切り替えない（`isVoiceLocked`）。
 */
export type TaiwanVoice = {
  provider: "azure" | "gemini";
  gender: TaiwanGender;
  model?: string;
  /** Gemini の声（性別ごと）。Azure は使わない。 */
  voices?: Partial<Record<TaiwanGender, string>>;
};

/** `app_config.key='tts_voice'` の中身。 */
export type TtsVoiceConfig = {
  /** 台湾の声（あれば zh-TW はこれが優先）。 */
  taiwan?: TaiwanVoice;
  languages?: Partial<Record<string, TtsChoice>>;
};

/** Azure の台湾（zh-TW）の声。Microsoft の声の一覧にある zh-TW の声だけ。 */
export const TAIWAN_AZURE_VOICES: Record<TaiwanGender, string[]> = {
  female: ["zh-TW-HsiaoChenNeural", "zh-TW-HsiaoYuNeural"],
  male: ["zh-TW-YunJheNeural"],
};

/** 台湾の声を適用する学習言語。 */
export const TAIWAN_LANGUAGE: string = DEFAULT_TARGET_LANGUAGE;

/** 声を選べる学習言語（学習言語の表をそのまま使う）。 */
export const TTS_LANGUAGES = TARGET_LANGUAGES;

/** 声の ID・モデル名に使ってよい字（置き場所の道にも混ざるので絞る）。 */
const SAFE = /^[A-Za-z0-9_.:()\- ]{1,100}$/;

/**
 * 保存する前の掃除。知らない会社・変な字は捨てる
 * （その言語は「これまでの声」に戻る）。
 */
export function cleanTtsConfig(raw: unknown): TtsVoiceConfig {
  const out: Partial<Record<string, TtsChoice>> = {};
  const taiwan = cleanTaiwan((raw as TtsVoiceConfig | null)?.taiwan);
  const langs = (raw as TtsVoiceConfig | null)?.languages;
  if (!langs || typeof langs !== "object") return taiwan ? { taiwan } : {};
  for (const lang of TTS_LANGUAGES) {
    const c = (langs as Record<string, unknown>)[lang] as Partial<TtsChoice> | undefined;
    if (!c || typeof c !== "object") continue;
    const info = providerInfo(c.provider);
    if (!info) continue;
    const voice = typeof c.voice === "string" ? c.voice.trim() : "";
    if (!SAFE.test(voice)) continue;
    const model = typeof c.model === "string" ? c.model.trim() : "";
    if (model && !SAFE.test(model)) continue;
    out[lang] = { provider: info.id, voice, ...(model ? { model } : {}) };
  }
  return {
    ...(taiwan ? { taiwan } : {}),
    ...(Object.keys(out).length ? { languages: out } : {}),
  };
}

/** 台湾の声の掃除。知らない会社・性別・変な字は捨てる（台湾の声を取り消した扱い）。 */
export function cleanTaiwan(raw: unknown): TaiwanVoice | undefined {
  const c = raw as Partial<TaiwanVoice> | null | undefined;
  if (!c || typeof c !== "object") return undefined;
  if (c.provider !== "azure" && c.provider !== "gemini") return undefined;
  if (c.gender !== "female" && c.gender !== "male") return undefined;
  const model = typeof c.model === "string" ? c.model.trim() : "";
  if (model && !SAFE.test(model)) return undefined;
  const voices: Partial<Record<TaiwanGender, string>> = {};
  for (const g of ["female", "male"] as const) {
    const v = typeof c.voices?.[g] === "string" ? c.voices[g]!.trim() : "";
    if (v && SAFE.test(v)) voices[g] = v;
  }
  return {
    provider: c.provider,
    gender: c.gender,
    ...(model ? { model } : {}),
    ...(Object.keys(voices).length ? { voices } : {}),
  };
}

/**
 * 台湾の声から、実際に頼む声を決める。決められなければ null（= 台湾の声は無効）。
 * Azure は台湾の表の声だけ（表に無い声を手で入れても使わない）。Gemini は開発者が
 * 選んだ声が要る（性別の声が未選択なら無効 — 別の性別・別の声で鳴らさない）。
 */
export function taiwanChoice(t: TaiwanVoice | null | undefined): TtsChoice | null {
  if (!t) return null;
  if (t.provider === "azure") {
    const list = TAIWAN_AZURE_VOICES[t.gender];
    const want = t.voices?.[t.gender];
    const voice = want && list.includes(want) ? want : list[0];
    return { provider: "azure", voice };
  }
  const voice = t.voices?.[t.gender];
  if (!voice) return null;
  const info = providerInfo("gemini");
  const model = t.model && info?.models.includes(t.model) ? t.model : info?.models[0];
  return { provider: "gemini", voice, ...(model ? { model } : {}) };
}

/**
 * **声の札。** 貯めた音の置き場所（サーバ・端末の両方）に混ぜる。
 * 何も選んでいなければ、これまでの `alloy`。
 *
 * 道にも PostgREST の絞り込みにも入るので、英数字と `_` `-` だけにする
 * （`.` は絞り込みの区切りと紛れる）。
 */
export function voiceTag(choice: TtsChoice | null | undefined): string {
  if (!choice) return TTS_VOICE_DEFAULT;
  const part = (s: string) => s.replace(/[^A-Za-z0-9-]+/g, "_").slice(0, 60);
  return [choice.provider, part(choice.voice), choice.model ? part(choice.model) : ""]
    .filter(Boolean)
    .join("_");
}

/** その言語で使う声（選んでいなければ null = これまでの声）。 */
export function choiceFor(
  config: TtsVoiceConfig | null | undefined,
  language: string,
): TtsChoice | null {
  // 台湾の声が決まっていれば、zh-TW はいつもこれ（アプリ全体で1つの声）。
  if (language === TAIWAN_LANGUAGE) {
    const t = taiwanChoice(config?.taiwan);
    if (t) return t;
  }
  const c = config?.languages?.[language];
  return c && providerInfo(c.provider) ? c : null;
}

/**
 * 台湾の声が有効か（= zh-TW の読み上げは他の声へ切り替えない）。
 * 有効な間、失敗してもこれまでの声・端末の声へは落とさない。
 */
export function isVoiceLocked(config: TtsVoiceConfig | null | undefined, language: string) {
  return language === TAIWAN_LANGUAGE && taiwanChoice(config?.taiwan) !== null;
}

// ---- 各社への頼み方（純粋な部分） ------------------------------------------

function escapeXml(s: string): string {
  return s.replace(/[<>&'"]/g, (ch) =>
    ch === "<"
      ? "&lt;"
      : ch === ">"
        ? "&gt;"
        : ch === "&"
          ? "&amp;"
          : ch === "'"
            ? "&apos;"
            : "&quot;",
  );
}

/** Azure の SSML。速さは `prosody rate` の百分率（0.95 → -5%）。 */
export function azureSsml(text: string, voice: string, speed: number): string {
  const lang = voice.split("-").slice(0, 2).join("-");
  const rate = Math.round((speed - 1) * 100);
  return (
    `<speak version='1.0' xml:lang='${escapeXml(lang)}'>` +
    `<voice name='${escapeXml(voice)}'>` +
    `<prosody rate='${rate >= 0 ? "+" : ""}${rate}%'>${escapeXml(text)}</prosody>` +
    `</voice></speak>`
  );
}

/**
 * 読み上げの会社に渡す言語の名前。台湾華語・英語はいままでどおり
 * (`zh` で始まれば中国語、それ以外は英語)。日本語だけ自分の名前を渡す —
 * 前の2分岐のままだと、日本語の語を「英語として読め」と頼むことになる。
 */
function providerLanguage(language: string, zh: string, other: string, ja: string): string {
  if (language.startsWith("zh")) return zh;
  return language === "ja" ? ja : other;
}

/** ElevenLabs で言語を固定できるのは Turbo / Flash v2.5 だけ（他は付けると断られる）。 */
export function elevenLabsBody(text: string, model: string, speed: number, language: string) {
  const enforce = model === "eleven_flash_v2_5" || model === "eleven_turbo_v2_5";
  return {
    text,
    model_id: model,
    ...(enforce ? { language_code: providerLanguage(language, "zh", "en", "ja") } : {}),
    voice_settings: { speed: Math.min(1.2, Math.max(0.7, speed)) },
  };
}

// ---- Gemini（3.8 TTS） ---------------------------------------------------------

/**
 * Gemini TTS の頼み方（`generateContent`）。声は `voiceName` に入れる（内蔵の声・拡張ライブラリ
 * の声のどちらも名前で指す）。言語は入力の文から自動で判るので指定しない。
 * 台湾なまりは**声で決める**（公式: なまりの恒久的な変更を style の指示に入れず、地域の
 * 声を選ぶこと）ので、文章には何も足さない。
 */
export function geminiBody(text: string, voice: string) {
  return {
    contents: [{ parts: [{ text }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } },
    },
  };
}

/** 16bit モノラルの生の音（PCM）に WAV の頭（RIFF）を付ける。 */
export function pcmToWav(pcm: Uint8Array, sampleRate = 24000): Uint8Array {
  const header = new ArrayBuffer(44);
  const v = new DataView(header);
  const str = (o: number, s: string) => {
    for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i));
  };
  str(0, "RIFF");
  v.setUint32(4, 36 + pcm.length, true);
  str(8, "WAVE");
  str(12, "fmt ");
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true); // PCM
  v.setUint16(22, 1, true); // mono
  v.setUint32(24, sampleRate, true);
  v.setUint32(28, sampleRate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  str(36, "data");
  v.setUint32(40, pcm.length, true);
  const out = new Uint8Array(44 + pcm.length);
  out.set(new Uint8Array(header), 0);
  out.set(pcm, 44);
  return out;
}

export function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/**
 * Gemini の返事から音を取り出す。**3.8 は WAV（RIFF 付き）、以前の TTS モデルは頭の無い PCM
 * （`audio/L16;rate=24000`）**を返すので、どちらでも鳴る WAV にそろえる。
 * 音が無い（安全上の拒否・文だけ返った等）ときは投げる。
 */
export function geminiAudioFrom(json: unknown): { bytes: Uint8Array; mime: string } {
  const parts = (
    json as {
      candidates?: Array<{
        content?: { parts?: Array<{ inlineData?: { data?: string; mimeType?: string } }> };
      }>;
    }
  )?.candidates?.[0]?.content?.parts;
  const inline = parts?.find((p) => p.inlineData?.data)?.inlineData;
  if (!inline?.data) throw new Error("TTS gemini empty audio");
  const bytes = base64ToBytes(inline.data);
  const mime = (inline.mimeType ?? "").toLowerCase();
  const riff = bytes.length > 4 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF";
  if (riff || mime.includes("wav")) return { bytes, mime: "audio/wav" };
  if (mime.includes("mpeg") || mime.includes("mp3")) return { bytes, mime: "audio/mpeg" };
  const rate = Number(/rate=(\d+)/.exec(mime)?.[1] ?? 24000);
  return {
    bytes: pcmToWav(bytes, Number.isFinite(rate) && rate > 0 ? rate : 24000),
    mime: "audio/wav",
  };
}

export type GeminiVoiceInfo = {
  id: string;
  name: string;
  gender: string;
  accent: string;
  languages: string[];
};

export type GeminiDiagnosis = {
  keyPresent: boolean;
  /** 見つけた鍵の**名前**（値ではない）。 */
  keyEnv: string | null;
  models: Array<{ id: string; ok: boolean; status: number }>;
  voices: Record<"female" | "male", GeminiVoiceInfo[]>;
  /** 声の一覧が取れなかった理由（HTTP 状態と短い説明）。 */
  voicesError: string | null;
};
