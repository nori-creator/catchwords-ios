import { z } from "zod";
import { withoutGenericChunks } from "./generic-chunks";
import { normalizeTargetLanguage } from "./target-lang";
import { EtymologyDiagramSchema } from "./etymology-diagram";
import { isBrokenUsageChunk, tidyUsageParts, withoutSeparatorParts } from "./chunk-grammar";

/**
 * 単語カードの extras の唯一の定義(2026-07-25 詳細カード再構成)。
 * 以前は ai.functions / ghost.functions / stickers.functions がそれぞれ
 * 同じ形を別々に持っていて、フィールドを増やすたびにどこかの zod が
 * 黙って新フィールドを落とす事故が起きていた。全員ここを import する。
 *
 * すべて .catch なので、欠けていても型が違っても落ちずに既定値になる
 * (AI出力・古いDB行のどちらにも耐える)。
 */

export const ChunkPartSchema = z.object({
  text: z.string(),
  // 役割ラベル: S/V/V1/V2/O/M/C/Ptc など(復習の添削と同じ色体系で描画)
  pos: z.string().catch(""),
  /**
   * 入れ替えて使う所（公式の「人」「事」「someone」）。オーナー指示 2026-09-25
   * 「チャンクは公式、定理のように…跟＋人＋見面」。古いカードには無い。
   */
  slot: z.boolean().optional().catch(undefined),
  /**
   * 入れ替える所に、ネイティブがよく入れる**ほかの具体語**（頻度の高い順）。
   * オーナー指示 2026-09-27「汎用部分（人・もの）はタップすると、ネイティブ頻出の
   * 具体的単語が出る（跟+男朋友+吵架 → 女朋友・朋友…をスクロールで表示）。音声も全部」。
   * `ja` はその語の意味（読み手の言語）。古いカードには無い。
   */
  /**
   * 入れ替える所の**その語の意味**（読み手の言語）。語を入れ替えた時に、型の訳の中の
   * この部分を入れ替えた語の意味に差し替えて出す（R20「点線のなかのほかの単語をタップしたら、
   * もとの単語と同じように訳が表示され」）。古いカードには無い。
   */
  ja: z.string().optional().catch(undefined),
  /**
   * **札ごとの読み**（2026-10-15 オーナー「チャンクに拼音と注音を」）。台湾華語のカードだけ。
   * 拼音は声調記号つき・音節は空白区切り（`shuā zi`）、注音は音節を空白で区切り軽声は前に ˙
   * （`ㄕㄨㄚ ˙ㄗ`）。AI が書いた物をサーバが字ごとに検め、外れていれば辞書の読みに直す
   * （`chunk-readings.server.ts`）。**古いカードは持っていない**（作り直した時に付く）。
   */
  pinyin: z.string().optional().catch(undefined),
  zhuyin: z.string().optional().catch(undefined),
  alts: z
    .array(
      z.object({
        text: z.string(),
        ja: z.string().catch(""),
        // 入れ替える語の読み（台湾華語だけ。古いカードには無い）。
        pinyin: z.string().optional().catch(undefined),
        zhuyin: z.string().optional().catch(undefined),
      }),
    )
    .max(8)
    .optional()
    .catch(undefined),
});
export type ChunkPart = z.infer<typeof ChunkPartSchema>;

export const UsageChunkSchema = z.object({
  parts: z.array(ChunkPartSchema).catch([]),
  ja: z.string().catch(""),
});
export type UsageChunk = z.infer<typeof UsageChunkSchema>;

/**
 * **AI が返す型1つの形 = 型 + 自己点検**（2026-10-15 刷子「拿刷子刷牙」）。
 * `fits` は「その物の本来の使い方で、ネイティブがそのまま言う型か」の AI 自身の答え、`why` は一言。
 * サーバの門（`chunk-quality.ts`）が `fits: false` の型を落とし、**保存する前に2つの欄を外す**
 * （画面・iOS は受け取らない）。文字列の "false" / "no" も偽と読む（例文の `scene_fits` と同じ）。
 */
export const ChunkFitsSchema = z
  .union([z.boolean(), z.string().transform((s) => !/^(false|no|いいえ|否|×)$/i.test(s.trim()))])
  .optional()
  .catch(undefined);

export const AiUsageChunkSchema = UsageChunkSchema.extend({
  fits: ChunkFitsSchema,
  why: z.string().optional().catch(undefined),
});
export type AiUsageChunk = z.infer<typeof AiUsageChunkSchema>;

/**
 * **項目の作り直し（`runSectionRegen`）で受ける「かたまり」の形。**
 * 部品は `ChunkPartSchema` をそのまま使う — 前は `{text,pos,slot}` だけを書き出して
 * いたので、zod が `ja` と `alts` を**黙って落とし**、作り直した後は入れ替えの候補
 * （跟+男朋友+吵架 → 女朋友・朋友…）が消えていた（2026-10-07）。
 * 自己点検の欄（`fits` / `why`）も受ける — 門が見てから外す。
 */
export const RegenUsageChunksSchema = z.object({
  usage_chunks: z.array(AiUsageChunkSchema).min(1),
});

export const RelatedWordSchema = z.object({
  word: z.string(),
  kind: z.enum(["syn", "ant", "rel"]).catch("rel"),
  note: z.string().catch(""),
  /**
   * 読み(オーナー指示 2026-08-27 ⑧「発音記号がないから書き足して」)。
   *
   * **表記の名前を持たない**(注音か IPA かを書かない)。どちらに割り当てる
   * かは `target-profile.ts` の `readings` が言語ごとに知っているので、
   * ここは「1つめの読み・2つめの読み」だけを持つ
   * (`dictionary_entries.reading_primary` / `reading_alt` と同じ形)。
   * 古いカードは持っていないので**空が普通**。
   */
  reading: z.string().catch(""),
  reading_alt: z.string().catch(""),
});
export type RelatedWord = z.infer<typeof RelatedWordSchema>;

