import { z } from "zod";
import { readerText } from "./note-language";
import { targetProfile } from "./target-profile";

/**
 * **語源・部首の図**（オーナー依頼 2026-10-15。iOS が Web と同じ形の図を描く）:
 *
 *   [曖 / 日+愛 / 日がかげる] + [昧 / 日+未 / 夜明け前] = [曖昧 / はっきり見えない]
 *
 * Web の語源の節は文章（`etymology`）・仲間の語（`etymology_relatives`）・部首の1行（`radicals`、文字列）だけで、
 * 図に描ける**形のある欄が無かった**。ここで1つ足す（`extras.etymology_diagram`）。
 *
 * - `kind` — compound（字・語根の組み合わせで説明できる）/ single_char（1字の語）/
 *   loanword_phonetic（外国語の音を写した外来語: 沙發←sofa・咖啡←coffee）/ proper（商品名・店名などの固有名詞）/
 *   other（どれでもない・成り立ちが確かでない）。
 * - `parts` — 図の左の箱。compound は2つ以上（字の順。台湾華語はつなぐと見出し語）、single_char は1つ。
 *   各 {text: 字（英語は語根・接頭辞）, components: 部品の字（英語は空）, meaning: この語でのその字の意味}。
 * - `result_meaning` — 図の右の箱の意味（組み合わせた意味）。
 * - `source` — 外来語の元の語（loanword_phonetic のときだけ。例 "sofa"）。
 * - `note` — 短い1文の説明。**compound 以外は必ず入る**（図の代わりに出す文）。
 *
 * **空・壊れた図を返さない**: 形が崩れていれば `other` に落とし、`note` を語源の文章か決まった一言で埋める
 * （`normalizeEtymologyDiagram`）。
 */

export const ETYMOLOGY_KINDS = [
  "compound",
  "single_char",
  "loanword_phonetic",
  "proper",
  "other",
] as const;
export type EtymologyKind = (typeof ETYMOLOGY_KINDS)[number];

export const EtymologyPartSchema = z.object({
  text: z.string().catch(""),
  components: z.array(z.string()).catch([]).default([]),
  meaning: z.string().catch(""),
});

export const EtymologyDiagramSchema = z.object({
  kind: z.enum(ETYMOLOGY_KINDS).catch("other"),
  parts: z.array(EtymologyPartSchema).catch([]).default([]),
  result_meaning: z.string().catch("").default(""),
  source: z.string().catch("").default(""),
  note: z.string().catch("").default(""),
});
export type EtymologyDiagram = z.infer<typeof EtymologyDiagramSchema>;

/** 読む人の言語ごとの長さの上限（字数。英語は文字数）。 */
function caps(readerLang: string) {
  const l = readerLang.toLowerCase();
  if (l.startsWith("en")) return { meaning: 40, note: 140 };
  if (l.startsWith("zh")) return { meaning: 12, note: 50 };
  return { meaning: 14, note: 60 };
}

function cut(text: string, max: number): string {
  const chars = [...text.replace(/\s+/g, " ").trim()];
  return chars.length <= max ? chars.join("") : chars.slice(0, max).join("").trim();
}

/** 文章の最初の1文（語源の文章を、図の代わりの一言にする時）。 */
function firstSentence(text: string): string {
  const t = (text ?? "").replace(/\s+/g, " ").trim();
  const m = t.match(/^(.+?(?:[。．！？]|[.!?](?=\s|$)))/u);
  return (m ? m[1] : t).trim();
}

/** 図が作れない時の決まった一言（読む人の言語）。 */
function fallbackNote(kind: EtymologyKind, headword: string, source: string, readerLang: string) {
  const l = readerLang.toLowerCase();
  const en = l.startsWith("en");
  const zh = l.startsWith("zh");
  switch (kind) {
    case "loanword_phonetic":
      if (source)
        return en
          ? `A sound loan from "${source}".`
          : zh
            ? `音譯自「${source}」。`
            : `「${source}」の音を写した外来語。`;
      return en
        ? "A sound loan from another language."
        : zh
          ? "外來語的音譯。"
          : "外国語の音を写した外来語。";
    case "proper":
      return en
        ? "A proper noun (a brand or a name)."
        : zh
          ? "專有名詞（品牌或名稱）。"
          : "商品名・店名などの固有名詞。";
    case "single_char":
      return en
        ? `"${headword}" is a single character.`
        : zh
          ? `「${headword}」是單一個字。`
          : `「${headword}」は1字の語。`;
    default:
      return en
        ? `Learn "${headword}" as one word.`
        : zh
          ? `「${headword}」整個詞一起記。`
          : `「${headword}」は分けずに一語で覚える言葉。`;
  }
}

const HAN = /\p{Script=Han}/u;

