import XCTest
@testable import CatchWords

/// The home album's days count words, not photos (owner 2026-10-16: the glasses shot twice in a row stood twice on the
/// day with 「2語」 — on the server one word met twice: one sticker and two re-encounters). Run on its own by ios-check.yml.
@MainActor
final class AlbumDayTests: XCTestCase {
    private func word(_ head: String) throws -> Word {
        try JSONDecoder().decode(Word.self, from: Data(#"{"id":"w-\#(head)","headword":"\#(head)"}"#.utf8))
    }

    private func photo(_ id: String, _ head: String, at: Date, cutout: Bool) throws -> Sticker {
        Sticker(id: id, wordId: "w-\(head)", objectImageUrl: "u/\(id).jpg", cutoutImageUrl: cutout ? "u/\(id)-cutout.png" : nil,
                selfieImageUrl: nil, caption: nil, locationName: nil, takenAt: at, captureType: "photo", word: try word(head))
    }

    func testAWordMetTwiceOnADayStandsOnceWithItsLatestCutOut() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = today.addingTimeInterval(-86_400)
        // The word was caught yesterday; met again twice today (the album's re-encounter pages), and a cup today.
        let caught = try photo("s1", "眼鏡", at: yesterday.addingTimeInterval(3600), cutout: true)
        let again1 = try photo(DexStore.encounterAlbumPrefix + "e1", "眼鏡", at: today.addingTimeInterval(3600), cutout: true)
        let again2 = try photo(DexStore.encounterAlbumPrefix + "e2", "眼鏡", at: today.addingTimeInterval(3700), cutout: true)
        let cup = try photo("s2", "杯子", at: today.addingTimeInterval(3800), cutout: false)
        let days = AlbumDay.days(from: [caught, again1, again2, cup], today: today)
        XCTAssertEqual(days.map(\.day), [today, yesterday])
        XCTAssertEqual(days[0].items.count, 2, "today: 眼鏡 once and 杯子 — 「2語」, not 3")
        XCTAssertEqual(days[0].items.map(\.id), [again2.id, cup.id], "the latest of the two")
        XCTAssertEqual(days[1].items.map(\.id), [caught.id])
    }

    func testACutOutIsShownBeforeALaterPhotoOfTheSameWord() throws {
        let today = Calendar.current.startOfDay(for: Date())
        let cut = try photo("a", "眼鏡", at: today.addingTimeInterval(100), cutout: true)
        let later = try photo("b", "眼鏡", at: today.addingTimeInterval(200), cutout: false)
        XCTAssertEqual(AlbumDay.onePerWord([cut, later], language: "zh-TW").map(\.id), ["a"])
        // Different words on one day all stay.
        let other = try photo("c", "水筒", at: today.addingTimeInterval(300), cutout: false)
        XCTAssertEqual(AlbumDay.onePerWord([cut, other, later], language: "zh-TW").map(\.id), ["a", "c"])
    }
}
