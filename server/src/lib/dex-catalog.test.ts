import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  DEX_CATEGORIES,
  DEX_ITEMS,
  DEX_KEY_TO_CATEGORY,
  dexCategoryForKey,
  dexCategoryKey,
  dexCatalogCategory,
  dexCategoryOf,
  dexHeadword,
  dexItemFor,
  normDexHeadword,
} from "./dex-catalog";
import { CATEGORY_KEYS } from "./category";
import ios from "./__fixtures__/ios-dex-catalog.json";

/**
 * **iOS 版と同じ図鑑**（オーナー指示 2026-10-08「iOS版のように図鑑自体にものの影を表示して、
 * それぞれの単語に番号振って」）。`__fixtures__/ios-dex-catalog.json` は iOS リポジトリ
 * （nori-creator/rork-catchwords-728）の `ios/CatchWords/Models/DexCatalog.swift` の表を
 * そのまま書き出した物。番号・id・見出し語が1つでもずれると、同じ人の iPhone と Web で
 * 「No.012」が別の物になる。
 */
type IosItem = {
  id: string;
  zh: string;
  en: string;
  ja: string;
  symbol: string | null;
  baseNo?: number | null;
};
type IosCategory = { no: number; emoji: string; base: IosItem[]; extra: IosItem[] };
const IOS = ios as IosCategory[];

