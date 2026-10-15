import XCTest
@testable import CatchWords

/// A headword changed on the word page (owner 2026-10-15: 貓眼 corrected to 門, the review's answer still said 貓眼):
/// the round's cached choices for that sticker are dropped and the reloaded sticker replaces the old one in the queue
/// and the missed list. Run on its own by ios-check.yml.
@MainActor
final class ReviewHeadwordTests: XCTestCase {
    private func word(_ head: String, _ zhuyin: String) -> Word {
        let obj: [String: Any] = ["id": "w-\(head)", "headword": head, "language": "zh-TW", "reading_zhuyin": zhuyin,
                                  "meaning_ja": head, "part_of_speech": "N"]
        return try! JSONDecoder().decode(Word.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    private func sticker(_ id: String, _ w: Word?) -> Sticker {
        Sticker(id: id, wordId: w?.id ?? "w", objectImageUrl: nil, cutoutImageUrl: nil, selfieImageUrl: nil, caption: nil,
                locationName: nil, takenAt: Date(), captureType: "photo", word: w)
    }

    private func card(_ s: Sticker) -> ReviewCard {
        ReviewCard(review: ReviewState(id: "r-\(s.id)", stickerId: s.id, ease: 2.5, intervalDays: 1, repetitions: 1), sticker: s)
    }

    func testTheNewHeadwordReplacesTheOldInTheRoundAndItsChoicesAreRebuilt() {
        let old = sticker("s1", word("貓眼", "ㄇㄠ ㄧㄢˇ"))
        let other = sticker("s2", word("杯子", "ㄅㄟ ㄗ˙"))
        NativeAPI.targetLanguage = "zh-TW"
        let store = ReviewStore()
        store.queue = [card(old), card(other)]
        store.missed = [card(old)]
        let dex = DexStore()
        let before = store.choices(for: store.queue[0], dex: dex)
        XCTAssertTrue(before.contains { $0.headword == "貓眼" })
        XCTAssertTrue(store.hasCachedChoices(for: "s1"))
        _ = store.choices(for: store.queue[1], dex: dex)

        let fresh = sticker("s1", word("門", "ㄇㄣˊ"))
        store.replaceSticker(fresh)

        XCTAssertFalse(store.hasCachedChoices(for: "s1"), "the old choices are dropped")
        XCTAssertTrue(store.hasCachedChoices(for: "s2"), "another card's choices stay")
        XCTAssertEqual(store.queue[0].sticker.word?.headword, "門")
        XCTAssertEqual(store.queue[0].id, "r-s1", "the review row is the same")
        XCTAssertEqual(store.missed[0].sticker.word?.headword, "門")
        XCTAssertEqual(store.queue[1].sticker.word?.headword, "杯子")
        let after = store.choices(for: store.queue[0], dex: dex)
        XCTAssertTrue(after.contains { $0.headword == "門" })
        XCTAssertFalse(after.contains { $0.headword == "貓眼" })
    }
}
