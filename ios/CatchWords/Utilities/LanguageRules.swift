import Foundation

/// The language-mixing rules in one place (docs/language-rules.md, rules R1–R9, R22).
///
/// This file depends only on the display-language list (`ios/Shared/DisplayLanguages.swift`, generated from
/// `ios/Localization/languages.json`): CI compiles the two on their own with the case table
/// `ios/LanguageRules/cases.json` and fails the build if any rule gives a different answer
/// (`ios/LanguageRules/main.swift`). A reader's rules follow the script its language is written in, so a newly
/// listed language in a script below needs no new code here. When a mixed-language bug is found, its text goes into that
/// table first, then this file is changed until every case passes — so the rules only get stricter.
nonisolated enum LanguageRules {
    // MARK: Scripts

    static func isKana(_ v: UInt32) -> Bool { (0x3041...0x309F).contains(v) || (0x30A0...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9F).contains(v) }
    static func isHan(_ v: UInt32) -> Bool { (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || v == 0x3005 }
    static func isHangul(_ v: UInt32) -> Bool { (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) }
    static func isLatin(_ v: UInt32) -> Bool { (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v) }
    /// Latin letters with two marks (Vietnamese ạ ầ ở ữ …): Latin in counts, never in a headword.
    static func isLatinExtended(_ v: UInt32) -> Bool { (0x1E00...0x1EFF).contains(v) }

    struct Counts { var kana = 0, han = 0, hangul = 0, latin = 0; var cjk: Int { kana + han + hangul } }

    static func counts(_ s: String) -> Counts {
        var c = Counts()
        for u in s.unicodeScalars {
            let v = u.value
            if isKana(v) { c.kana += 1 } else if isHan(v) { c.han += 1 } else if isHangul(v) { c.hangul += 1 } else if isLatin(v) || isLatinExtended(v) { c.latin += 1 }
        }
        return c
    }

    // MARK: R3–R6 — explanation text for a reader

    /// Whether a meaning, translation or note does NOT look written in `reader` (any display language).
    /// - R3: a copy of the source sentence is wrong in every language.
    /// - R4 ja (kana script): a run of ≥5 Han with no kana is Chinese (unless `hanOnlyOk`, for short meanings such
    ///   as 鉄板焼 or 故宮博物院); a Latin-only sentence is English.
    /// - R5 zh-TW (Han script): kana that makes up a real part of the text is Japanese (one quoted kana word is
    ///   fine); a Latin-only sentence is English.
    /// - R6 en and every Latin-script reader: more CJK than Latin is not theirs (a Chinese headword inside is fine).
    /// - R22 Latin-script readers: a text that clearly reads as another listed Latin-script language (its own words
    ///   and letters: "the … of", "de … que", "của … là") is not theirs.
    /// - R22 ko (Hangul script): no Hangul at all, or Han / kana outweighing it, is not Korean.
    /// Anything unclear is kept — a right translation is never dropped.
    static func looksWrong(_ text: String?, reader: String, source: String? = nil, hanOnlyOk: Bool = false) -> Bool {
        let s = (text ?? "").filter { !$0.isWhitespace }
        guard !s.isEmpty else { return false }
        let strip: (String) -> String = { $0.filter { !$0.isWhitespace && !"。．.,，、!！?？「」『』\"'“”‘’".contains($0) } }
        if let source, !strip(source).isEmpty, strip(source) == strip(s) { return true }
        // R9: words quoted in 「」『』"" are cited examples (often in the learning language), not the
        // language the note is written in — judge the rest. A text that is all quotes is judged whole.
        let body = unquoted(s)
        let judged = body.isEmpty ? s : body
        let c = counts(judged)
        let latinWords = (text ?? "").split(whereSeparator: { !($0.isASCII && $0.isLetter) }).filter { $0.count >= 2 }.count
        let mostlyLatin = c.latin >= 5 && c.latin > c.cjk * 3 && latinWords >= 2
        switch DisplayLanguages.find(reader)?.script {
        case .kana:
            if !hanOnlyOk, judged.count >= 5, c.kana == 0, c.latin == 0, c.hangul == 0, c.han > 0 { return true }
            if c.han == 0, c.kana == 0, c.latin >= 5 { return true }
            if c.hangul > 0, c.hangul >= c.kana + c.han { return true }
            return mostlyLatin
        case .han:
            if c.kana >= 2, c.kana * 3 >= c.han { return true }
            if c.han == 0, c.latin >= 5 { return true }
            if c.hangul > 0, c.hangul >= c.han { return true }
            return mostlyLatin
        case .latin:
            if c.cjk >= 2, c.cjk > c.latin { return true }
            // Words need their spaces: the quoted parts are left out of the text as it was written.
            let words = unquoted(text ?? "")
            if let other = latinLanguage(of: words.isEmpty ? (text ?? "") : words), other != reader { return true }
            return false
        case .hangul:
            // Japanese: kana that makes up a real part of the text.
            if c.kana >= 2, c.kana * 2 >= c.hangul { return true }
            if c.hangul == 0 { return c.han + c.kana > 0 || mostlyLatin || c.latin >= 5 }
            // Chinese with a Korean word in it.
            return c.han + c.kana > c.hangul * 2
        case nil:
            return false
        }
    }

    // MARK: R22 — telling Latin-script languages apart

    /// The listed Latin-script language `text` clearly reads as, or nil when it is unclear. Each word that is one of a
    /// language's own words, and each of its own letters (đ ơ ư, ñ), counts for that language; the answer needs two
    /// counts and twice as many as any other language. A short meaning with nothing distinctive ("bus stop",
    /// "cam") is unclear.
    static func latinLanguage(of text: String) -> String? {
        let latin = DisplayLanguages.all.filter { $0.script == .latin }
        guard latin.count > 1 else { return nil }
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        var scores: [String: Int] = [:]
        for l in latin {
            var n = words.filter { l.markerWords.contains($0) }.count
            if !l.markerLetters.isEmpty { n += lower.filter { l.markerLetters.contains($0) }.count }
            scores[l.code] = n
        }
        let ranked = scores.sorted { $0.value > $1.value }
        guard let top = ranked.first, top.value >= 2 else { return nil }
        let second = ranked.dropFirst().first?.value ?? 0
        return top.value >= second * 2 ? top.key : nil
    }

    /// Whether two display languages are written in the same script (their text cannot be told apart by script alone).
    static func sameScript(_ a: String, _ b: String) -> Bool {
        guard let x = DisplayLanguages.find(a)?.script, let y = DisplayLanguages.find(b)?.script else { return false }
        return x == y
    }

    /// The text without its quoted parts (「…」, 『…』, “…”, "…").
    static func unquoted(_ s: String) -> String {
        var out = ""
        var closing: Character?
        let pairs: [Character: Character] = ["「": "」", "『": "』", "“": "”", "\"": "\""]
        for ch in s {
            if let c = closing {
                if ch == c { closing = nil }
            } else if let c = pairs[ch] {
                closing = c
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // MARK: R7 — outside text (server errors, database messages)

    /// Whether outside text may be shown as it is on a screen in `code`. Only human-written text in
    /// that language passes: Japanese with kana on a ja screen; Chinese (Han, no kana, not mostly Latin)
    /// on a zh-TW screen; Korean (Hangul, no kana, not mostly Han or Latin) on a ko screen. Raw Latin-script text
    /// (English or any other), codes (PGRST116) and anything else never show on any screen —
    /// they are translated from a known sentence or replaced by the screen's own message (G2).
    static func readsAs(_ text: String, _ code: String) -> Bool {
        let c = counts(text)
        switch DisplayLanguages.find(code)?.script {
        case .kana: return c.kana > 0 && c.latin <= (c.kana + c.han) * 3
        case .han: return c.han > 0 && c.kana == 0 && c.hangul == 0 && c.latin * 3 < c.han
        case .hangul: return c.hangul > 0 && c.kana == 0 && c.han <= c.hangul && c.latin * 3 < c.hangul
        case .latin, nil: return false
        }
    }

    // MARK: R8 — learning-language content

    /// Whether text is written in the learning language at all (an example sentence):
    /// Han for Taiwan Mandarin, kana or kanji for Japanese, Latin letters for English.
    static func isIn(_ text: String, target: String) -> Bool {
        let c = counts(text)
        switch target {
        case "en":
            // Any Han, kana or Hangul: not an English sentence (I3「這間咖啡廳的 ceiling 很高」).
            return c.cjk == 0
        case "ja":
            if c.hangul > 0 { return false }
            if c.kana > 0 { return true }
            // Han only: a short word (天井) is Japanese; a whole Han sentence is a Chinese copy.
            if c.han > 0 { return c.han < 5 }
            return c.latin == 0
        default:
            if c.kana > 0 || c.hangul > 0 { return false }
            if c.han > 0 { return true }
            return c.latin == 0
        }
    }

    // MARK: R15 — headwords and the word's language (target-profile.ts headwordOk, word-language.ts)

    /// The headword without bracketed notes, spaces and punctuation ("烤肉 (BBQ)" → "烤肉", "don't" → "dont").
    static func headwordCore(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "[（(【〔\\[][^）)】〕\\]]*[）)】〕\\]]", with: "", options: .regularExpression)
        s = String(s.unicodeScalars.filter { u in
            !CharacterSet.whitespacesAndNewlines.contains(u) && !CharacterSet.punctuationCharacters.contains(u)
                && !"'’‘-‐–—・·.,、。".unicodeScalars.contains(u)
        }.map(Character.init))
        return s
    }

    /// R20 「チャンクに学ぶべき単語の芒果がない」: a usage chunk must contain the word it teaches —
    /// the headword itself, or (Japanese/English) an inflected form of it. "很+甜" is not a chunk of 芒果.
    static func mentionsHeadword(_ text: String, headword: String, target: String) -> Bool {
        let core = headwordCore(headword)
        guard !core.isEmpty else { return true }
        switch target {
        case "en":
            let words = text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
            let heads = headword.lowercased().split { !$0.isLetter }.map(String.init).filter { !$0.isEmpty }
            guard !heads.isEmpty else { return true }
            // Every word of the headword appears, allowing regular endings (mango→mangoes, carry→carried, make→making).
            return heads.allSatisfy { h in
                var stem = h
                if stem.count >= 4, stem.hasSuffix("e") || stem.hasSuffix("y") { stem.removeLast() }
                // Short words (man, go) must match whole: "mankind" is not a form of "man".
                return words.contains { $0 == h || (h.count >= 4 && $0.hasPrefix(stem)) }
            }
        case "ja":
            let t = headwordCore(text)
            if t.contains(core) { return true }
            // Conjugated forms keep the stem: 食べる→食べた, 高い→高くない, ありがとう→ありがとうございます.
            var stem = core
            let isHiragana: (Unicode.Scalar) -> Bool = { (0x3041...0x309F).contains($0.value) }
            if core.unicodeScalars.contains(where: { isHan($0.value) }) {
                while let last = stem.unicodeScalars.last, isHiragana(last) { stem = String(stem.unicodeScalars.dropLast()) }
            } else if stem.count >= 3 {
                stem.removeLast()
            }
            return !stem.isEmpty && t.contains(stem)
        default:
            return headwordCore(text).contains(core)
        }
    }

    /// hero-image.ts heroSearchQuery: the words an image search gets for a word's picture. The first
    /// sense of the reader's meaning (自転車, not 腳踏車 — a Mandarin query returns shop photos and
    /// text), without brackets or 〜 placeholders; the headword when nothing is left; at most 40 characters.
    /// The card's own English search words (`extras.image_query`) come first when they are usable.
    static func heroSearchQuery(headword: String?, meaning: String?, imageQuery: String? = nil) -> String {
        let preferred = cleanImageQuery(imageQuery)
        if !preferred.isEmpty { return preferred }
        let head = (headword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Brackets first: 「自転車（口語では腳踏車）」 must not be cut at a 、 inside the brackets.
        let noBrackets = (meaning ?? "").replacingOccurrences(
            of: "[（(【〈《\\[「][^）)】〉》\\]」]*[）)】〉》\\]」]", with: " ", options: .regularExpression)
        let first = noBrackets.split(omittingEmptySubsequences: false) { "、,，;；/・|".contains($0) }.first.map(String.init) ?? ""
        let cleaned = first.replacingOccurrences(of: "[〜～…]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String((cleaned.isEmpty ? head : cleaned).prefix(40))
    }

    /// hero-image.ts cleanImageQuery: `extras.image_query` as search words. Brackets and quotes dropped, spaces
    /// squeezed, cut at a word boundary within 40 characters. A sentence (。!? inside, or more than 6 words) is not used.
    static func cleanImageQuery(_ raw: String?) -> String {
        guard let raw else { return "" }
        var t = raw.replacingOccurrences(of: "[（(【〈《\\[「][^）)】〉》\\]」]*[）)】〉》\\]」]", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "[\"'“”‘’「」『』]", with: " ", options: .regularExpression)
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        t = t.replacingOccurrences(of: "[。.]+$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.range(of: "[。!?！？]", options: .regularExpression) == nil else { return "" }
        let words = t.split(separator: " ").map(String.init)
        guard words.count <= 6 else { return "" }
        var out = ""
        for w in words {
            let next = out.isEmpty ? w : "\(out) \(w)"
            if next.count > 40 { break }
            out = next
        }
        return out
    }

    /// Whether `raw` can be a headword of `target`: Mandarin = Han only; English = Latin letters only;
    /// Japanese = kana/kanji only (a 1–2 capital prefix before katakana is fine: Tシャツ).
    static func headwordOk(_ raw: String, target: String) -> Bool {
        var s = headwordCore(raw)
        guard !s.isEmpty else { return false }
        let c = counts(s)
        switch target {
        case "en":
            return c.cjk == 0 && s.unicodeScalars.allSatisfy { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) }
        case "ja":
            s = s.replacingOccurrences(of: "^[A-ZＡ-Ｚ]{1,2}(?=[ァ-ヺー])", with: "", options: .regularExpression)  // l10n-ignore (pattern)
            guard !s.isEmpty else { return false }
            let jaOnly = s.unicodeScalars.allSatisfy { isKana($0.value) || isHan($0.value) || [0x30FC, 0x3005, 0x3006].contains($0.value) }
            // At least one real kana or kanji (not a word made only of ー or 〆).
            let real = s.unicodeScalars.contains { (isKana($0.value) && $0.value != 0x30FC) || isHan($0.value) }
            return jaOnly && real
        default:
            // Han only — no kana, Latin, Hangul, Cyrillic or anything else.
            return c.han > 0 && s.unicodeScalars.allSatisfy { isHan($0.value) || $0.value == 0x3007 }
        }
    }

    // MARK: R21 — a headword about to be saved

    /// Whether `raw` may be SAVED as a headword of `target` (owner 2026-10-15: never the display language in a headword,
    /// even when the word was typed in it — ボクサーパンツ typed by a Japanese reader came back as the headword of a
    /// Mandarin word).
    /// Stricter than `headwordOk`, which drops bracketed notes first: here nothing is dropped, so 「四角褲（ボクサー）」
    /// is refused too.
    /// - zh-TW: Han only (digits allowed), no kana and no Latin, Cyrillic or Hangul letters — except 1–3 capital
    ///   letters stuck to a Han character, which Taiwan writes as part of the word (T恤, 卡拉OK; the server's
    ///   target-profile.ts headwordOk does the same) — and no kanji only Japan writes that way (図鑑, 駅: Taiwan writes
    ///   圖, 驛 — `japaneseOnlyKanji`, the server's kanji-forms.ts).
    /// - en: Latin letters (digits, & and accents allowed), no CJK.
    /// - ja: kana / kanji (1–2 capitals before katakana are fine: Tシャツ), no other Latin.
    static func headwordSaveable(_ raw: String, target: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch target {
        case "en":
            let s = saveCore(trimmed)
            guard !s.isEmpty, counts(s).cjk == 0 else { return false }
            let ok = s.unicodeScalars.allSatisfy { isLatin($0.value) || ("0"..."9").contains(Character($0)) || $0 == "&" }
            return ok && s.unicodeScalars.contains { isLatin($0.value) }
        case "ja":
            var s = saveCore(trimmed)
            s = s.replacingOccurrences(of: "^[A-ZＡ-Ｚ]{1,2}(?=[ァ-ヺー])", with: "", options: .regularExpression)  // l10n-ignore (pattern)
            guard !s.isEmpty else { return false }
            let jaOnly = s.unicodeScalars.allSatisfy {
                isKana($0.value) || isHan($0.value) || [0x30FC, 0x3005, 0x3006, 0x3007].contains($0.value) || ("0"..."9").contains(Character($0))
            }
            let real = s.unicodeScalars.contains { (isKana($0.value) && $0.value != 0x30FC) || isHan($0.value) }
            return jaOnly && real
        default:
            let s = saveCore(droppingHanLatinAffixes(trimmed))
            guard !s.isEmpty else { return false }
            for u in s.unicodeScalars {
                let v = u.value
                if isKana(v) || isLatin(v) || isLatinExtended(v) || isHangul(v) || (0x0400...0x04FF).contains(v) { return false }
            }
            if s.contains(where: { japaneseOnlyKanji.contains($0) }) { return false }
            return s.unicodeScalars.contains { isHan($0.value) || $0.value == 0x3007 }
        }
    }

    /// Kanji only Japan's new forms use (Taiwan writes 圖 for 図, 驛 for 駅, 貓 for 猫 — the server's kanji-forms.ts
    /// JA_ONLY), less the ones Taiwan also uses as standard characters (並 餅 岳 芸).
    static let japaneseOnlyKanji: Set<Character> = Set("万与両並乗乱亀争亜仏仮会伝体価倹児党円写処剣剤剰励労効勧勲区医単厳参双収号唖営嘱噛団囲図国圏圧堕塁塩増壊壌壮声壱売変奥奨嬢学宝実寛寝対寿専将尭尽届属岳峡巌巣巻帯帰庁広廃弐弥弾当径従徳徴応恋恒恵悩悪惨懐戦戯戻払抜択担拝拠拡挙挟挿捜掲掻揺摂撃撹数斉斎断旧昼晩暁暦曽条来枢栄桜桟桧検楼楽様権横欧歓歩歯歳歴残殴殻毎気沢浄浅浜涙渇済渉渋渓温湾湿満滝滞潜瀬灯炉点焼犠状独狭猟献獣画畳痩発盗県砕礼祷禄禅称稲穂穏穣窃竜粋粛糸経絵継続総緑縁縄縦繊繍聴胆脚脱脳臓艶芦芸茎荘蒋蔵薫薬虚虫蚕蛍蛮蝋装覇覚覧観触訳証誉説読謡譲豊賛践転軽辞辺逓遅遥郷酔醤醸釈鉄銭鋳錬録関閲闘陥険随隠雑霊静頼顔顕餅駅駆騒験髄髪鴎鶏鹸麦麹麺黄黒黙齢猫").subtracting("並餅岳芸")  // l10n-ignore (kanji table)

    /// target-profile.ts headwordCore: the headword without spaces and punctuation (brackets go, what is inside stays).
    static func saveCore(_ text: String) -> String {
        let drop = Set("，、。．・…！？!?,.:;：；「」『』（）()【】〔〕[]{}\"'‘’“”—–-~〜·")
        return String(text.filter { !$0.isWhitespace && !drop.contains($0) })
    }

    /// target-profile.ts dropHanLatinAffixes: 1–3 capital letters stuck straight onto a Han character (the T of T恤,
    /// the OK of 卡拉OK) are part of a Mandarin word; any other Latin run stays (and is refused).
    static func droppingHanLatinAffixes(_ raw: String) -> String {
        let chars = Array(raw)
        var out = ""
        var i = 0
        func han(_ c: Character?) -> Bool { c.map { $0.unicodeScalars.contains { isHan($0.value) || $0.value == 0x3007 } } ?? false }
        while i < chars.count {
            guard chars[i].isASCII, chars[i].isLetter else { out.append(chars[i]); i += 1; continue }
            var j = i
            while j < chars.count, chars[j].isASCII, chars[j].isLetter { j += 1 }
            let run = chars[i..<j]
            let capitals = run.count <= 3 && run.allSatisfy { $0.isUppercase }
            let touchesHan = han(i > 0 ? chars[i - 1] : nil) || han(j < chars.count ? chars[j] : nil)
            if !(capitals && touchesHan) { out.append(contentsOf: run) }
            i = j
        }
        return out
    }

    /// web resolveWordLanguage: keep the stored language when the headword fits it; otherwise move
    /// the word to the one other language it fits (never into Japanese — kana in a Mandarin row is a
    /// slip of the learner's own language, and Han-only words fit both). An empty language is Mandarin.
    static func resolveWordLanguage(stored: String?, headword: String) -> String {
        let raw = (stored ?? "").trimmingCharacters(in: .whitespaces)
        let lang = ["zh-TW", "en", "ja"].contains(raw) ? raw : "zh-TW"
        let word = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !headwordOk(word, target: lang) else { return lang }
        let fits = ["zh-TW", "en"].filter { $0 != lang && headwordOk(word, target: $0) }
        return fits.count == 1 ? fits[0] : lang
    }
}
