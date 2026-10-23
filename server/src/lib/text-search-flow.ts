/**
 * **文字で調べた語の流れ**の決め事（画面にもサーバにも依らない純粋な所）。
 *
 * オーナー指示 2026-10-08:
 * > 文字検索したときは検索ボタンを押したらその場でくるくるとロード中になり、ユーザーが
 * > 検索したものが学習言語ならそのままシールをはがす場面（シールを表示するときは必ず画像や
 * > 発音が表示されてから、画像も変更出来きるように。）に移行し、母語で一対一の関係ではなく、
 * > 複数の単語の候補がある場合（同じ日本でも台湾華語だと区別があったり一般でな言い方や
 * > 学術的な言い方など）は単語の候補を表示して。
 *
 * 1. 押したら検索の欄のまま回る（別の待ち画面を出さない）。
 * 2. 語を引く（`suggestWordCandidates`）。返事は候補と「打った語がもう学習言語か」。
 * 3. `decideTextSearch` が「そのまま剥がす」「候補を選ばせる」「見つからない」を決める。
 * 4. 剥がす札は**絵と発音がそろってから**出す（`peelReady`）。
 */
import { z } from "zod";
import { coerceTargetHeadword, isTargetHeadword } from "./target-language";
import type { QueryLang } from "./text-query-lang";
import type { NameRegister } from "./candidate-register";

/**
 * 候補の**使われ方**の印（古い形）。画面はもう読まない — 古い iOS が読むので返し続ける
 * （`legacyUsageOf` が `register` から作る）。
 * - `common` 一般的 / `colloquial` 口語 / `formal` 書き言葉・改まった / `academic` 学術・専門
 * - `local` その土地でよく使う（台湾華語なら「台湾でよく使う」）
 */
export const CANDIDATE_USAGES = ["common", "colloquial", "formal", "academic", "local"] as const;
export type CandidateUsage = (typeof CANDIDATE_USAGES)[number];

/** AI が返した印を直す。知らない値・空は `null`（札を出さない）。 */
export function normalizeUsage(raw: unknown): CandidateUsage | null {
  if (typeof raw !== "string") return null;
  const v = raw.trim().toLowerCase();
  if (!v) return null;
  if ((CANDIDATE_USAGES as readonly string[]).includes(v)) return v as CandidateUsage;
  if (/^(general|standard|neutral|everyday|一般)/.test(v)) return "common";
  if (/^(casual|informal|spoken|slang|口語|口语)/.test(v)) return "colloquial";
  if (/^(written|literary|polite|書面|书面)/.test(v)) return "formal";
  if (/^(technical|scientific|specialist|professional|學術|学術|学术|專業)/.test(v))
    return "academic";
  if (/^(taiwan|regional|台灣|台湾)/.test(v)) return "local";
  return null;
}

/**
 * 候補の**文体**（どこで使う言葉か）。どの候補も**同じ1本の物差し**で1つだけ持つ。
 *
 * オーナー指摘 2026-10-09（「豚の口の周りの肉」→ 嘴邊肉［台湾でよく使う］／豬頰肉［一般的］）:
 * > 一般的な言い方とか台湾でよく使われるとか、違いが分かりにくいから、それぞれの言い方が
 * > どのように違うのか明確にして。書き言葉なのか？一般的な話し言葉の言い方なのか？
 * > 学術的ないいかたなのか？
 *
 * 前の印（`usage`）は「土地（台湾でよく使う）」と「文体（一般的・口語）」の2つの物差しが
 * 混ざっていて、並べても比べられなかった。候補はどれも台湾で使う語なので、土地は札にしない
 * （本当に土地が違いの時だけ「違い」の一言に書く）。
 *
 * - `spoken` 話し言葉（会話）
 * - `written` 書き言葉（文章・ニュース）
 * - `both` 会話でも文章でも
 * - `technical` 専門用語・学術
 * - `signage` 表示・メニューの言葉（店の札・品書き・案内板）
 */
export const CANDIDATE_REGISTERS = ["spoken", "written", "both", "technical", "signage"] as const;
export type CandidateRegister = (typeof CANDIDATE_REGISTERS)[number];

/**
 * AI が返した文体を直す。無い時は古い印（`usage`）から読む。
 * 土地の印（`local`）は文体ではないので札にしない（`null`）。
 */
