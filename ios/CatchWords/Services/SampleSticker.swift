import Foundation
import UIKit

/// The sample word 珍珠奶茶 a new account finds in its home album, dex and review before its first photo (owner
/// 2026-10-28: 「ユーザーが1枚目の写真を撮る前から、一つの画像を実際にホーム画面、図鑑、復習に情報を入れておく。これによってカメラを
/// 撮る前から、アプリの理解がしやすい。バブルティーの画像入れて」).
///
/// It is bundled with the app and lives on the phone only: never sent to the server, no AI call, no review row
/// (its grades are kept here, `grade`). It is made like a 保存待ち entry (`DexStore.addProvisional`): a `Sticker` with
/// `wordId: ""` (which turns the page's AI paths off), its pictures under paths the image cache answers from the bundle
/// (`ImageCache.file(for:)` → `bundledImageURL`), a `Word` decoded from `sample_word.json` and resolved for the reader's
/// language like every other word. It stays after the tour, marked 「見本」, and the learner can delete it (then it never
/// comes back for that account, `markDeleted`).
enum SampleSticker {
    /// Ids that start so are samples (`Sticker.isSample`); never a server id.
    nonisolated static let prefix = "sample-"
    static let id = prefix + "bubbletea"
    /// The paths the pictures are known by in the image cache (answered from the bundle, never signed).
    nonisolated static let cutoutPath = "sample/bubbletea-cutout.png"
    nonisolated static let photoPath = "sample/bubbletea-photo.jpg"
    nonisolated private static let bundled: [String: (name: String, ext: String)] = [
        cutoutPath: ("sample_sticker_bubbletea", "png"),
        photoPath: ("sample_photo_bubbletea", "jpg"),
    ]

    /// The bundled file for a sample picture path (nil for any other key).
    nonisolated static func bundledImageURL(for key: String) -> URL? {
        guard let b = bundled[key] else { return nil }
        return Bundle.main.url(forResource: b.name, withExtension: b.ext)
    }

    /// Whether `path` is one of the sample's pictures (left out of signing and uploads).
    nonisolated static func isSamplePath(_ path: String) -> Bool { bundled[path] != nil }

    private static var imageCache: [String: UIImage] = [:]

    /// The cut-out (or with `photo` the photo), for the screens that draw it outside the dex (the ready screen's hero).
    static func image(photo: Bool = false) -> UIImage? {
        let key = photo ? photoPath : cutoutPath
        if let c = imageCache[key] { return c }
        guard let url = bundledImageURL(for: key), let img = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[key] = img
        return img
    }

    // MARK: Per-account records (this phone)

    private static func key(_ what: String, _ uid: String) -> String { "sample.\(what).\(uid)" }

    /// Onboarding finished: the sample is this account's from now (and the day it was added is its catch day).
    static func markAdded(userId uid: String?) {
        guard let uid else { return }
        let d = UserDefaults.standard
        d.set(true, forKey: key("added", uid))
        if d.object(forKey: key("addedAt", uid)) == nil { d.set(Date().timeIntervalSince1970, forKey: key("addedAt", uid)) }
    }

    /// The learner deleted it: gone for good on this account.
    static func markDeleted(userId uid: String?) {
        guard let uid else { return }
        UserDefaults.standard.set(true, forKey: key("deleted", uid))
    }

    static func isEnabled(userId uid: String?) -> Bool {
        guard let uid else { return false }
        let d = UserDefaults.standard
        return d.bool(forKey: key("added", uid)) && !d.bool(forKey: key("deleted", uid))
    }

    static func addedAt(userId uid: String) -> Date {
        let t = UserDefaults.standard.double(forKey: key("addedAt", uid))
        return t > 0 ? Date(timeIntervalSince1970: t) : Date()
    }

    /// Account deletion: nothing of it stays.
    static func removeRecords(userId uid: String?) {
        guard let uid else { return }
        for what in ["added", "addedAt", "deleted", "review"] { UserDefaults.standard.removeObject(forKey: key(what, uid)) }
    }

    // MARK: The word

