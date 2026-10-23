import {
  checkMainExampleLabel,
  chunksMatchSentence,
  mainExampleLabelRule,
  mainExampleNeedsTidy,
  mainExampleRepair,
  mainSceneFor,
  mayWriteMainLabel,
  sceneMaxChars,
  type CheckedMainLabel,
  type MainExampleRepair,
} from "./example-patterns";
import { looksLikeTargetLanguage } from "./text-language";
import { readerText } from "./note-language";
import { reportServerBackgroundFailure } from "./background-failure.server";
import { targetProfile } from "./target-profile";
import type { UiLang } from "./i18n";

/**
 * **札の無い古いメインの例文に、札だけを付ける**（オーナー報告 2026-10-16: 冰淇淋 の1つ目の例文
 * 「夏天吃冰淇淋。」に場面の札が無く、2つ目の例文には有る）。
 *
 * 場面の札（2026-10-14）より前に出来た例文は、共有の行（`words.example_sentence`）にそのまま残る
 * （オーナー決定: 古い例文の**文そのもの**は作り直さない）。札だけなら足してよいので、単語の詳細を開いた時
 * （`getWordExplanation`）に、返事の後で**札だけを書く小さな呼び出し**を1回する。札は次に開いた時に出る。
 *
 * - 文は変えない。札は**その文のために**書かせ、`example_scene_for` = その文を付ける（iOS はこれが無いと出さない）
 * - 札の決まりは例文のパターンと同じ（短い1行・読む人の言語・字数の上限 — `mainExampleLabelRule`）
 * - 追加の例文のうちメインと同じパターンの物は落とし、`example_pattern_count` を 1 + 残った数にする
 * - 別の文のパーツ（`example_chunks`）は、その文のパーツに入れ替えるか空にする
 * - 札がもう片方の行（読む人の行 ⇔ 共有の行）に在れば AI を呼ばずに写す。札が在って同じパターンの追加の
 *   例文だけが残っている行も、AI を呼ばずに直す。**AI を呼ぶ時だけ**記録された同意と枠が要る（`allowSceneLabel`）
 *
 * **書き方**（PR #189 の点検）: 行を丸ごと書き戻さない。`apply_main_example_label`（SQL の関数、1回の文）が、
 * 書く時点の行に名前を挙げた鍵だけを重ねる — 間にほかの処理が書いた鍵（使い方の型など）は残る。札は目印が
 * まだその文でない行にだけ、語のメインの例文がまだその文の時だけ書く。人が確かめた読む人の行は触らない。
 * 同じ行の仕事は1つずつ（`inFlight`、同じ実行環境の中）。同じ行は `RETRY_AFTER_MS` の間、呼び直さない。
 */

/** 同じ行を呼び直すまでの間（同じ実行環境の中だけ）。 */
export const RETRY_AFTER_MS = 30 * 60 * 1000;
const recent = new Map<string, number>();
/** いま仕事中の行（同じ実行環境の中だけ。読む前に取り、終わったら外す）。 */
const inFlight = new Set<string>();

/** 試験用: 呼び直しの記録を消す。 */
export function forgetMainExampleLabelAttempts(): void {
  recent.clear();
  inFlight.clear();
}

type ExplanationKey = { explainLang: string; l1: string };

/** 読む人の行（**生の** extras — 書く時の比べ（`staleChunks`・`drop`）が行の値そのものと合うように）。 */
type ReaderRow = {
  example_translation: string | null;
  extras: Record<string, unknown> | null;
  source: string;
};

/** `apply_main_example_label` に渡す物。`l1` が null なら共有の行。 */
export type RepairCall = {
  wordId: string;
  explainLang: string;
  l1: string | null;
  sentence: string;
  repair: MainExampleRepair;
  translation: string | null;
};

