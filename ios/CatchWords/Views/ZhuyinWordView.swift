import SwiftUI

nonisolated struct ZhuyinUnit: Hashable, Sendable {
    let char: String
    let body: [String]
    let tone: String
    let neutral: Bool
    var hasReading: Bool { !body.isEmpty }
}

/// zhuyin-layout.ts `pairZhuyin`: one syllable per Han character, or nil (then the reading goes below).
nonisolated enum ZhuyinLayout {
    static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (0x3400...0x4DBF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value) || s.value == 0x3005 || s.value == 0x3007
        }
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "ˊˇˋ˙")
        if let a = Unicode.Scalar(0x3105), let b = Unicode.Scalar(0x312F) {
            set.formUnion(CharacterSet(charactersIn: a...b))
        }
        return set
    }()

    static func pair(_ headword: String, _ zhuyin: String?) -> [ZhuyinUnit]? {
        let word = headword.trimmingCharacters(in: .whitespaces)
        guard let reading = zhuyin?.trimmingCharacters(in: .whitespaces), !word.isEmpty, !reading.isEmpty else { return nil }
        let syllables = reading.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let chars = Array(word)
        let hanCount = chars.filter(isHan).count
        guard hanCount > 0, hanCount == syllables.count else { return nil }
        guard syllables.allSatisfy({ $0.unicodeScalars.allSatisfy { allowed.contains($0) } }) else { return nil }
        var i = 0
        var out: [ZhuyinUnit] = []
        for ch in chars {
            guard isHan(ch) else {
                out.append(ZhuyinUnit(char: String(ch), body: [], tone: "", neutral: false))
                continue
            }
            let s = syllables[i]
            i += 1
            var body: [String] = []
            var tone = ""
            var neutral = false
            for c in s {
                if "ˊˇˋ".contains(c) { tone = String(c) } else if c == "˙" { neutral = true } else { body.append(String(c)) }
            }
            out.append(ZhuyinUnit(char: String(ch), body: body, tone: tone, neutral: neutral))
        }
        return out
    }
}

/// One character with the pinyin syllable that sits over it (nil over punctuation and Latin letters).
nonisolated struct PinyinUnit: Hashable, Sendable {
    let char: String
    let reading: String?
}

