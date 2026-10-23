import fs from "node:fs";
import path from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/integrations/supabase/client.server", () => ({ supabaseAdmin: {} }));

import {
  AI_CONSENT_FUNCTIONS,
  AI_CONSENT_VERSION,
  assertAttestedConsent,
  consentModeFor,
  consentStatusFrom,
  hasCurrentConsent,
  isAiConsentError,
  type AiConsentRow,
} from "./ai-consent";
import {
  assertAiConsent,
  forgetConsent,
  recordAiConsentFor,
  type ConsentDb,
} from "./ai-consent.server";
import { NATIVE_FNS, statusForError } from "./native-fn";
import { readableError } from "./errors";

/** `ai_consents` の偽物（読む・足す・取り消すだけ）。 */
function fakeDb(opts: { rows?: AiConsentRow[]; error?: { code?: string; message?: string } } = {}) {
  const rows: (AiConsentRow & { user_id: string })[] = (opts.rows ?? []).map((r) => ({
    ...r,
    user_id: "u1",
  }));
  const calls = { select: 0, insert: [] as Record<string, unknown>[], revoked: 0 };
  const db: ConsentDb = {
    from: () => ({
      select: () => ({
        eq: (_k, uid) => ({
          order: () => ({
            limit: async () => {
              calls.select++;
              if (opts.error) return { data: null, error: opts.error };
              return { data: rows.filter((r) => r.user_id === uid), error: null };
            },
          }),
        }),
      }),
      insert: async (row) => {
        calls.insert.push(row);
        rows.push({
          user_id: String(row.user_id),
          version: Number(row.version),
          agreed_at: String(row.agreed_at),
          revoked_at: null,
        });
        return { data: null, error: null };
      },
      update: (patch) => ({
        eq: (_k, uid) => ({
          is: async () => {
            for (const r of rows)
              if (r.user_id === uid && r.revoked_at === null) {
                r.revoked_at = String(patch.revoked_at);
                calls.revoked++;
              }
            return { data: null, error: null };
          },
        }),
      }),
    }),
  };
  return { db, calls, rows };
}

const req = (url: string, headers: Record<string, string> = {}) =>
  new Request(url, { method: "POST", headers });
const WEB = req("https://app.example/_serverFn/abc");
const NATIVE = req("https://app.example/api/native-fn");
const agreed: AiConsentRow = {
  version: AI_CONSENT_VERSION,
  agreed_at: "2026-10-03T00:00:00Z",
  revoked_at: null,
};

beforeEach(() => forgetConsent());

describe("consentModeFor（どの呼び出しで確かめるか）", () => {
  it("Web の画面からはいつも確かめる", () => {
    expect(consentModeFor(WEB, {})).toBe("enforce");
    expect(consentModeFor(null, {})).toBe("enforce");
  });
  it("iOS（native-fn）は、見出しも環境変数も無ければ確かめない（古い iOS を壊さない）", () => {
    expect(consentModeFor(NATIVE, {})).toBe("skip");
  });
  it("Supabase の Edge Function（`/native-fn`）も iOS として見分ける", () => {
    expect(consentModeFor(req("https://ref.supabase.co/native-fn"), {})).toBe("skip");
    expect(consentModeFor(req("https://ref.supabase.co/functions/v1/native-fn"), {})).toBe("skip");
    expect(consentModeFor(req("https://ref.supabase.co/functions/v1/native-fn-x"), {})).toBe("enforce");
  });
  it("iOS が同意の見出しを付けたら確かめる（どちらの綴りでも）", () => {
    const h1 = req("https://app.example/api/native-fn", { "AI-Consent-Version": "1" });
    const h2 = req("https://app.example/api/native-fn", { ai_consent_version: "1" });
    expect(consentModeFor(h1, {})).toBe("enforce");
    expect(consentModeFor(h2, {})).toBe("enforce");
  });
  it("AI_CONSENT_ENFORCE_NATIVE を立てたら iOS も必ず確かめる", () => {
    expect(consentModeFor(NATIVE, { AI_CONSENT_ENFORCE_NATIVE: "true" })).toBe("enforce");
    expect(consentModeFor(NATIVE, { AI_CONSENT_ENFORCE_NATIVE: "0" })).toBe("skip");
  });
});

