import Foundation

// The usage-chunk shapes and the rules that decide how a chunk is shown (docs/chunk-rules.md).
// Kept free of UI so the swiftc rules harness (ios/LanguageRules) can test every rule.

/// extras.usage_chunks entry (extras.ts UsageChunkSchema): a formula like 跟＋男朋友＋吵架 and its translation.
nonisolated struct UsageChunk: Codable, Sendable, Hashable {
    var parts: [ChunkPart]
    var ja: String

    init(parts: [ChunkPart], ja: String) {
        self.parts = parts
        self.ja = ja
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parts = (try? c.decode([ChunkPart].self, forKey: .parts)) ?? []
        ja = (try? c.decode(String.self, forKey: .ja)) ?? ""
    }

    var text: String { parts.map(\.text).joined() }
}

/// Another word natives often put in a swappable part, with its meaning in the reader's language.
nonisolated struct ChunkAlt: Codable, Sendable, Hashable {
    var text: String
    var ja: String

    init(text: String, ja: String) {
        self.text = text
        self.ja = ja
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        ja = (try? c.decode(String.self, forKey: .ja)) ?? ""
    }
}

/// One block of a chunk (extras.ts ChunkPartSchema).
nonisolated struct ChunkPart: Codable, Sendable, Hashable {
    var text: String
    var pos: String
    /// A part natives swap (the 男朋友 of 跟＋男朋友＋吵架).
    var slot: Bool?
    /// This word's meaning, written as it appears in the chunk's translation (彼氏 in 「彼氏と喧嘩する」).
    var ja: String?
    /// Other words natives often put here, most frequent first.
    var alts: [ChunkAlt]?
    /// This block's reading, one syllable per character (server chunk tokens, 2026-10-15: `pinyin` with tone marks and
    /// `zhuyin` on every token), shown small above the block in the reading the learner chose (設定 › 発音表記). nil on
    /// older cards: the block shows its text alone, as before.
    var pinyin: String?
    var zhuyin: String?

    init(text: String, pos: String, slot: Bool? = nil, ja: String? = nil, alts: [ChunkAlt]? = nil,
         pinyin: String? = nil, zhuyin: String? = nil) {
        self.text = text
        self.pos = pos
        self.slot = slot
        self.ja = ja
        self.alts = alts
        self.pinyin = pinyin
        self.zhuyin = zhuyin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        pos = (try? c.decode(String.self, forKey: .pos)) ?? ""
        slot = try? c.decodeIfPresent(Bool.self, forKey: .slot)
        ja = try? c.decodeIfPresent(String.self, forKey: .ja)
        alts = (try? c.decodeIfPresent([ChunkAlt].self, forKey: .alts))?.filter { !$0.text.isEmpty }
        pinyin = Self.reading(try? c.decodeIfPresent(String.self, forKey: .pinyin))
        zhuyin = Self.reading(try? c.decodeIfPresent(String.self, forKey: .zhuyin))
    }

    /// A reading as sent, trimmed; nil when empty or not a string (an older card, or a broken token).
    private static func reading(_ raw: String??) -> String? {
        guard let s = (raw ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// Two blocks' readings as one (C7, `ChunkRules.mergeCompounds`: 芒果＋冰 → 芒果冰 keeps ㄇㄤˊ ㄍㄨㄛˇ ㄅㄧㄥ); nil as
    /// soon as either block has none (half a reading over a word would mislead).
    static func joinedReading(_ a: String?, _ b: String?) -> String? {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return nil }
        return a + " " + b
    }
}

nonisolated enum ChunkRules {
    // MARK: - Part kinds

    static func isNoun(_ p: ChunkPart) -> Bool {
        let u = p.pos.uppercased()
        // pos.ts: N…, and the old role marks S (subject) and O (object), which are noun phrases.
        return u.hasPrefix("N") || u == "S" || u == "O" || p.pos.contains("名詞")  // l10n-ignore (matching server POS)
    }

    static func isMeasure(_ p: ChunkPart) -> Bool {
        let u = p.pos.uppercased()
        return u.hasPrefix("M") || p.pos.contains("量詞")  // l10n-ignore (matching server POS)
    }

    static func isAdverb(_ p: ChunkPart) -> Bool {
        let u = p.pos.uppercased()
        return u.hasPrefix("ADV") || p.pos.contains("副詞")  // l10n-ignore (matching server POS)
    }

    /// A predicate adjective (Mandarin stative verb). Attributive-only Vs-attr and object-taking Vst are not.
    static func isPredicateStative(_ p: ChunkPart) -> Bool {
        let u = p.pos.uppercased()
        if u == "VS-ATTR" || u == "VST" { return false }
        return u.hasPrefix("VS")
    }

    // MARK: - C8 Degree words (很・有點・超…)

    /// Words that stand before a Mandarin adjective to say how much (chunk-grammar.ts DEGREE).
    static let degreeWords = ["很", "好", "超", "太", "真", "非常", "蠻", "滿", "挺", "比較", "更", "最", "有點", "有一點", "不", "沒", "還", "特別", "相當", "越來越", "這麼", "那麼", "多"]  // l10n-ignore (Mandarin words)

    /// The degree words offered in the wheel, most used first (C5): 很 → 超・非常・有點・蠻.
    /// Negations (不・不太) are left out: 「とても甘い」 cannot become 「甘くない」 by swapping one word.
    static let degreeChoices = ["很", "超", "非常", "有點", "蠻"]  // l10n-ignore (Mandarin words)

    /// What each degree word means, in the reader's language (as it would read in the chunk's translation).
    static func degreeGloss(_ word: String, reader: String) -> String {
        let table: [String: (ja: String, en: String)] = [  // l10n-ignore (glosses per reader language)
            "很": ("とても", "very"), "超": ("すごく", "super"), "非常": ("非常に", "extremely"),  // l10n-ignore
            "有點": ("ちょっと", "a little"), "蠻": ("わりと", "pretty"), "好": ("すごく", "so"),  // l10n-ignore
        ]
        guard let g = table[word] else { return "" }
        switch reader {
        case "en": return g.en
        case "ja": return g.ja
        default: return word
        }
    }

    static func isDegree(_ p: ChunkPart) -> Bool { degreeChoices.contains(p.text.trimmingCharacters(in: .whitespaces)) }

    // MARK: - Tidy (applied to every chunk before it is drawn)

    /// Puts a chunk into the shape it is shown in (docs/chunk-rules.md). Running it twice changes nothing.
    /// - C7: a word natives use as one word (芒果冰) is one block, never 芒果＋冰.
    /// - C8: a Mandarin noun + adjective gets its degree word (滷味＋很＋入味).
    /// - C5: a degree word can be swapped (很 → 超・非常・有點・蠻).
    static func tidy(_ parts: [ChunkPart], headword: String, target: String, reader: String) -> [ChunkPart] {
        var out = withoutSeparatorParts(parts)
        guard target.hasPrefix("zh") else { return out }
        out = mergeCompounds(out, headword: headword)
        out = withDegree(out)
        return out.map { p -> ChunkPart in
            guard isDegree(p), !LanguageRules.mentionsHeadword(p.text, headword: headword, target: target) else { return p }
            var q = p
            q.slot = true
            if (q.ja ?? "").isEmpty { q.ja = degreeGloss(p.text, reader: reader) }
            if (q.alts ?? []).isEmpty {
                q.alts = degreeChoices.filter { $0 != p.text }.map { ChunkAlt(text: $0, ja: degreeGloss($0, reader: reader)) }
            }
            return q
        }
    }

    // MARK: - C14 Separators are not blocks (chunk-grammar.ts withoutSeparatorParts)

    /// The AI sometimes returns the ＋ of the formula (跟＋男朋友＋吵架) as a block: 牛蒡 [+] 炒.
    /// Blocks made only of separators (+ ＋ ・ / ／ | and spaces) are dropped, and a block holding a separating
    /// plus (牛蒡+炒) is split there. A half-width + next to a Latin letter, digit or + is part of the word (C++).
    static func withoutSeparatorParts(_ parts: [ChunkPart]) -> [ChunkPart] {
        let separatorOnly = CharacterSet(charactersIn: "+＋・･/／|｜").union(.whitespacesAndNewlines)
        var out: [ChunkPart] = []
        for p in parts {
            if p.text.unicodeScalars.allSatisfy({ separatorOnly.contains($0) }) { continue }
            let pieces = splitOnSeparatorPlus(p.text)
            if pieces.isEmpty { continue }
            if pieces.count == 1 {
                // Only a + at the edge was dropped (炒+): the block is the same, so its other fields stay.
                var q = p
                q.text = pieces[0]
                out.append(pieces[0] == p.text ? p : q)
                continue
            }
            // Split pieces keep only the part of speech: the swaps and meaning belonged to the whole block.
            out.append(contentsOf: pieces.map { ChunkPart(text: $0, pos: p.pos) })
        }
        return out
    }

    private static func splitOnSeparatorPlus(_ text: String) -> [String] {
        let chars = Array(text)
        func near(_ i: Int) -> Bool {
            guard i >= 0, i < chars.count else { return false }
            let c = chars[i]
            return c == "+" || (c.isASCII && (c.isLetter || c.isNumber))
        }
        var out: [String] = []
        var cur = ""
        for (i, ch) in chars.enumerated() {
            if ch == "＋" || (ch == "+" && !near(i - 1) && !near(i + 1)) {
                out.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: - C15 Broken patterns (chunk-grammar.ts isBrokenUsageChunk)

    /// Ends that make an object-taking verb no longer bare (賣完・吃光・切好・煮熟): 「名詞＋動詞」 is then a topic form.
    private static let verbCompletion: Set<Character> = Set("了過著完好掉光到住走開起來去成熟爛死錯對滿夠")  // l10n-ignore (Mandarin characters)

    /// A chunk that is not a real way of saying it, kept narrow (owner report 2026-10-09 「嘴邊肉＋切 / 嘴邊肉をする」):
    /// 1. Mandarin, exactly two blocks: the learned noun, then a bare object-taking verb (pos `V`, 1–2 characters,
    ///    not ending in a result / aspect character). 嘴邊肉切 is not Mandarin (切嘴邊肉 or 嘴邊肉切一盤 is).
    /// 2. Not Japanese: the translation only copies the headword (「嘴邊肉をする」, or the headword itself).
    static func isBroken(_ chunk: UsageChunk, headword: String, target: String) -> Bool {
        let head = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return false }
        let parts = withoutSeparatorParts(chunk.parts).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if target.hasPrefix("zh"), parts.count == 2 {
            let noun = parts[0], verb = parts[1]
            let v = verb.text.trimmingCharacters(in: .whitespaces)
            if noun.text.contains(head), isNounGroup(noun.pos),
               verb.pos.trimmingCharacters(in: .whitespaces) == "V",
               !v.contains(head), v.count <= 2, let last = v.last, !verbCompletion.contains(last) {
                return true
            }
        }
        guard target != "ja", parts.count >= 2 else { return false }
        var ja = chunk.ja.replacingOccurrences(of: "[（(][^）)]*[）)]", with: "", options: .regularExpression)
        ja = ja.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        ja = ja.replacingOccurrences(of: "[。．.!！]$", with: "", options: .regularExpression)
        guard !ja.isEmpty else { return false }
        if ja == head { return true }
        let escaped = NSRegularExpression.escapedPattern(for: head)
        let verbs = "(?:を|に)?(?:する|します|やる|行う|おこなう)$"  // l10n-ignore (matching Japanese translations)
        if ja.range(of: "^[〜~]?\(escaped)\(verbs)", options: .regularExpression) != nil { return true }
        if ja.range(of: "^[〜~…]+(?:を|に)?(?:する|します|やる)$", options: .regularExpression) != nil { return true }  // l10n-ignore
        return false
    }

    /// pos.ts posGroup(pos) == "n": N…, and not a V / M / Adv / … tag.
    private static func isNounGroup(_ pos: String) -> Bool {
        let p = pos.trimmingCharacters(in: .whitespaces)
        return p.uppercased().hasPrefix("N") || p.contains("名詞")  // l10n-ignore (matching server POS)
    }

    /// C7: nouns side by side with the headword make one word in Mandarin (芒果＋冰 → 芒果冰, 台灣＋芒果 → 台灣芒果).
    static func mergeCompounds(_ parts: [ChunkPart], headword: String) -> [ChunkPart] {
        let core = LanguageRules.headwordCore(headword)
        guard !core.isEmpty else { return parts }
        var out: [ChunkPart] = []
        for p in parts {
            // Noun tags (N…) only: the old role marks S / O are phrases, not words to join.
            if let last = out.last, last.pos.uppercased().hasPrefix("N"), p.pos.uppercased().hasPrefix("N"),
               last.text.contains(core) || p.text.contains(core),
               (last.text + p.text).count <= 6 {
                out[out.count - 1] = ChunkPart(text: last.text + p.text, pos: last.pos,
                                               pinyin: ChunkPart.joinedReading(last.pinyin, p.pinyin),
                                               zhuyin: ChunkPart.joinedReading(last.zhuyin, p.zhuyin))
            } else {
                out.append(p)
            }
        }
        return out
    }

    /// C8 (chunk-grammar.ts withDegreeAdverb): 「滷味入味」 is not what natives say; they say 「滷味很入味」.
    static func withDegree(_ parts: [ChunkPart]) -> [ChunkPart] {
        guard parts.count >= 2, let last = parts.last else { return parts }
        let prev = parts[parts.count - 2]
        guard isPredicateStative(last), isNoun(prev),
              !degreeWords.contains(where: { last.text.hasPrefix($0) }),
              !parts.contains(where: isAdverb) else { return parts }
        return Array(parts.dropLast()) + [ChunkPart(text: "很", pos: "Adv"), last]  // l10n-ignore (Mandarin word)
    }

    // MARK: - What is shown

    /// C7: a chunk that was one word split in two (芒果＋冰 → 芒果冰) is a word, not a way of using it.
    /// An old chunk saved as a single block is kept (web refineUsageChunks does the same).
    static func isPattern(original: [ChunkPart], tidied: [ChunkPart]) -> Bool {
        tidied.count >= 2 || original.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count < 2
    }

    /// C2 / C5 / C6: a part opens the wheel only when it is not the word being learned, is a concrete noun,
    /// a measure word or a degree word, and has other words to offer.
    static func isSwappable(_ p: ChunkPart, headword: String, target: String) -> Bool {
        guard p.slot == true else { return false }
        let alts = (p.alts ?? []).filter { !$0.text.isEmpty && $0.text != p.text }
        guard !alts.isEmpty else { return false }
        if !headword.isEmpty, LanguageRules.mentionsHeadword(p.text, headword: headword, target: target) { return false }
        if p.pos.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return isNoun(p) || isMeasure(p) || (target.hasPrefix("zh") && isDegree(p))
    }

    /// The choices of a swappable part: the word itself first, then the others.
    static func choices(_ p: ChunkPart) -> [ChunkAlt] {
        [ChunkAlt(text: p.text, ja: p.ja ?? "")] + (p.alts ?? []).filter { !$0.text.isEmpty && $0.text != p.text }
    }

    /// The chunk read aloud: English words are spaced, Mandarin and Japanese are not.
    static func spoken(_ parts: [ChunkPart], target: String) -> String {
        parts.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: target == "en" ? " " : "")
    }

    /// C12 (chunk-grammar.ts swappedTranslation): the translation with the swapped word's meaning put in place of
    /// the original's. When the original cannot be found, the translation stays and says what was swapped.
    static func swappedTranslation(_ translation: String, original: [ChunkPart], shown: [ChunkPart], reader: String) -> String {
        var out = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes: [String] = []
        for (i, part) in original.enumerated() where i < shown.count && shown[i].text != part.text {
            let alt = choices(part).first { $0.text == shown[i].text }
            let to = (alt?.ja.isEmpty == false ? alt!.ja : shown[i].text)
            if let from = [part.ja ?? "", part.text].first(where: { !$0.isEmpty && out.contains($0) }),
               let r = out.range(of: from) {
                out.replaceSubrange(r, with: to)
            } else {
                notes.append("\(part.text) → \(shown[i].text)" + ((alt?.ja ?? "").isEmpty ? "" : ": \(alt!.ja)"))
            }
        }
        guard !notes.isEmpty else { return out }
        return reader == "en" ? "\(out) (\(notes.joined(separator: ", ")))"
            : reader == "ja" ? "\(out)（\(notes.joined(separator: "、"))）" : "\(out)（\(notes.joined(separator: "，"))）"
    }
}
