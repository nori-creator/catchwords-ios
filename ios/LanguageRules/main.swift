// Language-mixing regression check (docs/language-rules.md).
// Language-mixing and chunk rules (docs/chunk-rules.md) regression check.
// CI: swiftc ios/Shared/DisplayLanguages.swift ios/CatchWords/Utilities/LanguageRules.swift ios/CatchWords/Utilities/ChunkRules.swift \
//       ios/CatchWords/Utilities/Sentences.swift ios/LanguageRules/main.swift -o lr
//     && ./lr ios/LanguageRules/cases.json
import Foundation

struct Case: Decodable {
    let id: String
    let rule: String
    let fn: String
    let text: String
    let reader: String?
    let target: String?
    let source: String?
    let hanOnlyOk: Bool?
    let expect: Bool
    /// tidyChunk: the chunk as it is drawn.
    let expected: String?
    /// swapTranslation: the chunk, and "index=word" swapped into it.
    let chunk: String?
    let pick: String?
    let why: String
}

/// "跟:Prep+~男朋友:N+吵架:V" → parts. A leading ~ is a part the AI marked swappable: with two other words (X, Y), or
/// with the ones written after it ("~塞住了|不通|壞了:V"). A word may carry its gloss after = ("~很=とても|有點=ちょっと|超=すごく:Adv").
func parseChunk(_ spec: String) -> [ChunkPart] {
    spec.split(separator: "+").map { raw in
        var t = String(raw)
        let slot = t.hasPrefix("~")
        if slot { t.removeFirst() }
        let bits = t.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let words = bits[0].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let alts = words.count > 1 ? Array(words.dropFirst()) : ["X", "Y"]
        let own = words[0].split(separator: "=", maxSplits: 1).map(String.init)
        return ChunkPart(text: own[0], pos: bits.count > 1 ? bits[1] : "", slot: slot ? true : nil, ja: own.count > 1 ? own[1] : nil,
                         alts: slot ? alts.map { a in
                             let kv = a.split(separator: "=", maxSplits: 1).map(String.init)
                             return ChunkAlt(text: kv[0], ja: kv.count > 1 ? kv[1] : "")
                         } : nil)
    }
}

