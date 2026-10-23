import Foundation

nonisolated enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case timeout
    /// This device has no network at all (airplane mode, no signal, cellular data off for the app).
    case offline
    /// The device is online, but the connection to the server could not be made or dropped mid-request (the
    /// `URLError` code is kept for the developer log, e.g. -1005 for a connection the server closed). Before
    /// 2026-10-15 these all read 「インターネットに接続できません」 too, so a dropped save looked like being offline.
    case connectionLost(Int)
    case server(Int, String)
    case decoding
    case message(String)
    /// The server's rolling-24h cap (`assertWithinDailyCap`). Waiting a few minutes does not help.
    case limit(String)
    /// An AI function was refused before sending: this account has not agreed to send data to AI (`AIConsent`).
    case aiConsentRequired

    /// err.dailyCap (web i18n).
    static var dailyCapMessage: String { L("1日の利用上限に達しました。24時間以内に自動で回復します。") }

    var errorDescription: String? {
        switch self {
        case .notConfigured: L("サーバーの設定が見つかりません。")
        case .unauthorized: L("ログインの有効期限が切れました。もう一度ログインしてください。")
        case .timeout: L("通信が時間切れになりました。電波の良い場所でもう一度お試しください。")
        case .offline: L("インターネットに接続できません。")
        case .connectionLost(let code): L("サーバーとの通信が途中で切れました（\(code)）。")
        case .server(let code, let msg): L10n.readerSafe(msg, fallback: L("サーバーエラー（\(code)）"))
        case .decoding: L("データの読み込みに失敗しました。")
        case .message(let m): L10n.readerSafe(m, fallback: L("うまくいきませんでした。もう一度お試しください。"))
        case .limit(let m): L10n.readerSafe(m, fallback: Self.dailyCapMessage)
        case .aiConsentRequired: L("AIを使う機能は、AIへのデータ送信に同意すると使えます。")
        }
    }

    /// Whether retrying later may succeed (the web app shows the reason instead of a blanket "later").
    var isRetryable: Bool {
        switch self {
        case .timeout, .offline, .connectionLost: true
        case .server(let code, _): code >= 500 || code == 429
        case .limit: false
        default: false
        }
    }
}

/// Minimal Supabase REST client talking to the SAME project as the Lovable web app.
/// RLS (`auth.uid() = user_id`) protects every row, so the app talks to it directly.
final class SupabaseClient {
    static let shared = SupabaseClient()

    private let baseURL: URL?
    private let anonKey: String
    private let sessionAccount = "supabase.session"
    private(set) var session: AuthSession?
    private let urlSession: URLSession

    init() {
        let raw = AppConfig.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = raw.isEmpty ? nil : URL(string: raw)
        anonKey = AppConfig.supabasePublishableKey
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        #if DEBUG
        DemoBackend.configure(cfg)  // -uiDemo: answered offline, never production
        #endif
        urlSession = URLSession(configuration: cfg)
        if let data = KeychainStore.load(account: sessionAccount) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    var userId: String? { session?.userId }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let json = try await authRequest(path: "token?grant_type=password", body: ["email": email, "password": password])
        try storeSession(json)
    }

    /// Returns true when a session was created immediately (email confirmation disabled).
    /// The display language rides along as user_metadata: the confirmation email is written in it
    /// (`supabase/templates`), and it is sent before the account has a profile.
    func signUp(email: String, password: String) async throws -> Bool {
        let json = try await authRequest(path: "signup", body: [
            "email": email, "password": password, "data": ["ui_language": L10n.lang],
        ])
        if json["access_token"] != nil {
            try storeSession(json)
            return true
        }
        return false
    }

    /// Supabase anonymous sign-in (only works when anonymous sign-ins are enabled on the project).
    func signInAnonymously() async throws {
        let json = try await authRequest(path: "signup", body: [:])
        try storeSession(json)
    }

