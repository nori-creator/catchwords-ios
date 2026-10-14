import Foundation

/// Zhuyin → pinyin, ported from the web's `pinyin-zhuyin.ts` (`parseZhuyin` + `syllablesToPinyin`) so a reading spelled
/// here reads exactly as the web spells it: one space between syllables, the tone mark on a or e first, on the o of
/// ou, otherwise on the last vowel; ü kept after n/l and written u after j/q/x/y; a neutral tone (˙) left unmarked.
/// Pure functions, no UI.
///
/// Why: owner 2026-10-11 「設定でピン音にしても復習で注音が表示される。」 — the review quiz's bundled pool
/// (Models/QuizPool.swift) carries zhuyin only, so with ピンイン chosen (設定 › 発音表記) its choices kept the zhuyin.
/// Spelling the pinyin from the zhuyin lets every choice follow the setting.
nonisolated enum PinyinZhuyin {
    /// One syllable: its spelling without a tone mark, and its tone (1–4; 5 = neutral).
    typealias Syllable = (base: String, tone: Int)

    /// A zhuyin reading → pinyin with tone marks: 「ㄇㄤˊ ㄍㄨㄛˇ」 → 「máng guǒ」, 「ㄐㄩㄝˊ ˙ㄉㄜ」 → 「jué de」.
    /// `want` is the number of syllables expected (the headword's Han characters): it decides how syllables written
    /// together without a space are cut. nil when any part is not zhuyin (kana, IPA, a typo), so the caller keeps
    /// the zhuyin.
    static func pinyin(fromZhuyin text: String?, want: Int = 0) -> String? {
        guard let text, let syllables = parseZhuyin(text, want: want) else { return nil }
        return syllables.map { format($0) }.joined(separator: " ")
    }

    /// web `parseZhuyin` (+ `splitReading`): cut the reading at spaces and commas, then each run into syllables.
    /// When some cut gives exactly `want` syllables, that one (earlier runs cut into as few as they can be);
    /// otherwise every run in as few syllables as it can be. nil when a run cannot be read.
    static func parseZhuyin(_ text: String, want: Int = 0) -> [Syllable]? {
        let runs = text.split(whereSeparator: { $0.isWhitespace || ",，、".contains($0) }).map { String($0) }
        guard !runs.isEmpty else { return nil }
        let options = runs.map { cuts(of: $0) }
        guard !options.contains(where: { $0.isEmpty }) else { return nil }
        let counts = options.map { $0.keys.sorted() }
        // reach[i]: every syllable total the runs from i on can make.
        var reach = Array(repeating: Set<Int>(), count: runs.count + 1)
        reach[runs.count] = [0]
        for i in stride(from: runs.count - 1, through: 0, by: -1) {
            for c in counts[i] {
                for r in reach[i + 1] { reach[i].insert(c + r) }
            }
        }
        var out: [Syllable] = []
        if want > 0, reach[0].contains(want) {
            var left = want
            for i in runs.indices {
                guard let c = counts[i].first(where: { reach[i + 1].contains(left - $0) }), let part = options[i][c] else { return nil }
                out += part
                left -= c
            }
            return out
        }
        for i in runs.indices {
            guard let c = counts[i].first, let part = options[i][c] else { return nil }
            out += part
        }
        return out
    }

    // MARK: - Pinyin cut per syllable (one over each character)

    /// A pinyin reading cut into exactly `want` syllables, each kept as written (tone marks and all):
    /// 「shǒu biǎo」 → [shǒu, biǎo], 「mángguǒ」 → [máng, guǒ], 「Xī'ān」 → [Xī, ān]. Written runs are cut where
    /// spaces, apostrophes, hyphens or middle dots are; a run written together is cut into real syllables (the
    /// inventory below), as few as possible unless that misses `want`. nil when the reading cannot give `want` syllables
    /// (the caller then keeps one line over the whole word). Owner 2026-10-14: 「ピンインはなるべく、それぞれの漢字のうえに」.
    static func syllables(ofPinyin text: String?, want: Int) -> [String]? {
        guard let text, want > 0 else { return nil }
        let runs = text.split(whereSeparator: { $0.isWhitespace || "'’‘-‐·・,，、".contains($0) }).map { Array($0) }
        guard !runs.isEmpty else { return nil }
        if runs.count == want { return runs.map { String($0) } }
        // Every way to cut each run, by syllable count (from the end, as `cuts(of:)` does for zhuyin).
        var options: [[Int: [String]]] = []
        for run in runs {
            let base = run.map { baseLetter($0) }
            var suffix = Array(repeating: [Int: [String]](), count: run.count + 1)
            suffix[run.count] = [0: []]
            for i in stride(from: run.count - 1, through: 0, by: -1) {
                var here: [Int: [String]] = [:]
                for len in stride(from: min(6, run.count - i), through: 1, by: -1) {
                    guard pinyinBases.contains(String(base[i..<(i + len)])) else { continue }
                    var piece = String(run[i..<(i + len)])
                    // A tone digit written after the syllable (shou3) stays with it.
                    var next = i + len
                    if next < run.count, run[next].isNumber { piece.append(run[next]); next += 1 }
                    for (n, rest) in suffix[next] where here[n + 1] == nil { here[n + 1] = [piece] + rest }
                }
                suffix[i] = here
            }
            guard !suffix[0].isEmpty else { return nil }
            options.append(suffix[0])
        }
        var reach = Array(repeating: Set<Int>(), count: runs.count + 1)
        reach[runs.count] = [0]
        for i in stride(from: runs.count - 1, through: 0, by: -1) {
            for c in options[i].keys { for r in reach[i + 1] { reach[i].insert(c + r) } }
        }
        guard reach[0].contains(want) else { return nil }
        var out: [String] = []
        var left = want
        for i in runs.indices {
            guard let c = options[i].keys.sorted().first(where: { reach[i + 1].contains(left - $0) }),
                  let part = options[i][c] else { return nil }
            out += part
            left -= c
        }
        return out
    }

    /// A letter without its tone mark, lower-cased (ǚ → ü, v → ü, Á → a). Anything else stays as it is.
    private static func baseLetter(_ c: Character) -> Character {
        let lower = String(c).lowercased()
        if lower == "v" { return "ü" }
        var scalars = String.UnicodeScalarView()
        for u in lower.decomposedStringWithCanonicalMapping.unicodeScalars
        where !(0x0300...0x036F).contains(u.value) || u.value == 0x0308 {
            scalars.append(u)
        }
        let s = String(scalars).precomposedStringWithCanonicalMapping
        return s.count == 1 ? Character(s) : c
    }

    /// Every toneless pinyin spelling (u after j/q/x as written, ü after n/l, the buzzed i, erhua 「r」).
    private static let pinyinBases: Set<String> = {
        var out = Set(standalone.map { $0.0 })
        out.insert("r")
        for (ini, _) in initials {
            var fins = allowed[ini] ?? []
            if specialI.contains(ini) { fins.append("i") }
            for fin in fins {
                out.insert(ini + fin)
                if palatalInitials.contains(ini) { out.insert(ini + fin.replacingOccurrences(of: "ü", with: "u")) }
            }
        }
        return out
    }()

    // MARK: - Syllables

    /// The longest zhuyin syllable tried, in characters with its ˙ or tone mark (the web's `parseZhuyin` passes 5).
    private static let maxSyllableLength = 5

    /// web `segmentOptions`: every way to cut one run of zhuyin into syllables, by syllable count. Longer syllables are
    /// tried first, so of two cuts with the same count the one that took the longer syllable first stays.
    private static func cuts(of run: String) -> [Int: [Syllable]] {
        let chars = run.map { String($0) }
        // suffixCuts[i]: the cuts of chars[i...], by count — filled from the end (the web memoises the same recursion).
        var suffixCuts = Array(repeating: [Int: [Syllable]](), count: chars.count + 1)
        suffixCuts[chars.count] = [0: []]
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            var here: [Int: [Syllable]] = [:]
            for len in stride(from: min(maxSyllableLength, chars.count - i), through: 1, by: -1) {
                guard let syllable = parseSyllable(chars[i..<(i + len)].joined()) else { continue }
                for (n, rest) in suffixCuts[i + len] where here[n + 1] == nil {
                    here[n + 1] = [syllable] + rest
                }
            }
            suffixCuts[i] = here
        }
        return suffixCuts[0]
    }

    /// web `ZY_TONE`.
    private static let toneOfMark: [Character: Int] = ["ˉ": 1, "ˊ": 2, "ˇ": 3, "ˋ": 4, "˙": 5]

    /// web `parseZhuyinSyllable`: one zhuyin syllable — ˙ before it is the neutral tone, a mark after it tones 1–4
    /// (none = tone 1). nil when it is not a syllable.
    private static func parseSyllable(_ raw: String) -> Syllable? {
        var s = raw
        var tone = 1
        if s.hasPrefix("˙") {
            tone = 5
            s.removeFirst()
        }
        if let last = s.last, let mark = toneOfMark[last] {
            if tone == 5 { return nil }
            tone = mark
            s.removeLast()
        }
        guard let base = baseOfZhuyin[s] else { return nil }
        return (base: base, tone: tone)
    }

    /// U+0304 macron, U+0301 acute, U+030C caron, U+0300 grave: tones 1–4.
    private static let toneMarks = ["\u{0304}", "\u{0301}", "\u{030C}", "\u{0300}"]

    /// web `formatPinyin`: the tone mark goes on a, else e, else ê, else the o of ou, else the last of i/o/u/ü.
    private static func format(_ s: Syllable) -> String {
        guard (1...4).contains(s.tone) else { return s.base }
        let chars = Array(s.base)
        var at = chars.firstIndex(of: "a")
        if at == nil { at = chars.firstIndex(of: "e") }
        if at == nil { at = chars.firstIndex(of: "ê") }
        if at == nil, s.base.contains("ou") { at = chars.firstIndex(of: "o") }
        if at == nil { at = chars.lastIndex(where: { "iouü".contains($0) }) }
        guard let i = at else { return s.base }
        let marked = String(chars[...i]) + toneMarks[s.tone - 1] + String(chars[(i + 1)...])
        return marked.precomposedStringWithCanonicalMapping
    }

    // MARK: - The syllable inventory (web INITIALS / FINALS / STANDALONE / ALLOWED)

    /// The initials, two-letter ones first.
    private static let initials: [(String, String)] = [
        ("zh", "ㄓ"), ("ch", "ㄔ"), ("sh", "ㄕ"), ("b", "ㄅ"), ("p", "ㄆ"), ("m", "ㄇ"), ("f", "ㄈ"),
        ("d", "ㄉ"), ("t", "ㄊ"), ("n", "ㄋ"), ("l", "ㄌ"), ("g", "ㄍ"), ("k", "ㄎ"), ("h", "ㄏ"),
        ("j", "ㄐ"), ("q", "ㄑ"), ("x", "ㄒ"), ("r", "ㄖ"), ("z", "ㄗ"), ("c", "ㄘ"), ("s", "ㄙ"),
    ]

    private static let finals: [String: String] = [
        "a": "ㄚ", "o": "ㄛ", "e": "ㄜ", "ai": "ㄞ", "ei": "ㄟ", "ao": "ㄠ", "ou": "ㄡ", "an": "ㄢ", "en": "ㄣ",
        "ang": "ㄤ", "eng": "ㄥ", "ong": "ㄨㄥ",
        "i": "ㄧ", "ia": "ㄧㄚ", "ie": "ㄧㄝ", "iao": "ㄧㄠ", "iu": "ㄧㄡ", "ian": "ㄧㄢ", "in": "ㄧㄣ",
        "iang": "ㄧㄤ", "ing": "ㄧㄥ", "iong": "ㄩㄥ",
        "u": "ㄨ", "ua": "ㄨㄚ", "uo": "ㄨㄛ", "uai": "ㄨㄞ", "ui": "ㄨㄟ", "uan": "ㄨㄢ", "un": "ㄨㄣ", "uang": "ㄨㄤ",
        "ü": "ㄩ", "üe": "ㄩㄝ", "üan": "ㄩㄢ", "ün": "ㄩㄣ",
    ]

    /// The syllables without an initial (those written with y / w included), in the web's order.
    private static let standalone: [(String, String)] = [
        ("a", "ㄚ"), ("o", "ㄛ"), ("e", "ㄜ"), ("ê", "ㄝ"), ("ai", "ㄞ"), ("ei", "ㄟ"), ("ao", "ㄠ"), ("ou", "ㄡ"),
        ("an", "ㄢ"), ("en", "ㄣ"), ("ang", "ㄤ"), ("eng", "ㄥ"), ("er", "ㄦ"),
        ("yi", "ㄧ"), ("ya", "ㄧㄚ"), ("yo", "ㄧㄛ"), ("ye", "ㄧㄝ"), ("yai", "ㄧㄞ"), ("yao", "ㄧㄠ"), ("you", "ㄧㄡ"),
        ("yan", "ㄧㄢ"), ("yin", "ㄧㄣ"), ("yang", "ㄧㄤ"), ("ying", "ㄧㄥ"), ("yong", "ㄩㄥ"),
        ("yu", "ㄩ"), ("yue", "ㄩㄝ"), ("yuan", "ㄩㄢ"), ("yun", "ㄩㄣ"),
        ("wu", "ㄨ"), ("wa", "ㄨㄚ"), ("wo", "ㄨㄛ"), ("wai", "ㄨㄞ"), ("wei", "ㄨㄟ"), ("wan", "ㄨㄢ"), ("wen", "ㄨㄣ"),
        ("wang", "ㄨㄤ"), ("weng", "ㄨㄥ"),
    ]

    private static let standaloneZhuyin: [String: String] = Dictionary(standalone, uniquingKeysWith: { first, _ in first })

    /// The finals each initial takes (a little wider than the real syllables, as on the web).
    private static let allowed: [String: [String]] = {
        let plain = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng"]
        let iGroup = ["i", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing"]
        let uGroup = ["u", "ua", "uo", "uai", "ui", "uan", "un", "uang"]
        let labial: [String] = plain + iGroup + ["u"]
        let alveolar: [String] = plain + ["ong"] + iGroup + ["u", "uo", "ui", "uan", "un"]
        let velar: [String] = plain + ["ong"] + uGroup
        let palatal: [String] = iGroup + ["iong", "ü", "üe", "üan", "ün"]
        let retroflex: [String] = plain + ["ong"] + uGroup
        var out: [String: [String]] = [:]
        for i in ["b", "p", "m", "f"] { out[i] = labial }
        for i in ["d", "t"] { out[i] = alveolar }
        for i in ["n", "l"] { out[i] = alveolar + ["ü", "üe"] }
        for i in ["g", "k", "h"] { out[i] = velar }
        for i in ["j", "q", "x"] { out[i] = palatal }
        for i in ["zh", "ch", "sh", "r", "z", "c", "s"] { out[i] = retroflex }
        return out
    }()

    /// Initials whose bare "i" is the buzzed vowel (zhi = ㄓ, si = ㄙ).
    private static let specialI: Set<String> = ["zh", "ch", "sh", "r", "z", "c", "s"]
    private static let palatalInitials: Set<String> = ["j", "q", "x"]

    /// web `pinyinBaseToZhuyin`: a toneless pinyin syllable → its zhuyin (no tone mark), nil for a spelling no initial takes.
    private static func zhuyin(ofBase base: String) -> String? {
        if let zy = standaloneZhuyin[base] { return zy }
        for (ini, zy) in initials where base.hasPrefix(ini) {
            var fin = String(base.dropFirst(ini.count))
            if fin == "i", specialI.contains(ini) { return zy }
            // After j/q/x a written u is ü (ju = jü).
            if palatalInitials.contains(ini), fin.hasPrefix("u") { fin = "ü" + String(fin.dropFirst()) }
            guard allowed[ini]?.contains(fin) == true, let f = finals[fin] else { return nil }
            return zy + f
        }
        return nil
    }

    /// web `INVENTORY` read backwards (`ZHUYIN_TO_BASE`): zhuyin without a tone mark → its pinyin spelling. Built in
    /// the web's order (the syllables without an initial, then each initial's finals); the first spelling of a zhuyin wins.
    private static let baseOfZhuyin: [String: String] = {
        var spellings: [(String, String)] = standalone
        for (ini, _) in initials {
            var fins = allowed[ini] ?? []
            if specialI.contains(ini) { fins.append("i") }
            for fin in fins {
                // After j/q/x, ü is written u (ju, que, xuan, qun).
                let written = palatalInitials.contains(ini) ? fin.replacingOccurrences(of: "ü", with: "u") : fin
                if let zy = zhuyin(ofBase: ini + written) { spellings.append((ini + written, zy)) }
            }
        }
        var out: [String: String] = [:]
        for (base, zy) in spellings where out[zy] == nil { out[zy] = base }
        return out
    }()
}
