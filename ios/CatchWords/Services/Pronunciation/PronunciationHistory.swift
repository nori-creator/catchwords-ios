import Foundation

/// The learner's scores per word on this device (the coach shows how they moved). Only numbers and dates — never the
/// voice. Per account; removed with the account.
@MainActor
enum PronunciationHistory {
    nonisolated struct Attempt: Codable, Sendable, Equatable {
        let at: Date
        let score: Int
    }

    private static let perWord = 30
    private static let words = 300

    nonisolated private static func key(_ userId: String?) -> String { "pron.history.\(userId ?? "-")" }

    private static func all() -> [String: [Attempt]] {
        guard let data = UserDefaults.standard.data(forKey: key(SupabaseClient.shared.userId)),
              let saved = try? JSONDecoder().decode([String: [Attempt]].self, from: data) else { return [:] }
        return saved
    }

    static func attempts(_ headword: String) -> [Attempt] { all()[headword] ?? [] }

    static func add(_ headword: String, score: Int) {
        var saved = all()
        var list = saved[headword] ?? []
        list.append(Attempt(at: Date(), score: score))
        saved[headword] = Array(list.suffix(perWord))
        if saved.count > words {
            let oldest = saved.sorted { ($0.value.last?.at ?? .distantPast) < ($1.value.last?.at ?? .distantPast) }
            for (word, _) in oldest.prefix(saved.count - words) { saved[word] = nil }
        }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key(SupabaseClient.shared.userId))
        }
    }

    nonisolated static func removeRecords(userId: String?) {
        UserDefaults.standard.removeObject(forKey: key(userId))
    }
}
