import { describe, expect, it } from "vitest";
import {
  DEX_CATEGORY_GUIDES,
  DEX_CATEGORY_GUIDE_JA,
  dexCategoryExamples,
  dexCategoryKeys,
} from "./dex-category-guide";
import { DEX_CATEGORIES, DEX_KEY_TO_CATEGORY, dexCategoryForKey } from "./dex-catalog";
import { CATEGORY_CHOICE_RULES_JA, CATEGORY_KEYS, normalizeCategory } from "./category";
import { dexPlaceOf, type DexGroupable } from "./dex-book";
import { misplacedByStoredKey, reclassifyPrompt } from "./category-backfill";
import { DICT } from "./i18n";

/**
 * 2026-10-09 オーナー報告「桃がなぜか景色に分類されてる。分類のアルゴリズム改善して。
 * ios版の２０種類を徹底して。」— 桃は表（iOS の DexCatalog）に無く、見出し語の規則にも
 * 当たらず、AI の答え "nature" のまま図鑑の「空・自然」（18）に置かれていた。
 */

const place = (headword: string, cat: string | null, shelf: string | null = null) => {
  const s: DexGroupable = {
    id: headword,
    taken_at: "2026-10-09T00:00:00Z",
    shelf_key: shelf,
    word: { headword, language: "zh-TW", category_key: cat },
  };
  return dexPlaceOf(s, "zh-TW", new Set());
};

describe("図鑑の20のカテゴリーの一覧（AI への物差し）", () => {
  it("iOS の表と同じ20のカテゴリーを、同じ順で、i18n と同じ日本語の名前で持つ", () => {
    expect(DEX_CATEGORY_GUIDES.map((g) => g.no)).toEqual(DEX_CATEGORIES.map((c) => c.no));
    const dict = DICT as unknown as Record<string, { ja: string }>;
    for (const g of DEX_CATEGORY_GUIDES) expect(g.ja).toBe(dict[`dexcat.${g.no}`].ja);
  });

  it("どのカテゴリーにも答える鍵が1つ以上あり、鍵は1つのカテゴリーにだけ載る", () => {
    const seen: string[] = [];
    for (const g of DEX_CATEGORY_GUIDES) {
      const keys = dexCategoryKeys(g.no);
      expect(keys.length).toBeGreaterThan(0);
      seen.push(...keys);
    }
    expect([...seen].sort()).toEqual(CATEGORY_KEYS.filter((k) => k !== "other").sort());
  });

  it("例は表の物から（果物・野菜には桃も載る）", () => {
    expect(dexCategoryExamples(3)).toEqual(expect.arrayContaining(["蘋果", "香蕉", "芒果", "桃"]));
    expect(dexCategoryExamples(17)).toContain("桃花");
  });

  it("カード・写真の候補・分け直しの指示文が20の一覧を載せる", () => {
    expect(CATEGORY_CHOICE_RULES_JA).toContain(DEX_CATEGORY_GUIDE_JA);
    for (const g of DEX_CATEGORY_GUIDES)
      expect(DEX_CATEGORY_GUIDE_JA).toContain(`${g.no}. ${g.ja}`);
    expect(DEX_CATEGORY_GUIDE_JA).toMatch(/3\. 果物・野菜 .*category_key: fruit \/ vegetable/);
    expect(DEX_CATEGORY_GUIDE_JA).toMatch(
      /18\. 空・自然 .*category_key: nature \/ weather \/ sky \/ water \/ mountain/,
    );
    const p = reclassifyPrompt([{ i: 0, headword: "桃", meaning: "もも" }]);
    expect(p).toContain("図鑑の20のカテゴリー");
    expect(p).toContain(DEX_CATEGORY_GUIDE_JA);
  });
});

describe("分類の鍵 → 20のカテゴリー（全部の鍵）", () => {
  // 54 の鍵の行き先（other は20のどれにも入れず「その他」の節）。
  const EXPECTED: Record<string, number | null> = {
    drink: 1,
    food: 2,
    fruit: 3,
    vegetable: 3,
    dessert: 4,
    kitchenware: 5,
    home: 6,
    furniture: 6,
    decoration: 6,
    appliance: 7,
    tech: 8,
    gadget: 8,
    stationery: 9,
    book: 9,
    document: 9,
    color: 9,
    shape: 9,
    tool: 10,
    medicine: 10,
    money: 10,
    clothes: 11,
    clothing_part: 11,
    accessory: 12,
    shoes: 12,
    bag: 12,
    jewelry: 12,
    vehicle: 13,
    transport: 13,
    building: 14,
    shop: 14,
    street: 15,
    sign: 15,
    character: 15,
    symbol: 15,
    animal: 16,
    plant: 17,
    flower: 17,
    nature: 18,
    weather: 18,
    sky: 18,
    water: 18,
    mountain: 18,
    toy: 19,
    game: 19,
    sport: 19,
    instrument: 19,
    art: 19,
    body: 20,
    face: 20,
    hand: 20,
    person: 20,
    family: 20,
    job: 20,
    other: null,
  };

  it("表が54の鍵を全部覆う", () => {
    expect(Object.keys(EXPECTED).sort()).toEqual([...CATEGORY_KEYS].sort());
  });

  it.each(Object.entries(EXPECTED))("%s → %s", (key, no) => {
    expect(dexCategoryForKey(key)).toBe(no);
    if (no != null) {
      expect(no).toBeGreaterThanOrEqual(1);
      expect(no).toBeLessThanOrEqual(20);
    }
  });

  it("果物は「空・自然」でも「植物・花」でもない", () => {
    expect(DEX_KEY_TO_CATEGORY.fruit).toBe(3);
    expect(DEX_KEY_TO_CATEGORY.fruit).not.toBe(DEX_KEY_TO_CATEGORY.nature);
    expect(DEX_KEY_TO_CATEGORY.fruit).not.toBe(DEX_KEY_TO_CATEGORY.plant);
  });
});