export function normalizeRegister(raw: unknown, legacyUsage?: unknown): CandidateRegister | null {
  if (typeof raw === "string") {
    const v = raw.trim().toLowerCase();
    if ((CANDIDATE_REGISTERS as readonly string[]).includes(v)) return v as CandidateRegister;
    if (/^(conversation|colloquial|casual|informal|口語|口语|話し言葉)/.test(v)) return "spoken";
    if (/^(formal|literary|書面|书面|書き言葉)/.test(v)) return "written";
    if (/^(common|general|neutral|everyday|一般|両方)/.test(v)) return "both";
    if (/^(academic|scientific|specialist|professional|jargon|學術|学術|学术|專業|専門)/.test(v))
      return "technical";
    if (/^(sign|menu|label|display|表示|菜單|メニュー)/.test(v)) return "signage";
  }
  switch (normalizeUsage(legacyUsage)) {
    case "common":
      return "both";
    case "colloquial":
      return "spoken";
    case "formal":
      return "written";
    case "academic":
      return "technical";
    default:
      return null;
  }
}

/** 古い iOS のための印（`usage`）を文体から作る。表示・メニューの言葉は「一般的」に寄せる。 */
export function legacyUsageOf(register: CandidateRegister | null): CandidateUsage | null {
  switch (register) {
    case "spoken":
      return "colloquial";
    case "written":
      return "formal";
    case "technical":
      return "academic";
    case "both":
    case "signage":
      return "common";
    default:
      return null;
  }
}

/** 生成の形（`suggestWordCandidates`）。足りない欄は空で受ける — 形が崩れても0件にしない。 */
export const WordCandidatesSchema = z.object({
  /**
   * 打った語が**もう学習言語の語か**（「蓮藕」「貓」）。漢字だけの語は手元で見分けられない
   * （「電車」「猫」）ので、ここで AI に判定させる。言わなかった回は `null`。
   */
  query_is_target: z.boolean().nullable().optional(),
  candidates: z
    .array(
      z.object({
        headword: z.string(),
        reading_zhuyin: z.string().default(""),
        pinyin: z.string().default(""),
        meaning_ja: z.string().default(""),
        /**
         * 他の候補との**違い**（比べた一言。例: 「豬頰肉より口語的。店で頼むならこちら」）。
         * 古い iOS もこの欄を出すので、名前は変えない。
         */
        distinction: z.string().default(""),
        /**
         * どんな言い方か（`candidate-register.ts` の5つ。2026-10-15）。古い返事の文体の値
         * （spoken など）も受け、`normalizeNameRegister` が読む。
         */
        register: z.string().nullable().optional(),
        /** 文体（`CANDIDATE_REGISTERS`。2026-10-15 まで `register` に入っていた物）。 */
        style: z.string().nullable().optional(),
        /** 使う場面（どこで聞く・見るか。例: 「屋台・黑白切の店で注文するとき」）。 */
        scene: z.string().nullable().optional(),
        /** 使われ方（古い形 `CANDIDATE_USAGES`）。古い返事・古い iOS のために受ける。 */
        usage: z.string().nullable().optional(),
        /** 画像検索用の短い英語（札の絵を探す。`heroSearchQuery` が整える）。 */
        image_query: z.string().nullable().optional(),
        /**
         * 図鑑の分類の鍵（2026-10-15）。形は信用しない — サーバが `coerceCategoryKey` と見出し語の規則で直す。
         * iOS はカードが届く前に保存するとこの分類で図鑑に置く（無いと「その他」に入った — 花束）。
         */
        category_key: z.unknown().optional(),
      }),
    )
    .default([]),
});

/** 画面へ返す候補の1つ。 */
export type TextCandidate = {
  headword: string;
  reading_zhuyin: string;
  pinyin: string;
  meaning_ja: string;
  /** 他の候補との違い（比べた一言）。 */
  distinction: string;
  /** どんな言い方か（5つのどれか。必ず入る — `finalizeNameRegisters`）。 */
  register: NameRegister;
  /** 文体の札（1つだけ。Web の候補の一覧が出す）。分からない時は `null`（札を出さない）。 */
  style: CandidateRegister | null;
  /** 使う場面。無ければ空。 */
  scene: string;
  /** 古い印（古い iOS 用。画面は `register` を読む）。 */
  usage: CandidateUsage | null;
  image_query: string;
  /** 図鑑の分類の鍵（2026-10-15。古い返事には無い）。 */
  category_key?: string;
  /** 表示言語の短い意味（`meaning_ja` の最初の言い方。2026-10-15。古い返事には無い）。 */
  gloss?: string;
  /** 打った物の表示言語の名前（写真の候補のタグと同じ欄。2026-10-15。古い返事には無い）。 */
  object_label?: string;
};