/// The drawn chunk: "-" when it is not shown as a pattern; ~ marks a block that opens the wheel.
func drawChunk(_ spec: String, headword: String, target: String, reader: String) -> String {
    let original = parseChunk(spec)
    let parts = ChunkRules.tidy(original, headword: headword, target: target, reader: reader)
    guard ChunkRules.isPattern(original: original, tidied: parts) else { return "-" }
    return parts.map { (ChunkRules.isSwappable($0, headword: headword, target: target) ? "~" : "") + "\($0.text):\($0.pos)" }
        .joined(separator: "+")
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ios/LanguageRules/cases.json"
guard let data = FileManager.default.contents(atPath: path),
      let cases = try? JSONDecoder().decode([Case].self, from: data) else {
    print("::error::cannot read \(path)")
    exit(2)
}

var failed = 0
var ids = Set<String>()
for c in cases {
    if !ids.insert(c.id).inserted { print("::error::duplicate case id \(c.id)"); failed += 1 }
    let got: Bool
    switch c.fn {
    case "looksWrong": got = LanguageRules.looksWrong(c.text, reader: c.reader ?? "", source: c.source, hanOnlyOk: c.hanOnlyOk ?? false)
    case "readsAs": got = LanguageRules.readsAs(c.text, c.reader ?? "")
    case "isIn": got = LanguageRules.isIn(c.text, target: c.target ?? "")
    case "headwordOk": got = LanguageRules.headwordOk(c.text, target: c.target ?? "")
    case "mentionsHeadword": got = LanguageRules.mentionsHeadword(c.text, headword: c.source ?? "", target: c.target ?? "")
    case "heroSearchQuery": got = LanguageRules.heroSearchQuery(headword: c.source, meaning: c.text) == (c.target ?? "")
    case "tidyChunk":
        let drawn = drawChunk(c.text, headword: c.source ?? "", target: c.target ?? "", reader: c.reader ?? "ja")
        got = drawn == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] drew \(drawn), expected \(c.expected ?? "") — \(c.why)") }
    case "swapTranslation":
        let parts = ChunkRules.tidy(parseChunk(c.chunk ?? ""), headword: c.source ?? "", target: c.target ?? "", reader: c.reader ?? "ja")
        var shown = parts
        for p in (c.pick ?? "").split(separator: ",") {
            let kv = p.split(separator: "=").map(String.init)
            if kv.count == 2, let i = Int(kv[0]), i < shown.count { shown[i].text = kv[1] }
        }
        let out = ChunkRules.swappedTranslation(c.text, original: parts, shown: shown, reader: c.reader ?? "ja")
        got = out == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] translated \(out), expected \(c.expected ?? "") — \(c.why)") }
    case "brokenChunk":
        // text = the chunk translation, chunk = its parts, source = headword, target = learning language.
        got = ChunkRules.isBroken(UsageChunk(parts: parseChunk(c.chunk ?? ""), ja: c.text), headword: c.source ?? "", target: c.target ?? "")
    case "resolveLanguage": got = LanguageRules.resolveWordLanguage(stored: c.reader, headword: c.text) == c.target
    case "chunkRole":
        // text = the chunk, source = headword; expected = the roles joined with +.
        let roles = parseChunk(c.text).map { p -> String in
            switch ChunkRules.role(p, headword: c.source ?? "", target: c.target ?? "") {
            case .head: "head"
            case .partner: "partner"
            case .frame: "frame"
            }
        }.joined(separator: "+")
        got = roles == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] roles \(roles), expected \(c.expected ?? "") — \(c.why)") }
    case "chunkSpan":
        // text = the sentence, chunk = the formula; expected = the run of the formula in it, "-" for none.
        let span = ChunkRules.spanText(of: UsageChunk(parts: parseChunk(c.chunk ?? ""), ja: ""), in: c.text, target: c.target ?? "") ?? "-"
        got = span == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] span \(span), expected \(c.expected ?? "") — \(c.why)") }
    case "legacyPatterns":
        // chunk = the formulas joined by " / ", text = the sentences "zh=scene" joined by " / "; expected = one letter pair per
        // block in order: CE (formula with its sentence), C (formula alone), E (sentence alone), joined by +.
        let chunks = (c.chunk ?? "").components(separatedBy: " / ").filter { !$0.isEmpty }.map { UsageChunk(parts: parseChunk($0), ja: "") }
        let examples = c.text.components(separatedBy: " / ").filter { !$0.isEmpty }.map { e -> ChunkRules.LegacyExample in
            let kv = e.split(separator: "=", maxSplits: 1).map(String.init)
            return ChunkRules.LegacyExample(zh: kv[0], ja: "", scene: kv.count > 1 ? kv[1] : "")
        }
        let out = ChunkRules.patternsFromLegacy(chunks: chunks, examples: examples, headword: c.source ?? "", target: c.target ?? "zh-TW")
            .map { ($0.chunk.parts.isEmpty ? "" : "C") + ($0.example.zh.isEmpty ? "" : "E") }.joined(separator: "+")
        got = out == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] blocks \(out), expected \(c.expected ?? "") — \(c.why)") }
    case "unbreakable":
        // text = the sentence, source = its words (comma-separated); expected writes the joiner as _.
        let words = (c.source ?? "").split(separator: ",").map(String.init)
        let out = Sentences.unbreakable(c.text, words: words).replacingOccurrences(of: "\u{2060}", with: "_")
        got = out == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] joined \(out), expected \(c.expected ?? "") — \(c.why)") }
    case "exampleHit":
        // text = the sentence, chunk = the chunks joined by " / " in the card's order; expected = "number:start:length"
        // (number 1-based, start in characters) and the parts' texts per character joined by ",", or "-" for none.
        let chunks = (c.chunk ?? "").components(separatedBy: " / ").filter { !$0.isEmpty }.map { UsageChunk(parts: parseChunk($0), ja: "") }
        let out: String
        if let hit = ChunkRules.exampleHit(sentence: c.text, chunks: chunks, target: c.target ?? "zh-TW") {
            out = "\(hit.chunk + 1):\(hit.start):\(hit.length) " + hit.parts.map(\.text).joined(separator: ",")
        } else {
            out = "-"
        }
        got = out == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] hit \(out), expected \(c.expected ?? "") — \(c.why)") }
    case "exampleGroups":
        // text = the sentence, source = its words (comma-separated), chunk = "start:length" of the chunk's run or "";
        // expected = the runs joined by "|".
        let chars = Array(c.text).map(String.init)
        let words = (c.source ?? "").split(separator: ",").map(String.init)
        let bits = (c.chunk ?? "").split(separator: ":").compactMap { Int($0) }
        let span = bits.count == 2 ? bits[0]..<(bits[0] + bits[1]) : nil
        let out = ChunkRules.exampleGroups(chars, words: words, span: span).map { g in g.map { chars[$0] }.joined() }.joined(separator: "|")
        got = out == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] runs \(out), expected \(c.expected ?? "") — \(c.why)") }
    case "exampleLines":
        // text = the runs' widths (comma-separated), source = "gap,first,rest"; expected = the runs per line, lines joined by "|".
        let widths = c.text.split(separator: ",").compactMap { Double($0) }
        let g = (c.source ?? "").split(separator: ",").compactMap { Double($0) }
        let out = g.count == 3
            ? ChunkRules.lines(widths: widths, gap: g[0], first: g[1], rest: g[2]).map { $0.map(String.init).joined(separator: ",") }.joined(separator: "|")
            : "?"
        got = out == (c.expected ?? "")
        if !got { print("::error::\(c.id) [\(c.rule)] lines \(out), expected \(c.expected ?? "") — \(c.why)") }
    default:
        print("::error::\(c.id): unknown fn \(c.fn)"); failed += 1; continue
    }
    if got != c.expect {
        failed += 1
        print("::error::\(c.id) [\(c.rule)] \(c.fn)(\"\(c.text)\", reader: \(c.reader ?? "-"), target: \(c.target ?? "-")) = \(got), expected \(c.expect) — \(c.why)")
    }
}
print("Language rules: \(cases.count - failed)/\(cases.count) cases pass.")
exit(failed == 0 ? 0 : 1)
