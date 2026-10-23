import Foundation

/// One character of an example sentence with its reading (server `readSentences`). nil readings: punctuation, letters,
/// digits, or a character the dictionary there could not read (never guessed).
nonisolated struct SentenceUnit: Codable, Hashable, Sendable {
    let char: String
    let pinyin: String?
    let zhuyin: String?
}

/// The readings of the example sentences (owner 2026-10-22: 「例文の漢字にピンインまたは注音をすべて書いて、書き方、
/// 大きさはアプリ内の書き方に統一して」): asked of the server once per sentence — its dictionary with Taiwan's readings,
/// no AI (`sentence-readings.server.ts`) — and kept on the device. A sentence it could not read is shown as before.
@MainActor
final class SentenceReadings {
    static let shared = SentenceReadings()

    /// A word the card already reads (the headword, a chunk part): it wins over the dictionary where it stands.
    struct Known: Hashable {
        let text: String
        let pinyin: String
    }

    nonisolated private struct Entry: Codable, Sendable {
        let sentence: String
        let units: [SentenceUnit]
    }

    nonisolated private struct Answer: Decodable, Sendable {
        let readings: [Entry]
    }

    private var units: [String: [SentenceUnit]] = [:]
    /// The sentences in the order they came (the oldest are let go past `maxKept`).
    private var order: [String] = []
    private var loaded = false
    private var saveTask: Task<Void, Never>?
    private static let maxKept = 800
    nonisolated private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sentence-readings.json")

    /// What is kept for this sentence (nothing asked).
    func cached(_ sentence: String) -> [SentenceUnit]? {
        loadIfNeeded()
        return units[sentence]
    }

    /// The readings of these sentences: the kept ones at once, the others asked of the server in one call. A sentence the
    /// server did not answer (offline, an older server) is left out.
    func load(_ sentences: [String], known: [Known]) async -> [String: [SentenceUnit]] {
        loadIfNeeded()
        var missing: [String] = []
        for s in sentences where !s.isEmpty && units[s] == nil && !missing.contains(s) { missing.append(s) }
        if !missing.isEmpty {
            let words = known.filter { !$0.text.isEmpty && !$0.pinyin.isEmpty }.prefix(40)
                .map { ["text": $0.text, "pinyin": $0.pinyin] }
            if let answer = try? await NativeAPI.call("readSentences", ["sentences": Array(missing.prefix(24)), "words": words],
                                                      as: Answer.self, timeout: 15) {
                for e in answer.readings where e.units.map(\.char).joined() == e.sentence {
                    keep(e.sentence, e.units)
                }
                scheduleSave()
            }
        }
        var out: [String: [SentenceUnit]] = [:]
        for s in sentences { if let u = units[s] { out[s] = u } }
        return out
    }

    /// The headword and the chunk parts the card reads.
    static func known(headword: String, pinyin: String?, chunks: [UsageChunk]) -> [Known] {
        var out: [Known] = []
        if let p = pinyin, !headword.isEmpty { out.append(Known(text: headword, pinyin: p)) }
        for c in chunks {
            for part in c.parts {
                if let p = part.pinyin, !p.isEmpty { out.append(Known(text: part.text, pinyin: p)) }
            }
        }
        return Array(Set(out))
    }

    #if DEBUG
    /// `-uiPreview milktea`: the readings the server's dictionary gives these sentences (the demo has no dictionary).
    func seedForPreview(_ sentence: String, _ u: [SentenceUnit]) {
        loadIfNeeded()
        keep(sentence, u)
    }
    #endif

    private func keep(_ sentence: String, _ u: [SentenceUnit]) {
        if units[sentence] == nil { order.append(sentence) }
        units[sentence] = u
        if order.count > Self.maxKept {
            for s in order.prefix(order.count - Self.maxKept) { units[s] = nil }
            order.removeFirst(order.count - Self.maxKept)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.file),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for e in entries { keep(e.sentence, e.units) }
    }

    /// Written a moment after the last answer, off the main thread.
    private func scheduleSave() {
        saveTask?.cancel()
        let entries = order.compactMap { s in units[s].map { Entry(sentence: s, units: $0) } }
        let url = Self.file
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
            }.value
        }
    }
}
