import { describe, expect, it } from "vitest";
import {
  EXAMPLE_PROMPT_VERSION,
  ExamplePatternSchema,
  alignExampleExtras,
  alignExtraExamples,
  applyExamplePatterns,
  nearDuplicateExample,
  sceneMaxChars,
  shortScene,
  similarity,
  exampleMatchesSentence,
  examplePatternsRule,
  guardExampleColumns,
  pickExamplePatterns,
  type ExamplePattern,
} from "./example-patterns";
import { CardReplySchema } from "./card-schema";
import { fillEmptySharedExtras } from "./shared-word-guard";
import { sectionNeedsFill } from "./card-sections";
import { normalizeExtras } from "./extras";

const p = (o: Partial<ExamplePattern>): ExamplePattern => ExamplePatternSchema.parse(o);

const zhOpts = { headword: "眼鏡", language: "zh-TW", readerLang: "ja" };

describe("pickExamplePatterns", () => {
  it("よく使う順に並べ、札と文を組のまま返す", () => {
    const out = pickExamplePatterns(
      [
        p({
          share: 20,
          sentence: "你的眼鏡好好看！",
          scene: "友達の新しいメガネをほめるとき",
          translation: "そのメガネかわいいね！",
        }),
        p({
          share: 60,
          sentence: "我的眼鏡不見了。",
          scene: "メガネが見つからず家で探しているとき",
          translation: "メガネがなくなった。",
        }),
      ],
      zhOpts,
    );
    expect(out.map((e) => e.sentence)).toEqual(["我的眼鏡不見了。", "你的眼鏡好好看！"]);
    expect(out[0].scene).toBe("メガネが見つからず家で探しているとき");
  });

  it("自己点検が false・札が空・見出し語の無い文・同じ文は落とす", () => {
    const out = pickExamplePatterns(
      [
        p({
          share: 90,
          sentence: "我戴眼鏡。",
          scene: "友達が眼鏡をしていないことに気づいたとき",
          scene_fits: false,
        }),
        p({ share: 80, sentence: "我的眼鏡呢？", scene: "" }),
        p({ share: 70, sentence: "我看不清楚。", scene: "遠くの字が読めないとき" }),
        p({ share: 60, sentence: "我的眼鏡不見了。", scene: "メガネを探しているとき" }),
        p({ share: 50, sentence: "我的眼鏡不見了！", scene: "メガネを探しているとき" }),
      ],
      zhOpts,
    );
    expect(out.map((e) => e.sentence)).toEqual(["我的眼鏡不見了。"]);
  });

  it("scene_fits が無い（確かめていない）だけでは落とさない・文字列の false は落とす", () => {
    expect(
      pickExamplePatterns(
        [p({ sentence: "我的眼鏡不見了。", scene: "メガネを探しているとき" })],
        zhOpts,
      ),
    ).toHaveLength(1);
    expect(
      pickExamplePatterns(
        [
          p({
            sentence: "我的眼鏡不見了。",
            scene: "メガネを探しているとき",
            scene_fits: "false" as never,
          }),
        ],
        zhOpts,
      ),
    ).toHaveLength(0);
  });

  it("上限を守る（追加の例文を頼まない呼び出しは1つ）", () => {
    const many = [
      p({ share: 50, sentence: "我的眼鏡不見了。", scene: "家でメガネを探して" }),
      p({ share: 20, sentence: "你戴眼鏡好帥！", scene: "友達の新しいメガネをほめる" }),
      p({ share: 15, sentence: "眼鏡起霧了，看不到。", scene: "冬に熱いラーメンを食べて" }),
      p({ share: 10, sentence: "這副眼鏡多少錢？", scene: "眼鏡屋で値段を聞く" }),
      p({ share: 5, sentence: "睡覺前記得拿下眼鏡。", scene: "寝る前に子どもに言う" }),
    ];
    expect(pickExamplePatterns(many, { ...zhOpts, max: 1 })).toHaveLength(1);
    expect(pickExamplePatterns(many, zhOpts)).toHaveLength(4);
  });

  it("読む人の言語でない札・訳は使わない", () => {
    const out = pickExamplePatterns(
      [p({ sentence: "我的眼鏡不見了。", scene: "找眼鏡的時候", translation: "我的眼鏡不見了。" })],
      zhOpts,
    );
    expect(out).toHaveLength(0);
  });

  it("英語は活用で形が変わるので、見出し語を含むかは見ない", () => {
    const out = pickExamplePatterns(
      [p({ sentence: "I went home early.", scene: "友達に昨日のことを話すとき" })],
      { headword: "go", language: "en", readerLang: "ja" },
    );
    expect(out).toHaveLength(1);
  });
});