    private static let json: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "sample_word", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }()

    static var headword: String { json?["headword"] as? String ?? "珍珠奶茶" }  // l10n-ignore (learning-language headword)
    static var zhuyin: String { json?["reading_zhuyin"] as? String ?? "" }
    static var pinyin: String { json?["pinyin"] as? String ?? "" }

    /// The sticker as `reader` should see it (the notes in that display language; English, then Japanese, when the
    /// file has no block for it). nil only when the bundled file is unreadable.
    static func make(reader: String, takenAt: Date) -> Sticker? {
        guard let j = json, let word = makeWord(j, reader: reader) else { return nil }
        return Sticker(id: id, wordId: "", objectImageUrl: photoPath, cutoutImageUrl: cutoutPath, selfieImageUrl: nil,
                       caption: nil, locationName: nil, takenAt: takenAt, captureType: "photo", word: word,
                       lat: place.lat, lng: place.lng)
    }

    /// Where it was "caught": 西門町 in Taipei, so the dex's map has its pin like every other view has the sample (owner
    /// 2026-10-29: 「すべての図鑑の種類で事前に入れた画像が表示されるようにして。マップは適当に台北市内にして」). The place's name is
    /// read from the point in the display language, as for a real catch (`LocalizedPlaceText`).
    nonisolated static let place = (lat: 25.0421, lng: 121.5076)

    private static func makeWord(_ j: [String: Any], reader: String) -> Word? {
        let texts = j["text"] as? [String: [String: String]] ?? [:]
        guard let t = texts[reader] ?? texts["en"] ?? texts["ja"] else { return nil }
        func s(_ k: String) -> String { t[k] ?? "" }
        let head = j["head_part"] as? [String: Any] ?? ["text": headword, "pos": "N"]
        var chunks: [[String: Any]] = []
        for (i, c) in (j["chunks"] as? [[String: Any]] ?? []).enumerated() {
            guard var slot = c["slot"] as? [String: Any] else { continue }
            let jaKey = slot.removeValue(forKey: "ja_key") as? String ?? ""
            slot["ja"] = s(jaKey)
            slot["slot"] = true
            slot["alts"] = (c["alts"] as? [[String: Any]] ?? []).map { a -> [String: Any] in
                var a = a
                let k = a.removeValue(forKey: "ja_key") as? String ?? ""
                a["ja"] = s(k)
                return a
            }
            chunks.append(["parts": [head, slot], "ja": s("chunk\(i + 1)"), "note": s("note\(i + 1)")])
        }
        func parts(_ key: String) -> [[String: Any]] {
            (j[key] as? [[String]] ?? []).map { ["text": $0.first ?? "", "pos": $0.first == headword ? "N" : "X"] }
        }
        var measure = j["measure_word"] as? [String: Any] ?? [:]
        measure["note"] = s("measure")
        let related = (j["related"] as? [[String: Any]] ?? []).map { r -> [String: Any] in
            let k = r["key"] as? String ?? ""
            return ["word": r["word"] ?? "", "kind": "rel", "reading": r["reading"] ?? "", "gloss": s(k + "g"), "note": s(k + "n")]
        }
        let obj: [String: Any] = [
            "id": "sample-word", "headword": headword, "reading_zhuyin": zhuyin, "pinyin": pinyin,
            "language": "zh-TW", "category_key": j["category_key"] ?? "drink",
            "meaning_ja": s("meaning"),
            "example_sentence": j["example_sentence"] ?? "", "example_translation": s("ex1"),
            "extras": [
                "explain_lang": reader,
                "usage_chunks": chunks,
                "example_chunks": parts("example_chunks"),
                "examples_extra": [["zh": j["example_extra_zh"] ?? "", "ja": s("ex2"), "chunks": parts("example_extra_chunks")]],
                "example_pattern_count": 2,
                "measure_words": [measure],
                "related_words": related,
                "taiwan_note": s("taiwan"),
            ] as [String: Any],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let w = try? JSONDecoder().decode(Word.self, from: data) else { return nil }
        return ReaderLanguage.resolve(w, explanation: nil, readerMeaning: nil, reader: reader)
    }

    /// The example sentences' readings, put where the word page reads them (the server's dictionary is not asked).
    static func seedReadings() {
        for r in json?["readings"] as? [[String: Any]] ?? [] {
            guard let sentence = r["sentence"] as? String, let raw = r["units"] as? [[String: Any]] else { continue }
            let units = raw.map { SentenceUnit(char: $0["char"] as? String ?? "", pinyin: $0["pinyin"] as? String,
                                               zhuyin: $0["zhuyin"] as? String) }
            SentenceReadings.shared.seed(sentence, units: units)
        }
    }

    // MARK: Its review (kept on this phone; `ReviewStore.grade` never sends it)

    nonisolated private struct Kept: Codable {
        var ease: Double
        var intervalDays: Int
        var repetitions: Int
        var lastReviewedAt: Date?
        var dueAt: Date
        /// The learner's own answers on it, oldest first (its curve draws them after the story's). Absent in what was
        /// kept before it was written.
        var log: [Answer]?
    }

    nonisolated private struct Answer: Codable {
        var at: Date
        var intervalDays: Int
        var ease: Double
    }

    /// Its story of reviews: learned some days before it was added and reviewed three times, 1, 3 and 8 days after (each
    /// wait longer than the last), each answer scored like a right one (`SRS.next`, 5). So its memory curve shows what reviewing does — back
    /// to 100% at each review, a gentler slope each time — and the next review falls due on the day it is added (owner
    /// 2026-10-29: 「何回か復習した時のグラフを表示して。復習したら100％になり、グラフの傾きが緩やかになること、また最適な
    /// 復習なタイミングがわかることをユーザーに見せたい」).
    nonisolated private static let storyDays: [Double] = [1, 3, 8]

    private struct Story {
        let learnedAt: Date
        let rows: [(at: Date, state: SRS.State)]
    }

    private static func story(addedAt: Date) -> Story {
        var state = SRS.State(ease: 2.5, intervalDays: 0, repetitions: 0)
        var steps: [(day: Double, state: SRS.State)] = []
        var previous = 0.0
        for day in storyDays {
            state = SRS.next(state, score: 5, elapsedDays: steps.isEmpty ? nil : day - previous)
            steps.append((day, state))
            previous = day
        }
        // The last review's interval runs out on the day the sample is added: it is due then.
        let span = previous + Double(state.intervalDays)
        let learnedAt = addedAt.addingTimeInterval(-span * 86_400)
        return Story(learnedAt: learnedAt, rows: steps.map { (at: learnedAt.addingTimeInterval($0.day * 86_400), state: $0.state) })
    }

    private static func addedAt(_ uid: String?) -> Date { uid.map { addedAt(userId: $0) } ?? Date() }

    /// When its story starts: where its memory curve begins (before the day it was added).
    static func learnedAt(userId uid: String?) -> Date { story(addedAt: addedAt(uid)).learnedAt }

    /// Its reviews for the memory curve: the story's three, then the learner's own.
    static func history(userId uid: String?) -> [ReviewHistoryRow] {
        let told = story(addedAt: addedAt(uid)).rows.compactMap {
            ReviewHistoryRow(stickerId: id, reviewedAt: $0.at, intervalDaysAfter: $0.state.intervalDays, easeAfter: $0.state.ease)
        }
        let own = (uid.flatMap { load($0) }?.log ?? []).compactMap {
            ReviewHistoryRow(stickerId: id, reviewedAt: $0.at, intervalDaysAfter: $0.intervalDays, easeAfter: $0.ease)
        }
        return told + own
    }

    /// Its review state: after the story (due 10 minutes after it was added, so the first review finds a card) until
    /// the learner grades it.
    static func reviewState(userId uid: String?) -> ReviewState {
        let added = addedAt(uid)
        let last = story(addedAt: added).rows.last
        let told = Kept(ease: last?.state.ease ?? 2.5, intervalDays: last?.state.intervalDays ?? 0,
                        repetitions: last?.state.repetitions ?? 0, lastReviewedAt: last?.at,
                        dueAt: added.addingTimeInterval(600))
        let kept = uid.flatMap { load($0) } ?? told
        return ReviewState(id: nil, stickerId: id, ease: kept.ease, intervalDays: kept.intervalDays,
                           repetitions: kept.repetitions, lastReviewedAt: kept.lastReviewedAt, dueAt: kept.dueAt)
    }

    /// One answer, scored as the server scores (`SRS.next`: correct 5, wrong 1), kept for the next time.
    @discardableResult
    static func grade(userId uid: String, correct: Bool, now: Date = Date()) -> ReviewState {
        let before = reviewState(userId: uid)
        let elapsed = before.lastReviewedAt.map { now.timeIntervalSince($0) / 86_400 }
        let next = SRS.next(SRS.State(ease: before.ease, intervalDays: before.intervalDays, repetitions: before.repetitions ?? 0),
                            score: correct ? 5 : 1, elapsedDays: elapsed)
        let log = (load(uid)?.log ?? []) + [Answer(at: now, intervalDays: next.intervalDays, ease: next.ease)]
        let kept = Kept(ease: next.ease, intervalDays: next.intervalDays, repetitions: next.repetitions, lastReviewedAt: now,
                        dueAt: now.addingTimeInterval(Double(max(1, next.intervalDays)) * 86_400), log: log)
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: key("review", uid)) }
        return reviewState(userId: uid)
    }

    private static func load(_ uid: String) -> Kept? {
        guard let data = UserDefaults.standard.data(forKey: key("review", uid)) else { return nil }
        return try? JSONDecoder().decode(Kept.self, from: data)
    }
}

extension Sticker {
    /// The bundled sample word (`SampleSticker`): on this phone only, never on the server.
    nonisolated var isSample: Bool { id.hasPrefix(SampleSticker.prefix) }
}