describe("同意の行の読み方", () => {
  it("今の版に同意して取り消していない行があれば同意あり", () => {
    expect(hasCurrentConsent([agreed])).toBe(true);
    expect(hasCurrentConsent([{ ...agreed, revoked_at: "2026-10-04T00:00:00Z" }])).toBe(false);
    expect(hasCurrentConsent([{ ...agreed, version: AI_CONSENT_VERSION - 1 }])).toBe(false);
    expect(hasCurrentConsent([])).toBe(false);
  });
  it("状態は新しい行から作る", () => {
    const s = consentStatusFrom([
      { ...agreed, agreed_at: "2026-10-01T00:00:00Z", revoked_at: "2026-10-02T00:00:00Z" },
      agreed,
    ]);
    expect(s).toMatchObject({ agreed: true, agreedAt: agreed.agreed_at, revokedAt: null });
    expect(consentStatusFrom([]).agreed).toBe(false);
  });
});

describe("assertAiConsent（AI を呼ぶ前の関所）", () => {
  it("同意が無ければ AI_CONSENT_REQUIRED で断る", async () => {
    const { db } = fakeDb();
    const err = await assertAiConsent("u1", { db, request: WEB, env: {} }).catch((e) => e);
    expect(isAiConsentError(err)).toBe(true);
    expect(statusForError(err)).toBe(403);
  });
  it("同意があれば通し、60 秒は DB に聞き直さない", async () => {
    const { db, calls } = fakeDb({ rows: [agreed] });
    await assertAiConsent("u1", { db, request: WEB, env: {} });
    await assertAiConsent("u1", { db, request: WEB, env: {} });
    expect(calls.select).toBe(1);
  });
  it("古い iOS（見出しなし）は DB を見ずに通す。見出しがあれば断る", async () => {
    const { db, calls } = fakeDb();
    await assertAiConsent("u1", { db, request: NATIVE, env: {} });
    expect(calls.select).toBe(0);
    const withHeader = req("https://app.example/api/native-fn", { "AI-Consent-Version": "1" });
    await expect(assertAiConsent("u1", { db, request: withHeader, env: {} })).rejects.toThrow(
      "AI_CONSENT_REQUIRED",
    );
  });
  it("表がまだ無い（移行待ち）時は通す", async () => {
    const { db } = fakeDb({ error: { code: "PGRST205", message: "ai_consents not found" } });
    await expect(assertAiConsent("u1", { db, request: WEB, env: {} })).resolves.toBeUndefined();
  });
  it("DB が読めない時は閉じる側に倒す（503）", async () => {
    const { db } = fakeDb({ error: { code: "08006", message: "connection failure" } });
    const err = await assertAiConsent("u1", { db, request: WEB, env: {} }).catch((e) => e);
    expect(String(err.message)).toContain("AI_CONSENT_CHECK_FAILED");
    expect(statusForError(err)).toBe(503);
  });
});

describe("recordAiConsentFor（同意する・取り消す）", () => {
  it("同意で行を足し、取り消しで revoked_at を入れる。取り消した後は断る", async () => {
    const { db, calls } = fakeDb();
    const on = await recordAiConsentFor(
      "u1",
      { agreed: true, version: AI_CONSENT_VERSION, source: "ios" },
      db,
    );
    expect(on.agreed).toBe(true);
    expect(calls.insert[0]).toMatchObject({ user_id: "u1", version: 1, source: "ios" });
    await assertAiConsent("u1", { db, request: WEB, env: {} });
    const off = await recordAiConsentFor(
      "u1",
      { agreed: false, version: AI_CONSENT_VERSION, source: "web" },
      db,
    );
    expect(off.agreed).toBe(false);
    expect(off.revokedAt).not.toBeNull();
    // 覚えていた同意も消えている（同じサーバではすぐ効く）。
    await expect(assertAiConsent("u1", { db, request: WEB, env: {} })).rejects.toThrow(
      "AI_CONSENT_REQUIRED",
    );
  });
  it("古い版の同意は今の同意にしない", async () => {
    const { db, calls } = fakeDb();
    await expect(
      recordAiConsentFor("u1", { agreed: true, version: 0, source: "web" }, db),
    ).rejects.toThrow("AI_CONSENT_REQUIRED");
    expect(calls.insert).toEqual([]);
  });
});

