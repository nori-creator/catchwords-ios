import { refineUsageChunks, usableCollocations, type WordExtrasDTO } from "./extras";
import { looksLikeTargetLanguage } from "./text-language";
import { targetProfile, type ProfileSection } from "./target-profile";

/**
 * 語のカードの節。**画面と生成側で1つの出所を共有する。**
 *
 * ## なぜ切り出したか
 * 「作り直せる節」の一覧が `WordCard.tsx` と `ai.functions.ts` の
 * **2箇所に別々に書かれていた**。片方だけに足すと、
 *   ・画面にだけ足す → 「作る」を押せるのに server が弾く
 *   ・server にだけ足す → 作れるのにボタンが出ない
 * どちらも**エラーにならず、押した人にだけ起きる**。
 * `quick_facts` を足したときは両方に手で書いて、たまたま合っていた。
 * たまたま合うものは、いつか合わなくなる。
 */

/**
 * カードに並ぶ節の**全部**(どの学習言語のカードにも出うる物の集合)。
 *
 * ## 順序はここでは決めない
 * 既定の並びは `target-profile.ts` の `sections` が言語ごとに持っている。
 * ここは**存在の定義**だけ — 「この名前の節がある」という一覧。
 *
 * ## 言語ごとに出る物が違う
 *   台湾華語だけ … `measure_words`(量詞) / `taiwan_note`
 *   英語だけ     … `forms` / `countability` / `stress` /
 *                  `phrasal_verbs` / `culture_note`
 *   日本語だけ   … `kanji_breakdown` / `pitch_accent` / `conjugation` /
 *                  `politeness` / `counters` / `word_origin` / `japan_note`
 * どちらに出るかを `if (lang === …)` で書かない。`sectionsFor()` を通す。
 */
export const SECTION_IDS = [
  // --- どの言語のカードにも出る -------------------------------------------
  "meaning",
  "web_images",
  "example",
  "examples_extra",
  "usage_chunks",
  "related_words",
  "pronunciation_tips",
  "etymology",
  "mnemonic",
  "real_usage",
  // --- 台湾華語のカードだけ -----------------------------------------------
  "measure_words",
  "taiwan_note",
  // --- 英語のカードだけ ---------------------------------------------------
  "forms",
  "countability",
  "stress",
  "phrasal_verbs",
  "culture_note",
  // --- 日本語のカードだけ(2026-10-01) -------------------------------------
  "kanji_breakdown",
  "pitch_accent",
  "conjugation",
  "politeness",
  "counters",
  "word_origin",
  "japan_note",
] as const;

export type SectionId = (typeof SECTION_IDS)[number];

/**
 * **どの言語のカードにも並べない節**（オーナー指示 2026-10-02「ネットの画像・追加の例文・
 * 発音のコツ・覚え方の項目を消して」）。
 *
 * 名前は `SECTION_IDS` に残す。保存済みのカードの中身と、作り直しの窓口
 * （`REGEN_SECTIONS`、iOS 版も呼ぶ）の型がこの名前を使っているため。
 * 戻すときは `target-profile.ts` の各言語の `sections` に足し、ここから外す。
 */
export const RETIRED_SECTIONS: readonly SectionId[] = [
  "web_images",
  "examples_extra",
  "pronunciation_tips",
  "mnemonic",
  // 語源・部首（オーナー決定 2026-10-15「語源・部首の項目を消して」。サーバも作らない — `NOT_GENERATED_SECTIONS`）。
  "etymology",
];

/**
 * **サーバがもう作らない節**（オーナー決定 2026-10-15「発音のコツと覚え方はサーバで作らない」、
 * 同日「語源・部首の項目を消して」）。
 *
 * カード生成の指示から外し（トークンを使わない）、節ごとの作り直し（`regenerateCardSection`）は AI を呼ばずに
 * 空で返す。iOS 1.0.0 など古い版は空の節を自動で埋めに来るので、口は残したまま何もしない。
 * `sectionNeedsFill` も「埋める必要なし」と答える（作り直しの引き金にしない）。保存済みのカードの中身は消さない。
 *
 * 語源の節（`etymology`）は欄が4つ: `etymology`（文）/ `etymology_relatives` / `radicals` / `etymology_diagram`
 * （`card-request.ts` の `OPTIONAL_EXTRA_KEYS`）。日本語のカードの `kanji_breakdown` / `word_origin` は別の節で、
 * ここには入れていない（頼まれたのは 語源・部首 の節だけ）。
 */
