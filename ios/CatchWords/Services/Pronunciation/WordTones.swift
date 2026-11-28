import Foundation

/// A word's syllables and their tones, from its reading (the zhuyin from the Taiwan dictionary first, else the pinyin).
nonisolated struct WordTones: Sendable, Equatable {
    nonisolated struct Syllable: Sendable, Equatable {
        /// The character.
        var char: String
        /// Its pinyin as written over it (with the tone mark).
        var pinyin: String
        /// 1–4; 5 = neutral.
        var tone: Int
    }

    var headword: String
    var syllables: [Syllable]

    /// The tones as the dictionary writes them, e.g. 「2-4」 for 學校. Natives recorded saying any word with the same
    /// pattern give the band for this one (the pitch of a word follows its tones far more than its sounds). Words with
    /// 一 or 不 have no pattern: their tone changes with the next one, so only their own recordings fit.
    var pattern: String? {
        guard !syllables.contains(where: { $0.char == "一" || $0.char == "不" }) else { return nil } // l10n-ignore
        return syllables.map { String($0.tone) }.joined(separator: "-")
    }

    /// The character and its pinyin, for a hint: 「麻 má」.
    func label(_ i: Int) -> String {
        guard syllables.indices.contains(i) else { return "" }
        return "\(syllables[i].char) \(syllables[i].pinyin)"
    }

    /// nil when the headword is not all Han characters or its reading does not give one syllable per character.
    static func make(headword: String, zhuyin: String?, pinyin: String?) -> WordTones? {
        let chars = headword.filter { !$0.isWhitespace }.map { String($0) }
        guard !chars.isEmpty, chars.count <= 8, chars.allSatisfy(isHan) else { return nil }
        let n = chars.count
        var tones: [Int]?
        var spelled: [String]?
        if let z = zhuyin, !z.isEmpty, let parsed = PinyinZhuyin.parseZhuyin(z, want: n), parsed.count == n {
            tones = parsed.map { $0.tone }
            spelled = PinyinZhuyin.pinyin(fromZhuyin: z, want: n)?.split(separator: " ").map(String.init)
        }
        if let cut = PinyinZhuyin.syllables(ofPinyin: pinyin, want: n), cut.count == n {
            if tones == nil { tones = cut.map(tone(ofPinyin:)) }
            if spelled?.count != n { spelled = cut }
        }
        guard let tones, tones.count == n else { return nil }
        let marks = (spelled?.count == n ? spelled : nil) ?? Array(repeating: "", count: n)
        return WordTones(headword: headword, syllables: (0..<n).map {
            Syllable(char: chars[$0], pinyin: marks[$0], tone: tones[$0])
        })
    }

    /// The tone of one pinyin syllable: its mark (ā á ǎ à), or a digit after it (ma3); none = neutral.
    static func tone(ofPinyin syllable: String) -> Int {
        if let last = syllable.last, let d = last.wholeNumberValue, (1...5).contains(d) { return d }
        for u in syllable.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.value {
            case 0x0304: return 1
            case 0x0301: return 2
            case 0x030C: return 3
            case 0x0300: return 4
            default: continue
            }
        }
        return 5
    }

    static func isHan(_ s: String) -> Bool {
        guard let u = s.unicodeScalars.first, s.unicodeScalars.count == 1 else { return false }
        switch u.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }
}
