import Foundation

// GET /api/user/alert-events

struct AlertEventsResponse: Decodable, Sendable {
    var events: [AlertEvent]?
    var unackedCount: Int?

    enum CodingKeys: String, CodingKey {
        case events
        case unackedCount = "unacked_count"
    }
}

struct AlertEvent: Decodable, Hashable, Identifiable, Sendable {
    var id: Int64
    var kind: String?
    var title: String?
    var body: String?
    var channelsSent: [String]?
    var createdAt: String?
    var acknowledgedAt: String?

    var isAcknowledged: Bool { acknowledgedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case channelsSent = "channels_sent"
        case createdAt = "created_at"
        case acknowledgedAt = "acknowledged_at"
    }
}

struct OkResponse: Decodable, Sendable {
    var ok: Bool?
    var error: String?
    var message: String?
}

struct TestAlertResponse: Decodable, Sendable {
    var ok: Bool?
    var sent: [String]?
    var error: String?
}

// GET /api/user/history

struct HistoryResponse: Decodable, Sendable {
    var days: Int?
    var chart: HistoryChart?
    var houseOverlay: HouseOverlay?
    var readings: HistoryReadingsPage?

    enum CodingKeys: String, CodingKey {
        case days, chart, readings
        case houseOverlay = "house_overlay"
    }
}

struct HistoryChart: Decodable, Sendable {
    var points: [ChartPoint]?
}

struct HouseOverlay: Decodable, Sendable {
    var source: String?
    var points: [ChartPoint]?
}

struct ChartPoint: Decodable, Hashable, Sendable {
    var timestamp: String
    var tempf: Double
    var humidity: Double?
    var probeLabel: String?

    var date: Date? { ISODates.parse(timestamp) }
}

struct HistoryReadingsPage: Decodable, Sendable {
    var readings: [HistoryReading]?
}

struct HistoryReading: Decodable, Hashable, Sendable {
    var tempc: Double?
    var tempf: Double?
    var humidity: Double?
    var timestamp: String?
    var feedName: String?
    var probeLabel: String?

    enum CodingKeys: String, CodingKey {
        case tempc, tempf, humidity, timestamp
        case feedName = "feed_name"
        case probeLabel = "probe_label"
    }
}

// POST /api/claims/email

struct ClaimsEmailResponse: Decodable, Sendable {
    var ok: Bool?
    var verifyUrl: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok, error
        case verifyUrl = "verify_url"
    }
}
