import { describe, it, expect } from "vitest";
import {
  CEFR_SCALE,
  LEVEL_INDEXES,
  LEVEL_OUT,
  TOCFL_SCALE,
  levelOptions,
  restoreLevel,
  parseLevelStep,
} from "./level-scale";

/**
 * 級の目盛りを2つの体系で共有する所の門。
 *
 * ここで一番怖いのは**取り違え** — `A1` の 1 を TOCFL の1級と読んだり、
 * `TOCFL-2` のハイフンを符号と読んだりすると、級が静かに間違う。
 * 級は「この語は自分に難しいか」の判断そのものなので、静かに間違うと
 * 学習の順番が崩れる。
 */

describe("parseLevelStep — TOCFL の形", () => {
  it("いろいろな書き方から段を取り出す", () => {
    expect(parseLevelStep("TOCFL-2")).toBe(2);
    expect(parseLevelStep("tocfl 5")).toBe(5);
    expect(parseLevelStep("3")).toBe(3);
    expect(parseLevelStep(4)).toBe(4);
    expect(parseLevelStep("第6級")).toBe(6);
  });

  it("**`TOCFL-2` のハイフンを符号と読まない**", () => {
    // `-?\d+` と書くと 2級が -2 になり、丸ごと級外へ落ちる。
    expect(parseLevelStep("TOCFL-2")).not.toBe(LEVEL_OUT);
  });
});

describe("parseLevelStep — CEFR の形", () => {
  it("A1〜C2 を1〜6に読む", () => {
    expect(parseLevelStep("A1")).toBe(1);
    expect(parseLevelStep("A2")).toBe(2);
    expect(parseLevelStep("B1")).toBe(3);
    expect(parseLevelStep("B2")).toBe(4);
    expect(parseLevelStep("C1")).toBe(5);
    expect(parseLevelStep("C2")).toBe(6);
  });

  it("小文字でも読む", () => {
    expect(parseLevelStep("b2")).toBe(4);
  });

  it("**綴りを数字より先に読む**(`A1` の 1 を1級と取り違えない)", () => {
    expect(parseLevelStep("A1")).toBe(1); // たまたま一致
    expect(parseLevelStep("C1")).toBe(5); // ここで取り違えが出る
    expect(parseLevelStep("B2")).toBe(4);
  });

  it("文の中に混ざっていても拾う", () => {
    expect(parseLevelStep("CEFR B1")).toBe(3);
  });
});

describe("parseLevelStep — 級外と「分からない」", () => {
  it("1〜6 の外は級外", () => {
    expect(parseLevelStep("TOCFL-0")).toBe(LEVEL_OUT);
    expect(parseLevelStep("TOCFL-7")).toBe(LEVEL_OUT);
    expect(parseLevelStep("99")).toBe(LEVEL_OUT);
  });

  it("**「級外」と「分からない」を混ぜない**", () => {
    expect(parseLevelStep(null)).toBeNull();
    expect(parseLevelStep(undefined)).toBeNull();
    expect(parseLevelStep("")).toBeNull();
    expect(parseLevelStep("   ")).toBeNull();
    expect(parseLevelStep("級外")).toBeNull();
    expect(parseLevelStep("unknown")).toBeNull();
  });

  it("壊れた数字で落ちない", () => {
    expect(parseLevelStep(Number.NaN)).toBeNull();
    expect(parseLevelStep("TOCFL-")).toBeNull();
  });
});

describe("段の形が2つの体系で同じ", () => {
  it("どちらも6段", () => {
    expect(TOCFL_SCALE.labels).toHaveLength(6);
    expect(CEFR_SCALE.labels).toHaveLength(6);
  });
});

describe("toStored — 保存する形へ往復できる", () => {
  it("TOCFL", () => {
    for (const i of LEVEL_INDEXES) expect(parseLevelStep(TOCFL_SCALE.toStored(i))).toBe(i);
  });

  it("CEFR", () => {
    for (const i of LEVEL_INDEXES) expect(parseLevelStep(CEFR_SCALE.toStored(i))).toBe(i);
  });
});

