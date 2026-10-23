import { describe, it, expect } from "vitest";
import {
  CATEGORY_KEYS,
  CATEGORY_META,
  ROOM_KEYS,
  ROOM_CATEGORIES,
  asCategoryKey,
  categoryEmoji,
  normalizeCategory,
  normalizeRoomWeights,
  roomMixFromCategories,
  wordCategoryKey,
} from "./category";

/**
 * カテゴリーの定義。
 *
 * 図鑑の棚はこの表がそのまま形になる。ここが崩れると、単語が
 * **どこの棚にも入らない**か、**同じ棚が2つできる**。どちらも
 * 「毎回同じ場所に居る」という図鑑の前提を壊す。
 */

describe("CATEGORY_META / ROOM_CATEGORIES", () => {
  it("すべてのカテゴリーがどれかの部屋にちょうど1回だけ入る", () => {
    const all = Object.keys(CATEGORY_META);
    const placed = ROOM_KEYS.flatMap((r) => ROOM_CATEGORIES[r]);
    expect(placed.length).toBe(all.length);
    expect(new Set(placed).size).toBe(all.length);
    expect([...placed].sort()).toEqual([...all].sort());
  });

  it("空の部屋を作らない(棚の無い部屋の見出しだけが並ぶのを防ぐ)", () => {
    for (const room of ROOM_KEYS) {
      expect(ROOM_CATEGORIES[room].length).toBeGreaterThan(0);
    }
  });

  it("どのカテゴリーにも絵文字がある", () => {
    for (const [key, meta] of Object.entries(CATEGORY_META)) {
      expect(meta.emoji, `${key} に絵文字が無い`).toBeTruthy();
    }
  });
});

describe("asCategoryKey", () => {
  it("既知のキーはそのまま通す", () => {
    expect(asCategoryKey("fruit")).toBe("fruit");
  });

  it("空・null・未知のキーは other に落とす", () => {
    // DBには古いキー(place / object)が残っている可能性がある。
    expect(asCategoryKey(null)).toBe("other");
    expect(asCategoryKey(undefined)).toBe("other");
    expect(asCategoryKey("")).toBe("other");
    expect(asCategoryKey("   ")).toBe("other");
    expect(asCategoryKey("place")).toBe("other");
  });

  it("前後の空白を落として判定する", () => {
    expect(asCategoryKey("  fruit  ")).toBe("fruit");
  });

  it("Object.prototype の名前を「既知のカテゴリー」として通さない", () => {
    // `key in CATEGORY_META` は継承したプロパティにも当たるので、
    // "constructor" などが素通りして CATEGORY_META[key] が関数を返し、
    // .emoji を引いたところで画面が落ちる。
    for (const evil of ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]) {
      expect(asCategoryKey(evil), `${evil} が素通りした`).toBe("other");
      expect(() => categoryEmoji(evil)).not.toThrow();
      expect(typeof categoryEmoji(evil)).toBe("string");
    }
  });

  it("見出し語が Object.prototype の名前でも、関数を返さない", () => {
    // `EXACT[h]` も同じ穴を持っていた。`asCategoryKey` では潰したのに、
    // **すぐ隣のこの引きだけ見落としていた**(1箇所直したら同じ形を探す)。
    // 文字キャッチは見出し語を人が打てるので、机上の話ではない。
    for (const evil of ["constructor", "__proto__", "toString", "hasOwnProperty", "valueOf"]) {
      const got = normalizeCategory(evil, null);
      expect(typeof got, `${evil} で ${typeof got} が返った`).toBe("string");
      expect(CATEGORY_KEYS as readonly string[]).toContain(got);
    }
  });

  it("見出し語が既知でなければ、AI の答えを尊重する", () => {
    expect(normalizeCategory("沒有この語", "drink")).toBe("drink");
    expect(normalizeCategory("沒有この語", "存在しない鍵")).toBe("other");
  });

  /**
   * オーナー報告 2026-10-08: 図鑑で**燒仙草が「植物・花」**に入っていた（「〜草」の語末規則）。
   * 名前に草・花・葉・鍋・燈が入っていても、食べ物・飲み物・街の物はそちらへ。
   */
  it("名前に草・花・葉・鍋・燈があっても、食べ物・飲み物・街の物はその棚へ", () => {
    const cases: Array<[string, string]> = [
      ["燒仙草", "dessert"],
      ["仙草", "dessert"],
      ["仙草凍", "dessert"],
      ["愛玉", "dessert"],
      ["豆花", "dessert"],
      ["爆米花", "dessert"],
      ["棉花糖", "dessert"],
      ["仙草茶", "drink"],
      ["青草茶", "drink"],
      ["茶葉", "drink"],
      ["火鍋", "food"],
      ["麻辣鍋", "food"],
      ["韭菜花", "vegetable"],
      ["紅綠燈", "street"],
      ["路燈", "street"],
    ];
    for (const [h, want] of cases) expect(normalizeCategory(h, "plant"), h).toBe(want);
    // 本物の植物・花・道具は今まで通り。
    expect(normalizeCategory("小草", null)).toBe("plant");
    expect(normalizeCategory("玫瑰花", null)).toBe("flower");
    expect(normalizeCategory("平底鍋", null)).toBe("kitchenware");
    expect(normalizeCategory("檯燈", null)).toBe("furniture");
  });

  it("読む時も見出し語で直す（保存済みの古い取り違えを正す）", () => {
    expect(wordCategoryKey({ headword: "燒仙草", category_key: "plant" })).toBe("dessert");
    expect(wordCategoryKey({ headword: "某個字", category_key: "drink" })).toBe("drink");
    expect(wordCategoryKey({ headword: "", category_key: "place" })).toBe("other");
    expect(wordCategoryKey({ category_key: null })).toBe("other");
  });

  // 2026-10-09 オーナー報告: 蘑菇・小豬が「その他」になり、図鑑で日用品に並んでいた。
  it("キノコは植物（表の香菇と同じ）、子どもの動物は動物。面膜は日用品のまま", () => {
    expect(normalizeCategory("蘑菇", "other")).toBe("plant");
    expect(normalizeCategory("金針菇", "other")).toBe("plant");
    expect(normalizeCategory("小豬", "other")).toBe("animal");
    expect(normalizeCategory("豬仔", "other")).toBe("animal");
    expect(normalizeCategory("小雞", "other")).toBe("animal");
    expect(normalizeCategory("面膜", "medicine")).toBe("medicine");
    // 「〜豬」を広く取らない（豬排は料理）。
    expect(normalizeCategory("豬排", "food")).toBe("food");
    expect(normalizeCategory("斑馬線", "street")).toBe("street");
  });

  // 2026-10-09 オーナー報告（図鑑の「その他」）:「可頌は食べ物だし、面膜は生活用品だよね。」
  it("「その他」に残っていた語は、AI の答えが other でも見出し語で棚に入る", () => {
    expect(normalizeCategory("可頌", "other")).toBe("dessert");
    expect(normalizeCategory("貝果", "other")).toBe("dessert");
    expect(normalizeCategory("吐司", "other")).toBe("dessert");
    expect(normalizeCategory("麵包", "other")).toBe("dessert");
    expect(normalizeCategory("面膜", "other")).toBe("medicine");
    expect(normalizeCategory("刷子", "other")).toBe("tool");
    expect(normalizeCategory("馬桶刷", "other")).toBe("tool");
    expect(normalizeCategory("開關", "other")).toBe("home");
    expect(normalizeCategory("電燈開關", "other")).toBe("home");
    expect(normalizeCategory("手背", "other")).toBe("body");
    expect(normalizeCategory("健康餐", "other")).toBe("food");
    expect(normalizeCategory("便當", null)).toBe("food");
    // 本当に分けられない語は「その他」のまま（無理に棚へ入れない）
    expect(normalizeCategory("亮點", "other")).toBe("other");
  });

  it("新しい規則が隣の語を取り違えない", () => {
    expect(normalizeCategory("牙刷", "other")).toBe("medicine");
    expect(normalizeCategory("烤麵包機", "appliance")).toBe("appliance");
    expect(normalizeCategory("餐具", "kitchenware")).toBe("kitchenware");
    expect(normalizeCategory("早餐店", "shop")).toBe("shop");
    expect(normalizeCategory("便當盒", "kitchenware")).toBe("kitchenware");
    expect(normalizeCategory("手套", "clothes")).toBe("clothes");
  });
});

