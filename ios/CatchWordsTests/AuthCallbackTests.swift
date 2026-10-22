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

    // Google straight with Google (`GoogleSignIn`, 2026-10-22).
    private let googleID = "123-abc.apps.googleusercontent.com"

    func testGoogleSendsTheIOSClientBackToItsReversedID() {
        XCTAssertEqual(GoogleSignIn.redirectScheme(clientID: googleID), "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(GoogleSignIn.redirectURI(clientID: googleID), "com.googleusercontent.apps.123-abc:/oauth2redirect")
        XCTAssertNil(GoogleSignIn.redirectScheme(clientID: "not-a-client-id"))
        XCTAssertNil(GoogleSignIn.redirectScheme(clientID: ".apps.googleusercontent.com"))
    }

    func testTheGoogleSignInURL() throws {
        let url = try XCTUnwrap(GoogleSignIn.authorizeURL(clientID: googleID, codeChallenge: "abc", hashedNonce: "n1"))
        XCTAssertEqual(url.host(), "accounts.google.com")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], googleID)
        XCTAssertEqual(items["redirect_uri"], "com.googleusercontent.apps.123-abc:/oauth2redirect")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["scope"], "openid email profile")
        XCTAssertEqual(items["code_challenge"], "abc")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["nonce"], "n1")
    }

    func testWhatGoogleHandsBack() {
        XCTAssertEqual(GoogleSignIn.parse(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=4/xy&scope=email")!,
                                          clientID: googleID), .code("4/xy"))
        XCTAssertEqual(GoogleSignIn.parse(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?error=access_denied")!,
                                          clientID: googleID), .error("access_denied"))
        XCTAssertNil(GoogleSignIn.parse(URL(string: "catchwords://auth-callback?code=xyz")!, clientID: googleID))
    }

    func testTheGoogleTokenFormKeepsPlusSigns() throws {
        let body = try XCTUnwrap(GoogleSignIn.tokenRequestBody(code: "4/a+b", verifier: "v", clientID: googleID))
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("grant_type=authorization_code"))
        XCTAssertTrue(text.contains("code=4/a%2Bb"))
        XCTAssertTrue(text.contains("client_id=\(googleID)"))
        XCTAssertFalse(text.contains("client_secret"))
    }

    func testTheNonceGoesToGoogleHashed() {
        // SHA-256 of "abc", hex (FIPS 180-2 example): what Supabase compares the token's nonce with.
        XCTAssertEqual(GoogleSignIn.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testTheServerFunctionsAreOnOurSupabase() {
        XCTAssertEqual(AppConfig.nativeFunctionURL.absoluteString,
                       "https://libwmvpoqvxfxbjgqnuj.supabase.co/functions/v1/native-fn")
    }
}
