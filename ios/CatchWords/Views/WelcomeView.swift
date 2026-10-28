import SwiftUI
import AuthenticationServices

/// The first screen before signing in (the owner's design of 2026-10-11).
///
/// The app icon and 「CatchWords」 at the top left; three word stickers cut out of that design (a latte 「咖啡」,
/// a plant 「植物」 and a croissant 「麵包」: the words are Taiwanese Mandarin, on the album's own tags) with a sparkle; the tagline
/// 「日常のすべてが学びになる」 and one line under it; then the ways in: Google and Apple right here (the same web
/// sign-in as the sign-in screen), 「メールでログイン」 and 「初めての方は 新規登録」 (both open the sign-in screen
/// with the mail form already open), and the agreement to the terms.
///
/// Motion (the app's opening, owner 2026-10-27: 「アプリを開いたときのアニメーション、モーションデザインにこだわって」): the
/// first time in a launch the icon pops up in the middle of the screen (where the blank launch screen left off) and
/// flies to its place at the top left while 「CatchWords」 slides out of it; the stickers pop in one after another and
/// float gently, the sparkle twinkles; the tagline rises out of a blur line by line (`HeadlineReveal`; 「学び」 stays
/// black, owner 2026-10-28); the ways in rise one after another. A tap on a sticker says its word.
/// Back from the mail screen only the quick part plays. With reduced motion only the still picture.
struct WelcomeView: View {
    /// 「メールでログイン」.
    let onMail: () -> Void
    /// 「初めての方は 新規登録」.
    let onSignUp: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared: Bool = false
    /// The icon's opening: popped up in the middle (`logoPop`), then at its place in the header (`docked`).
    @State private var logoPop: Bool = false
    @State private var docked: Bool = false
    /// Where the header's icon is and the middle of the screen (global), to fly the icon from one to the other.
    @State private var logoFrame: CGRect = .zero
    @State private var screen: CGRect = .zero

    /// The icon's opening plays once per launch; coming back from the mail screen shows the page at once.
    @MainActor private static var hasOpened = false
    /// The stickers' least height.
    private static let minStage: CGFloat = 150