/**
 * 出会う確率のための「場面」。
 * 語がどこで出るかと、その人がどこに居るかを**同じ鍵**で並べないと
 * 内積が意味を持たない。ここで守るのはその一点。
 */
describe("normalizeRoomWeights", () => {
  it("合計1に直す", () => {
    const w = normalizeRoomWeights({ eat: 2, town: 2 });
    expect(w).toEqual({ eat: 0.5, town: 0.5 });
  });

  it("**知らない鍵は落とす**(片方にしか無い鍵は必ず0を掛けることになる)", () => {
    const w = normalizeRoomWeights({ eat: 1, スーパー: 1, 新聞: 5 });
    expect(w).toEqual({ eat: 1 });
  });

  it("0 や負や壊れた数は数えない", () => {
    const w = normalizeRoomWeights({ eat: 1, town: 0, house: -3, play: Number.NaN });
    expect(w).toEqual({ eat: 1 });
  });

  it("使える鍵が1つも無ければ null(補正を掛けない)", () => {
    expect(normalizeRoomWeights({ スーパー: 1 })).toBeNull();
    expect(normalizeRoomWeights({})).toBeNull();
    expect(normalizeRoomWeights(null)).toBeNull();
  });
});

describe("roomMixFromCategories", () => {
  it("撮ったものの部屋の割合になる", () => {
    const mix = roomMixFromCategories(["fruit", "vegetable", "street"]);
    expect(mix?.eat).toBeCloseTo(2 / 3, 6);
    expect(mix?.town).toBeCloseTo(1 / 3, 6);
  });

  it("知らないカテゴリーは other 扱いで数える(捨てない)", () => {
    const mix = roomMixFromCategories(["まだ無いカテゴリー"]);
    expect(mix).not.toBeNull();
    expect(Object.values(mix!).reduce((a, b) => a + b, 0)).toBeCloseTo(1, 6);
  });

  it("**1枚も撮っていなければ null**。一様と言い切らない", () => {
    expect(roomMixFromCategories([])).toBeNull();
  });
});

describe("写真の候補の指示文の分類の一覧（2026-10-09）", () => {
  it("一覧を「fruit|のどれか: vegetable|…」と崩さない（崩れると AI が一覧の外を返し other に落ちる）", async () => {
    const fs = await import("node:fs");
    const path = await import("node:path");
    const src = fs.readFileSync(path.join(__dirname, "ai.functions.ts"), "utf8");
    expect(src).not.toContain('CATEGORY_KEYS.join("|のどれか: ")');
    expect(src).toContain('"category_key":"${CATEGORY_KEYS.join("|")} のどれか"');
  });
});