describe("levelOptions — 設定に並べる6つ", () => {
  it("**TOCFL の文言が変わっていない**", () => {
    expect(levelOptions(TOCFL_SCALE)).toEqual([
      { value: "TOCFL-1", label: "TOCFL Level 1" },
      { value: "TOCFL-2", label: "TOCFL Level 2" },
      { value: "TOCFL-3", label: "TOCFL Level 3" },
      { value: "TOCFL-4", label: "TOCFL Level 4" },
      { value: "TOCFL-5", label: "TOCFL Level 5" },
      { value: "TOCFL-6", label: "TOCFL Level 6" },
    ]);
  });

  it("**CEFR に `Level` を付けない**(A1級 という体系が無いのと同じ話)", () => {
    const got = levelOptions(CEFR_SCALE);
    expect(got[0]).toEqual({ value: "A1", label: "CEFR A1" });
    expect(got[5]).toEqual({ value: "C2", label: "CEFR C2" });
    for (const o of got) expect(o.label).not.toContain("Level");
  });

  it("**保存する形は読み返せる**(設定した級が次に開いたとき消えない)", () => {
    for (const sc of [TOCFL_SCALE, CEFR_SCALE]) {
      for (const o of levelOptions(sc)) expect(parseLevelStep(o.value)).not.toBeNull();
    }
  });
});

describe("restoreLevel — 学習言語を切り替えたときの級", () => {
  /**
   * 学習言語を選べるようにした日(2026-08-25、第4段)から、同じ人の
   * `level_goal` に `"TOCFL-2"` と `"A2"` の両方があり得る。
   * 載せ替えないと、設定の一覧に**無い値**が選ばれた状態になり、
   * 選択が空に見えて保存もできない。
   */
  it("段を引き継いで表記だけ載せ替える", () => {
    expect(restoreLevel(CEFR_SCALE, "TOCFL-2", 1)).toBe("A2");
    expect(restoreLevel(TOCFL_SCALE, "B1", 1)).toBe("TOCFL-3");
  });

  it("同じ目盛りならそのまま(触らない)", () => {
    for (const i of LEVEL_INDEXES) {
      const v = CEFR_SCALE.toStored(i);
      expect(restoreLevel(CEFR_SCALE, v, 1)).toBe(v);
      const t = TOCFL_SCALE.toStored(i);
      expect(restoreLevel(TOCFL_SCALE, t, 1)).toBe(t);
    }
  });

  it("**6段を往復しても壊れない**(切り替えを繰り返しても段が動かない)", () => {
    for (const i of LEVEL_INDEXES) {
      const start = TOCFL_SCALE.toStored(i);
      const there = restoreLevel(CEFR_SCALE, start, 1);
      const back = restoreLevel(TOCFL_SCALE, there, 1);
      expect(back, `段${i}`).toBe(start);
    }
  });

  it("読めない値は fallback(空の選択を作らない)", () => {
    for (const bad of [null, undefined, "", "  ", "級外", "unknown"]) {
      expect(restoreLevel(CEFR_SCALE, bad, 2), String(bad)).toBe("A2");
    }
  });

  it("**6段の外は fallback**(`toStored(7)` は一覧に無い値を作る)", () => {
    for (const out of ["TOCFL-7", "TOCFL-0", "9"]) {
      expect(restoreLevel(CEFR_SCALE, out, 1), out).toBe("A1");
    }
  });

  it("**返す値は必ず一覧の中に在る**(選択が空にならない)", () => {
    const inputs = [null, "", "TOCFL-2", "B1", "C2", "TOCFL-7", "級外", "unknown", 3];
    for (const scale of [TOCFL_SCALE, CEFR_SCALE]) {
      const values = levelOptions(scale).map((o) => o.value);
      for (const raw of inputs) {
        expect(values, `${scale.id}: ${raw}`).toContain(restoreLevel(scale, raw, 1));
      }
    }
  });
});

describe("outStored — 級外を保存する形", () => {
  it("**保存して読み返すと級外になる**", () => {
    // オーナー指示 2026-08-26「CEFR-J に無い語は級外にして」。
    // ここが往復しないと、級外の語が「分からない」と混ざる。
    for (const scale of [TOCFL_SCALE, CEFR_SCALE]) {
      expect(parseLevelStep(scale.outStored), scale.id).toBe(LEVEL_OUT);
    }
  });

  it("**級の形と混ざらない**", () => {
    for (const scale of [TOCFL_SCALE, CEFR_SCALE]) {
      for (const i of LEVEL_INDEXES) {
        expect(scale.outStored, scale.id).not.toBe(scale.toStored(i));
      }
    }
  });
});
