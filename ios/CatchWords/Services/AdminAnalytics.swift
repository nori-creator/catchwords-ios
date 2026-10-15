import Foundation

/// The developer's numbers, the same the web shows its admin (`/admin/users`, `/admin/metrics`, `/admin/beta`; owner
/// 2026-10-11: 「開発者の私だけ設定の開発者設定からweb版と同じように、利用者やアプリの詳しい情報、分析が見えるように」).
///
/// Read through `/api/native-fn` under admin names (web `native-fn.ts`: `adminListUsers` → `listAdminUsers`,
/// `adminGetUserDetail` → `getAdminUserDetail`, `adminGetOverview` → `getAdminOverview`, `adminGetDashboard` →
/// `getAdminDashboard`, `adminGetBetaMetrics` → `getBetaMetrics`). Every one checks `has_role(admin)` on the server
/// (403 for anyone else). Each answer is kept as the JSON the server sent (`JSONValue`) and read leniently, so a field
/// the web adds or drops never breaks a screen. A server without these names yet (the web change not published)
/// answers 404 (`notDeployed`): the screens say so instead of failing silently.
enum AdminAnalytics {
    enum Failure: Error, Equatable {
        /// The web has not been published with these functions yet.
        case notDeployed
        /// The server does not count this account as an admin.
        case forbidden
        case other(String)
    }

    typealias Answer = Result<JSONValue, Failure>

    /// Every account's row (web `listAdminUsers`).
    static func users() async -> Answer {
        await run { try await NativeAPI.call("adminListUsers", [:], timeout: 120) }
    }

    /// The whole service's numbers (web `getAdminOverview`).
    static func overview() async -> Answer {
        await run { try await NativeAPI.call("adminGetOverview", [:], timeout: 120) }
    }

    /// One account in detail, compared with everyone (web `getAdminUserDetail`).
    static func userDetail(_ userId: String) async -> Answer {
        await run { try await NativeAPI.call("adminGetUserDetail", ["userId": userId], timeout: 120) }
    }

    /// The KPI dashboard: funnel and the last 14 days (web `getAdminDashboard`).
    static func dashboard() async -> Answer {
        await run { try await NativeAPI.call("adminGetDashboard", [:], timeout: 120) }
    }

    /// The beta metrics (web `getBetaMetrics`).
    static func beta() async -> Answer {
        await run { try await NativeAPI.call("adminGetBetaMetrics", [:], timeout: 120) }
    }

    /// The learners' error reports, newest first (web `adminListReports`, 2026-10-15: rows of `{id, headword, kind,
    /// note, status, reporter_lang, created_at}`). Until the web is published with it the answer is 404 → `notDeployed`.
    static func reports() async -> Answer {
        await run { try await NativeAPI.call("adminListReports", [:], timeout: 120) }
    }

    private static func run(_ work: () async throws -> Data) async -> Answer {
        do {
            let data = try await work()
            return .success((try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null)
        } catch let APIError.server(status, message) {
            if status == 404 { return .failure(.notDeployed) }
            if status == 403 { return .failure(.forbidden) }
            return .failure(.other(L10n.readerSafe(message, fallback: L("サーバーエラー（\(status)）"))))
        } catch {
            return .failure(.other((error as? LocalizedError)?.errorDescription ?? L("読み込めませんでした")))
        }
    }

    /// What a failure says on screen.
    static func message(_ f: Failure) -> String {
        switch f {
        case .notDeployed: L("この画面に使うサーバの機能がまだありません。Web版の更新（Publish）が必要です。")
        case .forbidden: L("このアカウントは管理者ではありません。")
        case .other(let text): text.isEmpty ? L("読み込めませんでした") : text
        }
    }
}

// MARK: - Reading the JSON leniently

extension JSONValue {
    var double: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): Double(s)
        default: nil
        }
    }
    var int: Int? { double.map { Int($0.rounded()) } }
    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var array: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }
    var object: [String: JSONValue] {
        if case .object(let o) = self { return o }
        return [:]
    }
    var isNull: Bool { self == .null }

    func num(_ key: String) -> Double? { self[key]?.double }
    func count(_ key: String) -> Int { self[key]?.int ?? 0 }
    func text(_ key: String) -> String? { self[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    func list(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
    /// `[[name, n], …]` pairs (the web's `Object.entries`-style lists).
    func pairs(_ key: String) -> [(String, Int)] {
        list(key).compactMap { row in
            let a = row.array
            guard a.count >= 2, let n = a[1].int else { return nil }
            return (a[0].string ?? "—", n)
        }
    }
}

/// Numbers and dates as the developer screens print them.
enum AdminFormat {
    static func int(_ n: Int?) -> String {
        guard let n else { return "—" }
        return n.formatted(.number.locale(L10n.locale))
    }

    static func number(_ n: Double?, digits: Int = 1) -> String {
        guard let n else { return "—" }
        return n.formatted(.number.precision(.fractionLength(0...digits)).locale(L10n.locale))
    }

    static func percent(_ n: Double?) -> String {
        guard let n else { return "—" }
        return "\(Int(n.rounded()))%"
    }

    static func usd(_ n: Double?, digits: Int = 2) -> String {
        guard let n else { return "—" }
        return "$" + n.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
    }

    /// Milliseconds as seconds (1.2 s); under one second as ms.
    static func ms(_ n: Double?) -> String {
        guard let n else { return "—" }
        return n >= 1000 ? String(format: "%.1f s", n / 1000) : "\(Int(n.rounded())) ms"
    }

    static func date(_ iso: String?) -> String {
        guard let iso, let d = SupabaseDate.parse(iso) else { return "—" }
        return d.formatted(.dateTime.year().month().day().locale(L10n.locale))
    }

    static func dateTime(_ iso: String?) -> String {
        guard let iso, let d = SupabaseDate.parse(iso) else { return "—" }
        return d.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.locale))
    }

    /// A `YYYY-MM-DD` day as M/D (web `md`).
    static func day(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return key }
        return "\(m)/\(d)"
    }

    /// How long ago (web: たった今 / N分前 / N時間前 / N日前 / Nか月前 / 記録なし).
    static func ago(_ iso: String?) -> String {
        guard let iso, let d = SupabaseDate.parse(iso) else { return L("記録なし") }
        let s = max(0, Date().timeIntervalSince(d))
        if s < 60 { return L("たった今") }
        if s < 3600 { return L("\(Int(s / 60))分前") }
        if s < 86_400 { return L("\(Int(s / 3600))時間前") }
        if s < 86_400 * 31 { return L("\(Int(s / 86_400))日前") }
        return L("\(Int(s / (86_400 * 30)))か月前")
    }
}
