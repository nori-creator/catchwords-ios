import SwiftUI
import UIKit

/// Dynamic Type for the app's point sizes (launch audit D-01).
///
/// The screens are drawn to the web design's pixel sizes (`.system(size: 15)` …), which never followed
/// the user's text size. `.scaledFont(size:weight:design:)` keeps those sizes at the default text size
/// ("Large") and scales them like the nearest system text style does (UIFontMetrics), so a 13 pt
/// caption grows like `.footnote` and a 34 pt title only as much as `.largeTitle`.
///
/// Limits: the whole app stops at `AppTypeScale.cap` (accessibility 2, also set at the root with
/// `.appTypeSizeCap()`), and dense or fixed-geometry screens (the camera, the scanner) stop earlier
/// with `.denseTypeSizeCap()`.
///
/// Still drawn at a fixed size on purpose (their size is part of a spec or of a fixed frame):
/// the card catch and the hologram card (`Views/CardCatch`, docs/prototype/SPEC.md), the dex shadow grid
/// (`DexGallery`), the tab bar and the shutter, zhuyin ruby (`ZhuyinWordView`),
/// album collage prints, calendar cells, and SF Symbol glyphs inside fixed-size circles and buttons.
extension View {
    /// `.scaledFont(size: weight:design:)` that follows the user's text size (capped; see `AppTypeScale`).
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    monospacedDigit: Bool = false) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, monospacedDigit: monospacedDigit))
    }

    /// The app-wide ceiling for the text size (set once at the root and on the preview root).
    func appTypeSizeCap() -> some View {
        dynamicTypeSize(...AppTypeScale.cap)
    }

    /// A lower ceiling for screens whose layout is a fixed composition (camera chrome, book pages).
    func denseTypeSizeCap() -> some View {
        dynamicTypeSize(...AppTypeScale.denseCap)
    }
}

/// Reads the environment's text size, so the font updates live when the user changes it.
struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let monospacedDigit: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let font = Font.system(size: AppTypeScale.scaled(size, for: dynamicTypeSize), weight: weight, design: design)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

enum AppTypeScale {
    /// Beyond this the screens' fixed compositions can no longer hold (also applied at the root).
    static let cap: DynamicTypeSize = .accessibility2
    /// Dense, fixed-geometry screens.
    static let denseCap: DynamicTypeSize = .xxxLarge

    /// `size` (designed at the default "Large" text size) scaled for `dynamicTypeSize`, never past `cap`.
    static func scaled(_ size: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let clamped = min(dynamicTypeSize, cap)
        if clamped == .large { return size }
        let traits = UITraitCollection(preferredContentSizeCategory: category(for: clamped))
        return UIFontMetrics(forTextStyle: textStyle(for: size)).scaledValue(for: size, compatibleWith: traits)
    }

    /// The system text style whose default size is nearest below `size`: big titles grow less than body text.
    static func textStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<13: .caption1
        case ..<15: .footnote
        case ..<16: .subheadline
        case ..<17: .callout
        case ..<20: .body
        case ..<22: .title3
        case ..<28: .title2
        case ..<34: .title1
        default: .largeTitle
        }
    }

    static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
