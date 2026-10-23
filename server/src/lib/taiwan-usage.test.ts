import { describe, it, expect } from "vitest";
import { taiwanUsageFrom, type TaiwanUsage } from "./taiwan-usage";

/**
 * この列には制約が付いている(`common`/`written`/`spoken`/`rare` のどれか)。
 * 自由文を入れていたせいで、辞書の蓄積が**一括まるごと**失敗していた。
 *
 * ここで守るのは2つ:
 *   1. 返すのは必ず制約に通る値か null。**地の文をそのまま返さない**
 *   2. 決められないときは埋めない。当てずっぽうは「知らない」より悪い
 */
const ALLOWED: ReadonlyArray<TaiwanUsage | null> = ["common", "written", "spoken", "rare", null];

describe("taiwanUsageFrom", () => {
  it("形の決まった欄(register_tag)から写す", () => {
    expect(taiwanUsageFrom({ registerTag: "口語" })).toBe("spoken");
    expect(taiwanUsageFrom({ registerTag: "書面" })).toBe("written");
  });

  it("「口語・書面」は文体で絞れないので頻度に落とす", () => {
    expect(taiwanUsageFrom({ registerTag: "口語・書面", frequencyLevel: 5 })).toBe("common");
    expect(taiwanUsageFrom({ registerTag: "口語・書面", frequencyLevel: 1 })).toBe("rare");
    // 頻度も中途半端なら埋めない
    expect(taiwanUsageFrom({ registerTag: "口語・書面", frequencyLevel: 3 })).toBeNull();
  });

  it("**文体は頻度より優先する**(語について多くを言っている)", () => {
    expect(taiwanUsageFrom({ registerTag: "書面", frequencyLevel: 5 })).toBe("written");
  });

  it("形の決まった欄が無ければ、紛れの無い地の文だけ読む", () => {
    expect(taiwanUsageFrom({ prose: "LINEのチャットでよく使う" })).toBe("spoken");
    expect(taiwanUsageFrom({ prose: "新聞やニュースで見かける" })).toBe("written");
  });

  it("地の文に両方出たら決めない", () => {
    expect(taiwanUsageFrom({ prose: "会話でも新聞でも使う" })).toBeNull();
  });

  it("頻度しか無いとき", () => {
    expect(taiwanUsageFrom({ frequencyLevel: 5 })).toBe("common");
    expect(taiwanUsageFrom({ frequencyLevel: 4 })).toBe("common");
    expect(taiwanUsageFrom({ frequencyLevel: 1 })).toBe("rare");
    expect(taiwanUsageFrom({ frequencyLevel: 2 })).toBeNull();
    expect(taiwanUsageFrom({ frequencyLevel: 3 })).toBeNull();
  });

  it("頻度が無く、地の文が頻度だけを言っているとき", () => {
    expect(taiwanUsageFrom({ prose: "台湾ではめったに使わない" })).toBe("rare");
    expect(taiwanUsageFrom({ prose: "台湾では日常的に見かける" })).toBe("common");
  });

  it("**手がかりが無ければ埋めない**", () => {
    expect(taiwanUsageFrom({})).toBeNull();
    expect(taiwanUsageFrom({ prose: "  " })).toBeNull();
    expect(taiwanUsageFrom({ registerTag: null, frequencyLevel: null, prose: null })).toBeNull();
  });

  it("実際に列へ入れていた文でも、制約に通る値しか返さない", () => {
    const real = [
      "スーパーや夜市でよく見かける。日常会話で頻繁に使う。",
      "友達とのLINEで使う、ややくだけた言い方。",
      "新聞やテレビのニュースで使われる硬い表現。",
      "",
      "特に決まった場面は無い",
    ];
    for (const prose of real) {
      expect(ALLOWED).toContain(taiwanUsageFrom({ prose }));
    }
  });

  it("壊れた数を渡しても落ちない", () => {
    expect(ALLOWED).toContain(taiwanUsageFrom({ frequencyLevel: Number.NaN }));
    expect(ALLOWED).toContain(taiwanUsageFrom({ frequencyLevel: Infinity }));
  });
});
