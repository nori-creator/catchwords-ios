import Foundation

/// Where the app talks to — owned by this repository, not injected by a build service.
///
/// (The Rork-generated `Config.swift` held empty strings and was never read; it was removed.)
/// These values are the same ones the Lovable web app ships in its public bundle:
/// - The Supabase publishable key is the `anon` role. It is meant to be public;
///   every row is protected by RLS (`auth.uid() = user_id`).
/// - No secret (AI keys etc.) may ever be placed here. AI goes through the web
///   server (`/api/native-fn`), which holds the keys.
enum AppConfig {
    /// The published Lovable web app. Its server hosts `/api/native-fn`.
    nonisolated static let webBaseURL = URL(string: "https://catchwords.lovable.app")!

    /// The legal pages on the web app (texts in docs/legal). Built from `webBaseURL`, so every link in the
    /// app (sign-in, settings, paywall, AI consent) moves with it. Each carries the display language as `?lang=`
    /// (owner 2026-10-15: under the English UI the pages opened in Japanese — the web falls back to Japanese when
    /// Safari has no stored language; the web now reads `lang=ja|en|zh-TW`).
    nonisolated static var termsURL: URL { legalURL("terms") }
    nonisolated static var privacyURL: URL { legalURL("privacy") }
    /// 特定商取引法に基づく表記. The web app serves it at /legal/tokushoho (src/components/legal/TokushohoDocument.tsx).
    nonisolated static var tokushohoURL: URL { legalURL("legal/tokushoho") }
    /// 設定 › お問い合わせ・サポート. The same page goes into App Store Connect's support URL.
    // Web の /support（docs/web-changes/ の 0001〈旧 docs/legal/web/legal.patch〉で足す頁。連絡先は LEGAL_EMAIL から出る）
    nonisolated static var supportURL: URL { legalURL("support") }

    /// A page of the web app with the display language as its `lang` query (`URLComponents`, never pasted strings).
    /// `lang` defaults to the app's display language (`L10n.lang`, the web's own codes); a language the web has no
    /// pages in (languages.json `legalDocs`) opens the English ones.
    nonisolated static func legalURL(_ path: String, lang: String? = nil) -> URL {
        var parts = URLComponents(url: webBaseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.path = "/" + path.split(separator: "/").joined(separator: "/")
        let code = L10n.normalize(lang ?? L10n.lang)
        parts.queryItems = [URLQueryItem(name: "lang", value: L10n.language(code).legalDocs ? code : DisplayLanguages.fallback)]
        return parts.url ?? webBaseURL.appendingPathComponent(path)
    }
    /// Apple's page for the subscriptions of the signed-in Apple ID (cancel there).
    nonisolated static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// Where the web's `/native-auth` bridge hands a Google / Apple login back to the app
    /// (`catchwords://auth-callback#…`, see `WebAuthSession`).
    nonisolated static let authCallbackScheme = "catchwords"
    nonisolated static let authCallbackHost = "auth-callback"
    /// Apple sign-in straight from the device (Supabase `grant_type=id_token`). Off: it needs the app's
    /// bundle id registered on the auth server, which Lovable Cloud does not expose, and a native Apple
    /// login gets a different Apple user id than the web's, so the same person would end up with two
    /// accounts. Apple goes through the web bridge like Google.
    nonisolated static let nativeAppleSignIn = false

    nonisolated static let supabaseURL = "https://arjicopbmvseztldpxpk.supabase.co"
    nonisolated static let supabasePublishableKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFyamljb3BibXZzZXp0bGRweHBrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMjUwODQsImV4cCI6MjA5NzcwMTA4NH0.ZzTgNSzT8QWZ2QIeBUVjx_UONYMl-R1Iak9oRAJMknQ"
}
