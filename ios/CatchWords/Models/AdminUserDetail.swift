import Foundation

/// One person in the developer's 分析 (server `getAdminUserDetail`, `admin-users.functions.ts` + `admin-user-insights.ts`).
///
/// Numbers only, as the privacy policy lets the operator look (§2): no e-mail, no exact place (city and district only,
/// and no coordinates — the map places the areas by their names on the phone), no photo, no word, no text the person
/// wrote. Every field is optional so an older or newer server never breaks the page.
nonisolated struct AdminUserDetail: Decodable, Sendable, Equatable {
    nonisolated struct Profile: Decodable, Sendable, Equatable {
        var displayName: String? = nil
        var avatarUrl: String? = nil
        var createdAt: String? = nil
        var uiLanguage: String? = nil
        var targetLanguage: String? = nil
        var levelGoal: String? = nil
        var currentLevel: String? = nil
        var reviewDailyLimit: Int? = nil
        var plan: String? = nil
        var onboarded: Bool? = nil
    }

    nonisolated struct Day: Decodable, Sendable, Equatable, Identifiable {
        let day: String
        var catches: Double? = nil
        var reviews: Double? = nil
        var correct: Double? = nil
        var opens: Double? = nil
        var minutes: Double? = nil
        var id: String { day }
        /// What the calendar shades by: catches + reviews.
        var activity: Int { Int(((catches ?? 0) + (reviews ?? 0)).rounded()) }
    }

    nonisolated struct Week: Decodable, Sendable, Equatable, Identifiable {
        let from: String
        let to: String
        var reviews: Int? = nil
        var accuracy: Double? = nil
        var id: String { from }
    }

    nonisolated struct Memory: Decodable, Sendable, Equatable {
        var levels: [Int]? = nil
    }

    nonisolated struct Catches: Decodable, Sendable, Equatable {
        var total: Int? = nil
        var last30: Int? = nil
        var first: String? = nil
        var last: String? = nil
        var again: Int? = nil
    }

    nonisolated struct Streak: Decodable, Sendable, Equatable {
        var current: Int? = nil
        var best: Int? = nil
    }

    nonisolated struct Review: Decodable, Sendable, Equatable {
        var total180: Int? = nil
        var last30: Int? = nil
        var correctPct: Double? = nil
        var cards: Int? = nil
        var dueNow: Int? = nil
        var matured: Int? = nil
    }

    nonisolated struct Sessions: Decodable, Sendable, Equatable {
        var sessions: Int? = nil
        var medianMin: Double? = nil
        var totalMin: Double? = nil
    }

    nonisolated struct Usage: Decodable, Sendable, Equatable {
        var sessions: Sessions? = nil
        var openDays: Int? = nil
    }

    /// A city and district (never a street), how many catches, and when in the day (Taipei time).
    nonisolated struct Area: Decodable, Sendable, Equatable, Identifiable {
        let name: String
        let n: Int
        var morning: Int? = nil
        var day: Int? = nil
        var night: Int? = nil
        var id: String { name }
    }

    nonisolated struct Count: Decodable, Sendable, Equatable, Identifiable {
        let key: String
        let n: Int
        var id: String { key }
    }

    nonisolated struct Device: Decodable, Sendable, Equatable {
        var appVersion: String? = nil
        var device: String? = nil
        var os: String? = nil
        var lang: String? = nil
        var at: String? = nil
    }

    nonisolated struct Tutorial: Decodable, Sendable, Equatable {
        var parts: [String]? = nil
        var lastStep: String? = nil
        var lastAt: String? = nil
        var ended: Int? = nil
    }

    nonisolated struct App: Decodable, Sendable, Equatable {
        var device: Device? = nil
        var tutorial: Tutorial? = nil
        var screens30: [Count]? = nil
        var features30: [Count]? = nil
        var lastScreens: [Count]? = nil
    }

    nonisolated struct Trouble: Decodable, Sendable, Equatable {
        var aiCalls30: Int? = nil
        var aiFailures30: Int? = nil
        var aiUsd30: Double? = nil
        var failures30: Int? = nil
        var reports30: Int? = nil
    }

    var profile: Profile? = nil
    var provider: String? = nil
    var lastActive: String? = nil
    /// new / active / at_risk / lapsed / never (the same rule as the list).
    var status: String? = nil
    /// The day since sign-up (the sign-up day is day 1).
    var dayNumber: Int? = nil
    var daily: [Day]? = nil
    var weekly: [Week]? = nil
    var memory: Memory? = nil
    var catches: Catches? = nil
    var streak: Streak? = nil
    var review: Review? = nil
    var usage: Usage? = nil
    var areas: [Area]? = nil
    var categories: [Count]? = nil
    /// Monday … Sunday × 0 … 23 o'clock (Taipei time).
    var heat: [[Int]]? = nil
    var app: App? = nil
    var trouble: Trouble? = nil

    static func decode(_ data: Data) throws -> AdminUserDetail {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(AdminUserDetail.self, from: data)
    }
}
