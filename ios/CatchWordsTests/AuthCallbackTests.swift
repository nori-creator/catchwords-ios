import XCTest
@testable import CatchWords

/// Google sign-in on the app's own Supabase (2026-10-20): the sign-in URL, the PKCE pair, and reading what
/// Supabase hands back on `catchwords://auth-callback`. Run on its own by ios-check.yml.
final class AuthCallbackTests: XCTestCase {
    func testTheChallengeIsTheRFC7636Example() {
        // RFC 7636 Appendix B.
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testEachVerifierIsNewAndUsesOnlyUnreservedCharacters() {
        let a = PKCE.makeVerifier(), b = PKCE.makeVerifier()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 64)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(a.unicodeScalars.allSatisfy(allowed.contains))
    }

    func testTheSignInURLGoesToOurSupabaseWithTheChallenge() throws {
        let url = try XCTUnwrap(WebAuthSession.authorizeURL(provider: "google", codeChallenge: "abc"))
        XCTAssertEqual(url.host(), URL(string: AppConfig.supabaseURL)?.host())
        XCTAssertEqual(url.path(), "/auth/v1/authorize")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["provider"], "google")
        XCTAssertEqual(items["redirect_to"], "catchwords://auth-callback")
        XCTAssertEqual(items["code_challenge"], "abc")
        XCTAssertEqual(items["code_challenge_method"], "s256")
    }

    func testTheCodeComesBack() {
        XCTAssertEqual(AuthCallback.parse(URL(string: "catchwords://auth-callback?code=xyz")!), .code("xyz"))
    }

    func testAnErrorComesBackInTheQueryOrTheFragment() {
        XCTAssertEqual(AuthCallback.parse(URL(string: "catchwords://auth-callback?error=access_denied&error_description=Denied")!),
                       .error("Denied"))
        XCTAssertEqual(AuthCallback.parse(URL(string: "catchwords://auth-callback#error=server_error")!), .error("server_error"))
    }

    func testOtherURLsAreNotACallback() {
        XCTAssertNil(AuthCallback.parse(URL(string: "catchwords://other?code=xyz")!))
        XCTAssertNil(AuthCallback.parse(URL(string: "https://auth-callback?code=xyz")!))
        XCTAssertNil(AuthCallback.parse(URL(string: "catchwords://auth-callback")!))
    }

    func testTheServerFunctionsAreOnOurSupabase() {
        XCTAssertEqual(AppConfig.nativeFunctionURL.absoluteString,
                       "https://libwmvpoqvxfxbjgqnuj.supabase.co/functions/v1/native-fn")
    }
}