export const NOT_GENERATED_SECTIONS: readonly SectionId[] = [
  "pronunciation_tips",
  "mnemonic",
  "etymology",
];

/** サーバがもう作らない節か（`NOT_GENERATED_SECTIONS`）。 */
export function isNotGeneratedSection(id: string): boolean {
  return (NOT_GENERATED_SECTIONS as readonly string[]).includes(id);
}

/**
 * その学習言語のカードに出る節を、**その言語の並び順で**返す。
 *
 * 出所は `target-profile.ts` の `sections` ただ1つ。画面の既定の並びも、
 * 裏で順に作る仕組みも、設定の並べ替えの一覧も、全部ここを通る。
 *
 * **`ProfileSection` と `SectionId` は同じ物を指す2つの名前**で、
 * 片方に足して片方に足し忘れると型が合わなくなる — それを狙っている
 * (`card-sections.test.ts` が両者の集合が一致することも数えている)。
 */
export function sectionsFor(lang: string | null | undefined): readonly SectionId[] {
  return targetProfile(lang).sections;
}

/**
 * **`SectionId` と `ProfileSection` が1文字も違わないことを、型で確かめる。**
 *
 * 同じ物の名前が2つある(片方は値の並び、片方は言語ごとの一覧の型)。
 * 循環 import になるので1つにまとめられないが、**片方だけに足す**のは
 * この app が何度もやった形なので、足りない側で `tsc` が落ちるようにする。
 * どちらの向きも見る — `sectionsFor` の戻り型だけでは片側しか守れない。
 */
type Assert<T extends true> = T;
type Same<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;

type _SectionNamesMatch = Assert<Same<SectionId, ProfileSection>>;

/**
 * AI で作り直せる節。外部リンク系(`web_images` / `real_usage`)は
 * 生成物ではないので入らない。
 */
export const REGEN_SECTIONS = [
  "meaning",
  "example",
  "examples_extra",
  "usage_chunks",
  "measure_words",
  "related_words",
  "pronunciation_tips",
  "etymology",
  "mnemonic",
  "taiwan_note",
  // --- 英語のカードの節 ---------------------------------------------------
  // **`forms` はここに入らない。** 語形は ECDICT から入る辞書の事実で、
  // AI に作らせる物ではない。作らせると "child" の複数形が "childs" に
  // なり得るし、待ち時間とお金を、既に手元にある答えのために払うことになる。
  "countability",
  "stress",
  "phrasal_verbs",
  "culture_note",
  // --- 日本語のカードの節 -------------------------------------------------
  // 英語の `forms` と違い、**活用も AI に作らせる。** 日本語の活用を引ける
  // 辞書の取り込みがまだ無いので、作り直せないと節が空のまま残る。
  // 活用は規則で決まるので、作らせても誤りにくい(指示文で辞書形からの形を名指しする)。
  "kanji_breakdown",
  "pitch_accent",
  "conjugation",
  "politeness",
  "counters",
  "word_origin",
  "japan_note",
] as const;

export type RegenSection = (typeof REGEN_SECTIONS)[number];

/**
 * その節が AI で作り直せるか。
 *
 * **型を絞る形で書く。** `REGEN_SECTIONS.includes(id)` を直に書くと、
 * `id` が広い型のままなので、server に渡す所で型が合わなくなる
 * (合わせるためにキャストを置くと、食い違いを検査で捕まえられなくなる)。
 */
export function isRegenSection(id: SectionId): id is RegenSection {
  return (REGEN_SECTIONS as readonly string[]).includes(id);
}

/**
 * その節に**中身があるか**。
 *
 * ## なぜ画面から出したか
 * この判定は `WordCard.tsx` の中にあって、画面だけが知っていた。
 * 裏で項目を順に作る仕組み(オーナー指摘「候補を選択した瞬間から裏で
 * 単語の詳細のすべての項目を作り始めてる。項目の上から順に」)を足すと、
 * **server も「この節はまだ空か」を知る必要がある**。同じ問いに2つの答えが
 * あると、server が「空だ」と言い続けて作り直し、画面は「埋まっている」と
 * 言い続ける — 止まらない生成になる。判定はここ1つにする。
 *
 * ## 描く条件と数える条件を必ず一致させる
 * 過去に2回、数え方と描き方がずれて**見出しだけの空の節**が出た
 * (`usage_chunks` と `usage_context`)。中身の有無は「Body が実際に何かを
 * 描くか」で決める。
 */