export type MainExampleLabelDeps = {
  /** service role の Supabase クライアント（`words` / `stickers` を読む）。 */
  admin: unknown;
  /** 読む人の行を1つ引く（生の extras）。 */
  readReader: (admin: unknown, wordId: string, key: ExplanationKey) => Promise<ReaderRow | null>;
  /** 1つの行を部分的に直す（`apply_main_example_label`）。何か書いたら true。 */
  applyRepair: (call: RepairCall) => Promise<boolean>;
  /** AI を呼んでよいか（同意・その日の枠）。駄目なら投げる。AI を呼ぶ時だけ呼ばれる。 */
  allow: (userId: string) => Promise<void>;
  /** 指示を渡し、返事の文を受け取る。 */
  generate: (prompt: string) => Promise<string>;
  parseJson: (text: string) => unknown;
  languageName: (lang: string) => string;
  now?: () => number;
};

export type MainExampleLabelResult =
  { outcome: "labelled" | "tidied" } | { outcome: "skipped" | "failed"; reason: string };

type LooseDb = {
  from: (t: string) => {
    select: (c: string) => {
      eq: (
        k: string,
        v: string,
      ) => {
        maybeSingle: () => PromiseLike<{ data: unknown; error: unknown }>;
        eq: (
          k: string,
          v: string,
        ) => {
          limit: (n: number) => {
            maybeSingle: () => PromiseLike<{ data: unknown; error: unknown }>;
          };
          eq: (
            k: string,
            v: string,
          ) => { maybeSingle: () => PromiseLike<{ data: unknown; error: unknown }> };
        };
      };
    };
  };
  rpc?: (fn: string, args: unknown) => PromiseLike<{ data: unknown; error: unknown }>;
};

type WordRow = {
  headword: string;
  language: string | null;
  example_sentence: string | null;
  extras: Record<string, unknown> | null;
  source: string;
};

const asObject = (v: unknown): Record<string, unknown> | null =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;

async function readWord(admin: unknown, wordId: string): Promise<WordRow | null> {
  const { data, error } = await (admin as LooseDb)
    .from("words")
    .select("headword, language, example_sentence, extras, source")
    .eq("id", wordId)
    .maybeSingle();
  if (error || !data) return null;
  const r = data as Record<string, unknown>;
  return {
    headword: String(r.headword ?? ""),
    language: (r.language as string | null) ?? null,
    example_sentence: (r.example_sentence as string | null) ?? null,
    extras: asObject(r.extras),
    source: String(r.source ?? "ai"),
  };
}

async function ownsWord(admin: unknown, userId: string, wordId: string): Promise<boolean> {
  const { data } = await (admin as LooseDb)
    .from("stickers")
    .select("id")
    .eq("user_id", userId)
    .eq("word_id", wordId)
    .limit(1)
    .maybeSingle();
  return !!data;
}

/** 共有の解説が読む人の言語で書かれているか（`stickers.functions.ts` の `sharedExtrasInLang` と同じ）。 */
function sharedInLang(extras: Record<string, unknown> | null, lang: string): boolean {
  if (!extras) return false;
  const v = extras.explain_lang;
  return ((typeof v === "string" && v.trim()) || "ja") === lang;
}

/**
 * 1つの行に直す物があるか: 札を書いてよい（`mayWriteMainLabel` — 札が無い・別の文の札）か、その文の札が在って
 * 掃除（同じパターンの追加の例文・数）だけが要るか。目印の無い札の行は、どちらにも当たらない（触らない）。
 */
const needsWork = (extras: Record<string, unknown> | null, sentence: string, head: string) =>
  mayWriteMainLabel(sentence, extras) || mainExampleNeedsTidy(extras, sentence, head);

/**
 * 1つの行の見え方。
 * - `inLang`: 読む人の言語で書かれた行か（違えば、その行の札を写さない・その行に書かない）
 * - `writable`: 書いてよいか（読む人の言語で、人が確かめた行でない）
 */
type RowView = { extras: Record<string, unknown> | null; writable: boolean; inLang: boolean };

/** 読む人の行の見え方（鍵が読む人の言語の行）。人が確かめた行は書かない。 */
const readerView = (row: { extras: unknown; source?: string | null } | null): RowView | null =>
  row ? { extras: asObject(row.extras), writable: row.source !== "verified", inLang: true } : null;

