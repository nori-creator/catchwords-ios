import { describe, expect, it } from "vitest";
import { etymologyDiagramRule, normalizeEtymologyDiagram } from "./etymology-diagram";
import { ExtrasSchema } from "./extras";
import { stripUnrequested } from "./card-request";

const zh = (headword: string, extra: Record<string, string> = {}) => ({
  headword,
  language: "zh-TW",
  readerLang: "ja",
  ...extra,
});

describe("語源の図（2026-10-15）", () => {
  it("曖昧: 字の組み合わせの図をそのまま返す", () => {
    const d = normalizeEtymologyDiagram(
      {
        kind: "compound",
        parts: [
          { text: "曖", components: ["日", "愛"], meaning: "日がかげる" },
          { text: "昧", components: ["日", "未"], meaning: "夜明け前" },
        ],
        result_meaning: "はっきり見えない",
      },
      zh("曖昧"),
    );
    expect(d).toEqual({
      kind: "compound",
      parts: [
        { text: "曖", components: ["日", "愛"], meaning: "日がかげる" },
        { text: "昧", components: ["日", "未"], meaning: "夜明け前" },
      ],
      result_meaning: "はっきり見えない",
      source: "",
      note: "",
    });
  });

  it("つないでも見出し語にならない分解は other に落とし、説明を必ず入れる", () => {
    const d = normalizeEtymologyDiagram(
      { kind: "compound", parts: [{ text: "曖" }, { text: "味" }] },
      zh("曖昧", { etymology: "「曖」も「昧」も暗くてよく見えないことを表す。古くからの言い方。" }),
    );
    expect(d.kind).toBe("other");
    expect(d.parts).toEqual([]);
    expect(d.note).toBe("「曖」も「昧」も暗くてよく見えないことを表す。");
  });

  it("外来語（沙發 ← sofa）: 図の箱は使わず、元の語と説明", () => {
    const d = normalizeEtymologyDiagram(
      { kind: "loanword_phonetic", source: "sofa", parts: [{ text: "沙" }, { text: "發" }] },
      zh("沙發"),
    );
    expect(d).toMatchObject({ kind: "loanword_phonetic", parts: [], source: "sofa" });
    expect(d.note).toBe("「sofa」の音を写した外来語。");
  });

  it("固有名詞・1字の語・何も返らない時も、空の図にしない", () => {
    expect(normalizeEtymologyDiagram({ kind: "proper" }, zh("全聯")).note).toBe(
      "商品名・店名などの固有名詞。",
    );
    const one = normalizeEtymologyDiagram({ kind: "single_char", parts: [] }, zh("傘"));
    expect(one.parts).toEqual([{ text: "傘", components: [], meaning: "" }]);
    expect(one.note).toBe("「傘」は1字の語。");
    // 2字の語に single_char は other
    expect(normalizeEtymologyDiagram({ kind: "single_char" }, zh("雨傘")).kind).toBe("other");
    const none = normalizeEtymologyDiagram(null, zh("便當"));
    expect(none).toMatchObject({ kind: "other", parts: [] });
    expect(none.note).toBe("「便當」は分けずに一語で覚える言葉。");
    expect(normalizeEtymologyDiagram("壊れた", { ...zh("便當"), readerLang: "en" }).note).toBe(
      'Learn "便當" as one word.',
    );
  });

  it("読む人の言語でない意味は落とし、英語の語根の分解は字の照合をしない", () => {
    const d = normalizeEtymologyDiagram(
      {
        kind: "compound",
        parts: [
          { text: "re-", components: ["x"], meaning: "再び" },
          { text: "ject", meaning: "投げる" },
        ],
        result_meaning: "拒む",
      },
      { headword: "reject", language: "en", readerLang: "ja" },
    );
    expect(d.kind).toBe("compound");
    expect(d.parts.map((p) => p.text)).toEqual(["re-", "ject"]);
  });

  it("extras に図の欄があり、語源を頼まない呼び出しでは落とす", () => {
    const ex = ExtrasSchema.parse({ etymology_diagram: { kind: "other", note: "x" } });
    expect(ex.etymology_diagram?.kind).toBe("other");
    expect(ExtrasSchema.parse({}).etymology_diagram).toBeNull();
    expect(stripUnrequested({ etymology_diagram: {} }, ["meaning"])).not.toHaveProperty(
      "etymology_diagram",
    );
    expect(etymologyDiagramRule("zh-TW", "日本語")).toMatch(/loanword_phonetic/);
    expect(etymologyDiagramRule("en", "日本語")).toMatch(/語根/);
  });
});
