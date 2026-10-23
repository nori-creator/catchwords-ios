import XCTest
@testable import CatchWords

/// The server's limit messages start with a machine code (web `ai-cap.ts`, 「AI_DAILY_CAP 1日の利用上限…」): no reader
/// ever sees it. Run on its own by .github/workflows/ios-check.yml.
@MainActor
final class ServerMessageTests: XCTestCase {
    private let sent = "AI_DAILY_CAP 1日の利用上限(2500回)に達しました。24時間以内に自動で回復します。"

    func testMachineCodeIsNeverShown() {
        let saved = L10n.lang
        defer { L10n.lang = saved }
        for lang in ["ja", "en", "zh-TW", "es", "ko", "vi"] {
            L10n.lang = lang
            let shown = L10n.readerSafe(sent, fallback: "fallback")
            XCTAssertFalse(shown.contains("AI_DAILY_CAP"), "\(lang): \(shown)")
        }
        L10n.lang = "ja"
        XCTAssertTrue(L10n.readerSafe(sent, fallback: "fallback").hasPrefix("1日の利用上限"))
    }

    func testAPlainFirstWordStays() {
        let saved = L10n.lang
        defer { L10n.lang = saved }
        L10n.lang = "en"
        XCTAssertNotEqual(L10n.readerSafe("API error, try again.", fallback: "fallback"), "error, try again.")
    }
}