/** 共有の行の見え方。違う言語の解説は写さず書かない。人が確かめた語は書かない（写すのはよい）。 */
const sharedView = (
  row: { extras: unknown; source?: string | null } | null,
  lang: string,
): RowView | null => {
  if (!row) return null;
  const extras = asObject(row.extras);
  const inLang = sharedInLang(extras, lang);
  return { extras, writable: inLang && row.source !== "verified", inLang };
};

/**
 * **何をするか**（仕事と、頼むかの判断で同じ物を使う）。
 * - `readerTodo` / `sharedTodo`: 書ける行のうち、直す物がある行
 * - `copy`: どちらかの行に在る、その文の札（在れば AI を呼ばずに写す）
 * - `needAi`: 札を付ける行があるのに、写せる札が無い（AI を呼ぶ = 同意と枠が要る）
 */
function planRepair(
  sentence: string,
  head: string,
  reader: RowView | null,
  shared: RowView | null,
  lang: string,
) {
  const readerTodo = !!reader?.writable && needsWork(reader.extras, sentence, head);
  const sharedTodo = !!shared?.writable && needsWork(shared.extras, sentence, head);
  /**
   * 写してよい札: 読む人の言語の行にある、その文の札で、札そのものも読む人の言語で書かれた物だけ
   * （英語で読む人の行に日本語の札を写さない — PR #189 の点検）。
   */
  const copyable = (row: RowView | null) => {
    if (!row?.inLang) return "";
    const scene = mainSceneFor(sentence, row.extras);
    return scene && readerText(scene, lang, sentence).trim() ? scene : "";
  };
  const readerScene = copyable(reader);
  const sharedScene = copyable(shared);
  const needsLabel =
    (readerTodo && mayWriteMainLabel(sentence, reader?.extras)) ||
    (sharedTodo && mayWriteMainLabel(sentence, shared?.extras));
  return {
    readerTodo,
    sharedTodo,
    copy: readerScene || sharedScene,
    copySource: readerScene ? reader : sharedScene ? shared : null,
    needAi: needsLabel && !(readerScene || sharedScene),
  };
}

/**
 * その語・その読む人の行のメインの例文に、札が無ければ付ける（同じパターンの追加の例文も落とす）。
 * **投げない** — 失敗は結果で返す（呼ぶのは返事の後の裏の仕事）。
 */