const ExampleExtraSchema = z.object({
  zh: z.string(),
  ja: z.string().catch(""),
  /** いつ・どんな気持ちで言う一文か(例:「夜市で値段を聞くとき」)。 */
  scene: z.string().catch(""),
  /**
   * `scene` を**どの文のために書いたか**（その文の文字列。2026-10-15、メインの例文の `example_scene_for` と同じ）。
   * iOS は例文の節に全部のパターンを並べ、`scene_for` が `zh` と同じ時だけ札を出す。古いカードは空。
   */
  scene_for: z.string().optional().catch(undefined),
  chunks: z.array(ChunkPartSchema).catch([]),
});

/**
 * 語形(英語)。**AI を1回も呼ばずに埋まる**唯一の節。
 *
 * ECDICT の `exchange` 欄が `p:went/d:gone/i:going/3:goes` の形で持っていて、
 * `lexicon-import.ts` の `parseExchange` がここに写す。生成に頼らないので
 * 待ち時間もお金もかからず、しかも辞書由来なので間違えない。
 *
 * **同じ形を取り込み側とカード側の2箇所に書かない。** 取り込みの script も
 * ここを import する — 片方に欄を足して片方に足し忘れると、DB には入って
 * いるのに画面に出ない(逆も起きる)という、この app が何度もやった形になる。
 *
 * 全部 `.catch("")` にして、無い活用は空文字にする。`null` と `""` を
 * 混ぜると描く側で二重に判定する羽目になる。
 */
export const WordFormsSchema = z.object({
  /** 複数形(名詞)。"child" → "children" */
  plural: z.string().catch(""),
  /** 過去形(動詞)。"go" → "went" */
  past: z.string().catch(""),
  /** 過去分詞(動詞)。"go" → "gone" */
  pastParticiple: z.string().catch(""),
  /** 現在分詞・動名詞。"go" → "going" */
  ing: z.string().catch(""),
  /** 三人称単数現在。"go" → "goes" */
  third: z.string().catch(""),
  /** 比較級(形容詞・副詞)。"good" → "better" */
  comparative: z.string().catch(""),
  /** 最上級。"good" → "best" */
  superlative: z.string().catch(""),
  /** 原形。活用形で引いたときに元の語へ戻す("went" → "go")。 */
  lemma: z.string().catch(""),
});
export type WordForms = z.infer<typeof WordFormsSchema>;

// --- 日本語のカードだけの欄の形(2026-10-01) ----------------------------------
// 生成(`generateCard`)と作り直し(`regenerateCardSection`)の両方がここを使う。
// 片方に欄を足して片方に足し忘れると、作った物が保存で黙って落ちる(冒頭の注)。

/**
 * 語の中の漢字1字ずつ。`on` は音読み(カタカナ)、`kun` は訓読み(ひらがな)。
 * 無い読みは空文字。**かなだけの語は空配列**(節ごと出さない)。
 */
export const KanjiBreakdownSchema = z.object({
  kanji: z.string(),
  meaning: z.string().catch(""),
  on: z.string().catch(""),
  kun: z.string().catch(""),
});
export type KanjiBreakdown = z.infer<typeof KanjiBreakdownSchema>;

/** 活用の1行。`form` は形の名前(読む人の言語)、`text` はその形の日本語。 */
export const ConjugationRowSchema = z.object({
  form: z.string().catch(""),
  text: z.string(),
});
export type ConjugationRow = z.infer<typeof ConjugationRowSchema>;

/** 助数詞の1行。`word` は数つき(「一本」)、`reading` はその読み、`note` は使い分け。 */
export const CounterSchema = z.object({
  word: z.string(),
  reading: z.string().catch(""),
  note: z.string().catch(""),
});
export type Counter = z.infer<typeof CounterSchema>;