/**
 * AI の返した図を確かめて、**必ず描ける図**にして返す（AI は呼ばない）。
 *
 * - compound: 字・語根が2つ以上。台湾華語（漢字の言語）は、つなぐと見出し語になること。部品は漢字だけ。
 *   満たさなければ other に落とす。組み合わせの意味が無ければ、カードの意味で埋める。
 * - single_char: 漢字の言語は見出し語が1字の時だけ（そうでなければ other）。
 * - loanword_phonetic / proper / other: 図の箱は使わない（`parts` は空）。`note` を必ず埋める。
 * - 意味・説明は読む人の言語でない物を落とし、長さの上限まで短くする。
 */
export function normalizeEtymologyDiagram(
  raw: unknown,
  ctx: {
    headword: string;
    language: string;
    readerLang: string;
    meaning?: string;
    etymology?: string;
  },
): EtymologyDiagram {
  const parsed = EtymologyDiagramSchema.safeParse(raw ?? {});
  const d: EtymologyDiagram = parsed.success
    ? parsed.data
    : { kind: "other", parts: [], result_meaning: "", source: "", note: "" };
  const head = (ctx.headword ?? "").trim();
  const hanWord = targetProfile(ctx.language).scriptLang === "zh-Hant";
  const cap = caps(ctx.readerLang);
  const reader = (t: string, max: number) => cut(readerText((t ?? "").trim(), ctx.readerLang), max);

  const parts = d.parts
    .map((p) => ({
      text: (p.text ?? "").trim(),
      components: (p.components ?? [])
        .map((c) => (c ?? "").trim())
        .filter((c) => c && (!hanWord || HAN.test(c))),
      meaning: reader(p.meaning, cap.meaning),
    }))
    .filter((p) => p.text);
  let kind: EtymologyKind = d.kind;
  if (kind === "compound") {
    const joins = !hanWord || parts.map((p) => p.text).join("") === head;
    if (parts.length < 2 || !joins) kind = "other";
  }
  if (kind === "single_char") {
    if (hanWord && [...head].length !== 1) kind = "other";
  }
  const source = cut((d.source ?? "").trim(), 40);
  let note = reader(d.note, cap.note);
  if (!note && kind !== "compound" && kind !== "single_char") {
    const fromProse = reader(firstSentence(ctx.etymology ?? ""), cap.note);
    note = (kind === "other" && fromProse) || fallbackNote(kind, head, source, ctx.readerLang);
  }
  if (kind === "compound") {
    return {
      kind,
      parts,
      result_meaning:
        reader(d.result_meaning, cap.meaning) || reader(ctx.meaning ?? "", cap.meaning),
      source: "",
      note,
    };
  }
  if (kind === "single_char") {
    const one = parts[0] ?? { text: head, components: [], meaning: "" };
    const piece = { ...one, text: hanWord ? head : one.text || head };
    return {
      kind,
      parts: [piece],
      result_meaning:
        reader(d.result_meaning, cap.meaning) || reader(ctx.meaning ?? "", cap.meaning),
      source: "",
      note: note || (!piece.meaning ? fallbackNote(kind, head, "", ctx.readerLang) : ""),
    };
  }
  return {
    kind,
    parts: [],
    result_meaning: reader(d.result_meaning, cap.meaning),
    source: kind === "loanword_phonetic" ? source : "",
    note,
  };
}

/** 指示文の1行（カード生成と語源の作り直しで同じ文）。 */
export function etymologyDiagramRule(language: string, nl: string): string {
  const hanWord = targetProfile(language).scriptLang === "zh-Hant";
  const unit = hanWord ? "字" : "語根・接頭辞・接尾辞";
  return [
    `- etymology_diagram: 語源の**図**（画面で [${unit} / 部品+部品 / 意味] + [...] = [語 / 意味] と描く）。kind を1つ:`,
    `  compound（2つ以上の${unit}の組み合わせで意味が説明できる語）/ single_char（1字の語）/`,
    `  loanword_phonetic（外国語の音を写した外来語。例: 沙發←sofa・咖啡←coffee）/ proper（商品名・ブランド・店名・人名などの固有名詞）/`,
    `  other（どれにも当てはまらない・成り立ちが確かでない）。`,
    `  形: {kind, parts:[{text: ${unit}, components: ${hanWord ? 'その字の部品の字（例 曖 → ["日","愛"]）' : "空配列"}, meaning: その${unit}がこの語で持つ意味(${nl}で短く)}],` +
      ` result_meaning: 組み合わせた意味(${nl}で短く), source: 外来語の元の語(loanword_phonetic のときだけ。例 "sofa"), note: 短い1文の説明(${nl})}`,
    `  compound は parts を${hanWord ? "字の順に並べ、つなぐと見出し語になること" : "語の順に並べる"}。single_char は parts を1つ。` +
      `loanword_phonetic・proper・other は parts を空配列にして、**note を必ず書く**。`,
    `  **分解を作らない** — 確かでなければ other にして note に書く（例: 曖昧 → compound [曖/日+愛/日がかげる] + [昧/日+未/夜明け前] = はっきり見えない）。`,
  ].join("\n");
}