    /// Finishes an OAuth sign-in (Google): the code from `catchwords://auth-callback?code=…` plus the PKCE
    /// verifier only this device holds (`WebAuthSession`).
    func exchangeOAuthCode(_ code: String, verifier: String) async throws {
        let json = try await authRequest(path: "token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
        try storeSession(json)
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await signInWithIdToken(provider: "apple", idToken: idToken, nonce: nonce)
    }

    /// Signs in with an OpenID Connect ID token from Apple or Google (`grant_type=id_token`). The token's
    /// audience must be one of the provider's client IDs in the project's Auth settings; `nonce` is the raw
    /// nonce whose SHA-256 went to the provider.
    func signInWithIdToken(provider: String, idToken: String, nonce: String, accessToken: String? = nil) async throws {
        var body = ["provider": provider, "id_token": idToken, "nonce": nonce]
        if let accessToken { body["access_token"] = accessToken }
        let json = try await authRequest(path: "token?grant_type=id_token", body: body)
        try storeSession(json)
    }

    /// Sends the password (re)set email. Also lets Google/Apple users add a password to the SAME account (UUID).
    func sendPasswordReset(email: String) async throws {
        _ = try await authRequest(
            path: "recover?redirect_to=\(AppConfig.passwordResetURL.absoluteString)",
            body: ["email": email]
        )
    }

    /// Merges keys into auth `user_metadata` (the web keeps learning_preferences / notification_preferences there).
    func updateUserMetadata(_ data: [String: Any]) async throws {
        try await refreshForRequest()
        guard let baseURL, let token = session?.accessToken,
              let url = URL(string: "auth/v1/user", relativeTo: baseURL) else { throw APIError.notConfigured }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "PUT"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])
        let (_, response) = try await perform(req)
        guard (200..<300).contains(response.statusCode) else { throw APIError.server(response.statusCode, "") }
    }

    /// After `deleteMyAccount`: asks Supabase Auth itself whether the login still exists, with the session
    /// this device still holds. `GET auth/v1/user` answers 200 only while the auth user exists (deleted →
    /// 401/403/404 "user not found"), and the refresh token stops working once its sessions are gone.
    /// `true` = the login is proven gone; `false` = Auth still knows this user; `nil` = could not ask (offline).
    func verifyLoginDeleted() async -> Bool? {
        guard let baseURL, let s = session,
              let userURL = URL(string: "auth/v1/user", relativeTo: baseURL),
              let refreshURL = URL(string: "auth/v1/token?grant_type=refresh_token", relativeTo: baseURL) else { return nil }
        var userReq = URLRequest(url: userURL, timeoutInterval: 15)
        userReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        userReq.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        guard let (_, userRes) = try? await urlSession.data(for: userReq),
              let userCode = (userRes as? HTTPURLResponse)?.statusCode else { return nil }
        if (200..<300).contains(userCode) { return false }
        guard [401, 403, 404].contains(userCode) else { return nil }
        var refreshReq = URLRequest(url: refreshURL, timeoutInterval: 15)
        refreshReq.httpMethod = "POST"
        refreshReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        refreshReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        refreshReq.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        guard let (_, refreshRes) = try? await urlSession.data(for: refreshReq),
              let refreshCode = (refreshRes as? HTTPURLResponse)?.statusCode else { return nil }
        return !(200..<300).contains(refreshCode)
    }

    /// The signed-in user's `user_metadata` (notification_preferences, learning_preferences…).
    func userMetadata() async throws -> [String: Any] {
        try await refreshForRequest()
        guard let baseURL, let token = session?.accessToken,
              let url = URL(string: "auth/v1/user", relativeTo: baseURL) else { throw APIError.notConfigured }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(req)
        guard (200..<300).contains(response.statusCode),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw APIError.server(response.statusCode, "") }
        return json["user_metadata"] as? [String: Any] ?? [:]
    }

    /// Refreshes the access token when it is about to expire (or `force`, after a 401).
    ///
    /// A refresh token the server no longer accepts (revoked by "sign out everywhere", already rotated,
    /// expired) means the login is over: the session is dropped, `.sessionExpired` is posted so the app
    /// returns to the login screen, and `APIError.unauthorized` is thrown. A network or server error keeps
    /// the session — the caller goes on with the current token and may simply be offline.
    /// `within`: refresh when the token expires within this many seconds (the camera refreshes earlier, so the
    /// photo's request never waits for a refresh — `NativeAPI.warmUp`).
    func refreshIfNeeded(force: Bool = false, within: TimeInterval = 120) async throws {
        guard let current = session else { throw APIError.unauthorized }
        guard force || current.expiresAt.timeIntervalSinceNow < within else { return }
        // One refresh at a time: refresh tokens rotate, so two concurrent refreshes would make the
        // second one fail as "already used" and log the user out for nothing.
        if let running = refreshTask { return try await running.value }
        let token = current.refreshToken
        let task = Task<Void, Error> { [self] in
            try await refreshSession(refreshToken: token)
        }
        refreshTask = task
        // Cleared by the caller that started it, and only while it is still the current one: a sign-out
        // drops it, and a refresh started after that (next account) must not be cleared by this one.
        defer { if refreshTask == task { refreshTask = nil } }
        try await task.value
    }

    private var refreshTask: Task<Void, Error>?

    private func refreshSession(refreshToken: String) async throws {
        guard let baseURL, let url = URL(string: "auth/v1/token?grant_type=refresh_token", relativeTo: baseURL) else {
            throw APIError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let (data, response) = try await perform(req)
        // Signed out (or into another account) while the request was in flight: the answer belongs to a
        // session that is gone — never restore it, overwrite the next account, or sign that one out.
        guard session?.refreshToken == refreshToken else { throw CancellationError() }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (200..<300).contains(response.statusCode) {
            try storeSession(json)
            return
        }
        if Self.isRefreshTokenRejected(status: response.statusCode, json: json) {
            expireSession()
            throw APIError.unauthorized
        }
        let msg = (json["error_description"] as? String) ?? (json["msg"] as? String) ?? ""
        throw APIError.server(response.statusCode, msg)
    }

    /// GoTrue answers 400/401 with `error_code` (`refresh_token_not_found`, `refresh_token_already_used`,
    /// `session_not_found`) or `error: invalid_grant` when the refresh token is dead.
    private static func isRefreshTokenRejected(status: Int, json: [String: Any]) -> Bool {
        guard status == 400 || status == 401 || status == 403 else { return false }
        let code = ((json["error_code"] as? String) ?? (json["code"] as? String) ?? "").lowercased()
        let err = ((json["error"] as? String) ?? "").lowercased()
        let desc = ((json["error_description"] as? String) ?? (json["msg"] as? String) ?? "").lowercased()
        if ["refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired",
            "user_not_found", "user_banned"].contains(code) { return true }
        if err == "invalid_grant" { return true }
        return desc.contains("refresh token") || desc.contains("session")
    }

    /// The login is over (dead refresh token, or still 401 after a fresh token): drop the session and
    /// tell the app, which shows the login screen with the "expired" message.
    func expireSession() {
        guard session != nil else { return }
        signOut()
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        KeychainStore.delete(account: sessionAccount)
    }

    /// A sign-out the user asked for: the local session goes at once, and the server is told to revoke
    /// this device's session (`POST auth/v1/logout?scope=local`, so the web stays signed in) in the
    /// background. Best effort: offline or a server error never holds the sign-out up.
    func signOutRevokingSession() {
        guard let ended = session else { signOut(); return }
        signOut()
        guard let baseURL else { return }
        let key = anonKey
        let http = urlSession
        Task.detached {
            await SupabaseClient.revoke(ended, baseURL: baseURL, anonKey: key, urlSession: http)
        }
    }

    /// `/logout` needs a live access token: an expired one is swapped for a fresh one first (with the
    /// refresh token the device still holds), so the refresh token is revoked too.
    nonisolated private static func revoke(_ s: AuthSession, baseURL: URL, anonKey: String, urlSession: URLSession) async {
        var access = s.accessToken
        if s.expiresAt.timeIntervalSinceNow < 30,
           let url = URL(string: "auth/v1/token?grant_type=refresh_token", relativeTo: baseURL) {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
            guard let answer = try? await urlSession.data(for: req),
                  let json = (try? JSONSerialization.jsonObject(with: answer.0)) as? [String: Any],
                  let fresh = json["access_token"] as? String else { return }
            access = fresh
        }
        guard let url = URL(string: "auth/v1/logout?scope=local", relativeTo: baseURL) else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        _ = try? await urlSession.data(for: req)
    }

    private func authRequest(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let baseURL, let url = URL(string: "auth/v1/\(path)", relativeTo: baseURL) else { throw APIError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await perform(req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            let msg = (json["error_description"] as? String) ?? (json["msg"] as? String) ?? (json["message"] as? String) ?? ""
            throw APIError.message(Self.localizeAuthError(msg, code: response.statusCode))
        }
        return json
    }

    private func storeSession(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let uid = user["id"] as? String else { throw APIError.decoding }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        persist(AuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userId: uid,
            email: user["email"] as? String
        ))
    }

    private func persist(_ s: AuthSession) {
        session = s
        if let data = try? JSONEncoder().encode(s) { KeychainStore.save(data, account: sessionAccount) }
    }

    private static func localizeAuthError(_ msg: String, code: Int) -> String {
        let m = msg.lowercased()
        if m.contains("invalid login") { return L("メールアドレスかパスワードが違います。") }
        if m.contains("already registered") { return L("このメールアドレスは登録済みです。ログインしてください。") }
        if m.contains("known to be weak") || m.contains("weak_password") { return L("このパスワードは推測されやすいため使えません。英字と数字を混ぜた、ほかのパスワードにしてください。") }
        if m.contains("password should be") { return L("パスワードは6文字以上にしてください。") }
        if m.contains("email not confirmed") { return L("確認メールのリンクを開いてからログインしてください。") }
        if m.contains("rate limit") { return L("しばらく時間をおいてからお試しください。") }
        return L("ログインに失敗しました（\(code)）")  // never the raw English message (G2)
    }

    // MARK: - REST

    func rest(
        _ method: String,
        _ path: String,
        body: Any? = nil,
        prefer: String? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        try await refreshForRequest()
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, response) = try await withTokenRetry { token in
            guard let baseURL, let url = URL(string: "rest/v1/\(path)", relativeTo: baseURL) else { throw APIError.notConfigured }
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.httpMethod = method
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
            req.httpBody = bodyData
            return try await perform(req)
        }
        guard (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError.server(response.statusCode, (json?["message"] as? String) ?? "")
        }
        return data
    }

    /// Every row of a GET, a page at a time. The server returns at most 1000 rows per request whatever
    /// `limit` says, so a single big `limit` silently dropped the rest. `path` must have a stable,
    /// unique `order` (end it with the primary key) and no `limit` / `offset` of its own.
    func restAll<T: Decodable>(_ path: String, as: T.Type, decoder: JSONDecoder,
                               pageSize: Int = 1000, maxPages: Int = 20) async throws -> [T] {
        var out: [T] = []
        for page in 0..<maxPages {
            let data = try await rest("GET", "\(path)&limit=\(pageSize)&offset=\(page * pageSize)")
            let chunk = try decoder.decode([T].self, from: data)
            out += chunk
            if chunk.count < pageSize { break }
        }
        return out
    }

    /// Before a request: refresh an expiring token, but never fail the request for a network hiccup
    /// during the refresh — the current token may still work (or the request reports offline itself).
    /// A dead refresh token (`.unauthorized`) does fail it: the user has to log in again.
    func refreshForRequest() async throws {
        do {
            try await refreshIfNeeded()
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch {
            // offline / server error: go on with the token we have
        }
    }

    /// Runs a request with the current token; on 401 refreshes once (forced) and retries. A second 401
    /// means the login is over.
    func withTokenRetry(_ send: (String) async throws -> (Data, HTTPURLResponse)) async throws -> (Data, HTTPURLResponse) {
        guard let token = session?.accessToken, let uid = session?.userId else { throw APIError.unauthorized }
        let first = try await send(token)
        guard Self.isExpiredToken(first) else { return first }
        // Another account (or none) since the first try: never refresh, retry or expire on its behalf.
        guard session?.userId == uid else { throw CancellationError() }
        try await refreshIfNeeded(force: true)
        guard let fresh = session?.accessToken, session?.userId == uid else { throw CancellationError() }
        let second = try await send(fresh)
        guard session?.userId == uid else { throw CancellationError() }
        if Self.isExpiredToken(second) {
            expireSession()
            throw APIError.unauthorized
        }
        return second
    }

    /// 401, or Storage's way of saying the same: HTTP 400 (sometimes 403) with `jwt expired`,
    /// `"exp" claim timestamp check failed` or `InvalidJWT` in the body.
    nonisolated static func isExpiredToken(_ answer: (Data, HTTPURLResponse)) -> Bool {
        let status = answer.1.statusCode
        if status == 401 { return true }
        guard status == 400 || status == 403, answer.0.count < 4096 else { return false }
        let body = String(decoding: answer.0, as: UTF8.self).lowercased()
        return body.contains("jwt expired") || body.contains("\"exp\" claim") || body.contains("exp claim")
            || body.contains("invalidjwt") || body.contains("token is expired")
    }

    // MARK: - Storage (private bucket "stickers": {uuid}/{ts}-{kind}.jpg)

    /// `existsIsDone`: this is another try of the same file (`UploadRetry`). If an earlier try had landed after all,
    /// storage answers that the file exists — every name is new (a time stamp), so it is ours and the upload is done.
    func upload(_ data: Data, path: String, contentType: String = "image/jpeg", bucket: String = "stickers", upsert: Bool = false,
                existsIsDone: Bool = false) async throws {
        try await refreshForRequest()
        guard let baseURL, let url = URL(string: "storage/v1/object/\(bucket)/\(path)", relativeTo: baseURL) else {
            throw APIError.notConfigured
        }
        // A token that expired on the way (clock skew, a long upload queue) gets one refresh and a retry.
        let (body, response) = try await withTokenRetry { token in
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.httpMethod = "POST"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.setValue(upsert ? "true" : "false", forHTTPHeaderField: "x-upsert")
            req.httpBody = data
            return try await perform(req)
        }
        guard (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let message = (json?["message"] as? String) ?? ""
            if existsIsDone, Self.isAlreadyThere(status: response.statusCode, json: json) { return }
            throw APIError.server(response.statusCode, message.isEmpty ? L("写真の保存に失敗しました。") : message)
        }
    }

    /// Storage's answer to a file that is already there (409, or 400 with statusCode "409" / error "Duplicate").
    nonisolated static func isAlreadyThere(status: Int, json: [String: Any]?) -> Bool {
        if status == 409 { return true }
        guard status == 400, let json else { return false }
        let code = (json["statusCode"] as? String) ?? (json["statusCode"] as? Int).map { String($0) } ?? ""
        let error = ((json["error"] as? String) ?? "").lowercased()
        let message = ((json["message"] as? String) ?? "").lowercased()
        return code == "409" || error == "duplicate" || message.contains("already exists")
    }

    /// Deletes one object (`DELETE /storage/v1/object/<bucket>/<path>`). Storage's RLS lets an account delete
    /// only inside its own folder (`avatars_delete_own`: the first folder is its uid). An object that is
    /// already gone counts as deleted (404, or 400 "not found").
    func removeObject(path: String, bucket: String) async throws {
        try await refreshForRequest()
        guard let baseURL, let url = URL(string: "storage/v1/object/\(bucket)/\(path)", relativeTo: baseURL) else {
            throw APIError.notConfigured
        }
        let (body, response) = try await withTokenRetry { token in
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.httpMethod = "DELETE"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return try await perform(req)
        }
        let status = response.statusCode
        if (200..<300).contains(status) || status == 404 { return }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let detail = (json?["message"] as? String) ?? (json?["error"] as? String) ?? ""
        if status == 400, detail.lowercased().contains("not found") { return }
        throw APIError.server(status, detail)
    }

    /// Public bucket URL (avatars).
    func publicURL(bucket: String, path: String) -> String? {
        guard let baseURL, let url = URL(string: "storage/v1/object/public/\(bucket)/\(path)", relativeTo: baseURL) else { return nil }
        return url.absoluteString
    }

    func signedURLs(for paths: [String], expiresIn: Int = 60 * 60 * 6) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        try await refreshForRequest()
        guard let baseURL, let url = URL(string: "storage/v1/object/sign/stickers", relativeTo: baseURL) else {
            throw APIError.notConfigured
        }
        let payload = try JSONSerialization.data(withJSONObject: ["expiresIn": expiresIn, "paths": paths])
        let (data, response) = try await withTokenRetry { token in
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = payload
            return try await perform(req)
        }
        guard (200..<300).contains(response.statusCode),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [:] }
        var out: [String: URL] = [:]
        for item in arr {
            guard let path = item["path"] as? String,
                  let signed = (item["signedURL"] as? String) ?? (item["signedUrl"] as? String),
                  let full = URL(string: "storage/v1\(signed)", relativeTo: baseURL) else { continue }
            out[path] = full.absoluteURL
        }
        return out
    }

    private func perform(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
            return (data, http)
        } catch let error as URLError {
            throw APIError.from(error)
        }
    }
}

