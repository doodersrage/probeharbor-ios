import XCTest
@testable import ProbeHarbor

final class InsightsAndFormattingTests: XCTestCase {
    private func point(_ minutes: Int, _ f: Double, humidity: Double = 40) -> ChartPoint {
        let base = ISODates.parse("2026-10-09T00:00:00Z")!
        let date = base.addingTimeInterval(Double(minutes) * 60)
        return ChartPoint(timestamp: ISO8601DateFormatter().string(from: date), tempf: f, humidity: humidity, probeLabel: "P0")
    }

    private func labels(_ insights: [HeatingInsight]) -> [String] { insights.map(\.label) }

    func testRapidDropAndNearFreeze() {
        let insights = HeatingInsights.build(
            points: [point(0, 42), point(60, 39), point(120, 36)],
            outdoorTempF: 30, freezeThresholdF: 34
        )
        XCTAssertTrue(labels(insights).contains("Rapid temperature drop"))
        let near = insights.first { $0.label == "Near freeze threshold" }
        XCTAssertEqual(near?.severity, .info, "above the threshold is informational")
    }

    func testAtThresholdIsAWarning() {
        let insights = HeatingInsights.build(points: [point(0, 33)], outdoorTempF: nil, freezeThresholdF: 34)
        XCTAssertEqual(insights.first { $0.label == "Near freeze threshold" }?.severity, .warning)
    }

    func testColdSnapAndCondensation() {
        let insights = HeatingInsights.build(
            points: [point(0, 50, humidity: 92)], outdoorTempF: 15, freezeThresholdF: 34
        )
        XCTAssertTrue(labels(insights).contains("Cold snap outside"))
        XCTAssertTrue(labels(insights).contains("Condensation risk"))
    }

    func testHouseGapAndHeating() {
        let house = HouseInsight(source: "thermostat", ambientTempF: 70, heatSetpointF: 68, hvacMode: "HEAT", detail: nil, referenceLabel: nil)
        let insights = HeatingInsights.build(points: [point(0, 45)], outdoorTempF: nil, freezeThresholdF: 34, house: house)
        XCTAssertTrue(labels(insights).contains("House–probe gap"))
        XCTAssertTrue(labels(insights).contains("HVAC heating"))
    }

    func testNoPointsNoInsights() {
        XCTAssertTrue(HeatingInsights.build(points: [], outdoorTempF: 10, freezeThresholdF: 34).isEmpty)
    }

    func testDewPoint() {
        XCTAssertEqual(HeatingInsights.dewPointF(tempF: 68, rhPct: 50)!, 48.7, accuracy: 0.3)
        XCTAssertNil(HeatingInsights.dewPointF(tempF: 68, rhPct: 0))
    }

    func testNumberFormatting() {
        XCTAssertEqual(Format.number(34), "34")
        XCTAssertEqual(Format.number(33.46), "33.5")
        XCTAssertEqual(Format.duration(ms: 3_900_000), "1h 5m")
        XCTAssertEqual(Format.duration(ms: 125_000), "2m")
        XCTAssertEqual(Format.duration(ms: 9_000), "9s")
    }

    func testSensorValueFormatting() {
        var sensor = LiveSensor(
            deviceId: "d", deviceName: "Garage", space: nil, key: "t", label: "Probe", kind: "temperature",
            unit: nil, valueNum: nil, valueBool: nil, valueText: nil, recordedAt: nil,
            temp: TempSample(f: 66.7, c: 19.3, h: 48)
        )
        XCTAssertEqual(Format.sensorValue(sensor), "66.7°F (19.3°C) · 48% RH")
        sensor.temp = nil
        sensor.valueBool = false
        XCTAssertEqual(Format.sensorValue(sensor), "Closed / Off")
        sensor.valueBool = nil
        sensor.valueNum = 87
        sensor.unit = "%"
        XCTAssertEqual(Format.sensorValue(sensor), "87 %")
    }
}
