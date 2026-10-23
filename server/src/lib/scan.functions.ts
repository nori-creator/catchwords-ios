import { NAME_REGISTERS, normalizeNameRegister } from "./candidate-register";
import { createServerFn } from "@tanstack/react-start";
import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";
import { keepTargetHeadwords } from "./target-language";
import {
  DICTIONARY_SELECT,
  resolveDictionaryFields,
  type RawDictionaryRow,
} from "./dictionary-entry";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { generateText } from "ai";
import { z } from "zod";
import { isNounLike } from "./pos";
import { fitsReaderMeaning } from "./first-catch-meaning";
import {
  assertWithinDailyCap,
  forFeature,
  getAi,
  getAiFor,
  measuredAi,
} from "./ai-provider.server";
import { normalizeDetection } from "./scan-detect-parse";
import { readAllPages } from "./pagination";
import { targetProfile, type CoachPhrases } from "./target-profile";

/**
 * Scan-First MVP §3.2 — one AI call combines object detection + OCR and returns
 * a fixed JSON. The client draws dots at normalized coords (0..1000). We also
 * record every result into scan_events (§3.7) so "調べたが保存しなかった語" can
 * resurface later.
 */

const DetectInput = z.object({
  // Cap ~8MB base64 (~6MB raw) to prevent cost/memory abuse via AI vision calls.
  imageBase64: z.string().min(100).max(8_000_000), // data URL or raw base64
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
  /**
   * 画面が**保存に使う**学習言語（端末の設定）。
   *
   * 前は渡しておらず、ここはプロフィールの学習言語で AI に頼んでいた。
   * ところが画面は端末の学習言語で保存する — 2つが食い違うと、
   * 台湾華語で見つけた「拿鐵」が英語の語として保存される
   * （オーナー報告 2026-10-02）。渡されたらそれに合わせる。
   * iOS 版など渡さない呼び出しは、これまでどおりプロフィールを読む。
   */
  targetLanguage: z.string().max(16).optional(),
});

const DetectItemSchema = z.object({
  kind: z.enum(["object", "text"]),
  headword: z.string().min(1),
  zhuyin: z.string().default(""),
  pinyin: z.string().default(""),
  meaning_ja: z.string().default(""),
  pos: z.string().default(""),
  point: z.tuple([z.number(), z.number()]),
  confidence: z.number().min(0).max(1).default(0.8),
  alternatives: z.array(z.string()).default([]),
  /**
   * どんな言い方か（`candidate-register.ts` の5つ、2026-10-15 — どの候補にも必ず付ける）。スキャンは
   * 写っている物ごとに1語（ふだんの名前）なので、無い・読めない時は一般的な言い方。
   */
  register: z.preprocess(
    (v) => normalizeNameRegister(v) ?? undefined,
    z.enum(NAME_REGISTERS).catch("common"),
  ),
});

export type DetectedItem = z.infer<typeof DetectItemSchema> & { id: string };

export type DictionaryEntry = {
  headword: string;
  /**
   * 既定の読み。**名前は古いまま**だが、中身は学習言語の読み
   * (台湾華語は注音、英語はアメリカ英語の IPA)。
   * 引くときに `reading_primary` から読み直している
   * (`dictionary-entry.ts` の注)。
   */
  zhuyin: string | null;
  /** 第二の読み(台湾華語は拼音、英語はイギリス英語寄りの IPA)。 */
  pinyin: string | null;
  /** 読む人の言語での意味。**合う言語が無ければ空**。 */
  meaning_ja: string;
  pos: string | null;
  tocfl_level: number | null;
  /** CEFR / TOCFL の段。**`null` は級外**(級が付いていない語)。 */
  level_step: number | null;
  audio_path: string | null;
  /** Signed URL for the pre-generated audio (§4.3). Play directly — no TTS round trip. */
  audio_url: string | null;
  source: string | null;
  entry_type: string | null;
};

