import Foundation

/// Explanatory prose cut into sentences, so the word page can draw one sentence per row with a line under each
/// (owner 2026-10-14 「読みやすいように文の下に線に書いて」, 2026-10-15 「文の下に線、1文1行」).
///
/// A sentence ends after 。！？ (Japanese / Chinese) or after . ! ? followed by a space (English), and at every line
/// break. It never ends inside 「」『』（）() and the like or inside "double quotes", so a quoted 「好吃。」 stays in its
/// sentence; a closing quote or bracket stays with the sentence it closes; 「本当！？」 or "Really?!" is one ending.
/// An English period after an abbreviation (Mr. e.g. i.e. vs.), an initial (J. K.) or inside a number (3.5) is not an
/// ending. Brackets that are never closed are ignored rather than swallowing the rest of the text.
nonisolated enum Sentences {
    static func split(_ text: String) -> [String] {
        let out = split(Array(text), brackets: true)
        return out ?? split(Array(text), brackets: false) ?? []
    }

    /// Room for the line to break between any two characters of Japanese / Chinese prose (a zero-width space between
    /// them), so a row fills its width the way printed Japanese does. Without it the text system's word-aware breaking
    /// moved a whole word down and left a gap at the end of the line (owner 2026-10-15: 「ただし、台湾では声調をしっかりと
    /// 意識 / しましょう。」 broke early although there was room). Never before a mark that may not start a line
    /// (。、」）ー ぁ ッ …) and never after one that may not end it (「（).
    static func wrappable(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count * 2)
        var prev: Character?
        for ch in text {
            if let p = prev, isCJKLetter(p), isCJKLetter(ch), !noLineStart.contains(ch) {
                out.append("\u{200B}")
            }
            out.append(ch)
            prev = ch
        }
        return out
    }

    /// The opposite of `wrappable` for the words of a sentence (owner 2026-10-23: the example broke as 「水完全沖不下 /
    /// 去！」): a WORD JOINER (U+2060) between the characters of every occurrence of each of `words`, so the line never
    /// breaks inside a word (沖不下去 stays whole) and still breaks between words. Longer words first, so 馬桶刷 is kept
    /// whole before 馬桶 is. Words of one character, empty words and Latin words (which never break inside) change nothing.
    static func unbreakable(_ text: String, words: [String]) -> String {
        let chars = Array(text)
        guard chars.count > 1 else { return text }
        var joined = [Bool](repeating: false, count: chars.count)   // joined[i]: no break between chars[i] and chars[i+1]
        let wordChars = words.map { Array($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0.count > 1 && $0.allSatisfy { !$0.isWhitespace } }
            .sorted { $0.count > $1.count }
        for w in wordChars {
            var i = 0
            while i + w.count <= chars.count {
                if Array(chars[i..<(i + w.count)]) == w {
                    for k in i..<(i + w.count - 1) { joined[k] = true }
                    i += w.count
                } else {
                    i += 1
                }
            }
        }
        guard joined.contains(true) else { return text }
        var out = ""
        for (i, ch) in chars.enumerated() {
            out.append(ch)
            if joined[i] { out.append("\u{2060}") }
        }
        return out
    }

    // MARK: - Splitting

    private static let enders: Set<Character> = ["。", "！", "？", "!", "?", "．"]
    private static let openers: [Character: Character] = [
        "「": "」", "『": "』", "（": "）", "(": ")", "【": "】", "［": "］", "[": "]", "〈": "〉", "《": "》", "“": "”", "‘": "’",
    ]
    private static let closers: Set<Character> = ["」", "』", "）", ")", "】", "］", "]", "〉", "》", "”", "’"]
    /// Words that end with a period without ending the sentence (compared lowercased, without their dots).
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "jr", "sr", "vs", "e.g", "eg", "i.e", "ie", "cf", "approx", "a.m", "p.m", "fig",
        "u.s", "u.k", "mt", "inc", "ltd", "esp", "ca",
    ]

    /// nil when `brackets` is on and a bracket was left open (the caller splits again without them).
    private static func split(_ chars: [Character], brackets: Bool) -> [String]? {
        var out: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        func flush() {
            let s = current.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { out.append(s) }
            current = ""
        }
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isNewline {
                // A bracket left open in this line: split the whole text again without brackets.
                if brackets, depth > 0 || inQuote { return nil }
                flush()
                i += 1
                continue
            }
            current.append(ch)
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            if brackets {
                if openers[ch] != nil, !(ch == "‘" && inWord(prev)) {
                    depth += 1
                    i += 1
                    continue
                }
                if closers.contains(ch), depth > 0, !(ch == "’" && inWord(prev) && inWord(next)) {
                    depth -= 1
                    // 「…。」 / (…!) closed after an ending, then a space or the end: the sentence ends with it.
                    if depth == 0, !inQuote, let p = prev, enders.contains(p) || p == ".", next == nil || next!.isWhitespace {
                        flush()
                    }
                    i += 1
                    continue
                }
                if ch == "\"" {
                    inQuote.toggle()
                    if !inQuote, depth == 0, let p = prev, enders.contains(p) || p == ".", next == nil || next!.isWhitespace {
                        flush()
                    }
                    i += 1
                    continue
                }
            }
            if depth == 0, !inQuote, endsHere(chars, at: i) { flush() }
            i += 1
        }
        if brackets, depth > 0 || inQuote { return nil }
        flush()
        return out
    }

    /// True when the character at `i` (outside any bracket) ends its sentence.
    private static func endsHere(_ chars: [Character], at i: Int) -> Bool {
        let ch = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        // 「！？」 / "?!" / "。。": one ending, after the last mark. A closing mark keeps the sentence open for it.
        if let n = next, enders.contains(n) || closers.contains(n) || n == "\"" || (n == "." && ch != ".") {
            if enders.contains(ch) || ch == "." { return false }
        }
        switch ch {
        case "。", "！", "？", "．":
            return true
        case "!", "?":
            // Straight into Japanese / Chinese after Japanese / Chinese (すごい!次は) ends; a name like "Yahoo!知恵袋" does not.
            let prevLatin = i > 0 && chars[i - 1].isASCII && chars[i - 1].isLetter
            return next == nil || next!.isWhitespace || (isCJKLetter(next!) && !prevLatin)
        case ".":
            guard next == nil || next!.isWhitespace else { return false }   // 3.5, e.g., example.com
            let word = wordBefore(chars, at: i)
            if word.hasSuffix(".") {   // "..." (an ellipsis) ends only before a capital
                return startsWithCapital(chars, after: i)
            }
            let lower = word.lowercased()
            if abbreviations.contains(lower) { return false }
            // "No. 5": the number follows.
            if lower == "no", nextIsDigit(chars, after: i) { return false }
            // An initial (J. K. Rowling) — one capital letter ("I." is a word).
            if word.count == 1, word != "I", word.first!.isUppercase { return false }
            if lower == "etc" { return next == nil || startsWithCapital(chars, after: i) }
            return true
        default:
            return false
        }
    }

    /// The run of non-space characters just before `i` (without the mark at `i`).
    private static func wordBefore(_ chars: [Character], at i: Int) -> String {
        var j = i - 1
        var word: [Character] = []
        while j >= 0, !chars[j].isWhitespace, !openers.keys.contains(chars[j]), chars[j] != "\"" {
            word.insert(chars[j], at: 0)
            j -= 1
        }
        return String(word)
    }

    private static func startsWithCapital(_ chars: [Character], after i: Int) -> Bool {
        var j = i + 1
        while j < chars.count, chars[j].isWhitespace { j += 1 }
        guard j < chars.count else { return true }
        return chars[j].isUppercase || isCJKLetter(chars[j])
    }

    private static func nextIsDigit(_ chars: [Character], after i: Int) -> Bool {
        var j = i + 1
        while j < chars.count, chars[j].isWhitespace { j += 1 }
        return j < chars.count && chars[j].isNumber
    }

    /// A letter that belongs to a word (an apostrophe between two of them is not a quote: don't, l’eau).
    private static func inWord(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c.isLetter || c.isNumber
    }

    // MARK: - Line breaking

    /// Marks that may not start a line (Japanese kinsoku): small kana, the long-vowel mark, closing punctuation.
    private static let noLineStart: Set<Character> = Set("ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿーゝゞヽヾ々〻")  // l10n-ignore (kinsoku characters)

    /// Han, hiragana or katakana (not punctuation, not zhuyin marks).
    static func isCJKLetter(_ c: Character) -> Bool {
        guard let u = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        switch u.value {
        case 0x3041...0x3096, 0x309D...0x309F: return true   // hiragana
        case 0x30A1...0x30FA, 0x30FC...0x30FF: return true   // katakana (ー included; never before it, see noLineStart)
        case 0x3005, 0x3007: return true                     // 々 〇
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }
}