export type TextSearchDecision =
  | { kind: "peel"; pick: TextCandidate; via: "target" | "single" }
  | { kind: "choose"; candidates: TextCandidate[] }
  | { kind: "none" };

/** 並べる候補の上限（多すぎると選べない）。 */
export const MAX_TEXT_CANDIDATES = 5;

/**
 * 語を引いた返事から、次に何をするかを決める。
 *
 * - 打った語が**はっきり学習言語**（手元の判定が `target` — 台湾の字にしか無い形が在る）
 *   → 候補を並べず、**打った語そのもの**を剥がす札へ（読み・意味は同じ語の候補から借りる）。
 * - 漢字だけで決まらない語（`ambiguous`）は**母語で打った語として**扱う
 *   （オーナー指摘 2026-10-09「桃と日本語で検索したら、そのまま表示された。台湾華語では
 *   水蜜桃とか、桃子っていう言い方もあるよね？…一対一の訳ではないよね？」）。日本語を母語に
 *   する人が「桃」「電車」と打ったら、それは日本語の語でもある。AI が「台湾華語でも通じる」と
 *   言っても、台湾での言い方が割れる（桃子・水蜜桃・桃）なら選ばせる。
 *   候補が無い時だけ、AI が「学習言語」と言った打った語のまま剥がす（読みはカードが補う）。
 * - 手元で `native` と分かった語（かな・新字体）は、AI が何と言っても母語として扱う。
 * - 母語で、使える候補が1つ → そのまま剥がす札へ（選ぶ物が1つの画面は出さない）。
 * - 2つ以上 → 選ばせる（最大 `MAX_TEXT_CANDIDATES`）。
 * - 0 → 見つからない（打った語のまま札を作らない — 見出しが母語のまま残る）。
 */
export function decideTextSearch(input: {
  query: string;
  local: QueryLang;
  queryIsTarget: boolean | null | undefined;
  candidates: readonly TextCandidate[];
  targetLanguage: string;
}): TextSearchDecision {
  const query = input.query.trim();
  const usable = dedupeCandidates(input.candidates, input.targetLanguage);
  const asTyped =
    input.local === "target" ||
    (input.local === "ambiguous" && input.queryIsTarget === true && usable.length === 0);
  if (asTyped && isTargetHeadword(query, input.targetLanguage)) {
    const same = usable.find((c) => c.headword === query);
    return {
      kind: "peel",
      via: "target",
      pick: same ?? {
        headword: query,
        reading_zhuyin: "",
        pinyin: "",
        meaning_ja: "",
        distinction: "",
        register: "common",
        style: null,
        scene: "",
        usage: null,
        image_query: "",
      },
    };
  }
  if (usable.length === 0) return { kind: "none" };
  if (usable.length === 1) return { kind: "peel", via: "single", pick: usable[0] };
  return { kind: "choose", candidates: usable.slice(0, MAX_TEXT_CANDIDATES) };
}

/** 学習言語の見出しとして通る物だけ、同じ語は1つに。 */
export function dedupeCandidates(
  items: readonly TextCandidate[],
  targetLanguage: string,
): TextCandidate[] {
  const out: TextCandidate[] = [];
  const seen = new Set<string>();
  for (const c of items) {
    const head = coerceTargetHeadword(c.headword, targetLanguage);
    if (!head || seen.has(head)) continue;
    seen.add(head);
    out.push({ ...c, headword: head });
  }
  return out;
}

/** 剥がす札を出すまでに待つ上限（ms）。これを過ぎたら、そろった物で出す。 */
export const PEEL_READY_MAX_WAIT_MS = 9000;

/**
 * **剥がす札を出してよいか。** 絵（撮った写真、またはネットの画像を探し終えた）と、
 * 発音（音が届いた・取れないと分かった）と、読みの載ったカードがそろってから。
 * 上限を過ぎたら、そろった物で出す（語を組んだ札・読みの文字だけ）— 待たせ続けない。
 */
export function peelReady(s: {
  hasCard: boolean;
  /** 札の絵が決まったか（写真がある・ネットの画像を探し終えた）。 */
  imageSettled: boolean;
  speech: "none" | "loading" | "ready" | "failed";
  /** 待ち始めてからの時間。 */
  waitedMs: number;
}): boolean {
  if (!s.hasCard) return false;
  if (s.waitedMs >= PEEL_READY_MAX_WAIT_MS) return true;
  const speechDone = s.speech === "ready" || s.speech === "failed";
  return s.imageSettled && speechDone;
}