extension APIError {
    /// One mapping for every request, never a raw system string. Only a device with no network at all reads as
    /// offline (airplane mode, no signal, cellular data off for the app); a connection that could not be made or
    /// dropped while the device is online (the server closed it, DNS, TLS, a captive Wi-Fi) is `connectionLost` with
    /// its code; an answer that cannot be read is `decoding`. Owner 2026-10-15: a save that failed was reported as
    /// 「ネットワークに接続できませんでした」 whatever had happened. A cancelled request (the screen went away) is a
    /// cancellation, not an error to show.
    nonisolated static func from(_ error: URLError) -> Error {
        switch error.code {
        case .timedOut: return APIError.timeout
        case .cancelled: return CancellationError()
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return APIError.offline
        case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData, .zeroByteResource:
            return APIError.decoding
        default:
            // networkConnectionLost, cannotConnectToHost, cannotFindHost, dnsLookupFailed, secureConnectionFailed …
            return APIError.connectionLost(error.code.rawValue)
        }
    }

    /// The error as the developer log writes it (設定 › 開発者 › アプリの情報): the kind and every detail kept.
    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case let e as APIError:
            switch e {
            case .notConfigured: return "notConfigured"
            case .unauthorized: return "unauthorized (401)"
            case .timeout: return "timeout"
            case .offline: return "offline (no network on the device)"
            case .connectionLost(let code): return "connectionLost URLError \(code) \(urlErrorName(code))"
            case .server(let code, let msg): return "server \(code) \(msg.prefix(200))"
            case .decoding: return "decoding (an answer the app could not read)"
            case .message(let m): return "message \(m.prefix(200))"
            case .limit(let m): return "limit \(m.prefix(120))"
            case .aiConsentRequired: return "aiConsentRequired"
            }
        case let e as URLError:
            return "URLError \(e.code.rawValue) \(urlErrorName(e.code.rawValue))"
        case let e as DecodingError:
            return "DecodingError \(String(describing: e).prefix(300))"
        case is CancellationError:
            return "cancelled"
        default:
            let ns = error as NSError
            return "\(ns.domain) \(ns.code) \(ns.localizedDescription.prefix(200))"
        }
    }

    /// The name of the commonest connection failures, for the developer log.
    nonisolated static func urlErrorName(_ code: Int) -> String {
        switch URLError.Code(rawValue: code) {
        case .networkConnectionLost: return "networkConnectionLost"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .cannotFindHost: return "cannotFindHost"
        case .dnsLookupFailed: return "dnsLookupFailed"
        case .secureConnectionFailed: return "secureConnectionFailed"
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .timedOut: return "timedOut"
        case .cannotLoadFromNetwork: return "cannotLoadFromNetwork"
        case .resourceUnavailable: return "resourceUnavailable"
        case .backgroundSessionWasDisconnected: return "backgroundSessionWasDisconnected"
        default: return ""
        }
    }
}

extension Notification.Name {
    /// Posted by `SupabaseClient` when the login is over (dead refresh token / still 401 after a refresh).
    static let sessionExpired = Notification.Name("app.catchwords.sessionExpired")
}

nonisolated enum SupabaseDate {
    /// Postgres timestamps come with 0–6 fractional digits; normalize before parsing.
    static func parse(_ raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        if let dot = s.firstIndex(of: ".") {
            let rest = s[s.index(after: dot)...]
            let tzStart = rest.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) ?? rest.endIndex
            s.removeSubrange(dot..<tzStart)
        }
        if !(s.hasSuffix("Z") || s.contains("+") || s.dropFirst(10).contains("-")) { s += "Z" }
        return parser.date(from: s)
    }

    static func string(_ date: Date) -> String {
        writer.string(from: date)
    }

    // One formatter each, made once: a new ISO8601DateFormatter per field cost ~1 ms × every date of a
    // 5000-row history read, on the main thread. ISO8601DateFormatter is thread-safe.
    nonisolated(unsafe) private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let writer: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let raw = try c.decode(String.self)
            guard let date = parse(raw) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(raw)")
            }
            return date
        }
        return d
    }
}
