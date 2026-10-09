import Foundation

// GET /api/user/export

struct UserExportResponse: Decodable, Sendable {
    var user: ExportUser?
    var preferences: UserPreferences?
    var alertSettings: AlertSettings?
    var entitlements: Entitlements?

    enum CodingKeys: String, CodingKey {
        case user, preferences, entitlements
        case alertSettings = "alert_settings"
    }
}

struct ExportUser: Decodable, Sendable {
    var id: String?
    var email: String?
}

struct Entitlements: Decodable, Sendable {
    var tier: String?
    var canUseClaimsPack: Bool?
    var canCreateShareLinks: Bool?
    var canUsePush: Bool?
    var historyDays: Int?
}

struct UserPreferences: Decodable, Equatable, Sendable {
    var showGarageTemps = true
    var showWeather = true
    var weatherCityId: String?
    var useCelsius = false
    var theme = "dark"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showGarageTemps = try c.decodeIfPresent(Bool.self, forKey: .showGarageTemps) ?? true
        showWeather = try c.decodeIfPresent(Bool.self, forKey: .showWeather) ?? true
        weatherCityId = try c.decodeIfPresent(String.self, forKey: .weatherCityId)
        useCelsius = try c.decodeIfPresent(Bool.self, forKey: .useCelsius) ?? false
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
    }

    enum CodingKeys: String, CodingKey {
        case showGarageTemps, showWeather, weatherCityId, useCelsius, theme
    }

    /// Fields for POST /api/user/preferences (checkboxes are "on" when set).
    var formFields: [(String, String)] {
        var fields: [(String, String)] = [
            ("redirect", "/dashboard/settings"),
            ("theme", theme.isEmpty ? "dark" : theme),
        ]
        if showGarageTemps { fields.append(("show_garage_temps", "on")) }
        if showWeather { fields.append(("show_weather", "on")) }
        if useCelsius { fields.append(("use_celsius", "on")) }
        if let city = weatherCityId, !city.isEmpty { fields.append(("weather_city_id", city)) }
        return fields
    }
}

