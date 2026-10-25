import XCTest
@testable import CatchWords

/// The praise after a catch is rare, comes first on the 3rd word, and the review is asked on the word right after a
/// praise (owner 2026-10-25, `PraiseSchedule`). Run on its own by ios-check.yml.
final class PraiseScheduleTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testFirstPraiseOnTheThirdWordThenTheReviewOnTheNext() {
        var s = PraiseSchedule()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(s.noteCatch(totalWords: 1, now: t0, roll: 0), .none)
        XCTAssertEqual(s.noteCatch(totalWords: 2, now: t0, roll: 0), .none)
        XCTAssertEqual(s.noteCatch(totalWords: 3, now: t0, roll: 0.99), .praise)
        s.notePraised(kind: "totalWords", now: t0)
        XCTAssertEqual(s.noteCatch(totalWords: 4, now: t0.addingTimeInterval(60), roll: 0), .askReview)
        XCTAssertNotNil(s.lastReviewAskAt)
    }

    func testLaterPraisesNeedWordsDaysAndLuck() {
        var s = PraiseSchedule()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = s.noteCatch(totalWords: 3, now: t0)
        s.notePraised(kind: "totalWords", now: t0)
        _ = s.noteCatch(totalWords: 4, now: t0)  // the review ask
        // Plenty of words but too soon: never.
        for n in 5...20 { XCTAssertEqual(s.noteCatch(totalWords: n, now: t0.addingTimeInterval(day), roll: 0), .none) }
        // Late enough and enough words: only when the roll falls under the chance.
        XCTAssertEqual(s.noteCatch(totalWords: 21, now: t0.addingTimeInterval(4 * day), roll: 0.9), .none)
        XCTAssertEqual(s.noteCatch(totalWords: 22, now: t0.addingTimeInterval(4 * day), roll: 0.1), .praise)
    }

    func testTheReviewIsNotAskedAgainWithinItsPeriod() {
        var s = PraiseSchedule()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        s.lastReviewAskAt = t0
        s.notePraised(kind: "wordsTop", now: t0.addingTimeInterval(30 * day))
        XCTAssertFalse(s.reviewDue)
        s.notePraised(kind: "daysTop", now: t0.addingTimeInterval(130 * day))
        XCTAssertTrue(s.reviewDue)
        XCTAssertEqual(s.recentKinds, ["wordsTop", "daysTop"])
    }

    func testComparisonsShowOnlyWhenTheyFlatter() {
        let good = MyStanding(words: .init(rank: 2, total: 40, topPercent: 5, count: 80),
                              activeDays: .init(rank: 30, total: 40, topPercent: 75, count: 3),
                              category: nil, firstCatcher: true)
        let kinds = PraiseMoment.options(standing: good, headword: "芒果", totalWords: 80, start: nil).map(\.kind)  // l10n-ignore (target word)
        XCTAssertEqual(kinds, [.firstCatcher, .wordsTop, .totalWords])
        // Too few people to compare with: only the learner's own count.
        let few = MyStanding(words: .init(rank: 1, total: 2, topPercent: 50, count: 3), activeDays: nil, category: nil, firstCatcher: true)
        XCTAssertEqual(PraiseMoment.options(standing: few, headword: "芒果", totalWords: 3, start: nil).map(\.kind), [.totalWords])  // l10n-ignore (target word)
    }

    func testTheBiggerSoundingFigureIsShown() {
        func r(_ rank: Int, _ top: Int) -> MyStanding.Rank { .init(rank: rank, total: 100, topPercent: top, count: 1) }
        XCTAssertTrue(PraiseMoment.prefersRank(r(2, 2)))      // 2位 over 上位2%
        XCTAssertFalse(PraiseMoment.prefersRank(r(5, 5)))     // 上位5% over 5位
        XCTAssertTrue(PraiseMoment.prefersRank(r(7, 20)))     // 7位 over 上位20%
        XCTAssertFalse(PraiseMoment.prefersRank(r(15, 15)))   // 上位15% over 15位
        // Third of only five people is still shown: a podium place.
        XCTAssertTrue(PraiseMoment.flatters(.init(rank: 3, total: 5, topPercent: 60, count: 1)))
    }

    func testRetentionIsAPlaceWithItsDetail() {
        let s = MyStanding(words: nil, activeDays: nil,
                           retention: .init(rank: 2, total: 40, topPercent: 5, count: 86, active: 30, days: 35),
                           category: nil, firstCatcher: false)
        let m = PraiseMoment.options(standing: s, headword: "", totalWords: 10, start: nil).first
        XCTAssertEqual(m?.kind, .retentionTop)
        XCTAssertEqual(m?.to, 2)
    }

    func testPickAvoidsTheLastKinds() {
        let opts = PraiseMoment.options(standing: nil, headword: "", totalWords: 10,
                                        start: Date().addingTimeInterval(-70 * day))
        XCTAssertEqual(Set(opts.map(\.kind)), [.months, .totalWords])
        for roll in stride(from: 0.0, to: 1.0, by: 0.1) {
            XCTAssertEqual(PraiseMoment.pick(opts, recent: ["totalWords"], roll: roll)?.kind, .months)
        }
    }

    func testNextGoalIsTheNextRoundNumber() {
        XCTAssertEqual(PraiseMoment.nextGoal(after: 3), 5)
        XCTAssertEqual(PraiseMoment.nextGoal(after: 50), 75)
        XCTAssertEqual(PraiseMoment.nextGoal(after: 1000), 1500)
    }
}
