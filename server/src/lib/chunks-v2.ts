import { z } from "zod";
import { ChunkPartSchema, type ChunkPart } from "./chunk-part";
import { allowsSimplePartners, isWeakPartnerChunk } from "./generic-chunks";
import { looksWrongForReader } from "./note-language";
import { headwordCore } from "./target-profile";
import { normalizeTargetLanguage, TARGET_LANGUAGES } from "./target-lang";

/**
 * **使い方チャンク v2 — 形だけを見る純粋な部分**（オーナー 2026-10-30「今までのチャンクのプロンプトや指示は
 * 全てを忘れて…1から設計し直して」。設計は `docs/chunk-rules.md` の v2 の節）。
 *
 * チャンク = その名詞を使ってネイティブが実際に口にする一文の中の、名詞を含む最小の「そのまま言える塊」。
 * - 2 社の AI に同じ指示で独立に書かせ、**同じ言い方（同じ型・含む関係・同じ中心の語）を書いた物を一致**とする
 *   （`mergeByAgreement`）。候補は全部 2 社の審査に出し、逆の会社の「自然」で決める（`rankAndSelect`）。残った塊にだけ
 *   block・品詞・訳を付ける（`finishCandidate`）。
 * - ここは**自然さを判定しない**。見る物は形だけ: 見出し語が入っているか、文の部分文字列か、句読点が無いか、
 *   見出し語の直前が量詞でないか、入れ替えの所が名詞で候補があるか、重複（`gateChunksV2`）。v1 の門にあった汎用・弱い相手・意味の衝突・
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
/**
 * **書く段の返事 1 つ**（中国語だけ・軽い形。2026-10-30 の 3 回目の採点で、block・品詞・候補の訳まで一度に書かせると
 * 1 語 30〜40 秒かかったので、書く段は文・塊・中心の語・型・入れ替えだけにし、block と訳は残った塊にだけ付ける）。
 * - `key` = 見出し語と組になる中心の語（動詞・形容詞・名詞のどれか 1 つ。帶・撐・半糖去冰）。**2 社の一致と重複の鍵**
 *   （関掉電風扇 と 把電風扇關掉 は同じ key → 同じ言い方）。
 * - `slot` = 別の名詞に入れ替えてもよく言う所の字（塊の中の部分文字列）。`alts` はそこに入る別の名詞。
 */
export const AiChunkV2Schema = z.object({
  sentence: z.string().catch(""),
  text: z.string().catch(""),
  key: z.string().catch(""),
  pattern: z.string().catch(""),
  slot: z.string().nullable().catch(null),
  alts: z.array(z.unknown()).catch([]),
});
export type AiChunkV2 = z.infer<typeof AiChunkV2Schema>;

export const AiChunksReplySchema = z.object({
  chunks: z.array(z.unknown()).catch([]),
});

/** 門を通った候補（中国語だけ。block・訳はまだ無い）。 */
export type ChunkCandidate = {
  text: string;
  sentence: string;
  key: string;
  pattern: string;
  slot: string | null;
  alts: string[];
};

/** 審査と並べ替えの返事。`i` は 1 から、`rank` は自然な物の中での順位（1 = いちばんよく言う）。 */
export const JudgeReplySchema = z.object({
  verdicts: z.array(z.unknown()).catch([]),
});
/** `same` = 同じ言い方だと審査が言った別の候補の番号（語順や補語が違うだけ: 把雨衣穿起來 と 把雨衣穿上）。 */
export type JudgeRank = { i: number; natural: boolean; rank: number | null; same?: number | null };

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
  | "measure_phrase"
  | "duplicate";

export type ChunkV2GateResult = {
  kept: ChunkCandidate[];
  dropped: Array<{ text: string; reason: ChunkV2DropReason }>;
};

export type ChunkV2GateContext = {
  headword: string;
  language: string | null | undefined;
};

const SENTENCE_PUNCT = /[，。！？；：、,.!?;:…]/u;
const HAN = /\p{Script=Han}/u;
/** 数・指示の語＋量詞（見出し語の直前にあれば量詞の型 — 量詞は別の欄）。 */
const MEASURE_BEFORE =
  /[一二兩三四五六七八九十幾這那每哪][個把杯件支條張本雙台隻瓶盒包顆塊碗盤罐袋套輛間頂面副串片份碟束桶盞根粒]$/u;
