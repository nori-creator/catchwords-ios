import CryptoKit
import Foundation

/// Google sign-in straight with Google, in the system's secure sign-in sheet (`WebAuthSession.open`).
///
/// The sheet opens Google's own page for the app's iOS OAuth client (`AppConfig.googleIOSClientID`), so Google
/// names CatchWords instead of the Supabase project address. Google sends the sheet back to the client's
/// reversed-ID scheme with a code; the code, with the PKCE verifier only this device holds, is exchanged at
/// Google for an ID token, and the ID token signs in to Supabase (`grant_type=id_token`, like Apple).
/// No SDK: the same steps as Google's GoogleSignIn library, without adding it to the app.
nonisolated enum GoogleSignIn {
    static let authorizeEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc` (the scheme Google sends
    /// an iOS client back to).
    static func redirectScheme(clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let id = String(clientID.dropLast(suffix.count))
        guard !id.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(id)"
    }

    static func redirectURI(clientID: String) -> String? {
        redirectScheme(clientID: clientID).map { "\($0):/oauth2redirect" }
    }

    /// Google's sign-in page: code flow with PKCE (S256) and the SHA-256 of the nonce (Supabase checks it
    /// against the raw nonce). `prompt=select_account` lets the learner pick the account each time.
    static func authorizeURL(clientID: String, codeChallenge: String, hashedNonce: String) -> URL? {
        guard let redirect = redirectURI(clientID: clientID),
              var comps = URLComponents(string: authorizeEndpoint) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: hashedNonce),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return comps.url
    }

    /// What Google hands back on the redirect scheme: `?code=…` or `?error=…`.
    static func parse(_ url: URL, clientID: String) -> AuthCallback? {
        guard let scheme = redirectScheme(clientID: clientID), url.scheme?.lowercased() == scheme.lowercased(),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var map: [String: String] = [:]
        for item in comps.queryItems ?? [] { map[item.name] = item.value ?? "" }
        if let code = map["code"], !code.isEmpty { return .code(code) }
        if let e = map["error_description"] ?? map["error"], !e.isEmpty { return .error(e) }
        return nil
    }

    /// The form Google's token endpoint takes for an iOS client (no client secret).
    static func tokenRequestBody(code: String, verifier: String, clientID: String) -> Data? {
        guard let redirect = redirectURI(clientID: clientID) else { return nil }
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
        // `+` would read as a space in a form body.
        return comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
    }

    /// Google refused the code (the detail goes to the developer log, not on screen).
    struct TokenError: Error {
        let detail: String
    }

    struct Tokens: Equatable {
        let idToken: String
        let accessToken: String?
    }

    static func exchange(code: String, verifier: String, clientID: String) async throws -> Tokens {
        guard let body = tokenRequestBody(code: code, verifier: verifier, clientID: clientID) else {
            throw WebAuthSession.Failure.failed
        }
        var req = URLRequest(url: tokenEndpoint, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let idToken = json["id_token"] as? String else {
            throw TokenError(detail: json["error"] as? String ?? "no id_token")
        }
        return Tokens(idToken: idToken, accessToken: json["access_token"] as? String)
    }

    /// A random nonce (raw, for Supabase) from the system's secure random generator.
    static func makeNonce() -> String { PKCE.makeVerifier() }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
