import Foundation

/// Where the app talks to — owned by this repository, not injected by a build service.
///
/// (The Rork-generated `Config.swift` held empty strings and was never read; it was removed.)
/// Since 2026-10-20 the app runs on its own Supabase project (catchwords, Tokyo), not on Lovable Cloud:
/// - The Supabase publishable key is meant to be public; every row is protected by RLS (`auth.uid() = user_id`).
/// - No secret (AI keys etc.) may ever be placed here. AI goes through the server functions (`server/` in this
///   repository, deployed as the Edge Function `native-fn`), which hold the keys in Supabase's secrets.
enum AppConfig {
    /// The app's own site (GitHub Pages, built from site/ by scripts/build_site.py): the legal and support pages
    /// and the password-reset page. Not the Lovable web app any more (2026-10-22).
    nonisolated static let webBaseURL = URL(string: "https://catchwords.app")!

    /// The legal pages on the site (texts in site/src). Built from `webBaseURL`, so every link in the
    /// app (sign-in, settings, paywall, AI consent) moves with it. Each carries the display language as `?lang=`
    /// (owner 2026-10-15: under the English UI the pages opened in Japanese — the web falls back to Japanese when
    /// Safari has no stored language; the web now reads `lang=ja|en|zh-TW`).
    nonisolated static var termsURL: URL { legalURL("terms") }
    nonisolated static var privacyURL: URL { legalURL("privacy") }
    /// 特定商取引法に基づく表記, at /legal/tokushoho (site/src/tokushoho.*.html).
    nonisolated static var tokushohoURL: URL { legalURL("legal/tokushoho") }
    /// 設定 › お問い合わせ・サポート. The same page goes into App Store Connect's support URL.
    // サイトの /support（site/src/support.*.html）
    nonisolated static var supportURL: URL { legalURL("support") }
    /// Where the password e-mail's link lands to set a new password (on the same site as the legal pages).
    nonisolated static var passwordResetURL: URL { webBaseURL.appendingPathComponent("reset-password") }

    /// A page of the site with the display language as its `lang` query (`URLComponents`, never pasted strings).
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

    /// Where Supabase hands a Google login back to the app (`catchwords://auth-callback?code=…`, see
    /// `WebAuthSession`). The project's Auth settings allow exactly this redirect.
    nonisolated static let authCallbackScheme = "catchwords"
    nonisolated static let authCallbackHost = "auth-callback"
    nonisolated static var authCallbackURL: String { "\(authCallbackScheme)://\(authCallbackHost)" }
    /// Apple sign-in straight from the device (Supabase `grant_type=id_token`): the system sheet, no web page.
    /// The project's Apple provider lists this app's bundle id. (Off while the app ran on Lovable Cloud, which
    /// did not let the bundle id be registered.)
    nonisolated static let nativeAppleSignIn = true

    /// The app's own Supabase project (catchwords, ap-northeast-1).
    nonisolated static let supabaseURL = "https://libwmvpoqvxfxbjgqnuj.supabase.co"
    nonisolated static let supabasePublishableKey = "sb_publishable_B0BKHxcXGuwdPkErW54uPg_ZEG1NEyc"
    /// The server functions: `server/` in this repository, deployed as the Edge Function `native-fn`
    /// (same `{ fn, data }` contract the web app's `/api/native-fn` had).
    nonisolated static var nativeFunctionURL: URL {
        URL(string: supabaseURL)!.appendingPathComponent("functions/v1/native-fn")
    }
}
