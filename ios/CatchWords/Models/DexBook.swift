import Foundation

/// Dex numbers (owner decision 2026-10-02, #3): the base 100 are No.001–100 (DexCatalog). Every other word the
/// learner catches gets No.101, 102, … in capture order — per learner and learning language, kept on this
/// device so a number never moves or comes back once given (no server change). Words are told apart by their
/// normalized headword, so catching the same word again keeps its number.
enum DexNumbering {
    static func storeKey(uid: String?, lang: String) -> String { "dex.numbers.\(uid ?? "guest").\(lang)" }

    private static func load(_ key: String) -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    /// sticker id → its No. Stickers are numbered oldest first (`taken_at`, then id); new numbers are saved.
    static func assign(_ stickers: [Sticker], lang: String, uid: String?) -> [String: Int] {
        let key = storeKey(uid: uid, lang: lang)
        var saved = load(key)
        var next = max(100, saved.values.max() ?? 100) + 1
        var changed = false
        var out: [String: Int] = [:]
        let ordered = stickers.sorted { $0.takenAt != $1.takenAt ? $0.takenAt < $1.takenAt : $0.id < $1.id }
        for s in ordered {
            let headword = s.word?.headword ?? ""
            if let base = DexCatalog.item(headword: headword, lang: lang)?.baseNo {
                out[s.id] = base
                continue
            }
            let h = DexCatalog.norm(headword, lang: lang)
            let k = h.isEmpty ? "id:\(s.id)" : h
            if let n = saved[k] {
                out[s.id] = n
            } else {
                saved[k] = next
                out[s.id] = next
                next += 1
                changed = true
            }
        }
        if changed { UserDefaults.standard.set(saved, forKey: key) }
        return out
    }

    /// The No. a word gets when it is caught now (the card shows it before the save).
    static func preview(headword: String, stickers: [Sticker], lang: String, uid: String?) -> Int {
        if let base = DexCatalog.item(headword: headword, lang: lang)?.baseNo { return base }
        _ = assign(stickers, lang: lang, uid: uid)
        let saved = load(storeKey(uid: uid, lang: lang))
        let h = DexCatalog.norm(headword, lang: lang)
        if !h.isEmpty, let n = saved[h] { return n }
        return max(100, saved.values.max() ?? 100) + 1
    }
}

/// One square of the dex gallery (`slotHTML`).
struct DexSlot: Identifiable {
    enum Kind {
        /// A caught word: its cut-out or photo, No., name.
        case caught(Sticker)
        /// Not caught yet: the grey silhouette, No. (base items only) and the first-character label.
        case shadow(DexItem)
        /// The landing target of a word that is not a shadow, before the light reaches it: an empty square.
        case pending
    }

    let id: String
    let no: Int?
    let kind: Kind
}

/// One category card of the gallery (`.dcat`): caught words (by No.), then the current shadows.
struct DexSection: Identifiable {
    let category: DexCategory
    let slots: [DexSlot]
    let caughtCount: Int
    var id: Int { category.no }
}

/// The category-shadow gallery (prototype `renderDex` grid, with the owner's 20 categories and shadows).
enum DexBook {
    /// Shadows shown per category (owner: 3–5; the first 5 items not caught yet, in catalog order).
    static let shadowCount = 5

    /// Where a caught word sits: its catalog item's category, else its category key's (`Sticker.categoryKey`).
    static func category(of s: Sticker, lang: String) -> Int {
        if let it = DexCatalog.item(headword: s.word?.headword, lang: lang) { return it.category }
        return DexCatalog.category(forKey: s.categoryKey)
    }

    /// The landing word while its light is on the way. Owner 2026-10-11 (「ナンバーが小さいものをキャッチしたときに、
    /// 古い単語を横切るアニメーションではなく、図鑑に追加するときに、事前にもとの古い番号が高い単語の位置を1つ右に移動し、
    /// 新しい単語はその左に入るようにして」): the star no longer lands after the caught words and the word then jumps
    /// to its place by No. across them. First (`room` false, while the dex page rises) the gallery is drawn as it was
    /// before the catch; then the room is made (`room` true, animated by DexView): the words numbered after it move
    /// one square to the right, its shadow fades from the shadows and the next one refills (as after the landing), and
    /// its own square waits at its place (its silhouette, or an empty square). The star lands in that square, which
    /// then simply fills (same id, same place).
    struct Hold: Equatable {
        let stickerId: String
        var room: Bool = false
    }

