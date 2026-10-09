import XCTest
@testable import ProbeHarbor

final class SessionAndAuthTests: XCTestCase {
    private let url = URL(string: "https://probeharbor.dev/api/home/readings")!
    private let tokens = SessionTokens(accessToken: "a1", refreshToken: "r1", mfaSatisfied: false)

    func testCookieHeaderIncludesMfaOnlyWhenSatisfied() {
        XCTAssertEqual(SessionCookies.header(for: tokens), "sb-access-token=a1; sb-refresh-token=r1")
        var satisfied = tokens
        satisfied.mfaSatisfied = true
        XCTAssertEqual(SessionCookies.header(for: satisfied), "sb-access-token=a1; sb-refresh-token=r1; sb-mfa-required=0")
    }

    func testRotatedTokensFromSetCookieReplaceTheSession() {
        let headers: [AnyHashable: Any] = [
            "Set-Cookie": "sb-access-token=a2; Path=/; HttpOnly; Secure, sb-refresh-token=r2; Path=/; HttpOnly; Secure",
        ]
        let next = SessionCookies.updated(tokens, responseHeaders: headers, url: url)
        XCTAssertEqual(next, SessionTokens(accessToken: "a2", refreshToken: "r2", mfaSatisfied: false))
    }

    func testMfaCookieMarksSessionSatisfied() {
        let headers: [AnyHashable: Any] = ["Set-Cookie": "sb-mfa-required=0; Path=/"]
        XCTAssertEqual(SessionCookies.updated(tokens, responseHeaders: headers, url: url)?.mfaSatisfied, true)
    }

    func testResponsesWithoutSessionCookiesChangeNothing() {
        XCTAssertNil(SessionCookies.updated(tokens, responseHeaders: ["Content-Type": "application/json"], url: url))
        let unrelated: [AnyHashable: Any] = ["Set-Cookie": "theme=dark; Path=/"]
        XCTAssertNil(SessionCookies.updated(tokens, responseHeaders: unrelated, url: url))
    }

    func testFormRedirectSuccessAndErrors() {
        XCTAssertNoThrow(try FormRedirect.evaluate(status: 302, location: "/dashboard/alerts?alert_saved=1", successHints: ["alert_saved=1"]).get())
        XCTAssertEqual(
            FormRedirect.evaluate(status: 302, location: "/signin?next=/dashboard", successHints: ["alert_saved=1"]),
            .failure(.unauthorized)
        )
        XCTAssertEqual(
            FormRedirect.evaluate(status: 302, location: "/dashboard/share?error=pro_required", successHints: ["created=1"]),
            .failure(.message("Pro plan required"))
        )
        XCTAssertEqual(
            FormRedirect.evaluate(status: 500, location: "", successHints: ["saved=1"]),
            .failure(.message("Save failed (HTTP 500)"))
        )
    }

    func testShareTokenReadFromRedirect() {
        XCTAssertEqual(FormRedirect.queryValue("new_token", in: "/dashboard/share?created=1&new_token=ab%2Bc"), "ab+c")
        XCTAssertNil(FormRedirect.queryValue("new_token", in: "/dashboard/share?created=1"))
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(APIClient.formEncode([("label", "Mom & Dad"), ("email", "a+b@x.io")]), "label=Mom+%26+Dad&email=a%2Bb%40x.io")
    }

    func testMfaPolicyMatchesAndroid() {
        let aal1 = jwt(["aal": "aal1", "email": "me@example.com"])
        let aal2 = jwt(["aal": "aal2"])
        let totp = SupabaseUser(email: nil, factors: [.init(status: "verified", factorType: "totp")], userMetadata: nil)
        let yubikey = SupabaseUser(email: nil, factors: [], userMetadata: .init(yubikeyOtpPublicIds: ["cccc"]))
        let plain = SupabaseUser(email: nil, factors: [.init(status: "unverified", factorType: "totp")], userMetadata: nil)

        XCTAssertTrue(MFAPolicy.needsStepUp(accessToken: aal1, user: totp))
        XCTAssertTrue(MFAPolicy.needsStepUp(accessToken: aal1, user: yubikey))
        XCTAssertFalse(MFAPolicy.needsStepUp(accessToken: aal1, user: plain))
        XCTAssertFalse(MFAPolicy.needsStepUp(accessToken: aal2, user: totp))
        XCTAssertEqual(JWT.email(aal1), "me@example.com")
    }

    func testOAuthStartURLNamesTheIOSApp() {
        let config = AppConfig(baseURL: URL(string: "https://probeharbor.dev")!, supabaseURL: nil, supabaseAnonKey: "")
        XCTAssertEqual(
            config.oauthStartURL(provider: "google").absoluteString,
            "https://probeharbor.dev/api/auth/mobile/start?provider=google&app=dev.probeharbor.ios"
        )
        XCTAssertEqual(config.shareURL(token: "t1").absoluteString, "https://probeharbor.dev/share/t1")
    }

    private func jwt(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJIUzI1NiJ9.\(payload).sig"
    }
}