describe("applyExamplePatterns", () => {
  const card: {
    example_sentence: string;
    example_translation: string;
    extras: Record<string, unknown>;
  } = { example_sentence: "", example_translation: "", extras: { usage_context: "x" } };
  const picked = [
    {
      sentence: "我的眼鏡不見了。",
      translation: "メガネがなくなった。",
      scene: "メガネを探しているとき",
      chunks: [],
    },
    {
      sentence: "你的眼鏡好好看！",
      translation: "そのメガネいいね！",
      scene: "友達のメガネをほめるとき",
      chunks: [],
    },
  ];

  it("1つ目をメインの例文に、残りを追加の例文に写し、札に文の目印を付ける", () => {
    const out = applyExamplePatterns(card, picked, { withExtra: true });
    expect(out.example_sentence).toBe("我的眼鏡不見了。");
    expect(out.extras.example_scene).toBe("メガネを探しているとき");
    expect(out.extras.example_scene_for).toBe("我的眼鏡不見了。");
    expect(out.extras.example_v).toBe(EXAMPLE_PROMPT_VERSION);
    expect(out.extras.examples_extra).toEqual([
      {
        zh: "你的眼鏡好好看！",
        ja: "そのメガネいいね！",
        scene: "友達のメガネをほめるとき",
        scene_for: "你的眼鏡好好看！",
        chunks: [],
      },
    ]);
    expect(out.extras.example_pattern_count).toBe(2);
    expect(out.extras.usage_context).toBe("x");
  });

  it("追加の例文を頼まない呼び出しでは examples_extra と数を書かない", () => {
    const out = applyExamplePatterns(card, picked.slice(0, 1), { withExtra: false });
    expect(out.extras).not.toHaveProperty("examples_extra");
    expect(out.extras).not.toHaveProperty("example_pattern_count");
  });

  it("1つも残らなければカードはそのまま", () => {
    expect(applyExamplePatterns(card, [], { withExtra: true })).toBe(card);
  });

  it("1つの場面だけの語は、追加の例文の節を作り直しに行かない", () => {
    const out = applyExamplePatterns(card, picked.slice(0, 1), { withExtra: true });
    expect(out.extras.examples_extra).toEqual([]);
    expect(
      sectionNeedsFill("examples_extra", {
        headword: "眼鏡",
        language: "zh-TW",
        extras: normalizeExtras(out.extras),
      }),
    ).toBe(false);
  });
});

describe("文と札を組で扱う（2026-10-15 眼鏡）", () => {
  const fresh = {
    example_scene: "メガネを探しているとき",
    example_chunks: [{ text: "眼鏡", pos: "N" }],
    example_scene_for: "我的眼鏡不見了。",
    example_v: 2,
    usage_context: "毎日",
  };

  it("共有の行の文が別の文なら、札・パーツは埋めない（ほかの項目は埋める）", () => {
    const filled = fillEmptySharedExtras(
      {
        usage_context: "",
        example_scene: "",
        related_words: [{ word: "a", kind: "rel", note: "n" }],
      },
      alignExampleExtras(fresh, "我戴眼鏡。"),
    );
    expect(filled?.example_scene).toBe("");
    expect(filled).not.toHaveProperty("example_scene_for");
    expect(filled?.usage_context).toBe("毎日");
  });

  it("同じ文（句読点の違いだけ）なら札も埋める", () => {
    expect(alignExampleExtras(fresh, "我的眼鏡不見了！")).toBe(fresh);
  });

  it("目印の無い古い extras は触らない", () => {
    const legacy = { example_scene: "昔の札" };
    expect(alignExampleExtras(legacy, "我戴眼鏡。")).toBe(legacy);
  });

  it("訳だけを別の文の訳で埋めない", () => {
    expect(
      guardExampleColumns(
        { example_translation: "メガネがなくなった。" },
        { example_sentence: "我戴眼鏡。" },
        { example_sentence: "我的眼鏡不見了。" },
      ),
    ).toEqual({});
    // 文も一緒に埋める回・文がまだ無い回は、そのまま
    expect(
      guardExampleColumns(
        { example_sentence: "我的眼鏡不見了。", example_translation: "メガネがなくなった。" },
        { example_sentence: "" },
        { example_sentence: "我的眼鏡不見了。" },
      ),
    ).toHaveProperty("example_translation");
    expect(exampleMatchesSentence("我的眼鏡不見了。", "")).toBe(true);
  });
});

