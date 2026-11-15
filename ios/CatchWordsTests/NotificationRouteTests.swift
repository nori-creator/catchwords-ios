import XCTest
@testable import CatchWords

/// Where a tapped notification leads (`NotificationRouter.route(for:)`). The delegate itself answers iOS on the
/// main thread (the `async` form crashed when a review reminder was tapped, TestFlight 1.0.6 (1094)).
@MainActor
final class NotificationRouteTests: XCTestCase {
    func test_reviewReminderOpensReview() {
        XCTAssertEqual(NotificationRouter.route(for: "review-0"), .review)
        XCTAssertEqual(NotificationRouter.route(for: "review-2"), .review)
    }

    func test_placeReminderOpensItsWord() {
        XCTAssertEqual(NotificationRouter.route(for: "place-abc-123"), .sticker("abc-123"))
    }

    func test_albumAndPendingPhotos() {
        XCTAssertEqual(NotificationRouter.route(for: Milestone.notificationId), .home)
        XCTAssertEqual(NotificationRouter.route(for: PendingRetry.notificationPrefix + "x"), .pendingPhotos)
    }

    func test_someoneElsesNotificationGoesNowhere() {
        XCTAssertNil(NotificationRouter.route(for: "something-else"))
    }
}
