import AuthenticationServices
import Foundation
import UIKit

struct AuthOutcome: Sendable {
    var needsMfa: Bool
}

/// Sign-in flows: Supabase email/password, site OAuth (Google / GitHub /
/// Discord) through ASWebAuthenticationSession, and site MFA verification.
@MainActor
final class AuthService {
    private let config: AppConfig
    private let store: SessionStoring
    private let api: APIClient
    private let supabase: SupabaseAuth?
    private var oauthSession: ASWebAuthenticationSession?
    private let presentation = PresentationAnchor()

    init(config: AppConfig, store: SessionStoring, api: APIClient) {
        self.config = config
        self.store = store
        self.api = api
        if let url = config.supabaseURL, !config.supabaseAnonKey.isEmpty {
            supabase = SupabaseAuth(url: url, anonKey: config.supabaseAnonKey)
        } else {
            supabase = nil
        }
    }

    var isEmailSignInConfigured: Bool { supabase != nil }
    var isSignedIn: Bool { store.load() != nil }
    var needsMfaToFinish: Bool { store.load().map { !$0.mfaSatisfied } ?? false }

    func signIn(email: String, password: String) async throws -> AuthOutcome {
        let supabase = try requireSupabase()
        let response = try await supabase.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        guard let access = response.accessToken, let refresh = response.refreshToken else {
            throw APIError.message("Sign-in succeeded but no session was returned")
        }
        return try await finish(access: access, refresh: refresh, user: response.user)
    }

    /// Returns true when a session started (no email confirmation required).
    func signUp(email: String, password: String) async throws -> Bool {
        let supabase = try requireSupabase()
        let response = try await supabase.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password)
        guard let access = response.accessToken, let refresh = response.refreshToken else { return false }
        _ = try await finish(access: access, refresh: refresh, user: response.user)
        return true
    }

    func resetPassword(email: String) async throws {
        try await requireSupabase().recover(email: email.trimmingCharacters(in: .whitespaces))
    }

    /// Opens the provider sign-in sheet; the site redirects to
    /// dev.probeharbor.ios://oauth?exchange=… which this session captures.
    func signInWithOAuth(provider: String) async throws -> AuthOutcome {
        let start = config.oauthStartURL(provider: provider)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: start, callbackURLScheme: AppConfig.appID) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? APIError.message("Sign-in was not completed"))
                }
            }
            session.presentationContextProvider = presentation
            session.prefersEphemeralWebBrowserSession = true
            oauthSession = session
            if !session.start() {
                continuation.resume(throwing: APIError.message("Could not open the sign-in page"))
            }
        }
        oauthSession = nil
        guard let exchange = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "exchange" })?.value
        else {
            throw APIError.message("Sign-in did not return to the app")
        }
        return try await exchangeOAuth(token: exchange)
    }

    func exchangeOAuth(token: String) async throws -> AuthOutcome {
        let (payload, _): (TokenPairResponse, Int) = try await api.postJSON(
            "/api/auth/mobile/exchange", body: ["exchange_token": token]
        )
        guard payload.ok == true, let access = payload.accessToken, let refresh = payload.refreshToken else {
            throw APIError.message(payload.error ?? "OAuth exchange failed")
        }
        let user = try? await supabase?.user(accessToken: access)
        return try await finish(access: access, refresh: refresh, user: user)
    }

    /// TOTP code or a YubiKey OTP (44+ characters from a tap).
    func verifyMfa(code: String, yubikeyOTP: String?) async throws {
        var body: [String: Any] = [:]
        if let otp = yubikeyOTP, !otp.isEmpty { body["yubikey_otp"] = otp } else { body["code"] = code }
        let (payload, _): (TokenPairResponse, Int) = try await api.postJSON("/api/auth/mfa-verify", body: body)
        guard payload.ok == true, let access = payload.accessToken, let refresh = payload.refreshToken else {
            throw APIError.message(payload.error ?? "Invalid code")
        }
        store.save(SessionTokens(accessToken: access, refreshToken: refresh, mfaSatisfied: true))
    }

    func signOut() async {
        if let tokens = store.load() {
            await supabase?.signOut(accessToken: tokens.accessToken)
        }
        store.clear()
    }

    var currentEmail: String? { store.load().flatMap { JWT.email($0.accessToken) } }

    // MARK: Private

    private func requireSupabase() throws -> SupabaseAuth {
        guard let supabase else {
            throw APIError.message("Email sign-in isn't configured in this build. Use Google or GitHub, or set Config/Secrets.xcconfig.")
        }
        return supabase
    }

    private func finish(access: String, refresh: String, user: SupabaseUser?) async throws -> AuthOutcome {
        var user = user
        if user?.factors == nil, let supabase {
            user = (try? await supabase.user(accessToken: access)) ?? user
        }
        let needsMfa = MFAPolicy.needsStepUp(accessToken: access, user: user)
        store.save(SessionTokens(accessToken: access, refreshToken: refresh, mfaSatisfied: !needsMfa))
        return AuthOutcome(needsMfa: needsMfa)
    }
}

private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