export const ExtrasSchema = z.object({
  // --- 旧フィールド(古いカードの表示互換のため保持) ---------------------
  collocations: z.array(z.string()).catch([]),
  synonyms: z.array(z.string()).catch([]),
  antonyms: z.array(z.string()).catch([]),
  trivia: z.string().catch(""),
  common_situation: z.string().catch(""),
  usage_note: z.string().catch(""),
  register_note: z.string().catch(""),
  synonym_diff: z.string().catch(""),
  word_order: z.string().catch(""),
  study_tips: z.string().catch(""),
  // --- 現行フィールド ------------------------------------------------------
  etymology: z.string().catch(""),
  /**
   * 同じ語根・接頭辞・接尾辞を持つ**仲間の語**（オーナー指示 2026-08-26
   * 「同じ語源や接頭辞、接尾辞を持つ関連語、派生語があれば紹介して」）。
   *
   * **英語の語だけ。** 学習言語が英語のときにしか作らせない
   * (オーナー追記「上の語源の項目については、学習言語英語のときだけ」)。
   * 台湾華語の語は空のまま — 部首・声符の話は `radicals` が持つ。
   *
   * `{ word, note }`。`note` は「その部品が何を意味するか」を短く。
   */
  etymology_relatives: z
    .array(
      z.object({
        word: z.string().catch(""),
        note: z.string().catch(""),
      }),
    )
    .catch([]),
  radicals: z.string().catch(""),
  /**
   * 語源・部首の**図**（2026-10-15、`etymology-diagram.ts`）。iOS が [字 / 部品+部品 / 意味] + … = [語 / 意味] と描く。
   * 分解できない語は `kind`（single_char / loanword_phonetic / proper / other）と短い `note`。古いカードは null。
   */
  etymology_diagram: EtymologyDiagramSchema.nullable().catch(null).default(null),
  mnemonic: z.string().catch(""),
  /**
   * 例文（example_sentence）の場面・気持ちの短い説明（読む人の言語）。追加の例文の `scene` と同じ書き方。
   * オーナー指示 2026-10-14「例文は追加の例文のように…状況場面感情の説明を短く例文のうえに書いて」。
   */
  example_scene: z.string().catch(""),
  /**
   * `example_scene` と `example_chunks` を**どの例文のために書いたか**（その例文の文字列）。
   * オーナー報告 2026-10-15「眼鏡: 我戴眼鏡。の上に『友達が眼鏡をしていないことに気づいたとき』」— 共有の行は
   * 空の欄だけ埋めるので、前から在った例文の横に別の生成の札が入っていた。表示する例文と違えば札を出さない
   * （`example-patterns.ts` の `alignExampleExtras`）。古いカードは空（確かめようがない）。
   */
  example_scene_for: z.string().catch(""),
  /** 例文の作り方の版（`EXAMPLE_PROMPT_VERSION`）。古いカードは null。 */
  example_v: z.number().int().nullable().catch(null),
  /**
   * その語がよく使われる場面のパターンの数（メインの例文を含む）。1 なら追加の例文は無いのが正しい
   * （「1つの状況でしか使わない語なら例文は1つでいい」2026-10-15）。古いカードは null。
   */
  example_pattern_count: z.number().int().min(1).max(10).nullable().catch(null),
  examples_extra: z.array(ExampleExtraSchema).catch([]),
  /** 頻度・使う場面(統合): どこで見て使うか+口語/書面+頻度の説明。 */
  usage_context: z.string().catch(""),
  /** 使用頻度レベル 1〜5(5=毎日レベル)。視覚メーター用。 */
  frequency_level: z.number().int().min(1).max(5).nullable().catch(null),
  /**
   * 【退役】「口語」「書面」「口語・書面」の札（オーナー決定 2026-10-15「中立・書き言葉・話し言葉の
   * 表示を無くす」）。**もう作らない・画面に出さない・返さない**（`withoutRetiredExtras`）。
   * 形だけ残すのは、保存済みの行の値を**消さないため**（スキーマから外すと次の保存で静かに消える）。
   */
  register_tag: z.string().catch(""),
  /** 【退役】話し言葉⇄書き言葉の目盛り。`register_tag` と同じ扱い（作らない・出さない・返さない）。 */
  register_scale: z.number().int().min(-2).max(2).nullable().catch(null),
  /**
   * その語に**どこで出会うか**の分布。鍵は図鑑の部屋
   * (`category.ts` の `ROOM_KEYS`: eat / town / house / wear / play /
   * nature / people / marks)。合計はおよそ1。
   *
   * **自由な場面名を作らせない。** 出会う確率は「語が出る場面」と
   * 「その人が居る場面」の内積で出す(`lib/rarity.ts` の `sceneOverlap`)。
   * その人の側は撮ったものの部屋から数えるので、**両方が同じ鍵で並んで
   * いないと内積が意味を持たない**。
   *
   * 古いカードは持っていない。無ければ場面の補正は掛からない。
   */
  scene_weights: z.record(z.string(), z.number()).nullable().catch(null),
  /** 旬の月(1〜12)。通年なら空。季節外れの補正に使う。 */
  season_months: z.array(z.number().int().min(1).max(12)).catch([]),
  /** 「台南」「台湾」など、そこでしか見ないもの。限定が無ければ空。 */
  region_scope: z.string().catch(""),
  /**
   * **なぜそこ限定なのか。**(オーナー指摘 2026-08-28 ②
   * 「立扇という単語の時に台湾限定と出た」)
   *
   * 地域名だけを訊くと、この app が台湾の語を扱う以上、模型は何にでも
   * 「台湾」と答える。本番では `region_scope` の入った9語のうち6語が
   * 誤りだった(扇風機・エアコン・シュークリーム…)。
   *
   * だから理由を要る物にした。`scene-bubbles.ts` の `limitedRegion` は
   * **ここが空なら限定を名乗らせない**。理由の言えない物は、そこにしか
   * 無い物ではない。
   */
  region_scope_kind: z.enum(["specialty", "institution", "regional_word"]).nullable().catch(null),
  /**
   * その語が出る検定の印（`dictionary_entries.exam_tags` の写し）。
   *
   * **AI に作らせない。** 辞書の行に入っている事実で、当て推量で
   * 「TOEFL の語」と書かれると、級を当て推量させていたのと同じ問題に戻る
   * （オーナー指摘 2026-08-27 ⑭）。
   */
  exam_tags: z.array(z.string()).catch([]),
  /**
   * **その語に出会いやすい所を、具体的な札で並べる**(オーナー指摘 2026-08-20)。
   *
   * > 「頻度、使う場面の欄は、この単語に遭遇する確率が高い場所、状況、感情、
   * >  時刻、媒体、季節をラベルとして囲って複数挙げて。スーパー、ニュース、
   * >  看板、メニュー、道、駅、誕生日、夜、春みたいに」
   *
   * `scene_weights`(部屋8つ)は**数式のための分布**で、人が読む言葉では
   * ない。こちらは読む側の札で、種類ごとに色を分けて並べる。
   *
   * 種類が読めない札は `place` に落とす — 札そのものは捨てない
   * (「スーパー」が消えるより、色が1つずれるほうが害が小さい)。
   */
  encounter_labels: z
    .array(
      z.object({
        // `trait` は**その物じたいの性質**(熱い/持ち歩ける/使い捨て)。
        // オーナー指示 2026-08-28 ②「そのものの物理的な性質など」。
        // 出会う場所とは別の軸なので、画面でも別の束に入る。
        kind: z
          .enum(["place", "situation", "emotion", "time", "media", "season", "trait"])
          .catch("place"),
        label: z.string(),
      }),
    )
    .catch([]),
  /**
   * 「今週出会う見込み」の**計算結果の控え**(`encounter.functions.ts` が置く)。
   *
   * ここだけは**人が書いた物ではなく、機械が数えた物**。全利用者を数える
   * 問い合わせが要るので、カードを開くたびには数えず1日1回に留める。
   * 形が変わっても古い控えで落ちないよう、中身は緩く受けて `at` だけ見る。
   */
  encounter: z
    .object({
      /** いつ数えたか。これを見て1日1回に留める。 */
      at: z.string(),
      probability: z.number().catch(0),
      stars: z.number().int().min(1).max(5).catch(3),
      confidence: z.enum(["estimate", "blended", "measured"]).catch("estimate"),
      observed_users: z.number().int().nullable().catch(null),
      top_rooms: z.array(z.string()).catch([]),
      region_scope: z.string().nullable().catch(null),
      season_months: z.array(z.number().int()).catch([]),
    })
    .nullable()
    .catch(null),
  /**
   * 使い方の型・チャンク(コロケーション+語順を統合、品詞色分け)。
   * AI の返事は自己点検の欄（`fits` / `why`）を持つことがある（`AiUsageChunkSchema`）。ここで受けないと
   * zod が**門より先に黙って落とし**、門は何も見られない。保存する物は門が外す（`stripChunkSelfCheck`）。
   */
  usage_chunks: z.array(AiUsageChunkSchema).catch([]),
  /** メイン例文のパーツ分解。 */
  example_chunks: z.array(ChunkPartSchema).catch([]),
  /** 類義語・反義語・関連語(使い分けノート付き)。 */
  related_words: z.array(RelatedWordSchema).catch([]),
  /** 量詞(名詞のみ)。複数ある場合は使い分けノート付き。 */
  measure_words: z
    .array(
      z.object({
        word: z.string(),
        zhuyin: z.string().catch(""),
        pinyin: z.string().catch(""),
        note: z.string().catch(""),
      }),
    )
    .catch([]),
  /** 日本人向けの発音のコツ(声調・有気音・そり舌・鼻音韻尾など)。 */
  /**
   * 一目で分かる要点。**表として出す**ための、短い「見出し: 中身」の並び。
   *
   * ## なぜ地の文と別に持つか
   * 解説はこれまで全部が地の文だった。描く側でどれだけ組み直しても、
   * 中身が文である以上「読む」しかない(オーナー指摘:「文章だけでなく、
   * 表のように一目で解説を理解できるように」)。表にしたいなら、
   * **表になる形で生成させる**必要がある。
   *
   * 中身は短く。value が長い文になったら、それは地の文の項目の仕事。
   */
  /**
   * 【退役】「ひと目でわかる」の表。
   *
   * 2026-08-20 にオーナー指示で**画面からも生成からも外した**。
   * ここに残してあるのは**既にDBに入っている139語の中身を消さないため**だけ。
   * スキーマから外すと `normalizeExtras` が落とし、次の保存で静かに消える。
   * 読む所も書く所も無いので、新しく増えることはない。
   */
  quick_facts: z
    .array(
      z.object({
        label: z.string(),
        value: z.string(),
      }),
    )
    .catch([]),
  pronunciation_tips: z.string().catch(""),
  /** 台湾での一言雑学(文化・習慣・歴史・流行)+語法の注意。 */
  taiwan_note: z.string().catch(""),
  // --- 英語のカードだけの欄 ------------------------------------------------
  // 台湾華語のカードには出ない(`target-profile.ts` の `sections` が決める)。
  // 逆に `measure_words` は英語のカードには出ない — 英語に量詞は無い。
  /**
   * 語形。**辞書から入るので AI を呼ばない。**
   * `null` は「まだ引いていない」、全欄が空のオブジェクトは
   * 「引いたが活用が無い語(不変化名詞など)」で、意味が違う。
   */
  forms: WordFormsSchema.nullable().catch(null),
  /**
   * 可算/不可算と冠詞。
   *
   * **中国語話者にとって最大の誤りの元。** 中国語に冠詞は無いので、
   * "I bought furniture" と "I bought a furniture" のどちらが正しいかは
   * 母語からは分からない。台湾華語話者向けの版(指摘⑬)の中心にあたる。
   */
  countability: z
    .object({
      kind: z.enum(["countable", "uncountable", "both"]).catch("countable"),
      /** その語に付く冠詞の形("a" / "an" / "the" / "—")。 */
      article: z.string().catch(""),
      /** 使い分けの一言(both のときは、どちらの意味でどちらになるか)。 */
      note: z.string().catch(""),
    })
    .nullable()
    .catch(null),
  /**
   * どの音節を強く読むか。
   *
   * **通じるかどうかを最も左右する。** 音を全部正しく出しても強勢の位置が
   * 違うと英語話者には別の語に聞こえる(PREsent / preSENT)。中国語は
   * 声調言語で強勢が語の意味を変えないため、意識に上りにくい。
   *
   * `syllables` は音節に切った綴り、`primary`/`secondary` はその添字。
   */
  stress: z
    .object({
      syllables: z.array(z.string()).catch([]),
      primary: z.number().int().min(0).nullable().catch(null),
      secondary: z.number().int().min(0).nullable().catch(null),
      note: z.string().catch(""),
    })
    .nullable()
    .catch(null),
  /**
   * 句動詞。動詞のカードで、台湾華語なら量詞が入る枠が空く所に入る。
   * "give up" / "give in" のように、語そのものからは意味が読めない物。
   */
  phrasal_verbs: z
    .array(
      z.object({
        phrase: z.string(),
        meaning: z.string().catch(""),
        example: z.string().catch(""),
      }),
    )
    .catch([]),
  /**
   * 文化の一言。台湾華語のカードの `taiwan_note` にあたる欄。
   * 米/英の違い(elevator / lift)、その語にまつわる習慣など。
   */
  culture_note: z.string().catch(""),
  // --- 日本語のカードだけの欄 ----------------------------------------------
  // 台湾華語・英語のカードには出ない(`target-profile.ts` の `sections` が決める)。
  /**
   * 語の中の漢字1字ずつの意味と音訓。日本語の漢字は1字に読みが複数あり、
   * 語ごとにどれを使うかが決まる(生活=せい / 生まれる=う / 生ビール=なま)。
   */
  kanji_breakdown: z.array(KanjiBreakdownSchema).catch([]),
  /**
   * 高低アクセント(東京式)の説明。型の名前(平板・頭高・中高・尾高)と、
   * 高さの並び(例: は↘し)と、同じ音で型の違う語があればその対比。
   */
  pitch_accent: z.string().catch(""),
  /** 活用(動詞・い形容詞・な形容詞)。**名詞は空配列**。 */
  conjugation: z.array(ConjugationRowSchema).catch([]),
  /** 敬語・丁寧さ(くだけた / 丁寧 / 尊敬・謙譲の言い換えと、使う相手)。 */
  politeness: z.string().catch(""),
  /** その名詞を数える助数詞。名詞でなければ空配列。 */
  counters: z.array(CounterSchema).catch([]),
  /** 語種(和語・漢語・外来語・混種語)と、それが硬さ・場面にどう効くか。 */
  word_origin: z.string().catch(""),
  /** 日本ならではの一言。台湾華語の `taiwan_note`・英語の `culture_note` にあたる欄。 */
  japan_note: z.string().catch(""),
  /**
   * この解説を**どの言語で書いたか**("ja" / "en")。
   * 設定の表示言語を英語に変えたとき、日本語のまま残った古い解説を
   * 自動で作り直すための目印(空=言語不明の旧データ=日本語とみなす)。
   */
  explain_lang: z.string().catch(""),
  /**
   * この解説を**どの母語の学習者向けに書いたか**(L1Code: "ja"/"en"/…)。
   *
   * 発音のコツと語順の説明は母語ごとに中身が変わる — 日本語話者には
   * 「有気音と無気音の区別が無い」、韓国語話者には「f が無い」と書く。
   * だから母語設定を変えたら、表示言語と同じように作り直す必要がある。
   * 空=旧データで、母語不明。日本語向けとみなす。
   */
  explain_l1: z.string().catch(""),
  /**
   * **画像検索に投げる短い英語**（オーナー報告 2026-10-08「牛蒡を検索すると花の写真しか
   * 出ない」）。学ぶ人がその語で指す**日常の物**（牛蒡 → `burdock root`）。
   *
   * 意味の欄（`ゴボウ`）をそのまま投げると、写真の出所は英語の説明で引くので植物の
   * ゴボウ（花・野草）に当たる。カードを作る呼び出しで一緒に返させる（AI の呼び出しは
   * 増やさない）。読むのは `hero-image.ts` の `heroSearchQuery`。古いカードは空 —
   * その時は今までどおり意味の欄で探す。画面には出さない。
   */
  image_query: z.string().catch(""),
  /**
   * **写っていたら外れの英語**（オーナー報告 2026-10-08 ②「レンコンを調べたのに蓮の花」）。
   * `image_query` と同じ呼び出しで返させる（レンコン → `flower` `blossom` `pond` `petal`）。
   * 候補の並べ替えで、これが説明に出てくる写真を捨てる（`image-search-rank.ts`）。画面には出さない。
   */
  image_avoid: z.array(z.string()).catch([]).default([]),
});

