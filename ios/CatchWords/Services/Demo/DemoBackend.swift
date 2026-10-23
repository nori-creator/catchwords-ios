#if DEBUG
import Foundation

/// Offline, deterministic stand-in for every server the app talks to, so UI tests can sign in and walk
/// through every screen on CI without touching production (DEBUG builds only).
///
/// On only when the app is launched with `-uiDemo <learningLanguage>` (zh-TW / en / ja). The display
/// language is chosen separately with `-ui.lang ja|en|zh-TW`. Other launch arguments:
/// - `-uiDemoReset YES`: start clean (signed out, no saved settings, fresh demo data).
/// - `-uiDemoEmpty YES`: an account with a profile but no words (empty states).
/// - `-uiDemoOnboarded NO`: the profile has not finished onboarding.
/// - `-uiDemoPlan pro`: the profile is on the Pro plan.
///
/// Everything lives in memory (`DemoDatabase`), so each launch starts from the same seed.
/// Error paths: a typed headword / caption / draft of `__fail__` answers HTTP 500, `__limit__` answers 429;
/// signing in with the password `wrong` fails with "Invalid login credentials"; signing up with an email that
/// starts with `registered@` says the address is taken, one that starts with `confirm@` waits for confirmation.
///
/// Hooks (DEBUG only): `DemoBackend.install()` at launch (covers `URLSession.shared`) and
/// `DemoBackend.configure(cfg)` for sessions with their own configuration (SupabaseClient).
nonisolated final class DemoBackend: URLProtocol {
    /// The learning language requested with `-uiDemo`, or nil when the demo is off.
    static let learningLanguage: String? = {
        guard let raw = UserDefaults.standard.string(forKey: "uiDemo")?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("zh") { return "zh-TW" }
        if lower.hasPrefix("en") { return "en" }
        if lower.hasPrefix("ja") { return "ja" }
        return nil
    }()

    /// DEBUG build launched with `-uiDemo <zh-TW|en|ja>`.
    static var isOn: Bool { learningLanguage != nil }

    /// Registers the demo for `URLSession.shared` (NativeAPI, images, speech). Call once at launch.
    @MainActor
    static func install() {
        guard isOn else { return }
        _ = URLProtocol.registerClass(DemoBackend.self)
        if UserDefaults.standard.bool(forKey: "uiDemoReset") {
            reset()
        }
    }

    /// Puts the demo first in a session configuration (SupabaseClient builds its own session).
    static func configure(_ cfg: URLSessionConfiguration) {
        guard isOn else { return }
        var classes: [AnyClass] = [DemoBackend.self]
        let mine = ObjectIdentifier(DemoBackend.self)
        for c in cfg.protocolClasses ?? [] where ObjectIdentifier(c) != mine {
            classes.append(c)
        }
        cfg.protocolClasses = classes
    }

    /// Clean start for a test: empty demo data, signed out, no settings kept from an earlier run.
    @MainActor
    static func reset() {
        DemoDatabase.shared.reset()
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
        KeychainStore.delete(account: "supabase.session")
        SupabaseClient.shared.signOut()
    }

    // MARK: - URLProtocol

    private static let queue = DispatchQueue(label: "app.catchwords.demo-backend", qos: .userInitiated, attributes: .concurrent)

    /// Set when the loading system cancels the request; nothing is delivered after that.
    private let flag = DemoStopFlag()

    override class func canInit(with request: URLRequest) -> Bool {
        guard isOn, let scheme = request.url?.scheme?.lowercased() else { return false }
        // Every web request is answered here: the demo never reaches the real internet.
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let req = request
        let body = DemoBackend.bodyData(of: req)
        let flag = self.flag
        let target = DemoProtocolRef(self)
        // A short wait so loading states actually render; pictures come back faster.
        let delay: Double = DemoRouter.isImageRequest(req) ? 0.05 : 0.15
        DemoBackend.queue.asyncAfter(deadline: .now() + delay) {
            let response = DemoRouter.handle(req, body: body)
            if flag.isStopped { return }
            target.value.deliver(response, for: req)
        }
    }

    override func stopLoading() {
        flag.stop()
    }

    fileprivate func deliver(_ response: DemoResponse, for req: URLRequest) {
        guard let url = req.url else { return }
        let headers: [String: String] = [
            "Content-Type": response.contentType,
            "Content-Length": String(response.body.count),
            "Cache-Control": "no-store",
        ]
        guard let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if !response.body.isEmpty {
            client?.urlProtocol(self, didLoad: response.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession hands a protocol the body as a stream; read it whole.
    private static func bodyData(of req: URLRequest) -> Data {
        if let body = req.httpBody { return body }
        guard let stream = req.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            out.append(buffer, count: n)
        }
        return out
    }
}

/// Carries the protocol instance into the delayed answer (URLProtocol calls arrive off the main thread).
nonisolated final class DemoProtocolRef: @unchecked Sendable {
    let value: DemoBackend

    init(_ value: DemoBackend) {
        self.value = value
    }
}

/// A cancel flag shared between a request and its delayed answer.
nonisolated final class DemoStopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

/// One answer of the demo backend.
nonisolated struct DemoResponse {
    var status: Int
    var body: Data
    var contentType: String

    static func json(_ object: Any, status: Int = 200) -> DemoResponse {
        DemoResponse(status: status, body: DJ.data(object), contentType: "application/json")
    }

    static func empty(_ status: Int) -> DemoResponse {
        DemoResponse(status: status, body: Data(), contentType: "application/json")
    }

    /// `{"error": …, "message": …}` — NativeAPI reads `error`, the REST client reads `message`.
    static func error(_ status: Int, _ message: String) -> DemoResponse {
        let body: [String: Any] = ["error": message, "message": message]
        return json(body, status: status)
    }

    static func image(_ data: Data, contentType: String = "image/png") -> DemoResponse {
        DemoResponse(status: 200, body: data, contentType: contentType)
    }

    static func notFound() -> DemoResponse {
        DemoResponse(status: 404, body: Data("Not found".utf8), contentType: "text/plain")
    }
}

/// Picks the part of the demo that answers a request.
nonisolated enum DemoRouter {
    static let supabaseHost: String = (URL(string: AppConfig.supabaseURL)?.host ?? "").lowercased()

    static func handle(_ req: URLRequest, body: Data) -> DemoResponse {
        guard let url = req.url else { return .empty(400) }
        let host = (url.host ?? "").lowercased()
        let method = (req.httpMethod ?? "GET").uppercased()
        let query: [URLQueryItem] = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? []
        let path = url.path
        let db = DemoDatabase.shared

        if host == supabaseHost {
            if path.hasSuffix("/functions/v1/native-fn") {
                let json = DJ.dict(DJ.parse(body))
                let fn = DJ.str(json["fn"]) ?? ""
                return db.callFunction(fn, DJ.dict(json["data"]))
            }
            if path.hasPrefix("/auth/v1/") {
                return db.auth(method: method, path: String(path.dropFirst("/auth/v1/".count)), query: query, body: body)
            }
            if path.hasPrefix("/rest/v1/") {
                let prefer = req.value(forHTTPHeaderField: "Prefer") ?? ""
                return db.rest(method: method, table: String(path.dropFirst("/rest/v1/".count)), query: query, body: body, prefer: prefer)
            }
            if path.hasPrefix("/storage/v1/") {
                return db.storage(method: method, path: String(path.dropFirst("/storage/v1/".count)), body: body)
            }
            return .notFound()
        }
        // Any other host (Unsplash, Wikimedia, demo.invalid…): a made-up picture, never the real internet.
        if host == "demo.invalid" || isImageURL(url) {
            return .image(db.webImage(url: url))
        }
        return .notFound()
    }

    static func isImageRequest(_ req: URLRequest) -> Bool {
        guard let url = req.url else { return false }
        if (url.host ?? "").lowercased() == supabaseHost { return url.path.hasPrefix("/storage/v1/object/") && req.httpMethod != "POST" }
        return isImageURL(url)
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"].contains(ext) { return true }
        let host = (url.host ?? "").lowercased()
        return host.contains("unsplash") || host.contains("wikimedia") || url.path.contains("/img/")
    }
}

/// Small JSON helpers for `[String: Any]` rows (values are Foundation JSON types only).
nonisolated enum DJ {
    static func str(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        return nil
    }

    static func num(_ value: Any?) -> Double? {
        if let s = value as? String { return Double(s) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        guard let d = num(value) else { return nil }
        return Int(d.rounded())
    }

    static func bool(_ value: Any?) -> Bool? {
        if let s = value as? String { return s == "true" }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    static func dict(_ value: Any?) -> [String: Any] {
        if let d = value as? [String: Any] { return d }
        return [:]
    }

    static func list(_ value: Any?) -> [[String: Any]] {
        if let l = value as? [[String: Any]] { return l }
        return []
    }

    static func strings(_ value: Any?) -> [String] {
        if let l = value as? [String] { return l }
        return []
    }

    static func isNull(_ value: Any?) -> Bool {
        guard let value else { return true }
        return value is NSNull
    }

    /// The value, or JSON null.
    static func orNull(_ value: Any?) -> Any {
        if let value { return value }
        return NSNull()
    }

    static func iso(_ date: Date) -> String { SupabaseDate.string(date) }

    static func now() -> String { iso(Date()) }

    static func uuid() -> String { UUID().uuidString.lowercased() }

    /// A local calendar day as YYYY-MM-DD.
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func data(_ object: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return Data("null".utf8) }
        return data
    }

    static func parse(_ data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
#endif