function parseJsonFromAiText(text: string): unknown {
  const trimmed = text.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) return JSON.parse(fenced[1]);
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) return JSON.parse(trimmed.slice(start, end + 1));
  return JSON.parse(trimmed);
}

/**
 * 検出の指示文。**言語で変わる所だけ**を学習言語の表(`coach`)から入れる
 * (2026-10-01、日本語を足した日)。台湾華語の値で組むと、いままでの文と1文字も違わない。
 */
const scanPrompt = (
  coach: CoachPhrases,
) => `あなたは${coach.scanEngineLabel}の学習アプリの検出エンジンです。
入力画像から、学習価値のある「モノ (kind=object)」と「写っている文字 (kind=text)」を検出してください。

厳守ルール:
- 出力は下記スキーマに厳密に従うJSONオブジェクトのみ。前置き・後書き・コードフェンス禁止。
- ${coach.scanScriptRule}
- 学習者のレベルに合う語を優先(下の「レベル指示」に従う)。学習価値の低いもの(壁・空・地面など)は返さない。
- kind=text は看板・メニュー・商品ラベルなど「写っている文字そのもの」。推測で足したり書き換えたりしない。
- point は画像を 0〜1000 に正規化した座標 [x, y]。**必ずその物体の見えている塊の重心**に置く
  (左上が [0,0]、右下が [1000,1000]、x=横、y=縦。x と y を絶対に入れ替えない)。
  **座標の精度がこの機能の価値そのもの**です。以下を必ず守ってください:
  - まず対象の外接矩形を頭の中で決め、その中心を point にする。輪郭の外・背景・
    隣の物体の上に置くのは誤り。細長い物(傘・箸・看板)は中央付近を指す。
  - 対象が部分的に隠れている場合は「見えている部分」の中心。
  - 複数個写っている物(りんごが3つ等)は、最も大きく写っている個体の中心1点だけ。
  - 画像の端(x<40 / x>960 / y<40 / y>960)にはほぼ置かない — 端に見切れている物は
    そもそも学習対象にしない。
  - 2つの item が近すぎる(距離が 60 未満)場合は、別の物体か確認し、同じ物なら1つに統合する。
  - 置いた後に自己検証: 「その座標をペンで刺したら、本当にその物に当たるか?」
    当たらないなら座標を修正、それでも自信が無ければ confidence を 0.6 以下にする。
- confidence は 0〜1。**語の同定と座標の両方**に自信がある時だけ 0.9 以上。
  どちらかが曖昧なら 0.75 未満にし、alternatives に紛らわしい候補を1〜2個入れる。
- items は最大 6 個。**数より正確さ**: 座標に自信が持てるものだけを返す
  (曖昧な物を無理に足すより、確実な4個の方が良い)。大きく写っている・
  学習価値の高いものを優先。
- ${coach.scanReadingRule}
- **名詞だけを返す。** 動詞・形容詞・副詞・量詞は出さない。写真に写っている
  「物」の名前だけを挙げる。

出力スキーマ:
{
  "items": [
    {
      "kind": "object" | "text",
${coach.scanSample}
      "pos": "名詞",
      "point": [512, 340],
      "confidence": 0.93,
      "alternatives": [],
      "register": "common"
    }
  ]
}
register は ${NAME_REGISTERS.join(" / ")} のどれか（headword はその言語を話す人がふだんその物を呼ぶ一般的な言い方 = common にする）。`;