describe("examplePatternsRule / CardReplySchema", () => {
  const rule = (max: number) =>
    examplePatternsRule({
      headword: "眼鏡",
      targetName: "台湾華語",
      nl: "日本語",
      max,
      levelRule: "例文のレベル: TOCFL 1",
      sourceRule: "例文の作り方",
      chunkRoles: "S / V / O",
    });

  it("パターン → 一文 → その文のための札 → 確かめ の順に頼み、数を水増ししない", () => {
    const r = rule(4);
    expect(r).toMatch(/1〜4個/);
    expect(r).toMatch(/数を合わせるために場面を作らない/);
    expect(r).toMatch(/scene_fits/);
    expect(r.indexOf("sentence")).toBeLessThan(r.indexOf("scene を書く"));
    expect(r).toMatch(/例文のレベル: TOCFL 1/);
    expect(rule(1)).toMatch(/いちばんよく使うパターン1つだけ/);
  });

  it("返事の example_patterns が壊れていてもカードは落ちない", () => {
    const card = CardReplySchema.parse({ meaning_ja: "メガネ", example_patterns: "壊れた" });
    expect(card.example_patterns).toEqual([]);
    const ok = CardReplySchema.parse({
      meaning_ja: "メガネ",
      example_patterns: [
        { sentence: "我的眼鏡不見了。", scene: "x", share: "60", scene_fits: true },
      ],
    });
    expect(ok.example_patterns[0].share).toBe(60);
  });
});

describe("似た場面は2つに分けない・札は短く（2026-10-15）", () => {
  it("札がよく似たパターン・同じ文型の文は、よく使う方だけ残す", () => {
    const out = pickExamplePatterns(
      [
        p({ share: 60, sentence: "我要一杯珍珠奶茶。", scene: "手搖飲の店で注文するとき" }),
        p({ share: 30, sentence: "我要兩杯珍珠奶茶。", scene: "店で友達の分も頼む" }),
        p({ share: 20, sentence: "珍珠奶茶超好喝！", scene: "手搖飲の店で注文するときに" }),
        p({ share: 10, sentence: "這家的珍珠奶茶很有名。", scene: "友達に人気の店を教える" }),
      ],
      { headword: "珍珠奶茶", language: "zh-TW", readerLang: "ja" },
    );
    expect(out.map((e) => e.sentence)).toEqual(["我要一杯珍珠奶茶。", "這家的珍珠奶茶很有名。"]);
  });

  it("似ていない2つは両方残す", () => {
    expect(
      nearDuplicateExample(
        { scene: "家でメガネを探して", sentence: "我的眼鏡不見了。" },
        { scene: "友達の新しいメガネをほめる", sentence: "你戴眼鏡好帥！" },
        "眼鏡",
      ),
    ).toBe(false);
    expect(similarity("abc", "abc")).toBe(1);
  });

  it("札は読む人の言語ごとの上限まで短くする（区切りがあればそこで）", () => {
    expect(sceneMaxChars("ja")).toBe(24);
    expect(sceneMaxChars("zh-TW")).toBe(18);
    expect(sceneMaxChars("en")).toBe(60);
    const long = "夜市の屋台で、友達と一緒に食べ歩きをしながら、おいしい物を探しているとき";
    const short = shortScene(long, "ja");
    expect([...short].length).toBeLessThanOrEqual(24);
    expect(short).toBe("夜市の屋台で、友達と一緒に食べ歩きをしながら");
    expect(shortScene("家でメガネを探して。", "ja")).toBe("家でメガネを探して");
  });

  it("追加の例文も文の目印で確かめる（別の文のための札は空にする）", () => {
    expect(
      alignExtraExamples([
        { zh: "你戴眼鏡好帥！", scene: "友達のメガネをほめる", scene_for: "你戴眼鏡好帥！" },
        { zh: "這副眼鏡多少錢？", scene: "家でメガネを探して", scene_for: "我的眼鏡不見了。" },
        { zh: "舊的", scene: "目印の無い古い札" },
      ]).map((e) => e.scene),
    ).toEqual(["友達のメガネをほめる", "", "目印の無い古い札"]);
  });
});

describe("例文は自然さが先・級は目安（オーナー決定 2026-10-15）", () => {
  it("級より上の語（質地・黏膩）を含む自然な文も、級を理由に落とさない", () => {
    const picked = pickExamplePatterns(
      [
        {
          situation: "",
          share: 70,
          sentence: "這款防曬乳質地很清爽，擦起來一點都不黏膩。",
          translation: "この日焼け止めはテクスチャーがさっぱりしていて、塗っても全然べたつかない。",
          scene: "ドラッグストアで友達に勧めるとき",
          chunks: [],
          scene_fits: true,
        },
      ],
      { headword: "防曬乳", language: "zh-TW", readerLang: "ja", max: 4 },
    );
    expect(picked.map((p) => p.sentence)).toEqual(["這款防曬乳質地很清爽，擦起來一點都不黏膩。"]);
  });
});
