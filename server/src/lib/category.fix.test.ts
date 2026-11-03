import { describe, expect, it } from "vitest";
import { normalizeCategory } from "./category";
import { dexCategoryForKey } from "./dex-catalog";

// 点検 M38・T46（2026-11-03）: 規則が AI の正しい分類を上書きしていた語。
const CASES: Array<[string, string, string, number]> = [
  // [見出し, AI の分類, 期待の鍵, 図鑑の番号]
  ["咖啡店", "shop", "shop", 14],
  ["奶茶店", "shop", "shop", 14],
  ["麵包店", "shop", "shop", 14],
  ["手機店", "shop", "shop", 14],
  ["火車站", "building", "building", 14],
  ["信用卡", "document", "money", 10],
  ["銀行卡", "document", "money", 10],
  ["悠遊卡", "money", "money", 10],
  ["汽車鑰匙", "transport", "tool", 10],
  ["刮鬍刀", "medicine", "medicine", 10],
  ["咖啡機", "appliance", "appliance", 7],
  ["麻花", "dessert", "dessert", 4],
  ["地瓜", "fruit", "vegetable", 3],
  ["天燈", "street", "street", 15],
];
describe("分類の規則", () => {
  for (const [h, ai, key, no] of CASES) {
    it(`${h} → ${key}（No.${no}）`, () => {
      expect(normalizeCategory(h, ai)).toBe(key);
      expect(dexCategoryForKey(key)).toBe(no);
    });
  }
  it("今までどおりの語", () => {
    expect(normalizeCategory("咖啡", "other")).toBe("drink");
    expect(normalizeCategory("書店", "other")).toBe("shop");
    expect(normalizeCategory("湯匙", "other")).toBe("kitchenware");
    expect(normalizeCategory("店員", "other")).toBe("job");
  });
});