describe("登録前（ゲスト）の同意", () => {
  it("今の版の同意が付いていなければ断る", () => {
    expect(() => assertAttestedConsent(undefined)).toThrow("AI_CONSENT_REQUIRED");
    expect(() => assertAttestedConsent(0)).toThrow("AI_CONSENT_REQUIRED");
    expect(() => assertAttestedConsent(AI_CONSENT_VERSION)).not.toThrow();
  });
});

describe("AI を呼ぶ関数は、どれも送る前に同意を確かめる", () => {
  const files = [
    "ai.functions.ts",
    "scan.functions.ts",
    "jev.functions.ts",
    "wordbook.functions.ts",
    "journal.functions.ts",
    "first-catch-ai.functions.ts",
    "images.functions.ts",
    "category-backfill.functions.ts",
  ].map((f) => fs.readFileSync(path.join(__dirname, f), "utf8"));
  const bodyOf = (name: string) => {
    for (const src of files) {
      const at = src.indexOf(`export const ${name} = createServerFn`);
      if (at < 0) continue;
      const next = src.indexOf("\nexport ", at + 1);
      return src.slice(at, next < 0 ? undefined : next);
    }
    return "";
  };
  for (const name of AI_CONSENT_FUNCTIONS) {
    it(name, () => {
      const body = bodyOf(name);
      expect(body, name).not.toBe("");
      expect(body).toMatch(/assertAiConsent\(|assertAttestedConsent\(/);
    });
  }
  it("登録前のチュートリアルの道も確かめる", () => {
    const guest = fs.readFileSync(path.join(__dirname, "first-catch-guest.server.ts"), "utf8");
    expect(guest).toMatch(/assertAttestedConsent\(data\.aiConsentVersion\)/);
  });
});

describe("iOS（native-fn）", () => {
  it("同意を読む・記録する関数を呼べる", () => {
    expect(Object.keys(NATIVE_FNS)).toEqual(
      expect.arrayContaining(["getAiConsent", "recordAiConsent"]),
    );
  });
  it("iOS の AI の関数は全部 native-fn に在る（一覧がずれていない）", () => {
    for (const name of AI_CONSENT_FUNCTIONS.slice(0, 9))
      expect([name, name in NATIVE_FNS]).toEqual([name, true]);
  });
});

describe("画面の文", () => {
  it("同意が無い失敗は、どの言語でも辞書の文に直す", () => {
    const t = (k: string) => `[${k}]`;
    const e = new Error("AI_CONSENT_REQUIRED: AI を使う機能は…");
    expect(readableError(e, "fallback", "en", t)).toBe("[err.aiConsent]");
    expect(readableError(e, "fallback", "ja", t)).toBe("[err.aiConsent]");
  });
});

describe("移行（ai_consents）", () => {
  // The schema now lives in the app repository's single baseline (pg_dump style).
  const sql = fs.readFileSync(
    path.join(__dirname, "../../../supabase/migrations/20261020103934_baseline_part2_tables_constraints_policies.sql"),
    "utf8",
  );
  it("RLS を入れ、本人は読むだけ（書く決まりを置かない）", () => {
    expect(sql).toContain("ALTER TABLE public.ai_consents ENABLE ROW LEVEL SECURITY;");
    expect(sql).toContain(
      "CREATE POLICY ai_consents_select_own ON public.ai_consents FOR SELECT TO authenticated USING ((auth.uid() = user_id));",
    );
    expect(sql.match(/CREATE POLICY [^\n]* ON public\.ai_consents /g)).toHaveLength(1);
    expect(sql).toContain(
      "ai_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE",
    );
  });
});

