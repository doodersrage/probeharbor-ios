import Foundation

/// Cookie names the site uses for dashboard sessions (see the web app's lib/auth).
enum SessionCookies {
    static let access = "sb-access-token"
    static let refresh = "sb-refresh-token"
    static let mfa = "sb-mfa-required"
    static let mfaSatisfied = "0"
    static let mfaRequired = "1"

    /// `Cookie:` header for a request; the session is sent like a browser would.
    static func header(for tokens: SessionTokens) -> String {
        var parts = [
            "\(access)=\(tokens.accessToken)",
            "\(refresh)=\(tokens.refreshToken)",
        ]
        if tokens.mfaSatisfied { parts.append("\(mfa)=\(mfaSatisfied)") }
        return parts.joined(separator: "; ")
    }

    /// Applies `Set-Cookie` from a response. The site rotates both tokens when it
    /// refreshes an expired access token, so a response can replace the session.
    /// Returns nil when the response carried no session change.
    static func updated(
        _ current: SessionTokens?,
        responseHeaders: [AnyHashable: Any],
        url: URL
    ) -> SessionTokens? {
        var fields: [String: String] = [:]
        for (key, value) in responseHeaders {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !cookies.isEmpty else { return nil }
        let byName = Dictionary(cookies.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

        let accessValue = byName[access]?.value ?? current?.accessToken
        let refreshValue = byName[refresh]?.value ?? current?.refreshToken
        guard let accessValue, !accessValue.isEmpty, let refreshValue, !refreshValue.isEmpty else {
            return nil
        }
        let mfaSatisfiedValue: Bool
        switch byName[mfa]?.value {
        case mfaSatisfied: mfaSatisfiedValue = true
        case mfaRequired: mfaSatisfiedValue = false
        default: mfaSatisfiedValue = current?.mfaSatisfied ?? false
        }
        let next = SessionTokens(accessToken: accessValue, refreshToken: refreshValue, mfaSatisfied: mfaSatisfiedValue)
        return next == current ? nil : next
    }
}

/// Dashboard settings writes are form POSTs that answer with a 302. Success is a
/// redirect whose Location carries a flag like `alert_saved=1`; anything else is
/// mapped to the message the Android app shows for the same case.
enum FormRedirect {
    static func evaluate(status: Int, location: String, successHints: [String]) -> Result<String, APIError> {
        let isRedirect = (300...399).contains(status)
        if isRedirect, successHints.contains(where: { location.contains($0) }) {
            return .success(location)
        }
        if (200...299).contains(status), successHints.isEmpty {
            return .success(location)
        }
        if location.contains("/signin") { return .failure(.unauthorized) }
        if location.contains("alert_error") || location.contains("prefs_error") {
            return .failure(.message("Server rejected the save"))
        }
        if location.contains("pro_required") || location.contains("error=pro") {
            return .failure(.message("Pro plan required"))
        }
        if location.contains("viewer") || location.contains("manager_required") {
            return .failure(.message("Your household role cannot make this change"))
        }
        if location.contains("editor") || location.contains("forbidden") {
            return .failure(.message("Household editor role required"))
        }
        if location.contains("missing_email") {
            return .failure(.message("Email is required"))
        }
        let suffix = location.isEmpty ? "" : ": \(location)"
        return .failure(.message("Save failed (HTTP \(status)\(suffix))"))
    }

    /// Query value from a redirect Location (e.g. `new_token` after creating a share link).
    static func queryValue(_ name: String, in location: String) -> String? {
        guard let start = location.firstIndex(where: { $0 == "?" }) else { return nil }
        let query = String(location[location.index(after: start)...])
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == name {
                return parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            }
        }
        return nil
    }
}
