import Foundation
import Observation

// MARK: - しらべる (the dictionary, owner 2026-11-08)
//
// 「検索とかその辞書みたいに文字を検索して、単語カードが作れたり…辞書の代わりになるようにしたい」
// 「ただ辞書を表示するだけだったら、その辞書を使えばいい…AI にしかできない、学習者にとって役立つ情報を」
//
// Type anything — a word of the display language (傘), the learning language's characters (雨傘), a reading (yusan,
// ㄩˇ ㄙㄢˇ) — and press search. The server (`lookupWord`, server/src/lib/dictionary.functions.ts) answers with 1–6
// entries: the dictionary's base (headword, reading, short meaning, other senses, where it is used, a proper noun or
// not) and what only an AI writes for a learner: what each character means in the word and why they make this meaning,
// which word to use when the search splits, and one short sentence Taiwanese people say.

/// One character of a headword and what it means in that word (`chars`).
nonisolated struct LookupChar: Codable, Sendable, Hashable {
    let char: String
    let pinyin: String
    let meaning: String
}

/// One entry of a search (`lookupWord` → `entries`).
nonisolated struct LookupEntry: Codable, Sendable, Hashable, Identifiable {
    let headword: String
    let pinyin: String
    let zhuyin: String
    /// The central meaning, short (the reader's language).
    let gloss: String
    /// Other common meanings (0–2).
    let senses: [String]
    /// A name (a shop, a place, a brand, a person): told apart from the common words.
    let proper: Bool
    /// Where the word is heard or seen: everyday / spoken / written / technical / sign.
    let usage: String
    /// Against the other entries of the search: which one to use when (empty for a single entry).
    let nuance: String
    let chars: [LookupChar]
    /// How the characters' meanings make the word's.
    let why: String
    let example: String
    let exampleTranslation: String
    let imageQuery: String
    let categoryKey: String

    var id: String { headword }

    enum CodingKeys: String, CodingKey {
        case headword, pinyin, gloss, senses, proper, usage, nuance, chars, why, example
        case zhuyin = "reading_zhuyin"
        case exampleTranslation = "example_translation"
        case imageQuery = "image_query"
        case categoryKey = "category_key"
    }

    init(headword: String, pinyin: String, zhuyin: String, gloss: String, senses: [String] = [], proper: Bool = false,
         usage: String = "everyday", nuance: String = "", chars: [LookupChar] = [], why: String = "", example: String = "",
         exampleTranslation: String = "", imageQuery: String = "", categoryKey: String = "other") {
        self.headword = headword
        self.pinyin = pinyin
        self.zhuyin = zhuyin
        self.gloss = gloss
        self.senses = senses
        self.proper = proper
        self.usage = usage
        self.nuance = nuance
        self.chars = chars
        self.why = why
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.imageQuery = imageQuery
        self.categoryKey = categoryKey
    }

    /// Every field may be missing on an answer from another server version: an entry reads whatever it has.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        headword = s(.headword)
        pinyin = s(.pinyin)
        zhuyin = s(.zhuyin)
        gloss = s(.gloss)
        senses = ((try? c.decodeIfPresent([String].self, forKey: .senses)) ?? nil) ?? []
        proper = ((try? c.decodeIfPresent(Bool.self, forKey: .proper)) ?? nil) ?? false
        usage = s(.usage)
        nuance = s(.nuance)
        chars = ((try? c.decodeIfPresent([LookupChar].self, forKey: .chars)) ?? nil) ?? []
        why = s(.why)
        example = s(.example)
        exampleTranslation = s(.exampleTranslation)
        imageQuery = s(.imageQuery)
        categoryKey = s(.categoryKey)
    }

    /// R10 (docs/language-rules.md): what the server wrote is shown only when it is in the reader's language
    /// (`ReaderLanguage.shown`; the server checks it too, `dictionary-lookup.ts`). An entry whose meaning is not is dropped.
    @MainActor func readerSafe() -> LookupEntry? {
        let g = ReaderLanguage.shown(gloss)
        guard !g.isEmpty else { return nil }
        let keptChars = chars.allSatisfy { !ReaderLanguage.shown($0.meaning).isEmpty } ? chars : []
        let translation = ReaderLanguage.shown(exampleTranslation)
        return LookupEntry(headword: headword, pinyin: pinyin, zhuyin: zhuyin, gloss: g,
                           senses: senses.map { ReaderLanguage.shown($0) }.filter { !$0.isEmpty },
                           proper: proper, usage: usage, nuance: ReaderLanguage.shown(nuance), chars: keptChars,
                           why: keptChars.isEmpty ? "" : ReaderLanguage.shown(why),
                           example: translation.isEmpty ? "" : example, exampleTranslation: translation,
                           imageQuery: imageQuery, categoryKey: categoryKey)
    }

    /// The same word as a name the card and the save understand (the catch's `Candidate`).
    var candidate: Candidate {
        Candidate(kind: "word", headword: headword, zhuyin: zhuyin, pinyin: pinyin, meaningJa: gloss, pos: "",
                  point: [500, 500], confidence: 1, alternatives: [], distinction: nuance, register: proper ? "proper" : "common",
                  categoryKey: categoryKey.isEmpty ? nil : categoryKey)
    }

    /// The short label for where the word is used; nil for an everyday word (no label: it is the usual case).
    var usageLabel: String? {
        switch usage {
        case "spoken": L("話し言葉")
        case "written": L("書き言葉")
        case "technical": L("専門用語")
        case "sign": L("看板・メニュー")
        default: nil
        }
    }
}

