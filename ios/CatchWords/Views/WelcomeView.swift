import SwiftUI
import AuthenticationServices

/// The first screen before signing in (the owner's design of 2026-10-11), and the only one: sign-up and sign-in are
/// the same page (owner 2026-10-29: 「ログインの画面も新規登録の画面と同じデザインにして」「デフォルトで新規登録の画面にし」).
///
/// The app icon and 「CatchWords」 at the top left; three word stickers cut out of that design (a latte 「咖啡」,
/// a plant 「植物」 and a croissant 「麵包」: the words are Taiwanese Mandarin, on the album's own tags) with a sparkle; a badge
/// that says which page this is (「新規登録」 blue, 「ログイン」 green) over its headline (「日常のすべてが学びになる」 /
/// 「おかえりなさい」), then the ways in, each saying what it does (「Googleで登録」 / 「Googleでログイン」, Apple's own
/// 「Appleで登録」 / 「Appleでサインイン」, 「メールで登録」 / 「メールでログイン」 — Google's and Apple's guidelines name the
/// action on the button). The mail fields open under the mail button when it is tapped. The other page is one tap at the
/// bottom (「アカウントをお持ちの方は ログイン」 / 「初めての方は 新規登録」), then the agreement to the terms.
///
/// Motion (the app's opening, owner 2026-10-27: 「アプリを開いたときのアニメーション、モーションデザインにこだわって」): the
/// first time in a launch the icon pops up in the middle of the screen (where the blank launch screen left off) and
/// flies to its place at the top left while 「CatchWords」 slides out of it; the stickers pop in one after another and
/// float gently, the sparkle twinkles; the headline rises out of a blur line by line (`HeadlineReveal`; 「学び」 stays
/// black, owner 2026-10-28), again when the page changes; the ways in rise one after another. A tap on a sticker says its
/// word. With reduced motion only the still picture.
struct WelcomeView: View {
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
    /// Which page: sign-up unless asked otherwise.
    @State private var isSignUp: Bool
    /// The mail fields, opened by the mail button.
    @State private var showMail: Bool
    @State private var email: String = ""
    @State private var password: String = ""
    /// Nudges the form sideways when signing in fails, like a head shake.
    @State private var shake: CGFloat = 0
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    /// The icon's opening plays once per launch.
    @MainActor private static var hasOpened = false
    /// The stickers' least height.
    private static let minStage: CGFloat = 150

    init(startSignIn: Bool = false, startMail: Bool = false) {
        _isSignUp = State(initialValue: !startSignIn)
        _showMail = State(initialValue: startMail)
    }

