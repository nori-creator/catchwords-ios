import { z } from "zod";
import { ChunkPartSchema, type ChunkPart } from "./chunk-part";
import { allowsSimplePartners, isWeakPartnerChunk } from "./generic-chunks";
import { looksWrongForReader } from "./note-language";
import { headwordCore } from "./target-profile";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **使い方チャンク v2 — 形だけを見る純粋な部分**（オーナー 2026-10-30「今までのチャンクのプロンプトや指示は
 * 全てを忘れて…1から設計し直して」。設計は `docs/chunk-rules.md` の v2 の節）。
 *
 * チャンク = その名詞を使ってネイティブが実際に口にする一文の中の、名詞を含む最小の「そのまま言える塊」。
 * - 2 社の AI に同じ指示で独立に書かせ、**型（入れ替えの所を ＿ にした字）が一致した物を正解**にする
 *   （`mergeByAgreement`）。片方だけの物は、もう片方の会社に自然さと頻度を聞く（`applyJudge`）。
 * - ここは**自然さを判定しない**。見る物は形だけ: 見出し語が入っているか、文の部分文字列か、句読点が無いか、
 *   入れ替えは 1 か所以内か、重複、訳の言語（`gateChunksV2`）。v1 の門にあった汎用・弱い相手・意味の衝突・
 *   禁止一覧・分割・echo の判定は持ち込まない（禁止を足すたびに正しい形を巻き添えにしてきた）。
 * - 見出し語は決して入れ替えない（オーナー: 入れ替えたら解説の意味が無い）。
 *
 * 外の世界に触れない（AI・DB は `chunks-v2.server.ts`）。試験は `chunks-v2.test.ts`。
 */

/**
 * **名詞の役割で分けた型**（2026-10-30 夜、オーナー「本当にこれで全部網羅できる？」で見直した）。
 *
 * 前の 10 種（動詞＋名詞・把…・用…・名詞＋了…）は「よく出る形」の寄せ集めで、介詞が 用・在・把 しか無く、方位の語が 裡 だけ、
 * 名詞が主語になる動作（蚊子咬我）や 跟/給/從 の句が入らなかった。**文の中で名詞が置かれ得る場所は文法で決まっている**ので、
 * その役割で分ける: 名詞は ①動詞の目的語 ②述語の主語・話題 ③介詞（在/到/從/用/跟/給/把/被…）の目的語 ④修飾される側
 * ⑤別の名詞を修飾する側 ⑥方位の語を付けた場所 のどれかに立つか、⑦決まった言い回しの中にある。それでも当てはまらない物は
 * ⑧その他（捨てない — 型は AI に「名詞が立てる場所」を全部思い出させるための物で、門ではない。合否は 2 社の一致が決める）。
 * 画面には出さない。
 */
export const CHUNK_PATTERNS = [
  "object", // ① 動詞の目的語: V＋N（V了/過＋N、V＋一下＋N、V＋補語＋N も）: 吹電風扇 / 買到票
  "subject", // ② 主語・話題: N＋V了 / N＋被V了 / N＋很＋Adj / N＋比＋N＋Adj / N＋V＋O: 手機沒電了 / 湯很燙 / 蚊子咬我
  "coverb", // ③ 介詞の目的語: 在/到/從/往・用/拿・跟/和・給/對/幫/替・把・被 ＋N（＋方位）＋V: 用吸管喝 / 跟朋友吃飯 / 把衣服放進洗衣機裡
  "modified", // ④ 修飾される: Adj(的)＋N / V(的)＋N / N(的)＋N: 冰的紅茶 / 剛買的手機 / 台灣的芒果
  "modifier", // ⑤ 別の名詞を修飾: N的N / N＋N / N＋和＋N: 雨傘的把手 / 手機殼 / 筷子和湯匙
  "locative", // ⑥ 場所化: N＋裡/裡面/上/上面/下/底下/外/外面/中/旁邊/前面/後面 を含む句: 放在桌上 / 冰箱裡的牛奶
  "set_phrase", // ⑦ 決まった言い回し: 注文・依頼・質問・感嘆: 紅茶半糖少冰 / 幫我拿一下遙控器 / 有沒有衛生紙
  "other", // ⑧ 上のどれでもないが、ネイティブが塊として言う物
] as const;
export type ChunkPattern = (typeof CHUNK_PATTERNS)[number];

