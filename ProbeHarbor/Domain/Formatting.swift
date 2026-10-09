import Foundation

enum ISODates {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return withFraction.date(from: value) ?? plain.date(from: value)
    }
}

enum Format {
    /// "34" for whole numbers, "33.5" otherwise (same as the Android app).
    static func number(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func temp(_ f: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f°F", f)
    }

    static func sensorValue(_ sensor: LiveSensor) -> String {
        if let sample = sensor.temp {
            let humidity = (sample.h ?? 0) > 0 ? " · \(Int(sample.h ?? 0))% RH" : ""
            return "\(number(sample.f))°F (\(number(sample.c))°C)\(humidity)"
        }
        if let bool = sensor.valueBool { return bool ? "Open / On" : "Closed / Off" }
        if let text = sensor.valueText, !text.isEmpty { return text }
        if let num = sensor.valueNum {
            let unit = sensor.unit.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
            return "\(number(num))\(unit)"
        }
        return "—"
    }

    static func duration(ms: Double) -> String {
        let total = Int(ms)
        let minutes = total / 60_000
        let hours = minutes / 60
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total / 1000)s"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    /// "5 min. ago" style for an ISO timestamp; falls back to the raw string.
    static func relativeTime(_ iso: String?, now: Date = Date()) -> String {
        guard let iso else { return "—" }
        guard let date = ISODates.parse(iso) else { return iso }
        return relative.localizedString(for: date, relativeTo: now)
    }

    static func dateTime(_ iso: String?) -> String {
        guard let date = ISODates.parse(iso) else { return iso ?? "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
