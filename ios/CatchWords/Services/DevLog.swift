import Foundation
import Observation

/// What went wrong on this phone, kept for the developer (設定 › 開発者 › アプリの情報 › 最近の記録): the real error of
/// a failed save (owner 2026-10-15: every failure read 「ネットワークに接続できませんでした」, so nobody could tell a dropped
/// connection from a server refusal or an answer the app could not read), an answer that did not decode, an example
/// shown without its scene label. Learners never see it. The newest `limit` entries are kept on the phone (UserDefaults),
/// so a failure seen in the morning can still be read in the evening; the same line twice within ten minutes is kept once.
@Observable
final class DevLog {
    static let shared = DevLog()

    nonisolated struct Entry: Codable, Identifiable, Sendable, Hashable {
        let id: String
        let at: Date
        /// What it is about: save, decode, example …
        let area: String
        let text: String
    }

    static let limit = 80
    private static let key = "dev.log.v1"

    /// Newest first.
    private(set) var entries: [Entry] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ area: String, _ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let now = Date()
        if entries.contains(where: { $0.area == area && $0.text == line && now.timeIntervalSince($0.at) < 600 }) { return }
        entries.insert(Entry(id: UUID().uuidString, at: now, area: area, text: line), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        persist()
        #if DEBUG
        print("[DevLog] \(area): \(line)")
        #endif
    }

    func clear() {
        entries = []
        persist()
    }

    /// Every entry as plain text, for 「コピー」 (pasted into a message to the developer).
    var text: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return entries.map { "\(f.string(from: $0.at)) [\($0.area)] \($0.text)" }.joined(separator: "\n")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
