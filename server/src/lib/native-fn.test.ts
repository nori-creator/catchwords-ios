import { describe, expect, it } from "vitest";
import { NATIVE_ADMIN_FNS, NATIVE_FNS, publicMessage, statusForError } from "./native-fn";

describe("native-fn allowlist", () => {
  it("exposes the capture, card, save and review functions iOS needs", () => {
    for (const name of [
      "suggestWords",
      "warmUpCapture",
      "suggestWordCandidates",
      "logCandidatePick",
      "generateCard",
      "saveSticker",
      "checkOwnedWord",
      "recordEncounter",
      "synthesizeSpeech",
      "gradeReview",
      "deleteMyAccount",
      "setStickerCategory",
      "saveMyCategory",
      "deleteMyCategory",
      "correctMyJournal",
      "getJournalPrompts",
      "listJournal",
      "getMyStats",
      "extractWordbook",
      "getReaderMeanings",
      "searchImageCandidates",
      "setStickerPlaceholder",
      "storeAppleAuthCode",
    ]) {
      expect(NATIVE_FNS[name]).toBeTypeOf("function");
    }
  });

  it("does not expose the speaking review or the catch voice note (owner decision 2026-10-02)", () => {
    for (const name of ["getSpeakingFeedback", "getSpeakingScaffold", "setStickerVoiceVideo"]) {
      expect(NATIVE_FNS[name]).toBeUndefined();
    }
  });

  it("exposes only the listed admin functions (AI settings 2026-10-09, users and metrics 2026-10-11)", () => {
    const admin = Object.keys(NATIVE_FNS).filter((n) => n.toLowerCase().includes("admin"));
    expect(admin.sort()).toEqual([...NATIVE_ADMIN_FNS].sort());
    for (const name of admin) {
      expect(name.startsWith("admin")).toBe(true);
      expect(NATIVE_FNS[name]).toBeTypeOf("function");
    }
    // ほかの管理者向けの道具（辞書の取り込み・発音の作り置き・単価の書き換え）は載せない。
    for (const name of [
      "setTtsVoiceAdmin",
      "pregenerateDictionaryTts",
      "importDictionaryEntries",
      "checkIsAdmin",
      "setBetaUnitCosts",
      "listAdminUsers",
      "getAdminUserDetail",
    ]) {
      expect(NATIVE_FNS[name]).toBeUndefined();
    }
  });

  it("exposes the developer's users and metrics only under admin names (owner decision 2026-10-11)", () => {
    for (const name of [
      "adminListUsers",
      "adminGetUserDetail",
      "adminGetOverview",
      "adminGetDashboard",
      "adminGetBetaMetrics",
    ]) {
      expect(NATIVE_ADMIN_FNS).toContain(name);
      expect(NATIVE_FNS[name]).toBeTypeOf("function");
    }
  });

  it("resolves every admin function to a real server function", async () => {
    for (const name of NATIVE_ADMIN_FNS) {
      expect(await NATIVE_FNS[name]()).toBeTypeOf("function");
    }
  });

  it("does not resolve prototype keys", () => {
    expect(Object.prototype.hasOwnProperty.call(NATIVE_FNS, "constructor")).toBe(false);
    expect(Object.prototype.hasOwnProperty.call(NATIVE_FNS, "__proto__")).toBe(false);
  });
});

describe("statusForError", () => {
  it("maps auth, cap, validation and other failures", () => {
    expect(statusForError(new Error("Unauthorized: Invalid token"))).toBe(401);
    expect(statusForError(new Error("Forbidden: 管理者だけが使えます"))).toBe(403);
    expect(statusForError(new Error("1日の利用上限(200回)に達しました。"))).toBe(429);
    const zod = Object.assign(new Error("[]"), { name: "ZodError" });
    expect(statusForError(zod)).toBe(400);
    const bad = Object.assign(new Error("知らない会社です: nope"), { name: "BadRequestError" });
    expect(statusForError(bad)).toBe(400);
    expect(statusForError(new Error("AI_TEST_DAILY_LIMIT: 試しは1日 300 枚までです"))).toBe(429);
    expect(
      statusForError(new Error("AI_TEST_PHOTO_MISMATCH: cafe の写真が違います（アプリを最新に）")),
    ).toBe(400);
    expect(statusForError(new Error("boom"))).toBe(500);
  });
});

describe("publicMessage", () => {
  it("hides validation internals and truncates long messages", () => {
    const zod = Object.assign(new Error('[{"path":["x"]}]'), { name: "ZodError" });
    expect(publicMessage(zod)).not.toContain("path");
    expect(publicMessage(new Error("x".repeat(1000))).length).toBe(300);
  });
});
