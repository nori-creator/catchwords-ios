import AuthenticationServices
import UIKit

/// Google / Apple sign-in through the web app (`/native-auth`, see `lib/native-auth.ts` there).
///
/// Lovable Cloud's Google and Apple logins go through Lovable's own OAuth broker, which the app cannot
/// call directly. So the app opens the web app's bridge page in the system's secure sign-in sheet
/// (`ASWebAuthenticationSession`), the web completes the login exactly as on catchwords.lovable.app, and
/// hands the session back on `catchwords://auth-callback#…`. Same account as the web, no provider setup.
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: Error {
        /// The user closed the sheet — not an error to show.
        case cancelled
        case failed
    }

    private var session: ASWebAuthenticationSession?

    /// Opens the bridge for `provider` ("google" / "apple") and returns the callback URL.
    func signIn(provider: String, state: String) async throws -> URL {
        var comps = URLComponents(url: AppConfig.webBaseURL.appendingPathComponent("native-auth"), resolvingAgainstBaseURL: false)!
        // `lang`: the sheet is a fresh browser each time (no saved web language), so the bridge page is told the app's
        // display language (web `sanitizeNativeLang`; a language the web has no screens for shows in English).
        comps.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "state", value: state),
                            URLQueryItem(name: "lang", value: L10n.lang)]
        guard let url = comps.url else { throw Failure.failed }
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme(AppConfig.authCallbackScheme)) { callback, error in
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
            // A fresh, private browser each time: the web's copy of the session is gone when the sheet closes,
            // and a previous Google account isn't silently reused.
            s.prefersEphemeralWebBrowserSession = true
            s.presentationContextProvider = self
            session = s
            if !s.start() {
                session = nil
                cont.resume(throwing: Failure.failed)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

/// The session the web bridge hands back: `catchwords://auth-callback#access_token=…&refresh_token=…&state=…`.
nonisolated struct AuthCallback: Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let state: String

    /// Nil unless the URL is our callback with every required field. Tokens are in the fragment (never sent
    /// to a server); `expires_at` (unix seconds) is preferred, `expires_in` accepted.
    static func parse(_ url: URL) -> AuthCallback? {
        guard url.scheme?.lowercased() == AppConfig.authCallbackScheme,
              url.host?.lowercased() == AppConfig.authCallbackHost,
              let fragment = url.fragment,
              let items = URLComponents(string: "?" + fragment)?.queryItems else { return nil }
        var map: [String: String] = [:]
        for it in items { map[it.name] = it.value ?? "" }
        guard let access = map["access_token"], !access.isEmpty,
              let refresh = map["refresh_token"], !refresh.isEmpty,
              let state = map["state"], !state.isEmpty else { return nil }
        var expiresAt: Date?
        if let at = map["expires_at"].flatMap(Double.init) {
            expiresAt = Date(timeIntervalSince1970: at)
        } else if let within = map["expires_in"].flatMap(Double.init) {
            expiresAt = Date().addingTimeInterval(within)
        }
        return AuthCallback(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, state: state)
    }
}
