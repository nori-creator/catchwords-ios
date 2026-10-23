import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
/**
 * **報告からの直しを、共有の語に書いてよいか**の決まり。
 *
 * 語（`words` の行）は**全員で共有している**（見出し語と言語で1行）。
 * 1人の報告でAIが作り直した案をそのまま書くと、その語を持つ全員の
 * カードが変わる。`QA.md` の約束:
 *
 * > User-reported canonical corrections require validation before global
 * > propagation.
 *
 * だから**作った目とは別の目**（Jev、使えなければ別の呼び出しのAI）に
 * 「前と後、どちらが正しいか」を聞き、**後の方が正しいと十分に言えた
 * ときだけ**書く。言えなければ書かずに報告として残す（管理画面の
 * 確認待ちに載る）。
 */

/** 誰が確かめたか。`none` は確かめられなかった（鍵が無い・落ちた）。 */
export type JudgeSource = "jev" | "llm" | "none";

export type CorrectionVerdict = {
  by: JudgeSource;
  /** 「新しい方が正しい」の確率。確かめられなければ `null`。 */
  pAfter: number | null;
};

/**
 * 書いてよい確率の下限。
 *
 * **0.5 ではない。** 「どちらとも言えない」を書き換えの許可にしない —
 * 間違っていたときに壊れるのは報告した人だけではない。7割の確からしさを
 * 求め、届かなければ人の確認に回す。
 */
export const ACCEPT_THRESHOLD = 0.7;

export function shouldApplyCorrection(v: CorrectionVerdict): boolean {
  if (v.by === "none") return false;
  if (v.pAfter == null || !Number.isFinite(v.pAfter)) return false;
  return v.pAfter >= ACCEPT_THRESHOLD;
}

/**
 * 別のAIの答え（JSON）を確率に直す。**「新しい方」と言ったときだけ**
 * その確信度を使い、それ以外は 0（書かない）。
 * 形が違えば確かめられなかった扱い。
 */
export function verdictFromLlm(raw: unknown): CorrectionVerdict {
  const v = raw as { verdict?: unknown; confidence?: unknown } | null;
  if (!v || typeof v !== "object") return { by: "none", pAfter: null };
  const conf =
    typeof v.confidence === "number" && Number.isFinite(v.confidence) ? v.confidence : NaN;
  if (v.verdict === "after") {
    if (!(conf >= 0 && conf <= 1)) return { by: "none", pAfter: null };
    return { by: "llm", pAfter: conf };
  }
  if (v.verdict === "before" || v.verdict === "unsure") return { by: "llm", pAfter: 0 };
  return { by: "none", pAfter: null };
}

/**
 * **発音・品詞は、AIに作らせずに辞書と照らす。**
 *
 * 読みと品詞は「その語の事実」で、文ではない（`ARCHITECTURE.md`「Prefer
 * deterministic/licensed data for facts that should not vary」）。AIに作り
 * 直させると、注音の声調のような**いちばん間違えやすい所**を、別の目も
 * 通さずに全員のカードへ書くことになる。
 *
 * 辞書の行が**確かめられた物**（`source` が `ai` 以外）で、しかも今の値と
 * 違うときだけ、辞書の値で直す。そうでなければ直さない（報告として残る）。
 */
export type DictRowForFix = {
  source: string | null;
  reading: string | null;
  readingAlt: string | null;
  pos: string | null;
};
export type WordForFix = {
  source: string | null;
  reading_zhuyin: string | null;
  pinyin: string | null;
  part_of_speech: string | null;
};

export function dictionaryFixPatch(
  kind: "pronunciation" | "pos",
  word: WordForFix,
  dict: DictRowForFix | null,
): Record<string, string> | null {
  // 確認済みの語は、報告1つでは書き換えない（`constitution §2-1`）。
  if (word.source === "verified") return null;
  // AIが作った辞書の行は、AIが作ったカードを直す根拠にならない。
  if (!dict || !dict.source || dict.source === "ai") return null;
  const norm = (v: string | null | undefined) => (v ?? "").normalize("NFC").trim();
  if (kind === "pronunciation") {
    const patch: Record<string, string> = {};
    if (norm(dict.reading) && norm(dict.reading) !== norm(word.reading_zhuyin)) {
      patch.reading_zhuyin = norm(dict.reading);
    }
    if (norm(dict.readingAlt) && norm(dict.readingAlt) !== norm(word.pinyin)) {
      patch.pinyin = norm(dict.readingAlt);
    }
    return Object.keys(patch).length > 0 ? patch : null;
  }
  if (norm(dict.pos) && norm(dict.pos) !== norm(word.part_of_speech)) {
    return { part_of_speech: norm(dict.pos) };
  }
  return null;
}

/**
 * **確かな辞書に無い語の、発音・品詞の直し。**（オーナー指示 2026-09-23 の3回目
 * 「ユーザーが単語の詳細などでエラーを報告したときに自動的に正しく修正する
 * システムを構築して」）
 *
 * 上の `dictionaryFixPatch` は確かな辞書の行がある語しか直せない。辞書に無い語
 * （写真で見つけた新しい語など）は、報告しても直らなかった。ここでは
 * **2つの別の AI に独立に聞いた答えが完全に一致したとき**だけ直す案を作る。
 * 書く前にさらに `judgeCorrection`（Jev）が前と後を比べる — 3つの目が揃わない
 * 限り、全員の語は書き換わらない。
 *
 *  ・確認済みの語（`verified`）は書き換えない
 *  ・答えが1つでも食い違えば直さない（揺れる答えは事実ではない）
 *  ・台湾華語は、注音の音節の数と漢字の数が合わなければ直さない
 *  ・今の値と同じなら直さない
 */
export type ReadingAnswer = { reading: string; reading_alt: string; pos: string };

export function consensusFixPatch(
  kind: "pronunciation" | "pos",
  word: WordForFix & { headword: string; language: string | null },
  answers: ReadingAnswer[],
): Record<string, string> | null {
  if (word.source === "verified") return null;
  if (answers.length < 2) return null;
  const norm = (v: string | null | undefined) =>
    (v ?? "").normalize("NFC").replace(/\s+/g, " ").trim();
  const same = (pick: (a: ReadingAnswer) => string) => {
    const vals = answers.map((a) => norm(pick(a)));
    return vals[0] && vals.every((v) => v === vals[0]) ? vals[0] : null;
  };
  if (kind === "pos") {
    const pos = same((a) => a.pos);
    return pos && pos !== norm(word.part_of_speech) ? { part_of_speech: pos } : null;
  }
  const reading = same((a) => a.reading);
  if (!reading) return null;
  const alt = same((a) => a.reading_alt);
  if ((word.language ?? DEFAULT_TARGET_LANGUAGE).startsWith("zh")) {
    const han = [...word.headword].filter((ch) => /\p{Script=Han}/u.test(ch)).length;
    if (han > 0 && reading.split(" ").length !== han) return null;
  }
  const patch: Record<string, string> = {};
  if (reading !== norm(word.reading_zhuyin)) patch.reading_zhuyin = reading;
  if (alt && alt !== norm(word.pinyin)) patch.pinyin = alt;
  return Object.keys(patch).length > 0 ? patch : null;
}
