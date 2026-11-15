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

    /// A picture quiz (owner 2026-11-15): the tap opens that word's 4-choice question first.
    func test_reviewQuizOpensItsWordsQuestion() {
        let id = ReminderService.reviewIdentifier(index: 1, stickerId: "7C15-86CD")
        XCTAssertEqual(id, "review-1@7C15-86CD")
        XCTAssertEqual(NotificationRouter.route(for: id), .quiz("7C15-86CD"))
        XCTAssertEqual(ReminderService.reviewIdentifier(index: 0, stickerId: nil), "review-0")
        XCTAssertEqual(NotificationRouter.route(for: "review-0@"), .review)
    }

    func test_placeReminderOpensItsWordsQuestion() {
        XCTAssertEqual(NotificationRouter.route(for: "place-abc-123"), .quiz("abc-123"))
    }

    func test_albumAndPendingPhotos() {
        XCTAssertEqual(NotificationRouter.route(for: Milestone.notificationId), .home)
        XCTAssertEqual(NotificationRouter.route(for: PendingRetry.notificationPrefix + "x"), .pendingPhotos)
    }

    func test_someoneElsesNotificationGoesNowhere() {
        XCTAssertNil(NotificationRouter.route(for: "something-else"))
    }
}
