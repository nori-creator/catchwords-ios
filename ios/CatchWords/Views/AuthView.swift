import SwiftUI
import AuthenticationServices

/// Signing in and signing up: the welcome screen is both (owner 2026-10-29: the sign-in page looks like the sign-up page;
/// sign-up first, 「ログイン」 at the bottom; the mail fields open when the mail button is tapped). See `WelcomeView`.
struct AuthView: View {
    /// The sign-in page first (the previews of it).
    var startSignIn: Bool = false
    /// The mail fields already open (the previews of them).
    var startMail: Bool = false

    var body: some View {
        WelcomeView(startSignIn: startSignIn, startMail: startMail)
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

extension View {
    /// The sign-in screen's fields.
    func authFieldStyle() -> some View {
        self
            .scaledFont(size: 16)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.secondary, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }
}