export const detectScan = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => DetectInput.parse(input))
  .handler(async ({ data, context }) => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らずに断る。
    await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const ai = await getAiFor("scan", "scan_detect");
    const { supabase, userId } = context;
    await assertWithinDailyCap(userId, "scan_detect");
    const { levelInstruction, explanationLanguageRule } = await import("./ai-provider.server");
    const { getUserTargetLanguage } = await import("./ai-provider.server");
    const target = data.targetLanguage
      ? normalizeTargetLanguage(data.targetLanguage)
      : await getUserTargetLanguage(userId);
    const levelRule = await levelInstruction(userId);
    const langRule = await explanationLanguageRule(userId, target);

    const imageInput = data.imageBase64.startsWith("data:")
      ? data.imageBase64
      : `data:image/jpeg;base64,${data.imageBase64}`;

    const t0 = Date.now();
    const coach = targetProfile(target).coach;
    const prompt = `${scanPrompt(coach)}\n\nレベル指示: ${levelRule}\n${langRule}`;
    const ask = async (cfg: typeof ai) => {
      const r = await generateText({
        model: cfg.gateway(cfg.modelFast),
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image", image: imageInput },
            ],
          },
        ],
        abortSignal: AbortSignal.timeout(25_000),
      });
      let raw: unknown;
      try {
        raw = parseJsonFromAiText(r.text);
      } catch {
        raw = null;
      }
      const items = normalizeDetection(raw);
      if (!items) throw new Error("AI did not return valid detection JSON");
      return items;
    };
    /**
     * **1回失敗したら、既定の AI でもう1回。**（オーナー報告 2026-09-23「検出に
     * 失敗と出る」）開発者が設定でスキャンに別の AI（OpenRouter など）を選んで
     * いると、その AI が画像を読めない・止まっている・形の違う返事をする、で
     * スキャンが丸ごと止まっていた。既定と同じ設定のときはやり直さない
     * （同じ物に同じことを頼んでも結果は同じ）。
     */
    let found: Awaited<ReturnType<typeof ask>>;
    try {
      found = await ask(ai);
    } catch (first) {
      const base = await Promise.resolve()
        .then(() => measuredAi(forFeature(getAi(), "scan"), "scan", "scan_detect"))
        .catch(() => null);
      const same =
        !base ||
        ((base.name ?? base.provider) === (ai.name ?? ai.provider) &&
          base.modelFast === ai.modelFast);
      console.warn(`[scan] detect failed with ${ai.modelFast}: ${(first as Error).message}`);
      if (same) throw new Error(`scan detect failed: ${(first as Error).message}`);
      try {
        found = await ask(base);
      } catch (second) {
        throw new Error(`scan detect failed: ${(second as Error).message}`);
      }
    }
    const parsed = { items: found };

    // **返ってきた物を実際に絞る。** プロンプトには「名詞だけ」と書いてあるが、
    // 書いてあることと返ってくる物は別(この app で何度も踏んでいる)。
    //
    // ## なぜ名詞だけなのか(オーナー指示 2026-08-20)
    // 一時期は「湯気の立つ麺→熱」のように状態・動作も1〜2個足していた。
    // だが**カードに載せる絵を用意できるのは物だけ**で、動詞のカードは
    // 写真が撮れず、絵の無いカードが図鑑に混ざる。
    // ネットの画像・動画・GIF を引く経路と生成の経路ができてから、
    // 他の品詞に広げる。それまでは名詞に絞る。
    //
    // ※ここは**写真に写った物**の候補。人が打ち込んだ言葉の候補
    // (ai.functions.ts の suggestWordCandidates)は別で、そちらは品詞を
    // 絞らない — 「走る」と打った人に候補が1つも返らなくなるため。
    //
    // 品詞の札が無いものは通す — 分からないことを理由に捨てない。
    parsed.items = parsed.items.filter((it) => isNounLike(it.pos));
    /**
     * **学習言語の字の語だけを返す**（オーナー報告 2026-10-02「英語の復習に
     * 拿鐵の4択」）。写っている文字（kind=text）は「書き換えない」約束なので、
     * 台湾の店のメニューを写すと、英語を学ぶ人にも「拿鐵」がそのまま返る。
     * 画面はそれを学習言語の語として保存していた。言い換えの候補
     * （`alternatives`）も同じ関所に通す。
     */
    parsed.items = keepTargetHeadwords(parsed.items, target);
    // 意味は読む人の言語（下の `detectParts` と同じ）。**別の言語で返った意味は空にしてから**、控え・辞書・
    // 画面に渡す（控えには意味の言語の目印を付けるので、目印と中身が食い違う控えを作らない）。
    const scanReader = await (await import("./ai-provider.server")).getExplanationLanguage(userId);
    parsed.items = parsed.items.map((it) =>
      fitsReaderMeaning(it.meaning_ja, scanReader) ? it : { ...it, meaning_ja: "" },
    );

    /**
     * 見つけた語の意味と読みを控える（監査 2026-10-03 M3、`generated-cards.ts`）。
     * かざして拾った語を保存すると、新しい共有の語の行はこの控え（か辞書）から中身を取る
     * — 画面の送った文は使わない。返事は待たせない。
     */
    if (parsed.items.length > 0) {
      const { runAfterResponse } = await import("./after-response");
      const items = parsed.items;
      await runAfterResponse("scan: record candidate receipts", async () => {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { recordGeneratedCards, candidateCard } = await import("./generated-cards");
        await recordGeneratedCards(
          supabaseAdmin,
          items.map((it) => ({
            language: target,
            headword: it.headword,
            kind: "candidate" as const,
            card: candidateCard(
              { meaning_ja: it.meaning_ja, reading_zhuyin: it.zhuyin, pinyin: it.pinyin },
              scanReader,
            ),
          })),
        );
      });
    }

    // 自動で貯まる共有辞書: AIが今調べた読み・意味を蓄積(fire-and-forget)。
    // 次のスキャンからは辞書ヒット=AI再問い合わせゼロで即表示になる。
    // ついでに1日1回の自己改善(辞書監査+ニュースコーパス観察)も起動。
    // 意味は読む人の言語で返ってくる。日本語だけが辞書の `meaning_ja`、ほかの言語は `meanings[言語]`（2026-10-15）。
    void import("./lexicon.server").then(async (m) => {
      void m.learnLexiconEntries(parsed.items, scanReader);
      void m.maybeRunDailySelfImprovement(userId);
    });

    // §7 measurement: server-side detection latency (AI call + parse).
    // The client's full scan→dots number additionally includes upload+render.
    const detectMs = Date.now() - t0;

    // §3.7 record every detected item as a scan_event (tapped=false initially)
    if (parsed.items.length > 0) {
      const rows = parsed.items.map((it) => ({
        user_id: userId,
        headword: it.headword,
        meaning_ja: it.meaning_ja || null,
        kind: it.kind,
        confidence: it.confidence,
        tapped: false,
        caught: false,
        lat: data.lat ?? null,
        lng: data.lng ?? null,
        detect_ms: detectMs,
      }));
      const { error: insErr } = await supabase.from("scan_events").insert(rows);
      if (insErr && /detect_ms/.test(insErr.message)) {
        // Migration not applied yet — keep the funnel log working without the column.
        await supabase.from("scan_events").insert(rows.map(({ detect_ms: _detectMs, ...r }) => r));
      }
    }

    const items: DetectedItem[] = parsed.items.map((it, i) => ({
      ...it,
      id: `${Date.now()}_${i}`,
    }));
    return { items };
  });

