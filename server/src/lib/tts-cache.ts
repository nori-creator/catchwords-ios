/**
 * Deterministic storage path for cached TTS audio. Because the path is a pure
 * function of (language, voice, text[, pronunciation identity]), any code can
 * compute where a word's audio lives without a DB column: if the object exists
 * we reuse it, if not the TTS server function generates and uploads it.
 */
export const TTS_VOICE_DEFAULT = "alloy";

/**
 * **発音の見分け**（PRODUCT.md › Pronunciation / TTS「Cache identity must distinguish …
 * canonical reading/pronunciation, POS when relevant」、ARCHITECTURE.md › TTS、2026-10-03）。
 *
 * 同じ綴りで読みが違う語（多音字の 行 xíng / háng、英語の read・lead）が、同じ音を
 * 使い回さないよう、読み（拼音・注音・IPA）と品詞を置き場所の鍵に混ぜる。
 *
 * ## 古い置き場所を読めるままにする
 * 読みも品詞も分からない呼び出し（今までの全部）は、**今までと同じ鍵**になる
 * （`speechIdentity` が空を返す）。読みが要らない語（多音字を含まない華語・
 * 読み違えの無い英語）も今までの鍵のまま — 既に貯めた音・作り置きをそのまま使い、
 * 作り直しの費用を増やさない。鍵が分かれるのは**読み違えが起こり得る語で、
 * 読みか品詞が分かっている時だけ**。
 */
export type SpeechIdentityInput = {
  /** 拼音（声調記号つき）。華語ではこれを先に使う。 */
  pinyin?: string | null;
  /** 注音。拼音が無い時だけ使う。 */
  zhuyin?: string | null;
  /** 英語などの IPA。 */
  ipa?: string | null;
  /** 品詞（「名詞」「noun」「Vi」など、どの書き方でもよい）。 */
  pos?: string | null;
};

/**
 * 読みが文脈で変わる字（多音字）。この字を含む華語の語だけ、読みで鍵を分ける。
 * 繁体字・簡体字の両方。網羅でなくてよい（漏れた語は今までどおり1つの音を共有する）。
 */
const ZH_POLYPHONIC = new Set(
  Array.from(
    "行長长還还為为樂乐傳传當当調调發发乾干間间將将會会結结數数應应種种著着轉转處处參参" +
      "稱称惡恶載载曾重了得都好便差地和假教角看空累難难相中朝大背薄藏衝冲答打倒的度分更" +
      "觀观橫横哄解卷圈強强切少舍捨省似宿提吐喝畜血要扎只隻正佛降泊奔臭量興兴率覺觉" +
      "供給给號号盛縫缝鮮鲜漂磨模",
  ).filter((c) => /\p{Script=Han}/u.test(c)),
);

/**
 * 綴りが同じで読みが違う英語（heteronyms）。品詞か IPA で鍵を分ける。
 * 小文字で比べる。網羅でなくてよい。
 */
const EN_HETERONYMS = new Set([
  "bass",
  "bow",
  "close",
  "conduct",
  "conflict",
  "console",
  "content",
  "contest",
  "contract",
  "desert",
  "dove",
  "excuse",
  "house",
  "lead",
  "live",
  "minute",
  "moped",
  "object",
  "permit",
  "present",
  "produce",
  "progress",
  "project",
  "read",
  "record",
  "refuse",
  "row",
  "separate",
  "sow",
  "subject",
  "tear",
  "use",
  "wind",
  "wound",
]);

/** その綴りが、読みで鍵を分ける必要のある語か。 */
export function isPronunciationAmbiguous(language: string, text: string): boolean {
  const t = text.trim();
  if (!t) return false;
  if (language.startsWith("zh")) return Array.from(t).some((c) => ZH_POLYPHONIC.has(c));
  if (language.startsWith("en")) return EN_HETERONYMS.has(t.toLowerCase());
  return false;
}

/** 読みを比べられる形に（Unicode の正規化・小文字・空白と区切りの記号を落とす）。 */
export function normalizeReading(reading: string | null | undefined): string {
  return (reading ?? "")
    .normalize("NFC")
    .toLowerCase()
    .replace(/[\s/[\]()'’\-.·・]/g, "");
}

/**
 * 品詞を小さな集合に寄せる。分からない書き方は空（鍵に入れない）。
 * 画面の言語ごとに書き方が違う（名詞・noun・N）ので、そのまま鍵にすると同じ語が割れる。
 */
export function canonicalPos(pos: string | null | undefined): string {
  const p = (pos ?? "").normalize("NFC").trim().toLowerCase();
  if (!p) return "";
  if (/^(n|noun|名詞|名|名词|專有名詞|量詞|量词|m)$/.test(p)) return "n";
  if (/^(v|vi|vt|vs|vp|verb|動詞|动词|動|动)$/.test(p) || /^v[a-z]?(-sep)?$/.test(p)) return "v";
  if (/^(adj|a|adjective|形容詞|形容词|形容動詞|形)$/.test(p)) return "adj";
  if (/^(adv|ad|adverb|副詞|副词|副)$/.test(p)) return "adv";
  if (/^(prep|preposition|介詞|介词|前置詞)$/.test(p)) return "prep";
  return "";
}

/**
 * 鍵に混ぜる発音の印。空文字なら**今までと同じ鍵**（`ttsObjectPath` / `audioCacheKey`）。
 * - 華語: 多音字を含み、読み（拼音 → 注音）が分かる時だけ `r=…`。品詞は拼音が読みを
 *   決め切るので混ぜない（候補の段の仮の品詞で鍵が割れないように）。
 * - 英語: 読み違えの起こる綴りで、IPA か品詞が分かる時だけ `r=…` / `p=…`。
 */
export function speechIdentity(
  language: string,
  text: string,
  input: SpeechIdentityInput | null | undefined,
): string {
  if (!input || !isPronunciationAmbiguous(language, text)) return "";
  if (language.startsWith("zh")) {
    const py = normalizeReading(input.pinyin);
    if (py) return `r=py:${py}`;
    const zy = normalizeReading(input.zhuyin);
    return zy ? `r=zy:${zy}` : "";
  }
  const ipa = normalizeReading(input.ipa);
  const pos = canonicalPos(input.pos);
  return [ipa && `r=ipa:${ipa}`, pos && `p=${pos}`].filter(Boolean).join("|");
}

export async function ttsObjectPath(
  language: string,
  voice: string,
  text: string,
  identity = "",
): Promise<string> {
  // 印が無ければ今までと同じ材料（= 同じ置き場所）。
  const material = identity ? `${text}\u0000${identity}` : text;
  const bytes = new TextEncoder().encode(material);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${language}/${voice}/${hex}.mp3`;
}
