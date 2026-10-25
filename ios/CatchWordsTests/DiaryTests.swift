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

    // MARK: Correcting (2026-10-25)

    func testATextIsCutIntoSentencesAndTheLastUnfinishedOneWaits() {
        let parts = DiaryStore.sentences(in: "今天很熱。我說：「好熱！」\n晚上吃麵")
        XCTAssertEqual(parts.map { $0.text }, ["今天很熱。", "我說：「好熱！」", "晚上吃麵"])
        XCTAssertEqual(parts.map { $0.finished }, [true, true, false])
    }

    func testANewLineFinishesASentenceWithoutPunctuation() {
        let parts = DiaryStore.sentences(in: "早安\n\n我去公園?")
        XCTAssertEqual(parts.map { $0.text }, ["早安", "我去公園?"])
        XCTAssertEqual(parts.map { $0.finished }, [true, true])
    }

    func testASentenceCheckReadsTheServersAnswer() throws {
        let json = #"{"ok":false,"issues":[{"wrong":"個","fix":"顆","kind":"measure","explain":"x"},{"wrong":"","fix":"a","kind":"word","explain":""}],"natural":"我買了三顆芒果。","natural_note":"y"}"#
        let c = try JSONDecoder().decode(SentenceCheck.self, from: Data(json.utf8))
        XCTAssertEqual(c.issues.map(\.wrong), ["個"], "an issue without its wrong part is dropped")
        XCTAssertFalse(c.ok)
        XCTAssertEqual(c.naturalNote, "y")
        XCTAssertTrue(c.hasNote)
    }

    func testAFineSentenceHasNoNote() throws {
        let c = try JSONDecoder().decode(SentenceCheck.self, from: Data(#"{"ok":true,"issues":[],"natural":"","natural_note":""}"#.utf8))
        XCTAssertTrue(c.ok)
        XCTAssertFalse(c.hasNote)
    }

    func testACorrectionReadsItsListsAndTheStoredColumns() throws {
        let json = #"{"correction":"我買了三顆芒果。","feedback_ja":"よく書けました","mistakes":[{"wrong":"三個芒果","fix":"三顆芒果","explain":"量詞"}],"tendencies":["量詞",""],"native_phrases":[{"zh":"好好吃喔","ja":"おいしい","note":""}]}"#
        let c = try JSONDecoder().decode(DiaryCorrection.self, from: Data(json.utf8))
        XCTAssertEqual(c.natural, "我買了三顆芒果。")
        XCTAssertEqual(c.feedback, "よく書けました")
        XCTAssertEqual(c.mistakes.map(\.fix), ["三顆芒果"])
        XCTAssertEqual(c.tendencies, ["量詞"])
        XCTAssertEqual(c.phrases.map(\.zh), ["好好吃喔"])
    }

    // MARK: The page curl's geometry (`PageCurlGeometry`, the book on a wide screen)

    private let spread = CGSize(width: 1000, height: 800)

    func testAPageNotMovedIsNotLifted() {
        let g = PageCurlGeometry.make(progress: 0, liftY: 600, grabY: 600, size: spread)
        XCTAssertFalse(g.lifted)
    }

    func testALandedPageLiesFlatAlongTheSpine() {
        let g = PageCurlGeometry.make(progress: 1, liftY: 500, grabY: 700, size: spread)
        XCTAssertTrue(g.lifted)
        XCTAssertEqual(g.fold.x, 500, accuracy: 0.01, "the fold is at the spine")
        XCTAssertEqual(g.dir.dx, 1, accuracy: 0.0001, "and upright")
        XCTAssertEqual(g.dir.dy, 0, accuracy: 0.0001)
        XCTAssertLessThan(g.radius, 0.01, "no roll left: the leaf lies flat on the other page")
    }

    func testAPageHeldLevelFoldsUpright() {
        let g = PageCurlGeometry.make(progress: 0.3, liftY: 600, grabY: 600, size: spread)
        XCTAssertEqual(g.dir.dy, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(g.fold.x, 500)
        XCTAssertLessThan(g.fold.x, 1000)
        XCTAssertGreaterThan(g.radius, 0)
    }

    func testAFingerHeldHigherLiftsTheCornerAtASlant() {
        let g = PageCurlGeometry.make(progress: 0.1, liftY: 650, grabY: 780, size: spread)
        XCTAssertGreaterThan(abs(g.dir.dy), 0.05, "a corner, not the whole edge")
        XCTAssertEqual(g.dir.dx * g.dir.dx + g.dir.dy * g.dir.dy, 1, accuracy: 0.0001)
    }

    func testTheFoldNeverCrossesTheSpine() {
        for p in stride(from: 0.05, through: 1.0, by: 0.05) {
            let g = PageCurlGeometry.make(progress: CGFloat(p), liftY: 0, grabY: 800, size: spread)
            XCTAssertGreaterThanOrEqual(g.fold.x, 500, "progress \(p)")
        }
    }

    func testTheRollNeverOutgrowsTheDistanceTravelled() {
        let g = PageCurlGeometry.make(progress: 0.01, liftY: 600, grabY: 600, size: spread)
        // 1 % of the way: the edge moved 10 pt, so the roll is at most 10 / π.
        XCTAssertLessThanOrEqual(g.radius, 10 / .pi + 0.001)
    }
}
