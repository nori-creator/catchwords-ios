/**
 * **拼音 ⇄ 注音の小さな変換器**（2026-10-03、本番で「拿鐵」が
 * 「nálǎtiě」と出た件）。
 *
 * 読みの検査（`tw-reading.server.ts`）が使う。外の部品を持たない純粋な
 * 関数だけなので、どちら側から読んでもよい。
 *
 * - 音節は「声調を除いた綴り（`base`）」と「声調 1〜4、5 = 軽声」で持つ。
 * - 注音の軽声は台湾の書き方どおり**前に** ˙ を置く（`zhuyin-layout.ts` と同じ）。
 * - 「ü」は `v` / `u:` でも受ける。
 */

export type Syllable = { base: string; tone: 1 | 2 | 3 | 4 | 5 };

const INITIALS: ReadonlyArray<readonly [string, string]> = [
  ["zh", "ㄓ"],
  ["ch", "ㄔ"],
  ["sh", "ㄕ"],
  ["b", "ㄅ"],
  ["p", "ㄆ"],
  ["m", "ㄇ"],
  ["f", "ㄈ"],
  ["d", "ㄉ"],
  ["t", "ㄊ"],
  ["n", "ㄋ"],
  ["l", "ㄌ"],
  ["g", "ㄍ"],
  ["k", "ㄎ"],
  ["h", "ㄏ"],
  ["j", "ㄐ"],
  ["q", "ㄑ"],
  ["x", "ㄒ"],
  ["r", "ㄖ"],
  ["z", "ㄗ"],
  ["c", "ㄘ"],
  ["s", "ㄙ"],
];

const FINALS: Record<string, string> = {
  a: "ㄚ",
  o: "ㄛ",
  e: "ㄜ",
  ai: "ㄞ",
  ei: "ㄟ",
  ao: "ㄠ",
  ou: "ㄡ",
  an: "ㄢ",
  en: "ㄣ",
  ang: "ㄤ",
  eng: "ㄥ",
  ong: "ㄨㄥ",
  i: "ㄧ",
  ia: "ㄧㄚ",
  ie: "ㄧㄝ",
  iao: "ㄧㄠ",
  iu: "ㄧㄡ",
  ian: "ㄧㄢ",
  in: "ㄧㄣ",
  iang: "ㄧㄤ",
  ing: "ㄧㄥ",
  iong: "ㄩㄥ",
  u: "ㄨ",
  ua: "ㄨㄚ",
  uo: "ㄨㄛ",
  uai: "ㄨㄞ",
  ui: "ㄨㄟ",
  uan: "ㄨㄢ",
  un: "ㄨㄣ",
  uang: "ㄨㄤ",
  ü: "ㄩ",
  üe: "ㄩㄝ",
  üan: "ㄩㄢ",
  ün: "ㄩㄣ",
};

/** 声母の無い音節（y / w で書く物を含む）。 */
const STANDALONE: Record<string, string> = {
  a: "ㄚ",
  o: "ㄛ",
  e: "ㄜ",
  ê: "ㄝ",
  ai: "ㄞ",
  ei: "ㄟ",
  ao: "ㄠ",
  ou: "ㄡ",
  an: "ㄢ",
  en: "ㄣ",
  ang: "ㄤ",
  eng: "ㄥ",
  er: "ㄦ",
  yi: "ㄧ",
  ya: "ㄧㄚ",
  yo: "ㄧㄛ",
  ye: "ㄧㄝ",
  yai: "ㄧㄞ",
  yao: "ㄧㄠ",
  you: "ㄧㄡ",
  yan: "ㄧㄢ",
  yin: "ㄧㄣ",
  yang: "ㄧㄤ",
  ying: "ㄧㄥ",
  yong: "ㄩㄥ",
  yu: "ㄩ",
  yue: "ㄩㄝ",
  yuan: "ㄩㄢ",
  yun: "ㄩㄣ",
  wu: "ㄨ",
  wa: "ㄨㄚ",
  wo: "ㄨㄛ",
  wai: "ㄨㄞ",
  wei: "ㄨㄟ",
  wan: "ㄨㄢ",
  wen: "ㄨㄣ",
  wang: "ㄨㄤ",
  weng: "ㄨㄥ",
};