/**
 * §3.5 「+細かく」 on-demand hierarchical detection. The client crops a region
 * around a previously-tapped object (e.g. 手) and sends it in; we ask the fast
 * model to enumerate *parts* of that thing (拇指 / 手掌 / 指甲) with normalized
 * coords **within the cropped region**. The client maps them back into the
 * parent frame. Kept as a second call so the initial scan stays fast.
 */
const DetectPartsInput = z.object({
  imageBase64: z.string().min(100).max(8_000_000),
  parentHeadword: z.string().min(1).max(40),
});

export const detectParts = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => DetectPartsInput.parse(input))
  .handler(async ({ data, context }) => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らずに断る。
    await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const ai = await getAiFor("scan", "scan_parts");
    await assertWithinDailyCap(context.userId, "scan_parts");
    const imageInput = data.imageBase64.startsWith("data:")
      ? data.imageBase64
      : `data:image/jpeg;base64,${data.imageBase64}`;

    // 言語・字・例は学習言語の表から(`coach`)。台湾華語の値はいままでの文そのもの。
    const { getUserTargetLanguage, explanationLanguageRule, getExplanationLanguage } =
      await import("./ai-provider.server");
    const partsTarget = await getUserTargetLanguage(context.userId);
    const coach = targetProfile(partsTarget).coach;
    // **意味（meaning_ja）は読む人の言語で**（2026-10-20: 見本の値が日本語の「親指」だけで、指示が無かった。
    // スペイン語・韓国語・ベトナム語の読み手に日本語の意味が返り、その言語の辞書に入っていた）。
    const [partsLangRule, partsReader] = await Promise.all([
      explanationLanguageRule(context.userId, partsTarget),
      getExplanationLanguage(context.userId),
    ]);
    const prompt = `画像には「${data.parentHeadword}」が写っています。この物体を構成する**部分・要素**の名称を、${coach.partsLanguage}で学習価値のあるものだけ最大6個抽出してください。
- ${partsLangRule}（meaning_ja はその言語の短い訳語。見本の値の言語につられない）
- 全体名(${data.parentHeadword})は含めない
- 部位・部品・素材・付随物のみ(例: ${coach.partsExample})
- point は切り取られた画像内での中心座標を 0〜1000 に正規化した [x, y]
- ${coach.partsRule}
- 出力はJSONのみ、前置き/コードフェンス禁止

出力スキーマ:
{"items":[{"kind":"object",${coach.partsSample},"pos":"名詞","point":[420,510],"confidence":0.9,"alternatives":[]}]}`;

    let text = "";
    try {
      const r = await generateText({
        model: ai.gateway(ai.modelFast),
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image", image: imageInput },
            ],
          },
        ],
      });
      text = r.text;
    } catch (e) {
      throw new Error(`detect parts failed: ${(e as Error).message}`);
    }

    // 検出と同じく寛容に読む（1か所の形の違いで全部を捨てない）。
    let raw: unknown = null;
    try {
      raw = parseJsonFromAiText(text);
    } catch {
      /* 下で null として扱う */
    }
    const partItems = normalizeDetection(raw);
    if (!partItems) throw new Error("AI did not return valid parts JSON");
    const parsed = { items: partItems };

    // 部品の候補も名詞だけ(上の検出と同じ約束)。学習言語の字の語だけ(同じく)。
    parsed.items = keepTargetHeadwords(
      parsed.items.filter((it) => isNounLike(it.pos)),
      partsTarget,
    );
    // 意味は読む人の言語（日本語だけが辞書の `meaning_ja`。上の `detectScan` と同じ）。**別の言語で返った意味は
    // 空にしてから**辞書と画面に渡す（その言語の辞書に別の言語の意味を貯めない）。
    parsed.items = parsed.items.map((it) =>
      fitsReaderMeaning(it.meaning_ja, partsReader) ? it : { ...it, meaning_ja: "" },
    );
    void import("./lexicon.server").then(({ learnLexiconEntries }) =>
      learnLexiconEntries(parsed.items, partsReader),
    );

    // Also log parts into scan_events so recollection notifications can surface them.
    if (parsed.items.length > 0) {
      await context.supabase.from("scan_events").insert(
        parsed.items.map((it) => ({
          user_id: context.userId,
          headword: it.headword,
          meaning_ja: it.meaning_ja || null,
          kind: it.kind,
          confidence: it.confidence,
          tapped: false,
          caught: false,
        })),
      );
    }

    const items: DetectedItem[] = parsed.items.map((it, i) => ({
      ...it,
      id: `part_${Date.now()}_${i}`,
    }));
    return { items };
  });

