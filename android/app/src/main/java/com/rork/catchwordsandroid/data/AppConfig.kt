package com.rork.catchwordsandroid.data

/**
 * Where the app talks to: the same Supabase project and web server as the iOS app and the web app.
 * The publishable key is the public `anon` role (every row is protected by RLS). No secret may be placed here:
 * AI goes through the web server (`/api/native-fn`), which holds the keys.
 */
object AppConfig {
    const val WEB_BASE_URL = "https://catchwords.lovable.app"
    const val TERMS_URL = "$WEB_BASE_URL/terms"
    const val PRIVACY_URL = "$WEB_BASE_URL/privacy"
    const val TOKUSHOHO_URL = "$WEB_BASE_URL/legal/tokushoho"
    const val SUPPORT_URL = "$WEB_BASE_URL/support"

    const val AUTH_CALLBACK_SCHEME = "catchwords"
    const val AUTH_CALLBACK_HOST = "auth-callback"

    const val SUPABASE_URL = "https://arjicopbmvseztldpxpk.supabase.co"
    const val SUPABASE_KEY =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFyamljb3BibXZzZXp0bGRweHBrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMjUwODQsImV4cCI6MjA5NzcwMTA4NH0.ZzTgNSzT8QWZ2QIeBUVjx_UONYMl-R1Iak9oRAJMknQ"
}