    var body: some View {
        Group {
            if showMail {
                // With the fields open the page always scrolls: swapping layouts while the keyboard comes up would make new
                // fields and drop the focus.
                ScrollView {
                    page(scrolls: true)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            } else {
                // One screen, the stickers taking the height the rest leaves. When even the smallest stickers leave too
                // little room (a large text size on a small phone, an error under the buttons), the page scrolls instead,
                // so the other page's link and the agreement can always be reached.
                ViewThatFits(in: .vertical) {
                    page(scrolls: false)
                    ScrollView {
                        page(scrolls: true)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .background {
            WelcomeBackdrop(lit: appeared)
                .ignoresSafeArea()
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { screen = $0 }
        .onAppear {
            // Back here with a reason (the session expired): the sign-in page, its fields open. A pending confirmation
            // of a new account: its message under the open fields.
            if auth.errorMessage != nil {
                isSignUp = false
                showMail = true
            } else if auth.infoMessage != nil {
                showMail = true
            }
        }
        .onChange(of: auth.errorMessage) { _, msg in
            guard msg != nil, showMail, !reduceMotion else { return }
            Task {
                for x in [12.0, -10, 7, -4, 0] {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.4)) { shake = x }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        }
        .task { await open() }
    }

    /// The opening: the icon in the middle → its place, then the page (see the type's comment).
    private func open() async {
        // After the app's opening (`LaunchIntro`: the mark and the name on the blue) the icon is already known: it waits at
        // its place, and the page comes in as the blue lifts off.
        if LaunchIntro.played, !Self.hasOpened {
            Self.hasOpened = true
            logoPop = true
            docked = true
            await LaunchIntro.waitForReveal()
            try? await Task.sleep(for: .milliseconds(140))
            if reduceMotion { appeared = true } else { withAnimation(.easeOut(duration: 0.45)) { appeared = true } }
            return
        }
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

    /// The page's badge (which page this is, at a glance), its headline and one line.
    private var copy: some View {
        VStack(spacing: 10) {
            modeBadge
                .staggerIn(appeared, delay: 0.05, distance: 6)
            RevealHeadline(marked: isSignUp ? L("日常のすべてが\n学びになる") : L("おかえりなさい"),
                           size: 32, active: appeared, delay: 0.12, duration: 1.0)
                .lineLimit(2)
                .id(isSignUp)  // the headline rises again on the other page
            Text(isSignUp ? L("街で出会う言葉を、ステッカーに。") : L("ログインして、集めた単語の続きから。"))
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .staggerIn(appeared, delay: 0.45, distance: 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// 「新規登録」 (blue, a person with a plus) or 「ログイン」 (green, a person with a check).
    private var modeBadge: some View {
        let tint = isSignUp ? Theme.primaryInk : Theme.ok
        return HStack(spacing: 6) {
            Image(systemName: isSignUp ? "person.badge.plus" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 14, weight: .bold))
                .accessibilityHidden(true)
            Text(isSignUp ? L("新規登録") : L("ログイン"))
                .scaledFont(size: 15, weight: .heavy)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
        .contentTransition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("welcome.mode")
    }

    private var ways: some View {
        VStack(spacing: 12) {
            // Google and Apple go through the web app's sign-in (same account as the web); the account is made the first
            // time either way, so the two pages differ only in what the buttons say.
            Button {
                Task { await auth.signInWithWeb(provider: "google") }
            } label: {
                HStack(spacing: 10) {
                    GoogleMark(size: 20)
                    Text(isSignUp ? L("Googleで登録") : L("Googleでログイン"))
                        .scaledFont(size: 17, weight: .semibold)
                        .contentTransition(.opacity)
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

            orLine
                .staggerIn(appeared, delay: 0.64)

            if showMail {
                mailForm
                    .offset(x: shake)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                mailButton
                    .staggerIn(appeared, delay: 0.68)
            }

            messages

            otherPage
                .staggerIn(appeared, delay: 0.72)

            if AuthStore.devSkipLogin {
                Button {
                    Task { await auth.enterAsGuest() }
                } label: {
                    Label(L("ログインせずに入る（開発用）"), systemImage: "arrow.right.circle")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
            }

            // Consent to the terms and the privacy policy is given by continuing (both pages are links).
            Text(LegalLinks.signInAgreement())
                .scaledFont(size: 11)
                .foregroundStyle(Theme.muted)
                .tint(Theme.primaryInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("welcome.agreement")
                .staggerIn(appeared, delay: 0.76, distance: 6)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: auth.errorMessage)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: auth.infoMessage)
    }

    /// Apple's own button (HIG: the system draws the logo, title and proportions): 「Appleで登録」 on the sign-up page,
    /// 「Appleでサインイン」 on the sign-in page (the system's words for each).
    @ViewBuilder
    private var apple: some View {
        if AppConfig.nativeAppleSignIn {
            SignInWithAppleButton(isSignUp ? .signUp : .signIn) { req in
                auth.prepareApple(req)
            } onCompletion: { result in
                Task { await auth.completeApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)  // HIG: white on a dark screen
            .frame(height: 54)
            .clipShape(.capsule)
            .id(isSignUp)  // the title is fixed at creation
            .accessibilityIdentifier("welcome.apple")
        } else {
            // The tap runs the web sign-in so the account is the same as on the web.
            AppleIDWebButton(type: isSignUp ? .signUp : .signIn, style: colorScheme == .dark ? .white : .black,
                             cornerRadius: 27, identifier: "welcome.apple", isEnabled: !auth.isBusy) {
                Task { await auth.signInWithWeb(provider: "apple") }
            }
            .id("\(colorScheme)-\(isSignUp)")  // the button's type and style are fixed at creation; rebuild it when they change
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
    }

    /// 「または」 between the one-tap ways in and mail.
    private var orLine: some View {
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
    }

    /// 「メールで登録」 / 「メールでログイン」: opens the fields (owner 2026-10-29: 「タップしたら、入力する欄を出して」).
    private var mailButton: some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMail = true }
            Task { try? await Task.sleep(for: .milliseconds(350)); focused = .email }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                Text(isSignUp ? L("メールで登録") : L("メールでログイン"))
                    .scaledFont(size: 17, weight: .semibold)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("welcome.mail")
    }

    private var mailForm: some View {
        VStack(spacing: 10) {
            TextField("", text: $email, prompt: Text(L("メールアドレス")).foregroundStyle(Theme.muted))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .authFieldStyle()
                .accessibilityIdentifier("auth.email")
            SecureField("", text: $password, prompt: Text(L("パスワード")).foregroundStyle(Theme.muted))
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .authFieldStyle()
                .accessibilityIdentifier("auth.password")
            PrimaryButton(title: isSignUp ? L("新規登録") : L("ログイン"), isLoading: auth.isBusy, action: submit)
                .disabled(trimmedEmail.isEmpty || password.isEmpty)
                .accessibilityIdentifier("auth.submit")
            if !isSignUp {
                Button(L("パスワードを忘れた")) {
                    Task { await auth.resetPassword(email: trimmedEmail) }
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .disabled(trimmedEmail.isEmpty)
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let msg = auth.errorMessage {
            Label(msg, systemImage: "exclamationmark.circle.fill")
                .scaledFont(size: 13)
                .foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let msg = auth.infoMessage {
            Label(msg, systemImage: "checkmark.circle.fill")
                .scaledFont(size: 13)
                .foregroundStyle(Theme.ok)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            if auth.awaitingConfirmation {
                PrimaryButton(title: L("確認が終わったので、ログインする"), icon: "arrow.right") {
                    withAnimation(.snappy) {
                        isSignUp = false
                        showMail = true
                        auth.awaitingConfirmation = false
                        auth.infoMessage = nil
                    }
                    focused = .password
                }
            }
        }
    }

    /// The other page, one tap at the bottom (owner 2026-10-29: 「アカウントをお持ちの人はログインをしたに配置し」).
    private var otherPage: some View {
        Button {
            Haptics.selection()
            auth.errorMessage = nil
            withAnimation(.snappy) { isSignUp.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(isSignUp ? L("アカウントをお持ちの方は") : L("初めての方は"))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 3) {
                    Text(isSignUp ? L("ログイン") : L("新規登録")).fontWeight(.bold)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).accessibilityHidden(true)
                }
                .foregroundStyle(Theme.primaryInk)
            }
            .scaledFont(size: 15)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .contentTransition(.opacity)
        .accessibilityIdentifier("welcome.switch")
    }

    /// AutoFill and the keyboard's suggestion bar can leave a space at either end of the address.
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        // The keyboard's Go key works even while the button is greyed out.
        guard !trimmedEmail.isEmpty, !password.isEmpty, !auth.isBusy else { return }
        focused = nil
        let mail = trimmedEmail
        Task {
            if isSignUp {
                await auth.signUp(email: mail, password: password)
            } else {
                await auth.signIn(email: mail, password: password)
            }
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
