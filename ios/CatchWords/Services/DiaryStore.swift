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

/// One sentence checked while the diary is written (`checkDiarySentence`, owner 2026-10-25: 「日記を書いてるときに
/// 間違えたら、解説ともに１文ごとやリアルタイムで添削修整」): what is wrong in it (each `wrong` exactly as written, so the
/// page can underline it), and the most natural way to say what the learner meant.
nonisolated struct SentenceCheck: Decodable, Sendable, Hashable {
    nonisolated struct Issue: Decodable, Sendable, Hashable {
        /// The wrong part, as written in the sentence (learning language).
        var wrong: String
        /// How it should be (learning language).
        var fix: String
        /// word / grammar / order / particle / measure / other.
        var kind: String
        /// Why, in the display language.
        var explain: String

        init(wrong: String, fix: String, kind: String, explain: String) {
            self.wrong = wrong
            self.fix = fix
            self.kind = kind
            self.explain = explain
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            wrong = ((try? c.decode(String.self, forKey: .wrong)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            fix = ((try? c.decode(String.self, forKey: .fix)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            kind = (try? c.decode(String.self, forKey: .kind)) ?? "other"
            explain = ((try? c.decode(String.self, forKey: .explain)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        enum CodingKeys: String, CodingKey { case wrong, fix, kind, explain }
    }

    var ok: Bool
    var issues: [Issue]
    /// The most natural way to say it (learning language); empty when the sentence already is.
    var natural: String
    /// Why that is more natural (display language).
    var naturalNote: String

    enum CodingKeys: String, CodingKey {
        case ok, issues, natural
        case naturalNote = "natural_note"
    }

    init(ok: Bool, issues: [Issue], natural: String = "", naturalNote: String = "") {
        self.ok = ok
        self.issues = issues
        self.natural = natural
        self.naturalNote = naturalNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issues = ((try? c.decode([Issue].self, forKey: .issues)) ?? []).filter { !$0.wrong.isEmpty && !$0.fix.isEmpty }
        ok = issues.isEmpty
        natural = ((try? c.decode(String.self, forKey: .natural)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        naturalNote = ((try? c.decode(String.self, forKey: .naturalNote)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Anything to show under the text: something to fix, or a more natural way to say it.
    var hasNote: Bool { !issues.isEmpty || !natural.isEmpty }
}

/// The finished diary's correction (`correctMyJournal`, owner 2026-10-25: 「日記書き終えて、添削ボタン押すと、ユーザーが
/// 言いたいことをもとに最も自然な文を書いてくれる…どんな間違いをしやすいのか、どんな間違いをしたのか、どのような
/// フレーズを使うともっと自然か」). A correction read back later (`listMyDiaryMonth`) has the lists folded into `feedback`.
nonisolated struct DiaryCorrection: Decodable, Sendable, Hashable {
    nonisolated struct Mistake: Decodable, Sendable, Hashable {
        var wrong: String
        var fix: String
        var explain: String

        init(wrong: String, fix: String, explain: String) {
            self.wrong = wrong
            self.fix = fix
            self.explain = explain
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            wrong = ((try? c.decode(String.self, forKey: .wrong)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            fix = ((try? c.decode(String.self, forKey: .fix)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            explain = ((try? c.decode(String.self, forKey: .explain)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        enum CodingKeys: String, CodingKey { case wrong, fix, explain }
    }

    /// The most natural full text of what the learner meant (learning language).
    var natural: String
    /// The coach's words (display language).
    var feedback: String
    var mistakes: [Mistake]
    var tendencies: [String]
    var phrases: [DiaryPhrase]

    enum CodingKeys: String, CodingKey {
        case natural = "correction"
        case feedback = "feedback_ja"
        case mistakes, tendencies
        case phrases = "native_phrases"
    }

    init(natural: String, feedback: String, mistakes: [Mistake] = [], tendencies: [String] = [], phrases: [DiaryPhrase] = []) {
        self.natural = natural
        self.feedback = feedback
        self.mistakes = mistakes
        self.tendencies = tendencies
        self.phrases = phrases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        natural = ((try? c.decode(String.self, forKey: .natural)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        feedback = ((try? c.decode(String.self, forKey: .feedback)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        mistakes = ((try? c.decode([Mistake].self, forKey: .mistakes)) ?? []).filter { !$0.wrong.isEmpty && !$0.fix.isEmpty }
        tendencies = ((try? c.decode([String].self, forKey: .tendencies)) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        phrases = ((try? c.decode([DiaryPhrase].self, forKey: .phrases)) ?? []).filter { !$0.zh.isEmpty }
    }
}

/// Whether the diary is offered: the book's spread, the day's diary page, 振り返る, 添削 and 「日記」 on the home's days.
/// Off for now (owner 2026-10-29: 「日記の機能は一旦対応させない。今すでにある機能だけに絞る」); the code stays.
enum DiaryFeature {
    static let enabled = false
}

/// The diary pages this account has opened (`journal_entries`), a month at a time; what is typed is kept here at once
/// and saved a moment after the typing stops (`saveMyDiary`). One per app (`shared`): the home's spread, its sheet and
/// the previews read the same pages.
///
/// Correcting (owner 2026-10-25): each sentence is checked once when it is finished (`check`, kept by its text so the
/// same sentence is never sent twice); what those checks pointed out — also what the learner then fixed — goes with the
/// finished diary to its correction (`correct`), which explains the day's mistakes and tendencies from it.
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

    /// Sentences checked, by their text, and the ones being checked.
    private(set) var checks: [String: SentenceCheck] = [:]
    private(set) var checking: Set<String> = []
    /// Why checking stopped (no AI consent, the day's limit, no connection, a server without it yet): no more sentences
    /// are sent until the page is opened again (`resumeChecks`).
    private(set) var checkUnavailable: String?
    /// What the checks pointed out, per day, kept even after it is fixed (the correction's notes).
    private var pointedOut: [String: [SentenceCheck.Issue]] = [:]
    /// Finished corrections made in this launch (with their lists), per day; ones being made; failures.
    private(set) var corrections: [String: DiaryCorrection] = [:]
    private(set) var correcting: Set<String> = []
    private(set) var correctError: [String: String] = [:]

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
        checks = [:]
        checking = []
        checkUnavailable = nil
        pointedOut = [:]
        corrections = [:]
        correcting = []
        correctError = [:]
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

    // MARK: Correcting

    /// The sentences of a text, each with whether it is finished (。！？!? or a new line after it); closing quotes and
    /// brackets stay with their sentence.
    nonisolated static func sentences(in text: String) -> [(text: String, finished: Bool)] {
        var out: [(text: String, finished: Bool)] = []
        var current = ""
        var ended = false
        for ch in text {
            if ended, "」』）)\"”’".contains(ch) {
                current.append(ch)
                continue
            }
            if ended || ch.isNewline {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append((t, true)) }
                current = ""
                ended = false
                if ch.isNewline { continue }
            }
            current.append(ch)
            if "。！？!?".contains(ch) { ended = true }
        }
        let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { out.append((t, ended)) }
        return out
    }

    /// Checks one finished sentence once (`before`: what was written before it, for its meaning).
    func check(_ sentence: String, before: String, day: Date) async {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, checks[s] == nil, !checking.contains(s), checkUnavailable == nil,
              SupabaseClient.shared.session != nil else { return }
        checking.insert(s)
        defer { checking.remove(s) }
        do {
            let r = try await NativeAPI.call("checkDiarySentence",
                                             ["sentence": String(s.prefix(300)), "before": String(before.suffix(1500)), "date": Self.key(day)],
                                             as: SentenceCheck.self, timeout: 25)
            checks[s] = r
            if !r.issues.isEmpty { pointedOut[Self.key(day), default: []].append(contentsOf: r.issues) }
        } catch {
            checkUnavailable = (error as? LocalizedError)?.errorDescription ?? L("添削できませんでした")
        }
    }

    /// The page was opened again: checking may try once more.
    func resumeChecks() { checkUnavailable = nil }

    /// The day's correction to show: this launch's (with its lists), else the one read from the server.
    func correction(for day: Date) -> DiaryCorrection? {
        let k = Self.key(day)
        if let c = corrections[k] { return c }
        guard let e = entries[k], let natural = e.correction else { return nil }
        return DiaryCorrection(natural: natural, feedback: e.feedback ?? "", phrases: e.nativePhrases)
    }

    /// Corrects the finished diary: saved first, then sent with what the sentence checks pointed out.
    @discardableResult
    func correct(_ day: Date) async -> Bool {
        let k = Self.key(day)
        guard let text = entries[k]?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !correcting.contains(k) else { return false }
        correcting.insert(k)
        defer { correcting.remove(k) }
        await save(day)
        let notes: [[String: Any]] = (pointedOut[k] ?? []).suffix(40).map {
            ["wrong": String($0.wrong.prefix(80)), "fix": String($0.fix.prefix(80)), "kind": String($0.kind.prefix(20))]
        }
        do {
            let r = try await NativeAPI.call("correctMyJournal", ["draft": String(text.prefix(2000)), "date": k, "notes": notes],
                                             as: DiaryCorrection.self, timeout: 90)
            corrections[k] = r
            if var e = entries[k] {
                e.correction = r.natural
                e.feedback = r.feedback
                e.nativePhrases = r.phrases
                entries[k] = e
            }
            correctError[k] = nil
            return true
        } catch {
            correctError[k] = (error as? LocalizedError)?.errorDescription ?? L("添削できませんでした")
            return false
        }
    }

    /// Checks and a correction put in by a preview or a test (no server).
    func seedChecksForPreview(_ list: [String: SentenceCheck], correction: DiaryCorrection? = nil, on day: Date = Date()) {
        for (k, v) in list { checks[k] = v }
        if let correction { corrections[Self.key(day)] = correction }
    }

    /// Pages put in by a preview or a test (no server).
    func seedForPreview(_ list: [DiaryEntry]) {
        for e in list { entries[e.date] = e }
        loadedMonths.formUnion(list.map { String($0.date.prefix(7)) })
    }
}