export type WordExtrasDTO = z.infer<typeof ExtrasSchema>;

export function emptyExtras(): WordExtrasDTO {
  return ExtrasSchema.parse({});
}

/** DBやAIから来た生の extras を安全に正規化(壊れていれば null)。 */
export function normalizeExtras(raw: unknown): WordExtrasDTO | null {
  if (!raw || typeof raw !== "object") return null;
  const res = ExtrasSchema.safeParse(raw);
  return res.success ? res.data : null;
}

/**
 * **もう画面に出さない欄**（オーナー決定 2026-10-15: 中立 / 書き言葉 / 話し言葉の札を無くす）。
 * 保存済みの値は消さない（`ExtrasSchema` に残す）が、画面と iOS へ返す物からは外す。
 */
export const RETIRED_EXTRAS_KEYS = ["register_tag", "register_scale"] as const;

/** 画面・iOS へ返す形: 退役した欄を空にする。保存する物には使わない（値を消さないため）。 */
export function withoutRetiredExtras<T extends Partial<WordExtrasDTO> | null | undefined>(
  extras: T,
): T {
  if (!extras) return extras;
  return { ...extras, register_tag: "", register_scale: null };
}

/** 読む所で使う形（正規化 + 退役した欄を外す）。 */
export function publicExtras(raw: unknown): WordExtrasDTO | null {
  return withoutRetiredExtras(normalizeExtras(raw));
}

