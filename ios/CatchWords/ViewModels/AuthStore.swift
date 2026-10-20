import SwiftUI
import AuthenticationServices
import CryptoKit

nonisolated enum AuthPhase: Equatable, Sendable {
    case checking
    case signedOut
    case signedIn
    case failed(String)
}

@Observable
final class AuthStore {
    var phase: AuthPhase = .checking
    var isBusy: Bool = false
    var errorMessage: String?
    var infoMessage: String?
    /// True after sign-up sent a confirmation email: the screen offers "I've confirmed — sign in".
    var awaitingConfirmation: Bool = false
    var email: String? { SupabaseClient.shared.session?.email }

    /// Development builds only: enter the app without logging in (anonymous guest).
    /// App Store builds are Release builds, so this is off there automatically.
    static let devSkipLogin: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
    /// True while inside the app without a real account (guest mode).
    var isGuest: Bool = false

    private let client = SupabaseClient.shared
    private var currentNonce: String?
    private var webAuth: WebAuthSession?

    /// A login saved on this device opens the app at once, without waiting for the network (a slow or
    /// unanswered connection must not lock the learner out of what works offline); the token is refreshed
    /// in the background. A login the server no longer accepts ends through the usual path: the refresh
    /// calls `SupabaseClient.expireSession()`, which posts `.sessionExpired` → `sessionExpired()` → the
    /// login screen with the reason. No saved login → the login screen (nothing to wait for).
    func bootstrap() async {
        phase = .checking
        guard client.session != nil else {
            if Self.devSkipLogin { await enterAsGuest() } else { phase = .signedOut }
            return
        }
        phase = .signedIn
        Task { [client] in
            // Network errors keep the saved login (offline use); a rejected refresh token has already
            // expired the session inside `refreshIfNeeded`.
            try? await client.refreshIfNeeded()
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            try await self.client.signIn(email: email, password: password)
            self.phase = .signedIn
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            let signedIn = try await self.client.signUp(email: email, password: password)
            if signedIn {
                self.phase = .signedIn
            } else {
                self.infoMessage = L("確認メールを送りました。メールのリンクを開いて登録を完了したら、このアプリに戻って「ログイン」してください。")
                self.awaitingConfirmation = true
            }
        }
    }

    func resetPassword(email: String) async {
        await run {
            try await self.client.sendPasswordReset(email: email)
            self.infoMessage = L("パスワード設定用のメールを送りました。")
        }
    }

    /// Google (or another OAuth provider) through Supabase Auth's sign-in page in the system sheet
    /// (`WebAuthSession`, PKCE): the code it hands back is exchanged here for the session. Closing the sheet is
    /// not an error.
    func signInWithWeb(provider: String) async {
        let verifier = PKCE.makeVerifier()
        let web = WebAuthSession()
        webAuth = web
        defer { webAuth = nil }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        awaitingConfirmation = false
        defer { isBusy = false }
        do {
            let url = try await web.signIn(provider: provider, codeChallenge: PKCE.challenge(for: verifier))
            switch AuthCallback.parse(url) {
            case .code(let code):
                try await client.exchangeOAuthCode(code, verifier: verifier)
            case .error(let detail):
                DevLog.shared.add("auth", "\(provider): \(detail)")
                throw WebAuthSession.Failure.failed
            case nil:
                throw APIError.message(L("ログインの応答が正しくありません。もう一度お試しください。"))
            }
            isGuest = false
            phase = .signedIn
            Haptics.success()
        } catch WebAuthSession.Failure.cancelled {
            // closed the sheet
        } catch WebAuthSession.Failure.failed {
            errorMessage = provider == "apple" ? L("Appleでのログインに失敗しました。") : L("Googleでのログインに失敗しました。")
            Haptics.warning()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("エラーが発生しました。")
            Haptics.warning()
        }
    }

    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(nonce)
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = L("Appleでのログインに失敗しました。")
            }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = L("Appleでのログインに失敗しました。")
                return
            }
            // Kept so the server can revoke this Apple grant when the account is deleted (Guideline 5.1.1(v)).
            let authCode = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            await run {
                try await self.client.signInWithApple(idToken: token, nonce: nonce)
                self.phase = .signedIn
                if let authCode, let uid = self.client.userId {
                    Self.storeAppleAuthCode(authCode, for: uid)
                }
            }
        }
    }

    /// Hands Apple's one-time `authorizationCode` to the server (`storeAppleAuthCode`), which exchanges it
    /// for a refresh token so deleting the account can revoke Sign in with Apple. Fire-and-forget in the
    /// background: sign-in never waits for it, and any failure (no network, a server without the function,
    /// missing Apple keys, a different account signed in meanwhile) is ignored.
    private static func storeAppleAuthCode(_ code: String, for uid: String) {
        Task {
            _ = try? await NativeAPI.call("storeAppleAuthCode", ["code": code], timeout: 20, asUser: uid)
        }
    }

    /// Tries a Supabase anonymous session (so saving works); falls back to a local-only guest entry.
    func enterAsGuest() async {
        do {
            try await client.signInAnonymously()
            isGuest = false
        } catch {
            print("[Auth] anonymous sign-in unavailable, entering local guest mode")
            isGuest = true
        }
        errorMessage = nil
        phase = .signedIn
    }

    /// The display language goes back to the iPhone's (fresh-install default) unless `keepLanguage`
    /// (onboarding's 「ログイン」, where the learner has just picked it on screen).
    func signOut(keepLanguage: Bool = false) {
        client.signOutRevokingSession()
        isGuest = false
        ReaderLanguage.serverLang = nil  // the next account's comes with its profile
        if !keepLanguage { L10n.resetToDevice() }
        phase = .signedOut
    }

    /// The server no longer accepts this login (signed out everywhere, token revoked): back to the
    /// login screen with the reason, instead of every request failing quietly.
    func sessionExpired() {
        guard phase == .signedIn else { return }
        client.signOut()
        isGuest = false
        phase = .signedOut
        infoMessage = nil
        errorMessage = APIError.unauthorized.errorDescription
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        awaitingConfirmation = false
        defer { isBusy = false }
        do {
            try await work()
            Haptics.success()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("エラーが発生しました。")
            Haptics.warning()
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars.randomElement() ?? "a" })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