/**
 * Bulk lookup for detected headwords against the verified dictionary (§4.2).
 * Returns a map keyed by headword so the client can decorate chips with the
 * "✓ 検証済み" badge and prefer DB values over AI output.
 */
export const lookupHeadwords = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        headwords: z.array(z.string()).max(20),
        language: z.string().default(DEFAULT_TARGET_LANGUAGE),
        /**
         * 解説を読む人の言語。`meanings` の鍵はこれ。
         * **既定を日本語にしない道は無い** — 古い `meaning_ja` の
         * 受け皿がその言語だけなので、既定はここに合わせる。
         */
        explain_lang: z.string().default("ja"),
      })
      .parse(input),
  )
  .handler(async ({ data, context }) => {
    const words = Array.from(new Set(data.headwords.map((s) => s.trim()).filter(Boolean)));
    const empty: Record<string, DictionaryEntry> = {};
    if (words.length === 0) return { entries: empty };
    // 型の当てはめ。列の並びを定数にすると supabase の型が読めなくなるので、
    // ここで**1度だけ**形を言う(読み直しは `dictionary-entry.ts`)。
    type Row = RawDictionaryRow & {
      headword: string;
      pos: string | null;
      audio_path: string | null;
      source: string | null;
      entry_type: string | null;
    };
    const { data: rows, error } = await context.supabase
      .from("dictionary_entries")
      // 列の並びは `dictionary-entry.ts` が持つ。**1箇所に書く** —
      // 並びと読み直しが別々の場所にあると、列を足したとき片方だけ直る。
      .select(DICTIONARY_SELECT)
      .eq("language", data.language)
      .in("headword", words)
      .overrideTypes<Row[]>();
    if (error) throw new Error(error.message);

    // §4.3: pre-generated audio is served straight from Storage. Sign all
    // audio paths in one call so tap→audio start needs zero further requests.
    // **いまの声で作った音だけ**を渡す。開発者が声を変えた後、前の声で作り置いた
    // 音を渡すと古い声が鳴り続ける（その語はタップ時に新しい声で作られる）。
    const { currentVoiceTag } = await import("./tts-provider.server");
    const voicePrefix = `${data.language}/${await currentVoiceTag(data.language)}/`;
    const paths = (rows ?? [])
      .map((r) => r.audio_path)
      .filter((p): p is string => !!p && p.startsWith(voicePrefix));
    const urlByPath = new Map<string, string>();
    if (paths.length > 0) {
      const { data: signed } = await context.supabase.storage
        .from("tts")
        .createSignedUrls([...new Set(paths)], 60 * 60 * 6);
      for (const row of signed ?? []) {
        if (row.path && row.signedUrl && !row.error) urlByPath.set(row.path, row.signedUrl);
      }
    }

    const map: Record<string, DictionaryEntry> = {};
    for (const r of rows ?? []) {
      // **読む人の言語で読み直す。** 英語の行は新しい列にしか入って
      // いないので、ここを通さないと読みも意味も空で返る
      // (辞書だけでカードを出す道が英語で丸ごと死んでいた)。
      const f = resolveDictionaryFields(r, data.explain_lang);
      map[r.headword] = {
        headword: r.headword,
        zhuyin: f.reading,
        pinyin: f.readingAlt,
        meaning_ja: f.meaning,
        pos: r.pos ?? null,
        tocfl_level: r.tocfl_level ?? null,
        level_step: f.levelStep,
        audio_path: r.audio_path ?? null,
        audio_url: r.audio_path ? (urlByPath.get(r.audio_path) ?? null) : null,
        source: r.source ?? null,
        entry_type: r.entry_type ?? null,
      };
    }
    return { entries: map };
  });