export async function labelMainExample(
  deps: MainExampleLabelDeps,
  input: { userId: string; wordId: string; key: ExplanationKey },
): Promise<MainExampleLabelResult> {
  const now = (deps.now ?? Date.now)();
  const memo = `${input.wordId}:${input.key.explainLang}:${input.key.l1}`;
  const last = recent.get(memo);
  if (last !== undefined && now - last < RETRY_AFTER_MS) return skipped("recently tried");
  // 同じ行の仕事は1つずつ。確かめて取るまでの間に await を挟まない（同時に来た2つ目はここで止まる）。
  if (inFlight.has(memo)) return skipped("in flight");
  inFlight.add(memo);
  try {
    const word = await readWord(deps.admin, input.wordId);
    if (!word) return skipped("no word");
    const sentence = (word.example_sentence ?? "").trim();
    const head = word.headword.trim();
    if (!sentence || !looksLikeTargetLanguage(sentence, word.language)) {
      return skipped("no main example");
    }
    // 自分の図鑑に在る語だけ（`regenerateCardSection` と同じ持ち主の確かめ）。
    if (!(await ownsWord(deps.admin, input.userId, input.wordId))) return skipped("not owned");

    const reader = await deps.readReader(deps.admin, input.wordId, input.key);
    const plan = planRepair(
      sentence,
      head,
      readerView(reader),
      sharedView(word, input.key.explainLang),
      input.key.explainLang,
    );
    if (!plan.readerTodo && !plan.sharedTodo) return skipped("nothing to do");

    let label: CheckedMainLabel | null = null;
    let viaAi = false;
    /** AI がメインと同じパターンと言った追加の例文の**文**（番号は AI に見せた一覧の中だけの位置）。 */
    let samePattern: string[] = [];
    if (plan.copy) {
      recent.set(memo, now);
      // 札を写す行のパーツも、この文を分けた物なら一緒に写す（違えば写さない — 書く側が別の文のパーツを消す）。
      const src = plan.copySource?.extras;
      const chunks = chunksMatchSentence(src?.example_chunks, sentence)
        ? (src?.example_chunks as CheckedMainLabel["chunks"])
        : [];
      label = { scene: plan.copy, translation: "", chunks, sameAsMain: [] };
    } else if (plan.needAi) {
      // AI を呼ぶ時だけ: 記録された同意と、その日の枠（同意の無い人も、写す・掃除するだけの仕事はできる）。
      await deps.allow(input.userId);
      // 呼んでよいと分かってから記録する（同意の無い人・枠の尽きた人が、ほかの人の札を止めないように）。
      recent.set(memo, now);
      const listFrom = plan.readerTodo ? reader?.extras : word.extras;
      const extrasList = (listFrom?.examples_extra as unknown[] | undefined)
        ?.map((x) => String((x as { zh?: unknown })?.zh ?? "").trim())
        .filter(Boolean);
      const wantTranslation = plan.readerTodo && !(reader?.example_translation ?? "").trim();
      const profile = targetProfile(word.language);
      // 書く行にこの文のパーツが無ければ（無い・別の文の物）、同じ呼び出しでこの文のパーツも書かせる。
      const wantChunks =
        (plan.readerTodo && !chunksMatchSentence(reader?.extras?.example_chunks, sentence)) ||
        (plan.sharedTodo && !chunksMatchSentence(word.extras?.example_chunks, sentence));
      const chunkRoles = wantChunks ? profile.chunkRoles.join(" / ") : undefined;
      const nl = deps.languageName(input.key.explainLang);
      const prompt = [
        `${profile.promptName}の単語「${head}」の例文に、場面の札だけを付けます。例文は変えません。出力はJSONオブジェクト1つだけ(前置き不要)。`,
        mainExampleLabelRule({
          sentence,
          headword: head,
          targetName: profile.promptName,
          nl,
          sceneMax: sceneMaxChars(input.key.explainLang),
          translation: wantTranslation,
          chunkRoles,
          extras: extrasList,
        }),
        `{"example_main":{"scene":"短い1行(${nl})",${wantTranslation ? `"translation":"訳(${nl})",` : ""}${chunkRoles ? `"chunks":[{"text":"","pos":""}],` : ""}"scene_fits":true${extrasList?.length ? `,"same_as_main":[]` : ""}}}`,
      ].join("\n");
      const text = await deps.generate(prompt);
      const raw = deps.parseJson(text) as { example_main?: unknown } | null;
      label = checkMainExampleLabel(raw?.example_main, {
        sentence,
        readerLang: input.key.explainLang,
      });
      if (!label) return { outcome: "failed", reason: "no usable label" };
      viaAi = true;
      samePattern = label.sameAsMain
        .map((i) => extrasList?.[i] ?? "")
        .filter((x): x is string => !!x);
    } else {
      recent.set(memo, now);
    }

    /** 1つの行の直し。何を足す・落とすは読んだ行で決め、書くのは SQL が書く時点の行に重ねる。 */
    const repairFor = (extras: Record<string, unknown> | null) =>
      mainExampleRepair(extras, {
        sentence,
        headword: head,
        label: mayWriteMainLabel(sentence, extras) ? label : null,
        samePattern,
      });
    let wrote = false;
    let labelled = false;
    if (plan.readerTodo) {
      const repair = repairFor(reader?.extras ?? null);
      if (repair) {
        wrote =
          (await deps.applyRepair({
            wordId: input.wordId,
            explainLang: input.key.explainLang,
            l1: input.key.l1,
            sentence,
            repair,
            translation: viaAi && label?.translation ? label.translation : null,
          })) || wrote;
        labelled ||= repair.scene !== null;
      }
    }
    if (plan.sharedTodo) {
      const repair = repairFor(word.extras);
      if (repair) {
        wrote =
          (await deps.applyRepair({
            wordId: input.wordId,
            explainLang: input.key.explainLang,
            l1: null,
            sentence,
            repair,
            translation: null,
          })) || wrote;
        labelled ||= repair.scene !== null;
      }
    }
    if (!wrote) return { outcome: "failed", reason: "nothing written" };
    return { outcome: labelled ? "labelled" : "tidied" };
  } catch (e) {
    return { outcome: "failed", reason: e instanceof Error ? e.message : String(e) };
  } finally {
    inFlight.delete(memo);
  }
}

