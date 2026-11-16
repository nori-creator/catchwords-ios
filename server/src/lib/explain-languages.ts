import { CHINESE_EXPLANATION_LANGUAGE } from "./target-lang";

/**
 * **解説の言語（読む人の言語）の一覧。** AI が意味・訳・注記・添削を書く言語で、
 * `profiles.ui_language` に入る値。
 *
 * オーナー指示 2026-10-20:
 * > 「iOS版の表示言語 いろんな言語に対応させたい。まずは今の英語と日本語に加えて、
 * >  繁體字（台灣），スペイン語、韓国語、ベトナム語に対応させる。」
 *
 * ## Web の画面の言語（`UI_LANGS`）とは別に持つ
 * Web の画面の文字（`DICT`）は `Record<UiLang, string>` で、言語を1つ足すと約1,000件の
 * 訳が要る。iOS の画面は iOS の翻訳表が持つので、サーバに要るのは「その言語で解説を
 * 書ける」ことだけ。だから **画面の言語 ⊆ 解説の言語** として、こちらだけを増やす。
 * Web は自分の画面に無い言語の人には英語で描き（`webUiLangOf`）、その人の設定は
 * 書き換えない（`language-sync.ts`）。
 *
 * ## iOS と同じ一覧
 * 符号・並びは iOS の `ios/Localization/languages.json` と同じ。並びは母語の選択肢
 * （`L1_ORDER`）の順でもあり、iOS は同じ順で `word_explanations` の `l1` を選ぶので、
 * **順を変えると iOS が別の行を探す。** 足すときは末尾に足す。iOS 側の確認
 * （`scripts/check_native_contract.py`）が、iOS の表示言語がここに全部あるかを毎日見る。
 *
 * 足し方: `docs/adding-a-language.md` の「解説の言語を足す」。
 */
export type ExplainScript = "kana" | "han" | "hangul" | "latin";

export type ExplainLanguageInfo = {
  /** `profiles.ui_language` / `word_explanations.explain_lang` の値。 */
  readonly code: string;
  /** AI への指示文（日本語）の中での呼び名。 */
  readonly promptName: string;
  /** 英語の指示文での呼び名（その言語自身の名前を添えて使う）。 */
  readonly englishName: string;
  /** その言語自身の名前。 */
  readonly autonym: string;
  /** 書く文字。読む人の言語の判定（`note-language.ts` ほか）はこれで分かれる。 */
  readonly script: ExplainScript;
  /** 日付・数の書式。 */
  readonly locale: string;
  /**
   * 欧文の言語どうしを見分ける手がかり: その言語に多い短い語。**他の欧文の言語に
   * 無い物だけ**が数えられる（`latinLanguageOf`）。
   */
  readonly markerWords: readonly string[];
  /** 同じく、その言語に特有の文字（đ ơ ư、ñ）。 */
  readonly markerLetters: string;
  /** 英語の指示文に添える、その言語の書き方の決まり。 */
  readonly writingRule: string;
  /**
   * **単語の中身（意味・例文の訳・型の訳と解説・量詞の注・関連語・メモ）を、その言語で自然に書く決まり**
   * （オーナー 2026-11-16「直訳ではなくて最も自然な訳を表示したい」）。本番の行で見つかった直訳・誤訳・
   * 文体の混ざりの例を、その言語の読者の指示にだけ入れる（`reader-style.ts` の `readerStyleRule`）。
   * 話し方は画面の訳と同じ（es は tú・中南米寄りの中立、ko は 해요체、vi は bạn、en は米国）。
   */
  readonly contentStyle: string;
};