/** 声母ごとに付く韻母（組めない綴りを音節と数えないため。少し広めに取る）。 */
const ALLOWED: Record<string, readonly string[]> = (() => {
  const plain = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng"];
  const iGroup = ["i", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing"];
  const uGroup = ["u", "ua", "uo", "uai", "ui", "uan", "un", "uang"];
  const labial = [...plain, ...iGroup, "u"];
  const alveolar = [...plain, "ong", ...iGroup, "u", "uo", "ui", "uan", "un"];
  const velar = [...plain, "ong", ...uGroup];
  const palatal = [...iGroup, "iong", "ü", "üe", "üan", "ün"];
  const retroflex = [...plain, "ong", ...uGroup];
  const out: Record<string, readonly string[]> = {};
  for (const i of ["b", "p", "m", "f"]) out[i] = labial;
  for (const i of ["d", "t"]) out[i] = alveolar;
  for (const i of ["n", "l"]) out[i] = [...alveolar, "ü", "üe"];
  for (const i of ["g", "k", "h"]) out[i] = velar;
  for (const i of ["j", "q", "x"]) out[i] = palatal;
  for (const i of ["zh", "ch", "sh", "r", "z", "c", "s"]) out[i] = retroflex;
  return out;
})();

const SPECIAL_I = new Set(["zh", "ch", "sh", "r", "z", "c", "s"]);

/** 声調を除いた拼音1音節 → 注音（声調の印なし）。組めない綴りは `null`。 */
export function pinyinBaseToZhuyin(base: string): string | null {
  if (STANDALONE[base]) return STANDALONE[base];
  for (const [ini, zy] of INITIALS) {
    if (!base.startsWith(ini)) continue;
    let fin = base.slice(ini.length);
    if (fin === "i" && SPECIAL_I.has(ini)) return zy;
    // j/q/x の後の u は ü（ju = jü）。
    if ("jqx".includes(ini) && fin.startsWith("u")) fin = "ü" + fin.slice(1);
    if (!ALLOWED[ini]?.includes(fin)) return null;
    return zy + FINALS[fin];
  }
  return null;
}

/** 全音節の一覧（綴り → 注音）。逆引きと分かち書きに使う。 */
const INVENTORY: ReadonlyMap<string, string> = (() => {
  const m = new Map<string, string>();
  for (const [k, v] of Object.entries(STANDALONE)) m.set(k, v);
  for (const [ini] of INITIALS) {
    const fins = [...(ALLOWED[ini] ?? []), ...(SPECIAL_I.has(ini) ? ["i"] : [])];
    for (const fin of fins) {
      // j/q/x の ü は u で書く（ju, que, xuan, qun）。
      const spelled = "jqx".includes(ini) ? fin.replace("ü", "u") : fin;
      const zy = pinyinBaseToZhuyin(ini + spelled);
      if (zy) m.set(ini + spelled, zy);
    }
  }
  return m;
})();

const ZHUYIN_TO_BASE: ReadonlyMap<string, string> = (() => {
  const m = new Map<string, string>();
  for (const [base, zy] of INVENTORY) if (!m.has(zy)) m.set(zy, base);
  return m;
})();

export function isPinyinBase(base: string): boolean {
  return INVENTORY.has(base);
}

const TONE_MARK: Record<string, 1 | 2 | 3 | 4> = {
  "\u0304": 1,
  "\u0301": 2,
  "\u030c": 3,
  "\u0300": 4,
};
const MARK_OF: Record<number, string> = { 1: "\u0304", 2: "\u0301", 3: "\u030c", 4: "\u0300" };

/** 拼音1音節（声調記号つき・数字つき・声調なし）を読む。読めなければ `null`。 */
export function parsePinyinSyllable(raw: string): Syllable | null {
  let s = raw.normalize("NFD").toLowerCase();
  let tone: Syllable["tone"] | null = null;
  const digit = /([0-5])$/.exec(s);
  if (digit) {
    const d = Number(digit[1]);
    tone = d === 0 || d === 5 ? 5 : (d as 1 | 2 | 3 | 4);
    s = s.slice(0, -1);
  }
  let marks = 0;
  let out = "";
  for (const ch of s) {
    const t = TONE_MARK[ch];
    if (t) {
      marks++;
      tone = t;
    } else out += ch;
  }
  if (marks > 1 || (marks === 1 && digit)) return null;
  const base = out
    .normalize("NFC")
    .replace(/u:/g, "ü")
    .replace(/v/g, "ü")
    // j/q/x/y の後の ü は u と書く決まり。
    .replace(/^([jqxy])ü/, "$1u");
  if (!INVENTORY.has(base)) return null;
  return { base, tone: tone ?? 5 };
}

/** 声調記号つきの拼音1音節を書く（a/e が先、ou は o、ほかは最後の母音）。 */
export function formatPinyin(s: Syllable): string {
  if (s.tone === 5) return s.base;
  const b = s.base;
  let at = b.indexOf("a");
  if (at < 0) at = b.indexOf("e");
  if (at < 0) at = b.indexOf("ê");
  if (at < 0 && b.includes("ou")) at = b.indexOf("o");
  if (at < 0) {
    for (let i = b.length - 1; i >= 0; i--) {
      if ("iouü".includes(b[i])) {
        at = i;
        break;
      }
    }
  }
  if (at < 0) return b;
  return (b.slice(0, at + 1) + MARK_OF[s.tone] + b.slice(at + 1)).normalize("NFC");
}

/** 1音節 → 注音（軽声は前に ˙）。組めなければ `null`。 */
export function syllableToZhuyin(s: Syllable): string | null {
  const body = INVENTORY.get(s.base);
  if (!body) return null;
  if (s.tone === 5) return "˙" + body;
  return body + ({ 1: "", 2: "ˊ", 3: "ˇ", 4: "ˋ" } as const)[s.tone];
}

const ZY_TONE: Record<string, Syllable["tone"]> = { ˉ: 1, ˊ: 2, ˇ: 3, ˋ: 4, "˙": 5 };

/** 注音1音節を読む。読めなければ `null`。 */
export function parseZhuyinSyllable(raw: string): Syllable | null {
  let s = raw.trim();
  let tone: Syllable["tone"] = 1;
  if (s.startsWith("˙")) {
    tone = 5;
    s = s.slice(1);
  }
  const last = s.slice(-1);
  if (ZY_TONE[last]) {
    if (tone === 5) return null;
    tone = ZY_TONE[last];
    s = s.slice(0, -1);
  }
  const base = ZHUYIN_TO_BASE.get(s);
  return base ? { base, tone } : null;
}

/** 区切りの無い綴りの、音節数ごとの分け方（音節数 → 分け方）。 */
function segmentOptions(
  text: string,
  parseOne: (s: string) => Syllable | null,
  maxLen: number,
): Map<number, Syllable[]> {
  const chars = [...text];
  const memo = new Map<number, Map<number, Syllable[]>>();
  const from = (i: number): Map<number, Syllable[]> => {
    const hit = memo.get(i);
    if (hit) return hit;
    const out = new Map<number, Syllable[]>();
    if (i === chars.length) out.set(0, []);
    else {
      // 長い音節から試す（同じ数なら長く取った分け方が残る）。
      for (let len = Math.min(maxLen, chars.length - i); len >= 1; len--) {
        const syl = parseOne(chars.slice(i, i + len).join(""));
        if (!syl) continue;
        for (const [n, rest] of from(i + len)) {
          if (!out.has(n + 1)) out.set(n + 1, [syl, ...rest]);
        }
      }
    }
    memo.set(i, out);
    return out;
  };
  return from(0);
}

/**
 * 空白・区切り記号で切り、その中をさらに音節に分ける。
 * 合計が `want` 個になる分け方があればそれを（前の塊ほど少なく分ける）、
 * 無ければ塊ごとに一番少ない分け方を返す。読めない塊があれば `null`。
 */
function splitReading(
  text: string,
  splitter: RegExp,
  parseOne: (s: string) => Syllable | null,
  want: number,
  maxLen: number,
): Syllable[] | null {
  const chunks = text.split(splitter).filter(Boolean);
  if (chunks.length === 0) return null;
  const options = chunks.map((c) => segmentOptions(c, parseOne, maxLen));
  if (options.some((o) => o.size === 0)) return null;
  const counts = options.map((o) => [...o.keys()].sort((a, b) => a - b));
  // reach[i] = i 番目以降の塊で作れる合計の集合。
  const reach: Set<number>[] = Array.from({ length: chunks.length + 1 }, () => new Set());
  reach[chunks.length].add(0);
  for (let i = chunks.length - 1; i >= 0; i--) {
    for (const c of counts[i]) for (const r of reach[i + 1]) reach[i].add(c + r);
  }
  const out: Syllable[] = [];
  if (want > 0 && reach[0].has(want)) {
    let left = want;
    for (let i = 0; i < chunks.length; i++) {
      const c = counts[i].find((n) => reach[i + 1].has(left - n))!;
      out.push(...options[i].get(c)!);
      left -= c;
    }
    return out;
  }
  for (let i = 0; i < chunks.length; i++) out.push(...options[i].get(counts[i][0])!);
  return out;
}

/**
 * 拼音の読みを音節に分ける（「ná tiě」「na2 tie3」「nálǎtiě」も読む）。
 * `want` は期待する音節数（分かち書きが曖昧なときの手がかり）。
 */
export function parsePinyin(text: string, want = 0): Syllable[] | null {
  const t = (text ?? "").trim();
  if (!t) return null;
  // 声調記号の付いた母音は NFC で1文字。1音節は数字の声調つきで最大 7 文字（zhuang4）。
  return splitReading(t.normalize("NFC"), /[\s'’\-·・,，]+/u, parsePinyinSyllable, want, 7);
}

/** 注音の読みを音節に分ける（空白なしで続けて書かれた物も読む）。 */
export function parseZhuyin(text: string, want = 0): Syllable[] | null {
  const t = (text ?? "").trim();
  if (!t) return null;
  return splitReading(t, /[\s,，、]+/u, parseZhuyinSyllable, want, 5);
}

/** 音節の列 → 空白区切りの注音。 */
export function syllablesToZhuyin(list: readonly Syllable[]): string | null {
  const parts = list.map(syllableToZhuyin);
  return parts.every((p): p is string => p !== null) ? parts.join(" ") : null;
}

/** 音節の列 → 空白区切りの拼音（声調記号つき）。 */
export function syllablesToPinyin(list: readonly Syllable[]): string {
  return list.map(formatPinyin).join(" ");
}

/** 拼音の読み → 空白区切りの注音。読めなければ `null`。 */
export function pinyinToZhuyin(text: string): string | null {
  const list = parsePinyin(text);
  return list ? syllablesToZhuyin(list) : null;
}

export function sameSyllables(a: readonly Syllable[], b: readonly Syllable[]): boolean {
  return a.length === b.length && a.every((s, i) => s.base === b[i].base && s.tone === b[i].tone);
}
