import Foundation

/// Typed calls for every endpoint and dashboard form the Android app uses.
struct ProbeHarborAPI: Sendable {
    let client: APIClient

    // MARK: Readings & home

    func homeReadings(space: String? = nil) async throws -> HomeReadingsResponse {
        var query = [URLQueryItem(name: "save", value: "0")]
        if let space { query.append(URLQueryItem(name: "space", value: space)) }
        return try await client.get("/api/home/readings", query: query)
    }

    func homeInsights() async throws -> HomeInsightsResponse { try await client.get("/api/user/home-insights") }
    func doorEvents() async throws -> DoorEventsResponse { try await client.get("/api/user/door-events") }
    func ingestStatus() async throws -> IngestStatusResponse { try await client.get("/api/devices/ingest-status") }
    func thermostat() async throws -> ThermostatStatusResponse { try await client.get("/api/integrations/thermostat") }
    func portfolio() async throws -> PortfolioResponse { try await client.get("/api/user/portfolio") }
    func referral() async throws -> ReferralResponse { try await client.get("/api/user/referral") }
    func export() async throws -> UserExportResponse { try await client.get("/api/user/export") }

    func weather(cityId: String?) async throws -> WeatherResponse {
        try await client.get("/api/home/weather", query: cityId.map { [URLQueryItem(name: "cityId", value: $0)] } ?? [])
    }