export function isChunkPattern(v: unknown): v is ChunkPattern {
  return typeof v === "string" && (CHUNK_PATTERNS as readonly string[]).includes(v);
}

/** 塊の中の見出し語の場所（どの block の、何字目から何字）。画面は字の範囲で青く塗る。 */
export const ChunkHeadSchema = z.object({
  block: z.number().int().min(0),
  start: z.number().int().min(0),
  length: z.number().int().min(1),
});
export type ChunkHead = z.infer<typeof ChunkHeadSchema>;

/**
 * 保存する形（`extras.usage_chunks_v2`、書庫 `chunk_library`）。block は v1 の `ChunkPart` と同じ形（iOS の
 * 表示の部品を使い回す）。`text` は block の字をつないだ物。`sentence` はその塊を切り出した文（例文として出す）。
 */
export const UsageChunkV2Schema = z.object({
  text: z.string(),
  blocks: z.array(ChunkPartSchema).catch([]),
  head: ChunkHeadSchema.nullable().catch(null),
  pattern: z.string().catch(""),
  /** 塊の訳（読む人の言語）。欄の名前は v1 と同じ `ja`。 */
  ja: z.string().catch(""),
  note: z.string().optional().catch(undefined),
  sentence: z.string().catch(""),
  sentence_ja: z.string().catch(""),
  /** 審査の頻度（1〜5）。一致で決まった物は null のことがある。 */
  frequency: z.number().int().min(1).max(5).nullable().catch(null),
  /** どう決まったか: 2 社の一致 / 片方だけで審査に通った。 */
  by: z.enum(["agreement", "judge"]).optional().catch(undefined),
});
export type UsageChunkV2 = z.infer<typeof UsageChunkV2Schema>;

/** AI が返す 1 つ（寛容に読む。無い欄・違う型は既定値に）。 */
export const AiChunkV2Schema = z.object({
  sentence: z.string().catch(""),
  sentence_ja: z.string().catch(""),
  text: z.string().catch(""),
  blocks: z.array(ChunkPartSchema).catch([]),
  pattern: z.string().catch(""),
  ja: z.string().catch(""),
  note: z.string().catch(""),
});
export type AiChunkV2 = z.infer<typeof AiChunkV2Schema>;

export const AiChunksReplySchema = z.object({
  chunks: z.array(z.unknown()).catch([]),
});

/** 審査の返事。`i` は 1 から。 */
export const JudgeReplySchema = z.object({
  verdicts: z.array(z.unknown()).catch([]),
});
export type JudgeVerdict = { i: number; natural: boolean; frequency: number | null };

/** 審査で合格とする頻度の下限（5 = 真っ先に出る、3 = よく言う、1 = まれ）。 */
export const JUDGE_MIN_FREQUENCY = 3;
/** 画面に出す数の上限。 */
export const CHUNKS_V2_MAX = 4;
/** 文の長さの上限（句読点を除いた字数。画面で注音付きでも 2 行に入る長さ、`EXAMPLE_MAX_HAN` と同じ）。 */
export const CHUNK_SENTENCE_MAX = 24;

export type ChunkV2DropReason =
  | "empty"
  | "headword_missing"
  | "headword_only"
  | "no_sentence"
  | "not_in_sentence"
  | "sentence_long"
  | "punctuation"
  | "two_slots"
  | "duplicate"
  | "translation_language";

export type ChunkV2GateResult = {
  kept: UsageChunkV2[];
  dropped: Array<{ text: string; reason: ChunkV2DropReason }>;
};

export type ChunkV2GateContext = {
  headword: string;
  language: string | null | undefined;
  /** 読む人の言語（訳の言語を確かめる）。無ければ確かめない。 */
  readerLang?: string | null;
};

const SENTENCE_PUNCT = /[，。！？；：、,.!?;:…]/u;
const HAN = /\p{Script=Han}/u;

/** 字を比べる形（空白を落とす）。 */
export function squash(text: string | null | undefined): string {
  return (text ?? "").replace(/\s+/gu, "");
}

/** 読む人の言語が学ぶ言語と同じか（繁體中文で台湾華語を読む人の訳は空でよい）。 */
function readerIsTarget(readerLang: string | null | undefined, language: string | null | undefined): boolean {
  const r = (readerLang ?? "").toLowerCase();
  const t = normalizeTargetLanguage(language).toLowerCase();
  if (!r) return false;
  return r.startsWith("zh") ? t.startsWith("zh") : r === t;
}