/** 読む中身ではなく目印・手がかりの鍵（「中身がある」に数えない）。 */
const EXTRAS_MARKER_KEYS = new Set([
  "explain_lang",
  "explain_l1",
  "image_query",
  "image_avoid",
  "example_scene_for",
  "example_v",
  "example_pattern_count",
]);

/** True when an extras object carries at least one non-empty field. */
export function hasExtrasContent(e: Partial<WordExtrasDTO> | null | undefined): boolean {
  if (!e) return false;
  // explain_lang / explain_l1 は内容ではなく目印、image_query / image_avoid は画像検索の
  // 手がかりで読む物ではないので「中身がある」判定から外す。
  return Object.entries(e).some(([k, v]) =>
    EXTRAS_MARKER_KEYS.has(k)
      ? false
      : Array.isArray(v)
        ? v.length > 0
        : typeof v === "string"
          ? v.trim().length > 0
          : v != null,
  );
}

/**
 * Merge incoming extras over existing: a non-empty incoming field wins, an
 * empty one never erases what's already saved.
 */
export function mergeExtras(
  cur: Partial<WordExtrasDTO> | null | undefined,
  inc: Partial<WordExtrasDTO> | null | undefined,
): WordExtrasDTO {
  const base: Record<string, unknown> = { ...emptyExtras(), ...(cur ?? {}) };
  for (const [k, v] of Object.entries(inc ?? {})) {
    const filled = Array.isArray(v)
      ? v.length > 0
      : typeof v === "string"
        ? v.trim().length > 0
        : v != null;
    if (filled) base[k] = v;
  }
  const res = ExtrasSchema.safeParse(base);
  return res.success ? res.data : emptyExtras();
}

