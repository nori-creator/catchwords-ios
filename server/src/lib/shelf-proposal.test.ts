import { describe, it, expect } from "vitest";
import { normalizeShelfProposal, isBuiltinRoom } from "./shelf-proposal";
import { CATEGORY_KEYS } from "./category";

const ok = {
  key: "night_market_snack",
  label: "夜市のおやつ",
  emoji: "🍡",
  room_key: "eat",
  room_label: "食べる",
};

describe("normalizeShelfProposal", () => {
  it("素直な提案はそのまま通る", () => {
    expect(normalizeShelfProposal(ok)).toEqual(ok);
  });

  it("鍵は形に寄せる(空白・大文字・記号)", () => {
    expect(normalizeShelfProposal({ ...ok, key: "  Night Market-Snack " })?.key).toBe(
      "night_market_snack",
    );
    expect(normalizeShelfProposal({ ...ok, key: "temple/offering" })?.key).toBe("temple_offering");
  });

  it("**日本語の鍵は諦める**(直しようがない)", () => {
    expect(normalizeShelfProposal({ ...ok, key: "夜市のおやつ" })).toBeNull();
  });

  it("**何が来ても、出てくる鍵は安全な形か null**", () => {
    // 保証したいのは「危ない名前を弾く」ではなく
    // **「通ったものは必ず安全な形」**。弾き漏らしを1つずつ列挙すると
    // 列挙から漏れたものが通る(`__proto__` は前後の _ が落ちて `proto` に
    // なるので、名指しの禁止では捕まらない)。性質のほうを固定する。
    const nasty = [
      "__proto__",
      "constructor",
      "toString",
      "hasOwnProperty",
      "夜市",
      "",
      "   ",
      "___",
      "1abc",
      "a".repeat(200),
      "drop table x;--",
      "../../etc/passwd",
    ];
    for (const key of nasty) {
      const got = normalizeShelfProposal({ ...ok, key });
      if (got === null) continue;
      expect(got.key, `${key} が形を外れた`).toMatch(/^[a-z][a-z0-9_]{1,38}$/);
      // 既定の54棚とぶつからないこと(ぶつかると同じ棚が2つ並ぶ)。
      expect(CATEGORY_KEYS as readonly string[]).not.toContain(got.key);
    }
  });

  it("**既定の54棚と同じ鍵は作らせない**(同じ棚が2つ並ぶ)", () => {
    expect(normalizeShelfProposal({ ...ok, key: "fruit" })).toBeNull();
    expect(normalizeShelfProposal({ ...ok, key: "other" })).toBeNull();
  });

  it("長すぎる名前は**切り詰めずに諦める**", () => {
    // 24字で切ると「夜市で売っている甘い揚げ物のお…」が棚の名前になり、
    // 直す手段がユーザーに無い。
    const long = "夜".repeat(25);
    expect(normalizeShelfProposal({ ...ok, label: long })).toBeNull();
    expect(normalizeShelfProposal({ ...ok, room_label: long })).toBeNull();
  });

  it("名前の改行は1行に潰す", () => {
    expect(normalizeShelfProposal({ ...ok, label: "夜市の\n おやつ" })?.label).toBe(
      "夜市の おやつ",
    );
  });

  it("絵文字でないものは既定に落とす(棚は成立する)", () => {
    expect(normalizeShelfProposal({ ...ok, emoji: "なし" })?.emoji).toBe("📦");
    expect(normalizeShelfProposal({ ...ok, emoji: "N/A" })?.emoji).toBe("📦");
    expect(normalizeShelfProposal({ ...ok, emoji: "" })?.emoji).toBe("📦");
    expect(normalizeShelfProposal({ ...ok, emoji: 42 })?.emoji).toBe("📦");
  });

  it("欠けている項目があれば諦める", () => {
    expect(normalizeShelfProposal({ ...ok, label: undefined })).toBeNull();
    expect(normalizeShelfProposal({ ...ok, room_key: null })).toBeNull();
    expect(normalizeShelfProposal(null)).toBeNull();
    expect(normalizeShelfProposal(undefined)).toBeNull();
  });

  it("鍵は 39 文字までに収まる", () => {
    const got = normalizeShelfProposal({ ...ok, key: "a".repeat(80) });
    expect(got).not.toBeNull();
    expect(got!.key.length).toBeLessThanOrEqual(39);
  });
});

describe("isBuiltinRoom", () => {
  it("既定の部屋を見分ける", () => {
    expect(isBuiltinRoom("eat")).toBe(true);
    expect(isBuiltinRoom("faith")).toBe(false);
  });
});