/** 入れ替えの所にできない語（名詞でない）。 */
const PRONOUNS = new Set(["我", "你", "妳", "他", "她", "它", "我們", "你們", "妳們", "他們", "她們", "大家", "自己", "誰", "這", "那", "這個", "那個", "這裡", "那裡", "這邊", "那邊"]);

/** 字を詰める（空白を除く）。 */
export function squash(text: string | null | undefined): string {
  return (text ?? "").replace(/\s+/gu, "");
}

/**
 * 読む人の言語が学ぶ言語と同じ（繁體中文で台湾華語を読む → 訳は要らない）。
 * **`normalizeTargetLanguage` に読む人の言語を渡さない**: 知らない言語（es・ko・vi）を既定の zh-TW に落とすので、
 * スペイン語・韓国語・ベトナム語の読者が「訳は要らない」扱いになっていた（2026-10-30 の事前投入で発覚）。
 */
export function readerIsTarget(readerLang: string | null | undefined, language: string | null | undefined): boolean {
  const r = (readerLang ?? "").trim();
  if (!(TARGET_LANGUAGES as readonly string[]).includes(r)) return false;
  return r === normalizeTargetLanguage(language ?? "");
}

/** 句読点を除いた字数。 */
export function sentenceLength(sentence: string): number {
  return [...squash(sentence).replace(new RegExp(SENTENCE_PUNCT.source, "gu"), "")].length;
}

/**
 * 見出し語がどの block の何字目から何字にあるか（画面はこの範囲だけ青く塗る）。block をまたいで割れている時は null。
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

/**
 * 型の字: 入れ替えの所を ＿ に置き換えた塊の字（2 社の返事を比べる鍵の 1 つ）。候補（`slot` の字）と保存した塊（slot の
 * block）のどちらでも作れる。
 */
export function frameKey(chunk: { text?: string | null; slot?: string | null; blocks?: ReadonlyArray<ChunkPart> | null }): string {
  if (typeof chunk.slot === "string" && chunk.slot) {
    const text = squash(chunk.text);
    return text.includes(chunk.slot) ? text.replace(chunk.slot, "＿") : text;
  }
  const blocks = chunk.blocks ?? [];
  if (blocks.length === 0) return squash(chunk.text);
  return blocks.map((b) => (b.slot ? "＿" : squash(b.text))).join("");
}

/** 中心の語の鍵: 了/過/著・一下 を除いた字。無ければ型の字。 */
export function coreKey(chunk: { key?: string | null; text?: string | null; slot?: string | null; blocks?: ReadonlyArray<ChunkPart> | null }): string {
  const k = squash(chunk.key).replace(/一下$/u, "").replace(/[了過著]$/u, "");
  return k ? `K:${k}` : `F:${frameKey(chunk)}`;
}

/**
 * **塊の字を文に合わせて直す**（形だけ）。AI は「文からそのまま写す」と言われても、字を少し変えて切り出す（開電風扇 ← 你去開一下電風扇、
 * 手扶梯壞了 ← 手扶梯壞掉了）か、見出し語を外して切り出す（借我撐一下 ← 雨傘借我撐一下）ことがある — 考えさせない設定では特に多い
 * （5・6 回目の採点で 1 社の返事の 2〜5 割）。文はネイティブの一文なので、その中の連続した範囲なら塊として正しい。
 * 1. 塊が文にそのまま在ればその範囲。無ければ、塊の字が順に全部入る文の最短の範囲（余分の字は `maxExtra` まで）。
 * 2. 範囲に見出し語が無ければ、隣（間に 1 字まで）にある見出し語まで広げる。
 * 範囲が句読点をまたぐ・見つからない時は null（門が落とす）。
 */