/**
 * 量詞の欄と重なる「使い方」の型を落とす。
 *
 * 名詞のカードには量詞の欄(measure_words)があり、そこに「一張」が並ぶ。
 * その**すぐ上**の「使い方」に「一張 + 衛生紙」だけの型が出ると、
 * 同じ物を続けて2度読まされる(オーナー指摘 2026-08-18:
 * 「名詞の場合は量詞の欄があるから、チャンクの欄で同じものを表示しないで」)。
 *
 * **落とすのは「量詞と見出し語しか無い」型だけ。**
 * 「拿 + 一張 + 衛生紙」のように動詞や述語が付いた型は残す —
 * それは量詞の一覧には無い情報で、ネイティブの使い方そのものだから。
 * 量詞の型を丸ごと禁じると、逆に「動詞と目的語しか無い」状態に戻ってしまう
 * (オーナー指摘 2026-08-19:「品詞をすべて網羅して」)。
 */
/**
 * 型1つの長さの上限(繁体字の文字数)。これを超えると「型」ではなく文になる。
 *
 * **台湾華語の数え方**。英語には効かせない（すぐ下の注）。
 */
export const MAX_CHUNK_CHARS = 8;

/**
 * **英語の型の長さの上限（文字数）。**
 *
 * オーナー報告 2026-08-26（3度目）:
 * > 「単語のチャンク型の項目が生成されてない。」
 *
 * ## 生成はされていた。**こちらが全部落としていた。**
 * 上の 8 は「繁体字で8文字」。漢字1つが語1つぶんの中国語では
 * ちょうどよい目盛りだが、同じ数を英語に当てると
 * `put on socks`(12)も `a pair of socks`(15)も**1つ残らず落ちる**。
 * だから `refineUsageChunks` はいつも空を返し、
 * 「まだ空だ」→ 作り直す → また落とす、が延々と続いていた
 * （待ち時間もお金も払いながら、画面には一度も出ない）。
 *
 * ## 語の数で数える
 * 英語で「口に乗る型」を決めているのは文字数ではなく**語数**なので、
 * 語数のほうを見る。`MAX_CHUNK_PARTS`(4)と揃えて4語まで。
 * 文字数は「1語が異様に長い」を弾く保険として広めに置く。
 */
export const MAX_CHUNK_WORDS_EN = 4;
export const MAX_CHUNK_CHARS_EN = 28;
/**
 * **日本語の型の長さの上限(文字数)。**
 *
 * 日本語は助詞を型の中に必ず入れる(「傘をさす」)うえ、カタカナ語が長い
 * (「ハンバーガーを食べる」10字)。台湾華語の 8 を当てると、英語で起きた
 * 「生成はされているのに全部落ちる」が日本語で起きる。指示文の「12文字以内」と揃える。
 */
export const MAX_CHUNK_CHARS_JA = 12;
/** 型1つのパーツ数の上限。 */
export const MAX_CHUNK_PARTS = 4;
/** カードに並べる型の数の上限。 */
export const MAX_CHUNKS = 5;

/**
 * その型の文字列。
 *
 * **英語は空白で継ぐ。** 漢字は1字ずつが語なので継ぎ目が要らないが、
 * 英語で `["put on","socks"]` を素で継ぐと `put onsocks` になり、
 * 語数も重複の見分けも狂う。
 */
function chunkText(c: UsageChunk, sep = ""): string {
  return (c.parts ?? [])
    .map((p) => (p?.text ?? "").trim())
    .filter(Boolean)
    .join(sep);
}

/**
 * 語の数。**空白でも `chunkText` の継ぎ目でも切る** —
 * パーツが `["put on","socks"]` でも `["put","on","socks"]` でも
 * 同じ3語と数えたい（生成側がどちらの形で返すか決まっていない）。
 */
