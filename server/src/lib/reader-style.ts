import { explainLanguage } from "./explain-languages";
import { normalizeTargetLanguage } from "./target-lang";

/**
 * **単語の中身を、読む人の言語で自然に書かせる指示**（オーナー 2026-11-16「一からそれぞれの言語翻訳が自然か
 * どうかもう一度チェックして、直訳ではなくて最も自然な訳を表示したい」— 画面の訳の見直しに続けて、AI が書く
 * 単語の中身にも同じ決まりを入れることをオーナーが認めた）。
 *
 * 本番の行（`word_explanations` / `word_level_content`）と6言語の画面を見て、繰り返し出ていた形:
 * 1. 中国語の語順・つなぎ・言い回しを写した直訳（es «bueno para el cuerpo»、vi 請 →「làm ơn」、en "very delicious"、
 *    ja「都市高速鉄道」）
 * 2. 誤訳（es 小聲一點 →「despacio」）
 * 3. 読む人の文の中に中国語の句を、その言語の語のように混ぜる（es «quitarse los zapatos y 換拖鞋»）
 * 4. 同じ物が欄ごとに別の訳語（ja カップホルダー / ドリンクホルダー、en soup dumplings / xiaolongbao）
 * 5. 意味に同格・説明が付く（"MRT, the metro"）— これは `meaningRule` に置く
 * 6. 電報のような注記・文体の混ざり（ja です・ます と だ・である）
 * 7. 誇張（es «obligatorio»）
 * 8. zh-TW の読者: 意味が見出し語そのもの、日本語の語・字形の混入、例文の訳に中文を写す
 * 9. 学ぶ言語の例文そのものが文法的に崩れている（我不見了橡皮擦）
 * 10. 和文・中文の中の半角の「,」と、中国語の語の前後の空白
 *
 * 生成（`generateCard`）・項目の作り直し（`runSectionRegen`）・型の例文を足す呼び出し（`chunkExamplesRule`）が
 * 同じ1つを使う。言語ごとの例は `explain-languages.ts` の `contentStyle`（その言語の読者の指示にだけ入る）。
 * 出す欄・JSON の形・長さの上限は変えない — 指示を足すだけ。保存済みの語は自動で作り直さない（↻ を押した語と
 * 新しい語だけ）。
 */
export function readerStyleRule(opts: {
  /** 読む人の言語（`profiles.ui_language`）。 */
  explainLang: string;
  /** 学習言語の符号（`targetProfile(...).code`）。 */
  targetCode: string;
  /** 学習言語の呼び名（「台湾華語」）。 */
  targetName: string;
  /** 読む人の言語の呼び名（`explanationLanguageName`）。 */
  nl: string;
}): string {
  const { explainLang, targetCode, targetName, nl } = opts;
  const chinese = normalizeTargetLanguage(targetCode).toLowerCase().startsWith("zh");
  const readsTarget = readerReadsTarget(explainLang, targetCode);
  const style = explainLanguage(explainLang)?.contentStyle ?? "";
  return [
    `【訳と解説の自然さ — ${nl}のネイティブが自分の言語のアプリのために書いたように】`,
    `- 直訳しない: ${targetName}の語順・つなぎの語・言い回しを写さず、${nl}でいちばん自然な言い方にする。意味は変えない` +
      (chinese ? `（小聲一點 は「声を小さく」で、「ゆっくり」ではない）。` : `。`),
    `- ${nl}の文の中に${targetName}の句を${nl}の語のように混ぜない。学ぶ語に触れる時だけ「」で引く。`,
    `- 同じ物は、意味・例文の訳・型の訳・関連語・量詞の注・メモのどこでも同じ訳語にする（meaning_ja に書いた語を使い回す）。`,
    `- 注記・解説は語を落とさない完全な文で、文体を1つにそろえる。誇張しない（事実以上に「必須」「欠かせない」「非常に」と書かない）。`,
    readsTarget
      ? `- 読む人は${targetName}をそのまま読めるので、例文の訳（translation / example_translation）と型の訳（ja）は空文字にする（${targetName}の文を写さない）。意味・解説・注記は今までどおり書く。`
      : "",
    style ? `- ${style}` : "",
    `- 返す前に確かめて直す: ${targetName}の例文と型がどれも文法的に正しく、` +
      (chinese
        ? `台湾の人がふだん言う自然な言い方か（✗ 我不見了橡皮擦 → ○ 我的橡皮擦不見了 / ✗ 買文具店的筆記本）。`
        : `ネイティブがふだん言う自然な言い方か。`) +
      `訳が${targetName}の語順を写していないか。`,
  ]
    .filter(Boolean)
    .join("\n");
}

/** 読む人の言語が学習言語と同じ（台湾華語で読む人が台湾華語を学ぶ）か。`chunk-quality.ts` と同じ見方。 */
function readerReadsTarget(explainLang: string, targetCode: string): boolean {
  const r = (explainLang ?? "").trim().toLowerCase();
  const t = normalizeTargetLanguage(targetCode).toLowerCase();
  if (!r) return false;
  return r.startsWith("zh") ? t.startsWith("zh") : r === t;
}
