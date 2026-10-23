import SwiftUI
import UIKit

/// Design tokens ported from the web app's `styles.css` (light `:root` and dark `.dark`
/// "Deep Ocean", oklch → sRGB). Surface and text tokens follow the light/dark setting; the
/// camera keeps its deep-navy "machine" look and the home album stays paper in both.
enum Theme {
    static let background = Color(light: 0xF9FCFF, dark: 0x030915)
    static let backgroundDeep = Color(light: 0xEEF3F9, dark: 0x010510)
    static let card = Color(light: 0xFFFFFF, dark: 0x0A1423)
    static let surface2 = Color(light: 0xEDF2F8, dark: 0x16202F)
    static let secondary = Color(light: 0xEDF2F8, dark: 0x132032)
    static let accent = Color(light: 0xD8EEFF, dark: 0x112D55)
    /// The pale blue behind a sentence in the learning language inside a pattern card (owner 2026-10-23, the example's
    /// own face: lighter than `accent`, so the formula above it stays the stronger thing).
    static let inset = Color(light: 0xEAF3FF, dark: 0x112A4A)
    static let primary = Color(hex: 0x0083FF)
    /// Blue used as text: brighter on dark surfaces so it doesn't sink (web: 暗い面では青を暗くしない).
    static let primaryInk = Color(light: 0x0053D4, dark: 0x6FB0FF)
    static let primaryBright = Color(hex: 0x2A9BFF)
    static let primaryDeep = Color(hex: 0x0060E0)
    static let foreground = Color(light: 0x0B121A, dark: 0xF2F6F8)
    static let muted = Color(light: 0x5C646F, dark: 0x99A6B8)
    static let border = Color(light: 0xE0E5EB, dark: 0x1D2635)
    static let gold = Color(hex: 0xF4B93C)
    static let cyan = Color(hex: 0x64E0FF)
    static let destructive = Color(light: 0xE62B34, dark: 0xFF5E63)
    static let ok = Color(hex: 0x00A95C)
    static let radius: CGFloat = 14

    /// Dark pill behind white notice text (toasts, hints): stays dark in the dark theme too, where
    /// `foreground` turns light and white text on it disappeared.
    static let toastInk = Color(hex: 0x0B121A)

    static let navyDeep = Color(hex: 0x060D1C)
    static let navyCard = Color(hex: 0x131E37)

    /// memory.ts 6 levels (<30, <50, <70, <85, <95, else).
    static let memoryLevels: [Color] = [
        Color(hex: 0xF9262A), Color(hex: 0xF87300), Color(hex: 0xE5A500),
        Color(hex: 0x46BC24), Color(hex: 0x00B777), Color(hex: 0x0083FF),
    ]

    static let brandGradient = LinearGradient(
        colors: [primaryBright, primaryDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    /// A colour that follows the light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Dates in the display language (L10n): 9月28日 / Sep 28 / 9月28日.
enum JPDate {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    /// A formatter from a template (CLDR picks the right order and words for each language).
    private static func fmt(_ template: String, fixed: Bool = false) -> DateFormatter {
        let key = L10n.lang + "|" + template
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = L10n.locale
        if fixed { f.dateFormat = template } else { f.setLocalizedDateFormatFromTemplate(template) }
        cache[key] = f
        return f
    }

    /// 9月28日 · Sep 28
    static func monthDay(_ date: Date) -> String { fmt("MMMd").string(from: date) }
    /// 2026年9月28日 18:17 · Sep 28, 2026, 18:17
    static func full(_ d: Date) -> String { fmt("yMMMdHHmm").string(from: d) }
    /// 09/28 · 28/09 (the language's day/month order — es and vi read 10/3 as 10 March)
    static func mmdd(_ d: Date) -> String { fmt("MMdd").string(from: d) }
    /// 水曜日 · Wednesday
    static func weekday(_ d: Date) -> String { fmt("EEEE").string(from: d) }
    /// 9月28日(月) · Mon, Sep 28
    static func monthDayWeek(_ d: Date) -> String { fmt("MMMdE").string(from: d) }
    /// 2025年9月28日(日) · Sun, Sep 28, 2025
    static func yearMonthDayWeek(_ d: Date) -> String { fmt("yMMMdE").string(from: d) }
    /// 9/28 · 28/9 (the language's day/month order)
    static func slash(_ d: Date) -> String { fmt("Md").string(from: d) }
    /// 15:36 · 3:36 PM (the language's clock, as in the time pickers)
    static func time(_ d: Date) -> String { fmt("jmm").string(from: d) }
    /// 2026年 · 2026
    static func year(_ d: Date) -> String { fmt("y").string(from: d) }
    /// 9月 · September (stand-alone month name)
    static func month(_ d: Date) -> String { fmt("LLLL").string(from: d) }
    /// SEPTEMBER (the book spine's decorative month name, always English)
    static func monthName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM"
        return f.string(from: d).uppercased()
    }
    /// 日 月 火 … · S M T … in the display language, Sunday first.
    static var veryShortWeekdays: [String] { fmt("EEEEE").veryShortWeekdaySymbols ?? [] }
}

/// The app's fonts: the system font everywhere (owner 2026-10-20: 「アプリから手書き風のものは完全に消して、すべての言語対応
/// できるようにして」 — the bundled handwriting fonts had no Hangul and no Vietnamese ơ ư ạ, so a line could mix two
/// fonts). Text uses `.scaledFont(size:weight:)`; this keeps the one monospaced style.
enum AppFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