/// Pinyin over each Han character (owner 2026-10-14: 「ピンインはなるべく、それぞれの漢字のうえに表示して」): the pinyin
/// spelled from its zhuyin (written one syllable at a time, so it never cuts a syllable wrongly), else the word's own
/// pinyin cut into one syllable per character. nil when neither gives exactly one syllable per character — then the
/// reading stays one line over the whole word.
nonisolated enum PinyinLayout {
    static func pair(_ headword: String, pinyin: String?, zhuyin: String?) -> [PinyinUnit]? {
        let chars = Array(headword.trimmingCharacters(in: .whitespaces))
        let han = chars.filter(ZhuyinLayout.isHan).count
        guard han > 0 else { return nil }
        let spelled = PinyinZhuyin.pinyin(fromZhuyin: zhuyin, want: han)?.split(separator: " ").map(String.init)
        let own = (pinyin ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let syllables = spelled?.count == han ? spelled : PinyinZhuyin.syllables(ofPinyin: own, want: han)
        else { return nil }
        var i = 0
        return chars.map { (ch: Character) -> PinyinUnit in
            guard ZhuyinLayout.isHan(ch) else { return PinyinUnit(char: String(ch), reading: nil) }
            defer { i += 1 }
            return PinyinUnit(char: String(ch), reading: syllables[i])
        }
    }
}

/// Pinyin centred over each character, the characters in one line (the reading line keeps its height over
/// punctuation, so every character sits on the same baseline).
struct PinyinRubyLine: View {
    let units: [PinyinUnit]
    let size: CGFloat
    var weight: Font.Weight = .medium
    var color: Color = Theme.foreground
    var readingColor: Color = Theme.muted
    /// The reading keeps the headword's proportion at every size (no 9 pt floor): a small tag reads like the word page.
    var proportional: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: size * 0.05) {
            ForEach(Array(units.enumerated()), id: \.offset) { _, u in
                VStack(spacing: 0) {
                    Text(u.reading ?? " ")
                        .font(.system(size: proportional ? size * 0.36 : max(9, size * 0.36), weight: .medium))
                        .foregroundStyle(readingColor)
                        .lineLimit(1)
                        .fixedSize()
                    Text(u.char)
                        .font(.system(size: size, weight: weight))
                        .foregroundStyle(color)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(units.map(\.char).joined())
    }
}

/// A headword with its reading, drawn the way the learning language is read (web phonetic.tsx ReadingOf):
/// - Taiwan Mandarin: zhuyin stacked to the RIGHT of each character (or pinyin above, 設定 › 発音表記)
/// - Japanese: furigana in hiragana above the word (or Hepburn romaji); none for a kana-only word
/// - English: the word alone — never zhuyin, pinyin or kana (2026-08-26「注音やピンインを決して表示しないで」)
struct ZhuyinWordView: View {
    let headword: String
    let zhuyin: String?
    var size: CGFloat = 22
    var weight: Font.Weight = .medium
    var color: Color = Theme.foreground
    var readingColor: Color = Theme.muted
    /// Shown instead of the zhuyin when the learner chose ピンイン (設定 › 発音表記, web reading-pref).
    var pinyin: String? = nil
    /// The word's learning language (nil = the learner's current one).
    var language: String? = nil
    /// Readings in the headword's proportion at every size, as on the word page (no minimum size): the home tags
    /// (owner 2026-10-20: the small tag's reading came out as big as its characters).
    var proportionalReading: Bool = false
    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"
    /// Japanese reading: "kana" (furigana, default) or "romaji". Kept apart from the Mandarin choice.
    @AppStorage("reading.ja") private var readingJa: String = "kana"

    private var lang: String { language ?? NativeAPI.targetLanguage }

    var body: some View {
        switch lang {
        case "en": plainWord
        case "ja": japaneseWord
        default: mandarinWord
        }
    }

    /// Long English words and phrases ("traffic light") shrink or wrap instead of running off the row.
    private var plainWord: some View {
        Text(headword)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Furigana (or romaji) centred above the word, the way Japanese readers expect it.
    @ViewBuilder private var japaneseWord: some View {
        let kana = (zhuyin ?? "").trimmingCharacters(in: .whitespaces)
        let romaji = (pinyin ?? "").trimmingCharacters(in: .whitespaces)
        let reading = readingJa == "romaji" && !romaji.isEmpty ? romaji
            : (kana.isEmpty || kana == headword ? "" : kana)
        // Only kana or romaji may sit above a Japanese word (never zhuyin from an old row).
        if reading.isEmpty || !Self.isJapaneseReading(reading) {
            plainWord
        } else {
            VStack(spacing: max(0, size * 0.04)) {
                Text(reading)
                    .font(.system(size: max(9, size * 0.36), weight: .medium))
                    .foregroundStyle(readingColor)
                    .lineLimit(1)
                Text(headword)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headword)
        }
    }

    /// Kana, or Latin letters with macrons (tōkyō) and spaces — nothing else may be a Japanese reading.
    private static func isJapaneseReading(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { u in
            let v = u.value
            if LanguageRules.isKana(v) || v == 0x20 { return true }
            return v < 0x250 && u.properties.isAlphabetic
        }
    }

    /// The ruby cannot wrap, so a long word (珍珠奶茶 at 38 pt beside the edit and sound buttons) steps down
    /// in size instead of pushing its row — and the whole word page — wider than the screen.
    @ViewBuilder private var mandarinWord: some View {
        ViewThatFits(in: .horizontal) {
            mandarinRuby(size: size)
            mandarinRuby(size: size * 0.82)
            mandarinRuby(size: size * 0.68)
        }
    }

    @ViewBuilder private func mandarinRuby(size: CGFloat) -> some View {
        if readingPref == "pinyin", let units = PinyinLayout.pair(headword, pinyin: pinyin, zhuyin: zhuyin) {
            PinyinRubyLine(units: units, size: size, weight: weight, color: color, readingColor: readingColor,
                           proportional: proportionalReading)
        } else if readingPref == "pinyin", let p = pinyin?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(p)
                    .font(.system(size: reading(size * 0.4, floor: 10), weight: .medium))
                    .foregroundStyle(readingColor)
                Text(headword)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(color)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headword)
        } else if let units = ZhuyinLayout.pair(headword, zhuyin) {
            HStack(alignment: .center, spacing: size * 0.06) {
                ForEach(Array(units.enumerated()), id: \.offset) { _, u in
                    HStack(alignment: .center, spacing: size * 0.03) {
                        Text(u.char)
                            .font(.system(size: size, weight: weight))
                            .foregroundStyle(color)
                        if u.hasReading { column(u, size: size) }
                    }
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headword)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(headword)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(color)
                if let z = zhuyin, !z.isEmpty {
                    Text(z).font(.system(size: reading(size * 0.42, floor: 11))).foregroundStyle(readingColor)
                }
            }
        }
    }

    /// A reading's size: in proportion, kept from going below `floor` unless `proportionalReading`.
    private func reading(_ proportional: CGFloat, floor: CGFloat) -> CGFloat {
        proportionalReading ? proportional : max(floor, proportional)
    }

    private func column(_ u: ZhuyinUnit, size: CGFloat) -> some View {
        let s = reading(size * 0.3, floor: 7)
        return HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if u.neutral {
                    Text("˙").font(.system(size: s)).frame(height: s * 1.02)
                }
                ForEach(Array(u.body.enumerated()), id: \.offset) { _, sym in
                    Text(sym).font(.system(size: s)).frame(height: s * 1.02)
                }
            }
            Text(u.tone.isEmpty ? " " : u.tone)
                .font(.system(size: s))
                .frame(width: s * 0.55, height: s * 1.02)
        }
        .foregroundStyle(readingColor)
    }
}
