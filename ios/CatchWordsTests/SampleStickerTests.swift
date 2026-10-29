import XCTest
@testable import CatchWords

/// The bundled sample word 珍珠奶茶 (`SampleSticker`): readable in every display language, with everything its page
/// shows, and graded on the phone like the server would.
final class SampleStickerTests: XCTestCase {
    @MainActor
    func testEveryDisplayLanguageHasAWholeCard() throws {
        for code in DisplayLanguages.all.map(\.code) {
            let s = try XCTUnwrap(SampleSticker.make(reader: code, takenAt: Date()), "no sample for \(code)")
            XCTAssertTrue(s.isSample)
            XCTAssertEqual(s.wordId, "", "\(code): the sample must never look like a saved word")
            let w = try XCTUnwrap(s.word, "\(code): no word")
            XCTAssertEqual(w.headword, "珍珠奶茶")
            XCTAssertFalse(w.meaningJa.isEmpty, "\(code): the meaning was dropped")
            XCTAssertFalse(LanguageRules.looksWrong(w.meaningJa, reader: code, hanOnlyOk: true), "\(code): meaning 「\(w.meaningJa)」")
            XCTAssertEqual(w.extras?.explainLang, code)
            let chunks = w.extras?.usageChunks ?? []
            XCTAssertEqual(chunks.count, 2, "\(code): chunks")
            for c in chunks {
                XCTAssertFalse(c.ja.isEmpty, "\(code): a chunk without its translation")
                XCTAssertFalse(LanguageRules.looksWrong(c.ja, reader: code), "\(code): chunk 「\(c.ja)」")
                XCTAssertNotNil(c.note, "\(code): a chunk without its note")
                XCTAssertTrue(c.parts.contains { $0.text == "珍珠奶茶" }, "\(code): C1, the headword in every chunk")
                XCTAssertTrue(c.parts.contains { ChunkRules.isSwappable($0, headword: "珍珠奶茶", target: "zh-TW") },
                              "\(code): the swappable part lost its alternatives")
            }
            let examples = ExampleItem.all(sentence: w.exampleSentence, translation: w.exampleTranslation, extras: w.extras, target: "zh-TW")
            XCTAssertEqual(examples.count, 2, "\(code): examples")
            for ex in examples {
                // A reader of the learning language itself gets no translation: the same sentence is never repeated
                // under it (`LanguageRules.looksWrong` with its source).
                if code == "zh-TW" { XCTAssertNil(ex.translation, "zh-TW: 「\(ex.sentence)」 repeated as its own translation"); continue }
                XCTAssertFalse((ex.translation ?? "").isEmpty, "\(code): 「\(ex.sentence)」 without its translation")
                XCTAssertFalse(LanguageRules.looksWrong(ex.translation, reader: code, source: ex.sentence),
                               "\(code): translation 「\(ex.translation ?? "")」")
            }
            XCTAssertEqual(w.extras?.measureWords?.first?.word, "杯")
            XCTAssertEqual(w.extras?.allRelated.count, 3, "\(code): related words")
            XCTAssertTrue((w.extras?.taiwanNote ?? "").contains("**"), "\(code): the Taiwan note lost its marks")
        }
    }

    @MainActor
    func testReadingsSpellTheSentences() throws {
        SampleSticker.seedReadings()
        let s = try XCTUnwrap(SampleSticker.make(reader: "ja", takenAt: Date()))
        let w = try XCTUnwrap(s.word)
        for ex in ExampleItem.all(sentence: w.exampleSentence, translation: nil, extras: w.extras, target: "zh-TW") {
            let units = try XCTUnwrap(SentenceReadings.shared.cached(ex.sentence), "no readings for 「\(ex.sentence)」")
            XCTAssertEqual(units.map(\.char).joined(), ex.sentence)
            // Every character but punctuation is read.
            for u in units where !"，。".contains(u.char) { XCTAssertNotNil(u.zhuyin, "「\(ex.sentence)」: \(u.char) unread") }
        }
    }

    @MainActor
    func testGradingMovesTheReviewOn() {
        let uid = "test-" + UUID().uuidString
        defer { SampleSticker.removeRecords(userId: uid) }
        XCTAssertFalse(SampleSticker.isEnabled(userId: uid))
        SampleSticker.markAdded(userId: uid)
        XCTAssertTrue(SampleSticker.isEnabled(userId: uid))
        // It comes after its story of three on-time reviews (1, 2 and 5 days after it was learned): 8 days to the next,
        // which falls on the day it is added (due 10 minutes after, so the first review finds it).
        let added = SampleSticker.addedAt(userId: uid)
        let fresh = SampleSticker.reviewState(userId: uid)
        XCTAssertNil(fresh.id, "the sample has no row on the server")
        XCTAssertEqual(fresh.repetitions, 3)
        XCTAssertEqual(fresh.intervalDays, 8)
        XCTAssertEqual(fresh.lastReviewedAt?.timeIntervalSince(added) ?? 0, -8 * 86_400, accuracy: 1)
        XCTAssertEqual(fresh.dueAt?.timeIntervalSince(added) ?? 0, 600, accuracy: 1)
        let story = SampleSticker.history(userId: uid)
        XCTAssertEqual(story.count, 3)
        XCTAssertEqual(story.map { $0.intervalDaysAfter ?? 0 }, [1, 3, 8], "each review lengthens the next wait (a gentler slope)")
        XCTAssertTrue(story.allSatisfy { $0.reviewedAt < added })
        XCTAssertEqual(SampleSticker.learnedAt(userId: uid).timeIntervalSince(added), -13 * 86_400, accuracy: 1)
        let now = added.addingTimeInterval(600)
        let first = SampleSticker.grade(userId: uid, correct: true, now: now)
        XCTAssertEqual(first.repetitions, 4)
        XCTAssertEqual(first.intervalDays, 22)
        XCTAssertEqual(first.dueAt?.timeIntervalSince(now) ?? 0, 22 * 86_400, accuracy: 1)
        XCTAssertEqual(SampleSticker.history(userId: uid).count, 4, "the learner's own answer follows the story")
        let lapse = SampleSticker.grade(userId: uid, correct: false, now: now.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(lapse.repetitions, 0)
        XCTAssertEqual(lapse.intervalDays, 1)
        SampleSticker.markDeleted(userId: uid)
        XCTAssertFalse(SampleSticker.isEnabled(userId: uid))
    }
}
