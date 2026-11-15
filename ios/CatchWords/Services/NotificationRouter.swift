import SwiftUI
import UserNotifications

/// Where a tapped notification leads (web: review reminder → /review, place reminder → that word).
enum NotificationRoute: Equatable {
    case review
    /// The milestone album (web /home?memorial=N): home, where its entry sits on the page.
    case home
    case sticker(String)
    /// 「解析が終わりました」 (PendingRetry): the 「解析待ち」 list on the camera, to pick the word.
    case pendingPhotos
}

/// Receives taps on the app's notifications and hands the destination to the tab shell.
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    /// The destination waiting to be opened (cleared by the tab shell once it has navigated).
    var pending: NotificationRoute?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Where a notification's identifier leads (nil: not one of ours).
    static func route(for id: String) -> NotificationRoute? {
        if id.hasPrefix(ReminderService.placeIdentifierPrefix) {
            return .sticker(String(id.dropFirst(ReminderService.placeIdentifierPrefix.count)))
        }
        if id == Milestone.notificationId { return .home }
        if id.hasPrefix(ReminderService.reviewIdentifierPrefix) { return .review }
        if id.hasPrefix(PendingRetry.notificationPrefix) { return .pendingPhotos }
        return nil
    }

    // The completion-handler forms, not the `async` ones: iOS calls an `async` delegate method off the main thread
    // and, when it returns, the system's completion handler ran on that thread too. UIKit then updates its state
    // snapshot from there and asserts (`-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]`):
    // tapping a review reminder crashed the app (TestFlight 1.0.6 (1094), 2026-11-15). Both answers go back on main.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let route = Self.route(for: id) { self.pending = route }
            }
            completionHandler()
        }
    }

    /// A reminder that fires while the app is open still shows as a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async { completionHandler([.banner, .sound]) }
    }
}