export function repairChunkText(text: string, sentence: string, headword: string, maxExtra = 4): string | null {
  const t = [...squash(text)];
  const sArr = [...squash(sentence)];
  const head = headwordCore(headword);
  if (t.length === 0 || !head) return null;
  let a = -1;
  let b = -1;
  const direct = squash(sentence).indexOf(t.join(""));
  if (direct >= 0) {
    a = [...squash(sentence).slice(0, direct)].length;
    b = a + t.length;
  } else {
    for (let st = 0; st < sArr.length; st++) {
      if (sArr[st] !== t[0]) continue;
      let k = 0;
      let e = st;
      while (e < sArr.length && k < t.length) {
        if (sArr[e] === t[k]) k++;
        e++;
      }
      if (k < t.length || e - st - t.length > maxExtra) continue;
      if (a < 0 || e - st < b - a) {
        a = st;
        b = e;
      }
    }
    if (a < 0) return null;
  }
  const win = () => sArr.slice(a, b).join("");
  if (!win().includes(head)) {
    const hl = [...head].length;
    let hit = -1;
    for (let o = 0; o + hl <= sArr.length; o++) {
      if (sArr.slice(o, o + hl).join("") !== head) continue;
      if (o + hl >= a - 1 && o <= b + 1) {
        hit = o;
        break;
      }
    }
    if (hit < 0) return null;
    a = Math.min(a, hit);
    b = Math.max(b, hit + hl);
  }
  const out = win();
  return SENTENCE_PUNCT.test(out) ? null : out;
}

/**
 * **形だけの門。** 1 つずつ確かめ、通った候補と落とした物（理由つき）を返す。順番は返ってきた順。
 * 見る物: 見出し語が入る / 見出し語だけでない / 句読点が無い / 文の部分文字列 / 文が 24 字以内 / 見出し語の直前が
 * 量詞でない / 重複。入れ替えの所は、塊の中の字で・見出し語を含まず・代名詞でなく・候補が 2 つ以上ある時だけ残す
 * （だめなら入れ替え無しの塊として残す）。**自然さは見ない。**
 */
