import XCTest
@testable import CatchWords

/// 「量詞」の欄で量を二重にしない（owner 2026-11-23: 一杯咖啡 に 一杯 が付いて量が二重になった）. Same rules as the server's
/// `typed-head-noun.ts`.
final class MeasureCountTests: XCTestCase {
    func testOldPhraseHeadwordGivesTheThingsName() {
        XCTAssertEqual(MeasureCount.noun(of: "一杯咖啡").noun, "咖啡")
        XCTAssertEqual(MeasureCount.noun(of: "一杯咖啡").dropped, 2)
        XCTAssertEqual(MeasureCount.noun(of: "這杯咖啡").noun, "咖啡")
        XCTAssertEqual(MeasureCount.noun(of: "兩顆蘋果").noun, "蘋果")
        XCTAssertEqual(MeasureCount.noun(of: "一杯的咖啡").dropped, 3)
        // 一杯 + 咖啡 = 一杯咖啡 (never 一杯 一杯咖啡)
        XCTAssertEqual("一杯" + MeasureCount.noun(of: "一杯咖啡").noun, "一杯咖啡")
    }

    func testWordsAreNotSplit() {
        for w in ["咖啡", "珍珠奶茶", "雨傘", "滾筒黏毛器", "三明治", "五花肉", "九層塔", "四季豆", "千層麵", "一杯", "一本書",
                  "杯子", "這咖啡", "一般"] {
            XCTAssertEqual(MeasureCount.noun(of: w).noun, w, w)
            XCTAssertEqual(MeasureCount.noun(of: w).dropped, 0, w)
        }
    }

    func testReadingsLoseTheSameSyllables() {
        XCTAssertEqual(MeasureCount.dropSyllables("ㄧ ㄅㄟ ㄎㄚ ㄈㄟ", 2), "ㄎㄚ ㄈㄟ")
        XCTAssertEqual(MeasureCount.dropSyllables("yī bēi kāfēi", 2), "kāfēi")
        XCTAssertNil(MeasureCount.dropSyllables("yībēi", 2))
        XCTAssertEqual(MeasureCount.dropSyllables("kāfēi", 0), "kāfēi")
    }
}
