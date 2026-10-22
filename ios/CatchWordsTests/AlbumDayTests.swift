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

    // MARK: Where the day's photos go (owner 2026-10-22: 「その日の欄の1枚目は真ん中に」「決してほかの画像には被らない
    // ように上から順に」「1枚目とそれ以降の写真は同等に扱って」)

    private func items(_ n: Int) -> [CollageItem] {
        (0..<n).map { CollageItem(id: "p\($0)", ratio: [1.0, 0.8, 1.15, 0.7][$0 % 4], extra: 0.1) }
    }

    private func boxes(_ places: [AlbumPlacement], _ items: [CollageItem]) -> [AlbumBox] {
        zip(places, items).map { AlbumLayout.boxOf($0, ratio: $1.ratio, extra: $1.extra) }
    }

    private func assertNoOverlap(_ b: [AlbumBox], file: StaticString = #filePath, line: UInt = #line) {
        for i in b.indices { for j in b.indices where j < i {
            XCTAssertFalse(AlbumLayout.boxesOverlap(b[i], b[j], pad: 0), "photos \(j) and \(i) overlap", file: file, line: line)
        } }
    }

    func testOnePhotoStandsInTheMiddle() {
        let p = AlbumLayout.packDay(items(1))
        XCTAssertEqual(p[0].x, 0.5, accuracy: 0.0001, "never in a corner")
        let box = AlbumLayout.boxOf(p[0], ratio: 1, extra: 0.1)
        XCTAssertEqual(box.y, (AlbumLayout.MIN_BOARD_H - AlbumLayout.GAP_Y) / 2, accuracy: 0.01, "in the middle of the day")
    }

    func testEveryPhotoHasTheSameSize() {
        let p = AlbumLayout.packDay(items(5))
        XCTAssertEqual(Set(p.map(\.scale)).count, 1, "the first photo is not bigger than the others")
    }

    func testPhotosGoInRowsFromTheTopAndNeverOverlap() {
        let it = items(5)
        let p = AlbumLayout.packDay(it)
        XCTAssertLessThan(p[0].x, 0.5)
        XCTAssertGreaterThan(p[1].x, 0.5)
        XCTAssertLessThan(p[0].y, p[2].y, "the next row is under the first")
        XCTAssertEqual(p[4].x, 0.5, accuracy: 0.0001, "the last photo alone in its row is in the middle")
        assertNoOverlap(boxes(p, it))
    }

    func testANewPhotoTakesTheFirstFreePlaceFromTheTopBesideOnesPlacedByHand() {
        // One photo placed by hand at the top left: a new photo goes beside it at the top, not under everything.
        let fixed = [AlbumLayout.boxOf(AlbumPlacement(x: 0.24, y: 0.25, scale: 0.44 / AlbumLayout.BASE_WIDTH, rot: 0),
                                       ratio: 1, extra: 0.1)]
        let it = items(3)
        let p = AlbumLayout.packDay(it, fixed: fixed)
        XCTAssertGreaterThan(p[0].x, 0.5, "beside the photo placed by hand")
        XCTAssertLessThan(AlbumLayout.boxOf(p[0], ratio: it[0].ratio, extra: it[0].extra).y, 0.5, "at the top")
        assertNoOverlap(fixed + boxes(p, it))
    }
}