export const EXPLAIN_LANGUAGES = [
  {
    code: "ja",
    promptName: "日本語",
    englishName: "Japanese",
    autonym: "日本語",
    script: "kana",
    locale: "ja-JP",
    markerWords: [],
    markerLetters: "",
    writingRule: "",
    contentStyle:
      "日本語: 解説・注記・メモ（文で書く欄）はすべて「です・ます」でそろえる（「だ・である」を混ぜない）。" +
      "型の訳・関連語の gloss・場面の札は「です」を付けない短い句。型の訳は辞書形（✗「リモコンを押す」→ ○「リモコンのボタンを押す」）。" +
      "硬い直訳語を作らず、日本人がふだん使う呼び名にする（✗「都市高速鉄道」→ ○「MRT」）。" +
      "文中の中国語の前後に空白を入れず、句読点は全角（、。 — 半角の「,」を使わない）。",
  },
  {
    code: "en",
    promptName: "英語",
    englishName: "English",
    autonym: "English",
    script: "latin",
    locale: "en-US",
    markerWords: [
      "the",
      "of",
      "and",
      "to",
      "is",
      "are",
      "was",
      "were",
      "with",
      "for",
      "this",
      "that",
      "these",
      "those",
      "it",
      "its",
      "you",
      "your",
      "be",
      "been",
      "from",
      "by",
      "an",
      "or",
      "not",
      "can",
      "used",
      "when",
      "which",
      "who",
      "what",
      "on",
      "at",
      "as",
      "in",
      "into",
      "about",
      "something",
      "someone",
      "thing",
      "people",
    ],
    markerLetters: "",
    writingRule: "",
    contentStyle:
      "English: US English (sidewalk, trash can, cell phone). Natural collocations, not word for word: " +
      '✗ "very delicious" → ○ "really good"; ✗ "order one teppan noodles" → ○ "order the teppanyaki noodles". ' +
      "Use articles and plurals correctly. Call each dish or object by one name in every field: its usual English name if it has one, " +
      'otherwise one romanized name — never "soup dumplings" in one field and "xiaolongbao" in another.',
  },
  {
    code: CHINESE_EXPLANATION_LANGUAGE,
    promptName: "繁體中文(台湾)",
    englishName: "Traditional Chinese as written in Taiwan",
    autonym: "繁體中文",
    script: "han",
    locale: "zh-Hant-TW",
    markerWords: [],
    markerLetters: "",
    writingRule: "",
    contentStyle:
      "繁體中文（台灣）: Taiwan wording and full-width punctuation (，。、「」 — no half-width \",\", no spaces around Chinese words). No Japanese forms, words or the 「・」 dot " +
      "(✗ 日常会話 → ○ 日常會話; ✗ 天然石 → the Taiwan term). In a sentence call the language 中文, not 台灣華語. " +
      "meaning_ja is never the headword and never contains it — say what it is in other words (✗ 防曬乳 →「防曬乳」→ ○「防曬用的乳液」). " +
      "Never define a related word with itself. A measure_words note says when that measure word is used, never just the word (✗「一個」).",
  },
  {
    code: "es",
    promptName: "スペイン語",
    englishName: "Spanish",
    autonym: "español",
    script: "latin",
    locale: "es",
    markerWords: [
      "el",
      "la",
      "los",
      "las",
      "del",
      "de",
      "que",
      "en",
      "un",
      "una",
      "unos",
      "unas",
      "es",
      "son",
      "por",
      "para",
      "se",
      "su",
      "sus",
      "al",
      "lo",
      "como",
      "más",
      "muy",
      "pero",
      "este",
      "esta",
      "estos",
      "estas",
      "también",
      "cuando",
      "donde",
      "sin",
      "sobre",
      "entre",
      "hay",
      "está",
      "están",
      "ser",
      "puede",
      "algo",
      "alguien",
    ],
    markerLetters: "ñ¿¡",
    writingRule: "Use neutral Spanish leaning Latin American, and address the learner as tú.",
    contentStyle:
      "Spanish: full sentences with their articles and prepositions (not telegraphic). Say it as a native speaker would, not a calque: " +
      "✗ «bueno para el cuerpo» → ○ «bueno para la salud»; ✗ «cambiarse a pantuflas» → ○ «ponerse las pantuflas»; " +
      "小聲一點 → ○ «habla más bajo» (not «despacio»). Never drop a Chinese phrase into the Spanish sentence (✗ «quitarse los zapatos y 換拖鞋»). " +
      "One word per object in every field (not chancletas here and chanclas there). No exaggeration (✗ «obligatorio», «inseparable», «sumamente»).",
  },
  {
    code: "ko",
    promptName: "韓国語",
    englishName: "Korean",
    autonym: "한국어",
    script: "hangul",
    locale: "ko-KR",
    markerWords: [],
    markerLetters: "",
    writingRule: "Write Korean in Hangul only — no Hanja, no Japanese — in the polite 해요체.",
    contentStyle:
      "Korean: every note and explanation in 해요체 (never mixed with ~다); glosses and scene labels are short phrases. " +
      "Call the thing by its Korean name instead of attaching particles straight to Chinese characters (✗ 珍珠奶茶를 → ○ 버블티를); " +
      "quote a Chinese word only when explaining it (‘戴’는 …). Korean word order, not the Chinese one.",
  },
  {
    code: "vi",
    promptName: "ベトナム語",
    englishName: "Vietnamese",
    autonym: "Tiếng Việt",
    script: "latin",
    locale: "vi-VN",
    markerWords: [
      "của",
      "và",
      "là",
      "một",
      "có",
      "không",
      "cho",
      "với",
      "này",
      "được",
      "những",
      "các",
      "người",
      "trong",
      "khi",
      "để",
      "cũng",
      "đã",
      "rất",
      "thì",
      "mà",
      "nhưng",
      "hoặc",
      "nên",
      "từ",
      "khác",
      "đó",
      "gì",
    ],
    markerLetters: "ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịĩọỏốồổỗộớờởỡợũụủứừửữựỳỵỷỹ",
    writingRule: "Write Vietnamese with full diacritics.",
    contentStyle:
      "Vietnamese: natural spoken register, address the learner as bạn. Do not render 請 as «làm ơn» by default — in a polite request " +
      "Vietnamese usually drops it or says «cho mình…», «mời…», «…nhé». Translate the meaning, not word by word " +
      "(難得 → «khó lắm mới có dịp…», not «Hiếm khi»).",
  },
] as const satisfies readonly ExplainLanguageInfo[];