describe("図鑑の表は iOS と同じ", () => {
  it("20 のカテゴリーが同じ順・同じ絵文字", () => {
    expect(DEX_CATEGORIES.map((c) => [c.no, c.emoji])).toEqual(IOS.map((c) => [c.no, c.emoji]));
  });

  it("基本の100は表の順に No.001〜100（id も同じ）", () => {
    const web = DEX_CATEGORIES.flatMap((c) => c.base.map((it) => [it.id, it.baseNo]));
    const want = IOS.flatMap((c) => c.base.map((it) => [it.id, it.baseNo]));
    expect(web).toEqual(want);
    expect(web).toHaveLength(100);
    expect(web[0]).toEqual(["bubbletea", 1]);
    expect(web[99][1]).toBe(100);
  });

  it("毎日の物は番号なし・同じ順・同じ id", () => {
    for (const [i, c] of DEX_CATEGORIES.entries()) {
      expect(c.extra.map((it) => it.id)).toEqual(IOS[i].extra.map((it) => it.id));
      expect(c.extra.every((it) => it.baseNo === null)).toBe(true);
    }
  });

  it("見出し語（zh / en / ja）と SF Symbol の名前も同じ", () => {
    const strip = (it: IosItem) => ({
      id: it.id,
      zh: it.zh,
      en: it.en,
      ja: it.ja,
      symbol: it.symbol,
    });
    expect(DEX_ITEMS.map(strip)).toEqual(IOS.flatMap((c) => [...c.base, ...c.extra]).map(strip));
  });

  it("id は全部で1つずつ", () => {
    expect(new Set(DEX_ITEMS.map((it) => it.id)).size).toBe(DEX_ITEMS.length);
  });

  /**
   * iOS のリポジトリが隣に在る時（開発機）は、写しではなく**本物の Swift の表**と比べる。
   * CI には無いので、その時は飛ばす。
   */
  const swift = [
    process.env.CATCHWORDS_IOS_DIR,
    path.resolve(process.cwd(), "../rork-catchwords-728"),
  ]
    .filter((d): d is string => !!d)
    .map((d) => path.join(d, "ios/CatchWords/Models/DexCatalog.swift"))
    .find((p) => fs.existsSync(p));
  it.skipIf(!swift)("iOS の Swift の表と、そのまま同じ", () => {
    const src = fs.readFileSync(swift!, "utf8");
    const rows = [
      ...src.matchAll(/r\("([^"]*)", "([^"]*)", "([^"]*)", "([^"]*)"(?:, "([^"]*)")?\)/g),
    ].map((m) => ({ id: m[1], zh: m[2], en: m[3], ja: m[4], symbol: m[5] ?? null }));
    expect(DEX_ITEMS.map(({ id, zh, en, ja, symbol }) => ({ id, zh, en, ja, symbol }))).toEqual(
      rows,
    );
  });
});

describe("分類の鍵 → 図鑑のカテゴリー", () => {
  it("アプリの鍵は other を除いて全部どこかのカテゴリーへ行く", () => {
    const named = CATEGORY_KEYS.filter((k) => k !== "other");
    for (const k of named) expect(DEX_KEY_TO_CATEGORY[k]).toBeGreaterThan(0);
    expect(Object.keys(DEX_KEY_TO_CATEGORY).sort()).toEqual([...named].sort());
  });

  // 2026-10-09 オーナー報告: 札は「その他」の蘑菇・小豬が、図鑑では「洗面・日用品」に並んでいた。
  it("other・知らない鍵・鍵なしは null（「その他」の節。日用品に黙って寄せない）", () => {
    expect(dexCategoryForKey("other")).toBeNull();
    expect(dexCategoryForKey("place")).toBeNull();
    expect(dexCategoryForKey("constructor")).toBeNull();
    expect(dexCategoryForKey(null)).toBeNull();
    expect(dexCategoryForKey("animal")).toBe(16);
    expect(dexCategoryForKey("medicine")).toBe(10);
  });

  it("代表の鍵は、そのカテゴリーへ戻る", () => {
    for (let no = 1; no <= 20; no++) expect(dexCategoryForKey(dexCategoryKey(no))).toBe(no);
  });
});

describe("見出し語で影を引く", () => {
  it("学習言語の見出し語が同じなら、その影", () => {
    expect(dexItemFor("貓", "zh-TW")?.id).toBe("cat");
    expect(dexItemFor("咖啡", "zh-TW")?.baseNo).toBe(2);
    expect(dexItemFor("coffee", "en")?.id).toBe("coffee");
    expect(dexItemFor("コーヒー", "ja")?.id).toBe("coffee");
  });

  it("前後の空白・大文字・冠詞・カタカナ/ひらがなを揃えて比べる（iOS `norm`）", () => {
    expect(dexItemFor("  The Cat ", "en")?.id).toBe("cat");
    expect(dexItemFor("an apple", "en")?.id).toBe("apple");
    expect(dexItemFor("リンゴ", "ja")?.id).toBe("apple");
    expect(normDexHeadword("リンゴ", "ja")).toBe("りんご");
  });

  it("別の言語の見出し語では引かない", () => {
    expect(dexItemFor("coffee", "zh-TW")).toBeNull();
    expect(dexItemFor("", "zh-TW")).toBeNull();
    expect(dexItemFor("不在表裡的字", "zh-TW")).toBeNull();
  });

  it("表に在る語は表のカテゴリー、無い語は分類の鍵から", () => {
    expect(dexCategoryOf("貓", "other", "zh-TW")).toBe(16);
    expect(dexCategoryOf("夜市", "shop", "zh-TW")).toBe(14);
    expect(dexCategoryOf("某個字", null, "zh-TW")).toBeNull();
    expect(dexCategoryOf("某個字", "other", "zh-TW")).toBeNull();
  });

  it("表の物の言い方の揺れ（簡体字・小〜・〜仔）もカテゴリーは表から。番号は渡さない", () => {
    expect(dexCatalogCategory("小貓", "zh-TW")).toBe(16);
    expect(dexCatalogCategory("猫", "zh-TW")).toBe(16);
    expect(dexCatalogCategory("狗仔", "zh-TW")).toBe(16);
    expect(dexItemFor("小貓", "zh-TW")).toBeNull();
    expect(dexCatalogCategory("面膜", "zh-TW")).toBeNull();
    expect(dexCatalogCategory("小貓", "en")).toBeNull();
  });

  it("見出し語は学習言語で出す", () => {
    const cat = dexItemFor("貓", "zh-TW")!;
    expect(dexHeadword(cat, "en")).toBe("cat");
    expect(dexHeadword(cat, "ja")).toBe("猫");
    expect(dexHeadword(cat, undefined)).toBe("貓");
  });
});