export function gateChunksV2(raw: ReadonlyArray<unknown> | null | undefined, ctx: ChunkV2GateContext): ChunkV2GateResult {
  const head = headwordCore(ctx.headword);
  const kept: ChunkCandidate[] = [];
  const dropped: ChunkV2GateResult["dropped"] = [];
  const seen = new Set<string>();

  for (const item of raw ?? []) {
    const parsed = AiChunkV2Schema.safeParse(item);
    if (!parsed.success) continue;
    const c = parsed.data;
    let text = squash(c.text);
    const drop = (reason: ChunkV2DropReason) => dropped.push({ text, reason });

    if (!text) {
      drop("empty");
      continue;
    }
    // 文にそのまま無い・見出し語が無い塊は、文の範囲に直せれば直す（直せなければ下で落ちる）。
    if (head && squash(c.sentence) && (!squash(c.sentence).includes(text) || !text.includes(head))) {
      const fixed = repairChunkText(text, c.sentence, ctx.headword);
      if (fixed) text = fixed;
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
    if (MEASURE_BEFORE.test(text.slice(0, text.indexOf(head)))) {
      drop("measure_phrase");
      continue;
    }
    let slot: string | null = squash(c.slot) || null;
    let alts = c.alts
      .map((a) => (typeof a === "string" ? squash(a) : squash((a as { text?: string } | null)?.text)))
      .filter((a) => a && a !== slot && a !== head)
      .filter((a, i, arr) => arr.indexOf(a) === i)
      .slice(0, 6);
    if (!slot || !text.includes(slot) || slot.includes(head) || head.includes(slot) || PRONOUNS.has(slot) || alts.length < 2) {
      slot = null;
      alts = [];
    }
    const frame = frameKey({ text, slot });
    if (seen.has(frame) || seen.has(text)) {
      drop("duplicate");
      continue;
    }
    seen.add(frame);
    seen.add(text);
    kept.push({
      text,
      sentence: c.sentence.trim(),
      key: squash(c.key),
      pattern: isChunkPattern(c.pattern) ? c.pattern : "",
      slot,
      alts,
    });
  }
  return { kept, dropped };
}

export type AgreementResult = {
  /** 両方が出した言い方（同じ型、含む関係、または同じ中心の語）。順は A・B の順位の平均。 */
  agreed: ChunkCandidate[];
  /** A だけが出した物（B の会社の審査が要る）。 */
  onlyA: ChunkCandidate[];
  /** B だけが出した物（A の会社の審査が要る）。 */
  onlyB: ChunkCandidate[];
};

/**
 * **2 社の返事を照合する。** 一致 = ①同じ型（＿ を含めて同じ字）、②片方の型がもう片方を字として含む（放進筆袋裡 ⊂
 * 把＿放進筆袋裡 — 長い方を採る）、③**同じ中心の語**（關掉電風扇 と 把電風扇關掉: 2 社が独立に同じ組み合わせを選んだ事が
 * 頻度の証拠。字が違えば両方を候補に残し、審査の順位で 1 つに絞る）。
 * 3 回目の採点（2026-10-30）で、字の一致だけでは 2 社の一致が 7% しか無かった（自由に書いた文が字まで揃うことは稀）。
 */
export function mergeByAgreement(a: ReadonlyArray<ChunkCandidate>, b: ReadonlyArray<ChunkCandidate>): AgreementResult {
  const usedB = new Set<number>();
  const agreed: Array<{ chunk: ChunkCandidate; rank: number }> = [];
  const onlyA: ChunkCandidate[] = [];
  const bare = (c: ChunkCandidate) => frameKey(c).replace(/＿/gu, "");
  a.forEach((ca, ia) => {
    const ka = frameKey(ca);
    const find = (pred: (cb: ChunkCandidate) => boolean) => b.findIndex((cb, ib) => !usedB.has(ib) && pred(cb));
    let hit = find((cb) => frameKey(cb) === ka);
    let sameText = true;
    if (hit < 0) {
      const ba = bare(ca);
      hit = find((cb) => {
        const bb = bare(cb);
        return ba.includes(bb) || bb.includes(ba);
      });
    }
    if (hit < 0) {
      const kc = coreKey(ca);
      hit = kc.startsWith("K:") ? find((cb) => coreKey(cb) === kc) : -1;
      sameText = false;
    }
    if (hit < 0) {
      onlyA.push(ca);
      return;
    }
    usedB.add(hit);
    const cb = b[hit];
    const rank = (ia + hit) / 2;
    if (sameText) {
      const longer = [...bare(cb)].length > [...bare(ca)].length ? cb : ca;
      agreed.push({ chunk: longer, rank });
    } else {
      // 同じ中心の語で字が違う: 両方を残し、審査の順位で 1 つに（coreKey の重複は rankAndSelect が落とす）。
      agreed.push({ chunk: ca, rank });
      agreed.push({ chunk: cb, rank: rank + 0.01 });
    }
  });
  agreed.sort((x, y) => x.rank - y.rank);
  const onlyB = b.filter((_, ib) => !usedB.has(ib));
  return { agreed: agreed.map((x) => x.chunk), onlyA, onlyB };
}

/** 審査と並べ替えの返事を読む（文字列の true/false・数字も読む。読めない物は無視）。 */
export function readJudgeRanks(raw: unknown, count: number): JudgeRank[] {
  const parsed = JudgeReplySchema.safeParse(raw);
  if (!parsed.success) return [];
  const out: JudgeRank[] = [];
  parsed.data.verdicts.forEach((v, at) => {
    if (!v || typeof v !== "object") return;
    const o = v as Record<string, unknown>;
    const iRaw = o.i ?? o.index ?? at + 1;
    const i = typeof iRaw === "number" ? iRaw : Number.parseInt(String(iRaw), 10);
    if (!Number.isInteger(i) || i < 1 || i > count) return;
    const n = o.natural;
    const natural = n === true || (typeof n === "string" && /^(true|yes|是|はい)$/iu.test(n.trim()));
    const rRaw = o.rank;
    const r = typeof rRaw === "number" ? rRaw : Number.parseInt(String(rRaw ?? ""), 10);
    const sRaw = o.same ?? o.same_as;
    const sm = typeof sRaw === "number" ? sRaw : Number.parseInt(String(sRaw ?? ""), 10);
    const same = Number.isInteger(sm) && sm >= 1 && sm <= count && sm !== i ? sm : null;
    out.push({ i, natural, rank: Number.isInteger(r) && r >= 1 ? r : null, ...(same ? { same } : {}) });
  });
  return out;
}

/** 候補 1 つ: 塊と、どちらの会社が書いたか（both = 一致）。 */
export type PooledChunk = { chunk: ChunkCandidate; author: "a" | "b" | "both" };

/** 2 社の返事を 1 つの候補の列に（一致 → A だけ → B だけ）。 */
export function poolCandidates(m: AgreementResult): PooledChunk[] {
  return [
    ...m.agreed.map((chunk) => ({ chunk, author: "both" as const })),
    ...m.onlyA.map((chunk) => ({ chunk, author: "a" as const })),
    ...m.onlyB.map((chunk) => ({ chunk, author: "b" as const })),
  ];
}

export type ChunkV2RejectReason = "unnatural" | "duplicate" | "over_max";
export type SelectedCandidate = ChunkCandidate & { by: "agreement" | "judge" };
export type RejectedCandidate = ChunkCandidate & { reason: ChunkV2RejectReason };

/**
 * **決める**: A が書いた塊は B の審査が「自然」と言った物だけ、B の塊は A の審査が言った物だけ。審査が片方しか無ければ
 * その審査（自分の会社の分も）で決める。一致した塊は、答えた審査のどれかが「自然」と言えば通す（どちらも不自然と言えば
 * 落とす — 2 社が同じ汎用の文を書いた時の網）。並びは 2 社が付けた順位の平均（片方しか無ければその順位、どちらも無ければ
 * 候補の並び）。同じ中心の語・同じ型の塊、審査が「同じ言い方」と言った塊（`same`）は 1 つにし、上限まで。落とした物は理由つき。
 */
export function rankAndSelect(
  pool: ReadonlyArray<PooledChunk>,
  ranksA: ReadonlyArray<JudgeRank> | null,
  ranksB: ReadonlyArray<JudgeRank> | null,
  max = CHUNKS_V2_MAX,
): { selected: SelectedCandidate[]; rejected: RejectedCandidate[] } {
  const byA = new Map((ranksA ?? []).map((v) => [v.i, v]));
  const byB = new Map((ranksB ?? []).map((v) => [v.i, v]));
  // 審査の「同じ言い方」をまとめる（どちらかの会社が言えば同じ）。
  const parent = new Map<number, number>();
  const root = (i: number): number => {
    const p = parent.get(i);
    if (p == null || p === i) return i;
    const r = root(p);
    parent.set(i, r);
    return r;
  };
  for (const v of [...(ranksA ?? []), ...(ranksB ?? [])]) {
    if (v.same) parent.set(root(Math.max(v.i, v.same)), root(Math.min(v.i, v.same)));
  }
  const scored: Array<{ chunk: SelectedCandidate; score: number; at: number }> = [];
  const rejected: RejectedCandidate[] = [];
  pool.forEach((p, at) => {
    const i = at + 1;
    const va = byA.get(i);
    const vb = byB.get(i);
    let ok: boolean;
    if (p.author === "a") ok = ranksB ? !!vb?.natural : ranksA ? !!va?.natural : true;
    else if (p.author === "b") ok = ranksA ? !!va?.natural : ranksB ? !!vb?.natural : true;
    else ok = !ranksA && !ranksB ? true : !!va?.natural || !!vb?.natural;
    if (!ok) {
      rejected.push({ ...p.chunk, reason: "unnatural" });
      return;
    }
    const ranks = [va?.natural ? va.rank : null, vb?.natural ? vb.rank : null].filter((r): r is number => r != null);
    const score = ranks.length > 0 ? ranks.reduce((x, y) => x + y, 0) / ranks.length : pool.length + at;
    scored.push({ chunk: { ...p.chunk, by: p.author === "both" ? "agreement" : "judge" }, score, at });
  });
  scored.sort((x, y) => x.score - y.score || x.at - y.at);
  const selected: SelectedCandidate[] = [];
  const seen = new Set<string>();
  for (const s of scored) {
    const k = coreKey(s.chunk);
    const f = frameKey(s.chunk);
    const g = `G:${root(s.at + 1)}`;
    if (seen.has(k) || seen.has(f) || seen.has(g)) {
      rejected.push({ ...s.chunk, reason: "duplicate" });
      continue;
    }
    seen.add(k);
    seen.add(f);
    seen.add(g);
    if (selected.length < max) selected.push(s.chunk);
    else rejected.push({ ...s.chunk, reason: "over_max" });
  }
  return { selected, rejected };
}

/** 仕上げの段の返事 1 つ（block と、読む人の言語の訳）。 */
export type FinishItem = {
  blocks?: unknown;
  ja?: unknown;
  sentence_ja?: unknown;
  note?: unknown;
  slot_ja?: unknown;
  alts_ja?: unknown;
};

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

/**
 * 候補を保存する形に（block は仕上げの段の返事から。つないで塊と同じ字にならない返事は使わず、塊 1 つの block に）。
 * 入れ替えの所は、その字と同じ block に印を付ける。字がもっと大きい block の中にあれば、その block を 3 つに割る。
 * 訳は読む人の言語でない物を捨てる（`looksWrongForReader`）。読む人の言語が要らない時（繁體中文で読む）は訳を付けない。
 */
export function finishCandidate(
  cand: ChunkCandidate & { by?: "agreement" | "judge" },
  item: FinishItem | null,
  ctx: { headword: string; language: string | null | undefined; readerLang?: string | null },
): UsageChunkV2 {
  const rawBlocks = Array.isArray(item?.blocks) ? (item!.blocks as unknown[]) : [];
  let blocks: ChunkPart[] = rawBlocks
    .map((b) => {
      if (typeof b === "string") return { text: squash(b), pos: "" };
      const o = (b ?? {}) as { text?: unknown; pos?: unknown };
      return { text: squash(str(o.text)), pos: str(o.pos) };
    })
    .filter((b) => b.text);
  if (blocks.map((b) => b.text).join("") !== cand.text) blocks = [{ text: cand.text, pos: "" }];

  if (cand.slot) {
    let at = blocks.findIndex((b) => b.text === cand.slot);
    if (at < 0) {
      const host = blocks.findIndex((b) => b.text.includes(cand.slot!));
      if (host >= 0) {
        const h = blocks[host];
        const i = h.text.indexOf(cand.slot);
        const parts: ChunkPart[] = [
          { text: h.text.slice(0, i), pos: "" },
          { text: cand.slot, pos: "N" },
          { text: h.text.slice(i + cand.slot.length), pos: "" },
        ].filter((p) => p.text);
        blocks.splice(host, 1, ...parts);
        at = blocks.findIndex((b) => b.text === cand.slot);
      }
    }
    if (at >= 0) {
      const altsJa = Array.isArray(item?.alts_ja) ? (item!.alts_ja as unknown[]).map(str) : [];
      blocks[at] = {
        ...blocks[at],
        slot: true,
        alts: cand.alts.map((text, j) => ({ text, ja: altsJa[j] ?? "" })),
        ...(str(item?.slot_ja) ? { ja: str(item?.slot_ja) } : {}),
      };
    }
  }

  const check = !!ctx.readerLang && !readerIsTarget(ctx.readerLang, ctx.language);
  let ja = str(item?.ja);
  let sentenceJa = str(item?.sentence_ja);
  let note = str(item?.note);
  if (check) {
    if (looksWrongForReader(ja, ctx.readerLang, cand.text)) ja = "";
    if (looksWrongForReader(sentenceJa, ctx.readerLang, cand.sentence)) sentenceJa = "";
    if (looksWrongForReader(note, ctx.readerLang, cand.text)) note = "";
    if (!ja) {
      // 訳が付かなければ、block と候補の訳も付けない（言語を混ぜない）。
      sentenceJa = "";
      note = "";
      blocks = blocks.map((b) => ({ ...b, ...(b.ja ? { ja: undefined } : {}), ...(b.alts ? { alts: b.alts.map((a) => ({ ...a, ja: "" })) } : {}) }));
    }
  } else {
    ja = "";
    sentenceJa = "";
    note = "";
    blocks = blocks.map((b) => ({ ...b, ja: undefined, ...(b.alts ? { alts: b.alts.map((a) => ({ ...a, ja: "" })) } : {}) }));
  }
  const out: UsageChunkV2 = {
    text: cand.text,
    blocks: blocks.map((b) => {
      const n: ChunkPart = { text: b.text, pos: b.pos };
      if (b.slot) {
        n.slot = true;
        n.alts = b.alts;
      }
      if (b.ja) n.ja = b.ja;
      return n;
    }),
    head: headPlace(blocks, ctx.headword),
    pattern: cand.pattern,
    ja,
    ...(note ? { note } : {}),
    sentence: cand.sentence,
    sentence_ja: sentenceJa,
    frequency: null,
    ...(cand.by ? { by: cand.by } : {}),
  };
  return out;
}

/** 候補を、block 1 つ・訳なしの保存の形に（仕上げが無かった時、不合格の記録）。 */
export function candidateToChunk(cand: ChunkCandidate & { by?: "agreement" | "judge" }, headword: string, language: string | null | undefined): UsageChunkV2 {
  return finishCandidate(cand, null, { headword, language, readerLang: null });
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
