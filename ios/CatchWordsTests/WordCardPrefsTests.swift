import XCTest
@testable import CatchWords

/// The word page's sections (owner 2026-10-16): 台湾メモ is shown by default, right above 「実際の使われ方」, and a
/// card order saved before 1.0.1 gets it moved there and shown, once. Run on its own by .github/workflows/ios-check.yml.
final class WordCardPrefsTests: XCTestCase {
    func testTaiwanNoteShownRightAboveRealUsageByDefault() {
        let shown = CardSection.defaultVisible(for: "zh-TW")
        XCTAssertTrue(shown.contains(.taiwanNote))
        let order = CardSection.defaultOrder(for: "zh-TW")
        let note = try? XCTUnwrap(order.firstIndex(of: .taiwanNote))
        let real = try? XCTUnwrap(order.firstIndex(of: .realUsage))
        XCTAssertEqual(note.map { $0 + 1 }, real)
    }

    @MainActor
    func testSavedOrderGetsTaiwanNoteMovedAndShown() {
        let saved: [CardSection] = [.realUsage, .meaning, .taiwanNote, .example, .usageChunks, .measureWords, .relatedWords]
        let (order, hidden) = CardPrefsStore.taiwanNoteAboveRealUsage(order: saved, hidden: [.taiwanNote, .measureWords])
        XCTAssertEqual(order, [.taiwanNote, .realUsage, .meaning, .example, .usageChunks, .measureWords, .relatedWords])
        XCTAssertEqual(hidden, [.measureWords], "only 台湾メモ is shown again; the rest stays as chosen")
    }

    @MainActor
    func testSavedOrderWithoutRealUsagePutsTaiwanNoteLast() {
        let (order, hidden) = CardPrefsStore.taiwanNoteAboveRealUsage(order: [.meaning, .taiwanNote, .example], hidden: [])
        XCTAssertEqual(order, [.meaning, .example, .taiwanNote])
        XCTAssertTrue(hidden.isEmpty)
    }

    /// 「作り直す」's dust (`RegenDust`): the old content goes in half a second, the cloud waits for the new one, which
    /// gathers back only once the old one has gone, and the effect ends when it is back.
    @MainActor
    func testRegenerateDustTiming() {
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(RegenDust.phase(at: t0, startedAt: nil, readyAt: nil).active)
        let half = RegenDust.phase(at: t0.addingTimeInterval(RegenDust.dissolve / 2), startedAt: t0, readyAt: nil)
        XCTAssertEqual(half.out, 0.5, accuracy: 0.01)
        XCTAssertEqual(half.back, 0)
        // Still writing after 5 s: the cloud stays (fully gone, nothing back yet).
        let waiting = RegenDust.phase(at: t0.addingTimeInterval(5), startedAt: t0, readyAt: nil)
        XCTAssertEqual(waiting.out, 1)
        XCTAssertEqual(waiting.back, 0)
        XCTAssertTrue(waiting.active)
        // The answer came at once: the new content waits until the old has gone, then comes back.
        let early = t0.addingTimeInterval(0.1)
        XCTAssertEqual(RegenDust.phase(at: t0.addingTimeInterval(RegenDust.dissolve), startedAt: t0, readyAt: early).back, 0)
        let back = RegenDust.phase(at: t0.addingTimeInterval(RegenDust.dissolve + RegenDust.assemble / 2), startedAt: t0, readyAt: early)
        XCTAssertEqual(back.back, 0.5, accuracy: 0.01)
        let done = RegenDust.phase(at: t0.addingTimeInterval(RegenDust.dissolve + RegenDust.assemble + 0.01), startedAt: t0, readyAt: early)
        XCTAssertFalse(done.active)
    }

    /// Which sections 「作り直す」 is offered on: every one the server can write again (owner 2026-10-16), not 語形
    /// (dictionary), not the outside links and pictures, not the retired sections.
    func testEverySectionTheServerCanWriteCanBeRegenerated() {
        for lang in ["zh-TW", "en", "ja"] {
            for s in CardSection.sections(for: lang) where s != .forms && !s.isExternal {
                XCTAssertTrue(s.isRegenerable, "\(lang) \(s)")
            }
        }
        XCTAssertFalse(CardSection.forms.isRegenerable)
        XCTAssertFalse(CardSection.realUsage.isRegenerable)
        XCTAssertFalse(CardSection.webImages.isRegenerable)
        XCTAssertFalse(CardSection.etymology.isRegenerable)
        XCTAssertTrue(CardSection.taiwanNote.isRegenerable)
        XCTAssertTrue(CardSection.meaning.isRegenerable)
    }
}
