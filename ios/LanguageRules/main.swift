// Language-mixing regression check (docs/language-rules.md).
// Language-mixing and chunk rules (docs/chunk-rules.md) regression check.
// CI: swiftc ios/Shared/DisplayLanguages.swift ios/CatchWords/Utilities/LanguageRules.swift ios/CatchWords/Utilities/ChunkRules.swift \
//       ios/LanguageRules/main.swift -o lr
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

/// "跟:Prep+~男朋友:N+吵架:V" → parts. A leading ~ is a part the AI marked swappable (with one other word).
func parseChunk(_ spec: String) -> [ChunkPart] {
    spec.split(separator: "+").map { raw in
        var t = String(raw)
        let slot = t.hasPrefix("~")
        if slot { t.removeFirst() }
        let bits = t.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return ChunkPart(text: bits[0], pos: bits.count > 1 ? bits[1] : "", slot: slot ? true : nil,
                         alts: slot ? [ChunkAlt(text: "X", ja: "")] : nil)
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
