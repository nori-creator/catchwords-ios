import SwiftUI

/// The first-run guide's pictures as the app's own stickers (owner 2026-10-22: the guide still showed the web's old
/// photo prints; the app now keeps cut-outs). Each picture is a cut-out with a white die-cut border, lit as a slightly
/// curved vinyl sticker in Blender (`scripts/onboarding_stickers.py` → `blender/onboarding_stickers.py`); scenes with
/// no single thing (a street, a lake) are cut as a rounded shape, as the app's last resort does (`StickerCrop.shaped`).
/// The word is never baked into the picture: `WordTag` draws it with the reading the learner chose.
enum OnboardingSticker {
    /// Taiwanese Mandarin words shown on the guide's stickers (the learning language, never translated).
    struct Word {
        let image: String
        let headword: String
        let zhuyin: String
        let pinyin: String
    }

    static let cafe = Word(image: "cafe", headword: "咖啡", zhuyin: "ㄎㄚ ㄈㄟ", pinyin: "kāfēi")  // l10n-ignore (learning-language word)
    static let flower = Word(image: "flower", headword: "花", zhuyin: "ㄏㄨㄚ", pinyin: "huā")  // l10n-ignore (learning-language word)
    static let cat = Word(image: "cat", headword: "貓", zhuyin: "ㄇㄠ", pinyin: "māo")  // l10n-ignore (learning-language word)
    static let bubbleTea = Word(image: "bubbletea", headword: "珍珠奶茶", zhuyin: "ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ",  // l10n-ignore (learning-language word)
                                pinyin: "zhēnzhū nǎichá")

    static func image(_ name: String) -> UIImage? {
        OnboardingImage.load("onboarding_sticker_" + name)
    }
}

/// One sticker with its word tag half under its lower edge, as on the home album.
struct OnboardingStickerView: View {
    let word: OnboardingSticker.Word
    let width: CGFloat
    var tagTilt: Double = -4
    var tagSize: CGFloat = 17
    var lifted: Bool = false

    var body: some View {
        VStack(spacing: -tagSize * 0.7) {
            Group {
                if let img = OnboardingSticker.image(word.image) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: width * 0.2, style: .continuous).fill(Theme.secondary)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            // Within a square of `width`: a tall cat and a wide cup take about the same room.
            .frame(maxWidth: width, maxHeight: width)
            .shadow(color: Color(hex: 0x1C4A80).opacity(lifted ? 0.26 : 0.16), radius: lifted ? 16 : 9, y: lifted ? 12 : 6)
            WordTag(text: word.headword, zhuyin: word.zhuyin, pinyin: word.pinyin, tilt: tagTilt, size: tagSize,
                    language: "zh-TW")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.headword)
    }
}

/// The guide's opening picture: four stickers (咖啡・花・貓・珍珠奶茶) that drop onto the page one after another with a
/// spring, then float, each at its own pace. A tap gives the sticker a little hop (a hint that things here can be
/// touched). With reduced motion only the still picture.
struct OnboardingStickerCluster: View {
    /// Scale of the whole picture against its box (the ready screen shows it smaller).
    var compact: Bool = false

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var appeared: Bool = false

    private struct Spot {
        let word: OnboardingSticker.Word
        /// Centre (0–1 of the box) and width (of the box's width).
        let x: CGFloat, y: CGFloat, w: CGFloat
        let tilt: Double
        let delay: Double
        let bob: CGFloat
        let period: Double
    }

    private static let spots: [Spot] = [
        Spot(word: OnboardingSticker.bubbleTea, x: 0.72, y: 0.27, w: 0.42, tilt: 7, delay: 0.16, bob: 7, period: 4.3),
        Spot(word: OnboardingSticker.flower, x: 0.26, y: 0.28, w: 0.38, tilt: -8, delay: 0.06, bob: 9, period: 3.8),
        Spot(word: OnboardingSticker.cafe, x: 0.27, y: 0.72, w: 0.40, tilt: 4, delay: 0.26, bob: 6, period: 4.0),
        Spot(word: OnboardingSticker.cat, x: 0.71, y: 0.73, w: 0.40, tilt: -3, delay: 0.36, bob: 8, period: 3.6),
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height * 1.05)
            let ox = (geo.size.width - side) / 2
            let oy = (geo.size.height - side) / 2
            ZStack(alignment: .topLeading) {
                OnboardingSparkle(size: side * 0.09, appeared: appeared, animate: !reduceMotion)
                    .position(x: ox + side * 0.5, y: oy + side * 0.5)
                ForEach(0..<Self.spots.count, id: \.self) { i in
                    let s = Self.spots[i]
                    FloatingSticker(word: s.word, width: side * s.w, tilt: s.tilt, delay: s.delay, bob: s.bob,
                                    period: s.period, appeared: appeared, animate: !reduceMotion,
                                    tagSize: compact ? 17 : 21)
                        .position(x: ox + side * s.x, y: oy + side * s.y)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion { appeared = true } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { appeared = true }
            }
        }
    }
}