export type ExplainLang = (typeof EXPLAIN_LANGUAGES)[number]["code"];

/** 解説の言語の一覧。**先頭が既定**（知らない値はここへ落とす）。 */
export const EXPLAIN_LANGS: readonly ExplainLang[] = EXPLAIN_LANGUAGES.map((l) => l.code);

const BY_CODE: ReadonlyMap<string, ExplainLanguageInfo> = new Map(
  EXPLAIN_LANGUAGES.map((l) => [l.code, l]),
);

export function isExplainLang(v: unknown): v is ExplainLang {
  return typeof v === "string" && BY_CODE.has(v);
}

/** 知らない値は既定（日本語）に落とす。`normalizeUiLang` と同じ考え方。 */
export function normalizeExplainLang(raw: string | null | undefined): ExplainLang {
  const v = (raw ?? "").trim();
  return isExplainLang(v) ? v : EXPLAIN_LANGS[0];
}

/** その言語の情報。知らない符号は `null`。 */
export function explainLanguage(code: string | null | undefined): ExplainLanguageInfo | null {
  return BY_CODE.get((code ?? "").trim()) ?? null;
}

/** その言語を書く文字。台湾華語以外の `zh-*`（`zh-Hant` など）も漢字として扱う。 */
export function explainScript(code: string | null | undefined): ExplainScript | null {
  const c = (code ?? "").trim();
  const hit = BY_CODE.get(c);
  if (hit) return hit.script;
  return c.toLowerCase().startsWith("zh") ? "han" : null;
}

/** 2つの言語が同じ文字で書かれるか（文字だけでは見分けられない組か）。 */
export function sameExplainScript(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  const x = explainScript(a);
  return x !== null && x === explainScript(b);
}

/** 欧文の言語ごとの、他の欧文の言語に無い手がかり（語と文字）。 */
const LATIN_MARKERS: ReadonlyArray<{ code: string; words: ReadonlySet<string>; letters: string }> =
  (() => {
    const latin = EXPLAIN_LANGUAGES.filter((l) => l.script === "latin");
    return latin.map((l) => {
      const others = latin.filter((o) => o.code !== l.code);
      const words = (l.markerWords as readonly string[]).filter(
        (w) => !others.some((o) => (o.markerWords as readonly string[]).includes(w)),
      );
      const letters = [...l.markerLetters]
        .filter((c) => !others.some((o) => o.markerLetters.includes(c)))
        .join("");
      return { code: l.code, words: new Set(words), letters };
    });
  })();

/**
 * **欧文がどの言語で書かれているか**（はっきりしている時だけ）。iOS の
 * `LanguageRules.latinLanguage` と同じ数え方: その言語だけの語は1語ずつ、その言語だけの
 * 文字は1文字ずつ数え、2つ以上で、2番目の言語の2倍以上なら、その言語。
 * 手がかりの無い短い意味（"bus stop"）は分からない（`null`）。
 */
export function latinLanguageOf(text: string | null | undefined): string | null {
  if (LATIN_MARKERS.length < 2) return null;
  const lower = (text ?? "").toLowerCase();
  const words = lower.split(/[^\p{L}]+/u).filter(Boolean);
  const scores = LATIN_MARKERS.map((m) => {
    let n = words.filter((w) => m.words.has(w)).length;
    if (m.letters) for (const ch of lower) if (m.letters.includes(ch)) n++;
    return { code: m.code, n };
  }).sort((a, b) => b.n - a.n);
  const [top, second] = scores;
  if (!top || top.n < 2) return null;
  return top.n >= (second?.n ?? 0) * 2 ? top.code : null;
}
