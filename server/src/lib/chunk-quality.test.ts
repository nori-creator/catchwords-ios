import { describe, expect, it } from "vitest";
import production from "./__fixtures__/chunk-quality-production.json";
import {
  endsWithEchoVerb,
  gateUsageChunks,
  hasForeignScript,
  normalizeChunkPos,
  senseConflict,
  stripChunkSelfCheck,
  type ChunkDropReason,
} from "./chunk-quality";
import { AiUsageChunkSchema, ExtrasSchema, type AiUsageChunk } from "./extras";

/**
 * **使い方の型（チャンク）の門**（2026-10-15 オーナー「チャンクのミスが多すぎる。今までのミス、考えられる
 * 起こりうるミスを考えて対策をして」「拿刷子刷牙 間違ってる」）。
 *
 * 本番の 60 日分（412 行・1,215 個の型）を読んで分けた失敗の種類を、1つずつ固定する。
 * 下の「落としてはいけない」本番の 33 語（`__fixtures__/chunk-quality-production.json`）で、
 * 良い型まで落とさないことも見る。
 */

type P = {
  text: string;
  pos?: string;
  slot?: boolean;
  ja?: string;
  alts?: { text: string; ja: string }[];
};
const chunk = (parts: P[], ja = "", extra: Partial<AiUsageChunk> = {}): AiUsageChunk =>
  ({ parts: parts.map((p) => ({ pos: "", ...p })), ja, ...extra }) as AiUsageChunk;

function reasons(
  chunks: AiUsageChunk[],
  ctx: { headword: string; readerLang?: string; meaning?: string; mw?: { word: string }[] },
): Array<ChunkDropReason | "kept"> {
  return chunks.map((c) => {
    const g = gateUsageChunks([c], {
      headword: ctx.headword,
      language: "zh-TW",
      readerLang: ctx.readerLang ?? "ja",
      meaning: ctx.meaning ?? "",
      measureWords: ctx.mw ?? [],
    });
    return g.kept.length ? "kept" : g.dropped[0].reason;
  });
}

describe("刷子 — 本番の英語のカードそのまま（2026-10-15 15:09 UTC、word_explanations en）", () => {
  // 返ってきた3つの型そのもの。
  const payload: AiUsageChunk[] = [
    chunk(
      [
        { text: "用", pos: "Prep" },
        { text: "刷子", pos: "O" },
        {
          text: "刷",
          pos: "V",
          slot: true,
          ja: "scrub",
          alts: [
            { text: "洗", ja: "wash" },
            { text: "擦", ja: "rub" },
            { text: "清", ja: "clean" },
          ],
        },
      ],
      "scrub with a brush",
    ),
    chunk(
      [
        { text: "毛", pos: "S" },
        { text: "很", pos: "Adv" },
        { text: "軟", pos: "Vs", slot: true, ja: "soft" },
        { text: "的", pos: "Ptc" },
        { text: "刷子", pos: "O" },
      ],
      "a soft-bristled brush",
    ),
    chunk(
      [
        { text: "拿", pos: "V" },
        { text: "刷子", pos: "O" },
        {
          text: "刷牙",
          pos: "V",
          slot: true,
          ja: "brush teeth",
          alts: [
            { text: "洗鞋", ja: "wash shoes" },
            { text: "洗碗", ja: "wash dishes" },
            { text: "刷地", ja: "scrub the floor" },
          ],
        },
      ],
      "take a brush to scrub",
    ),
  ];

  it("3つとも落ちる: 用刷子刷（見出し語の字の言い直し）/ 毛很軟的刷子（長い）/ 拿刷子刷牙（歯を磨くのは牙刷）", () => {
    expect(reasons(payload, { headword: "刷子", readerLang: "en", meaning: "brush" })).toEqual([
      "echo_verb",
      "too_many_parts",
      "sense_conflict",
    ]);
  });

  it("拿刷子刷牙 は表に無くても、意味の欄（brush / ブラシ）とぶつかるので落ちる", () => {
    expect(senseConflict(payload[2], { headword: "刷子", meaning: "brush" })).toBe("brush");
    expect(senseConflict(payload[2], { headword: "刷子", meaning: "ブラシ、たわし" })).toBe(
      "brush",
    );
    // 歯ブラシ（牙刷）のカードでは 刷牙 は正しい型。
    expect(
      senseConflict(chunk([{ text: "用" }, { text: "牙刷" }, { text: "刷牙" }]), {
        headword: "牙刷",
        meaning: "歯ブラシ",
      }),
    ).toBeNull();
  });

  it("掃除のブラシの本当の型は通る（用刷子刷鞋子 / 用刷子刷地板）", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "用", pos: "Prep" },
              { text: "刷子", pos: "N" },
              { text: "刷", pos: "V" },
              { text: "鞋子", pos: "N" },
            ],
            "scrub shoes with a brush",
          ),
          chunk(
            [
              { text: "用", pos: "Prep" },
              { text: "刷子", pos: "N" },
              { text: "刷", pos: "V" },
              { text: "地板", pos: "N" },
            ],
            "scrub the floor with a brush",
          ),
        ],
        { headword: "刷子", readerLang: "en", meaning: "brush" },
      ),
    ).toEqual(["kept", "kept"]);
  });
});

