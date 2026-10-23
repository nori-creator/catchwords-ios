import { describe, expect, it } from "vitest";
import {
  categoryDisplay,
  cleanCategoryEmoji,
  cleanCategoryLabel,
  newCategoryKey,
  stickerCategoryKey,
} from "./user-category";

const mine = [
  { key: "u_trip0001", label: "旅のお土産", emoji: "🎁", room_key: "mine", room_label: "マイ" },
  { key: "drink", label: "のみもの", emoji: "🧋", room_key: "eat", room_label: "のみもの" },
];
const label = (k: string) => `label:${k}`;

describe("1枚のカテゴリー（写真ごとの移動）", () => {
  it("移していなければ語の既定の分類", () => {
    expect(stickerCategoryKey({ word: { category_key: "fruit" } })).toBe("fruit");
    expect(stickerCategoryKey({ shelf_key: null, word: { category_key: "place" } })).toBe("other");
  });
  it("既定の分類へ移したら、それが効く", () => {
    expect(stickerCategoryKey({ shelf_key: "food", word: { category_key: "fruit" } })).toBe("food");
  });
  it("自分のカテゴリーへ移したら、それが効く。消したカテゴリーなら既定へ戻る", () => {
    const keys = new Set(mine.map((m) => m.key));
    const s = { shelf_key: "u_trip0001", word: { category_key: "fruit" } };
    expect(stickerCategoryKey(s, keys)).toBe("u_trip0001");
    expect(stickerCategoryKey(s, new Set())).toBe("fruit");
  });
});

describe("名前と絵文字（付け直し）", () => {
  it("既定の分類は、付け直した名前を先に見る", () => {
    expect(categoryDisplay("drink", mine, label)).toEqual({
      label: "のみもの",
      emoji: "🧋",
      custom: false,
      renamed: true,
    });
    expect(categoryDisplay("fruit", mine, label)).toMatchObject({
      label: "label:fruit",
      renamed: false,
    });
  });
  it("自分で作ったカテゴリーは、その名前", () => {
    expect(categoryDisplay("u_trip0001", mine, label)).toMatchObject({
      label: "旅のお土産",
      emoji: "🎁",
      custom: true,
    });
  });
  it("知らない鍵は「その他」として見せる（空の見出しにしない）", () => {
    expect(categoryDisplay("u_gone", mine, label).label).toBe("label:other");
  });
});

describe("入力の形", () => {
  it("名前は前後の空白を落として 1〜24 字", () => {
    expect(cleanCategoryLabel("  旅の  お土産 ")).toBe("旅の お土産");
    expect(cleanCategoryLabel("   ")).toBeNull();
    expect(cleanCategoryLabel("あ".repeat(25))).toBeNull();
  });
  it("絵文字は空なら箱、長すぎれば切る", () => {
    expect(cleanCategoryEmoji("")).toBe("📦");
    expect(cleanCategoryEmoji("🎁")).toBe("🎁");
    expect([...cleanCategoryEmoji("🎁🎈🎉")].length).toBe(2);
  });
  it("新しい鍵は DB の形に合い、既に在る鍵と重ならない", () => {
    let n = 0;
    const seq = () => [0, 0, 0.5][n++];
    const key = newCategoryKey(["u_00000000"], seq);
    expect(key).toMatch(/^[a-z][a-z0-9_]{1,38}$/);
    expect(key).not.toBe("u_00000000");
  });
});