/** 句読点を除いた字数。 */
export function sentenceLength(sentence: string): number {
  return [...squash(sentence).replace(/[，。！？；：、,.!?;:…「」『』（）()\s]/gu, "")].length;
}

/**
 * 塊の中の見出し語の場所。見出し語の字を**含む block** を探し、その中の字の位置を返す（筆袋裡 の中の 筆袋）。
 * 見出し語が 2 つの block にまたがる（AI が 1 語を割った）時は null。
 */
export function headPlace(blocks: ReadonlyArray<ChunkPart>, headword: string): ChunkHead | null {
  const core = headwordCore(headword);
  if (!core) return null;
  for (let i = 0; i < blocks.length; i++) {
    const text = squash(blocks[i]?.text);
    const at = text.indexOf(core);
    if (at >= 0) return { block: i, start: [...text.slice(0, at)].length, length: [...core].length };
  }
  return null;
}

/** 型の字: 入れ替えの所を ＿ に置き換えて block をつないだ物（2 社の返事を比べる鍵）。 */
export function frameKey(chunk: { blocks?: ReadonlyArray<ChunkPart> | null; text?: string | null }): string {
  const blocks = chunk.blocks ?? [];
  if (blocks.length === 0) return squash(chunk.text);
  return blocks.map((b) => (b.slot ? "＿" : squash(b.text))).join("");
}

/** block を整える: 字を詰め、空の block を外し、見出し語の block と候補の無い block の slot を外す。 */
function tidyBlocks(raw: ReadonlyArray<ChunkPart>, headword: string): ChunkPart[] {
  const core = headwordCore(headword);
  const out: ChunkPart[] = [];
  for (const b of raw) {
    const text = squash(b.text);
    if (!text) continue;
    const alts = (b.alts ?? [])
      .map((a) => ({ ...a, text: squash(a.text) }))
      .filter((a) => a.text && a.text !== text)
      .slice(0, 6);
    const containsHead = !!core && text.includes(core);
    const slot = b.slot === true && !containsHead && alts.length >= 2;
    const next: ChunkPart = { ...b, text };
    if (slot) {
      next.slot = true;
      next.alts = alts;
    } else {
      delete next.slot;
      delete next.alts;
    }
    out.push(next);
  }
  return out;
}

/**
 * **形だけの門。** 1 つずつ確かめ、通った物（保存する形）と落とした物（理由つき）を返す。順番は返ってきた順。
 */
export function gateChunksV2(
  raw: ReadonlyArray<unknown> | null | undefined,
  ctx: ChunkV2GateContext,
): ChunkV2GateResult {
  const head = headwordCore(ctx.headword);
  const checkReader = !!ctx.readerLang && !readerIsTarget(ctx.readerLang, ctx.language);
  const kept: UsageChunkV2[] = [];
  const dropped: ChunkV2GateResult["dropped"] = [];
  const seen = new Set<string>();

  for (const item of raw ?? []) {
    const parsed = AiChunkV2Schema.safeParse(item);
    if (!parsed.success) continue;
    const c = parsed.data;
    let blocks = tidyBlocks(c.blocks, ctx.headword);
    // block が無い返事（text だけ）は 1 つの block として読む。
    if (blocks.length === 0 && squash(c.text)) blocks = [{ text: squash(c.text), pos: "" }];
    const text = blocks.map((b) => b.text).join("");
    const drop = (reason: ChunkV2DropReason) => dropped.push({ text: text || squash(c.text), reason });

    if (!text) {
      drop("empty");
      continue;
    }
    if (!head || !text.includes(head)) {
      drop("headword_missing");
      continue;
    }
    if (text === head) {
      drop("headword_only");
      continue;
    }
    if (SENTENCE_PUNCT.test(text)) {
      drop("punctuation");
      continue;
    }
    const sentence = squash(c.sentence);
    if (!sentence) {
      drop("no_sentence");
      continue;
    }
    if (!sentence.includes(text)) {
      drop("not_in_sentence");
      continue;
    }
    if (sentenceLength(sentence) > CHUNK_SENTENCE_MAX) {
      drop("sentence_long");
      continue;
    }
    if (blocks.filter((b) => b.slot).length > 1) {
      drop("two_slots");
      continue;
    }
    const ja = c.ja.trim();
    const sentenceJa = c.sentence_ja.trim();
    if (checkReader) {
      if (!ja || looksWrongForReader(ja, ctx.readerLang, text) || (sentenceJa && looksWrongForReader(sentenceJa, ctx.readerLang, sentence))) {
        drop("translation_language");
        continue;
      }
    }
    const key = frameKey({ blocks });
    if (seen.has(key) || seen.has(text)) {
      drop("duplicate");
      continue;
    }
    seen.add(key);
    seen.add(text);
    const note = c.note.trim();
    kept.push({
      text,
      blocks,
      head: headPlace(blocks, ctx.headword),
      pattern: isChunkPattern(c.pattern) ? c.pattern : "",
      ja,
      ...(note && !(checkReader && looksWrongForReader(note, ctx.readerLang, text)) ? { note } : {}),
      sentence: c.sentence.trim(),
      sentence_ja: sentenceJa,
      frequency: null,
    });
  }
  return { kept, dropped };
}