describe("見出し語の規則（20のカテゴリーに合わせて）", () => {
  it.each([
    ["桃", "fruit"],
    ["桃子", "fruit"],
    ["水蜜桃", "fruit"],
    ["櫻桃", "fruit"],
    ["荔枝", "fruit"],
    ["龍眼", "fruit"],
    ["蓮霧", "fruit"],
    ["釋迦", "fruit"],
    ["柳丁", "fruit"],
    ["葡萄柚", "fruit"],
    ["白桃", "fruit"],
    ["山竹", "fruit"],
    ["西瓜汁", "drink"],
    ["芒果冰", "dessert"],
    ["芒果乾", "dessert"],
    ["桃花", "flower"],
    ["蘑菇", "plant"],
    ["小豬", "animal"],
    ["可頌", "dessert"],
    ["面膜", "medicine"],
    ["手背", "body"],
    ["淡水河", "water"],
    ["觀音山", "mountain"],
    ["蔥花", "vegetable"],
    ["秘書", "job"],
    ["銀河", "sky"],
  ])("%s → %s", (h, key) => {
    expect(normalizeCategory(h, "nature")).toBe(key);
  });

  it.each(["爬山", "登山"])("%s（山へ行く行い）は山の名にしない", (h) => {
    expect(normalizeCategory(h, "sport")).toBe("sport");
  });

  it.each(["拔河", "過河"])("%s（綱引き・川を渡る行い）は川の名にしない", (h) => {
    expect(normalizeCategory(h, "sport")).toBe("sport");
  });

  it("果物の字を含むだけの語には当たらない（AI の答えのまま）", () => {
    expect(normalizeCategory("桃園", "building")).toBe("building");
    expect(normalizeCategory("黑桃", "game")).toBe("game");
    expect(normalizeCategory("桃樹", "plant")).toBe("plant");
    expect(normalizeCategory("女王頭", "nature")).toBe("nature");
  });
});

describe("図鑑の置き場所（表 → 見出し語の規則 → 保存された鍵）", () => {
  it.each<[string, string | null, number | string]>([
    // 保存された鍵が nature（AI の答え）でも、果物の規則が先
    ["桃", "nature", 3],
    ["桃子", "plant", 3],
    ["水蜜桃", "nature", 3],
    ["桃花", "nature", 17],
    ["蘑菇", "other", 17],
    ["小豬", "other", 16],
    ["可頌", "other", 4],
    ["面膜", "other", 10],
    ["手背", "other", 20],
    ["淡水河", "other", 18],
    ["夕陽", "food", 18], // 表に在る（空・自然）
    ["觀音山", "other", 18],
    ["女王頭", "nature", 18], // 岩（野柳）。空・自然でよい
    ["桃園", "building", 14],
  ])("%s（保存: %s）→ %s", (h, cat, want) => {
    expect(place(h, cat)).toBe(want);
  });

  it("その人が選んだ棚は動かさない", () => {
    expect(place("桃", "nature", "nature")).toBe(18);
    expect(place("桃", "nature", "plant")).toBe(17);
  });

  it("保存された鍵と置き場所が食い違う語を数える（棚を選んだ札は数えない）", () => {
    const item = (id: string, headword: string, cat: string, shelf: string | null = null) => ({
      word_id: id,
      shelf_key: shelf,
      word: { headword, language: "zh-TW", category_key: cat },
    });
    expect(
      misplacedByStoredKey(
        [
          item("w1", "桃", "nature"),
          item("w2", "桃花", "flower"),
          item("w3", "桃", "nature", "nature"),
          item("w4", "觀音山", "other"),
        ],
        "zh-TW",
      ),
    ).toEqual([
      { word_id: "w1", stored: 18, placed: 3 },
      { word_id: "w4", stored: null, placed: 18 },
    ]);
  });
});
