import Foundation

/// Build-time configuration from Info.plist (filled by Config/*.xcconfig).
struct AppConfig: Sendable {
    let baseURL: URL
    let supabaseURL: URL?
    let supabaseAnonKey: String

    /// Bundle ID; also the OAuth callback scheme the server redirects to.
    static let appID = "dev.probeharbor.ios"

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        let base = URL(string: value("PHBaseURL")) ?? URL(string: "https://probeharbor.dev")!
        return AppConfig(
            baseURL: base,
            supabaseURL: URL(string: value("PHSupabaseURL")).flatMap { $0.host == nil ? nil : $0 },
            supabaseAnonKey: value("PHSupabaseAnonKey")
        )
    }()

    var isSupabaseConfigured: Bool { supabaseURL != nil && !supabaseAnonKey.isEmpty }

    func url(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: trimmed, relativeTo: baseURL)!.absoluteURL
    }

    var plansURL: URL { url("/dashboard/plans") }
    var pricingURL: URL { url("/pricing") }
    var devicesSetupURL: URL { url("/dashboard/devices") }

    func shareURL(token: String) -> URL { url("/share/\(token)") }

    func oauthStartURL(provider: String) -> URL {
        var components = URLComponents(url: url("/api/auth/mobile/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            // Tells the server to redirect back to this app's scheme.
            URLQueryItem(name: "app", value: Self.appID),
        ]
        return components.url!
    }
}
