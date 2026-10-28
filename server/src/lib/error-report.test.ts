import { describe, expect, it, vi } from "vitest";
import { SERVER_SENTRY_DSN, errorEnvelope, parseDsn, reportServerError, stackFrames } from "./error-report";

describe("parseDsn", () => {
  it("reads the envelope URL and key from the DSN", () => {
    expect(parseDsn(SERVER_SENTRY_DSN)).toEqual({
      url: "https://o4512328596520960.ingest.us.sentry.io/api/4512328628240384/envelope/",
      key: "379c08be3ddf277d076d2f8e79d9cc23",
    });
  });
  it("refuses something that is not a DSN", () => {
    expect(parseDsn("")).toBeNull();
    expect(parseDsn("https://example.com/12")).toBeNull();
    expect(parseDsn("https://key@example.com/not-a-number")).toBeNull();
  });
});

describe("stackFrames", () => {
  it("reads V8 frames, oldest first, and marks the runtime's own as not the app's", () => {
    const stack = [
      "Error: boom",
      "    at generateCard (file:///var/tmp/sb/native-fn/bundle.js:12:345)",
      "    at async file:///var/tmp/sb/native-fn/bundle.js:99:1",
      "    at ext:runtime/serve.js:1:2",
    ].join("\n");
    const frames = stackFrames(stack);
    expect(frames.map((f) => f.function ?? "")).toEqual(["", "", "generateCard"]);
    expect(frames[2]).toMatchObject({ lineno: 12, colno: 345, in_app: true });
    expect(frames[0].in_app).toBe(false);
  });
});

describe("errorEnvelope", () => {
  it("is three JSON lines with the function, the error and nothing from the request", () => {
    const err = new TypeError("x is undefined");
    const env = errorEnvelope(err, {
      fn: "generateCard",
      status: 500,
      dsn: SERVER_SENTRY_DSN,
      eventId: "a".repeat(32),
      now: new Date("2026-10-27T00:00:00Z"),
    });
    const [head, item, event] = env.split("\n").map((l) => JSON.parse(l));
    expect(head).toMatchObject({ event_id: "a".repeat(32), dsn: SERVER_SENTRY_DSN });
    expect(item).toEqual({ type: "event" });
    expect(event).toMatchObject({
      level: "error",
      tags: { fn: "generateCard", status: "500" },
      exception: { values: [{ type: "TypeError", value: "x is undefined" }] },
    });
    expect(Object.keys(event)).not.toContain("request");
    expect(Object.keys(event)).not.toContain("user");
  });
});

describe("reportServerError", () => {
  it("POSTs the envelope with the key, and never throws when Sentry is unreachable", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response(null, { status: 200 }));
    await reportServerError(new Error("boom"), { fn: "suggestWords", status: 503 }, { fetchImpl });
    expect(fetchImpl).toHaveBeenCalledOnce();
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toContain("/api/4512328628240384/envelope/");
    expect(init.headers["X-Sentry-Auth"]).toContain("sentry_key=379c08be3ddf277d076d2f8e79d9cc23");

    const failing = vi.fn().mockRejectedValue(new Error("offline"));
    await expect(reportServerError(new Error("boom"), { fn: "x", status: 500 }, { fetchImpl: failing })).resolves.toBeUndefined();
  });
});
