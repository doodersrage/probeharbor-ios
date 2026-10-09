import Foundation

/// Minimal Supabase Auth (GoTrue) REST client: the four calls the app needs.
/// OAuth and MFA verification go through the ProbeHarbor site instead.
struct SupabaseAuth: Sendable {
    let url: URL
    let anonKey: String
    var session: URLSession = .shared

    struct TokenResponse: Decodable, Sendable {
        var accessToken: String?
        var refreshToken: String?
        var user: SupabaseUser?

        enum CodingKeys: String, CodingKey {
            case user
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    func signIn(email: String, password: String) async throws -> TokenResponse {
        try await post("token?grant_type=password", body: ["email": email, "password": password])
    }

    /// Returns a session only when the project skips email confirmation.
    func signUp(email: String, password: String) async throws -> TokenResponse {
        try await post("signup", body: ["email": email, "password": password])
    }

    func recover(email: String) async throws {
        let _: Empty = try await post("recover", body: ["email": email])
    }

    func user(accessToken: String) async throws -> SupabaseUser {
        var request = URLRequest(url: endpoint("user"))
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func signOut(accessToken: String) async {
        var request = URLRequest(url: endpoint("logout"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    // MARK: Plumbing

    private struct Empty: Decodable {}

    private func endpoint(_ path: String) -> URL {
        URL(string: "auth/v1/\(path)", relativeTo: url.appendingPathComponent(""))!.absoluteURL
    }

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw APIError.message(Self.errorMessage(data) ?? "Authentication failed (HTTP \(status))")
        }
        if data.isEmpty, let empty = Empty() as? T { return empty }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// GoTrue error bodies use `msg`, `error_description`, or `message`.
    static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["msg"] as? String)
            ?? (object["error_description"] as? String)
            ?? (object["message"] as? String)
            ?? (object["error"] as? String)
    }
}

struct SupabaseUser: Decodable, Sendable {
    var email: String?
    var factors: [Factor]?
    var userMetadata: Metadata?

    struct Factor: Decodable, Sendable {
        var status: String?
        var factorType: String?

        enum CodingKeys: String, CodingKey {
            case status
            case factorType = "factor_type"
        }
    }

    struct Metadata: Decodable, Sendable {
        var yubikeyOtpPublicIds: [String]?

        enum CodingKeys: String, CodingKey {
            case yubikeyOtpPublicIds = "yubikey_otp_public_ids"
        }
    }

    enum CodingKeys: String, CodingKey {
        case email, factors
        case userMetadata = "user_metadata"
    }

    var hasVerifiedFactor: Bool { (factors ?? []).contains { $0.status == "verified" } }
    var hasYubiKeyOTP: Bool { !(userMetadata?.yubikeyOtpPublicIds ?? []).isEmpty }
}

enum JWT {
    /// Claims payload of a JWT without verifying it (the server verifies).
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func assuranceLevel(_ token: String) -> String? { claims(token)?["aal"] as? String }
    static func email(_ token: String) -> String? { claims(token)?["email"] as? String }
}

enum MFAPolicy {
    /// Same rule as the Android app: step up when the session is below aal2 and
    /// the account has a verified MFA factor or an enrolled YubiKey OTP.
    static func needsStepUp(accessToken: String, user: SupabaseUser?) -> Bool {
        if JWT.assuranceLevel(accessToken) == "aal2" { return false }
        guard let user else { return false }
        return user.hasVerifiedFactor || user.hasYubiKeyOTP
    }
}
