import SwiftUI

/// One due card of today's review.
struct ReviewCard: Identifiable, Hashable {
    let review: ReviewState
    let sticker: Sticker
    var id: String { review.id ?? review.stickerId }
}

/// A 4-choice option (headword + reading).
struct QuizChoice: Identifiable, Hashable {
    let headword: String
    let zhuyin: String?
    /// Drawn instead of the zhuyin when the learner chose ピンイン (設定 › 発音表記); a Japanese word's is its romaji.
    var pinyin: String? = nil
    var id: String { headword }

    /// This choice with the pinyin it shows: spelled from its zhuyin as the web spells it (Utilities/PinyinZhuyin.swift),
    /// else the word's own (trimmed). Owner 2026-10-11 「設定でピン音にしても復習で注音が表示される。」: the choices carried
    /// no pinyin, so all four kept the zhuyin whatever the setting said. All four are spelled the same way: the bundled
    /// pool (Models/QuizPool.swift) has zhuyin only, and a learner's own pinyin is often written joined ("mángguǒ")
    /// where the spelled one is spaced ("píng guǒ"), which would tell the pool's distractors from the learner's word.
    /// A reading that cannot be spelled and no pinyin of its own: nil, and that word keeps its zhuyin.
    func withPinyin() -> QuizChoice {
        var out = self
        let own = (pinyin ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        out.pinyin = PinyinZhuyin.pinyin(fromZhuyin: zhuyin, want: headword.filter(ZhuyinLayout.isHan).count)
            ?? (own.isEmpty ? nil : own)
        return out
    }
}

/// Today's review queue — reads `reviews` (due_at <= now), grades with srs.ts, writes `reviews` + `review_history`.
@Observable
final class ReviewStore {
    var queue: [ReviewCard] = []
    var index: Int = 0
    var isLoading: Bool = false
    var hasLoaded: Bool = false
    var loadError: String?
    /// Set when a grade could not be saved (the card stays on screen to answer again).
    var gradeError: String?
    var streak: Int = 0
    var doneToday: Int = 0
    var correctCount: Int = 0
    /// Cards answered wrong in this round (offered again at the end, without recording).
    var missed: [ReviewCard] = []
    /// True while going over the missed cards again: nothing is graded or written.
    var isRetry: Bool = false
    /// More cards are due than the daily limit let into this round.
    var moreAvailable: Bool = false
    /// Today's limit is used up while cards are still due (web review-batch.ts "capped").
    var capped: Bool = false
    /// Due cards left after this batch (web `dueRemaining`).
    var dueRemaining: Int = 0
    /// Every review_history row (overall retention line + streak).
    var allHistory: [ReviewHistoryRow] = []
    /// `allHistory` was read from the server (the queue can load while the history read fails: then the empty list
    /// is not this account's history, and the forgetting curve waits for its own read instead of drawing it).
    private(set) var historyLoaded: Bool = false
    /// When the queue was last read: one older than 5 minutes is read again when the review tab opens on its first
    /// card (a word caught meanwhile comes due 10 minutes after its catch).
    private(set) var loadedAt: Date?

    private let client = SupabaseClient.shared

    /// The padding after the learner's own dex: everyday words of the learning language from the bundled pool
    /// (Models/QuizPool.swift), the same category key first, then the same room. No exam levels (owner 2026-10-03:
    /// per-word levels are gone on iOS). It replaces quiz-choices.ts's four fixed words; the pool is far larger,
    /// so a collision with the correct word still leaves 3.
    /// A Mandarin fallback in an English quiz was a reported bug (R3 「4択が学習言語英語なのに台湾華語の単語が混ざってる」):
    /// the pool keeps one list per learning language.
    /// With `correct`, a pool word that could also name the photo (`QuizPool.alsoFits`) is left out.
    static func fallback(for target: String, categoryKey: String? = nil, correct: String? = nil) -> [QuizChoice] {
        QuizPool.ranked(for: target, categoryKey: categoryKey)
            .filter { w in
                guard let correct else { return true }
                return !QuizPool.alsoFits(w.headword, category: w.categoryKey, correct: correct,
                                          correctCategory: categoryKey, target: target)
            }
            .map { QuizChoice(headword: $0.headword, zhuyin: $0.reading) }
    }

    /// The learning language the queue was built for (R5: a switched language must not keep the old cards).
    private(set) var loadedTarget: String = ""

