import Foundation
import Observation

/// Observed by every view that calls `L(...)`, so switching the display language redraws exactly
/// those views — in place, without losing the current tab or screen.
@Observable
nonisolated final class LanguageState: @unchecked Sendable {
    static let shared = LanguageState()
    var lang: String = {
        if let saved = UserDefaults.standard.string(forKey: L10n.storageKey), L10n.supported.contains(saved) { return saved }
        return L10n.deviceDefault
    }()
}

/// The app's display language (web `ui_language`). The languages are listed once, in
/// `ios/Localization/languages.json` (`DisplayLanguages`, generated from it).
///
/// Every piece of text the app itself writes goes through `L(...)`. The key is the Japanese source
/// text; every other language comes from `Resources/Localization/strings.json`. The CI check
/// (`scripts/check_l10n.py`) fails the build if any Japanese text in the code is not passed through
/// `L` or lacks a translation in any listed language — so a screen can never show two languages at once.
nonisolated enum L10n {
    static let supported = DisplayLanguages.codes
    static let storageKey = "ui.lang"

    /// The current display language. Set from the profile (`ui_language`) and kept on the device so
    /// the sign-in screens already use it.
    static var lang: String {
        get { LanguageState.shared.lang }
        set { LanguageState.shared.lang = newValue }
    }

    /// The current display language's details (separators, locale, script).
    static var current: DisplayLanguage { language(lang) }

    static func language(_ code: String) -> DisplayLanguage {
        DisplayLanguages.find(code) ?? DisplayLanguages.find(DisplayLanguages.fallback)!
    }

    /// First launch: the first of the iPhone's languages we have, else English.
    static var deviceDefault: String {
        for id in Locale.preferredLanguages {
            if let l = DisplayLanguages.forDevice(id) { return l.code }
        }
        return DisplayLanguages.fallback
    }

    static func set(_ code: String) {
        let c = normalize(code)
        lang = c
        UserDefaults.standard.set(c, forKey: storageKey)
        followInSystemScreens(c)
    }

    /// Signing out / account deleted: forget the chosen language, exactly like a fresh install, so the
    /// next person on this phone gets the iPhone's own language (an account's `ui_language` comes back
    /// with its profile on sign-in).
    static func resetToDevice() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        lang = deviceDefault
    }

    /// The app's own language list, which iOS reads at launch (the same setting as iPhone Settings › CatchWords ›
    /// Language).
    private static let appleLanguagesKey = "AppleLanguages"

    /// The text iOS draws inside the app — the camera / location / photo permission questions (InfoPlist.strings),
    /// the photo picker, the Sign in with Apple button — follows the app's language list, not `L10n.lang`.
    /// Writing the display language there makes them speak it too from the next launch (owner 2026-10-20: 「決して
    /// 言語が混ざらないようにして」). The UI tests pass the list as a launch argument, which wins over this.
    private static func followInSystemScreens(_ code: String) {
        let id = language(code).lproj
        let defaults = UserDefaults.standard
        if (defaults.array(forKey: appleLanguagesKey) as? [String])?.first == id { return }
        defaults.set([id], forKey: appleLanguagesKey)
    }

    /// A listed code as it is, another by its language part ("zh" → zh-TW, "es-MX" → es); unknown → ja.
    static func normalize(_ code: String?) -> String {
        DisplayLanguages.match(code)?.code ?? DisplayLanguages.source
    }

    /// For dates and numbers in the display language.
    static var locale: Locale { Locale(identifier: current.localeID) }

    /// key (Japanese) → [language code: text]
    private static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return [:] }
        return obj
    }()

    /// A translation from the table, or nil when there is none (ja returns the key itself).
    static func translation(_ key: String, in code: String? = nil) -> String? {
        let c = code ?? lang
        if c == "ja" { return key }
        if let t = table[key]?[c], !t.isEmpty { return t }
        return nil
    }

    /// Text that came from outside the app (a server error, a database message). Shown only when it
    /// is written in the display language — a known server sentence is translated, anything else in
    /// another language is replaced by `fallback`, so a message never mixes languages on screen.
    static func readerSafe(_ text: String, fallback: String) -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return fallback }
        if isOwnText(s) { return s }  // the app's own sentence, already in this language
        if let t = translation(s), lang != "ja" { return t }
        if lang != "ja", let t = knownServerSentence(s) { return t }
        return looksLike(s, lang) ? s : fallback
    }

    /// The server's Japanese sentences that vary in detail (counts, names) — by what they say (web errors.ts).
    private static func knownServerSentence(_ s: String) -> String? {
        if s.contains("利用上限") { return L("1日の利用上限に達しました。24時間以内に自動で回復します。") }  // l10n-ignore (matching the server text)
        if s.contains("Pro 限定") || s.contains("Pro限定") { return L("この機能は Pro 限定です。") }  // l10n-ignore (matching the server text)
        if s.contains("権限がありません") { return L("この操作の権限がありません。") }  // l10n-ignore (matching the server text)
        if s.contains("見つかりません") { return L("見つかりませんでした。") }  // l10n-ignore (matching the server text)
        if s.contains("もう一度") { return L("うまくいきませんでした。もう一度お試しください。") }  // l10n-ignore (matching the server text)
        return nil
    }

    /// Whether `s` is one of the app's own sentences in the display language (a table value, with any
    /// `{n}` filled in) — e.g. an error the app wrote with `L(...)` and passed through `APIError`.
    /// Never true for text in another script than the screen's (so server text can't pass as ours).
    static func isOwnText(_ s: String) -> Bool {
        let c = lang
        let n = LanguageRules.counts(s)
        switch current.script {
        case .latin: if n.cjk > 0 { return false }
        case .han: if n.kana > 0 || n.hangul > 0 { return false }
        case .hangul: if n.kana > 0 || n.han > 0 { return false }
        case .kana: break
        }
        guard let own = ownText[c] else { return false }
        if own.values.contains(s) { return true }
        let range = NSRange(s.startIndex..., in: s)
        return own.patterns.contains { $0.firstMatch(in: s, range: range) != nil }
    }

    /// Per language: every table value, and every template with `{n}` as an anchored pattern (a filled
    /// value is 1–40 characters on one line). Templates also match their singular form ("1 word").
    /// Built once (a `static let` is initialised thread-safely).
    private static let ownText: [String: (values: Set<String>, patterns: [NSRegularExpression])] = {
        var out: [String: (values: Set<String>, patterns: [NSRegularExpression])] = [:]
        for c in supported {
            let templates = c == "ja" ? Array(table.keys) : table.values.compactMap { $0[c] }
            var forms = templates
            let plurals = language(c).plurals
            for t in templates where !plurals.isEmpty {
                var one = t
                for (many, single) in plurals { one = one.replacingOccurrences(of: "} " + many, with: "} " + single) }
                if one != t { forms.append(one) }
            }
            let patterns: [NSRegularExpression] = forms.filter {
                // Only templates with enough fixed text to identify them ("{1}、{2}" would match anything).
                $0.contains("{1}") && $0.replacingOccurrences(of: "\\{[0-9]\\}", with: "", options: .regularExpression).count >= 4
            }.compactMap { t in
                // Placeholders become a marker first, so escaping can't touch them.
                let marked = t.replacingOccurrences(of: "\\{[0-9]\\}", with: "\u{1}", options: .regularExpression)
                let pattern = NSRegularExpression.escapedPattern(for: marked).replacingOccurrences(of: "\u{1}", with: "[^\\n]{1,40}")
                return try? NSRegularExpression(pattern: "^" + pattern + "$")
            }
            out[c] = (Set(templates), patterns)
        }
        return out
    }()

    /// Whether `text` reads as the given display language (LanguageRules R7).
    static func looksLike(_ text: String, _ code: String) -> Bool { LanguageRules.readsAs(text, code) }

    static func text(_ key: String, in code: String? = nil) -> String {
        let c = code ?? lang
        if c == "ja" { return key }
        if let t = table[key]?[c], !t.isEmpty { return t }
        #if DEBUG
        print("⚠️ L10n missing [\(c)]: \(key)")
        #endif
        // Never mix languages on screen: English is the neutral fallback for a missing translation.
        return table[key]?[DisplayLanguages.fallback] ?? key
    }
}

