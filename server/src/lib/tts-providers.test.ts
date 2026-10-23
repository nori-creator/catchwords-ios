import { describe, expect, it } from "vitest";
import {
  azureSsml,
  base64ToBytes,
  choiceFor,
  cleanTtsConfig,
  geminiAudioFrom,
  geminiBody,
  isVoiceLocked,
  pcmToWav,
  TAIWAN_AZURE_VOICES,
  taiwanChoice,
  elevenLabsBody,
  TTS_PROVIDERS,
  voiceTag,
} from "./tts-providers";

describe("発音の声の会社（開発者だけが選ぶ。オーナー指示 2026-09-23）", () => {
  it("繋いである3社だけを並べる（未接続の VoAI・ATEN は 2026-10-09 に外した）", () => {
    expect(TTS_PROVIDERS.map((p) => p.id)).toEqual(["azure", "gemini", "elevenlabs"]);
  });

  it("外した会社（2026-10-03 オーナー決定）が保存済みの設定に残っていても選ばれない", () => {
    const stale = { languages: { "zh-TW": { provider: "minimax", voice: "v1" } } } as never;
    expect(cleanTtsConfig(stale)).toEqual({});
    // 掃除前の古い設定を直接渡しても、表に無い会社は既定の声（null）に戻る。
    expect(choiceFor(stale, "zh-TW")).toBeNull();
  });

  it("保存の前に掃除する: 未接続・知らない会社・空の声・変な字は捨てる", () => {
    expect(
      cleanTtsConfig({
        languages: {
          "zh-TW": { provider: "azure", voice: " zh-TW-HsiaoChenNeural " },
          en: { provider: "voai", voice: "x" },
          fr: { provider: "azure", voice: "fr-FR-X" },
        },
      }),
    ).toEqual({ languages: { "zh-TW": { provider: "azure", voice: "zh-TW-HsiaoChenNeural" } } });
    expect(cleanTtsConfig({ languages: { en: { provider: "azure", voice: "" } } })).toEqual({});
    expect(cleanTtsConfig({ languages: { en: { provider: "azure", voice: "a/../b" } } })).toEqual(
      {},
    );
    expect(cleanTtsConfig(null)).toEqual({});
  });

  it("声の札: 何も選ばなければこれまでの alloy（今ある音をそのまま使う）", () => {
    expect(voiceTag(null)).toBe("alloy");
    expect(choiceFor({}, "zh-TW")).toBeNull();
  });

  it("声の札は英数字と _ - だけ（置き場所の道と絞り込みに入るので）。声・モデルが違えば札も違う", () => {
    const a = voiceTag({ provider: "elevenlabs", voice: "abc.DEF 1", model: "eleven_flash_v2_5" });
    expect(a).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(a).not.toBe(
      voiceTag({ provider: "elevenlabs", voice: "abc.DEF 1", model: "eleven_v3" }),
    );
    expect(voiceTag({ provider: "azure", voice: "zh-TW-HsiaoChenNeural" })).toBe(
      "azure_zh-TW-HsiaoChenNeural",
    );
  });

  it("Azure: 言語は声の名前から、速さは百分率、字は XML として逃がす", () => {
    const x = azureSsml("A&B<C>", "zh-TW-HsiaoChenNeural", 0.95);
    expect(x).toContain("xml:lang='zh-TW'");
    expect(x).toContain("<prosody rate='-5%'>A&amp;B&lt;C&gt;</prosody>");
  });

  it("ElevenLabs: 言語の固定は Flash / Turbo v2.5 だけに付ける（他は断られる）", () => {
    expect(elevenLabsBody("你好", "eleven_flash_v2_5", 0.95, "zh-TW").language_code).toBe("zh");
    expect("language_code" in elevenLabsBody("你好", "eleven_v3", 0.95, "zh-TW")).toBe(false);
    expect(elevenLabsBody("x", "eleven_v3", 2, "en").voice_settings.speed).toBe(1.2);
  });
});