    var body: some View {
        // One screen, the stickers taking the height the rest leaves. When even the smallest stickers leave too little
        // room (a large text size on a small phone, an error under the buttons), the page scrolls instead, so
        // 「新規登録」 and the agreement can always be reached.
        ViewThatFits(in: .vertical) {
            page(scrolls: false)
            ScrollView {
                page(scrolls: true)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            WelcomeBackdrop(lit: appeared)
                .ignoresSafeArea()
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { screen = $0 }
        .task { await open() }
    }

    /// The opening: the icon in the middle → its place, then the page (see the type's comment).
    private func open() async {
        guard !reduceMotion, !Self.hasOpened else {
            logoPop = true
            docked = true
            if reduceMotion { appeared = true } else { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
            return
        }
        Self.hasOpened = true
        // The header's icon must have been laid out before it can be sent to the middle.
        for _ in 0..<20 where logoFrame == .zero || screen == .zero {
            try? await Task.sleep(for: .milliseconds(16))
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { logoPop = true }
        try? await Task.sleep(for: .milliseconds(620))
        Haptics.impact(.soft, intensity: 0.6)
        withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { docked = true }
        try? await Task.sleep(for: .milliseconds(120))
        appeared = true
    }

    private func page(scrolls: Bool) -> some View {
        VStack(spacing: 0) {
            header
            // Last in line for the height (its priority on the outermost modifier, where the stack reads it): the words
            // and buttons below keep their whole height — the agreement used to be cut to one line.
            WelcomeStickers(appeared: appeared, animate: !reduceMotion)
                .frame(minHeight: Self.minStage, maxHeight: scrolls ? Self.minStage : .infinity)
                .padding(.horizontal, -24)
                .layoutPriority(-1)
            copy
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            ways
                .padding(.top, 18)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // The icon's place is measured on an empty slot, and the icon flies over it: measured on the icon itself, the
            // frame took in its own offset, which moved it again — a loop that held the main thread (UI test 2026-10-27).
            Color.clear
                .frame(width: 34, height: 34)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { if !docked { logoFrame = $0 } }
                .overlay {
                    WelcomeLogo(size: 34)
                        .scaleEffect(docked ? 1 : logoPop ? 2.4 : 1.3)
                        .offset(x: docked ? 0 : screen.midX - logoFrame.midX,
                                y: docked ? 0 : screen.minY + screen.height * 0.44 - logoFrame.midY)
                        .opacity(logoPop ? 1 : 0)
                }
                .zIndex(1)
            Text(verbatim: "CatchWords")
                .font(.system(size: 23, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .opacity(docked ? 1 : 0)
                .offset(x: docked ? 0 : -18)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85).delay(0.18), value: docked)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .zIndex(1)
        .accessibilityElement(children: .combine)
    }

    private var copy: some View {
        VStack(spacing: 10) {
            RevealHeadline(marked: L("日常のすべてが\n学びになる"), size: 32, active: appeared, delay: 0.12, duration: 1.0)
                .lineLimit(2)
            Text(L("街で出会う言葉を、ステッカーに。"))
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .staggerIn(appeared, delay: 0.45, distance: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var ways: some View {
        VStack(spacing: 12) {
            // Google and Apple go through the web app's sign-in (same account as the web).
            Button {
                Task { await auth.signInWithWeb(provider: "google") }
            } label: {
                HStack(spacing: 10) {
                    GoogleMark(size: 20)
                    Text(L("Googleで続ける")).scaledFont(size: 17, weight: .semibold)
                }
                .foregroundStyle(Color(hex: 0x1F1F1F))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white, in: .capsule)
                .overlay(Capsule().stroke(Color(hex: 0x747775), lineWidth: 1))
                .shadow(color: Color(hex: 0x1C4A80).opacity(0.08), radius: 10, y: 4)
            }
            .buttonStyle(PressableStyle())
            .disabled(auth.isBusy)
            .accessibilityIdentifier("welcome.google")
            .staggerIn(appeared, delay: 0.5)

            apple
                .staggerIn(appeared, delay: 0.57)

            if let msg = auth.errorMessage {
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text(L("または"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .staggerIn(appeared, delay: 0.64)

            Button(action: onMail) {
                HStack(spacing: 4) {
                    Text(L("メールでログイン"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(Theme.primaryInk)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .accessibilityIdentifier("welcome.signin")
            .staggerIn(appeared, delay: 0.68)

            Button(action: onSignUp) {
                HStack(spacing: 6) {
                    Text(L("初めての方は"))
                        .foregroundStyle(Theme.muted)
                    HStack(spacing: 3) {
                        Text(L("新規登録"))
                            .fontWeight(.bold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.primaryInk)
                }
                .scaledFont(size: 14)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .accessibilityIdentifier("welcome.start")
            .staggerIn(appeared, delay: 0.72)

            // Consent to the terms and the privacy policy is given by continuing (both pages are links).
            Text(LegalLinks.signInAgreement())
                .scaledFont(size: 11)
                .foregroundStyle(Theme.muted)
                .tint(Theme.primaryInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("welcome.agreement")
                .staggerIn(appeared, delay: 0.76, distance: 6)
        }
    }

    /// Apple's own button (HIG: the system draws the logo, title and proportions), 「Appleで続ける」.
    @ViewBuilder
    private var apple: some View {
        if AppConfig.nativeAppleSignIn {
            SignInWithAppleButton(.continue) { req in
                auth.prepareApple(req)
            } onCompletion: { result in
                Task { await auth.completeApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)  // HIG: white on a dark screen
            .frame(height: 54)
            .clipShape(.capsule)
            .accessibilityIdentifier("welcome.apple")
        } else {
            // The tap runs the web sign-in so the account is the same as on the web.
            AppleIDWebButton(type: .continue, style: colorScheme == .dark ? .white : .black, cornerRadius: 27,
                             identifier: "welcome.apple", isEnabled: !auth.isBusy) {
                Task { await auth.signInWithWeb(provider: "apple") }
            }
            .id(colorScheme)  // the button's style is fixed at creation; rebuild it when the scheme flips
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
    }
}

/// The app icon itself (the web shows `icon-192.png`); the native mark if the picture is missing.
struct WelcomeLogo: View {
    let size: CGFloat

    var body: some View {
        if let img = WelcomeImage.load("welcome_logo", type: "png") {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: Theme.primary.opacity(0.45), radius: size * 0.16, y: size * 0.14)
                .accessibilityHidden(true)
        } else {
            LogoMark(size: size)
                .accessibilityHidden(true)
        }
    }
}

/// Pictures of the welcome screen (bundled next to the onboarding photos).
enum WelcomeImage {
    private static var cache: [String: UIImage] = [:]

    static func load(_ name: String, type: String = "webp") -> UIImage? {
        let key = name + "." + type
        if let c = cache[key] { return c }
        guard let path = Bundle.main.path(forResource: name, ofType: type),
              let img = UIImage(contentsOfFile: path) else { return nil }
        cache[key] = img
        return img
    }
}

// MARK: - Backdrop

/// A pale sky blue at the top fading to the page colour, with a soft glow behind the stickers. The glow opens up with
/// the page (`lit`) and then breathes slowly.
private struct WelcomeBackdrop: View {
    var lit: Bool = true

    private static let top = Color(light: 0xE9F3FE, dark: 0x061A33)
    private static let glow = Color(light: 0xD5E8FC, dark: 0x0B2B52)

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background
                LinearGradient(colors: [Self.top, Self.top.opacity(0)], startPoint: .top, endPoint: .center)
                    .opacity(lit ? 1 : 0.4)
                RadialGradient(colors: [Self.glow.opacity(0.85), Self.glow.opacity(0)],
                               center: UnitPoint(x: 0.5, y: 0.34), startRadius: 0, endRadius: geo.size.width * 0.72)
                    .scaleEffect(lit ? (breathe ? 1.08 : 1) : 0.5)
                    .opacity(lit ? 1 : 0)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: lit)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true).delay(1.2)) { breathe = true }
        }
    }
}

// MARK: - The stickers

/// The three word stickers, the sparkle and the little burst lines, placed in the design's own pixels (the design
/// is 864 wide; the collage spans y 150…840) and scaled to the space they get. The pictures keep their
/// proportions; the places spread a little further than the pictures grow when the box is wider or taller.
private struct WelcomeStickers: View {
    let appeared: Bool
    let animate: Bool

    private struct Piece {
        let image: String
        /// The word on the sticker's tag and its readings (the tag is the album's own `WordTag`; a tap says the word).
        let word: String
        let zhuyin: String
        let pinyin: String
        /// Where the tag goes on the picture (its centre and size in the picture's pixels) and its lean: the place the
        /// label printed on the design's pictures had (owner 2026-10-28: 「名前のタグの字体もアプリの本物に揃えて」 —
        /// the printed labels were a handwriting face; they were taken off the pictures).
        let tag: CGRect
        let tagTilt: Double
        /// Centre and size in design pixels.
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat
        let delay: Double
        /// Floating: how far (design pixels) and how slowly.
        let bob: CGFloat
        let period: Double
    }

    private static let pieces: [Piece] = [
        Piece(image: "welcome_sticker_coffee", word: "咖啡", zhuyin: "ㄎㄚ ㄈㄟ", pinyin: "kāfēi",  // l10n-ignore (target word)
              tag: CGRect(x: 101 - 85, y: 295 - 40, width: 170, height: 80), tagTilt: -12,
              x: 244, y: 421, w: 395, h: 352, delay: 0.05, bob: 10, period: 3.6),
        Piece(image: "welcome_sticker_plant", word: "植物", zhuyin: "ㄓˊ ㄨˋ", pinyin: "zhíwù",  // l10n-ignore (target word)
              tag: CGRect(x: 275 - 78, y: 360 - 39, width: 156, height: 78), tagTilt: -9,
              x: 645, y: 365, w: 372, h: 420, delay: 0.17, bob: 12, period: 4.2),
        // 麵包 (owner 2026-10-28: 「パンは麵包にして」).
        Piece(image: "welcome_sticker_croissant", word: "麵包", zhuyin: "ㄇㄧㄢˋ ㄅㄠ", pinyin: "miànbāo",  // l10n-ignore (target word)
              tag: CGRect(x: 233 - 95, y: 245 - 36, width: 190, height: 72), tagTilt: -12,
              x: 440, y: 682, w: 407, h: 299, delay: 0.29, bob: 9, period: 3.9),
    ]
    private static let designWidth: CGFloat = 864
    private static let designTop: CGFloat = 150
    private static let designHeight: CGFloat = 690

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / Self.designWidth
            let sy = geo.size.height / Self.designHeight
            let s = min(sx, sy)
            let kx = min(sx, s * 1.2)
            let ky = min(sy, s * 1.2)
            let ox = (geo.size.width - Self.designWidth * kx) / 2
            let oy = (geo.size.height - Self.designHeight * ky) / 2
            ZStack(alignment: .topLeading) {
                WelcomeBurst()
                    .stroke(Color(hex: 0x5AA4F8), style: StrokeStyle(lineWidth: max(2, 6.5 * s), lineCap: .round))
                    .frame(width: 85 * s, height: 85 * s)
                    .opacity(appeared ? 1 : 0)
                    .animation(animate ? Animation.easeOut(duration: 0.4).delay(0.45) : nil, value: appeared)
                    .position(x: ox + 92.5 * kx, y: oy + (257.5 - Self.designTop) * ky)
                    .allowsHitTesting(false)
                ForEach(0..<Self.pieces.count, id: \.self) { i in
                    let p = Self.pieces[i]
                    WelcomeSticker(image: p.image, word: p.word, zhuyin: p.zhuyin, pinyin: p.pinyin,
                                   tag: p.tag, tagTilt: p.tagTilt, pictureWidth: p.w,
                                   width: p.w * s, height: p.h * s, delay: p.delay,
                                   bob: p.bob * s, period: p.period, appeared: appeared, animate: animate)
                        .position(x: ox + p.x * kx, y: oy + (p.y - Self.designTop) * ky)
                }
                WelcomeSparkle(size: 76 * s, appeared: appeared, animate: animate)
                    .position(x: ox + 747 * kx, y: oy + (662 - Self.designTop) * ky)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
}

/// One sticker: pops in (turning upright as it lands), then floats up and down. Its name is on the album's own tag
/// (`WordTag`: the app's type, the reading as the reading setting says). A tap squashes it and says the word.
private struct WelcomeSticker: View {
    let image: String
    let word: String
    let zhuyin: String
    let pinyin: String
    /// The tag's place and lean on the picture (picture pixels), and the picture's width in those pixels.
    let tag: CGRect
    let tagTilt: Double
    let pictureWidth: CGFloat
    let width: CGFloat
    let height: CGFloat
    let delay: Double
    let bob: CGFloat
    let period: Double
    let appeared: Bool
    let animate: Bool

    @State private var up: Bool = false
    @State private var squash: Bool = false

    var body: some View {
        let k = width / pictureWidth
        Group {
            if let img = WelcomeImage.load(image) {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) {
            WordTag(text: word, zhuyin: zhuyin, pinyin: pinyin, tilt: tagTilt, size: tag.height * k * 0.42,
                    minSize: CGSize(width: tag.width * k, height: tag.height * k * 0.86))
                .position(x: tag.midX * k, y: tag.midY * k)
        }
        .shadow(color: Color(hex: 0x1C4A80).opacity(0.16), radius: 10, y: 6)
        .scaleEffect(x: squash ? 1.08 : 1, y: squash ? 0.9 : 1, anchor: .bottom)
        .contentShape(.rect)
        .onTapGesture { say() }
        .offset(y: up ? -bob : 0)
        .rotationEffect(.degrees(appeared ? 0 : (delay < 0.1 ? -14 : delay < 0.2 ? 12 : -8)))
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .animation(animate ? Animation.spring(response: 0.6, dampingFraction: 0.62).delay(delay) : nil, value: appeared)
        .onAppear {
            guard animate else { return }
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true).delay(delay + 0.6)) { up = true }
        }
    }

    private func say() {
        Haptics.impact(.light)
        SoundService.shared.speak(word)
        withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { squash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { squash = false }
        }
    }
}

/// The blue four-pointed sparkle (an outline with curved sides), twinkling slowly.
private struct WelcomeSparkle: View {
    let size: CGFloat
    let appeared: Bool
    let animate: Bool

    @State private var twinkle: Bool = false

    var body: some View {
        WelcomeSparkleShape()
            .stroke(Color(hex: 0x1A7CF2), style: StrokeStyle(lineWidth: max(2, size * 0.085), lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.88, height: size)
            .rotationEffect(.degrees(8))
            .scaleEffect(animate ? (twinkle ? 1.08 : 0.94) : 1)
            .opacity(appeared ? 1 : 0)
            .animation(animate ? Animation.easeOut(duration: 0.5).delay(0.5) : nil, value: appeared)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.9)) { twinkle = true }
            }
    }
}

/// Four points joined by curves that bend in towards the centre.
private struct WelcomeSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var p = Path()
        p.move(to: pt(0.5, 0))
        p.addQuadCurve(to: pt(1, 0.5), control: pt(0.56, 0.44))
        p.addQuadCurve(to: pt(0.5, 1), control: pt(0.56, 0.56))
        p.addQuadCurve(to: pt(0, 0.5), control: pt(0.44, 0.56))
        p.addQuadCurve(to: pt(0.5, 0), control: pt(0.44, 0.44))
        p.closeSubpath()
        return p
    }
}

/// Three short strokes by the latte, as if it had just popped up (design pixels, box 50…135 × 215…300).
private struct WelcomeBurst: Shape {
    private static let lines: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 126, y: 223), CGPoint(x: 125, y: 253)),
        (CGPoint(x: 80, y: 243), CGPoint(x: 102, y: 270)),
        (CGPoint(x: 57, y: 285), CGPoint(x: 87, y: 292)),
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 85
        let sy = rect.height / 85
        var p = Path()
        for (a, b) in Self.lines {
            p.move(to: CGPoint(x: rect.minX + (a.x - 50) * sx, y: rect.minY + (a.y - 215) * sy))
            p.addLine(to: CGPoint(x: rect.minX + (b.x - 50) * sx, y: rect.minY + (b.y - 215) * sy))
        }
        return p
    }
}
