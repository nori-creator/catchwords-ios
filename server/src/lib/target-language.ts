/**
 * 「その文字列は、学んでいる言語の見出し語として通してよいか」を決める所。
 *
 * ## なぜ要るか
 * 母語(日本語)で調べる欄がある。入力は AI が台湾華語の見出し語に解決して
 * `headword_zh` で返す。ところが呼ぶ側は
 *
 *   const resolved = c.headword_zh || headword;
 *
 * と書いてあった。**解決できなかったときに日本語がそのまま見出しになる。**
 * 実際「シャーペン」がカタカナのまま図鑑に入り、注音だけが下に付いた。
 * 画面はエラーを出さない — 学習者は自分の母語を「台湾華語の単語」として
 * 覚えることになる。
 *
 * 見出し語は**学んでいる言語だけ**を通す。通せないなら、黙って落とさず
 * 呼ぶ側で作り直させる。
 */

/**
 * ## 2026-08-24: 判定そのものは `target-profile.ts` に移した
 * 言語ごとの違いを1つの表に集めたので、**文字の規則もその表が持つ**。
 * ここに同じ正規表現を残すと、英語版を足したときに片方だけ直る
 * (この app が声・写真・演出で繰り返した形)。ここは呼ぶ側のための口。
 */

import { EN_PROFILE, ZH_TW_PROFILE, headwordCore, targetProfile } from "./target-profile";
import { TARGET_LANGUAGES } from "./target-lang";

/**
 * 台湾華語の見出し語として通せるか。
 *
 * 通す: 漢字だけ(「文旦」「橡皮擦」)。日本語の漢字語と見分けは付かないが、
 *       その場合たいてい中国語としても通じるので、通してよい。
 * 落とす: かなを含む(「シャーペン」「けしごむ」)、欧文・キリル文字・
 *         ハングルを含む(「pencil」「シャーペンpen」)、漢字が1つも無い。
 */
export function isZhHeadword(text: string): boolean {
  return ZH_TW_PROFILE.headwordOk(text);
}

/** 英語の見出し語として通せるか。 */
export function isEnHeadword(text: string): boolean {
  return EN_PROFILE.headwordOk(text);
}

/**
 * 学んでいる言語の見出し語として通せるか。
 *
 * **知らない言語は判定しない。** ここで `targetProfile` の既定
 * (台湾華語)に落とすと、ドイツ語を学ぶ設定の人の "Bleistift" が
 * 「漢字が無い」という理由で静かに消える。落とすなら根拠が要る。
 */
export function isTargetHeadword(text: string, targetLanguage: string): boolean {
  // 中国語系はどれも繁体字の規則で見る(簡体字で入れた人も通す)。
  if (targetLanguage.startsWith("zh")) return isZhHeadword(text);
  if ((TARGET_LANGUAGES as readonly string[]).includes(targetLanguage)) {
    return targetProfile(targetLanguage).headwordOk(text);
  }
  return !!headwordCore(text ?? "");
}

/**
 * 生成が返した見出し語を、**捨てる前に一度だけ直す。**
 *
 * ## なぜ要るか（オーナー報告 2026-09-22「カメラの検索で日本語での検索ができない」）
 * 母語で打った語は AI が学習言語の見出し語に直して返す。その候補は
 * `isTargetHeadword` を通らなければ捨てられる — **捨てられた数がゼロに
 * なると、画面には「単語が見つかりませんでした」とだけ出る。**
 * 打った人からは、探しに行ったことすら分からない。
 *
 * ところが生成は、頼んでいなくても注釈を足してくることがある:
 *
 *   「烤肉 (BBQ)」「燒肉（日式）」「滷肉飯 lǔ ròu fàn」
 *
 * 括弧は `headwordCore` が落とすので「燒肉（日式）」は通るが、
 * **ラテン文字が1つでも混ざった瞬間に丸ごと落ちる**。中身は正しいのに、
 * 付け足しのせいで「そんな語は無い」と言うことになる。
 *
 * ここでは**先頭から続く、その言語の見出し語として通る一番長い部分**を
 * 取り出す。取れなければ `null` — 直せない物を無理に通すと、今度は
 * 母語がそのまま見出しになる元の不具合に戻る。
 *
 * 「シャーペン」のようにかなだけの物は、どこを切っても通らないので
 * `null` のまま落ちる（**そこは緩めない**）。
 */
