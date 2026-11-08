import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { DEFAULT_TARGET_LANGUAGE, normalizeTargetLanguage } from "./target-lang";
import { targetProfile } from "./target-profile";
import { CATEGORY_KEYS, coerceCategoryKey, normalizeCategory } from "./category";
import { typedQueryMode } from "./typed-candidates";
import { looksLikeTargetLanguage } from "./text-language";
import { fitsReaderMeaning, fitsReaderNote } from "./first-catch-meaning";
import {
  LOOKUP_MAX_ENTRIES,
  LOOKUP_QUERY_MAX,
  LOOKUP_USAGES,
  LookupReplySchema,
  lookupQueryLine,
  normalizeLookup,
  type LookupEntry,
  type LookupMode,
} from "./dictionary-lookup";

/**
 * **しらべる（辞書）の口**。打った言葉 → 学習言語の見出し（1〜6語）と、AI にしか書けない
 * 字の成り立ち・使い分け・例文。決め事と検め方は `dictionary-lookup.ts`。
 *
 * 入力 `{ query, targetLanguage }` → `{ query, mode, entries: LookupEntry[] }`。
 * 速さを優先する（写真を読む速いモデル、出力は小さい形）。カードの中身（チャンク・関連語…）は
 * 図鑑に入れた後に今の単語の頁が作る。
 */
const LookupInput = z.object({
  query: z.string().trim().min(1).max(LOOKUP_QUERY_MAX),
  targetLanguage: z.string().default(DEFAULT_TARGET_LANGUAGE),
});

export type LookupResult = { query: string; mode: LookupMode; entries: LookupEntry[] };

export const lookupWord = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => LookupInput.parse(input))
  .handler(async ({ data, context }): Promise<LookupResult> => {
    // 外部の AI へ送る前の同意（`ai-consent.ts`）。無ければ何も送らずに断る。
    await (await import("./ai-consent.server")).assertAiConsent(context.userId);
    const provider = await import("./ai-provider.server");
    const targetLanguage = normalizeTargetLanguage(data.targetLanguage);
    const ai = await provider.getAiFor("scan", "word_lookup");
    await provider.assertWithinDailyCap(context.userId, "lookup");
    const [levelRule, langRule, reader] = await Promise.all([
      provider.levelInstruction(context.userId),
      provider.explanationLanguageRule(context.userId, targetLanguage),
      provider.getExplanationLanguage(context.userId),
    ]);
    const profile = targetProfile(targetLanguage);
    const readerName = provider.explanationLanguageName(reader);
    const mode: LookupMode = typedQueryMode(data.query, targetLanguage, reader);
    const target = profile.promptName;

    const prompt = `あなたは${target}を学ぶ人のための辞書です。学習者が「${data.query}」と打って引いた。

${lookupQueryLine({ query: data.query, mode, targetName: target, readerName })}
${levelRule}
${langRule}

見出しの選び方:
- **実際に${target}を話す人がその意味で一番よく使う語を1つ目**に置く。母語の1語が${target}で割れる時
  （指す物が違う・話し言葉と書き言葉・看板やメニューの言葉）だけ、よく使う順に2〜${LOOKUP_MAX_ENTRIES}語。
  一対一なら1語だけ。言い換えを水増ししない。作った語・ほとんど使わない語は出さない。
- ${profile.capture.scriptRule}。中国大陸でしか使わない言い方は出さない。
- 品詞は選ばない（動詞・形容詞・副詞・量詞も引ける）。1字では単独で言いにくい語は、単独で言う形を1つ目に。
- 店名・地名・ブランド・人名などの固有名詞は proper を true にする（一般の語と混同させない）。

1語ごとに書くこと（headword 以外は、上で決めた解説の言語で書く）:
- headword: ${target}の語だけ。注釈・括弧・ローマ字を付けない。
- pinyin / reading_zhuyin: 台湾の標準の読み（教育部の辞典の読み）。
- gloss: 一番中心の意味を、辞書の見出しのように短く（1〜4語・15字程度まで）。
- senses: gloss 以外によく使う意味があれば最大2つ（無ければ空）。
- usage: ${LOOKUP_USAGES.join(" / ")} のどれか1つ（everyday=会話でも文章でも / spoken=話し言葉 /
  written=書き言葉・ニュース / technical=専門の言葉 / sign=看板・メニュー・表示で見る言葉）。
- nuance: 2語以上挙げた時だけ。**ほかの候補の語を挙げて比べ**、どの場面でどれを使うか（30字程度）。1語なら空。
- chars: 2字以上の語は、**見出しの字を左から1字ずつ全部**、その字のこの語の中での意味（短く）。
- why: 2字以上の語は、字の意味がどう組み合わさってこの意味になるか（40字程度。こじつけない。
  字から分からない語・当て字・外来語の音訳はそう書く）。
- example: その語を含む、台湾の人が実際に言う短い一文（24字以内）。学習者のレベルに合わせる。
- example_translation: その文の自然な訳。
- image_query: その語を写真で探す短い英語（2〜4語）。形の無い語は意味が伝わる場面。
- category_key: ${CATEGORY_KEYS.join("/")} のどれか1つ（物でない語は other）。

確かな物だけを書く。分からない所は空にする（作らない）。
JSON だけを返す: {"entries":[{"headword":"…","pinyin":"…","reading_zhuyin":"…","gloss":"…","senses":[],"proper":false,"usage":"everyday","nuance":"","chars":[{"char":"…","meaning":"…"}],"why":"…","example":"…","example_translation":"…","image_query":"…","category_key":"…"}]}`;

    let raw = await provider.generateStructured({
      model: ai.gateway(ai.modelFast),
      schema: LookupReplySchema,
      prompt,
    });
    // 0件は「形が読めなかった」ことが多い（`.catch([])`）。形を言い直して1度だけ引き直す（数えるのは1回のまま）。
    if (raw.entries.length === 0) {
      raw = await provider.generateStructured({
        model: ai.gateway(ai.modelFast),
        schema: LookupReplySchema,
        prompt: `${prompt}\n\n前後に説明を書かず、{"entries":[…]} の JSON だけを返す。headword は${target}の語だけ。`,
      });
    }

    const fix = await import("./tw-reading.server").then((m) => m.correctTaiwanReading);
    const entries = normalizeLookup(raw, {
      query: data.query,
      mode,
      targetLanguage,
      checks: {
        meaning: (t) => fitsReaderMeaning(t, reader),
        note: (t) => fitsReaderNote(t, reader, targetLanguage),
        target: (t) => looksLikeTargetLanguage(t, targetLanguage),
      },
      fixReading: (headword, item) => fix(targetLanguage, headword, item),
      category: (headword, key) => normalizeCategory(headword, coerceCategoryKey(key)),
    });
    return { query: data.query, mode, entries };
  });
