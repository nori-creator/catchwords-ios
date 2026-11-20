import SwiftUI
import UIKit
import CoreText

/// **Chinese learning text in the Taiwan glyph shapes** (owner 2026-11-20: a Taiwanese reader saw 「雨」 drawn the Japanese
/// way). Han characters have one code point for several regional shapes; with no language on the text, iOS picks the
/// font for them from the device's languages, so on a Japanese iPhone every Chinese word, chunk and example came out in
/// Hiragino (Japanese shapes) instead of PingFang TC.
///
/// Measured on the iOS simulator set to Japanese (`HanGlyphProbeTests`, 2026-11-20, 「雨骨直角」 compared with PingFang TC
/// and Hiragino): `typesettingLanguage(zh-Hant-TW)` on the text or on a parent, `AttributedString.languageIdentifier` and
/// UIKit's `NSLanguage` attribute all give the Taiwan shapes; the environment's locale does not.
///
/// Only the learning language's text is marked (headwords, readings' characters, chunks, examples, measure words,
/// related words, tags, choices). The app's own words (`L(...)`) keep the display language's shapes — a Japanese screen's
/// 図鑑 stays Japanese. Text with no Han characters (pinyin, the reader's language) is left alone, so its line metrics
/// do not change.
nonisolated enum TaiwanGlyphs {
    /// The learning language (台湾華語) as a typesetting language.
    static let language = Locale.Language(identifier: "zh-Hant-TW")
    static let identifier = "zh-Hant-TW"

    /// Whether `s` has a character of the Han script (the only characters whose shape depends on the language).
    static func hasHan(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    /// `s` with the learning language on every character (UIKit labels, TextKit).
    static func attributed(_ s: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        m.addAttribute(languageKey, value: identifier, range: NSRange(location: 0, length: m.length))
        return m
    }

    /// CoreText's language attribute (`kCTLanguageAttributeName`, "NSLanguage").
    static let languageKey = NSAttributedString.Key(rawValue: kCTLanguageAttributeName as String)
}

extension View {
    /// Draws the Han characters of this view's text in the Taiwan shapes (`TaiwanGlyphs`). Put it on text in the learning
    /// language only, never on a container that also holds the app's own words.
    func taiwanGlyphs(_ isEnabled: Bool = true) -> some View {
        typesettingLanguage(TaiwanGlyphs.language, isEnabled: isEnabled)
    }

    /// As `taiwanGlyphs()`, only when `text` has Han characters (pinyin or the reader's language keeps its own metrics).
    func taiwanGlyphs(for text: String) -> some View {
        typesettingLanguage(TaiwanGlyphs.language, isEnabled: TaiwanGlyphs.hasHan(text))
    }
}

extension View {
    /// The app's own words in the display language's Han shapes, at the root: a Japanese screen on an iPhone set to
    /// another language keeps Japanese shapes, a 繁體中文（台灣） screen on a Japanese iPhone gets the Taiwan ones. Only the
    /// display languages written with Han characters (ja, zh-TW); the others are left as they were. Learning text sets
    /// its own language (`taiwanGlyphs`), which wins inside.
    func displayLanguageGlyphs(_ language: DisplayLanguage) -> some View {
        let han = language.script == .kana || language.script == .han
        return typesettingLanguage(Locale.Language(identifier: language.localeID.replacingOccurrences(of: "_", with: "-")),
                                   isEnabled: han)
    }
}

extension AttributedString {
    /// The learning language on every run (`Text(AttributedString)` that mixes it with other text).
    func taiwanGlyphs() -> AttributedString {
        var a = self
        a.languageIdentifier = TaiwanGlyphs.identifier
        return a
    }
}
