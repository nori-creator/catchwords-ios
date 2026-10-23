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
    /// The display language the server has for this account (`profiles.ui_language`), set when the profile is read and
    /// when a change is saved. The server writes every explanation in that one (`getExplanationLanguage`), and keys it
    /// by it — not by what this screen shows.
    nonisolated(unsafe) static var serverLang: String?

    /// A new explanation asked for now would be written in `lang`. Not while the screen's language has not reached the
    /// server (the save failed or is still on its way): the server would write it in the old language, under the old
    /// key, and the word page would ask again on every opening (one AI card each time).
    /// Unknown (never read, never saved) counts as not yet: the server's default is ja.
    static func serverWritesIn(_ lang: String) -> Bool { serverLang == lang }

    /// web `readerL1`: the display language when it differs from the learning language, else the old
    /// native language, else the first allowed choice. The choices are the display languages (web `L1_ORDER`, the
    /// same list in the same order), never the learning language.
    static func l1(native: String?, target: String) -> String {
        let choices = DisplayLanguages.codes.filter { $0 != target }
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
            let lists: [Int] = [e.usageChunks?.count ?? 0, e.usagePatterns?.count ?? 0, e.examplesExtra?.count ?? 0, e.measureWords?.count ?? 0,
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

    /// The word as this reader should see it: their explanation when there is one; the shared row's
    /// reader-language text only when that row was written for this very reader's language; nothing
    /// (rather than another language) otherwise.
    static func resolve(_ shared: Word, explanation picked: Explanation?, readerMeaning: String?, reader: String) -> Word {
        var w = shared
        // Only an explanation written for this reader's language (one read for the language before a switch is not).
        let explanation = picked?.explainLang == reader ? picked : nil
        // R23: the shared row is one per word for every reader, so its meaning, translation and notes are in the
        // language of whoever made the card first. They are used only for a reader of that language — never on the
        // strength of their letters alone (English on a Spanish screen, 漢字 on a Japanese one look right; on
        // 2026-10-20 about 10 of the 312 shared rows carried a mark that did not match their meaning's language).
        let sharedForReader = sharedTextIsFor(shared, reader: reader)
        let sharedMeaning = sharedForReader ? shared.meaningJa : nil
        let sharedTranslation = sharedForReader ? shared.exampleTranslation : nil
        let meanings = [explanation?.meaning, readerMeaning, sharedMeaning].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        w.meaningJa = meanings.first { !$0.isEmpty && !looksWrong($0, reader: reader, hanOnlyOk: true) } ?? ""
        let translations = [explanation?.exampleTranslation, sharedTranslation].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        w.exampleTranslation = translations.first { !$0.isEmpty && !looksWrong($0, reader: reader, source: shared.exampleSentence) }
        // A row for this reader wins even when still empty (it is being filled in the background).
        if let explanation {
            var extras = explanation.extras
            if let mark = extras?.explainLang?.trimmingCharacters(in: .whitespaces), !mark.isEmpty, mark != reader { extras = nil }
            w.extras = extras.map { scrub($0, reader: reader) }
        } else if let extras = shared.extras {
            // The shared notes of another reader's language: the learning-language parts (chunks, forms, kanji,
            // counters, the picture words) are still this word's, every explaining text is emptied.
            w.extras = sharedForReader ? scrub(extras, reader: reader) : learningOnly(extras)
        }
        // What is kept is this reader's: marked so. A word resolved again for another reader (the dex copy kept on the
        // phone, a language switch before the server's read) then never passes for its shared row's language — an
        // unmarked word reads as Japanese (`sharedTextIsFor`).
        if w.extras == nil { w.extras = WordExtras() }
        w.extras?.explainLang = reader
        return w
    }

    /// The shared row's reader-language text (meaning, translation, notes) was written for `reader`: its mark is that
    /// language. Rows from before the marks (107 of 312 on 2026-10-20) were all written while Japanese was the only
    /// display language, so an unmarked row is for the first display language only.
    static func sharedTextIsFor(_ shared: Word, reader: String) -> Bool {
        let mark = (shared.extras?.explainLang ?? "").trimmingCharacters(in: .whitespaces)
        return mark.isEmpty ? reader == DisplayLanguages.source : mark == reader
    }

    /// Drop single translations and notes that came back in another language (web `scrubForReader`
    /// and `scrubForeignNotes`) — never rewritten, only emptied.
    static func scrub(_ e: WordExtras, reader: String) -> WordExtras {
        clean(e, kanaReader: L10n.language(reader).script == .kana) { text, source, hanOnlyOk in
            looksWrong(text, reader: reader, source: source, hanOnlyOk: hanOnlyOk)
        }
    }

    /// Every explaining text emptied, the learning-language parts kept: the shared notes of a word whose
    /// notes were written for another reader's language.
    static func learningOnly(_ e: WordExtras) -> WordExtras {
        var e = clean(e, kanaReader: false) { _, _, _ in true }
        e.explainLang = nil
        return e
    }

    /// Empties each reader-language text `drop(text, source, hanOnlyOk)` says to drop. The one list of the extras'
    /// reader-language fields: a field added to `WordExtras` in the reader's language is added here. `hanOnlyOk` only
    /// for words (a part's or a kanji's meaning, a form's name), where a Japanese word can be all kanji: notes, scene
    /// labels and chunk translations of 5+ kanji with no kana are Chinese on a Japanese screen (owner report
    /// 「量詞の説明が台湾華語になってる」).
    private static func clean(_ e: WordExtras, kanaReader: Bool, drop: (String?, String?, Bool) -> Bool) -> WordExtras {
        var e = e
        if drop(e.exampleScene, nil, false) { e.exampleScene = nil }
        e.examplesExtra = e.examplesExtra?.map { x in
            var x = x
            if drop(x.ja, x.zh, false) { x.ja = "" }
            if drop(x.scene, nil, false) { x.scene = "" }
            return x
        }
        e.usageChunks = e.usageChunks?.map { c in
            var c = c
            if drop(c.ja, nil, false) { c.ja = "" }
            // A swappable part's meaning and its choices' meanings are in the reader's language too (R6).
            c.parts = c.parts.map { p in
                var p = p
                if let j = p.ja, drop(j, nil, true) { p.ja = nil }
                p.alts = p.alts?.map { a in
                    drop(a.ja, nil, true) ? ChunkAlt(text: a.text, ja: "") : a
                }
                return p
            }
            return c
        }
        // A pattern's scene, note, translation and its formula's meanings are the reader's (R26); its sentence stays.
        e.usagePatterns = e.usagePatterns?.map { pat in
            var pat = pat
            if drop(pat.scene, nil, false) { pat.scene = "" }
            if drop(pat.note, nil, false) { pat.note = "" }
            if drop(pat.example.ja, pat.example.zh, false) { pat.example.ja = "" }
            if drop(pat.chunk.ja, nil, false) { pat.chunk.ja = "" }
            pat.chunk.parts = pat.chunk.parts.map { p in
                var p = p
                if let j = p.ja, drop(j, nil, true) { p.ja = nil }
                p.alts = p.alts?.map { a in drop(a.ja, nil, true) ? ChunkAlt(text: a.text, ja: "", pinyin: a.pinyin, zhuyin: a.zhuyin) : a }
                return p
            }
            return pat
        }
        e.measureWords = e.measureWords?.map { m in
            var m = m
            if drop(m.note, nil, false) { m.note = "" }
            return m
        }
        e.relatedWords = e.relatedWords?.map { r in
            var r = r
            if drop(r.note, nil, false) { r.note = "" }
            return r
        }
        // English and Japanese sections: the explanatory parts are in the reader's language; the
        // learning-language parts (forms, phrases, kanji, conjugated forms, counters) are left alone.
        if var c = e.countability { if drop(c.note, nil, false) { c.note = "" }; e.countability = c }
        if var st = e.stress { if drop(st.note, nil, false) { st.note = "" }; e.stress = st }
        e.phrasalVerbs = e.phrasalVerbs?.map { p in
            var p = p
            if drop(p.meaning, nil, true) { p.meaning = "" }
            return p
        }
        e.etymologyRelatives = e.etymologyRelatives?.map { w in
            var w = w
            if drop(w.note, nil, false) { w.note = "" }
            return w
        }
        e.kanjiBreakdown = e.kanjiBreakdown?.map { k in
            var k = k
            if drop(k.meaning, nil, true) { k.meaning = "" }
            return k
        }
        e.conjugation = e.conjugation?.map { r in
            var r = r
            if drop(r.form, nil, true) { r.form = "" }
            return r
        }
        e.counters = e.counters?.map { c in
            var c = c
            if drop(c.note, nil, false) { c.note = "" }
            return c
        }
        let notes: [WritableKeyPath<WordExtras, String?>] = [\.mnemonic, \.taiwanNote, \.pronunciationTips, \.studyTips,
                                                              \.etymology, \.trivia, \.usageNote, \.synonymDiff, \.usageContext, \.radicals,
                                                              \.cultureNote, \.japanNote]
        for kp in notes where drop(e[keyPath: kp], nil, false) {
            e[keyPath: kp] = nil
        }
        // Japanese-card notes cite the word's kana unquoted (「は↘し＝頭高型」): judged without kana for other readers
        // (for a Japanese reader the kana are part of the Japanese note).
        let kanaCiting: [WritableKeyPath<WordExtras, String?>] = [\.pitchAccent, \.politeness, \.wordOrigin]
        for kp in kanaCiting {
            let whole = e[keyPath: kp] ?? ""
            let t = kanaReader ? whole : String(whole.unicodeScalars.filter { !LanguageRules.isKana($0.value) }.map(Character.init))
            if drop(t, nil, false) { e[keyPath: kp] = nil }
        }
        return e
    }
}
