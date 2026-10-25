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

    /// 版25 (owner 2026-10-24/25): 「例文」 is a card again, right under 「使い方チャンク」 — on a new install and on an order
    /// saved while it was inside 「使い方」; an order that already places it keeps it there.
    @MainActor
    func testExampleCardComesBackUnderTheChunks() {
        XCTAssertEqual(CardSection.sections(for: "zh-TW"),
                       [.meaning, .usageChunks, .example, .measureWords, .relatedWords, .taiwanNote, .realUsage])
        XCTAssertEqual(CardSection.defaultOrder(for: "zh-TW"),
                       [.meaning, .usageChunks, .example, .measureWords, .relatedWords, .taiwanNote, .realUsage])
        let saved: [CardSection] = [.meaning, .usageChunks, .measureWords, .relatedWords, .taiwanNote, .realUsage]
        XCTAssertEqual(CardPrefsStore.withExampleAfterChunks(saved + [.example], saved: saved),
                       [.meaning, .usageChunks, .example, .measureWords, .relatedWords, .taiwanNote, .realUsage])
        let placed: [CardSection] = [.example, .meaning, .usageChunks]
        XCTAssertEqual(CardPrefsStore.withExampleAfterChunks(placed, saved: placed), placed)
    }

    @MainActor
    func testSavedOrderWithoutRealUsagePutsTaiwanNoteLast() {
        let (order, hidden) = CardPrefsStore.taiwanNoteAboveRealUsage(order: [.meaning, .taiwanNote, .example], hidden: [])
        XCTAssertEqual(order, [.meaning, .example, .taiwanNote])
        XCTAssertTrue(hidden.isEmpty)
    }

    /// Someone with no saved Mandarin order (new install) who hides 台湾メモ keeps it hidden: the one-time move is
    /// marked done on the default path too, so it does not run on the next launch and show it again.
    @MainActor
    func testHidingTaiwanNoteOnAFreshInstallIsKept() {
        let d = UserDefaults.standard
        let keys = ["wordcard-prefs-v6", "wordcard-prefs-v6-en", CardPrefsStore.taiwanNoteMovedKey]
        let before = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, before) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        keys.forEach { d.removeObject(forKey: $0) }

        let first = CardPrefsStore()
        first.use("en"); first.use("zh-TW")
        XCTAssertTrue(first.isVisible(.taiwanNote))
        XCTAssertTrue(d.bool(forKey: CardPrefsStore.taiwanNoteMovedKey), "the move counts as done with nothing saved")
        first.setVisible(.taiwanNote, false)

        let next = CardPrefsStore()  // the next launch
        next.use("en"); next.use("zh-TW")
        XCTAssertFalse(next.isVisible(.taiwanNote), "hiding it is kept")
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