    func history(days: Int, probe: String? = nil) async throws -> HistoryResponse {
        var query = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "include", value: "chart,readings,house_overlay"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
        ]
        if let probe { query.append(URLQueryItem(name: "probe", value: probe)) }
        return try await client.get("/api/user/history", query: query)
    }

    // MARK: Alerts

    func alertEvents(limit: Int = 30) async throws -> AlertEventsResponse {
        try await client.get("/api/user/alert-events", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func acknowledge(eventId: Int64) async throws {
        let (body, status): (OkResponse, Int) = try await client.postJSON(
            "/api/user/alert-events/ack", body: ["event_id": eventId]
        )
        guard (200...299).contains(status) else {
            throw APIError.message(body.error ?? "Ack failed (HTTP \(status))")
        }
    }

    func sendTestAlert() async throws -> String {
        let (body, status): (TestAlertResponse, Int) = try await client.postJSON("/api/user/alert-test", body: [:])
        if status == 403 { throw APIError.forbidden("Editor role required to send a test") }
        guard body.ok == true else { throw APIError.message(body.error ?? "Test failed (HTTP \(status))") }
        let sent = (body.sent ?? []).joined(separator: ", ")
        return "Test sent via \(sent.isEmpty ? "ok" : sent)"
    }

    func saveAlertSettings(_ settings: AlertSettings) async throws {
        try await client.postForm("/api/user/alert-settings", fields: settings.formFields, successHints: ["alert_saved=1"])
    }

    /// action: snooze | vacation | clear_snooze | clear_vacation
    func snooze(action: String, hours: Int? = nil, days: Int? = nil) async throws {
        var fields: [(String, String)] = [("redirect", "/dashboard/alerts"), ("action", action)]
        if let hours { fields.append(("hours", String(hours))) }
        if let days { fields.append(("days", String(days))) }
        try await client.postForm(
            "/api/user/alert-snooze",
            fields: fields,
            successHints: ["snooze=1", "vacation=1", "snooze_cleared=1", "vacation_cleared=1"]
        )
    }

    // MARK: Account

    func savePreferences(_ prefs: UserPreferences) async throws {
        try await client.postForm("/api/user/preferences", fields: prefs.formFields, successHints: ["prefs_saved=1"])
    }

    func registerPushToken(_ token: String) async throws {
        let (body, status): (OkResponse, Int) = try await client.postJSON(
            "/api/push/fcm", body: ["token": token, "platform": "ios", "appId": AppConfig.appID]
        )
        if status == 403 { throw APIError.forbidden("Pro plan required for push") }
        guard (200...299).contains(status) else {
            throw APIError.message(body.error ?? "Push registration failed (HTTP \(status))")
        }
    }

    func unregisterPushToken(_ token: String) async {
        let _: (OkResponse, Int)? = try? await client.postJSON("/api/push/fcm", body: ["token": token], method: "DELETE")
    }

    // MARK: Devices

    func renameDevice(id: String, name: String) async throws {
        try await client.postForm("/api/devices", fields: [
            ("redirect", "/dashboard/temperature"), ("action", "rename"),
            ("device_id", id), ("name", name.trimmingCharacters(in: .whitespaces)),
        ], successHints: ["device_renamed=1"])
    }

    func setDeviceSpace(id: String, space: String) async throws {
        try await client.postForm("/api/devices", fields: [
            ("redirect", "/dashboard/temperature"), ("action", "set_space"),
            ("device_id", id), ("space", space.trimmingCharacters(in: .whitespaces)),
        ], successHints: ["device_renamed=1"])
    }

    // MARK: Household

    func household() async throws -> HouseholdResponse { try await client.get("/api/household") }

    func renameHousehold(_ name: String) async throws {
        try await client.postForm("/api/household", fields: [
            ("redirect", "/dashboard/household"), ("action", "rename"), ("name", name.trimmingCharacters(in: .whitespaces)),
        ], successHints: ["saved=1"])
    }

    func invite(email: String, role: String) async throws {
        try await client.postForm("/api/household", fields: [
            ("redirect", "/dashboard/household"), ("action", "invite"),
            ("email", email.trimmingCharacters(in: .whitespaces)), ("role", role),
        ], successHints: ["invited=1"])
    }

    func switchHousehold(_ id: String) async throws {
        try await client.postForm("/api/household", fields: [
            ("redirect", "/dashboard/household"), ("action", "switch"), ("household_id", id),
        ], successHints: ["switched=1"])
    }

    // MARK: Share links

    func shareLinks() async throws -> [ShareLinkInfo] {
        let response: ShareLinksResponse = try await client.get("/api/share/manage")
        return response.links ?? []
    }

    /// Returns the new token when the redirect carries it.
    func createShareLink(label: String, scope: String, expiresDays: Int) async throws -> String? {
        let location = try await client.postForm("/api/share/manage", fields: [
            ("redirect", "/dashboard/share"), ("action", "create"),
            ("label", label.trimmingCharacters(in: .whitespaces)), ("scope", scope),
            ("expires_days", String(expiresDays)),
        ], successHints: ["created=1"])
        return FormRedirect.queryValue("new_token", in: location)
    }

    func revokeShareLink(id: String) async throws {
        try await client.postForm("/api/share/manage", fields: [
            ("redirect", "/dashboard/share"), ("action", "revoke"), ("id", id),
        ], successHints: ["revoked=1"])
    }

    // MARK: Claims pack

    /// HTML claims pack for the last `days` days, saved to a temp file for sharing.
    func downloadClaimsPack(days: Int) async throws -> URL {
        let (from, to) = Self.claimsRange(days: days)
        let data = try await client.data("/api/claims/pack", query: [
            URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "format", value: "html"),
        ])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("probeharbor-claims-\(from)-to-\(to).html")
        try data.write(to: url, options: .atomic)
        return url
    }

    func emailClaimsPack(adjusterEmail: String, days: Int) async throws -> String? {
        let (from, to) = Self.claimsRange(days: days)
        let (body, status): (ClaimsEmailResponse, Int) = try await client.postJSON("/api/claims/email", body: [
            "adjuster_email": adjusterEmail, "from": from, "to": to,
        ])
        guard body.ok == true else { throw APIError.message(body.error ?? "Email failed (HTTP \(status))") }
        return body.verifyUrl
    }

    /// UTC calendar range ending today, matching the Android app.
    static func claimsRange(days: Int, now: Date = Date()) -> (String, String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let to = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -max(days - 1, 0), to: to)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: from), formatter.string(from: to))
    }
}