/// `lookupWord`'s answer.
nonisolated struct LookupResult: Decodable, Sendable, Hashable {
    let query: String
    /// How the server read the query: learning / display / display_first.
    let mode: String
    let entries: [LookupEntry]

    init(query: String, mode: String, entries: [LookupEntry]) {
        self.query = query
        self.mode = mode
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = ((try? c.decodeIfPresent(String.self, forKey: .query)) ?? nil) ?? ""
        mode = ((try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil) ?? "display"
        // One entry that does not read is dropped, never the whole answer.
        entries = (((try? c.decodeIfPresent([LookupLenientEntry].self, forKey: .entries)) ?? nil) ?? [])
            .compactMap(\.value).filter { !$0.headword.isEmpty }
    }

    enum CodingKeys: String, CodingKey { case query, mode, entries }
}

/// An entry, or nil when it does not read.
nonisolated struct LookupLenientEntry: Decodable, Sendable {
    let value: LookupEntry?
    init(from decoder: Decoder) throws { value = try? LookupEntry(from: decoder) }
}

/// Searches, their answers for this launch, and the searches the learner made (on this device, per account).
@MainActor
@Observable
final class LookupService {
    static let shared = LookupService()

    /// The last searches, newest first (at most `recentLimit`). Kept on this device only — never sent anywhere.
    private(set) var recents: [String] = []
    static let recentLimit = 12

    @ObservationIgnored private var answers: [String: LookupResult] = [:]
    @ObservationIgnored private var cards: [String: Task<CardDetails?, Never>] = [:]
    @ObservationIgnored private var recentsOwner: String?

    private init() {}

    private func key(_ query: String) -> String {
        [query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), L10n.lang, NativeAPI.targetLanguage].joined(separator: "\u{1F}")
    }

    /// The same search again (this launch, the same display and learning language) is answered from memory.
    func cached(_ query: String) -> LookupResult? { answers[key(query)] }

    func lookup(_ query: String) async throws -> LookupResult {
        let q = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if let hit = answers[key(q)] { return hit }
        await ProfileStore.syncLanguageToServer()
        let raw = try await NativeAPI.call("lookupWord", ["query": q, "targetLanguage": NativeAPI.targetLanguage],
                                           as: LookupResult.self, timeout: 30)
        let res = LookupResult(query: q, mode: raw.mode, entries: raw.entries.compactMap { $0.readerSafe() })
        if !res.entries.isEmpty { answers[key(q)] = res }
        return res
    }

    /// Previews only: what a search returns, without the network.
    func seed(_ query: String, _ result: LookupResult) { answers[key(query)] = result }

    /// The word's card (`generateCard`), started when its entry is opened so that adding it is quick. One per headword
    /// and launch; a failed one is forgotten so the next try starts again.
    func card(for entry: LookupEntry) -> Task<CardDetails?, Never> {
        let k = key(entry.headword)
        if let running = cards[k] { return running }
        let candidate = entry.candidate
        let task = Task<CardDetails?, Never> { try? await AIService.shared.cardDetails(for: candidate) }
        cards[k] = task
        Task { if await task.value == nil { cards[k] = nil } }
        return task
    }

    // MARK: Recent searches

    private var recentsKey: String { "lookup.recents.\(SupabaseClient.shared.userId ?? "signedout")" }

    func loadRecents() {
        let owner = SupabaseClient.shared.userId
        guard recentsOwner != owner || recents.isEmpty else { return }
        recentsOwner = owner
        recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    func remember(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recents.removeAll { $0 == q }
        recents.insert(q, at: 0)
        if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }

    func forget(_ query: String) {
        recents.removeAll { $0 == query }
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }
}

// MARK: - Words already in the dex that match what is being typed

nonisolated enum LookupMatch {
    /// A reading without its tone marks, spaces and apostrophes (yǔ sǎn → yusan), for matching what is typed.
    static func plainReading(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "ü", with: "v")
            .filter { $0.isLetter }
    }

    /// The learner's own words for `query`: the headword, the meaning or the reading (tones optional) contains it.
    /// The headword's own match first, then the rest in the dex's order. At most `limit`.
    static func own(_ stickers: [Sticker], query: String, limit: Int = 6) -> [Sticker] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()
        let plain = plainReading(q)
        var heads: [Sticker] = [], others: [Sticker] = []
        var seen = Set<String>()
        for s in stickers {
            guard let w = s.word, !w.headword.isEmpty, !seen.contains(w.headword) else { continue }
            if w.headword.contains(q) {
                seen.insert(w.headword)
                heads.append(s)
            } else if w.meaningJa.lowercased().contains(lower)
                        || (!plain.isEmpty && plain.count >= 2 && plainReading(w.pinyin ?? "").hasPrefix(plain))
                        || (!(w.readingZhuyin ?? "").isEmpty && (w.readingZhuyin ?? "").replacingOccurrences(of: " ", with: "").contains(q.replacingOccurrences(of: " ", with: ""))) {
                seen.insert(w.headword)
                others.append(s)
            }
        }
        return Array((heads + others).prefix(limit))
    }
}
