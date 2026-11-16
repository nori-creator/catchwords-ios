import XCTest
@testable import CatchWords

/// The street and its number on a word's place line (`LocationService.streetLine`, owner 2026-11-16: Apple's 「No. 3-1」
/// showed as 「鄭州路 No. 3-1」 instead of the local 「鄭州路3-1號」). Run on its own by .github/workflows/ios-check.yml.
final class StreetAddressTests: XCTestCase {
    private func line(_ road: String, _ number: String?, _ country: String? = "TW") -> String {
        LocationService.streetLine(road: road, number: number, country: country)
    }

    func test_taiwanNumberIsWrittenTheLocalWay() {
        XCTAssertEqual(line("鄭州路", "No. 3-1"), "鄭州路3-1號")
        XCTAssertEqual(line("和平東路一段", "No.162"), "和平東路一段162號")
        XCTAssertEqual(line("鄭州路", "No 3"), "鄭州路3號")
        XCTAssertEqual(line("鄭州路", "3-1"), "鄭州路3-1號")
    }

    func test_aNumberAlreadyEndingIn號IsKept() {
        XCTAssertEqual(line("和平東路一段", "162號"), "和平東路一段162號")
        XCTAssertEqual(line("和平東路一段", "162號之1"), "和平東路一段162號之1")
    }

    func test_otherPlacesKeepTheirOwnForm() {
        // A street in Latin letters (the Spanish screen, a street abroad): as before.
        XCTAssertEqual(line("Zhengzhou Rd", "No. 3-1"), "No. 3-1 Zhengzhou Rd")
        XCTAssertEqual(line("Heping East Road", "162", "US"), "162 Heping East Road")
        // Japan: no 號.
        XCTAssertEqual(line("神南", "1-19", "JP"), "神南1-19")
        // China: 号.
        XCTAssertEqual(line("南京东路", "No. 100", "CN"), "南京东路100号")
    }

    func test_withoutANumberOnlyTheStreet() {
        XCTAssertEqual(line("鄭州路", nil), "鄭州路")
        XCTAssertEqual(line("鄭州路", "  "), "鄭州路")
    }
}