/**
 * §3.1b dot-state context: the user's own cards + previously tapped words,
 * fetched once per scan session and matched client-side (zero AI calls).
 * Headwords are NFC-normalized so 你/你 variants from different sources match.
 */
export type ScanContextEntry = {
  sticker_id: string;
  has_photo: boolean;
  found_at: string;
};

export type ScanContext = {
  owned: Record<string, ScanContextEntry>;
  tapped: string[];
};

const normHeadword = (s: string) => s.normalize("NFC").trim();

export const getScanContext = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<ScanContext> => {
    const { supabase, userId } = context;
    // **PostgREST は1回に1000行で切る**（2026-10-03 監査）。`.limit(2000)` / `.limit(3000)`
    // でも 1000 行しか来ず、1000 語を超えて集めた人には「もう持っている語」が
    // 新しく見えていた。全部 `readAllPages` で 1000 行ずつ読む（古い順は変えない）。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabase as any;
    const readStickers = (cols: string) =>
      readAllPages<unknown>((a, b) =>
        db
          .from("stickers")
          .select(cols)
          .eq("user_id", userId)
          .order("created_at", { ascending: true })
          .order("id")
          .range(a, b),
      );
    const [stickerRows, tapRes] = await Promise.all([
      readStickers(
        "id, created_at, capture_type, cutout_image_url, object_image_url, words(headword)",
      ).catch((e: unknown) => {
        // Migration not applied yet — every sticker is a photo catch then.
        if (e instanceof Error && /capture_type/.test(e.message))
          return readStickers(
            "id, created_at, cutout_image_url, object_image_url, words(headword)",
          );
        throw e;
      }),
      readAllPages<{ headword: string }>((a, b) =>
        db
          .from("scan_events")
          .select("headword")
          .eq("user_id", userId)
          .eq("tapped", true)
          .order("created_at", { ascending: false })
          .order("id")
          .range(a, b),
      ),
    ]);

    const owned: Record<string, ScanContextEntry> = {};
    type Row = {
      id: string;
      created_at: string;
      capture_type: string | null;
      cutout_image_url: string | null;
      object_image_url: string | null;
      words: { headword: string } | null;
    };
    for (const r of stickerRows.rows as Row[]) {
      if (!r.words?.headword) continue;
      const key = normHeadword(r.words.headword);
      const hasPhoto =
        (r.capture_type ?? "photo") === "photo" || !!r.cutout_image_url || !!r.object_image_url;
      const prev = owned[key];
      // Keep the earliest sticker; a photo on any sticker counts as captured.
      if (!prev) {
        owned[key] = { sticker_id: r.id, has_photo: hasPhoto, found_at: r.created_at };
      } else if (hasPhoto && !prev.has_photo) {
        prev.has_photo = true;
      }
    }

    const tapped = [...new Set(tapRes.rows.map((r) => normHeadword(r.headword)))];
    return { owned, tapped };
  });