    /// Forget the queue (the learning language changed, or the account signed out).
    func reset() {
        queue = []
        index = 0
        hasLoaded = false
        loadedAt = nil
        choiceCache = [:]
        loadedTarget = ""
        doneToday = 0
        streak = 0
        allHistory = []
        historyLoaded = false
        missed = []
        isRetry = false
        moreAvailable = false
    }

    /// Go over this round's wrong answers once more. Practice only: the schedule was already updated
    /// when they were first answered, so a second answer today must not move it again.
    func startRetry() {
        guard !missed.isEmpty else { return }
        choiceCache = [:]
        queue = missed.shuffled()
        missed = []
        index = 0
        correctCount = 0
        isRetry = true
    }

    /// Keep going past the daily limit: the next batch of due cards.
    func loadMore(dex: DexStore) async {
        await load(dex: dex, limit: doneToday + 20)
    }

    /// 「いま復習する」 on a word's curve: that word becomes the next card — moved up when it is still
    /// waiting in today's queue, added when it is not there (not due yet, or already answered).
    func bringForward(_ sticker: Sticker, review: ReviewState?, currentAnswered: Bool) {
        let at = min(queue.count, currentAnswered ? index + 1 : index)
        if let i = queue.firstIndex(where: { $0.sticker.id == sticker.id }), i >= index {
            if i == index && !currentAnswered { return }
            if i > at { queue.move(fromOffsets: IndexSet(integer: i), toOffset: at) }
            return
        }
        // Without a review row there is nothing to grade (the answer would not be saved).
        guard sticker.word != nil, let r = review, r.id != nil else { return }
        queue.insert(ReviewCard(review: r, sticker: sticker), at: at)
    }

    var current: ReviewCard? { index < queue.count ? queue[index] : nil }

    // MARK: - Ready before the tab opens (owner 2026-10-11: 「復習問題も事前に準備し、タップしたらラグなしで」)

    /// True when reading the queue again now would not pull a card from under the learner: nothing answered in this
    /// round yet (or the round is over), and not a retry of missed words.
    var canRefresh: Bool { !isRetry && (index == 0 || current == nil) }

    /// Reads today's queue ahead of time (right after the dex is read at launch, and when the app comes back), then
    /// puts the next cards' pictures and voices on the phone, so the review shows its first card at once.
    func preload(dex: DexStore, limit: Int) async {
        guard client.session != nil, !isLoading, canRefresh else { return }
        if let at = loadedAt, Date().timeIntervalSince(at) < 60, loadedTarget == NativeAPI.targetLanguage { return }
        await load(dex: dex, limit: limit)
        await prefetchUpcoming(dex: dex)
    }

    /// The review tab opened: a queue read more than 5 minutes ago is read again (on its first card only).
    func refreshIfStale(dex: DexStore, limit: Int) async {
        guard hasLoaded, canRefresh, let at = loadedAt, Date().timeIntervalSince(at) > 300 else { return }
        await load(dex: dex, limit: limit)
        await prefetchUpcoming(dex: dex)
    }

    /// The next cards' pictures (full size, as the quiz shows them) on disk — the first one decoded into memory —
    /// and the voices of their words and choices. Choices are drawn here once, so the card shows the same four.
    func prefetchUpcoming(dex: DexStore, count: Int = 8) async {
        let upcoming = Array(queue.dropFirst(index).prefix(count))
        guard !upcoming.isEmpty else { return }
        for card in upcoming {
            for c in choices(for: card, dex: dex) { SoundService.shared.prefetch(c.headword) }
        }
        let paths = upcoming.compactMap(\.sticker.dexImagePath)
        if let first = paths.first {
            if dex.url(for: first, preferThumb: false) == nil { await dex.prefetchPictures([first]) }
            if let url = dex.url(for: first, preferThumb: false) { _ = await ImageCache.shared.load(url: url, key: first) }
        }
        await dex.prefetchPictures(Array(paths.dropFirst()))
    }

