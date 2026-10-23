import AuthenticationServices
import CryptoKit
import UIKit

/// Google sign-in through the app's own Supabase Auth (OAuth with PKCE), in the system's secure sign-in sheet.
///
/// The sheet (`ASWebAuthenticationSession`) opens Supabase's `/auth/v1/authorize?provider=google`, Google
/// signs the person in, and Supabase sends the sheet back to `catchwords://auth-callback?code=…`. The code is
/// worth nothing on its own: only this device, holding the PKCE verifier it never sent anywhere, can exchange
/// it for a session (`SupabaseClient.exchangeOAuthCode`). No web page of ours is involved.
/// (Until 2026-10-20 this went through the Lovable web app's `/native-auth` bridge.)
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: Error {
        /// The user closed the sheet — not an error to show.
        case cancelled
        case failed
    }

    private var session: ASWebAuthenticationSession?

    /// Opens Supabase's sign-in page for `provider` ("google") and returns the callback URL.
    /// `codeChallenge` is `PKCE.challenge(for: verifier)`.
    func signIn(provider: String, codeChallenge: String) async throws -> URL {
        guard let url = Self.authorizeURL(provider: provider, codeChallenge: codeChallenge) else { throw Failure.failed }
        return try await open(url, callbackScheme: AppConfig.authCallbackScheme)
    }

    /// Opens `url` in the sheet and returns the URL it is sent back to on `callbackScheme`.
    func open(_ url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                Task { @MainActor in
                    self.session = nil
                    if let callback {
                        cont.resume(returning: callback)
                    } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                        cont.resume(throwing: Failure.cancelled)
                    } else {
                        cont.resume(throwing: Failure.failed)
                    }
                }
            }
            // A fresh, private browser each time: a previous Google account isn't silently reused.
            s.prefersEphemeralWebBrowserSession = true
            s.presentationContextProvider = self
            session = s
            if !s.start() {
                session = nil
                cont.resume(throwing: Failure.failed)
            }
        }
    }

    /// `…/auth/v1/authorize?provider=…&redirect_to=catchwords://auth-callback&code_challenge=…&code_challenge_method=s256`
    nonisolated static func authorizeURL(provider: String, codeChallenge: String) -> URL? {
        guard var comps = URLComponents(string: AppConfig.supabaseURL) else { return nil }
        comps.path = "/auth/v1/authorize"
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: AppConfig.authCallbackURL),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return comps.url
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

/// The PKCE pair for one sign-in (RFC 7636): a random verifier kept on the device, and its SHA-256 challenge
/// (base64url, no padding) that goes in the sign-in URL.
nonisolated enum PKCE {
    /// 64 characters from the unreserved set, from the system's secure random generator.
    static func makeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in chars[Int.random(in: 0..<chars.count, using: &rng)] })
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// What Supabase hands back on `catchwords://auth-callback?code=…` (or `?error=…&error_description=…`).
nonisolated enum AuthCallback: Equatable {
    case code(String)
    case error(String)

    /// Nil unless the URL is our callback carrying a code or an error.
    static func parse(_ url: URL) -> AuthCallback? {
        guard url.scheme?.lowercased() == AppConfig.authCallbackScheme,
              url.host?.lowercased() == AppConfig.authCallbackHost,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // Supabase puts the answer in the query; an error can also come in the fragment.
        var items = comps.queryItems ?? []
        if let fragment = comps.fragment, let more = URLComponents(string: "?" + fragment)?.queryItems { items += more }
        var map: [String: String] = [:]
        for it in items { map[it.name] = it.value ?? "" }
        if let code = map["code"], !code.isEmpty { return .code(code) }
        if let e = map["error_description"] ?? map["error"], !e.isEmpty { return .error(e) }
        return nil
    }
}
