import SwiftUI

/// One day's diary page (`journal_entries`; server `listMyDiaryMonth` / `saveMyDiary` / `correctMyJournal`). The
/// learner's own text is in the learning language; the correction too; the notes are in the display language.
nonisolated struct DiaryEntry: Decodable, Sendable, Hashable {
    /// `YYYY-MM-DD` — the album's day (`DiaryStore.key`).
    let date: String
    /// What the learner wrote (never rewritten by the app).
    var text: String
    /// The server's correction of the text (`correctMyJournal`), when one was made — read, not shown: the correction's
    /// design is being made again (owner 2026-10-24).
    var correction: String?
    /// The server's notes on it, in the display language (read, not shown — as above).
    var feedback: String?
    /// The server's 「ネイティブならこう言う」 phrases (read, not shown — as above).
    var nativePhrases: [DiaryPhrase]
    var usedStickerIds: [String]

    enum CodingKeys: String, CodingKey {
        case date, text, correction, feedback
        case nativePhrases = "native_phrases"
        case usedStickerIds = "used_sticker_ids"
    }

    init(date: String, text: String, correction: String? = nil, feedback: String? = nil, nativePhrases: [DiaryPhrase] = [],
         usedStickerIds: [String] = []) {
        self.date = date
        self.text = text
        self.correction = correction
        self.feedback = feedback
        self.nativePhrases = nativePhrases
        self.usedStickerIds = usedStickerIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        correction = Self.blankToNil(try? c.decodeIfPresent(String.self, forKey: .correction))
        feedback = Self.blankToNil(try? c.decodeIfPresent(String.self, forKey: .feedback))
        nativePhrases = ((try? c.decodeIfPresent([DiaryPhrase].self, forKey: .nativePhrases)) ?? nil ?? []).filter { !$0.zh.isEmpty }
        usedStickerIds = (try? c.decodeIfPresent([String].self, forKey: .usedStickerIds)) ?? nil ?? []
    }

    static func blankToNil(_ s: String??) -> String? {
        guard let v = (s ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }
}

/// `native_phrases[]`: the phrase in the learning language, its translation and when it is said (display language).
nonisolated struct DiaryPhrase: Decodable, Sendable, Hashable {
    var zh: String
    var ja: String
    var note: String

    init(zh: String, ja: String, note: String) {
        self.zh = zh
        self.ja = ja
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case zh, ja, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zh = ((try? c.decode(String.self, forKey: .zh)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ja = ((try? c.decode(String.self, forKey: .ja)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        note = ((try? c.decode(String.self, forKey: .note)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The diary pages this account has opened (`journal_entries`), a month at a time; what is typed is kept here at once
/// and saved a moment after the typing stops (`saveMyDiary`). One per app (`shared`): the home's spread, its sheet and
/// the previews read the same pages. The correction (`correctMyJournal`) is not called from the app yet: its design is
/// being made again (owner 2026-10-24).
@MainActor @Observable
final class DiaryStore {
    static let shared = DiaryStore()

    /// Pages by day (`key`).
    private(set) var entries: [String: DiaryEntry] = [:]
    /// Months read (`YYYY-MM`), so a page's month is asked for once.
    private var loadedMonths: Set<String> = []
    private var loadingMonths: Set<String> = []
    /// Days whose text on screen is newer than the server's.
    private(set) var dirty: Set<String> = []
    /// Days being saved right now.
    private(set) var saving: Set<String> = []
    /// The latest save's failure, per day (the page shows it at its top until a save goes through).
    private(set) var saveError: [String: String] = [:]
    /// A month that could not be read.
    private(set) var loadError: String?
    /// The account the pages belong to: another account signed in starts from nothing.
    private var userId: String?
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]

    /// Typing stops this long before the page is saved.
    static let saveDelay: Duration = .seconds(1.2)

    init() {}

    // MARK: Keys

    nonisolated(unsafe) private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated(unsafe) private static let monthFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// The page's key for a day: the phone's own calendar date (the home album's days), `YYYY-MM-DD`.
    nonisolated static func key(_ day: Date) -> String { dayFormat.string(from: day) }
    nonisolated static func monthKey(_ day: Date) -> String { monthFormat.string(from: day) }

    // MARK: Reading

    func entry(for day: Date) -> DiaryEntry? { entries[Self.key(day)] }

    /// Starts over when the signed-in account is not the one the pages were read for.
    private func checkAccount() {
        let uid = SupabaseClient.shared.userId
        guard uid != userId else { return }
        userId = uid
        entries = [:]
        loadedMonths = []
        loadingMonths = []
        dirty = []
        saveError = [:]
        for t in saveTasks.values { t.cancel() }
        saveTasks = [:]
    }

    /// Reads the month of `day` once (the other pages of the spread come with it).
    func loadMonth(of day: Date) async {
        checkAccount()
        guard SupabaseClient.shared.session != nil else { return }
        let month = Self.monthKey(day)
        guard !loadedMonths.contains(month), !loadingMonths.contains(month) else { return }
        loadingMonths.insert(month)
        defer { loadingMonths.remove(month) }
        do {
            let rows = try await NativeAPI.call("listMyDiaryMonth", ["month": month], as: [DiaryEntry].self, timeout: 20)
            guard userId == SupabaseClient.shared.userId else { return }
            for row in rows where !row.date.isEmpty {
                // A page being typed on keeps its newer text; the server's columns still arrive.
                if dirty.contains(row.date), var mine = entries[row.date] {
                    mine.correction = row.correction
                    mine.feedback = row.feedback
                    mine.nativePhrases = row.nativePhrases
                    entries[row.date] = mine
                } else {
                    entries[row.date] = row
                }
            }
            loadedMonths.insert(month)
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? L("日記を読み込めませんでした")
        }
    }

    // MARK: Writing

    /// The text as typed: kept at once, saved after `saveDelay` without more typing.
    func setText(_ text: String, for day: Date) {
        checkAccount()
        let k = Self.key(day)
        var e = entries[k] ?? DiaryEntry(date: k, text: "")
        guard e.text != text else { return }
        e.text = text
        entries[k] = e
        dirty.insert(k)
        saveTasks[k]?.cancel()
        saveTasks[k] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save(day)
        }
    }

    /// Saves the page now (the page closing). True when the server has the text on screen.
    @discardableResult
    func save(_ day: Date) async -> Bool {
        let k = Self.key(day)
        saveTasks[k]?.cancel()
        saveTasks[k] = nil
        guard dirty.contains(k), let e = entries[k] else { return true }
        guard SupabaseClient.shared.session != nil else { return false }
        let text = e.text
        saving.insert(k)
        defer { saving.remove(k) }
        do {
            _ = try await NativeAPI.call("saveMyDiary", ["date": k, "text": text], timeout: 20)
            // Typed on meanwhile: the newer text waits for its own save.
            if entries[k]?.text == text { dirty.remove(k) }
            saveError[k] = nil
            return dirty.contains(k) ? false : true
        } catch {
            saveError[k] = (error as? LocalizedError)?.errorDescription ?? L("日記を保存できませんでした")
            return false
        }
    }

    /// Pages put in by a preview or a test (no server).
    func seedForPreview(_ list: [DiaryEntry]) {
        for e in list { entries[e.date] = e }
        loadedMonths.formUnion(list.map { String($0.date.prefix(7)) })
    }
}
