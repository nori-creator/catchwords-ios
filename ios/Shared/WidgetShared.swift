import Foundation
import ActivityKit

// Compiled into BOTH the app (CatchWords) and the widget extension (CatchWordsWidgets):
// the `Shared` folder is a synchronized group that belongs to both targets.
// The app writes a `WidgetSnapshot`; the widgets only read it.

/// Where the app and the widgets meet: the App Group `group.com.nori.catchwords`.
nonisolated enum WidgetShared {
    static let appGroup = "group.com.nori.catchwords"
    static let snapshotKey = "widget.snapshot.v1"
    static let thumbsFolder = "WidgetThumbs"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// nil when the App Group is not provisioned for this build (then the widgets show their empty state). Asked once:
    /// each ask goes to the system's container service (the app's widget update asked several times per word on the
    /// main thread — seconds on the UI tour's simulator, 2026-10-16), and the answer never changes while running.
    static let containerURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)

    static var thumbsURL: URL? { containerURL?.appendingPathComponent(thumbsFolder, isDirectory: true) }

    static func thumbURL(_ file: String) -> URL? { thumbsURL?.appendingPathComponent(file) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    /// "2026-10-02" in the device's calendar and time zone (word of the day changes at local midnight).
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// One word shown by the 「今日の単語」 widget.
nonisolated struct WidgetWord: Codable, Sendable, Hashable {
    /// The day it is the word of the day (`WidgetShared.dayKey`).
    var day: String
    var stickerId: String
    var headword: String
    /// Zhuyin / kana reading (nil when the word has none).
    var reading: String?
    /// Meaning in the app's display language.
    var meaning: String
    /// File name inside `WidgetShared.thumbsURL` (JPEG on white, ≤ 300 px).
    var thumbFile: String?
    /// The picture is a cut-out (drawn whole, not cropped).
    var isCutout: Bool
}

/// What the app last told the widgets.
nonisolated struct WidgetSnapshot: Codable, Sendable, Hashable {
    /// The app's display language (a code of ios/Localization/languages.json).
    var lang: String
    /// Today's word first, then the next days' (so the widget still changes at midnight without the app).
    var words: [WidgetWord]
    /// Cards already due when the snapshot was written.
    var dueNow: Int
    /// Cards coming due later (ascending, capped) — the widget counts them up on its own.
    var upcomingDue: [Date]
    /// Words caught in the current learning language.
    var totalWords: Int
    /// Review streak in days (nil when unknown).
    var streak: Int?
    var updatedAt: Date

    func dueCount(at date: Date) -> Int {
        dueNow + upcomingDue.filter { $0 <= date }.count
    }

    func word(for date: Date) -> WidgetWord? {
        let key = WidgetShared.dayKey(date)
        return words.first { $0.day == key } ?? words.last
    }
}

/// The review session on the Lock Screen and in the Dynamic Island.
nonisolated struct ReviewActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Cards answered in this round.
        var done: Int
        /// Cards in this round.
        var total: Int
        /// Correct answers in this round.
        var correct: Int
    }

    /// The app's display language when the session started (a code of ios/Localization/languages.json).
    var lang: String
}
