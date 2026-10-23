import { describe, expect, it } from "vitest";
import {
  isFixableReportItem,
  isMissingColumnError,
  isStatusConstraintError,
  legacyStatus,
  outcomeFromFix,
  reportEmail,
  splitReportNote,
} from "./entry-report";
import { notifyConfig, sendDeveloperEmail } from "./report-notify.server";

/**
 * 利用者の「内容の誤りを報告」の行き先（2026-10-15）。報告は open のまま並ぶだけで、誰にも届いていなかった。
 */
describe("legacyStatus — 移行前の本番でも落ちない", () => {
  it("新しい状態を古い3つに写す", () => {
    expect(legacyStatus("fixed")).toBe("resolved");
    expect(legacyStatus("needs_review")).toBe("open");
    expect(legacyStatus("open")).toBe("open");
    expect(legacyStatus("dismissed")).toBe("dismissed");
  });

  it("列が無い・制約が古い失敗を見分ける（PostgREST の言い方も）", () => {
    expect(
      isMissingColumnError({
        message: 'column "outcome" of relation "entry_reports" does not exist',
        code: "42703",
      }),
    ).toBe(true);
    expect(
      isMissingColumnError({
        message: "Could not find the 'outcome' column of 'entry_reports' in the schema cache",
        code: "PGRST204",
      }),
    ).toBe(true);
    expect(isMissingColumnError({ message: "permission denied" })).toBe(false);
    expect(
      isStatusConstraintError({
        message: 'new row violates check constraint "entry_reports_status_check"',
        code: "23514",
      }),
    ).toBe(true);
    expect(isStatusConstraintError({ message: "timeout" })).toBe(false);
  });
});

describe("outcomeFromFix — 直した結果を状態と一言に", () => {
  it("直して書いた → fixed", () => {
    const o = outcomeFromFix({ fixed: true, by: "jev", item: "meaning" });
    expect(o.status).toBe("fixed");
    expect(o.outcome).toContain("meaning");
  });

  it("判定が通らなかった・AI が答えなかった・直せなかった → needs_review（理由が読める）", () => {
    expect(outcomeFromFix({ fixed: false, by: "llm", item: "meaning" })).toMatchObject({
      status: "needs_review",
    });
    expect(
      outcomeFromFix({ fixed: false, by: "none", item: "meaning", aiFailed: true }).outcome,
    ).toContain("AI が答えず");
    expect(outcomeFromFix({ fixed: false, by: "none", item: "pronunciation" }).outcome).toContain(
      "自動では直せなかった",
    );
  });

  it("直せる項目の一覧", () => {
    expect(isFixableReportItem("meaning")).toBe(true);
    expect(isFixableReportItem("usage_chunks")).toBe(true);
    expect(isFixableReportItem("pronunciation")).toBe(true);
    expect(isFixableReportItem("auto")).toBe(false);
    expect(isFixableReportItem(null)).toBe(false);
  });
});

describe("splitReportNote — 古い行の [item:…] を読む", () => {
  it("項目と一言に分ける", () => {
    expect(splitReportNote("[item:meaning] 量詞ではなくて　定規のいいを知りたい")).toEqual({
      item: "meaning",
      note: "量詞ではなくて　定規のいいを知りたい",
    });
    expect(splitReportNote("[item:auto]")).toEqual({ item: null, note: "" });
    expect(splitReportNote("ただの一言")).toEqual({ item: null, note: "ただの一言" });
  });
});

describe("reportEmail — 開発者へのメール", () => {
  it("見出し語・項目・一言・報告者の言語・結果・管理画面の URL が入る（本番の 尺 の報告そのもの）", () => {
    const m = reportEmail({
      headword: "尺",
      language: "zh-TW",
      kind: "meaning",
      item: "meaning",
      note: "量詞ではなくて　定規のいいを知りたい",
      reporterLang: "ja",
      status: "needs_review",
      outcome: "meaning: 直しの案は作ったが、別の目（jev）が「今の方が正しい／迷う」と判定",
      wordId: "888d2ea1-9877-4401-bd04-e242273269b0",
      reportId: "46a456f5-6aff-460f-a656-9846a980b83d",
      adminUrl: "https://catchwords.lovable.app/admin/metrics",
    });
    expect(m.subject).toBe("[CatchWords] 誤りの報告: 尺（meaning）— 確認が必要");
    expect(m.text).toContain("単語: 尺（zh-TW）");
    expect(m.text).toContain("一言: 量詞ではなくて　定規のいいを知りたい");
    expect(m.text).toContain("報告した人の表示言語: 日本語");
    expect(m.text).toContain("結果: 確認が必要 — meaning:");
    expect(m.text).toContain("https://catchwords.lovable.app/admin/metrics");
  });

  it("英語で読む人の報告（貓眼）: 一言が無ければ「（なし）」", () => {
    const m = reportEmail({
      headword: "貓眼",
      kind: "meaning",
      item: "meaning",
      note: "",
      reporterLang: "en",
      status: "fixed",
      adminUrl: "https://x/admin/metrics",
    });
    expect(m.text).toContain("一言: （なし）");
    expect(m.text).toContain("報告した人の表示言語: 英語");
    expect(m.subject).toContain("自動で直した");
  });
});

describe("sendDeveloperEmail — 鍵が無ければ送らない・本物には送らない", () => {
  const mail = { subject: "s", text: "t" };

  it("RESEND_API_KEY が無ければ skipped（fetch は呼ばれない）", async () => {
    let calls = 0;
    const fetchFn = (async () => {
      calls += 1;
      return new Response("{}", { status: 200 });
    }) as unknown as typeof fetch;
    expect(await sendDeveloperEmail(mail, { env: {}, fetchFn })).toBe("skipped");
    expect(calls).toBe(0);
  });

  it("鍵が在れば Resend に POST する（送り先は既定でオーナー、上書きできる）", async () => {
    const seen: Array<{ url: string; body: Record<string, unknown>; auth: string }> = [];
    const fetchFn = (async (url: string | URL | Request, init?: RequestInit) => {
      seen.push({
        url: String(url),
        body: JSON.parse(String(init?.body)),
        auth: String((init?.headers as Record<string, string>).Authorization),
      });
      return new Response("{}", { status: 200 });
    }) as unknown as typeof fetch;
    expect(await sendDeveloperEmail(mail, { env: { RESEND_API_KEY: "re_test" }, fetchFn })).toBe(
      "sent",
    );
    expect(seen[0].url).toBe("https://api.resend.com/emails");
    expect(seen[0].auth).toBe("Bearer re_test");
    expect(seen[0].body.to).toEqual(["nori0122hiroshima@gmail.com"]);
    expect(notifyConfig({ RESEND_API_KEY: "k", REPORT_NOTIFY_TO: "dev@example.com" }).to).toBe(
      "dev@example.com",
    );
  });

  it("Resend が失敗しても投げない（failed）", async () => {
    const fetchFn = (async () => new Response("no", { status: 500 })) as unknown as typeof fetch;
    expect(await sendDeveloperEmail(mail, { env: { RESEND_API_KEY: "k" }, fetchFn })).toBe(
      "failed",
    );
    const throwing = (async () => {
      throw new Error("offline");
    }) as unknown as typeof fetch;
    expect(
      await sendDeveloperEmail(mail, { env: { RESEND_API_KEY: "k" }, fetchFn: throwing }),
    ).toBe("failed");
  });
});
