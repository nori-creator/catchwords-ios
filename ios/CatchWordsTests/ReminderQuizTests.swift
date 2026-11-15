import XCTest
@testable import CatchWords

/// The picture quiz in review and place reminders (`ReminderQuiz`, owner 2026-11-15): which word it asks about, how
/// long the round takes, and the place line without the street. Run on its own by .github/workflows/ios-check.yml.
@MainActor
final class ReminderQuizTests: XCTestCase {
    private func word(_ head: String) throws -> Word {
        try JSONDecoder().decode(Word.self, from: Data(#"{"id":"w-\#(head)","headword":"\#(head)"}"#.utf8))
    }

    private func sticker(_ id: String, _ head: String, picture: Bool = true, place: String? = nil) throws -> Sticker {
        Sticker(id: id, wordId: "w-\(head)", objectImageUrl: picture ? "u/\(id).jpg" : nil,
                cutoutImageUrl: picture ? "u/\(id)-cutout.png" : nil, selfieImageUrl: nil, caption: nil,
                locationName: place, takenAt: Date(timeIntervalSince1970: 1_790_000_000), captureType: "photo",
                word: try word(head))
    }

    func test_picksTheWordDueFirstByThen() throws {
        let now = Date()
        let a = try sticker("a", "雨傘"), b = try sticker("b", "捷運"), c = try sticker("c", "水餃")
        let due = ["a": now.addingTimeInterval(600), "b": now.addingTimeInterval(-3600), "c": now.addingTimeInterval(86_400)]
        let pick = ReminderQuiz.pick(stickers: [a, b, c], due: due, at: now.addingTimeInterval(3600))
        XCTAssertEqual(pick?.sticker.id, "b", "due an hour ago: the first")
        XCTAssertEqual(pick?.others, 1, "a is due by then too; c is not")
    }

    func test_skipsAWordWithoutAPictureButCountsIt() throws {
        let now = Date()
        let bare = try sticker("a", "雨傘", picture: false), shown = try sticker("b", "捷運")
        let due = ["a": now.addingTimeInterval(-600), "b": now.addingTimeInterval(-60)]
        let pick = ReminderQuiz.pick(stickers: [bare, shown], due: due, at: now)
        XCTAssertEqual(pick?.sticker.id, "b", "the quiz needs a picture")
        XCTAssertEqual(pick?.others, 1)
    }

    func test_nothingDueMeansNoQuiz() throws {
        let now = Date()
        let a = try sticker("a", "雨傘")
        XCTAssertNil(ReminderQuiz.pick(stickers: [a], due: ["a": now.addingTimeInterval(86_400)], at: now))
        XCTAssertNil(ReminderQuiz.pick(stickers: [a], due: [:], at: now))
    }

    func test_neverTheSample() throws {
        let now = Date()
        let sample = try sticker(SampleSticker.prefix + "bubbletea", "珍珠奶茶")
        XCTAssertNil(ReminderQuiz.pick(stickers: [sample], due: [sample.id: now.addingTimeInterval(-60)], at: now))
    }

    func test_minutes() {
        XCTAssertEqual(ReminderQuiz.minutes(cards: 1), 1)
        XCTAssertEqual(ReminderQuiz.minutes(cards: 6), 1)
        XCTAssertEqual(ReminderQuiz.minutes(cards: 7), 2)
        XCTAssertEqual(ReminderQuiz.minutes(cards: 30), 5)
    }

    func test_areaDropsTheStreet() {
        XCTAssertEqual(ReminderQuiz.area("台北市 大安區 和平東路一段162號", custom: false), "大安區")
        XCTAssertEqual(ReminderQuiz.area("Taipei, Da'an District, 162 Heping East Road", custom: false), "Da'an District")
        XCTAssertEqual(ReminderQuiz.area("台北市", custom: false), "台北市")
        XCTAssertEqual(ReminderQuiz.area("台北市 和平東路一段162號", custom: false), "台北市", "no district: the city")
        XCTAssertEqual(ReminderQuiz.area("162 Heping East Road", custom: false), nil, "a street first: nothing")
        XCTAssertEqual(ReminderQuiz.area("CAMA 咖啡 公館店", custom: true), "CAMA 咖啡 公館店", "the learner's own name")
        XCTAssertNil(ReminderQuiz.area("  ", custom: false))
    }
}