    func load(dex: DexStore, limit: Int) async {
        // Local guest (no account): nothing to review, but the screen must leave its spinner.
        guard client.session != nil else {
            queue = []
            moreAvailable = false
            loadError = nil
            hasLoaded = true
            return
        }
        // The card on screen stays on screen with the same four choices when the queue is read again (a refresh
        // when the tab opens must never swap the card or reshuffle its buttons under the learner's eyes).
        let shownFirst = index == 0 && !isRetry ? current?.id : nil
        isLoading = true
        prefetchDex = dex
        defer { isLoading = false }
        async let historyTask = loadHistory(dex: dex)
        do {
            let now = SupabaseDate.string(Date())
            let enc = DexStore.enc(now)
            // Paged: the server answers at most 1000 rows per request (a big account's due count was cut).
            let rows = try await client.restAll(
                "reviews?select=id,sticker_id,ease,interval_days,repetitions,last_reviewed_at,due_at&due_at=lte.\(enc)&order=due_at.asc,id.asc",
                as: ReviewState.self, decoder: SupabaseDate.decoder
            )
            if !dex.hasLoaded { await dex.load() }
            // Only this learning language's cards (the dex is already filtered), and the daily limit is
            // counted after that filter — not before (R1 「復習の記憶の状態が他の学習言語と混ざってる」).
            let cards = rows.compactMap { r -> ReviewCard? in
                guard let s = dex.sticker(id: r.stickerId), s.word != nil else { return nil }
                return ReviewCard(review: r, sticker: s)
            }
            await historyTask  // doneToday is now this language's count
            // The daily limit reached: nothing more today (web getDueReviews returns [] then), but say so.
            let room = max(0, limit - doneToday)
            var next = Array(cards.prefix(room))
            if let shownFirst, let i = next.firstIndex(where: { $0.id == shownFirst }), i > 0 {
                next.insert(next.remove(at: i), at: 0)
            }
            queue = next
            let kept = Set(next.map(\.sticker.id))
            choiceCache = choiceCache.filter { kept.contains($0.key) }
            capped = room == 0 && !cards.isEmpty
            dueRemaining = cards.count - queue.count
            moreAvailable = dueRemaining > 0
            missed = []
            isRetry = false
            loadedTarget = NativeAPI.targetLanguage
            index = 0
            correctCount = 0
            loadError = nil
            hasLoaded = true
            loadedAt = Date()
        } catch is CancellationError {
            await historyTask
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? L("復習を読み込めませんでした。")
            await historyTask
        }
    }

    private func loadHistory(dex: DexStore) async {
        // Paged (1000 rows per request at most): the streak and today's count need every row.
        guard var rows = try? await client.restAll(
            "review_history?select=sticker_id,reviewed_at,interval_days_after,ease_after&order=reviewed_at.desc,id.desc",
            as: ReviewHistoryRow.self, decoder: SupabaseDate.decoder, maxPages: 50
        ) else { return }
        // Streak, today's count and the retention line: this learning language's words only.
        if !dex.hasLoaded { await dex.load() }
        let mine = Set(dex.stickers.map(\.id))
        if dex.hasLoaded { rows = rows.filter { $0.stickerId.map(mine.contains) ?? false } }
        allHistory = rows
        historyLoaded = true
        let days = Set(rows.map { SRS.taipeiDay($0.reviewedAt) })
        streak = SRS.streak(days: days)
        let today = SRS.taipeiDay(Date())
        doneToday = rows.filter { SRS.taipeiDay($0.reviewedAt) == today }.count
    }

    /// Distractors from the learner's own dex first (same category preferred), then the bundled pool (same category, then same room).
    /// Choices are drawn once per card. Without this the four buttons reshuffled every time the
    /// screen redrew — including right after a tap, so the answer you pressed jumped to another slot.
    @ObservationIgnored private var choiceCache: [String: [QuizChoice]] = [:]

    func choices(for card: ReviewCard, dex: DexStore) -> [QuizChoice] {
        if let cached = choiceCache[card.sticker.id] { return cached }
        let made = makeChoices(for: card, dex: dex)
        choiceCache[card.sticker.id] = made
        return made
    }

