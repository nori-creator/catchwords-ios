import Foundation

/// When the app praises the learner after a catch, and when it then asks for an App Store review (owner 2026-10-25:
/// 「ランダムで…ユーザーを褒める…祝福のアニメーション」「頻繁にその演出を出すと慣れるから、必ず頻度を絞って」「褒めた後に…
/// 次の単語を取ったときに、このアプリのレビューをお願いします」).
///
/// The rules, and the research each one leans on:
/// - **Rare and unpredictable.** After the first praise, one comes only when at least `minCatchesBetween` new words and
///   `minDaysBetween` days have passed, and even then only by chance (`chance`). A reward on a variable schedule keeps its
///   pull (Ferster & Skinner 1957, variable-ratio reinforcement); the same praise every time is soon not felt at all
///   (hedonic adaptation — Frederick & Loewenstein 1999). The floor keeps it rare however often the learner catches.
/// - **Early, once.** The first praise comes on the `firstAt`-th word: the learner has a little to be proud of, and an
///   early sense of progress keeps people going (the endowed-progress effect — Nunes & Drèze 2006).
/// - **Praise, then ask.** The review is asked on the very next new word after a praise, never out of the blue: the
///   learner has just had a good moment and then a second one (a catch). People judge an experience by its best moment
///   and its end (the peak-end rule — Kahneman et al. 1993), and a good turn makes a request welcome (reciprocity —
///   Cialdini). The ask is the system's own sheet (App Review Guideline 5.6.1 forbids custom review prompts; iOS itself
///   shows it at most 3 times in 365 days), asked again at most every `reviewEvery` days.
/// - **Never during the first tour**, and never a sheet over a sheet: a praise waits for the catch's landing to end.
///
/// Kept per account on the device (`praise.v1.<userId>`), like `OnboardingState`. Nothing here reaches the server.
nonisolated struct PraiseSchedule: Codable, Equatable {
    /// New words caught on this device since the schedule began (re-encounters do not count).
    var catches = 0
    /// New words since the last praise.
    var sinceLastPraise = 0
    var lastPraiseAt: Date?
    var praiseCount = 0
    /// The last kinds shown (newest last): the next praise is a different one (novelty keeps it felt).
    var recentKinds: [String] = []
    /// A praise was shown: the next new word asks for the review.
    var reviewDue = false
    var lastReviewAskAt: Date?

    static let firstAt = 3
    static let minCatchesBetween = 5
    static let minDaysBetween = 3.0
    static let chance = 0.4
    static let reviewEvery = 120.0

    enum Decision: Equatable { case none, praise, askReview }

    /// One new word was caught (`totalWords`: the learner's words now, this one included). `roll` is a number in 0..<1.
    mutating func noteCatch(totalWords: Int, now: Date = Date(), roll: Double = Double.random(in: 0..<1)) -> Decision {
        catches += 1
        sinceLastPraise += 1
        if reviewDue {
            reviewDue = false
            lastReviewAskAt = now
            return .askReview
        }
        let due: Bool
        if praiseCount == 0 {
            due = totalWords >= Self.firstAt
        } else if let last = lastPraiseAt {
            let days = now.timeIntervalSince(last) / 86_400
            due = sinceLastPraise >= Self.minCatchesBetween && days >= Self.minDaysBetween && roll < Self.chance
        } else {
            due = false
        }
        return due ? .praise : .none
    }

    /// The praise was shown (`kind`): the clock starts again, and the next new word asks for a review unless one was
    /// asked within `reviewEvery` days.
    mutating func notePraised(kind: String, now: Date = Date()) {
        praiseCount += 1
        sinceLastPraise = 0
        lastPraiseAt = now
        recentKinds = Array((recentKinds + [kind]).suffix(2))
        if let asked = lastReviewAskAt, now.timeIntervalSince(asked) / 86_400 < Self.reviewEvery {
            reviewDue = false
        } else {
            reviewDue = true
        }
    }

    // MARK: Storage (per account)

    static func storageKey(for userId: String?) -> String { "praise.v1.\(userId ?? "anon")" }

    static func load(userId: String?) -> PraiseSchedule {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: userId)),
              let s = try? JSONDecoder().decode(PraiseSchedule.self, from: data) else { return PraiseSchedule() }
        return s
    }

    func save(userId: String?) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey(for: userId))
    }

    /// Account deletion: that account's schedule.
    static func removeRecord(userId: String?) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: userId))
    }
}

/// `getMyStanding` (server `standing.functions.ts`): where the learner stands among everyone who has caught a word.
/// Only the learner's own counts and ranks come back.
nonisolated struct MyStanding: Decodable, Equatable {
    struct Rank: Decodable, Equatable {
        let rank: Int
        let total: Int
        let topPercent: Int
        let count: Int
        var key: String? = nil
    }
    let words: Rank?
    let activeDays: Rank?
    let category: Rank?
    let firstCatcher: Bool
}

