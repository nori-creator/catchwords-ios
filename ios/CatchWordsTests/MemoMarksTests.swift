import XCTest
@testable import CatchWords

/// 台湾メモ's phrases to remember (版25 §7, owner 2026-10-26): `**…**` from the server becomes a highlight and the marks
/// never show. Run on its own by .github/workflows/ios-check.yml.
final class MemoMarksTests: XCTestCase {
    func testPairedMarksBecomeRanges() {
        let r = MemoMarks.parse("水晶手鍊は**「開運アイテム」**として選ばれる。**左手**で着ける。")
        XCTAssertEqual(r.plain, "水晶手鍊は「開運アイテム」として選ばれる。左手で着ける。")
        XCTAssertEqual(r.ranges.map { (r.plain as NSString).substring(with: $0) }, ["「開運アイテム」", "左手"])
    }

    func testNoMarksIsTheTextAsItIs() {
        let r = MemoMarks.parse("台湾では夜市が多い。")
        XCTAssertEqual(r.plain, "台湾では夜市が多い。")
        XCTAssertTrue(r.ranges.isEmpty)
    }

    func testAnUnpairedMarkIsDroppedAndNothingIsHighlighted() {
        let r = MemoMarks.parse("**開運アイテム として選ばれる")
        XCTAssertEqual(r.plain, "開運アイテム として選ばれる")
        XCTAssertTrue(r.ranges.isEmpty)
    }

    func testAnEmptyPairHighlightsNothing() {
        let r = MemoMarks.parse("a****b")
        XCTAssertEqual(r.plain, "ab")
        XCTAssertTrue(r.ranges.isEmpty)
    }
}
