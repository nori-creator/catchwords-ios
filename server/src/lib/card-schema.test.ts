import { describe, it, expect } from "vitest";
import { CardSchema } from "./card-schema";

/**
 * オーナー指摘(2度):「単語の文字入力がエラーが出て、機能してない」。
 * 画面には "AI did not return a structured card" の1行しか出ず、
 * **1項目の型違いでカードが丸ごと落ちていた**のが原因だった。
 *
 * ここは「落ちてはいけない物が落ちないこと」と、
 * 「落ちるべき物は落ちること」の両方を押さえる門。
 */

/** 生成物として最低限まともな1枚。 */
const OK = {
  headword_zh: "遙控器",
  reading_zhuyin: "ㄧㄠˊ ㄎㄨㄥˋ ㄑㄧˋ",
  pinyin: "yáo kòng qì",
  meaning_ja: "リモコン",
  part_of_speech: "名詞",
  level: "TOCFL-2",
  category_key: "appliance",
  example_sentence: "遙控器在沙發上。",
  example_translation: "リモコンはソファの上にあります。",
};

describe("CardSchema — 1項目でカードを落とさない", () => {
  it("素直な1枚はそのまま通る", () => {
    const r = CardSchema.safeParse(OK);
    expect(r.success).toBe(true);
    expect(r.success && r.data.category_key).toBe("appliance");
  });

  // **これが「文字入力が機能してない」の正体。**
  // 54個の外の棚名が返るたびに parse が投げ、カードが消えていた。
  it.each(["electronics", "remote_control", "ELECTRONICS", "", "家具家電"])(
    "知らない棚 %p でもカードは生き残り、other に落ちる",
    (bad) => {
      const r = CardSchema.safeParse({ ...OK, category_key: bad });
      expect(r.success).toBe(true);
      expect(r.success && r.data.category_key).toBe("other");
    },
  );

  // 2026-10-15: 写真の候補の控えで、写真ごとに全部 "other" になっていた（花束の写真の 波斯菊・花瓶・木桌・木櫃）。
  // 指示文が見せる「→ category_key: home / furniture / decoration」の並び・番号・カテゴリーの名前を鍵1つに読む。
  it.each([
    ["home / furniture / decoration", "home"],
    ["plant|flower", "plant"],
    ["Flowers", "flower"],
    ["17", "plant"],
    ["家電", "appliance"],
    ["植物・花", "plant"],
    [" Dessert ", "dessert"],
  ])("分類の答え %p は鍵 %p に読む", (raw, key) => {
    const r = CardSchema.safeParse({ ...OK, category_key: raw });
    expect(r.success && r.data.category_key).toBe(key);
  });

  it("棚が丸ごと欠けていても落ちない", () => {
    const { category_key: _drop, ...rest } = OK;
    const r = CardSchema.safeParse(rest);
    expect(r.success).toBe(true);
    expect(r.success && r.data.category_key).toBe("other");
  });

  it("例文が欠けていても落ちない(無くてもカードは使える)", () => {
    const { example_sentence: _a, example_translation: _b, ...rest } = OK;
    const r = CardSchema.safeParse(rest);
    expect(r.success).toBe(true);
    expect(r.success && r.data.example_sentence).toBe("");
  });

  it("例文が文字列でなくても落ちない", () => {
    const r = CardSchema.safeParse({ ...OK, example_sentence: 42 });
    expect(r.success).toBe(true);
    expect(r.success && r.data.example_sentence).toBe("");
  });

  it("読み・品詞・レベルが欠けても既定で埋まる", () => {
    const r = CardSchema.safeParse({ meaning_ja: "リモコン" });
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.part_of_speech).toBe("名詞");
      expect(r.data.level).toBe("TOCFL-2");
      expect(r.data.reading_zhuyin).toBe("");
    }
  });

  it("extras が壊れていても、その項目だけが落ちる", () => {
    const r = CardSchema.safeParse({
      ...OK,
      extras: { register_scale: "とても書面", season_months: "夏", region_scope: 5 },
    });
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.data.extras?.register_scale).toBeNull();
      expect(r.data.extras?.season_months).toEqual([]);
      expect(r.data.extras?.region_scope).toBe("");
    }
  });
});

describe("CardSchema — 落ちるべき物は落ちる", () => {
  /**
   * **意味の無いカードはカードではない。**
   * ここまで寛容にすると「全部空のカード」が図鑑に入り、
   * 「検証済みとAI生成を区別する」より悪い「中身が無い」が起きる。
   */
  it("意味が無ければ通さない", () => {
    const { meaning_ja: _drop, ...rest } = OK;
    const r = CardSchema.safeParse(rest);
    expect(r.success).toBe(false);
  });

  it("意味が文字列でなければ通さない", () => {
    expect(CardSchema.safeParse({ ...OK, meaning_ja: null }).success).toBe(false);
    expect(CardSchema.safeParse({ ...OK, meaning_ja: 3 }).success).toBe(false);
  });

  it("そもそもオブジェクトでなければ通さない", () => {
    for (const bad of [null, undefined, "遙控器", 3, []]) {
      expect(CardSchema.safeParse(bad).success).toBe(false);
    }
  });

  /** 失敗したときは**どの項目か**が分かること。飲み込まない土台。 */
  it("失敗の理由に項目の名前が入っている", () => {
    const { meaning_ja: _drop, ...rest } = OK;
    const r = CardSchema.safeParse(rest);
    expect(r.success).toBe(false);
    if (!r.success) {
      expect(r.error.issues.map((i) => i.path.join("."))).toContain("meaning_ja");
    }
  });
});
