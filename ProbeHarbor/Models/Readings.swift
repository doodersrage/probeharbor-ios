import Foundation

// GET /api/home/readings

struct HomeReadingsResponse: Decodable, Sendable {
    var updatedAt: String?
    var sensors: [LiveSensor]?
    var spaces: [String]?
    var error: String?

    var allSensors: [LiveSensor] { sensors ?? [] }
    var allSpaces: [String] { spaces ?? [] }
}

struct TempSample: Decodable, Hashable, Sendable {
    var f: Double
    var c: Double
    var h: Double?
}

struct LiveSensor: Decodable, Hashable, Identifiable, Sendable {
    var deviceId: String
    var deviceName: String
    var space: String?
    var key: String
    var label: String
    var kind: String
    var unit: String?
    var valueNum: Double?
    var valueBool: Bool?
    var valueText: String?
    var recordedAt: String?
    var temp: TempSample?

    var id: String { "\(deviceId):\(key):\(kind)" }

    enum CodingKeys: String, CodingKey {
        case deviceId, deviceName, space, key, label, kind, unit, temp
        case valueNum = "value_num"
        case valueBool = "value_bool"
        case valueText = "value_text"
        case recordedAt = "recorded_at"
    }
}

// GET /api/devices/ingest-status

struct IngestStatusResponse: Decodable, Sendable {
    var waiting: Bool?
    var waitingCount: Int?
    var devices: [WaitingDevice]?

    enum CodingKeys: String, CodingKey {
        case waiting, devices
        case waitingCount = "waiting_count"
    }
}

struct WaitingDevice: Decodable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var sensorKeys: [String]?
    var lastSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case sensorKeys = "sensor_keys"
        case lastSeenAt = "last_seen_at"
    }
}

// GET /api/home/weather

struct WeatherResponse: Decodable, Sendable {
    var weather: WeatherSnapshot?
}

struct WeatherSnapshot: Decodable, Sendable {
    var name: String?
    var temp: Double?
    var humidity: Double?
    var description: String?
}

/// Devices aggregated from live sensors (the export has no device ids).
struct DeviceSummary: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var space: String?
    var sensorCount: Int
    var kinds: [String]

    static func aggregate(_ sensors: [LiveSensor]) -> [DeviceSummary] {
        Dictionary(grouping: sensors, by: \.deviceId)
            .map { id, rows in
                let first = rows.first
                let name = (first?.deviceName).flatMap { $0.isEmpty ? nil : $0 } ?? "Device"
                return DeviceSummary(
                    id: id,
                    name: name,
                    space: first?.space,
                    sensorCount: rows.count,
                    kinds: Array(Set(rows.map(\.kind))).sorted()
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