function countWords(text: string): number {
  return text.split(/[\s'’-]+/u).filter(Boolean).length;
}

/**
 * 型の中に学ぶ語が入っているか（iOS `LanguageRules.mentionsHeadword` と同じ判定）。
 *
 * - 台湾華語：見出し語の文字列がそのまま入っている
 * - 日本語：見出し語、または送り仮名を除いた語幹（食べる→食べた、高い→高くない）
 * - 英語：見出し語の各語が、そのままか規則的な語形変化で入っている
 *   （mango→mangoes、make→making、carry→carried）。3文字以下の語は丸ごと一致だけ
 *   （mankind は man の形ではない）
 */
export function chunkMentionsHeadword(
  text: string,
  headword: string,
  language?: string | null,
): boolean {
  const core = (s: string) =>
    s
      .replace(/[（(【〔[][^）)】〕\]]*[）)】〕\]]/gu, "")
      .replace(/[\s\p{P}'’‘\-‐–—・·.,、。]/gu, "");
  const head = core(headword);
  if (!head) return true;
  const lang = normalizeTargetLanguage(language);
  if (lang === "en") {
    const words = text
      .toLowerCase()
      .split(/[^\p{L}']+/u)
      .filter(Boolean);
    const heads = headword
      .toLowerCase()
      .split(/[^\p{L}]+/u)
      .filter(Boolean);
    if (heads.length === 0) return true;
    return heads.every((h) => {
      let stem = h;
      if (stem.length >= 4 && /[ey]$/.test(stem)) stem = stem.slice(0, -1);
      return words.some((w) => w === h || (h.length >= 4 && w.startsWith(stem)));
    });
  }
  const t = core(text);
  if (t.includes(head)) return true;
  if (lang === "ja") {
    let stem = head;
    if (/\p{Script=Han}/u.test(head)) stem = head.replace(/[\u3041-\u309F]+$/u, "");
    else if ([...head].length >= 3) stem = [...head].slice(0, -1).join("");
    return stem.length > 0 && t.includes(stem);
  }
  return false;
}

/**
 * 使い方の型を**厳選する**(オーナー指摘 2026-08-21)。
 *
 * > 「チャンク、型の精度が低い、適当になってる。ネイティブが最も高い確率で
 * >  その単語をどんな言葉と一緒に使うか…厳選して、スピーキングの時に
 * >  使えるように教えて。型やチャンクは長すぎないで。」
 *
 * プロンプトでも頼むが、**返ってきた物のほうを見て落とす**。この app は
 * 「書いてあることと返ってくる物は別」を何度も踏んでいる。
 *
 * 落とすのは次の物:
 * 0. **どの名詞にも付く汎用の組み合わせ**(`generic-chunks.ts`) —
 *    「買{語}」「喜歡{語}」はその語について何も教えていない
 *    (オーナー指示 2026-08-28 ③)
 * 1. **量詞に触れる型**(下の `withoutMeasureWords`) — 量詞の欄が別に在る
 * 2. **長すぎる型** — 8文字を超えると口に乗る「型」ではなく例文になる。
 *    例文の欄が別に在るので、ここが文になると欄の意味が重なる
 * 3. **文になっている型**(句点・感嘆符・疑問符が入っている)
 * 4. 見出し語しか無い型(情報が0)
 * 5. 同じ文字列の重複
 * 6. **学ぶ語が入っていない型**(オーナー報告 2026-10-01「チャンクに学ぶべき単語の芒果がない」)
 *    — 「芒果」の型に「很+甜」だけが来た。型は「その語をどう使うか」なので、
 *    語そのもの（日本語・英語は活用形も可）が入っていない物は型ではない
 * 7. **1語を分けただけの型**(オーナー指示 2026-10-01「芒果冰のようにひとかたまりとして普段
 *    扱われるものはチャンクを分けなくていい」) — 芒果＋冰 は 芒果冰 という1語
 * 8. **崩れた型・訳になっていない訳**(`isBrokenUsageChunk`。オーナー報告 2026-10-09
 *    「嘴邊肉＋切 / 嘴邊肉をする」) — 量詞を抜いて残った「名詞＋裸の動詞」、学ぶ語を写した訳
 *
 * そのうえで**先頭5つ**に切る。生成側は「使用頻度の高い順」に並べるので、
 * 切るのは後ろから。
 */
export function refineUsageChunks(
  chunks: ReadonlyArray<UsageChunk> | null | undefined,
  measureWords: ReadonlyArray<{ word?: string } | null | undefined> | null | undefined,
  headword: string,
  /**
   * その語の学習言語。**渡さないと台湾華語の目盛りで測る** —
   * 英語の型が1つ残らず落ちる（`MAX_CHUNK_CHARS_EN` の注）。
   */
  language?: string | null,
): UsageChunk[] {
  const head = headword.trim();
  const seen = new Set<string>();
  const isEnglish = normalizeTargetLanguage(language) === "en";
  const maxChars = chunkCharLimit(language);
  // 「+」だけの札・「牛蒡+炒」の継ぎ目を先に正す（`withoutSeparatorParts`）。長さ・札の数・
  // 重複は、画面に出る札で数える（保存済みの語にも効く）。
  const cleaned = (chunks ?? [])
    .filter(Boolean)
    .map((c) => ({ ...c, parts: withoutSeparatorParts(c.parts ?? []) }));
  return withoutGenericChunks(
    withoutMeasureWords(cleaned, measureWords, headword),
    headword,
    language,
  )
    .filter((c) => {
      const parts = (c.parts ?? []).filter((p) => (p?.text ?? "").trim().length > 0);
      if (parts.length === 0 || parts.length > MAX_CHUNK_PARTS) return false;
      const text = chunkText(c, isEnglish ? " " : "");
      if (text.length === 0) return false;
      // 句点の付いた物は文。**長さの前に見る** — 短い文(`我去了。`)は
      // 長さの網に掛からない。
      if (SENTENCE_END.test(text)) return false;
      if (isEnglish) {
        // 英語は**語の数**で測る（文字数だと `put on socks` すら落ちる）。
        if (countWords(text) > MAX_CHUNK_WORDS_EN) return false;
        if (text.length > MAX_CHUNK_CHARS_EN) return false;
      } else if (text.length > maxChars) {
        return false;
      }
      // 見出し語だけの型は、その語を見れば分かることしか言っていない。
      if (text === head) return false;
      // 分けた1語（芒果＋冰 → 芒果冰）は使い方ではない（チャンクの表示ルール C7）。
      // もともと札1つで保存された古い型は落とさない（合わせて1つになった物だけ）。
      if (parts.length >= 2 && tidyUsageParts(parts, language, { headword: head }).length < 2)
        return false;
      if (!chunkMentionsHeadword(chunkText(c, " "), head, language)) return false;
      // 量詞を抜いて崩れた型（嘴邊肉＋切）・訳になっていない訳（嘴邊肉をする）。
      if (isBrokenUsageChunk(c, head, language)) return false;
      if (seen.has(text)) return false;
      seen.add(text);
      return true;
    })
    .slice(0, MAX_CHUNKS);
}

/**
 * **量詞に触れる型を1つも通さない**(オーナー指示 2026-08-27 ⑫⑮)。
 *
 * > 「使い方のチャンク、量詞の項目があるから、チャンクでは同じような
 * >  ものを表示させないで。」
 * > 「名詞の場合は量詞の欄があるから、チャンクの欄で同じものを
 * >  表示しないで。**決して被らせないで**。」
 *
 * ## 前は「丸ごと同じ型」だけを落としていた
 * 古い条件は「量詞と見出し語**以外**のパーツが1つでもあれば通す」で、
 * つまり `一張地圖` は落ちるが `買一張地圖` は通っていた。量詞の欄を
 * 別に持っている以上、**量詞が出てくる時点で重なっている** —
 * 読む人から見れば「さっき下で読んだ字がまた出てきた」でしかない。
 *
 * 量詞は `pos: "M"` でも見分けられるが、**それだけに頼らない** —
 * 品詞は AI が付ける物なので、付け忘れた回に素通しになる。
 * その札の量詞の一覧と、量詞の記号と、**両方**で見る。
 */
export function withoutMeasureWords(
  chunks: ReadonlyArray<UsageChunk> | null | undefined,
  measureWords: ReadonlyArray<{ word?: string } | null | undefined> | null | undefined,
  headword: string,
): UsageChunk[] {
  const list = (chunks ?? []).filter(Boolean) as UsageChunk[];
  const cores = new Set(
    (measureWords ?? []).map((m) => measureWordCore(m?.word ?? "")).filter((w) => w.length > 0),
  );
  const head = headword.trim();
  return list.filter((c) => {
    const parts = (c.parts ?? []).filter((p) => (p?.text ?? "").trim().length > 0);
    if (parts.length === 0) return false;
    // 見出し語そのものは量詞と一致しない(量詞は数える器のほう)。
    // 見出し語が偶然その札の量詞と同じ字のときに、型を全部落とさない。
    return !parts.some((p) => {
      const text = (p.text ?? "").trim();
      if (text === head) return false;
      if (p.pos === "M") return true;
      return cores.has(measureWordCore(text));
    });
  });
}

/** 文字数で測る言語(台湾華語・日本語)の型の上限。 */
function chunkCharLimit(language: string | null | undefined): number {
  return normalizeTargetLanguage(language) === "ja" ? MAX_CHUNK_CHARS_JA : MAX_CHUNK_CHARS;
}

/**
 * 文末の約物。**これが入っていたら型ではなく文**(オーナー指摘 2026-08-27 ②)。
 *
 * > 「チャンク、型の項目が文章のようになってる。文章を表示したいのでは
 * >  なく、ネイティブがその単語を使う時に最も相性のいい、よく使う単語の
 * >  塊、フレーズを表示したい。」
 *
 * 長さの上限は前から在るが、長さだけでは短い文(`我去了。`)が通る。
 * 「そのまま口に乗せる塊」に句点は要らない。
 */
const SENTENCE_END = /[。．.!！?？…]/u;

/**
 * 古いカードの `collocations`(語のかたまりの文字列)を、型の節に出せる物
 * だけに絞る。
 *
 * 型が1つも残らなかったときの控えだが、**控えでも規則は同じ**
 * (オーナー指摘 2026-08-27 ②「文章を表示したいのではない」)。
 * 文になっている物と、長すぎる物を落とす。
 */
export function usableCollocations(
  collocations: ReadonlyArray<string | null | undefined> | null | undefined,
  language?: string | null,
): string[] {
  const isEnglish = normalizeTargetLanguage(language) === "en";
  const maxChars = chunkCharLimit(language);
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of collocations ?? []) {
    const text = (raw ?? "").trim();
    if (!text || seen.has(text)) continue;
    if (SENTENCE_END.test(text)) continue;
    if (isEnglish) {
      if (countWords(text) > MAX_CHUNK_WORDS_EN || text.length > MAX_CHUNK_CHARS_EN) continue;
    } else if (text.length > maxChars) {
      continue;
    }
    seen.add(text);
    out.push(text);
    if (out.length >= MAX_CHUNKS) break;
  }
  return out;
}

/**
 * その型を**ひと息で読み上げるときの文字列**。
 *
 * 継ぎ目は言語で決まる（英語は空白、漢字は無し）。この判断は
 * `chunkText` が既に持っているので、外へはこの薄い包みだけを出す —
 * 読み上げ側が `parts.join("")` を自前で書くと、英語の型が
 * `put onsocks` として合成される。
 */
/**
 * **チャンクの右に出す訳だけ**を取り出す。（オーナー指示 2026-09-23「チャンクの
 * 右側は訳だけにして」）
 *
 * 生成の頼み方が長く「短い説明」だったので、既存のカードには
 * 「タピオカミルクティーを頼む（注文の定番）」「よく使う型: …」のような説明が
 * 混ざっている。表示の側で、最初の1文から括弧書き・見出し（`…:`）・矢印の左を
 * 落として、訳の部分だけにする。頼み方は「訳だけ」に直した（`ai.functions.ts`）。
 */
export function chunkTranslation(ja: string | null | undefined): string {
  let t = (ja ?? "").split(/[。．\n]/, 1)[0] ?? "";
  // 矢印・イコールの右が訳（「喝+珍珠奶茶 → タピオカを飲む」）。
  const arrow = t.split(/→|=|＝/);
  t = arrow[arrow.length - 1];
  // 見出し「〜の型:」の後ろが訳。
  const colon = t.split(/[:：]/);
  if (colon.length > 1 && colon[colon.length - 1].trim()) t = colon[colon.length - 1];
  // 括弧書きの注釈は落とす（全角・半角）。
  t = t.replace(/[（(][^）)]*[）)]/g, "");
  return t.replace(/\s+/g, " ").trim();
}

export function chunkSpeechText(chunk: UsageChunk, language?: string | null): string {
  // 画面の札と同じ形を読む（台湾華語の「名詞＋形容詞」に 很 を補った後、`chunk-grammar.ts`）。
  return chunkText(
    { ...chunk, parts: tidyUsageParts(chunk.parts ?? [], language) },
    normalizeTargetLanguage(language) === "en" ? " " : "",
  );
}

/**
 * 量詞から数を落として本体だけにする(「一張」「兩張」「3張」→「張」)。
 * 生成側は数付きで出すが、チャンクでは素の「張」で現れることがあるため、
 * 見比べる前に同じ形に揃える。
 */
function measureWordCore(word: string): string {
  return word.trim().replace(/^[0-9０-９一二三四五六七八九十兩几幾半個]*(?=.)/u, "");
}
