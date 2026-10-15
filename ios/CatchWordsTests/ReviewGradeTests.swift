import XCTest
@testable import CatchWords

/// Review answers the server could not save (owner 2026-10-15: the card 內褲 was deleted mid-round and its grade came
/// back as a 500). The server now answers `gone` for a review row that no longer exists, 503 with a reason when its
/// database fails and 400 with a message for a bad request. Run on its own by .github/workflows/ios-check.yml.
@MainActor
final class ReviewGradeTests: XCTestCase {
    private func card(_ id: String) -> ReviewCard {
        let sticker = Sticker(id: "s-\(id)", wordId: "w-\(id)", objectImageUrl: "u/\(id)-object.jpg", cutoutImageUrl: nil,
                              selfieImageUrl: nil, caption: nil, locationName: nil, takenAt: Date(), captureType: "photo",
                              word: nil)
        return ReviewCard(review: ReviewState(id: "r-\(id)", stickerId: sticker.id, ease: 2.5, intervalDays: 1, repetitions: 1),
                          sticker: sticker)
    }

    private func store(_ ids: [String], at index: Int = 0) -> ReviewStore {
        let s = ReviewStore()
        s.queue = ids.map(card)
        s.index = index
        return s
    }

    // MARK: - The server's answer

    func testGoneIsRead() throws {
        let gone = try JSONDecoder().decode(ReviewStore.Graded.self, from: Data(#"{"gone":true,"score":null}"#.utf8))
        XCTAssertEqual(gone.gone, true)
        XCTAssertNil(gone.score)
        let saved = try JSONDecoder().decode(ReviewStore.Graded.self, from: Data(#"{"score":5,"interval_days":3}"#.utf8))
        XCTAssertNil(saved.gone)
        XCTAssertEqual(saved.score, 5)
        XCTAssertEqual(saved.intervalDays, 3)
    }

    /// Asked again only when another try can work: no network, a dropped connection, too slow, a server that failed
    /// (503 with its reason included). A refusal (400 with a message) would be refused again.
    func testOnlyNetworkTimeoutsAndServerFailuresAreAskedAgain() {
        XCTAssertTrue(ReviewStore.isWorthRetrying(APIError.offline))
        XCTAssertTrue(ReviewStore.isWorthRetrying(APIError.connectionLost(-1005)))
        XCTAssertTrue(ReviewStore.isWorthRetrying(APIError.timeout))
        XCTAssertTrue(ReviewStore.isWorthRetrying(APIError.server(500, "")))
        XCTAssertTrue(ReviewStore.isWorthRetrying(APIError.server(503, "データベースに接続できませんでした")))
        XCTAssertTrue(ReviewStore.isWorthRetrying(CancellationError()))
        XCTAssertFalse(ReviewStore.isWorthRetrying(APIError.server(400, "review_id が正しくありません")))
        XCTAssertFalse(ReviewStore.isWorthRetrying(APIError.server(404, "")))
        XCTAssertFalse(ReviewStore.isWorthRetrying(APIError.unauthorized))
        XCTAssertFalse(ReviewStore.isWorthRetrying(APIError.decoding))
    }

    // MARK: - Cards leaving the round

    /// A gone card (or a deleted word's) leaves what is left of the round and the missed list; the card on screen and
    /// the cards already answered stay where they are.
    func testLaterCopiesAndMissedGoTheScreenStays() {
        let s = store(["a", "b", "c", "b", "d"], at: 1)
        s.missed = [card("b"), card("a")]
        s.removeUpcoming { $0.id == "r-b" }
        XCTAssertEqual(s.queue.map(\.id), ["r-a", "r-b", "r-c", "r-d"])
        XCTAssertEqual(s.index, 1)
        XCTAssertEqual(s.current?.id, "r-b")
        XCTAssertEqual(s.missed.map(\.id), ["r-a"])
        // At the end of the round: nothing after it, nothing to take.
        let end = store(["a"], at: 0)
        end.removeUpcoming { _ in true }
        XCTAssertEqual(end.queue.map(\.id), ["r-a"])
    }

    func testDeletedWordsLeaveTheRound() {
        let dex = DexStore()
        let s = store(["a", "b", "c"], at: 0)
        // A dex being read again (empty) deletes nothing.
        s.dropDeleted(dex: dex)
        XCTAssertEqual(s.queue.count, 3)
        dex.stickers = [card("a").sticker, card("c").sticker]
        dex.hasLoaded = true
        s.dropDeleted(dex: dex)
        XCTAssertEqual(s.queue.map(\.id), ["r-a", "r-c"])
    }

    // MARK: - What the screen says

    /// One failure per card: a later card saved never takes an earlier card's failure off the screen.
    func testALaterSuccessKeepsAnEarlierFailure() {
        let s = store(["a", "b", "c"], at: 0)
        s.noteGradeFailure("a failed", card: "r-a")
        s.advance()
        XCTAssertEqual(s.gradeError, "a failed")
        // b saved: a's failure is still there (a comes back at the end).
        s.noteGradeFailure(nil, card: "r-b")
        XCTAssertEqual(s.gradeError, "a failed")
        // The card on screen's own failure first.
        s.noteGradeFailure("b failed", card: "r-b")
        XCTAssertEqual(s.gradeError, "b failed")
        s.noteGradeFailure(nil, card: "r-b")
        XCTAssertEqual(s.gradeError, "a failed")
        // a answered again and saved: nothing left to say.
        s.noteGradeFailure(nil, card: "r-a")
        XCTAssertNil(s.gradeError)
    }

    /// A refusal is told on the card it came with and does not follow the learner to the next one.
    func testARefusalGoesWhenTheLearnerMovesOn() {
        let s = store(["a", "b"], at: 0)
        s.noteGradeFailure("refused", card: "r-a", comesBack: false)
        XCTAssertEqual(s.gradeError, "refused")
        s.advance()
        XCTAssertNil(s.gradeError)
        XCTAssertTrue(s.gradeFailures.isEmpty)
    }
}