/// Alert settings as the export returns them (camelCase). Posted back as the
/// same form the web Alerts page submits.
struct AlertSettings: Decodable, Equatable, Sendable {
    var enabled = false
    var digestEnabled = false
    var freezeThresholdF = 34.0
    var humidityThreshold = 75.0
    var rateChangeF = 15.0
    var outageHours = 2.0
    var email: String?
    var channelEmail = true
    var channelSms = false
    var channelDiscord = false
    var channelPush = false
    var channelWebhook = false
    var channelTelegram = false
    var channelSlack = false
    var channelTeams = false
    var channelNtfy = false
    var channelPushover = false
    var channelWhatsapp = false
    var discordWebhookUrl: String?
    var slackWebhookUrl: String?
    var telegramBotToken: String?
    var telegramChatId: String?
    var forecastFreezeEnabled = false
    var nwsFreezeAlertsEnabled = false
    var forecastHoursAhead = 12.0
    var quietHoursEnabled = false
    var quietHoursStart = "22:00"
    var quietHoursEnd = "07:00"
    var quietHoursTimezone = "America/New_York"
    var quietHoursBypassFreeze = true
    var quietHoursSmsCritical = false
    var monthlyReportEnabled = false
    var quarterlyReportEnabled = false
    var dripEmailsEnabled = false
    var batteryAlertsEnabled = false
    var batteryTrendAlertsEnabled = false
    var batteryThresholdPct = 20.0
    var rssiAlertsEnabled = false
    var rssiThreshold = -90.0
    var escalationEnabled = false
    var escalationMinutes = 60.0
    var feedUptimeAlertsEnabled = false
    var portfolioAlertsEnabled = false
    var snoozeUntil: String?
    var vacationUntil: String?
    var ntfyTopic: String?
    var ntfyServer = "https://ntfy.sh"
    var smsPhone: String?
    var whatsappPhone: String?
    var outboundWebhookUrl: String?
    var readingWebhookUrl: String?

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, digestEnabled, freezeThresholdF, humidityThreshold, rateChangeF, outageHours, email
        case channelEmail, channelSms, channelDiscord, channelPush, channelWebhook, channelTelegram
        case channelSlack, channelTeams, channelNtfy, channelPushover, channelWhatsapp
        case discordWebhookUrl, slackWebhookUrl, telegramBotToken, telegramChatId
        case forecastFreezeEnabled, nwsFreezeAlertsEnabled, forecastHoursAhead
        case quietHoursEnabled, quietHoursStart, quietHoursEnd, quietHoursTimezone
        case quietHoursBypassFreeze, quietHoursSmsCritical
        case monthlyReportEnabled, quarterlyReportEnabled, dripEmailsEnabled
        case batteryAlertsEnabled, batteryTrendAlertsEnabled, batteryThresholdPct
        case rssiAlertsEnabled, rssiThreshold, escalationEnabled, escalationMinutes
        case feedUptimeAlertsEnabled, portfolioAlertsEnabled, snoozeUntil, vacationUntil
        case ntfyTopic, ntfyServer, smsPhone, whatsappPhone, outboundWebhookUrl, readingWebhookUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func bool(_ key: CodingKeys, _ fallback: Bool) throws -> Bool {
            try c.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }
        func num(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        func str(_ key: CodingKeys) throws -> String? {
            try c.decodeIfPresent(String.self, forKey: key)
        }
        enabled = try bool(.enabled, false)
        digestEnabled = try bool(.digestEnabled, false)
        freezeThresholdF = try num(.freezeThresholdF, 34)
        humidityThreshold = try num(.humidityThreshold, 75)
        rateChangeF = try num(.rateChangeF, 15)
        outageHours = try num(.outageHours, 2)
        email = try str(.email)
        channelEmail = try bool(.channelEmail, true)
        channelSms = try bool(.channelSms, false)
        channelDiscord = try bool(.channelDiscord, false)
        channelPush = try bool(.channelPush, false)
        channelWebhook = try bool(.channelWebhook, false)
        channelTelegram = try bool(.channelTelegram, false)
        channelSlack = try bool(.channelSlack, false)
        channelTeams = try bool(.channelTeams, false)
        channelNtfy = try bool(.channelNtfy, false)
        channelPushover = try bool(.channelPushover, false)
        channelWhatsapp = try bool(.channelWhatsapp, false)
        discordWebhookUrl = try str(.discordWebhookUrl)
        slackWebhookUrl = try str(.slackWebhookUrl)
        telegramBotToken = try str(.telegramBotToken)
        telegramChatId = try str(.telegramChatId)
        forecastFreezeEnabled = try bool(.forecastFreezeEnabled, false)
        nwsFreezeAlertsEnabled = try bool(.nwsFreezeAlertsEnabled, false)
        forecastHoursAhead = try num(.forecastHoursAhead, 12)
        quietHoursEnabled = try bool(.quietHoursEnabled, false)
        quietHoursStart = try str(.quietHoursStart) ?? "22:00"
        quietHoursEnd = try str(.quietHoursEnd) ?? "07:00"
        quietHoursTimezone = try str(.quietHoursTimezone) ?? "America/New_York"
        quietHoursBypassFreeze = try bool(.quietHoursBypassFreeze, true)
        quietHoursSmsCritical = try bool(.quietHoursSmsCritical, false)
        monthlyReportEnabled = try bool(.monthlyReportEnabled, false)
        quarterlyReportEnabled = try bool(.quarterlyReportEnabled, false)
        dripEmailsEnabled = try bool(.dripEmailsEnabled, false)
        batteryAlertsEnabled = try bool(.batteryAlertsEnabled, false)
        batteryTrendAlertsEnabled = try bool(.batteryTrendAlertsEnabled, false)
        batteryThresholdPct = try num(.batteryThresholdPct, 20)
        rssiAlertsEnabled = try bool(.rssiAlertsEnabled, false)
        rssiThreshold = try num(.rssiThreshold, -90)
        escalationEnabled = try bool(.escalationEnabled, false)
        escalationMinutes = try num(.escalationMinutes, 60)
        feedUptimeAlertsEnabled = try bool(.feedUptimeAlertsEnabled, false)
        portfolioAlertsEnabled = try bool(.portfolioAlertsEnabled, false)
        snoozeUntil = try str(.snoozeUntil)
        vacationUntil = try str(.vacationUntil)
        ntfyTopic = try str(.ntfyTopic)
        ntfyServer = try str(.ntfyServer) ?? "https://ntfy.sh"
        smsPhone = try str(.smsPhone)
        whatsappPhone = try str(.whatsappPhone)
        outboundWebhookUrl = try str(.outboundWebhookUrl)
        readingWebhookUrl = try str(.readingWebhookUrl)
    }