/// What one praise says. Built from the standing (when the server answered) and what the device knows.
nonisolated struct PraiseMoment: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case firstCatcher, wordsTop, daysTop, categoryTop, totalWords, months }

    let id = UUID()
    let kind: Kind
    /// The big number counts from `from` to `to` (a rank or a top % counts down, a total counts up).
    let from: Int
    let to: Int
    /// The line above the number.
    let title: String
    /// The big number in its words (「上位3%」「12語」…), for any value while it counts.
    let format: @Sendable (Int) -> String
    /// The line under the number.
    let caption: String
    /// What the learner did to get here (praise the effort, not the person — Mueller & Dweck 1998), or the next goal.
    let note: String

    static func == (a: PraiseMoment, b: PraiseMoment) -> Bool { a.id == b.id }

    /// A comparison with others is shown only when it flatters and means something: at least `minPeople` to compare
    /// with, and the learner in the top `maxTopPercent` (social comparison lifts only when it goes your way —
    /// Festinger 1954; a vague "you're great" convinces less than a true, specific number).
    static let minPeople = 5
    static let maxTopPercent = 30

    /// The praises this catch could show, strongest first.
    static func options(standing: MyStanding?, headword: String, totalWords: Int, start: Date?, now: Date = Date()) -> [PraiseMoment] {
        var out: [PraiseMoment] = []
        let note = effortNote(totalWords)
        if let s = standing {
            if s.firstCatcher, (s.words?.total ?? 0) >= 3, !headword.isEmpty {
                out.append(PraiseMoment(kind: .firstCatcher, from: 1, to: 1,
                                        title: L("「\(headword)」を獲得したのは"),
                                        format: { L("\($0)人目") },
                                        caption: L("全ユーザーの中で、あなたが初めてです"),
                                        note: note))
            }
            if let w = s.words, w.total >= minPeople, w.topPercent <= maxTopPercent {
                out.append(PraiseMoment(kind: .wordsTop, from: 100, to: w.topPercent,
                                        title: L("集めた単語の数は"),
                                        format: { L("上位\($0)%") },
                                        caption: w.rank <= 100 ? L("全ユーザーの中で\(w.rank)位") : L("全ユーザーの中で"),
                                        note: note))
            }
            if let d = s.activeDays, d.total >= minPeople, d.topPercent <= maxTopPercent {
                let byRank = d.rank <= 10
                let rankText: @Sendable (Int) -> String = { L("\($0)位") }
                let topText: @Sendable (Int) -> String = { L("上位\($0)%") }
                out.append(PraiseMoment(kind: .daysTop, from: byRank ? min(d.total, 50) : 100, to: byRank ? d.rank : d.topPercent,
                                        title: L("学んだ日数は"),
                                        format: byRank ? rankText : topText,
                                        caption: L("\(d.count)日、続けてきました"),
                                        note: L("続けてきたことが、いちばんの力です")))
            }
            if let c = s.category, let key = c.key, c.total >= minPeople, c.count >= 3, c.topPercent <= maxTopPercent {
                let label = Category.label(for: key)
                out.append(PraiseMoment(kind: .categoryTop, from: 100, to: c.topPercent,
                                        title: L("\(label)の単語の数は"),
                                        format: { L("上位\($0)%") },
                                        caption: L("\(label)の単語を\(c.count)語集めました"),
                                        note: note))
            }
        }
        if let start {
            let months = Calendar.current.dateComponents([.month], from: start, to: now).month ?? 0
            if months >= 1 {
                out.append(PraiseMoment(kind: .months, from: 0, to: months,
                                        title: L("使い始めて"),
                                        format: { L("\($0)か月") },
                                        caption: L("\(totalWords)語を集めました"),
                                        note: L("続けてきたことが、いちばんの力です")))
            }
        }
        if totalWords > 0 {
            let next = nextGoal(after: totalWords)
            out.append(PraiseMoment(kind: .totalWords, from: 0, to: totalWords,
                                    title: L("これまでに獲得した単語"),
                                    format: { L("\($0)語") },
                                    caption: L("次の目標の\(next)語まで、あと\(next - totalWords)語"),
                                    note: note))
        }
        return out
    }

    /// One of `options`: never one of the last two kinds when another is there; a first catch (rare, and true only now)
    /// most of the time; a comparison with others twice as often as a count of one's own.
    static func pick(_ options: [PraiseMoment], recent: [String], roll: Double = Double.random(in: 0..<1)) -> PraiseMoment? {
        let fresh = options.filter { !recent.contains($0.kind.rawValue) }
        let pool = fresh.isEmpty ? options : fresh
        if let first = pool.first(where: { $0.kind == .firstCatcher }), roll < 0.6 { return first }
        let weighted = pool.flatMap { m -> [PraiseMoment] in
            switch m.kind {
            case .wordsTop, .daysTop, .categoryTop, .firstCatcher: [m, m]
            case .totalWords, .months: [m]
            }
        }
        guard !weighted.isEmpty else { return nil }
        let i = min(weighted.count - 1, Int(roll * Double(weighted.count)))
        return weighted[i]
    }

    /// The next round number of words (the goal-gradient effect: a near goal pulls harder — Kivetz et al. 2006).
    static func nextGoal(after n: Int) -> Int {
        let steps = [5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 500, 750, 1000]
        return steps.first(where: { $0 > n }) ?? ((n / 500) + 1) * 500
    }

    private static func effortNote(_ n: Int) -> String {
        [L("1枚ずつ撮り続けてきた積み重ねです"),
         L("身の回りのものが、少しずつ言葉になっています"),
         L("毎日の小さな1枚が、ここまで来ました")][abs(n) % 3]
    }
}