describe("花束 — 本番の日本語のカードそのまま（2026-10-15 09:27 UTC）", () => {
  const payload = [
    chunk(
      [
        { text: "送", pos: "V" },
        { text: "花束", pos: "O", slot: false },
      ],
      "花束を贈る",
    ),
    chunk(
      [
        { text: "一束", pos: "M" },
        { text: "花束", pos: "O", slot: false },
      ],
      "ひと束の花束",
    ),
    chunk(
      [
        { text: "準備", pos: "V" },
        { text: "花束", pos: "O", slot: false },
      ],
      "花束を用意する",
    ),
  ];
  it("一束花束 は重ね言葉として落ち、残り2つは通る", () => {
    expect(reasons(payload, { headword: "花束", meaning: "花束", mw: [{ word: "一束" }] })).toEqual(
      ["kept", "redundant_measure", "kept"],
    );
  });
});

describe("本番で見つかった失敗の種類（1つずつ）", () => {
  it("意味の取り違え: 機車（スクーター）に俗語の「很機車」/ 尺（定規）に長さの単位 / 貓眼（ドアスコープ）に首飾り", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "他", pos: "N" },
              { text: "很", pos: "Adv" },
              { text: "機車", pos: "Vs" },
            ],
            "彼はすごく意地が悪い",
          ),
        ],
        {
          headword: "機車",
          meaning: "スクーター",
        },
      ),
    ).toEqual(["sense_conflict"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "剪", pos: "V" },
              { text: "三尺", pos: "N" },
              { text: "布", pos: "N" },
            ],
            "布を三尺切る",
          ),
        ],
        {
          headword: "尺",
          meaning: "定規",
        },
      ),
    ).toEqual(["headword_not_token"]);
    expect(
      senseConflict(
        chunk(
          [{ text: "項鍊" }, { text: "有" }, { text: "貓眼" }],
          "The necklace has a cat's eye.",
        ),
        {
          headword: "貓眼",
          meaning: "door peephole",
        },
      ),
    ).toBe("peephole");
  });

  it("量詞の型（量詞は別の欄）: 再來一碗肉燥麵 / 買一台小冰箱 / 這台立扇。介詞の 把 は量詞ではない", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "再來一碗", pos: "V" },
              { text: "肉燥麵", pos: "O" },
            ],
            "おかわり",
          ),
          chunk(
            [
              { text: "買一台", pos: "V" },
              { text: "小冰箱", pos: "N" },
            ],
            "小型冷蔵庫を一台買う",
          ),
          chunk(
            [
              { text: "這台", pos: "Det" },
              { text: "立扇", pos: "N" },
            ],
            "この扇風機",
          ),
          chunk(
            [
              { text: "把", pos: "Prep" },
              { text: "手帕", pos: "N" },
              { text: "拿出來", pos: "V" },
            ],
            "ハンカチを取り出す",
          ),
        ].slice(0, 4),
        { headword: "肉燥麵" },
      ).slice(0, 1),
    ).toEqual(["measure_word"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "買一台", pos: "V" },
              { text: "小冰箱", pos: "N" },
            ],
            "小型冷蔵庫を一台買う",
          ),
        ],
        { headword: "小冰箱" },
      ),
    ).toEqual(["measure_word"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "這台", pos: "Det" },
              { text: "立扇", pos: "N" },
            ],
            "この扇風機",
          ),
        ],
        { headword: "立扇" },
      ),
    ).toEqual(["measure_word"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "把", pos: "Prep" },
              { text: "手帕", pos: "N" },
              { text: "拿出來", pos: "V" },
            ],
            "ハンカチを取り出す",
          ),
        ],
        { headword: "手帕" },
      ),
    ).toEqual(["kept"]);
    // pos だけ M の札（剛出爐的/M）は量詞と見ない。
    expect(
      reasons(
        [
          chunk(
            [
              { text: "剛出爐的", pos: "M" },
              { text: "葡式蛋塔", pos: "N" },
            ],
            "焼き立てのエッグタルト",
          ),
        ],
        { headword: "葡式蛋塔" },
      ),
    ).toEqual(["kept"]);
  });

  it("見出し語が1つの札として入っていない: 桃 に 買一盒桃子 / 手 に 拿手機 / 床 に 起床", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "拿", pos: "V" },
              { text: "手機", pos: "N" },
            ],
            "スマホを持つ",
          ),
        ],
        { headword: "手" },
      ),
    ).toEqual(["headword_not_token"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "水蜜桃", pos: "N" },
              { text: "超", pos: "Adv" },
              { text: "多汁", pos: "Vs" },
            ],
            "桃がジューシー",
          ),
        ],
        { headword: "桃" },
      ),
    ).toEqual(["headword_not_token"]);
    expect(reasons([chunk([{ text: "起床", pos: "Vi" }], "起きる")], { headword: "床" })).toEqual([
      "single_token",
    ]);
  });

  it("1語を割っただけ: 門＋口 / 手＋機 / 楊桃＋汁。飲み物の注文の言い方（奶茶＋半糖）は通る", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "門", pos: "N" },
              { text: "口", pos: "N" },
            ],
            "入り口",
          ),
        ],
        { headword: "門" },
      ),
    ).toEqual(["compound_split"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "楊桃", pos: "N" },
              { text: "汁", pos: "N" },
            ],
            "スターフルーツジュース",
          ),
        ],
        { headword: "楊桃" },
      ),
    ).toEqual(["compound_split"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "奶茶", pos: "N" },
              { text: "半糖", pos: "Adv" },
            ],
            "ミルクティーを甘さ半分で",
          ),
        ],
        { headword: "奶茶" },
      ),
    ).toEqual(["kept"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "奶茶", pos: "N" },
              { text: "去冰", pos: "N" },
            ],
            "ミルクティーを氷なしで",
          ),
        ],
        { headword: "奶茶" },
      ),
    ).toEqual(["kept"]);
  });

  it("主語のある文・句点: 這個貓眼很漂亮 / 這間湯咖哩很有名 / 我每天早上都要喝一杯咖啡", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "這個", pos: "Det" },
              { text: "貓眼", pos: "N" },
              { text: "很", pos: "Adv" },
              { text: "漂亮", pos: "Vs" },
            ],
            "This cat's eye is very beautiful.",
          ),
        ],
        {
          headword: "貓眼",
          readerLang: "en",
        },
      ),
    ).toEqual(["sentence"]);
    expect(
      reasons(
        [
          chunk(
            [{ text: "我" }, { text: "喝" }, { text: "咖啡" }, { text: "。" }],
            "コーヒーを飲む",
          ),
        ],
        { headword: "咖啡" },
      ),
    ).toEqual(["sentence"]);
  });

  it("どの名詞にも付く組み合わせ（買・喜歡・這款）", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "買", pos: "V" },
              { text: "泡芙", pos: "O" },
            ],
            "シュークリームを買う",
          ),
        ],
        { headword: "泡芙" },
      ),
    ).toEqual(["generic"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "這款", pos: "Det" },
              { text: "保溫瓶", pos: "N" },
            ],
            "この保温ボトル",
          ),
        ],
        { headword: "保溫瓶" },
      ),
    ).toEqual(["generic"]);
  });

  it("崩れた型（嘴邊肉＋切）・見出し語の字の言い直し（夾子＋夾）", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "嘴邊肉", pos: "N" },
              { text: "切", pos: "V" },
            ],
            "豚のほほ肉を切る",
          ),
        ],
        { headword: "嘴邊肉" },
      ),
    ).toEqual(["broken"]);
    expect(
      endsWithEchoVerb(
        [
          { text: "用", pos: "Prep" },
          { text: "夾子", pos: "N" },
          { text: "夾", pos: "V" },
        ],
        "夾子",
      ),
    ).toBe(true);
    expect(
      endsWithEchoVerb(
        [
          { text: "從", pos: "Prep" },
          { text: "貓眼", pos: "N" },
          { text: "看", pos: "V" },
        ],
        "貓眼",
      ),
    ).toBe(false);
  });

  it("札に別の言語の字（かな・英語の語）。T恤・Q彈 は語の一部として通す", () => {
    expect(hasForeignScript("ゴボウ", "zh-TW")).toBe(true);
    expect(hasForeignScript("mango", "zh-TW")).toBe(true);
    expect(hasForeignScript("T恤", "zh-TW")).toBe(false);
    expect(hasForeignScript("Q彈", "zh-TW")).toBe(false);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "吃", pos: "V" },
              { text: "マンゴー", pos: "N" },
              { text: "芒果", pos: "N" },
            ],
            "",
          ),
        ],
        { headword: "芒果" },
      ),
    ).toEqual(["foreign_script"]);
  });

  it("品詞の名前を日本語・英語で書いた回は記号に直して通す（放置/動詞+滅蟑餌劑/名詞）", () => {
    expect(normalizeChunkPos("動詞")).toBe("V");
    expect(normalizeChunkPos("measure word phrase")).toBe("M");
    expect(normalizeChunkPos("Vs-attr")).toBe("Vs-attr");
    const g = gateUsageChunks(
      [
        chunk(
          [
            { text: "放置", pos: "動詞" },
            { text: "滅蟑餌劑", pos: "名詞" },
          ],
          "毒餌を置く",
        ),
      ],
      {
        headword: "滅蟑餌劑",
        language: "zh-TW",
        readerLang: "ja",
      },
    );
    expect(g.kept[0].parts.map((p) => p.pos)).toEqual(["V", "N"]);
  });

  it("札の字が品詞の記号そのもの（練手臂＋O）はその札だけ外す", () => {
    const g = gateUsageChunks(
      [
        chunk(
          [
            { text: "敷", pos: "V" },
            { text: "面膜", pos: "N" },
            { text: "O", pos: "" },
          ],
          "パックをする",
        ),
      ],
      {
        headword: "面膜",
        language: "zh-TW",
        readerLang: "ja",
      },
    );
    expect(g.kept[0].parts.map((p) => p.text)).toEqual(["敷", "面膜"]);
  });

  it("訳が無い・訳が型の写し・訳が読む人の言語でない（繁體中文で読む人の訳は空でよい）", () => {
    expect(
      reasons(
        [
          chunk(
            [
              { text: "敷", pos: "V" },
              { text: "面膜", pos: "N" },
            ],
            "",
          ),
        ],
        { headword: "面膜" },
      ),
    ).toEqual(["no_translation"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "洗", pos: "V" },
              { text: "髒的杯子", pos: "O" },
            ],
            "洗髒杯子",
          ),
        ],
        { headword: "髒的杯子" },
      ),
    ).toEqual(["translation_language"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "敷", pos: "V" },
              { text: "面膜", pos: "N" },
            ],
            "put on a face mask",
          ),
        ],
        { headword: "面膜", readerLang: "ja" },
      ),
    ).toEqual(["translation_language"]);
    expect(
      reasons(
        [
          chunk(
            [
              { text: "敷", pos: "V" },
              { text: "面膜", pos: "N" },
            ],
            "",
          ),
        ],
        { headword: "面膜", readerLang: "zh-TW" },
      ),
    ).toEqual(["kept"]);
  });

  it("同じ型・同じ訳の2つ目（擦凡士林 と 抹凡士林 が両方「ワセリンを塗る」）", () => {
    const g = gateUsageChunks(
      [
        chunk(
          [
            { text: "擦", pos: "V" },
            { text: "凡士林", pos: "N" },
          ],
          "ワセリンを塗る",
        ),
        chunk(
          [
            { text: "抹", pos: "V" },
            { text: "凡士林", pos: "N" },
          ],
          "ワセリンを塗る",
        ),
        chunk(
          [
            { text: "擦", pos: "V" },
            { text: "凡士林", pos: "N" },
          ],
          "ワセリンをつける",
        ),
      ],
      { headword: "凡士林", language: "zh-TW", readerLang: "ja" },
    );
    expect(g.kept).toHaveLength(1);
    expect(g.dropped.map((d) => d.reason)).toEqual(["duplicate_translation", "duplicate"]);
  });

  it("AI 自身が fits:false と答えた型は落とし、保存する物から fits / why を外す", () => {
    const parsed = AiUsageChunkSchema.parse({
      parts: [
        { text: "敷", pos: "V" },
        { text: "面膜", pos: "N" },
      ],
      ja: "パックをする",
      fits: "false",
      why: "不自然",
    });
    expect(parsed.fits).toBe(false);
    expect(reasons([parsed], { headword: "面膜" })).toEqual(["self_check"]);
    const ok = gateUsageChunks([{ ...parsed, fits: true }], {
      headword: "面膜",
      language: "zh-TW",
      readerLang: "ja",
    });
    expect(ok.kept[0]).not.toHaveProperty("fits");
    expect(ok.kept[0]).not.toHaveProperty("why");
    expect(stripChunkSelfCheck({ ...parsed, fits: true })).not.toHaveProperty("why");
  });

  it("見出し語の札と、名詞・量詞・程度の語でない札の slot・alts は外して保存する", () => {
    const g = gateUsageChunks(
      [
        chunk(
          [
            { text: "用", pos: "Prep" },
            { text: "刷子", pos: "N", slot: true, alts: [{ text: "鞋刷", ja: "" }] },
            { text: "刷", pos: "V", slot: true, alts: [{ text: "洗", ja: "wash" }] },
            { text: "鞋子", pos: "N", slot: true, alts: [{ text: "地板", ja: "floor" }] },
          ],
          "scrub shoes with a brush",
        ),
      ],
      { headword: "刷子", language: "zh-TW", readerLang: "en", meaning: "brush" },
    );
    const [, head, verb, noun] = g.kept[0].parts;
    expect(head.slot).toBeUndefined();
    expect(verb.slot).toBeUndefined();
    expect(verb.alts).toBeUndefined();
    expect(noun.slot).toBe(true);
  });

  it("extras の形も fits / why と札の読みを落とさない（門より先に zod が消さない）", () => {
    const ex = ExtrasSchema.parse({
      usage_chunks: [
        {
          parts: [{ text: "敷", pos: "V", pinyin: "fū", zhuyin: "ㄈㄨ" }],
          ja: "x",
          fits: false,
          why: "y",
        },
      ],
    });
    expect(ex.usage_chunks[0].fits).toBe(false);
    expect(ex.usage_chunks[0].parts[0].pinyin).toBe("fū");
  });
});