function skipped(reason: string): MainExampleLabelResult {
  return { outcome: "skipped", reason };
}

/**
 * **項目の作り直し（追加の例文の節）が一緒に書かせた札を書く**（`runSectionRegen`）。行を丸ごと書き戻さず、
 * 札を付ける行（札がまだ無い・書ける行）にだけ `apply_main_example_label` で名前を挙げた鍵を書く。
 * 語のメインの例文が変わっていれば書かない（SQL が確かめる）。**投げない**。
 */
export async function persistMainLabel(input: {
  /** 失敗を数える人（作り直しを頼んだ人）。 */
  userId: string;
  wordId: string;
  key: ExplanationKey;
  /** 札を書かせた時のメインの例文（語の文がもう違えば書かない）。 */
  sentence: string;
  label: { scene: string; chunks: CheckedMainLabel["chunks"]; translation: string };
  admin?: unknown;
  report?: typeof reportServerBackgroundFailure;
}): Promise<boolean> {
  const report = input.report ?? reportServerBackgroundFailure;
  const onError = (e: unknown) =>
    void report("scene_label", input.userId, e, {
      where: "persistMainLabel",
      word_id: input.wordId,
    });
  try {
    const admin =
      input.admin ?? (await import("@/integrations/supabase/client.server")).supabaseAdmin;
    const word = await readWord(admin, input.wordId);
    const sentence = input.sentence.trim();
    if (!word || !sentence || (word.example_sentence ?? "").trim() !== sentence) return false;
    const reader = await readReaderRaw(admin, input.wordId, input.key);
    const label: CheckedMainLabel = { ...input.label, sameAsMain: [] };
    // 札を書いてよい行だけ（札が無い・別の文の札。目印の無い札・人が確かめた行は触らない）。
    const repairFor = (extras: Record<string, unknown> | null) =>
      mayWriteMainLabel(sentence, extras)
        ? mainExampleRepair(extras, { sentence, headword: word.headword.trim(), label })
        : null;
    let wrote = false;
    if (reader && readerView(reader)?.writable) {
      const repair = repairFor(reader.extras);
      if (repair) {
        wrote =
          (await applyRepairViaRpc(
            admin,
            {
              wordId: input.wordId,
              explainLang: input.key.explainLang,
              l1: input.key.l1,
              sentence,
              repair,
              translation: input.label.translation || null,
            },
            onError,
          )) || wrote;
      }
    }
    if (sharedView(word, input.key.explainLang)?.writable) {
      const repair = repairFor(word.extras);
      if (repair) {
        wrote =
          (await applyRepairViaRpc(
            admin,
            {
              wordId: input.wordId,
              explainLang: input.key.explainLang,
              l1: null,
              sentence,
              repair,
              translation: null,
            },
            onError,
          )) || wrote;
      }
    }
    return wrote;
  } catch (e) {
    onError(e);
    return false;
  }
}

