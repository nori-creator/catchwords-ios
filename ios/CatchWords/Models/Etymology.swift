import Foundation

/// 語源・部首 as a diagram (owner 2026-10-15, as on the web): each character's box (the character, what it is built
/// from, what that means) joined with + into the word's box (the word and what it means), highlighted —
/// [曖 / 日+愛 / 日がかげる] + [昧 / 日+未 / 夜明け前] = [曖昧 / はっきり見えない].
/// A word that cannot be taken apart gets what fits it instead: one character's box with its radical (`single`),
/// where the sound came from for a loanword or a transliteration (`loanword`: 沙發 — 英語 sofa の音から), or a line about
/// a brand or another word (`proper`, `other`).
///
/// Read leniently from `extras.etymology_diagram` (server nori-creator/Lovable-catch-words-app#183: `{kind: compound |
/// single_char | loanword_phonetic | proper | other, parts: [{text, components, meaning}], result_meaning, source,
/// note}`; null on older cards); anything that would draw an empty or broken diagram is not a diagram (`drawable`): the
/// page then shows the prose.
nonisolated struct EtymologyDiagram: Codable, Sendable, Hashable {
    nonisolated enum Kind: String, Sendable, Hashable { case compound, single, loanword, proper, other }

    /// One character: 曖, built from 日 and 愛, meaning 日がかげる.
    nonisolated struct Part: Sendable, Hashable {
        var char: String
        var components: [String]
        var meaning: String
    }

    var kind: Kind
    var parts: [Part]
    /// The whole word (empty: the headword).
    var word: String
    /// What the whole word means.
    var meaning: String
    /// A sentence about it, in the reader's language (a loanword: 英語 sofa の音から).
    var note: String
    /// The foreign word it sounds like (sofa), for a loanword.
    var source: String
    /// As the server sent it (written back unchanged).
    var raw: JSONValue

    /// The key the server writes it under, then other names of the same thing.
    static let keys = ["etymology_diagram", "etymology_parts", "etymology_structure", "char_breakdown"]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let parsed = Self.parse(value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no etymology"))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }

    init(kind: Kind, parts: [Part], word: String = "", meaning: String = "", note: String = "", source: String = "",
         raw: JSONValue = .null) {
        self.kind = kind
        self.parts = parts
        self.word = word
        self.meaning = meaning
        self.note = note
        self.source = source
        self.raw = raw
    }

    /// The diagram in an extras object, under any of its names (nil when none reads).
    static func find(in extras: [String: JSONValue]?) -> EtymologyDiagram? {
        guard let extras else { return nil }
        for k in keys { if let v = extras[k], let d = parse(v) { return d } }
        return nil
    }

    /// The same, read straight from the extras being decoded (only its own keys are read).
    static func find(in decoder: Decoder) -> EtymologyDiagram? {
        guard let c = try? decoder.container(keyedBy: AnyKey.self) else { return nil }
        for k in keys {
            guard let key = AnyKey(stringValue: k), c.contains(key),
                  let v = try? c.decode(JSONValue.self, forKey: key), let d = parse(v) else { continue }
            return d
        }
        return nil
    }

    private nonisolated struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    // MARK: Reading

    static func parse(_ value: JSONValue) -> EtymologyDiagram? {
        switch value {
        case .array(let items):
            let parts = items.compactMap(part)
            guard !parts.isEmpty else { return nil }
            return EtymologyDiagram(kind: parts.count > 1 ? .compound : .single, parts: parts, raw: value)
        case .null:
            return nil
        case .object(let o):
            let parts = array(o, ["parts", "chars", "characters", "components", "items", "breakdown"]).compactMap(part)
            var word = text(o, ["word", "whole", "combined", "headword"])
            var meaning = text(o, ["meaning", "result_meaning", "word_meaning", "gloss", "whole_meaning"])
            if let result = o["result"] {
                if case .object(let r) = result {
                    if word.isEmpty { word = text(r, ["word", "char", "text", "headword"]) }
                    if meaning.isEmpty { meaning = text(r, ["meaning", "gloss", "sense"]) }
                } else if word.isEmpty, let w = result.string {
                    word = w.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            let note = text(o, ["note", "explanation", "summary", "origin", "description", "loan_note", "reason"])
            let source = text(o, ["source", "source_word", "origin_word", "from", "loan_source", "sound_of"])
            let declared = kindNamed(text(o, ["kind", "type", "mode", "category"]))
            let k: Kind = declared ?? (parts.count > 1 ? .compound : parts.count == 1 ? .single : source.isEmpty ? .other : .loanword)
            return EtymologyDiagram(kind: k, parts: parts, word: word, meaning: meaning, note: note, source: source, raw: value)
        default:
            return nil
        }
    }

    private static func kindNamed(_ raw: String) -> Kind? {
        let v = raw.lowercased()
        guard !v.isEmpty else { return nil }
        let loanword = ["phonetic", "loan", "translit", "sound", "borrow", "foreign", "音訳", "音譯", "外来", "外來"]  // l10n-ignore (data values)
        if loanword.contains(where: { v.contains($0) }) { return .loanword }
        if ["proper", "brand", "trademark"].contains(where: { v.contains($0) }) { return .proper }
        if v == "other" || v == "none" || v == "unknown" { return .other }
        let single = ["single", "pictograph", "simple", "radical", "indivisible", "象形", "指事"]  // l10n-ignore (data values)
        if single.contains(where: { v.contains($0) }) { return .single }
        let compound = ["compound", "component", "combin", "semantic", "decompos", "parts", "形声", "形聲", "会意", "會意"]  // l10n-ignore (data values)
        if compound.contains(where: { v.contains($0) }) { return .compound }
        return nil
    }

    private static func part(_ value: JSONValue) -> Part? {
        switch value {
        case .string(let s):
            let c = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? nil : Part(char: c, components: [], meaning: "")
        case .object(let o):
            let c = text(o, ["char", "character", "hanzi", "kanji", "glyph", "c", "text"])
            guard !c.isEmpty else { return nil }
            var comps = array(o, ["components", "parts", "radicals", "structure", "pieces", "made_of"]).compactMap { v -> String? in
                if let s = v.string { return s }
                if case .object(let p) = v { return text(p, ["char", "text", "part", "component"]) }
                return nil
            }
            if comps.isEmpty { comps = split(text(o, ["components", "parts", "radicals", "structure", "formula", "made_of"])) }
            comps = comps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return Part(char: c, components: comps, meaning: text(o, ["meaning", "gloss", "sense", "note", "meaning_ja"]))
        default:
            return nil
        }
    }

    /// 「日+愛」 / 「日＋愛」 / 「日・愛」 → 日, 愛.
    private static func split(_ s: String) -> [String] {
        s.split(whereSeparator: { "+＋・、,，/".contains($0) }).map(String.init)
    }

    private static func text(_ o: [String: JSONValue], _ keys: [String]) -> String {
        for k in keys {
            if let s = o[k]?.string {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return ""
    }

    private static func array(_ o: [String: JSONValue], _ keys: [String]) -> [JSONValue] {
        for k in keys { if case .array(let a)? = o[k], !a.isEmpty { return a } }
        return []
    }

    // MARK: Drawing

    /// What to draw for `headword`, or nil when the data would draw an empty or broken diagram:
    /// - compound: two or more characters of the word, each with what it is built from or what it means;
    /// - single: one character with its parts or meaning;
    /// - loanword: where the sound came from (a note or the source word); proper / other: their note.
    /// Boxes that would be broken with a note to say instead show the note (`other`).
    func drawable(for headword: String) -> EtymologyDiagram? {
        var d = self
        let word = (d.word.isEmpty ? headword : d.word).trimmingCharacters(in: .whitespacesAndNewlines)
        d.word = word
        let explained = d.parts.filter { !$0.components.isEmpty || !$0.meaning.isEmpty }
        let noteOnly: EtymologyDiagram? = d.note.isEmpty ? nil
            : EtymologyDiagram(kind: .other, parts: [], word: word, meaning: d.meaning, note: d.note, source: d.source, raw: d.raw)
        switch d.kind {
        case .compound:
            // Every box has something under its character, and every character is one of the word's.
            guard d.parts.count >= 2, explained.count == d.parts.count,
                  d.parts.allSatisfy({ word.contains($0.char) }) else {
                // A compound written for one character only reads as that character's box.
                if d.parts.count == 1, explained.count == 1 { d.kind = .single; return d }
                return noteOnly
            }
            return d
        case .single:
            guard let first = d.parts.first, !first.components.isEmpty || !first.meaning.isEmpty else { return noteOnly }
            d.parts = [first]
            return d
        case .loanword:
            d.parts = []
            return d.note.isEmpty && d.source.isEmpty ? nil : d
        case .proper, .other:
            d.parts = []
            return d.note.isEmpty ? nil : d
        }
    }

    /// The same diagram with every reader-language text that came back in another language emptied
    /// (`ReaderLanguage.scrub`); never rewritten.
    func scrubbed(_ wrong: (String) -> Bool) -> EtymologyDiagram {
        var d = self
        d.parts = d.parts.map { p in
            var p = p
            if wrong(p.meaning) { p.meaning = "" }
            return p
        }
        if wrong(d.meaning) { d.meaning = "" }
        if wrong(d.note) { d.note = "" }
        return d
    }

    /// What VoiceOver reads: each box, then the word.
    var spoken: String {
        let boxes = parts.map { ([$0.char, $0.components.joined(separator: "+"), $0.meaning].filter { !$0.isEmpty }).joined(separator: "、") }
        let whole = [word, meaning].filter { !$0.isEmpty }.joined(separator: "、")
        return (boxes + [whole, note]).filter { !$0.isEmpty }.joined(separator: "。")
    }
}