    /// Fields for POST /api/user/alert-settings. Checkboxes are sent as "true"
    /// only when on; the server treats a missing key as off.
    var formFields: [(String, String)] {
        var fields: [(String, String)] = [("redirect", "/dashboard/alerts")]
        func check(_ name: String, _ on: Bool) { if on { fields.append((name, "true")) } }
        func value(_ name: String, _ v: Double) { fields.append((name, Self.number(v))) }
        func optional(_ name: String, _ v: String?) { if let v { fields.append((name, v)) } }

        check("alerts_enabled", enabled)
        check("digest_enabled", digestEnabled)
        check("monthly_report_enabled", monthlyReportEnabled)
        check("quarterly_report_enabled", quarterlyReportEnabled)
        check("drip_emails_enabled", dripEmailsEnabled)
        check("forecast_freeze_enabled", forecastFreezeEnabled)
        check("nws_freeze_alerts_enabled", nwsFreezeAlertsEnabled)
        check("quiet_hours_enabled", quietHoursEnabled)
        check("quiet_hours_bypass_freeze", quietHoursBypassFreeze)
        check("quiet_hours_sms_critical", quietHoursSmsCritical)
        check("battery_alerts_enabled", batteryAlertsEnabled)
        check("battery_trend_alerts_enabled", batteryTrendAlertsEnabled)
        check("rssi_alerts_enabled", rssiAlertsEnabled)
        check("escalation_enabled", escalationEnabled)
        check("feed_uptime_alerts_enabled", feedUptimeAlertsEnabled)
        check("portfolio_alerts_enabled", portfolioAlertsEnabled)
        check("channel_email", channelEmail)
        check("channel_sms", channelSms)
        check("channel_discord", channelDiscord)
        check("channel_push", channelPush)
        check("channel_webhook", channelWebhook)
        check("channel_telegram", channelTelegram)
        check("channel_slack", channelSlack)
        check("channel_teams", channelTeams)
        check("channel_ntfy", channelNtfy)
        check("channel_pushover", channelPushover)
        check("channel_whatsapp", channelWhatsapp)
        value("freeze_threshold_f", freezeThresholdF)
        value("humidity_threshold", humidityThreshold)
        value("rate_change_f", rateChangeF)
        value("outage_hours", outageHours)
        value("forecast_hours_ahead", forecastHoursAhead)
        fields.append(("quiet_hours_start", quietHoursStart))
        fields.append(("quiet_hours_end", quietHoursEnd))
        fields.append(("quiet_hours_timezone", quietHoursTimezone))
        value("battery_threshold_pct", batteryThresholdPct)
        value("rssi_threshold", rssiThreshold)
        value("escalation_minutes", escalationMinutes)
        optional("alert_email", email)
        optional("discord_webhook_url", discordWebhookUrl)
        optional("slack_webhook_url", slackWebhookUrl)
        optional("telegram_bot_token", telegramBotToken)
        optional("telegram_chat_id", telegramChatId)
        optional("ntfy_topic", ntfyTopic)
        fields.append(("ntfy_server", ntfyServer))
        optional("sms_phone", smsPhone)
        optional("whatsapp_phone", whatsappPhone)
        optional("outbound_webhook_url", outboundWebhookUrl)
        optional("reading_webhook_url", readingWebhookUrl)
        return fields
    }

    /// Matches Kotlin's Double.toString for whole numbers ("34.0").
    static func number(_ v: Double) -> String {
        v.rounded() == v && abs(v) < 1e15 ? String(format: "%.1f", v) : String(v)
    }
}

// GET /api/household

struct HouseholdResponse: Decodable, Sendable {
    var householdId: String?
    var members: [HouseholdMember]?
    var households: [UserHousehold]?
    var invites: [HouseholdInvite]?
}

struct HouseholdMember: Decodable, Hashable, Sendable {
    var userId: String?
    var role: String?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case role, email
        case userId = "user_id"
    }
}

struct UserHousehold: Decodable, Hashable, Identifiable, Sendable {
    var householdId: String
    var role: String?
    var name: String?

    var id: String { householdId }

    enum CodingKeys: String, CodingKey {
        case role, name
        case householdId = "household_id"
    }
}

struct HouseholdInvite: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var email: String?
    var role: String?
    var expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case expiresAt = "expires_at"
    }
}

// GET /api/share/manage

struct ShareLinksResponse: Decodable, Sendable {
    var links: [ShareLinkInfo]?
}

struct ShareLinkInfo: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var token: String
    var scope: String?
    var label: String?
    var expiresAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, token, scope, label
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

// Auth responses from the site

struct TokenPairResponse: Decodable, Sendable {
    var ok: Bool?
    var accessToken: String?
    var refreshToken: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok, error
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