/**
 * 札だけの呼び出し（AI）をしてよいか。**サーバに記録された今の版の同意が要る**（PR #189 の点検 P2）。
 *
 * `assertAiConsent` は同意の見出しを送らない古い iOS（`/api/native-fn`）を通す — 端末が同意を確かめてから
 * AI の機能を呼ぶから。ここは読むだけの `getWordExplanation` から裏で始まる呼び出しで、端末の確認を経ていない。
 * だから見出し・環境変数に関わらず、記録された同意だけを見る（表が無い・取り消した・古い版なら呼ばない）。
 * 同意があれば、その日の枠（`scene_label`）を1回分とる。駄目なら投げる。
 */
export async function allowSceneLabel(
  userId: string,
  deps: {
    consentStatus: (userId: string) => Promise<{ agreed: boolean; recorded: boolean }>;
    reserve: (userId: string) => Promise<void>;
  },
): Promise<void> {
  const status = await deps.consentStatus(userId);
  if (!status.recorded || !status.agreed) {
    throw new Error("AI_CONSENT_REQUIRED: scene label needs recorded AI consent");
  }
  await deps.reserve(userId);
}

/** 本番の `applyRepair`: `apply_main_example_label` を呼ぶ（無い・失敗した時は書かない）。 */
export async function applyRepairViaRpc(
  admin: unknown,
  call: RepairCall,
  onError?: (error: unknown) => void,
): Promise<boolean> {
  const rpc = (admin as LooseDb).rpc;
  if (!rpc) return false;
  const { data, error } = await rpc.call(admin, "apply_main_example_label", {
    p_word_id: call.wordId,
    p_explain_lang: call.explainLang,
    p_l1: call.l1,
    p_sentence: call.sentence,
    p_scene: call.repair.scene,
    p_chunks: call.repair.chunks,
    p_stale_chunks: call.repair.staleChunks,
    p_drop: call.repair.drop,
    p_recount: call.repair.recount,
    p_translation: call.translation,
  });
  if (error) {
    console.warn("labelMainExample: apply_main_example_label failed", error);
    onError?.(error);
    return false;
  }
  return data === true;
}

/** 本番の `readReader`: 読む人の行を生のまま引く。 */
async function readReaderRaw(
  admin: unknown,
  wordId: string,
  key: ExplanationKey,
): Promise<ReaderRow | null> {
  const { data, error } = await (admin as LooseDb)
    .from("word_explanations")
    .select("extras, example_translation, source")
    .eq("word_id", wordId)
    .eq("explain_lang", key.explainLang)
    .eq("l1", key.l1)
    .maybeSingle();
  if (error || !data) return null;
  const r = data as Record<string, unknown>;
  return {
    extras: asObject(r.extras),
    example_translation: (r.example_translation as string | null) ?? null,
    source: String(r.source ?? "ai"),
  };
}

/**
 * 本番の道具をそろえて `labelMainExample` を呼ぶ（AI は速いモデル、枠は `scene_label`、AI を呼ぶ時だけ
 * 記録された同意が要る）。
 */
export async function runMainExampleLabel(input: {
  userId: string;
  wordId: string;
  key: ExplanationKey;
}): Promise<MainExampleLabelResult> {
  const [{ supabaseAdmin }, ai, consent, { generateText }] = await Promise.all([
    import("@/integrations/supabase/client.server"),
    import("./ai-provider.server"),
    import("./ai-consent.server"),
    import("ai"),
  ]);
  return labelMainExample(
    {
      admin: supabaseAdmin,
      readReader: readReaderRaw,
      applyRepair: (call) =>
        applyRepairViaRpc(supabaseAdmin, call, (e) =>
          reportServerBackgroundFailure("scene_label", input.userId, e, {
            where: "apply_main_example_label",
            word_id: input.wordId,
          }),
        ),
      allow: (userId) =>
        allowSceneLabel(userId, {
          consentStatus: (id) => consent.getAiConsentStatus(id),
          reserve: (id) => ai.assertWithinDailyCap(id, "scene_label"),
        }),
      generate: async (prompt) => {
        const cfg = await ai.getAiFor("card", "section_regen");
        const result = await ai.withModelFallback(cfg, cfg.modelFast, (m) =>
          generateText({
            model: cfg.gateway(m),
            prompt,
            abortSignal: AbortSignal.timeout(20_000),
          }),
        );
        return result.text;
      },
      parseJson: ai.parseJsonFromAiText,
      languageName: (lang) => ai.explanationLanguageName(lang as UiLang),
    },
    input,
  );
}

