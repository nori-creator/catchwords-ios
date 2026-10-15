import XCTest
@testable import CatchWords

/// The legal pages open in the display language (owner 2026-10-15: under the English UI the terms opened in Japanese):
/// every link carries `?lang=ja|en|zh-TW`, built with URLComponents. Run on its own by ios-check.yml.
final class LegalURLTests: XCTestCase {
    private func query(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value }
        return out
    }

    func testEachDisplayLanguageGoesIntoTheLink() {
        for lang in ["ja", "en", "zh-TW"] {
            let url = AppConfig.legalURL("terms", lang: lang)
            XCTAssertEqual(url.host(), AppConfig.webBaseURL.host())
            XCTAssertEqual(url.path(), "/terms")
            XCTAssertEqual(query(url)["lang"], lang, "\(lang)")
        }
    }

    func testEveryLegalPageCarriesTheCurrentLanguage() {
        let was = L10n.lang
        defer { L10n.lang = was }
        L10n.lang = "en"
        XCTAssertEqual(query(AppConfig.termsURL)["lang"], "en")
        XCTAssertEqual(query(AppConfig.privacyURL)["lang"], "en")
        XCTAssertEqual(query(AppConfig.tokushohoURL)["lang"], "en")
        XCTAssertEqual(query(AppConfig.supportURL)["lang"], "en")
        XCTAssertEqual(AppConfig.tokushohoURL.path(), "/legal/tokushoho")
        XCTAssertEqual(AppConfig.supportURL.path(), "/support")
        XCTAssertEqual(AppConfig.privacyURL.path(), "/privacy")
        L10n.lang = "zh-TW"
        XCTAssertEqual(AppConfig.termsURL.absoluteString, "https://catchwords.lovable.app/terms?lang=zh-TW")
        L10n.lang = "ja"
        XCTAssertEqual(AppConfig.privacyURL.absoluteString, "https://catchwords.lovable.app/privacy?lang=ja")
    }

    func testAnUnknownLanguageFallsBackToASupportedOne() {
        XCTAssertEqual(query(AppConfig.legalURL("terms", lang: "zh-Hant"))["lang"], "zh-TW")
        XCTAssertEqual(query(AppConfig.legalURL("terms", lang: "en-GB"))["lang"], "en")
        XCTAssertEqual(query(AppConfig.legalURL("terms", lang: "fr"))["lang"], "ja")
    }
}
