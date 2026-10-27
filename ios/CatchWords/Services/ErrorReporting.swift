import Foundation
import Sentry

/// Crashes and failures from learners' phones, sent to Sentry (owner 2026-10-27: 「どの機種の、どの画面の、何行目の
/// コードで落ちたか」 — most of what breaks on a phone never breaks on the developer's). Project `catchwords-ios`.
///
/// What is sent: crashes, app hangs, a server answer of 500–599, and the failures `DevLog` keeps (a save that failed,
/// an answer the app could not read, a sign-in that failed). With each, the model, iOS, app version and the last few
/// steps (breadcrumbs). What is never sent: screenshots, the view hierarchy, session replays (a learner's photos are on
/// the screen), the account, IP address or e-mail (`sendDefaultPii` off), request bodies, and the query part of a URL.
///
/// Only release builds (TestFlight, App Store) report: debug builds, unit tests, UI tests and the CI's screen previews
/// never start it, so the free plan's 5,000 events a month go to real failures.
///
/// `nonisolated`: Sentry calls `beforeSend` / `beforeBreadcrumb` on its own threads, so the closures must not take
/// the app's default main-actor isolation.
nonisolated enum ErrorReporting {
    /// The DSN of `catchwords-ios` — only an address to send to (Sentry: safe to ship in an app), never a secret.
    static let dsn = "https://82d921ffab5cc0d8874b292fb086bac8@o4512328596520960.ingest.us.sentry.io/4512328615854080"

    /// The `DevLog` areas that are failures. The others (tags, cutout, example, upload, network) are notes on what the
    /// app did instead, not something that went wrong for the learner.
    static let reportedAreas: Set<String> = ["save", "decode", "auth", "encounter"]

    nonisolated(unsafe) private static var started = false

    static func start() {
        #if DEBUG
        return
        #else
        guard !started else { return }
        started = true
        SentrySDK.start { o in
            o.dsn = dsn
            o.environment = installSource
            o.sendDefaultPii = false
            o.attachScreenshot = false
            o.attachViewHierarchy = false
            o.sessionReplay.sessionSampleRate = 0
            o.sessionReplay.onErrorSampleRate = 0
            // Errors only: no performance tracing (it would spend the free plan's quota and adds nothing yet).
            o.tracesSampleRate = nil
            o.beforeSend = { event in
                if let r = event.request {
                    r.queryString = nil
                    r.cookies = nil
                    r.headers = nil
                    r.url = r.url.map(Self.withoutQuery)
                }
                return event
            }
            o.beforeBreadcrumb = { crumb in
                if var data = crumb.data, let url = data["url"] as? String {
                    data["url"] = Self.withoutQuery(url)
                    crumb.data = data
                }
                return crumb
            }
        }
        #endif
    }

    /// A failure `DevLog` kept (`DevLog.add`), as a warning in Sentry with its area as a tag.
    static func devLog(area: String, text: String) {
        guard started, reportedAreas.contains(area), !text.contains("saved on a retry") else { return }
        SentrySDK.capture(message: "[\(area)] \(text)") { scope in
            scope.setLevel(.warning)
            scope.setTag(value: area, key: "area")
        }
    }

    /// 設定 › 開発者 › アプリの情報 › 「Sentry にテスト送信」: one message, to see that reports arrive. False when this build
    /// does not report (a debug build).
    @discardableResult
    static func sendTest() -> Bool {
        guard started else { return false }
        SentrySDK.capture(message: "Test from Settings › Developer › App info") { scope in
            scope.setLevel(.info)
            scope.setTag(value: "test", key: "area")
        }
        return true
    }

    /// Whether this build reports to Sentry (release builds only).
    static var isOn: Bool { started }

    /// "testflight" / "production": TestFlight builds carry a sandbox receipt.
    private static var installSource: String {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "production"
    }

    /// The URL without `?…` and `#…` (a search word or an id may ride in the query).
    static func withoutQuery(_ url: String) -> String {
        String(url.prefix { $0 != "?" && $0 != "#" })
    }
}