/// A sticker that drops in (from a little above, larger and turned, like one being stuck down), floats, and hops
/// when tapped.
private struct FloatingSticker: View {
    let word: OnboardingSticker.Word
    let width: CGFloat
    let tilt: Double
    let delay: Double
    let bob: CGFloat
    let period: Double
    let appeared: Bool
    let animate: Bool
    let tagSize: CGFloat

    @State private var up: Bool = false
    @State private var hops: Int = 0
    @State private var hop: Bool = false

    var body: some View {
        OnboardingStickerView(word: word, width: width, tagTilt: -tilt * 0.6, tagSize: tagSize, lifted: hop)
            .rotationEffect(.degrees(appeared ? tilt : tilt + (tilt >= 0 ? 14 : -14)))
            .scaleEffect(appeared ? (hop ? 1.08 : 1) : 1.35)
            .offset(y: appeared ? (up ? -bob : 0) - (hop ? 14 : 0) : -40)
            .opacity(appeared ? 1 : 0)
            .animation(animate ? Animation.spring(response: 0.55, dampingFraction: 0.62).delay(delay) : nil, value: appeared)
            .animation(.spring(response: 0.32, dampingFraction: 0.5), value: hop)
            .contentShape(.rect)
            .onTapGesture {
                Haptics.impact(.light, intensity: 0.7)
                guard animate else { return }
                hops += 1
                let n = hops
                hop = true
                Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    if hops == n { hop = false }
                }
            }
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true).delay(delay + 0.7)) { up = true }
            }
    }
}

/// The welcome screen's four-pointed sparkle, twinkling between the stickers.
private struct OnboardingSparkle: View {
    let size: CGFloat
    let appeared: Bool
    let animate: Bool

    @State private var twinkle: Bool = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Theme.primaryBright)
            .scaleEffect(appeared ? (twinkle ? 1.12 : 0.88) : 0.2)
            .rotationEffect(.degrees(twinkle ? 12 : -6))
            .opacity(appeared ? 0.9 : 0)
            .animation(animate ? Animation.spring(response: 0.5, dampingFraction: 0.6).delay(0.5) : nil, value: appeared)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.9)) { twinkle = true }
            }
    }
}

/// What the app does, in three steps (撮る → ステッカーに → 復習), the step in turn lighting up so the order reads at a
/// glance. `still`: no light moving (the ready screen, reduced motion).
struct OnboardingHowItWorks: View {
    var still: Bool = false

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var lit: Int = 0

    private static var steps: [(icon: String, label: String)] { [
        ("camera.fill", L("撮る")),
        ("scissors", L("ステッカーに")),
        ("rectangle.stack.fill", L("復習")),
    ] }

    var body: some View {
        let moving = !still && !reduceMotion
        HStack(spacing: 6) {
            ForEach(0..<Self.steps.count, id: \.self) { i in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .accessibilityHidden(true)
                }
                let on = moving ? lit == i : true
                HStack(spacing: 6) {
                    Image(systemName: Self.steps[i].icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? .white : Theme.primaryInk)
                        .frame(width: 26, height: 26)
                        .background(on ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.accent), in: Circle())
                        .symbolEffect(.bounce, value: moving && lit == i)
                    Text(Self.steps[i].label)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(on ? Theme.foreground : Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .scaleEffect(moving && lit == i ? 1.05 : 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Theme.border))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: lit)
        .accessibilityElement(children: .combine)
        .task(id: moving) {
            guard moving else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.3))
                lit = (lit + 1) % Self.steps.count
            }
        }
    }
}