describe("台湾の声（R18: 必ず台湾・男女を選べる・アプリ全体で1つの声）", () => {
  it("Azure は台湾（zh-TW）の表の声だけ。性別で決まり、表に無い声は使わない", () => {
    expect(taiwanChoice({ provider: "azure", gender: "female" })).toEqual({
      provider: "azure",
      voice: "zh-TW-HsiaoChenNeural",
    });
    expect(taiwanChoice({ provider: "azure", gender: "male" })?.voice).toBe("zh-TW-YunJheNeural");
    // 表にある別の女声は選べる。表に無い声（大陸の声など）は捨てて表の先頭に戻る。
    expect(
      taiwanChoice({
        provider: "azure",
        gender: "female",
        voices: { female: "zh-TW-HsiaoYuNeural" },
      })?.voice,
    ).toBe("zh-TW-HsiaoYuNeural");
    expect(
      taiwanChoice({
        provider: "azure",
        gender: "female",
        voices: { female: "zh-CN-XiaoxiaoNeural" },
      })?.voice,
    ).toBe("zh-TW-HsiaoChenNeural");
    for (const list of Object.values(TAIWAN_AZURE_VOICES))
      for (const v of list) expect(v.startsWith("zh-TW-")).toBe(true);
  });

  it("Gemini は選んだ性別の声が要る。未選択なら無効（別の性別・別の声で鳴らさない）", () => {
    expect(taiwanChoice({ provider: "gemini", gender: "male" })).toBeNull();
    expect(
      taiwanChoice({ provider: "gemini", gender: "male", voices: { female: "Aoede" } }),
    ).toBeNull();
    expect(
      taiwanChoice({
        provider: "gemini",
        gender: "female",
        voices: { female: "Aoede" },
        model: "gemini-3.8-flash-tts",
      }),
    ).toEqual({ provider: "gemini", voice: "Aoede", model: "gemini-3.8-flash-tts" });
    // 知らないモデル名は既定（軽いほう）に戻す。
    expect(
      taiwanChoice({
        provider: "gemini",
        gender: "female",
        voices: { female: "Aoede" },
        model: "x",
      })?.model,
    ).toBe("gemini-3.8-flash-lite-tts");
  });

  it("台湾の声が決まっていれば zh-TW はいつもそれ。英語には効かない", () => {
    const config = cleanTtsConfig({
      taiwan: { provider: "azure", gender: "male" },
      languages: { en: { provider: "azure", voice: "en-US-JennyNeural" } },
    });
    expect(choiceFor(config, "zh-TW")?.voice).toBe("zh-TW-YunJheNeural");
    expect(choiceFor(config, "en")?.voice).toBe("en-US-JennyNeural");
    expect(isVoiceLocked(config, "zh-TW")).toBe(true);
    expect(isVoiceLocked(config, "en")).toBe(false);
    // 言語ごとの設定より台湾の声が優先される。
    const both = cleanTtsConfig({
      taiwan: { provider: "azure", gender: "female" },
      languages: { "zh-TW": { provider: "azure", voice: "zh-CN-XiaoxiaoNeural" } },
    });
    expect(choiceFor(both, "zh-TW")?.voice).toBe("zh-TW-HsiaoChenNeural");
  });

  it("台湾の声が無効（Gemini の声が未選択）ならロックしない", () => {
    const config = cleanTtsConfig({ taiwan: { provider: "gemini", gender: "female" } });
    expect(isVoiceLocked(config, "zh-TW")).toBe(false);
    expect(choiceFor(config, "zh-TW")).toBeNull();
  });

  it("保存の前の掃除: 知らない会社・性別・変な字の声は捨てる", () => {
    expect(
      cleanTtsConfig({ taiwan: { provider: "voai", gender: "female" } }).taiwan,
    ).toBeUndefined();
    expect(cleanTtsConfig({ taiwan: { provider: "azure", gender: "x" } }).taiwan).toBeUndefined();
    expect(
      cleanTtsConfig({
        taiwan: { provider: "gemini", gender: "female", voices: { female: "a/b", male: " Kore " } },
      }).taiwan?.voices,
    ).toEqual({ male: "Kore" });
  });
});

describe("Gemini TTS の頼み方と返事（3.8 は WAV、以前は頭の無い PCM）", () => {
  it("声は voiceName に入れ、文には何も足さない（台湾なまりは声で決める）", () => {
    const body = geminiBody("你好", "Aoede");
    expect(body.contents[0].parts[0].text).toBe("你好");
    expect(body.generationConfig.responseModalities).toEqual(["AUDIO"]);
    expect(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName).toBe(
      "Aoede",
    );
  });

  it("PCM には WAV の頭（RIFF・24kHz・16bit・モノラル）を付ける", () => {
    const wav = pcmToWav(new Uint8Array([1, 2, 3, 4]));
    expect(String.fromCharCode(...wav.slice(0, 4))).toBe("RIFF");
    expect(String.fromCharCode(...wav.slice(8, 12))).toBe("WAVE");
    const v = new DataView(wav.buffer);
    expect(v.getUint32(24, true)).toBe(24000);
    expect(v.getUint16(34, true)).toBe(16);
    expect(v.getUint32(40, true)).toBe(4);
    expect(wav.length).toBe(48);
  });

  const reply = (data: string, mimeType: string) => ({
    candidates: [{ content: { parts: [{ inlineData: { data, mimeType } }] } }],
  });
  const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));

  it("RIFF 付きはそのまま、頭の無い PCM は WAV にそろえる", () => {
    const riff = pcmToWav(new Uint8Array([9, 9]));
    const a = geminiAudioFrom(reply(b64(riff), "audio/wav"));
    expect(a.mime).toBe("audio/wav");
    expect(Array.from(a.bytes)).toEqual(Array.from(riff));
    const b = geminiAudioFrom(reply(b64(new Uint8Array([1, 2])), "audio/L16;rate=16000"));
    expect(b.mime).toBe("audio/wav");
    expect(new DataView(b.bytes.buffer).getUint32(24, true)).toBe(16000);
    expect(Array.from(base64ToBytes(b64(new Uint8Array([7]))))).toEqual([7]);
  });

  it("音が無い返事（拒否・文だけ）は投げる", () => {
    expect(() =>
      geminiAudioFrom({ candidates: [{ content: { parts: [{ text: "x" }] } }] }),
    ).toThrow();
    expect(() => geminiAudioFrom({})).toThrow();
  });
});
