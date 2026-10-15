import Foundation

/// Server-written text (meanings, translations, notes) shown only in the reader's language.
///
/// Words are one shared row per (language, headword), so the meaning and notes on that row are in the
/// language of whoever made the card first. The reader's own explanation lives in
/// `word_explanations (word_id, explain_lang, l1)`. This file ports the web's rules for choosing
/// between them (`word-explanation.ts`, `note-language.ts`, `reader-language.ts`), so a Japanese
/// meaning never shows on an English or Chinese screen — or the other way round.
nonisolated enum ReaderLanguage {
    /// The language explanations are written in (= display language).
    static var explainLang: String { L10n.lang }
    /// The learner's old native language (`profiles.native_language`), set when the profile loads.
    nonisolated(unsafe) static var native: String?

    /// web `readerL1`: the display language when it differs from the learning language, else the old
    /// native language, else the first allowed choice.
    static func l1(native: String?, target: String) -> String {
        let order = ["ja", "en", "zh-TW"]
        let choices = order.filter { $0 != target }
        if choices.contains(L10n.lang) { return L10n.lang }
        if let n = native, choices.contains(n) { return n }
        return choices.first ?? "ja"
    }

    // MARK: - looksWrongForReader (note-language.ts) — rules live in LanguageRules

    static func looksWrong(_ text: String?, reader: String, source: String? = nil, hanOnlyOk: Bool = false) -> Bool {
        LanguageRules.looksWrong(text, reader: reader, source: source, hanOnlyOk: hanOnlyOk)
    }

    /// A meaning as a short gloss, for the places that show it as a name or a question (quiz, card, tags,
    /// word rows). Some meanings come back as a whole descriptive sentence (owner report 2026-10-04: the quiz
    /// asked 「<a sentence>」はどれ？). Display only — the stored meaning and the word page keep the full text.
    /// Short text is returned as it is; longer text is cut at its first clause (。；、/ ( : …, and for Latin
    /// text ; . ( : — never a comma inside a phrase), else at a word boundary, with "…".
    static func gloss(_ text: String, limit: Int? = nil) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let latin = t.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
            && !t.unicodeScalars.contains { $0.value >= 0x3000 }
        let cap = limit ?? (latin ? 40 : 20)
        guard t.count > cap else { return t }
        let separators: [String] = latin
            ? ["; ", ";", ". ", " (", "(", ": ", " - ", " — ", "\n"]
            : ["。", "；", ";", "、", "，", ",", "／", "/", "（", "(", "：", ":", "\n", "．"]
        var cut = t.endIndex
        for sep in separators {
            if let r = t.range(of: sep), r.lowerBound < cut, r.lowerBound > t.startIndex { cut = r.lowerBound }
        }
        let first = String(t[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty, first.count <= cap { return first }
        var head = String(first.prefix(cap - 1))
        if latin, let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) >= cap / 2 {
            head = String(head[..<space])
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }

    /// The first of `texts` written in the display language, or "" (never another language).
    static func shown(_ texts: String?..., source: String? = nil, hanOnlyOk: Bool = true) -> String {
        for t in texts {
            let v = (t ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty, !looksWrong(v, reader: L10n.lang, source: source, hanOnlyOk: hanOnlyOk) { return v }
        }
        return ""
    }

    // MARK: - Explanation rows (word_explanations)

    nonisolated struct Explanation: Decodable, Sendable, Hashable {
        let explainLang: String
        let l1: String
        let meaning: String
        let exampleTranslation: String?
        let extras: WordExtras?
        let source: String?

        enum CodingKeys: String, CodingKey {
            case l1, meaning, extras, source
            case explainLang = "explain_lang"
            case exampleTranslation = "example_translation"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            explainLang = (try? c.decode(String.self, forKey: .explainLang)) ?? ""
            l1 = (try? c.decode(String.self, forKey: .l1)) ?? ""
            meaning = (try? c.decode(String.self, forKey: .meaning)) ?? ""
            exampleTranslation = try? c.decodeIfPresent(String.self, forKey: .exampleTranslation)
            extras = try? c.decodeIfPresent(WordExtras.self, forKey: .extras)
            source = try? c.decodeIfPresent(String.self, forKey: .source)
        }

        /// web `hasExtrasContent`: anything beyond the language marks.
        var hasContent: Bool {
            guard let e = extras else { return false }
            let lists: [Int] = [e.usageChunks?.count ?? 0, e.examplesExtra?.count ?? 0, e.measureWords?.count ?? 0,
                                e.relatedWords?.count ?? 0, e.synonyms?.count ?? 0, e.antonyms?.count ?? 0,
                                e.phrasalVerbs?.count ?? 0, e.kanjiBreakdown?.count ?? 0, e.conjugation?.count ?? 0,
                                e.counters?.count ?? 0]
            if lists.contains(where: { $0 > 0 }) { return true }
            if e.forms != nil || e.countability != nil || e.stress != nil { return true }
            let texts: [String?] = [e.mnemonic, e.taiwanNote, e.pronunciationTips, e.studyTips, e.etymology, e.radicals,
                                    e.trivia, e.usageNote, e.synonymDiff, e.usageContext, e.cultureNote, e.pitchAccent,
                                    e.politeness, e.wordOrigin, e.japanNote]
            return texts.contains { !($0 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    /// web `needsGeneration`: there is no explanation for exactly this reader yet (or it is empty).
    static func needsGeneration(_ picked: Explanation?, lang: String, l1: String) -> Bool {
        guard let p = picked else { return true }
        if p.explainLang != lang || p.l1 != l1 { return true }
        if p.meaning.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return !p.hasContent
    }

    // MARK: - resolveDisplayWord (word-explanation.ts) + scrubForReader

    /// The word as this reader should see it: their explanation when there is one; the shared row
    /// only where it is written in their language; nothing (rather than another language) otherwise.
    static func resolve(_ shared: Word, explanation: Explanation?, readerMeaning: String?, reader: String) -> Word {
        var w = shared
        let meanings = [explanation?.meaning, readerMeaning, shared.meaningJa].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        w.meaningJa = meanings.first { !$0.isEmpty && !looksWrong($0, reader: reader, hanOnlyOk: true) } ?? ""
        let translations = [explanation?.exampleTranslation, shared.exampleTranslation].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        w.exampleTranslation = translations.first { !$0.isEmpty && !looksWrong($0, reader: reader, source: shared.exampleSentence) }
        // A row for this reader wins even when still empty (it is being filled in the background).
        var extras = explanation != nil ? explanation?.extras : shared.extras
        if let mark = extras?.explainLang?.trimmingCharacters(in: .whitespaces), !mark.isEmpty, mark != reader { extras = nil }
        w.extras = extras.map { scrub($0, reader: reader) }
        return w
    }

    /// Drop single translations and notes that came back in another language (web `scrubForReader`
    /// and `scrubForeignNotes`) — never rewritten, only emptied.
    static func scrub(_ e: WordExtras, reader: String) -> WordExtras {
        var e = e
        e.examplesExtra = e.examplesExtra?.map { x in
            var x = x
            if looksWrong(x.ja, reader: reader, source: x.zh) { x.ja = "" }
            if looksWrong(x.scene, reader: reader, hanOnlyOk: true) { x.scene = "" }
            return x
        }
        e.usageChunks = e.usageChunks?.map { c in
            var c = c
            if looksWrong(c.ja, reader: reader, hanOnlyOk: true) { c.ja = "" }
            // A swappable part's meaning and its choices' meanings are in the reader's language too (R6).
            c.parts = c.parts.map { p in
                var p = p
                if let j = p.ja, looksWrong(j, reader: reader, hanOnlyOk: true) { p.ja = nil }
                p.alts = p.alts?.map { a in
                    looksWrong(a.ja, reader: reader, hanOnlyOk: true) ? ChunkAlt(text: a.text, ja: "") : a
                }
                return p
            }
            return c
        }
        e.measureWords = e.measureWords?.map { m in
            var m = m
            if looksWrong(m.note, reader: reader, hanOnlyOk: true) { m.note = "" }
            return m
        }
        e.relatedWords = e.relatedWords?.map { r in
            var r = r
            if looksWrong(r.note, reader: reader, hanOnlyOk: true) { r.note = "" }
            return r
        }
        // English and Japanese sections: the explanatory parts are in the reader's language; the
        // learning-language parts (forms, phrases, kanji, conjugated forms, counters) are left alone.
        if var c = e.countability { if looksWrong(c.note, reader: reader) { c.note = "" }; e.countability = c }
        if var st = e.stress { if looksWrong(st.note, reader: reader) { st.note = "" }; e.stress = st }
        e.phrasalVerbs = e.phrasalVerbs?.map { p in
            var p = p
            if looksWrong(p.meaning, reader: reader, hanOnlyOk: true) { p.meaning = "" }
            return p
        }
        e.etymologyRelatives = e.etymologyRelatives?.map { w in
            var w = w
            if looksWrong(w.note, reader: reader, hanOnlyOk: true) { w.note = "" }
            return w
        }
        e.kanjiBreakdown = e.kanjiBreakdown?.map { k in
            var k = k
            if looksWrong(k.meaning, reader: reader, hanOnlyOk: true) { k.meaning = "" }
            return k
        }
        e.conjugation = e.conjugation?.map { r in
            var r = r
            if looksWrong(r.form, reader: reader, hanOnlyOk: true) { r.form = "" }
            return r
        }
        e.counters = e.counters?.map { c in
            var c = c
            if looksWrong(c.note, reader: reader, hanOnlyOk: true) { c.note = "" }
            return c
        }
        let notes: [WritableKeyPath<WordExtras, String?>] = [\.mnemonic, \.taiwanNote, \.pronunciationTips, \.studyTips,
                                                              \.etymology, \.trivia, \.usageNote, \.synonymDiff, \.usageContext, \.radicals,
                                                              \.cultureNote, \.japanNote]
        for kp in notes where looksWrong(e[keyPath: kp], reader: reader) {
            e[keyPath: kp] = nil
        }
        // Japanese-card notes cite the word's kana unquoted (「は↘し＝頭高型」): judge them without kana.
        let kanaCiting: [WritableKeyPath<WordExtras, String?>] = [\.pitchAccent, \.politeness, \.wordOrigin]
        for kp in kanaCiting {
            let t = String((e[keyPath: kp] ?? "").unicodeScalars.filter { !LanguageRules.isKana($0.value) }.map(Character.init))
            if looksWrong(t, reader: reader) { e[keyPath: kp] = nil }
        }
        return e
    }
}