/// A Japanese source string with its interpolated values (`L("\(n)日")`). The table key replaces each
/// interpolation with `{1}`, `{2}` … in order, so translations can move them around.
nonisolated struct LKey: ExpressibleByStringInterpolation, Sendable {
    var key: String
    var args: [String]

    init(stringLiteral value: String) {
        key = value
        args = []
    }

    init(stringInterpolation s: Interpolation) {
        key = s.key
        args = s.args
    }

    nonisolated struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            args.append("\(value)")
            key += "{\(args.count)}"
        }
    }
}

/// Text in the display language (see `L10n`).
nonisolated func L(_ k: LKey) -> String { L10n.fill(L10n.text(k.key), k.args, lang: L10n.lang) }

/// The same, in a given language (e.g. a notification written before the app opens).
nonisolated func L(_ k: LKey, in code: String) -> String { L10n.fill(L10n.text(k.key, in: code), k.args, lang: code) }

extension L10n {
    /// The comma between spoken parts in the display language: "、" / ", " / "，".
    static var comma: String { current.listSeparator }

    /// Puts the values into `{1}`, `{2}` … (and makes a counted noun after 1 singular: "1 words" → "1 word",
    /// with the language's own list in languages.json).
    nonisolated static func fill(_ template: String, _ args: [String], lang: String) -> String {
        var out = template
        let plurals = language(lang).plurals
        for (i, a) in args.enumerated() {
            let slot = "{\(i + 1)}"
            if a == "1", !plurals.isEmpty {
                for (many, one) in plurals {
                    out = out.replacingOccurrences(of: slot + " " + many, with: slot + " " + one)
                }
            }
            out = out.replacingOccurrences(of: slot, with: a)
        }
        return out
    }
}