    private func makeChoices(for card: ReviewCard, dex: DexStore) -> [QuizChoice] {
        let correct = QuizChoice(headword: card.sticker.word?.headword ?? "", zhuyin: card.sticker.word?.readingZhuyin,
                                 pinyin: card.sticker.word?.pinyin)
        let target = NativeAPI.targetLanguage
        let key = card.sticker.categoryKey
        let others = dex.stickers.compactMap { s -> (QuizChoice, Bool)? in
            guard let w = s.word, w.headword != correct.headword else { return nil }
            // Not another name for what the photo shows (健康便當 → 便當): it would be right too.
            if QuizPool.alsoFits(w.headword, category: s.categoryKey, correct: correct.headword,
                                 correctCategory: key, target: target) { return nil }
            return (QuizChoice(headword: w.headword, zhuyin: w.readingZhuyin, pinyin: w.pinyin), s.categoryKey == key)
        }
        let same = others.filter(\.1).map(\.0).shuffled()
        let rest = others.filter { !$0.1 }.map(\.0).shuffled()
        var out: [QuizChoice] = []
        let pool = Self.fallback(for: target, categoryKey: key, correct: correct.headword)
        // Compared by headword: the same word from the dex and from the pool may carry different readings.
        for c in same + rest + pool where c.headword != correct.headword && !out.contains(where: { $0.headword == c.headword }) {
            out.append(c)
            if out.count == 3 { break }
        }
        // Pinyin for the four drawn only (spelling it for the whole pool on every card would be wasted work).
        return ([correct] + out).map { $0.withPinyin() }.shuffled()
    }

    /// Graded by the web's own `gradeReview` (reviews.functions.ts): the same scoring (correct=5,
    /// −1 when slow, wrong=1), the same interval engine (SM-2 with the Jev guardrails) and the same
    /// history rows as the web — so a word comes due on the same day on the iPhone and on the web.
    /// If the server cannot be reached, nothing is written locally (a half-graded card would drift):
    /// returns false, `gradeError` says why, and the card is not counted as done.
    @discardableResult
    func grade(_ card: ReviewCard, correct: Bool, responseMs: Int, dex: DexStore) async -> Bool {
        gradeError = nil
        if isRetry {
            if correct { correctCount += 1 } else if !missed.contains(where: { $0.id == card.id }) { missed.append(card) }
            return true
        }
        let r = card.review
        let now = Date()
        guard let rid = r.id else { return true }
        struct Graded: Decodable {
            let score: Int?
            let intervalDays: Double?
            enum CodingKeys: String, CodingKey { case score, intervalDays = "interval_days" }
        }
        let graded: Graded
        do {
            graded = try await NativeAPI.call("gradeReview", [
                "review_id": rid,
                "correct": correct,
                "blur_seen": false,
                "response_ms": max(0, responseMs),
            ], as: Graded.self, timeout: 20)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? ""
            gradeError = reason.isEmpty ? L("採点を保存できませんでした。もう一度答えてください。") : L("採点を保存できませんでした。もう一度答えてください。\n\(reason)")
            return false
        }
        if correct { correctCount += 1 } else if !missed.contains(where: { $0.id == card.id }) { missed.append(card) }
        let intervalAfter = graded.intervalDays.map { Int($0.rounded()) } ?? r.intervalDays
        doneToday += 1
        if let row = ReviewHistoryRow(stickerId: r.stickerId, reviewedAt: now, intervalDaysAfter: intervalAfter, easeAfter: r.ease) {
            allHistory.insert(row, at: 0)
        }
        if streak == 0 || !Calendar.current.isDateInToday(now) { streak = max(streak, 1) }
        await dex.reloadReviews()
        return true
    }

    /// 「全体の記憶率（前後2週間）」 for every sticker that has a review row.
    func retentionSeries(dex: DexStore) -> (series: [RetentionPoint], today: Int?) {
        let cards: [RetentionSeries.Card] = dex.stickers.compactMap { s in
            guard let r = dex.reviews[s.id] else { return nil }
            return .init(stickerId: s.id, takenAt: s.takenAt, ease: r.ease, intervalDays: r.intervalDays, lastReviewedAt: r.lastReviewedAt)
        }
        return RetentionSeries.build(cards: cards, history: allHistory)
    }

    func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { index += 1 }
        // The card after next is made ready while this one is answered.
        guard let dex = prefetchDex else { return }
        Task { await prefetchUpcoming(dex: dex, count: 3) }
    }

    /// The dex the queue was read from (for preparing the next cards as the round goes on).
    @ObservationIgnored private weak var prefetchDex: DexStore?

    func history(stickerId: String) async -> [ReviewHistoryRow] {
        guard let data = try? await client.rest(
            "GET",
            "review_history?sticker_id=eq.\(stickerId)&select=reviewed_at,score,interval_days_after,ease_after&order=reviewed_at.asc&limit=200"
        ) else { return [] }
        return (try? SupabaseDate.decoder.decode([ReviewHistoryRow].self, from: data)) ?? []
    }
}
