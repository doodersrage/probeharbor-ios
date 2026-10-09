import Foundation

// GET /api/user/home-insights

struct HomeInsightsResponse: Decodable, Sendable {
    var freezeThresholdF: Double?
    var nightsAtRisk: [NightAtRisk]?
    var nwsAlerts: [NwsAlert]?
    var outdoorTempF: Double?
    var house: HouseInsight?
    var regionalBenchmark: RegionalBenchmark?
    var weather: InsightWeather?
    var timeToFreeze: TimeToFreeze?

    enum CodingKeys: String, CodingKey {
        case house, weather
        case freezeThresholdF = "freeze_threshold_f"
        case nightsAtRisk = "nights_at_risk"
        case nwsAlerts = "nws_alerts"
        case outdoorTempF = "outdoor_temp_f"
        case regionalBenchmark = "regional_benchmark"
        case timeToFreeze = "time_to_freeze"
    }
}

struct TimeToFreeze: Decodable, Sendable {
    var hours: Double?
    var hitsAtLabel: String?
    var confidence: String?
    var source: String?
    var message: String?
    var rateFPerHour: Double?
    var freezeThresholdF: Double?
    var currentTempF: Double?

    enum CodingKeys: String, CodingKey {
        case hours, confidence, source, message
        case hitsAtLabel = "hits_at_label"
        case rateFPerHour = "rate_f_per_hour"
        case freezeThresholdF = "freeze_threshold_f"
        case currentTempF = "current_temp_f"
    }
}

struct HouseInsight: Decodable, Sendable {
    var source: String?
    var ambientTempF: Double?
    var heatSetpointF: Double?
    var hvacMode: String?
    var detail: String?
    var referenceLabel: String?

    enum CodingKeys: String, CodingKey {
        case source, detail
        case ambientTempF = "ambient_temp_f"
        case heatSetpointF = "heat_setpoint_f"
        case hvacMode = "hvac_mode"
        case referenceLabel = "reference_label"
    }
}

struct RegionalBenchmark: Decodable, Sendable {
    var cityLabel: String?
    var message: String

    enum CodingKeys: String, CodingKey {
        case message
        case cityLabel = "city_label"
    }
}

struct NightAtRisk: Decodable, Hashable, Sendable {
    var dateLabel: String
    var minTempF: Double
    var atRisk: Bool

    enum CodingKeys: String, CodingKey {
        case dateLabel = "date_label"
        case minTempF = "min_temp_f"
        case atRisk = "at_risk"
    }
}

struct NwsAlert: Decodable, Hashable, Sendable {
    var event: String
    var headline: String
    var severity: String
    var expires: String?
}

struct InsightWeather: Decodable, Sendable {
    var name: String?
    var tempF: Double?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case name, description
        case tempF = "temp_f"
    }
}

// GET /api/user/door-events

struct DoorEventsResponse: Decodable, Sendable {
    var liveSessions: [DoorSession]?

    enum CodingKeys: String, CodingKey {
        case liveSessions = "live_sessions"
    }
}

struct DoorSession: Decodable, Hashable, Sendable {
    var label: String
    var openedAt: String
    var closedAt: String?
    var durationMs: Double?
    var stillOpen: Bool?

    enum CodingKeys: String, CodingKey {
        case label
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case durationMs = "duration_ms"
        case stillOpen = "still_open"
    }
}

// GET /api/user/portfolio

struct PortfolioResponse: Decodable, Sendable {
    var properties: [PortfolioProperty]?
}

struct PortfolioProperty: Decodable, Hashable, Identifiable, Sendable {
    var householdId: String
    var name: String
    var role: String
    var minTempF: Double?
    var freezeThresholdF: Double?
    var atRisk: Bool?
    var lastReadingAt: String?
    var deviceCount: Int?

    var id: String { householdId }

    enum CodingKeys: String, CodingKey {
        case name, role
        case householdId = "household_id"
        case minTempF = "min_temp_f"
        case freezeThresholdF = "freeze_threshold_f"
        case atRisk = "at_risk"
        case lastReadingAt = "last_reading_at"
        case deviceCount = "device_count"
    }
}

// GET /api/integrations/thermostat

struct ThermostatStatusResponse: Decodable, Sendable {
    var canUse: Bool?
    var canConnect: Bool?
    var connections: [ThermostatConnection]?
    var connectUrls: ThermostatConnectURLs?

    enum CodingKeys: String, CodingKey {
        case connections
        case canUse = "can_use"
        case canConnect = "can_connect"
        case connectUrls = "connect_urls"
    }
}

struct ThermostatConnection: Decodable, Hashable, Sendable {
    var provider: String
    var connectedAt: String?
    var ambientTempF: Double?
    var heatSetpointF: Double?
    var hvacMode: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case connectedAt = "connected_at"
        case ambientTempF = "ambient_temp_f"
        case heatSetpointF = "heat_setpoint_f"
        case hvacMode = "hvac_mode"
    }
}

struct ThermostatConnectURLs: Decodable, Sendable {
    var nest: String?
    var ecobee: String?
}

// GET /api/user/referral

struct ReferralResponse: Decodable, Sendable {
    var code: String
    var registerUrl: String
    var signupCount: Int?
    var bonusTrialDays: Int?

    enum CodingKeys: String, CodingKey {
        case code
        case registerUrl = "register_url"
        case signupCount = "signup_count"
        case bonusTrialDays = "bonus_trial_days"
    }
}
