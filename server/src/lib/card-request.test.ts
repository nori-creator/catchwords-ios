import { describe, expect, it } from "vitest";
import { stripUnrequested, wantsSection } from "./card-request";
import { DEFAULT_VISIBLE } from "./card-prefs";

describe("カードを作るときに頼む節", () => {
  it("既定の8項目なら、語源・覚え方・追加の例文・発音のコツ・台湾メモは頼まない", () => {
    for (const id of [
      "etymology",
      "mnemonic",
      "examples_extra",
      "pronunciation_tips",
      "taiwan_note",
    ] as const) {
      expect(wantsSection(DEFAULT_VISIBLE, id)).toBe(false);
    }
    for (const id of ["usage_chunks", "related_words", "measure_words"] as const) {
      expect(wantsSection(DEFAULT_VISIBLE, id)).toBe(true);
    }
  });

  it("意味・例文は、見えていなくても常に頼む（ほかの機能が使う）", () => {
    expect(wantsSection([], "meaning")).toBe(true);
    expect(wantsSection([], "example")).toBe(true);
  });

  it("節の一覧を渡さない古い呼び出しは、これまでどおり全部", () => {
    expect(wantsSection(undefined, "etymology")).toBe(true);
  });

  it("頼まなかった欄は返事から落とす（空で上書きしない）。頼んだ欄と共通の欄は残す", () => {
    const e = {
      etymology: "",
      radicals: "",
      mnemonic: "",
      usage_context: "夜市で",
      related_words: [{ word: "奶茶" }],
    };
    expect(stripUnrequested(e, DEFAULT_VISIBLE)).toEqual({
      usage_context: "夜市で",
      related_words: [{ word: "奶茶" }],
    });
    expect(stripUnrequested(e, undefined)).toBe(e);
  });
});