    /// One sticker per word, newest first (the prototype's `addEntry` keeps one entry per word: `S.dex`).
    static func words(_ stickers: [Sticker], lang: String) -> [Sticker] {
        var seen = Set<String>()
        var out: [Sticker] = []
        for s in stickers.sorted(by: { $0.takenAt > $1.takenAt }) {
            let h = DexCatalog.norm(s.word?.headword ?? "", lang: lang)
            let k = h.isEmpty ? "id:\(s.id)" : h
            if seen.insert(k).inserted { out.append(s) }
        }
        return out
    }

    static func sections(stickers: [Sticker], numbers: [String: Int], lang: String, hold: Hold?) -> [DexSection] {
        // One square per word: the newest sticker wins.
        var words = Self.words(stickers, lang: lang)
        let held = hold.flatMap { h in words.first { $0.id == h.stickerId } }
        if let held { words.removeAll { $0.id == held.id } }

        var byCategory: [Int: [Sticker]] = [:]
        var caughtItems = Set<String>()
        for s in words {
            byCategory[category(of: s, lang: lang), default: []].append(s)
            if let it = DexCatalog.item(headword: s.word?.headword, lang: lang) { caughtItems.insert(it.id) }
        }
        let heldCategory = held.map { category(of: $0, lang: lang) }
        let heldItem = held.flatMap { DexCatalog.item(headword: $0.word?.headword, lang: lang) }
        // Room made: the word already counts as caught for the shadows (its own shadow goes, the next one refills),
        // exactly as they will be once it has landed — so nothing moves when it lands.
        let room = held != nil && hold?.room == true
        if room, let it = heldItem { caughtItems.insert(it.id) }

        return DexCatalog.withOther.map { c in
            let caught = (byCategory[c.no] ?? []).sorted {
                let a = numbers[$0.id] ?? Int.max, b = numbers[$1.id] ?? Int.max
                return a != b ? a < b : $0.takenAt < $1.takenAt
            }
            var slots = caught.map { DexSlot(id: $0.id, no: numbers[$0.id], kind: .caught($0)) }
            let shadows = c.items.filter { !caughtItems.contains($0.id) }.prefix(shadowCount).map {
                DexSlot(id: "i:\($0.id)", no: $0.baseNo, kind: .shadow($0))
            }
            if room, let held, heldCategory == c.no {
                // Its square where the sort above will put it (after the words with the same or a lower No., as the
                // newest of them); the words numbered after it are one square to the right. It waits as its grey
                // silhouette (a word outside the catalog: an empty square) under its own id, so the light lands in it
                // and it fills in place.
                let no = numbers[held.id] ?? Int.max
                let at = caught.firstIndex { (numbers[$0.id] ?? Int.max) > no } ?? caught.count
                let waiting: DexSlot.Kind = heldItem.map { DexSlot.Kind.shadow($0) } ?? .pending
                slots.insert(DexSlot(id: held.id, no: numbers[held.id] ?? heldItem?.baseNo, kind: waiting), at: at)
            }
            slots += shadows
            // "n / m" counts words: one caught slot per word (`mine.length / mine.length + shadows (+ pending)`).
            return DexSection(category: c, slots: slots, caughtCount: caught.count)
        }
        // その他 only when a word is in it.
        .filter { $0.category.no != DexCatalog.otherNo || !$0.slots.isEmpty }
    }

    /// Base items caught (the header's 影 n / 100).
    static func baseCaught(_ stickers: [Sticker], lang: String) -> Int {
        Set(stickers.compactMap { s -> String? in
            guard let it = DexCatalog.item(headword: s.word?.headword, lang: lang), it.baseNo != nil else { return nil }
            return it.id
        }).count
    }

    /// The shadow's label. Owner decision 2026-10-03: show the whole headword (咖啡), not 咖？ — the grey
    /// silhouette and the grey text already say "not caught yet".
    static func shadowLabel(_ headword: String, lang: String) -> String { headword }
}
