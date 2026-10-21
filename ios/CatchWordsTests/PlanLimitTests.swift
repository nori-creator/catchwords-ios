import XCTest
@testable import CatchWords

/// The free catches a day (owner decision 2026-10-21): 10 a day for the first 7 days from the first launch, then 3.
/// Run on its own by ios-check.yml.
@MainActor
final class PlanLimitTests: XCTestCase {
    func testTheWelcomeWeekGivesTenADayThenThree() {
        let first = "2026-10-21"
        XCTAssertEqual(PlanStore.limit(onDay: "2026-10-21", firstDay: first), 10)
        XCTAssertEqual(PlanStore.limit(onDay: "2026-10-27", firstDay: first), 10)  // day 7
        XCTAssertEqual(PlanStore.limit(onDay: "2026-10-28", firstDay: first), 3)   // day 8
        XCTAssertEqual(PlanStore.limit(onDay: "2027-03-01", firstDay: first), 3)
    }

    func testDaysAcrossMonthsAndYears() {
        XCTAssertEqual(PlanStore.daysBetween("2026-12-29", "2027-01-04"), 6)
        XCTAssertEqual(PlanStore.daysBetween("2026-02-27", "2026-03-02"), 3)
        XCTAssertNil(PlanStore.daysBetween("", "2026-03-02"))
    }

    func testAnUnreadableFirstDayFallsBackToTheEverydayAmount() {
        XCTAssertEqual(PlanStore.limit(onDay: "2026-10-21", firstDay: "broken"), 3)
    }
}