/**
 * `getWordExplanation` から、札を付けに行くか。画面に出し得る行（選んだ読む人の行と、同じ言語の共有の行 —
 * 図鑑から開いた詳細は共有の行を出す）の**どちらか**に、仕事が直せる物がある時だけ:
 * - 人が確かめた読む人の行は書き換えない（その行だけなら頼まない — 頼んでも直せず、開くたびに頼み直すだけ）
 * - AI を呼ぶ時（写せる札が無い）だけ、記録された AI の同意が要る。写す・掃除するだけなら要らない
 * - 自分の図鑑に在る語だけ
 * どれかが欠ければ頼まない（`labelPending` も立てない）。
 */
export async function shouldLabelMainExample(input: {
  userId: string;
  wordId: string;
  /** 選んだ読む人の行（無ければ null。在って extras が空の行も行として扱う）。 */
  reader: { extras: unknown; source?: string | null } | null;
  /** 共有の行（語の extras と source。言語は `lang` と比べる）。 */
  shared: { extras: unknown; source?: string | null } | null;
  /** 読む人の言語（共有の行が同じ言語で書かれている時だけ、共有の行も直す）。 */
  lang: string;
  word: { language: string | null; headword: string; example_sentence: string | null };
  consentStatus?: (userId: string) => Promise<{ agreed: boolean; recorded: boolean }>;
  owns?: (userId: string, wordId: string) => Promise<boolean>;
}): Promise<boolean> {
  const sentence = (input.word.example_sentence ?? "").trim();
  if (!sentence || !looksLikeTargetLanguage(sentence, input.word.language)) return false;
  const plan = planRepair(
    sentence,
    input.word.headword.trim(),
    readerView(input.reader),
    sharedView(input.shared, input.lang),
    input.lang,
  );
  if (!plan.readerTodo && !plan.sharedTodo) return false;
  if (plan.needAi) {
    const status = input.consentStatus
      ? await input.consentStatus(input.userId)
      : await (await import("./ai-consent.server")).getAiConsentStatus(input.userId);
    if (!status.recorded || !status.agreed) return false;
  }
  const owns =
    input.owns ??
    (async (userId: string, wordId: string) => {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      return ownsWord(supabaseAdmin, userId, wordId);
    });
  return owns(input.userId, input.wordId);
}

/**
 * 開発者の記録に数える失敗か。数えない: 同意が無い・その日の枠を使い切った（決まりどおりに止めた）、
 * 書く物が無かった（ほかの処理が先に書いた — 正しい動き。SQL の失敗は `applyRepair` が別に数える）。
 * 数える: AI の失敗・使えない札・読み書きの失敗など。
 */
export function isReportableFailure(reason: string): boolean {
  return !/AI_CONSENT_REQUIRED|AI_DAILY_CAP|nothing written/.test(reason);
}

/**
 * `getWordExplanation` から: 返事の後で札を付ける（返事は待たせない）。結果は記録に残すだけ。
 */
export async function scheduleMainExampleLabel(input: {
  userId: string;
  wordId: string;
  key: ExplanationKey;
}): Promise<void> {
  const { runAfterResponse } = await import("./after-response");
  await runAfterResponse(
    "getWordExplanation: label the main example",
    async () => {
      const r = await runMainExampleLabel(input);
      if (r.outcome === "labelled" || r.outcome === "tidied") {
        console.info(`labelMainExample: ${r.outcome}`, { word_id: input.wordId });
      } else if (r.outcome === "failed" && isReportableFailure(r.reason)) {
        await reportServerBackgroundFailure("scene_label", input.userId, new Error(r.reason), {
          where: "labelMainExample",
          word_id: input.wordId,
        });
      }
    },
    { timeoutMs: 1_000 },
  );
}