export type AgreementResult = {
  /** 両方が出した型（A の物を採る。順は A・B の順位の平均）。 */
  agreed: UsageChunkV2[];
  /** A だけが出した物（B の会社に審査してもらう）。 */
  onlyA: UsageChunkV2[];
  /** B だけが出した物（A の会社に審査してもらう）。 */
  onlyB: UsageChunkV2[];
};

/**
 * **2 社の返事を型で照合する。** 同じ型（＿ を含めて同じ字）が両方に在れば一致。片方の型がもう片方の型を
 * 字として含む時も一致とみなし、**長い方**を採る（放進筆袋裡 ⊂ 把＿放進筆袋裡 — 短い方は長い方の切れ端）。
 */
export function mergeByAgreement(a: ReadonlyArray<UsageChunkV2>, b: ReadonlyArray<UsageChunkV2>): AgreementResult {
  const usedB = new Set<number>();
  const agreed: Array<{ chunk: UsageChunkV2; rank: number }> = [];
  const onlyA: UsageChunkV2[] = [];
  const bare = (c: UsageChunkV2) => frameKey(c).replace(/＿/gu, "");
  a.forEach((ca, ia) => {
    const ka = frameKey(ca);
    let hit = -1;
    // 1. 同じ型。
    for (let ib = 0; ib < b.length; ib++) {
      if (!usedB.has(ib) && frameKey(b[ib]) === ka) {
        hit = ib;
        break;
      }
    }
    // 2. 片方がもう片方を含む（＿ を抜いた字で）。
    if (hit < 0) {
      const ba = bare(ca);
      for (let ib = 0; ib < b.length; ib++) {
        if (usedB.has(ib)) continue;
        const bb = bare(b[ib]);
        if (ba.includes(bb) || bb.includes(ba)) {
          hit = ib;
          break;
        }
      }
    }
    if (hit < 0) {
      onlyA.push(ca);
      return;
    }
    usedB.add(hit);
    const cb = b[hit];
    const longer = [...bare(cb)].length > [...bare(ca)].length ? cb : ca;
    agreed.push({ chunk: { ...longer, by: "agreement" }, rank: (ia + hit) / 2 });
  });
  agreed.sort((x, y) => x.rank - y.rank);
  const onlyB = b.filter((_, ib) => !usedB.has(ib));
  return { agreed: agreed.map((x) => x.chunk), onlyA, onlyB };
}

/** 審査の返事を読む（`i` は 1 から。文字列の true/false・数字も読む。読めない物は無視）。 */
export function readJudgeVerdicts(raw: unknown, count: number): JudgeVerdict[] {
  const parsed = JudgeReplySchema.safeParse(raw);
  if (!parsed.success) return [];
  const out: JudgeVerdict[] = [];
  parsed.data.verdicts.forEach((v, at) => {
    if (!v || typeof v !== "object") return;
    const o = v as Record<string, unknown>;
    const iRaw = o.i ?? o.index ?? at + 1;
    const i = typeof iRaw === "number" ? iRaw : Number.parseInt(String(iRaw), 10);
    if (!Number.isInteger(i) || i < 1 || i > count) return;
    const n = o.natural;
    const natural = n === true || (typeof n === "string" && /^(true|yes|是|はい)$/iu.test(n.trim()));
    const fRaw = o.frequency;
    const f = typeof fRaw === "number" ? fRaw : Number.parseInt(String(fRaw ?? ""), 10);
    const frequency = Number.isInteger(f) && f >= 1 && f <= 5 ? f : null;
    out.push({ i, natural, frequency });
  });
  return out;
}

