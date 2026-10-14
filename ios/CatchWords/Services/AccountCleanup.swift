import Foundation
import UserNotifications
import WidgetKit

/// What stays on the device after a sign-out or an account deletion.
///
/// - Sign-out: the next person on this phone must not get any notification planned for the previous
///   account — review and place reminders (they carry its words and place names), the milestone album
///   ("◯日目の記念アルバム", counted from its sign-up day) and finished-analysis notices. Photos waiting in
///   「解析待ち」 stay — a photo that cannot be retaken is never thrown away just for signing out.
/// - Account deletion (App Store Review Guideline 5.1.1(v)): the server erased the account; the copies on
///   this phone go too — waiting photos, reminders, widget words and thumbnails, cached images.
enum AccountCleanup {
    /// After any sign-out (button, expired login, account deleted).
    static func signedOut() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter(isAccountNotification))
        center.removeAllDeliveredNotifications()
        UserDefaults.standard.set(false, forKey: ReminderService.placeKey)
        // The review reminder setting is that account's too: the next one starts from off and the default
        // time, and takes its own from the account at sign-in (`ReminderService.loadFromAccount`).
        UserDefaults.standard.set("off", forKey: ReminderService.modeKey)
        UserDefaults.standard.set(ReminderService.defaultTime, forKey: ReminderService.timesKey)
        // Photos fetched through signed URLs may sit in the shared HTTP cache.
        URLCache.shared.removeAllCachedResponses()
        // Whether that account was an admin (the developer section of 設定).
        AdminAccess.shared.clear()
    }

    /// Every notification the app plans belongs to the signed-in account (R6-03). The next sign-in plans
    /// its own again (reminders at sign-in, the milestone album when Home opens).
    static func isAccountNotification(_ id: String) -> Bool {
        id.hasPrefix(ReminderService.reviewIdentifierPrefix)
            || id.hasPrefix(ReminderService.placeIdentifierPrefix)
            || id.hasPrefix(PendingRetry.notificationPrefix)
            || id == Milestone.notificationId
    }

    /// After `deleteMyAccount` succeeded. `userId` is the deleted account (read before signing out).
    static func accountDeleted(userId: String?) async {
        await signedOut()
        // The display language chosen by that account (the sign-out right after resets it too).
        L10n.resetToDevice()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UserDefaults.standard.set("off", forKey: ReminderService.modeKey)
        if let userId { PendingQueue.shared.removeAll(ownerId: userId) }
        // That account's answer to the AI consent.
        if let userId { AIConsent.removeRecord(userId: userId) }

        // What that account closed or left half-way on this device: the milestone albums it dismissed and
        // the first tour still to continue.
        Milestone.removeRecord(userId: userId)
        TourStep.removePending(userId: userId)
        // The photos it took off the home album that only this phone remembered.
        if let userId { UserDefaults.standard.removeObject(forKey: "album.hidden.local.\(userId)") }
        // Which of its selfies had no person to cut out.
        if let userId { SelfieCutouts.shared.reset(deleting: userId) }

        // Unsent text drafts that older versions of the app kept on this device for that account
        // (`diary-draft-<user>-<date>`; the feature is gone, the leftovers go with the account).
        if let userId {
            let prefix = "diary-draft-\(userId)-"
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }

        // Widgets: the word of the day and its photo thumbnails.
        WidgetShared.defaults?.removeObject(forKey: WidgetShared.snapshotKey)
        if let thumbs = WidgetShared.thumbsURL {
            try? FileManager.default.removeItem(at: thumbs)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
