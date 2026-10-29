import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUp: Bool = false
    @State private var showMail: Bool = false
    /// Opened from the welcome screen's 「メールでログイン」 / 「新規登録」: only the mail form (Google and Apple are on
    /// the welcome screen itself).
    @State private var mailOnly: Bool = false
    @State private var appeared: Bool = false
    /// Nudges the form sideways when sign-in fails, like a head shake.
    @State private var shake: CGFloat = 0
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    /// The welcome screen comes first (`WelcomeView`, with Google and Apple); its 「メールでログイン」 and 「新規登録」 open
    /// this screen with the mail form.
    @State private var showOptions: Bool

    init(startOnOptions: Bool = false) {
        _showOptions = State(initialValue: startOnOptions)
    }

    var body: some View {
        ZStack {
            if showOptions {
                options
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                WelcomeView(onMail: { openMail(signUp: false) }, onSignUp: { openMail(signUp: true) })
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: showOptions)
        .onAppear {
            // Back here with a reason (the session expired) or a pending confirmation: show it at once.
            if auth.errorMessage != nil || auth.infoMessage != nil {
                showOptions = true
            }
        }
    }

    private func openMail(signUp: Bool) {
        Haptics.selection()
        isSignUp = signUp
        mailOnly = true
        showMail = true
        auth.errorMessage = nil
        // No keyboard yet: the screen is read first (the address field is one tap away, as before).
        showOptions = true
    }

    private var options: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    Button {
                        focused = nil
                        showOptions = false
                        mailOnly = false
                        showMail = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(L("戻る"))
                    .accessibilityIdentifier("auth.back")
                    Spacer()
                }
                .padding(.horizontal, -12)
                .padding(.bottom, -20)
                hero
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)

                VStack(spacing: 12) {
                    if !mailOnly { providers }

                    if showMail { mailForm.offset(x: shake).transition(.opacity.combined(with: .move(edge: .top))) }

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
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: auth.errorMessage)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: auth.infoMessage)
                .onChange(of: auth.errorMessage) { _, msg in
                    guard msg != nil, !reduceMotion else { return }
                    Task {
                        for x in [12.0, -10, 7, -4, 0] {
                            withAnimation(.spring(response: 0.08, dampingFraction: 0.4)) { shake = x }
                            try? await Task.sleep(for: .milliseconds(60))
                        }
                    }
                }

                // Consent to the terms and the privacy policy is given by continuing (both pages are links).
                Text(LegalLinks.signInAgreement())
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.muted)
                    .tint(Theme.primaryInk)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("auth.agreement")

                HStack(spacing: 16) {
                    Link(L("利用規約"), destination: AppConfig.termsURL)
                    Link(L("プライバシー"), destination: AppConfig.privacyURL)
                }
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .readableColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .statusBarScrim()
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.05)) { appeared = true }
        }
    }

    /// Google, Apple and 「メールアドレスで続ける」 (which opens the mail form under them).
    @ViewBuilder
    private var providers: some View {
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
            .background(.white, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x747775), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(auth.isBusy)
        .accessibilityIdentifier("auth.google")

        if AppConfig.nativeAppleSignIn {
            SignInWithAppleButton(.signIn) { req in
                auth.prepareApple(req)
            } onCompletion: { result in
                Task { await auth.completeApple(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)  // HIG: white on a dark screen
            .frame(height: 54)
            .clipShape(.rect(cornerRadius: 16))
        } else {
            // Apple's own button (HIG: the system draws the logo, title and proportions), but the tap
            // runs the web sign-in so the account is the same as on the web.
            AppleIDWebButton(style: colorScheme == .dark ? .white : .black, isEnabled: !auth.isBusy) {
                Task { await auth.signInWithWeb(provider: "apple") }
            }
            .id(colorScheme)  // the button's style is fixed at creation; rebuild it when the scheme flips
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .accessibilityIdentifier("auth.apple")
        }

        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMail.toggle() }
            if showMail {
                Task { try? await Task.sleep(for: .milliseconds(350)); focused = .email }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                Text(L("メールアドレスで続ける")).scaledFont(size: 17, weight: .semibold)
            }
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .glassCard(16)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("auth.mail")
    }

    private var hero: some View {
        VStack(spacing: 14) {
            WelcomeLogo(size: 72)
            Text(verbatim: "CatchWords")
                .scaledFont(size: 30, weight: .heavy)
                .foregroundStyle(Theme.foreground)
            Text(isSignUp ? L("新規登録") : L("ログイン"))
                .scaledFont(size: 26, weight: .bold)
                .foregroundStyle(Theme.foreground)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
        }
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
                .fieldStyle()
                .accessibilityIdentifier("auth.email")
            SecureField("", text: $password, prompt: Text(L("パスワード")).foregroundStyle(Theme.muted))
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .fieldStyle()
                .accessibilityIdentifier("auth.password")
            PrimaryButton(title: isSignUp ? L("新規登録") : L("ログイン"), isLoading: auth.isBusy, action: submit)
                .disabled(trimmedEmail.isEmpty || password.isEmpty)
                .accessibilityIdentifier("auth.submit")
            HStack {
                Button(isSignUp ? L("ログインに切り替え") : L("新規登録はこちら")) {
                    Haptics.selection()
                    withAnimation(.snappy) { isSignUp.toggle() }
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .contentTransition(.opacity)
                Spacer()
                if !isSignUp {
                    Button(L("パスワードを忘れた")) {
                        Task { await auth.resetPassword(email: trimmedEmail) }
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(trimmedEmail.isEmpty)
                    .transition(.opacity)
                }
            }
            .scaledFont(size: 13, weight: .medium)
            .foregroundStyle(Theme.primary)
            .frame(minHeight: 44)
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
        }
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

/// The system "Sign in with Apple" button (`ASAuthorizationAppleIDButton`, so the look follows the HIG) with our
/// own tap action. `SignInWithAppleButton` always starts the native ASAuthorization flow, so it can't be used
/// while Apple sign-in goes through the web app (`AppConfig.nativeAppleSignIn == false`).
struct AppleIDWebButton: UIViewRepresentable {
    var type: ASAuthorizationAppleIDButton.ButtonType = .signIn
    var style: ASAuthorizationAppleIDButton.Style
    var cornerRadius: CGFloat = 16
    var identifier: String = "auth.apple"
    var isEnabled: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: type, authorizationButtonStyle: style)
        button.cornerRadius = cornerRadius
        button.accessibilityIdentifier = identifier
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.5
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Google's standard four-colour "G" (Sign in with Google branding guidelines), as vectors: the official
/// logo's path data (48 × 48 view box) scaled to the frame, so it stays crisp at any size.
struct GoogleMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            GoogleGPart(part: .red).fill(Color(hex: 0xEA4335))
            GoogleGPart(part: .blue).fill(Color(hex: 0x4285F4))
            GoogleGPart(part: .yellow).fill(Color(hex: 0xFBBC05))
            GoogleGPart(part: .green).fill(Color(hex: 0x34A853))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One colour of the Google "G" (absolute coordinates of the official SVG, view box 0 0 48 48).
private struct GoogleGPart: Shape {
    enum Part { case red, blue, yellow, green }
    let part: Part

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch part {
        case .red:
            p.move(to: CGPoint(x: 24, y: 9.5))
            p.addCurve(to: CGPoint(x: 33.21, y: 13.1), control1: CGPoint(x: 27.54, y: 9.5), control2: CGPoint(x: 30.71, y: 10.72))
            p.addLine(to: CGPoint(x: 40.06, y: 6.25))
            p.addCurve(to: CGPoint(x: 24, y: 0), control1: CGPoint(x: 35.9, y: 2.38), control2: CGPoint(x: 30.47, y: 0))
            p.addCurve(to: CGPoint(x: 2.56, y: 13.22), control1: CGPoint(x: 14.62, y: 0), control2: CGPoint(x: 6.51, y: 5.38))
            p.addLine(to: CGPoint(x: 10.54, y: 19.41))
            p.addCurve(to: CGPoint(x: 24, y: 9.5), control1: CGPoint(x: 12.43, y: 13.72), control2: CGPoint(x: 17.74, y: 9.5))
            p.closeSubpath()
        case .blue:
            p.move(to: CGPoint(x: 46.98, y: 24.55))
            p.addCurve(to: CGPoint(x: 46.6, y: 20), control1: CGPoint(x: 46.98, y: 22.98), control2: CGPoint(x: 46.83, y: 21.46))
            p.addLine(to: CGPoint(x: 24, y: 20))
            p.addLine(to: CGPoint(x: 24, y: 29.02))
            p.addLine(to: CGPoint(x: 36.94, y: 29.02))
            p.addCurve(to: CGPoint(x: 32.16, y: 36.2), control1: CGPoint(x: 36.36, y: 31.98), control2: CGPoint(x: 34.68, y: 34.5))
            p.addLine(to: CGPoint(x: 39.89, y: 42.2))
            p.addCurve(to: CGPoint(x: 46.98, y: 24.55), control1: CGPoint(x: 44.4, y: 38.02), control2: CGPoint(x: 46.98, y: 31.84))
            p.closeSubpath()
        case .yellow:
            p.move(to: CGPoint(x: 10.53, y: 28.59))
            p.addCurve(to: CGPoint(x: 9.77, y: 24), control1: CGPoint(x: 10.05, y: 27.14), control2: CGPoint(x: 9.77, y: 25.6))
            p.addCurve(to: CGPoint(x: 10.53, y: 19.41), control1: CGPoint(x: 9.77, y: 22.4), control2: CGPoint(x: 10.04, y: 20.86))
            p.addLine(to: CGPoint(x: 2.55, y: 13.22))
            p.addCurve(to: CGPoint(x: 0, y: 24), control1: CGPoint(x: 0.92, y: 16.46), control2: CGPoint(x: 0, y: 20.12))
            p.addCurve(to: CGPoint(x: 2.56, y: 34.78), control1: CGPoint(x: 0, y: 27.88), control2: CGPoint(x: 0.92, y: 31.54))
            p.addLine(to: CGPoint(x: 10.53, y: 28.59))
            p.closeSubpath()
        case .green:
            p.move(to: CGPoint(x: 24, y: 48))
            p.addCurve(to: CGPoint(x: 39.89, y: 42.19), control1: CGPoint(x: 30.48, y: 48), control2: CGPoint(x: 35.93, y: 45.87))
            p.addLine(to: CGPoint(x: 32.16, y: 36.19))
            p.addCurve(to: CGPoint(x: 24, y: 38.49), control1: CGPoint(x: 30.01, y: 37.64), control2: CGPoint(x: 27.24, y: 38.49))
            p.addCurve(to: CGPoint(x: 10.53, y: 28.58), control1: CGPoint(x: 17.74, y: 38.49), control2: CGPoint(x: 12.43, y: 34.27))
            p.addLine(to: CGPoint(x: 2.55, y: 34.77))
            p.addCurve(to: CGPoint(x: 24, y: 48), control1: CGPoint(x: 6.51, y: 42.62), control2: CGPoint(x: 14.62, y: 48))
            p.closeSubpath()
        }
        let scale = min(rect.width, rect.height) / 48
        let transform = CGAffineTransform(translationX: rect.midX - 24 * scale, y: rect.midY - 24 * scale)
            .scaledBy(x: scale, y: scale)
        return p.applying(transform)
    }
}

private extension View {
    func fieldStyle() -> some View {
        self
            .scaledFont(size: 16)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.secondary, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }
}