describe("落としてはいけない: 本番の 33 語（良い型）", () => {
  type Row = {
    headword: string;
    meaning: string;
    el: string;
    uc: AiUsageChunk[];
    mw: { word: string }[];
  };
  const rows = production as unknown as Row[];

  it("どの語にも型が残る（1つの札しか無かった 鍵盤 を除く）", () => {
    for (const r of rows) {
      const g = gateUsageChunks(r.uc, {
        headword: r.headword,
        language: "zh-TW",
        readerLang: r.el,
        meaning: r.meaning,
        measureWords: r.mw,
      });
      if (r.headword === "鍵盤") expect(g.kept).toHaveLength(0);
      else
        expect({ headword: r.headword, kept: g.kept.length > 0 }).toEqual({
          headword: r.headword,
          kept: true,
        });
    }
  });

  it("落ちるのは理由の分かる物だけ（量詞・汎用・1語・主語のある文・同じ訳）で、全体の 85% 以上が残る", () => {
    let total = 0;
    let kept = 0;
    const allowed = new Set<ChunkDropReason>([
      "measure_word",
      "generic",
      "compound_split",
      "single_token",
      "sentence",
      "duplicate_translation",
      "headword_not_token",
    ]);
    for (const r of rows) {
      const g = gateUsageChunks(r.uc, {
        headword: r.headword,
        language: "zh-TW",
        readerLang: r.el,
        meaning: r.meaning,
        measureWords: r.mw,
      });
      total += r.uc.length;
      kept += g.kept.length;
      for (const d of g.dropped)
        expect({ text: d.text, ok: allowed.has(d.reason) }).toEqual({ text: d.text, ok: true });
    }
    expect(kept / total).toBeGreaterThanOrEqual(0.85);
  });

  it("名指しで残る型（拉開拉鍊・戴眼鏡・沖馬桶・涼拌竹筍・裝咖啡在保溫瓶・煎牛排・擦防曬乳）", () => {
    const keptTexts = rows.flatMap((r) =>
      gateUsageChunks(r.uc, {
        headword: r.headword,
        language: "zh-TW",
        readerLang: r.el,
        meaning: r.meaning,
        measureWords: r.mw,
      }).kept.map((c) => c.parts.map((p) => p.text).join("")),
    );
    for (const t of [
      "拉開拉鍊",
      "戴眼鏡",
      "沖馬桶",
      "涼拌竹筍",
      "裝咖啡在保溫瓶",
      "煎牛排",
      "擦防曬乳",
      "敷面膜",
      "臉很紅",
    ]) {
      expect(keptTexts).toContain(t);
    }
  });
});