export type SectionContentInput = {
  headword: string;
  /**
   * その語の学習言語。
   *
   * **例文が「その言語で書かれているか」まで見るのに要る**（オーナー報告
   * 2026-08-26、3度目「例文や単語の変化が回答が生成されてないのに項目が
   * 表示されてる」）。学習言語の写しが既定へ戻る隙間に作られたカードには
   * 英語の語を中国語の文へ埋めた例文が入っていて、画面はそれを
   * `looksLikeTargetLanguage` で落としていた。ところが**数える側は
   * 落としていなかった**ので、
   *
   *   数える側 …「例文は在る」→ 作り直しに来ない
   *   描く側   …「この文は出せない」→ 何も描かない
   *
   * となり、**見出しだけの空の節**が残った。これは上の注が
   * 「過去に2回やった」と書いてある形そのもの（3度目）。
   */
  language?: string | null;
  meaning_ja?: string | null;
  example_sentence?: string | null;
  /** `normalizeExtras` を通した extras。 */
  extras: WordExtrasDTO | null;
};

export function sectionHasContent(id: SectionId, input: SectionContentInput): boolean {
  const ex = input.extras ?? ({} as WordExtrasDTO);
  switch (id) {
    case "meaning":
      return !!input.meaning_ja;
    case "example":
      // **学習言語で書かれていない文は「無い」。** 描く側と同じ判定
      // (`WordCard.tsx` の `case "example"`)。片方だけに入れると
      // 見出しだけの空の節が残る。
      return (
        !!input.example_sentence && looksLikeTargetLanguage(input.example_sentence, input.language)
      );
    case "examples_extra":
      return (ex.examples_extra ?? []).some((e) => looksLikeTargetLanguage(e?.zh, input.language));
    case "usage_chunks":
      /**
       * **描く側と1文字も違わせない**(オーナー指摘 2026-08-27 ②)。
       *
       * ここは `ex.word_order`(語順の解説文)が在れば「中身が在る」と
       * 数えていた。描く側もそれを `<Prose>` で流していたので、
       * **かたまりの節に解説の段落が出る**。「文章を表示したいのでは
       * ない」との指摘そのもの。描く側から段落を外したので、
       * 数える側からも外す — 片方だけ直すと、今度は見出しだけの
       * 空の節が残る(この app が3度やった形)。
       */
      return (
        refineUsageChunks(ex.usage_chunks, ex.measure_words, input.headword, input.language)
          .length > 0 || usableCollocations(ex.collocations, input.language).length > 0
      );
    case "measure_words":
      return (ex.measure_words?.length ?? 0) > 0;
    case "related_words":
      return (
        (ex.related_words?.length ?? 0) > 0 ||
        (ex.synonyms?.length ?? 0) > 0 ||
        (ex.antonyms?.length ?? 0) > 0 ||
        !!ex.synonym_diff
      );
    case "pronunciation_tips":
      return !!(ex.pronunciation_tips || ex.study_tips);
    case "etymology":
      // 仲間の語だけが届いている段階でも「空」にしない。
      return !!ex.etymology || !!ex.radicals || (ex.etymology_relatives?.length ?? 0) > 0;
    case "mnemonic":
      return !!ex.mnemonic;
    case "taiwan_note":
      return !!(ex.taiwan_note || ex.trivia || ex.usage_note);
    // --- 英語のカードの節 ---------------------------------------------------
    case "forms":
      // `forms` が在るだけでは足りない。**活用の無い語**(不変化名詞など)は
      // 全欄が空のオブジェクトになるので、見出しだけの空の節になる。
      // `lemma` は原形で、活用そのものではないので数えない。
      return !!(
        ex.forms &&
        [
          ex.forms.plural,
          ex.forms.past,
          ex.forms.pastParticiple,
          ex.forms.ing,
          ex.forms.third,
          ex.forms.comparative,
          ex.forms.superlative,
        ].some(Boolean)
      );
    case "countability":
      return !!ex.countability;
    case "stress":
      // 音節に切れていなければ描く物が無い。`note` だけでは節にしない。
      return (ex.stress?.syllables?.length ?? 0) > 0;
    case "phrasal_verbs":
      return (ex.phrasal_verbs?.length ?? 0) > 0;
    case "culture_note":
      return !!ex.culture_note;
    // --- 日本語のカードの節 -------------------------------------------------
    case "kanji_breakdown":
      // 字の無い行(空の `kanji`)は描く物が無い。数える側も同じ物を見る。
      return (ex.kanji_breakdown ?? []).some((k) => !!k?.kanji?.trim());
    case "pitch_accent":
      return !!ex.pitch_accent;
    case "conjugation":
      return (ex.conjugation ?? []).some((c) => !!c?.text?.trim());
    case "politeness":
      return !!ex.politeness;
    case "counters":
      return (ex.counters?.length ?? 0) > 0;
    case "word_origin":
      return !!ex.word_origin;
    case "japan_note":
      return !!ex.japan_note;
    // 外の情報を見に行くだけの節。**行の中身では決められない。**
    //
    // `real_usage` は決まった数のリンクなので、いつでも描ける。
    // `web_images` は**取りに行ってみないと分からない**ので、ここでは
    // 判断できない — 1枚も見つからない語で見出しだけが残るのを止める
    // 条件は画面の側に在る(`use-web-images.ts` / `WordCard` の `canShow`)。
    case "web_images":
    case "real_usage":
      return true;
  }
}

