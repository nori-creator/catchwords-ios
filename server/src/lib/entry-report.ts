/**
 * **利用者の「内容の誤りを報告」の行き先**（2026-10-15）。外の世界に触れない所（試験で全部回せる）。
 *
 * ## これまで
 * 報告は `entry_reports` に積まれ、`status = open` のまま並ぶだけだった。直す道（`reportAndFixSection`）は
 * Pro の人の報告だけその場で動き、無料の人の報告は「記録のみ」。開発者に知らせる仕組みは無く、
 * 管理画面（`/admin/metrics`）を開いた人だけが見た。貓眼（2026-10-15）・尺（10-14、「量詞ではなくて
 * 定規のいいを知りたい」）・鮮奶酪（09-23）はどれも open のまま、誰にも届いていなかった。
 *
 * ## これから
 * 1. 報告が来たら、直せる項目（意味・例文・型・関連語・量詞・読み・品詞）は**その場か裏で**直す案を作り、
 *    別の目で確かめて通った物だけ書く（今までの道そのもの）。
 * 2. 結果を報告の行に残す: `fixed`（直して書いた）/ `needs_review`（直せなかった・確信が足りない）。
 * 3. 開発者に知らせる（メールの鍵が在ればメール。無ければ管理画面と iOS の開発者の一覧）。
 */

export type ReportStatus = "open" | "fixed" | "needs_review" | "resolved" | "dismissed";

/** 直せる項目（`reportAndFixSection` が受ける物）。 */
export const FIXABLE_REPORT_ITEMS = new Set([
  "meaning",
  "example",
  "examples_extra",
  "usage_chunks",
  "related_words",
  "measure_words",
  "taiwan_note",
  "culture_note",
  "japan_note",
  "countability",
  "stress",
  "phrasal_verbs",
  "kanji_breakdown",
  "conjugation",
  "politeness",
  "counters",
  "pitch_accent",
  "word_origin",
  "pronunciation",
  "pos",
]);

export function isFixableReportItem(item: string | null | undefined): boolean {
  return !!item && FIXABLE_REPORT_ITEMS.has(item);
}

/**
 * 移行（`20261015160000_entry_reports_outcome.sql`）が**まだ当たっていない**本番でも落ちないように、
 * 新しい状態を古い3つに写す。`fixed` は「対応済み」、`needs_review` は「未対応」のまま。
 */
export function legacyStatus(status: ReportStatus): "open" | "resolved" | "dismissed" {
  if (status === "fixed") return "resolved";
  if (status === "needs_review") return "open";
  return status;
}

/** 列がまだ無い（移行前）時の失敗か。PostgREST は schema cache の文で返す。 */
export function isMissingColumnError(err: { message?: string; code?: string } | null | undefined) {
  if (!err) return false;
  const m = err.message ?? "";
  return (
    err.code === "42703" ||
    err.code === "PGRST204" ||
    /column .* does not exist/i.test(m) ||
    /could not find the '.*' column/i.test(m) ||
    /schema cache/i.test(m)
  );
}

/** 新しい状態を受け付けない（制約が古い）時の失敗か。 */
export function isStatusConstraintError(
  err: { message?: string; code?: string } | null | undefined,
) {
  if (!err) return false;
  return (
    err.code === "23514" || /entry_reports_status_check|check constraint/i.test(err.message ?? "")
  );
}

export type ReportOutcome = {
  status: ReportStatus;
  /** 何をしたかの一言（開発者が読む。利用者には出さない）。 */
  outcome: string;
};

/** 直した結果を状態と一言にする（`reportAndFixSection` の返事の形から）。 */
export function outcomeFromFix(r: {
  fixed: boolean;
  by: "dictionary" | "jev" | "llm" | "none";
  item?: string | null;
  aiFailed?: boolean;
}): ReportOutcome {
  const item = r.item ?? "?";
  if (r.fixed) {
    const by = r.by === "dictionary" ? "辞書と照らして" : `別の AI（${r.by}）が確かめて`;
    return { status: "fixed", outcome: `${item} を自動で直した（${by}書いた）` };
  }
  if (r.aiFailed)
    return { status: "needs_review", outcome: `${item}: AI が答えず、直しの案を作れなかった` };
  if (r.by === "none") {
    return {
      status: "needs_review",
      outcome: `${item}: 自動では直せなかった（辞書に無い・案が作れない・項目が特定できない）`,
    };
  }
  return {
    status: "needs_review",
    outcome: `${item}: 直しの案は作ったが、別の目（${r.by}）が「今の方が正しい／迷う」と判定`,
  };
}

export type ReportMailInput = {
  headword: string;
  language?: string | null;
  kind: string;
  item?: string | null;
  note?: string | null;
  reporterLang?: string | null;
  status: ReportStatus;
  outcome?: string | null;
  wordId?: string | null;
  reportId?: string | null;
  adminUrl: string;
};

const LANG_NAME: Record<string, string> = {
  ja: "日本語",
  en: "英語",
  "zh-TW": "繁體中文",
};
const STATUS_JA: Record<ReportStatus, string> = {
  open: "未対応",
  fixed: "自動で直した",
  needs_review: "確認が必要",
  resolved: "対応済み",
  dismissed: "却下",
};

/** 開発者へのメール（件名と本文）。**利用者の写真・日記・メールアドレスは入れない。** */
export function reportEmail(r: ReportMailInput): { subject: string; text: string } {
  const item = r.item || r.kind;
  const subject = `[CatchWords] 誤りの報告: ${r.headword}（${item}）— ${STATUS_JA[r.status]}`;
  const lines = [
    `単語: ${r.headword}${r.language ? `（${r.language}）` : ""}`,
    `項目: ${item}（種類: ${r.kind}）`,
    `一言: ${(r.note ?? "").trim() || "（なし）"}`,
    `報告した人の表示言語: ${LANG_NAME[r.reporterLang ?? ""] ?? r.reporterLang ?? "不明"}`,
    `結果: ${STATUS_JA[r.status]}${r.outcome ? ` — ${r.outcome}` : ""}`,
    r.wordId ? `word_id: ${r.wordId}` : null,
    r.reportId ? `report_id: ${r.reportId}` : null,
    ``,
    `管理画面（エラー報告の一覧）: ${r.adminUrl}`,
  ].filter((l): l is string => l !== null);
  return { subject, text: lines.join("\n") };
}

/** iOS の開発者画面・Web の管理画面に出す1行。 */
export type EntryReportRow = {
  id: string;
  headword: string;
  kind: string;
  item: string | null;
  note: string;
  status: ReportStatus;
  outcome: string | null;
  reporter_lang: string | null;
  word_id: string | null;
  created_at: string;
  outcome_at: string | null;
};

/** `[item:meaning] 一言` の形の note から項目と一言を分ける（移行前の行・古い行のため）。 */
export function splitReportNote(note: string | null | undefined): {
  item: string | null;
  note: string;
} {
  const m = /^\[item:([a-z_]+)\]\s*/i.exec(note ?? "");
  if (!m) return { item: null, note: (note ?? "").trim() };
  return { item: m[1] === "auto" ? null : m[1], note: (note ?? "").slice(m[0].length).trim() };
}
