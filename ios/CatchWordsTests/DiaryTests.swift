import XCTest
@testable import CatchWords

/// The diary (2026-10-24): the pages' keys, and the server's rows as the page reads them. Run on its own by ios-check.yml.
@MainActor
final class DiaryTests: XCTestCase {
    // MARK: Keys

    func testAPageIsKeyedByThePhonesCalendarDay() {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 24; c.hour = 12
        let day = Calendar.current.date(from: c)!
        XCTAssertEqual(DiaryStore.key(day), "2026-10-24")
        XCTAssertEqual(DiaryStore.monthKey(day), "2026-10")
    }

    // MARK: The server's rows

    func testAMonthRowReadsWithTheServersColumns() throws {
        let json = #"{"date":"2026-10-24","text":"我吃鐵板麵","correction":"我吃了鐵板麵","feedback":"了を付ける","native_phrases":[{"zh":"好飽","ja":"おなかいっぱい","note":"食後に"},{"zh":"","ja":"x","note":""}],"used_sticker_ids":["s1"]}"#
        let e = try JSONDecoder().decode(DiaryEntry.self, from: Data(json.utf8))
        XCTAssertEqual(e.text, "我吃鐵板麵")
        XCTAssertEqual(e.correction, "我吃了鐵板麵")
        XCTAssertEqual(e.nativePhrases.map(\.zh), ["好飽"], "a phrase without its text is dropped")
        XCTAssertEqual(e.usedStickerIds, ["s1"])
    }

    func testABlankCorrectionIsNone() throws {
        let json = #"{"date":"2026-10-24","text":"a","correction":"  ","feedback":null}"#
        let e = try JSONDecoder().decode(DiaryEntry.self, from: Data(json.utf8))
        XCTAssertNil(e.correction)
        XCTAssertNil(e.feedback)
        XCTAssertEqual(e.nativePhrases, [])
    }
}
