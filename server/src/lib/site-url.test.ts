import { describe, it, expect } from "vitest";
import {
  FALLBACK_SITE_URL,
  configuredSiteUrl,
  normalizeSiteUrl,
  siteUrl,
  siteUrlFor,
} from "./site-url";

/**
 * サイトの住所（オーナー指示 2026-08-31「ドメインも独自で取得したい」）。
 *
 * ここが狂うと canonical と og:url が壊れる。**画面には何も出ない**ので、
 * 目で見て気づける類ではない。検査でしか捕まえられない。
 */

const own = { VITE_SITE_URL: "https://catchwords.app" };

describe("normalizeSiteUrl", () => {
  it("末尾のスラッシュを落とす（住所の形をそろえる）", () => {
    expect(normalizeSiteUrl("https://catchwords.app/")).toBe("https://catchwords.app");
    expect(normalizeSiteUrl("https://catchwords.app///")).toBe("https://catchwords.app");
  });

  it("前後の空白を落とす（.env の書き間違いを吸収する）", () => {
    expect(normalizeSiteUrl("  https://catchwords.app  ")).toBe("https://catchwords.app");
  });

  it("空・null は未設定として扱う", () => {
    expect(normalizeSiteUrl("")).toBeNull();
    expect(normalizeSiteUrl("   ")).toBeNull();
    expect(normalizeSiteUrl(null)).toBeNull();
    expect(normalizeSiteUrl(undefined)).toBeNull();
  });
});

describe("siteUrl", () => {
  it("**未設定なら今の本番の住所**（今日の出力を1文字も変えない）", () => {
    expect(siteUrl({})).toBe(FALLBACK_SITE_URL);
    expect(siteUrl({ VITE_SITE_URL: "" })).toBe(FALLBACK_SITE_URL);
  });

  it("設定されていればそちらを使う", () => {
    expect(siteUrl(own)).toBe("https://catchwords.app");
  });

  it("設定を読めている（configuredSiteUrl が分岐の元）", () => {
    expect(configuredSiteUrl(own)).toBe("https://catchwords.app");
    expect(configuredSiteUrl({})).toBeNull();
  });
});

describe("siteUrlFor", () => {
  it("**スラッシュを重ねない**（`…app//auth` を作らない）", () => {
    expect(siteUrlFor("/auth", own)).toBe("https://catchwords.app/auth");
    expect(siteUrlFor("auth", own)).toBe("https://catchwords.app/auth");
    expect(siteUrlFor("///auth", own)).toBe("https://catchwords.app/auth");
  });

  it("根はスラッシュを足さない", () => {
    expect(siteUrlFor("", own)).toBe("https://catchwords.app");
    expect(siteUrlFor("/", own)).toBe("https://catchwords.app");
  });

  it("入れ子の道も組める", () => {
    expect(siteUrlFor("/post/abc", own)).toBe("https://catchwords.app/post/abc");
  });

  it("未設定なら今の住所で組む", () => {
    expect(siteUrlFor("/privacy", {})).toBe(`${FALLBACK_SITE_URL}/privacy`);
  });
});
