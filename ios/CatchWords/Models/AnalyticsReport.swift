import Foundation

/// The developer's 分析 as the server counts it (server `analytics.ts`, `AnalyticsReport`). A learner is someone who
/// caught a word (new or again) or answered a review in the span; days are Taipei days. Anonymous, admin, test-mail and
/// flagged accounts are left out of every number and listed last with their reason. Each chart's one-line reading
/// comes as a `code` and its numbers (`insights`); the screen turns it into a sentence in the display language.
nonisolated struct AnalyticsReport: Decodable, Sendable, Equatable {
    nonisolated struct Metric: Decodable, Sendable, Equatable {
        let value: Double?
        let prev: Double?
        /// For a rate: how many people it is out of.
        let n: Int?
        let prevN: Int?
        /// Who is in the number (ids), for 「誰？」.
        let users: [String]?
    }

    nonisolated struct Overview: Decodable, Sendable, Equatable {
        let learners: Metric
        let newUsers: Metric
        let catches: Metric
        let reviews: Metric
        let firstDayCatch: Metric
        let weekReturn: Metric
    }

    nonisolated struct Day: Decodable, Sendable, Equatable, Identifiable {
        let day: String
        let learners: [String]
        let catches: Int
        let reviews: Int
        let signups: [String]
        var id: String { day }
    }

    nonisolated struct Step: Decodable, Sendable, Equatable, Identifiable {
        let key: String
        let users: [String]
        var id: String { key }
    }

    nonisolated struct Funnel: Decodable, Sendable, Equatable {
        let cohort: Int
        let steps: [Step]
        /// The step after the biggest loss (the red line); nil when no one was lost. Older servers: nil.
        var worst: Int? = nil
    }

    nonisolated struct Cell: Decodable, Sendable, Equatable {
        let pct: Double
        let users: [String]
    }

    nonisolated struct Cohort: Decodable, Sendable, Equatable, Identifiable {
        let week: String
        let size: Int
        let cells: [Cell?]
        var id: String { week }
    }

    nonisolated struct User: Decodable, Sendable, Equatable, Identifiable {
        let id: String
        let name: String?
        let avatarUrl: String?
        let createdAt: String
        let provider: String?
        let uiLanguage: String?
        let levelNow: String?
        let levelGoal: String?
        let onboarded: Bool
        /// new / active / at_risk / lapsed / never
        let status: String
        /// onboarding / first_catch, for someone who never caught a word
        let stoppedAt: String?
        let catches: Int
        let catchesInRange: Int
        let reviews: Int
        let reviewsInRange: Int
        let accuracy: Double?
        let learningDays: Int
        let lastActive: String?
        /// anonymous / admin / test_email / flagged; nil when counted
        let excluded: String?
        /// The last 14 days (oldest first): catches + reviews each day, for the row's small bars. Older servers: nil.
        var recent: [Int]? = nil
    }

    nonisolated struct Timing: Decodable, Sendable, Equatable {
        let p50: Double?
        let p90: Double?
        let n: Int
        let prevP50: Double?
    }

    nonisolated struct Rate: Decodable, Sendable, Equatable {
        let pct: Double?
        let n: Int
    }

    nonisolated struct Cost: Decodable, Sendable, Equatable {
        let total: Double
        let perLearner: Double?
        let unpriced: Int
    }

    nonisolated struct Place: Decodable, Sendable, Equatable, Identifiable {
        let name: String
        let n: Int
        var id: String { name }
    }

    nonisolated struct Quality: Decodable, Sendable, Equatable {
        let suggestS: Timing
        let cardS: Timing
        let firstPick: Rate
        let aiErrors: Rate
        let backupRefused: Int
        let aiCostUsd: Cost
        let failures: Int
        let places: [Place]
    }

    nonisolated struct Ads: Decodable, Sendable, Equatable {
        let limitHit: Int
        let offered: Int
        let watched: Int
        let failed: Int
    }

    nonisolated struct Insight: Decodable, Sendable, Equatable {
        let chart: String
        let code: String
        /// good / warn / bad / info
        let tone: String
        let values: [String: JSONValue]

        func num(_ key: String) -> Double { values[key]?.double ?? 0 }
        func int(_ key: String) -> Int { Int(num(key).rounded()) }
        func text(_ key: String) -> String { values[key]?.string ?? "" }
    }

    nonisolated struct Window: Decodable, Sendable, Equatable {
        let from: String
        let to: String
        let prevFrom: String
        let prevTo: String
    }

    let generatedAt: String
    let today: String
    let range: Int
    let window: Window
    let counted: Int
    let excluded: Int
    let appEventsSince: String?
    let overview: Overview
    let daily: [Day]
    let funnel: Funnel
    let cohorts: [Cohort]
    let users: [User]
    let quality: Quality
    let ads: Ads
    let insights: [Insight]
    /// 「要点」: up to three readings, bad before warn before good (server `pickHighlights`). Older servers: nil.
    var highlights: [Insight]? = nil

    static func decode(_ data: Data) throws -> AnalyticsReport {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(AnalyticsReport.self, from: data)
    }

    /// The reading under one chart (the first, when a chart has more than one).
    func insights(for chart: String) -> [Insight] { insights.filter { $0.chart == chart } }

    func user(_ id: String) -> User? { users.first { $0.id == id } }
}