/**
 * 類義語・関連語は並んでいるのに、**解説（note）が1つも無い**か。
 *
 * オーナー報告 2026-09-30「類義語や対義語関連語のそれぞれの解説がなくなってる」
 * （保溫瓶）。AI が note を学ぶ言語（中文）で返すと、読む人の言語でない注記として
 * 保存前に空にされる（`note-language.ts`）。語だけは残るので `sectionHasContent` は
 * 「在る」と答え、**二度と作り直されなかった**。語だけ並んでいても何が違うのか
 * 分からないので、この状態は「まだ作られていない」と数える。
 *
 * 節そのものは出したままにする（語は正しい）— 裏で解説付きの物に差し替わる。
 */
export function relatedWordsLackNotes(extras: WordExtrasDTO | null | undefined): boolean {
  const rel = extras?.related_words ?? [];
  return rel.length > 0 && rel.every((r) => !(r?.note ?? "").trim());
}

/**
 * その節を**裏で作る（作り直す）べきか**。画面の「まだ無い節」と server の
 * 「もう在るので作らない」の両方がここを見る（片方だけ直すと止まらない生成か、
 * 永久に直らない節になる — `sectionHasContent` の注と同じ理由）。
 */
export function sectionNeedsFill(id: SectionId, input: SectionContentInput): boolean {
  // サーバがもう作らない節（発音のコツ・覚え方）は、空でも埋めに行かない。
  if (isNotGeneratedSection(id)) return false;
  // 「1つの場面でしか使わない語」（`example_pattern_count === 1`、2026-10-15）は追加の例文が無いのが正しい。
  // 描く物は無い（`sectionHasContent` は false のまま）が、作り直しにも行かない — 行くと場面を水増しした例文が入る。
  if (id === "examples_extra" && input.extras?.example_pattern_count === 1) return false;
  if (!sectionHasContent(id, input)) return true;
  if (id === "related_words") return relatedWordsLackNotes(input.extras);
  return false;
}

/**
 * まだ作られていない節を、**画面に並ぶ順のまま**返す。
 * 順番はオーナーの指定(「項目の上から順に」)そのものなので、
 * ここで並べ替えない。
 */
export function missingSections(
  order: readonly SectionId[],
  input: SectionContentInput,
): RegenSection[] {
  return order.filter(
    (id): id is RegenSection => isRegenSection(id) && sectionNeedsFill(id, input),
  );
}

/**
 * 節の見出しの翻訳キー。**言語で変わる節が在る。**
 *
 * 「語源・部首」は英語のカードでは嘘になる（英語に部首は無い）。
 * 絵で見つけた — 英語のカードの見出しが `語源・部首` のままだった。
 *
 * 見出しは `t(`card.${id}`)` で機械的に引いていたので、
 * **例外を1箇所に置く**。ここを通さない呼び出しが増えると同じ嘘が戻る。
 */
export function sectionTitleKey(id: SectionId, language: string | null | undefined): string {
  if (id === "etymology" && !targetProfile(language).capture.hasRadicals) {
    return "card.etymologyOnly";
  }
  return `card.${id}`;
}
