import Foundation

/// 「量詞」の欄で、量を二重にしない（オーナー 2026-11-23: 「一杯のコーヒー」と打って保存された 一杯咖啡 に、量詞 一杯 が付いて
/// 「一杯 一杯咖啡」になった）。欄は「一 + 量詞 + その物」で組むので、見出し語の頭にもう数・量詞が付いている古い語
/// （句のまま保存された物）では、その頭を外した物の名前（咖啡）を並べる。外し方はサーバーの `typed-head-noun.ts`
/// （`headNounOf`）と同じ: 頭の「数／這・那・每・哪 + 量詞（+ 的）」だけで、残りが2字以上の漢字の時だけ。九層塔・五花肉・
/// 三明治のように2字目が量詞でない語は割らない。
nonisolated enum MeasureCount {
    private static let numerals = Set("一二兩三四五六七八九十幾半")  // l10n-ignore (target word)
    private static let demonstratives: Set<Character> = ["這", "那", "每", "哪"]  // l10n-ignore (target word)
    private static let measures = Set("杯個隻張份條本瓶碗盤塊顆片件雙台臺輛支枝把盒包罐袋串朵棵位間家粒根頂座副套盞匹頭株捲疊箱桶壺籃鍋")  // l10n-ignore (target word)

    /// The thing's own name in `headword` and how many characters were taken off its front (一杯咖啡 → 咖啡, 2).
    /// A headword with no number and measure word in front comes back whole (0).
    static func noun(of headword: String) -> (noun: String, dropped: Int) {
        let chars = Array(headword.trimmingCharacters(in: .whitespacesAndNewlines))
        var i = 0
        if let first = chars.first, demonstratives.contains(first) { i = 1 }
        while i < chars.count, numerals.contains(chars[i]) { i += 1 }
        guard i < chars.count, measures.contains(chars[i]), i > 0 else {
            return (String(chars), 0)
        }
        i += 1
        if i < chars.count, chars[i] == "的" { i += 1 }  // l10n-ignore (target word)
        let rest = chars[i...]
        guard rest.count >= 2, rest.allSatisfy(Self.isHan) else { return (String(chars), 0) }
        return (String(rest), i)
    }

    /// The reading without its first `count` syllables (one per character, space-separated); nil when it has too few.
    static func dropSyllables(_ reading: String?, _ count: Int) -> String? {
        guard let reading, count > 0 else { return reading }
        let parts = reading.split(whereSeparator: \.isWhitespace)
        guard parts.count > count else { return nil }
        return parts.dropFirst(count).joined(separator: " ")
    }

    private static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }
}