export const markScanTap = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        headword: z.string().min(1).max(100),
        tap_to_audio_ms: z.number().int().nonnegative().optional(),
      })
      .parse(input),
  )
  .handler(async ({ data, context }) => {
    // Best-effort: flip the most recent matching scan_event to tapped=true.
    const { data: rows } = await context.supabase
      .from("scan_events")
      .select("id")
      .eq("user_id", context.userId)
      .eq("headword", data.headword)
      .order("created_at", { ascending: false })
      .limit(1);
    const id = rows?.[0]?.id;
    if (id) {
      const patch: { tapped: boolean; tap_to_audio_ms?: number } = { tapped: true };
      if (data.tap_to_audio_ms != null) patch.tap_to_audio_ms = data.tap_to_audio_ms;
      const { error } = await context.supabase.from("scan_events").update(patch).eq("id", id);
      if (error && /tap_to_audio_ms/.test(error.message)) {
        await context.supabase.from("scan_events").update({ tapped: true }).eq("id", id);
      }
    }
    return { ok: true };
  });

export const markScanCaught = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z.object({ headword: z.string().min(1).max(100) }).parse(input),
  )
  .handler(async ({ data, context }) => {
    const { data: rows } = await context.supabase
      .from("scan_events")
      .select("id")
      .eq("user_id", context.userId)
      .eq("headword", data.headword)
      .order("created_at", { ascending: false })
      .limit(1);
    const id = rows?.[0]?.id;
    if (id)
      await context.supabase
        .from("scan_events")
        .update({ tapped: true, caught: true })
        .eq("id", id);
    return { ok: true };
  });