/** 片方だけの型に審査の答えを当て、合格した物だけ（頻度の高い順）。 */
export function applyJudge(
  pending: ReadonlyArray<UsageChunkV2>,
  verdicts: ReadonlyArray<JudgeVerdict>,
  minFrequency = JUDGE_MIN_FREQUENCY,
): UsageChunkV2[] {
  const byIndex = new Map(verdicts.map((v) => [v.i, v]));
  const out: Array<{ chunk: UsageChunkV2; f: number }> = [];
  pending.forEach((c, at) => {
    const v = byIndex.get(at + 1);
    if (!v || !v.natural || v.frequency == null || v.frequency < minFrequency) return;
    out.push({ chunk: { ...c, frequency: v.frequency, by: "judge" }, f: v.frequency });
  });
  out.sort((x, y) => y.f - x.f);
  return out.map((x) => x.chunk);
}

/** 最後の並び: 一致した物 → 審査に通った物。型の重複を落とし、上限まで。 */
export function finalChunks(
  agreed: ReadonlyArray<UsageChunkV2>,
  judged: ReadonlyArray<UsageChunkV2>,
  max = CHUNKS_V2_MAX,
): UsageChunkV2[] {
  const out: UsageChunkV2[] = [];
  const seen = new Set<string>();
  for (const c of [...agreed, ...judged]) {
    const k = frameKey(c);
    if (seen.has(k) || seen.has(c.text)) continue;
    seen.add(k);
    seen.add(c.text);
    out.push(c);
    if (out.length >= max) break;
  }
  return out;
}

/**
 * **読む人の目標レベルで並べ替える**（書庫の中国語は帯に依らない。オーナー 2026-10-26「吃＋小籠包 のような簡単な
 * 動詞の型は目標 1・2 級の人には出してよい」— 3 級以上の人には、汎用の動詞だけの塊を他に 2 つ以上あれば外し、
 * 無ければ最後へ）。
 */
export function orderForReader(
  chunks: ReadonlyArray<UsageChunkV2>,
  opts: { levelGoal: string | null | undefined; headword: string; language: string | null | undefined },
): UsageChunkV2[] {
  if (allowsSimplePartners(opts.levelGoal)) return [...chunks];
  const weak = chunks.map((c) => isWeakPartnerChunk(c.blocks, opts.headword, opts.language));
  const strong = chunks.filter((_, i) => !weak[i]);
  if (strong.length >= 2) return strong;
  return [...strong, ...chunks.filter((_, i) => weak[i])];
}

/**
 * 1 行に入るかの見積もり（iOS の `ChunkLineView` は 1 → 0.52 倍まで縮めて 1 行に収める。最小でも入らない塊は
 * 出さない）。字の幅: 漢字 = 文字の大きさ、英数 = 0.55 倍。`widthPt` は塊に使える横幅、`fontPt` は等倍の字の大きさ。
 */
export function fitsOneLine(
  text: string,
  opts: { widthPt: number; fontPt?: number; minScale?: number; gapPt?: number },
): boolean {
  const font = opts.fontPt ?? 22;
  const min = opts.minScale ?? 0.52;
  let w = 0;
  for (const ch of squash(text)) w += HAN.test(ch) ? font : font * 0.55;
  return w * min + (opts.gapPt ?? 0) <= opts.widthPt;
}

/** 記録用の一行（語・残した数・落とした理由）。語の中身は入れない。 */
export function describeChunkV2Gate(result: ChunkV2GateResult): string {
  const counts = new Map<string, number>();
  for (const d of result.dropped) counts.set(d.reason, (counts.get(d.reason) ?? 0) + 1);
  const reasons = [...counts.entries()].map(([k, n]) => `${k}:${n}`).join(" ");
  return `kept=${result.kept.length} dropped=${result.dropped.length}${reasons ? ` (${reasons})` : ""}`;
}