export function coerceTargetHeadword(raw: string, targetLanguage: string): string | null {
  const text = (raw ?? "").trim();
  if (!text) return null;
  if (isTargetHeadword(text, targetLanguage)) return text;
  // 先頭から1文字ずつ伸ばし、**通った中でいちばん長い所**を憶えておく。
  // 前から切るのは、注釈がたいてい後ろに付くから（「烤肉 (BBQ)」）。
  let best: string | null = null;
  for (let i = 1; i <= text.length; i++) {
    const head = text.slice(0, i).trim();
    if (head && isTargetHeadword(head, targetLanguage)) best = head;
  }
  if (best === null) return null;
  // 切った所に飾りが残る（「烤肉 (」）。`headwordCore` はこれを落として
  // 判定するので**通ってしまう**が、そのまま保存すると図鑑に飾りが残る。
  // 落ちる文字なら、落としてから返す。
  const trimmed = best.replace(
    /[\s，、。．・…！？!?,.:;：；「」『』（）()【】〔〕[\]{}"'‘’“”—–\-~〜]+$/u,
    "",
  );
  return trimmed && isTargetHeadword(trimmed, targetLanguage) ? trimmed : best;
}

/**
 * **見出し語は学習言語の語だけ**（オーナー指示 2026-10-15「打った語が母語でも、結果の見出し語は必ず学習言語。
 * 台湾華語なら漢字だけ — かな・ローマ字・母語の文字を入れない」）。
 *
 * 候補を順に見て、学習言語の見出し語として通る（直せる）最初の物を返す。どれも通らなければ `null` —
 * 呼ぶ側は**母語のまま見出しにせず**断る（`NOT_TARGET_LANGUAGE`）。台湾華語の関所はかな・欧文に加えて
 * 日本の新字体だけの字（図・駅）も落とす（`kanji-forms.ts`）。
 */
export function pickLearningHeadword(
  candidates: ReadonlyArray<string | null | undefined>,
  targetLanguage: string,
): string | null {
  for (const raw of candidates) {
    const head = coerceTargetHeadword(raw ?? "", targetLanguage);
    if (head) return head;
  }
  return null;
}

/**
 * **AI が返した候補の並びから、学習言語の語だけを残す。**
 *
 * ## なぜ要るか（オーナー報告 2026-10-02「図鑑の英語にノートが入っている」）
 * 英語を学んでいる人の図鑑に「ノート」（カタカナ）と「拿鐵」（繁体字）が
 * `language = 'en'` で入っていた。どちらも写真から撮った語。
 * 撮った後の候補（`suggestWords`）とスキャンの検出（`detectScan`）は、
 * AI の返事を**学習言語かどうか見ずに**そのまま画面へ出していた —
 * 打った語の候補（`suggestWordCandidates`）だけがこの関所を持っていた。
 * スキャンの画面に至っては「漢字を含む物だけ」を残す決め打ちで、
 * 英語を学ぶ人には**英語の語を捨てて漢字の語だけ**を見せていた。
 *
 * 1つずつ `coerceTargetHeadword` で直し（「烤肉 (BBQ)」→「烤肉」）、
 * 直せない物は捨てる。`alternatives`（言い換えの候補）も同じ関所に通す。
 * 同じ語が2回出たら後のほうを捨てる。
 */
export function keepTargetHeadwords<T extends { headword: string; alternatives?: string[] }>(
  items: readonly T[],
  targetLanguage: string,
): T[] {
  const out: T[] = [];
  const seen = new Set<string>();
  for (const it of items) {
    const head = coerceTargetHeadword(it.headword, targetLanguage);
    if (!head || seen.has(head)) continue;
    seen.add(head);
    const next: T = { ...it, headword: head };
    if (Array.isArray(it.alternatives)) {
      next.alternatives = it.alternatives
        .map((a) => coerceTargetHeadword(a, targetLanguage))
        .filter((a): a is string => !!a && a !== head);
    }
    out.push(next);
  }
  return out;
}

/**
 * 保存の関所が投げる印。**文ではなく印**にするのは、画面がこれを
 * その人の表示言語の文に直すため（`errors.ts`）。サーバの日本語の文を
 * そのまま投げると、英語・繁體中文で使っている人に日本語が出る。
 */
export const NOT_TARGET_LANGUAGE = "NOT_TARGET_LANGUAGE";

/**
 * **学習言語の語でなければ、保存させない。**（オーナー報告 2026-10-02）
 *
 * `words` は `(language, headword)` で全員が共有する行なので、
 * 「ノート」を `en` として1度保存すると、その行は英語の語として残り続ける
 * （図鑑・復習・4択の誤答の池に出る）。画面の側で何重に止めても、
 * 止め忘れた道が1本あれば同じことが起きる — 今回がそれだった。
 * だから**行を作る所（`upsertWord`）で必ず止める**。
 *
 * 黙って直さない（言語を付け替えない・見出しを書き換えない）。直すと、
 * 撮った人が選んだのと違う物が図鑑に入る。投げて、画面に理由を出させる。
 */
export function assertTargetHeadword(headword: string, language: string): void {
  if (!isTargetHeadword((headword ?? "").trim(), language)) {
    throw new Error(NOT_TARGET_LANGUAGE);
  }
}
