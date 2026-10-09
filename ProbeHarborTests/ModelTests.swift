import XCTest
@testable import ProbeHarbor

final class ModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testHomeReadingsDecodesSnakeAndCamelFields() throws {
        let response = try decode(HomeReadingsResponse.self, """
        {"updatedAt":"2026-10-09T12:00:00Z","spaces":["Garage"],
         "sensors":[{"deviceId":"d1","deviceName":"Garage ESP","space":"Garage","key":"t0","label":"Probe 0",
                     "kind":"temperature","value_num":null,"recorded_at":"2026-10-09T11:59:00Z",
                     "temp":{"f":66.7,"c":19.3,"h":48}},
                    {"deviceId":"d1","deviceName":"Garage ESP","key":"door","label":"Door","kind":"contact","value_bool":true}]}
        """)
        XCTAssertEqual(response.allSensors.count, 2)
        XCTAssertEqual(response.allSensors[0].temp?.f, 66.7)
        XCTAssertEqual(response.allSensors[1].valueBool, true)
        XCTAssertEqual(response.allSpaces, ["Garage"])
    }

    func testMissingCollectionsDecodeAsEmpty() throws {
        let response = try decode(HomeReadingsResponse.self, "{}")
        XCTAssertTrue(response.allSensors.isEmpty)
        XCTAssertTrue(response.allSpaces.isEmpty)
    }

    func testAlertSettingsDefaultsWhenFieldsMissing() throws {
        let settings = try decode(AlertSettings.self, #"{"enabled":true,"freezeThresholdF":30}"#)
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.freezeThresholdF, 30)
        XCTAssertTrue(settings.channelEmail, "email channel defaults on")
        XCTAssertTrue(settings.quietHoursBypassFreeze)
        XCTAssertEqual(settings.ntfyServer, "https://ntfy.sh")
        XCTAssertEqual(settings.quietHoursStart, "22:00")
    }

    func testAlertSettingsFormSendsCheckboxesOnlyWhenOn() {
        var settings = AlertSettings()
        settings.enabled = true
        settings.channelSms = false
        settings.email = "me@example.com"
        let fields = Dictionary(settings.formFields.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(fields["alerts_enabled"], "true")
        XCTAssertNil(fields["channel_sms"], "unchecked boxes are omitted, like the web form")
        XCTAssertEqual(fields["channel_email"], "true")
        XCTAssertEqual(fields["freeze_threshold_f"], "34.0")
        XCTAssertEqual(fields["rssi_threshold"], "-90.0")
        XCTAssertEqual(fields["alert_email"], "me@example.com")
        XCTAssertNil(fields["sms_phone"], "nil optionals are not sent")
        XCTAssertEqual(fields["redirect"], "/dashboard/alerts")
    }

    func testPreferencesFormUsesOnForCheckboxes() {
        var prefs = UserPreferences()
        prefs.useCelsius = true
        prefs.showWeather = false
        let fields = Dictionary(prefs.formFields.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(fields["use_celsius"], "on")
        XCTAssertEqual(fields["show_garage_temps"], "on")
        XCTAssertNil(fields["show_weather"])
        XCTAssertEqual(fields["theme"], "dark")
    }

    func testAlertEventsAndHistoryDecode() throws {
        let events = try decode(AlertEventsResponse.self, """
        {"unacked_count":1,"events":[{"id":42,"kind":"freeze","title":"Freeze","body":"Garage 31°F",
          "channels_sent":["email","push"],"created_at":"2026-10-09T03:00:00Z","acknowledged_at":null}]}
        """)
        XCTAssertEqual(events.unackedCount, 1)
        XCTAssertEqual(events.events?.first?.id, 42)
        XCTAssertFalse(events.events?.first?.isAcknowledged ?? true)

        let history = try decode(HistoryResponse.self, """
        {"days":7,"chart":{"points":[{"timestamp":"2026-10-09T03:00:00.000Z","tempf":31.5,"humidity":60,"probeLabel":"Probe 0"}]},
         "house_overlay":{"source":"thermostat","points":[]},
         "readings":{"readings":[{"tempf":31.5,"tempc":-0.3,"timestamp":"2026-10-09T03:00:00Z","probe_label":"Probe 0"}]}}
        """)
        XCTAssertEqual(history.chart?.points?.first?.tempf, 31.5)
        XCTAssertNotNil(history.chart?.points?.first?.date, "fractional-second timestamps parse")
        XCTAssertEqual(history.houseOverlay?.source, "thermostat")
        XCTAssertEqual(history.readings?.readings?.first?.probeLabel, "Probe 0")
    }

    func testInsightsDecode() throws {
        let insights = try decode(HomeInsightsResponse.self, """
        {"freeze_threshold_f":34,"nights_at_risk":[{"date_label":"Sat","min_temp_f":28,"at_risk":true}],
         "time_to_freeze":{"hours":5.3,"hits_at_label":"3 AM","source":"trend","confidence":"high","rate_f_per_hour":-0.4},
         "house":{"source":"thermostat","ambient_temp_f":70,"hvac_mode":"HEAT"},
         "regional_benchmark":{"city_label":"Richmond, VA","message":"About typical."}}
        """)
        XCTAssertEqual(insights.nightsAtRisk?.first?.atRisk, true)
        XCTAssertEqual(insights.timeToFreeze?.hitsAtLabel, "3 AM")
        XCTAssertEqual(insights.house?.ambientTempF, 70)
        XCTAssertEqual(insights.regionalBenchmark?.message, "About typical.")
    }

    func testDevicesAggregateBySensorDevice() {
        func sensor(_ device: String, _ name: String, _ kind: String) -> LiveSensor {
            LiveSensor(deviceId: device, deviceName: name, space: nil, key: kind, label: kind, kind: kind)
        }
        let devices = DeviceSummary.aggregate([
            sensor("b", "basement", "temperature"),
            sensor("a", "Garage", "temperature"),
            sensor("a", "Garage", "humidity"),
            sensor("a", "Garage", "temperature"),
        ])
        XCTAssertEqual(devices.map(\.name), ["basement", "Garage"], "sorted case-insensitively")
        XCTAssertEqual(devices[1].sensorCount, 3)
        XCTAssertEqual(devices[1].kinds, ["humidity", "temperature"])
    }

    func testClaimsRangeIsInclusiveUTCDays() {
        let now = ISODates.parse("2026-10-09T02:00:00Z")!
        let (from, to) = ProbeHarborAPI.claimsRange(days: 7, now: now)
        XCTAssertEqual(from, "2026-10-03")
        XCTAssertEqual(to, "2026-10-09")
    }
}

private extension LiveSensor {
    init(deviceId: String, deviceName: String, space: String?, key: String, label: String, kind: String) {
        self.init(
            deviceId: deviceId, deviceName: deviceName, space: space, key: key, label: label, kind: kind,
            unit: nil, valueNum: nil, valueBool: nil, valueText: nil, recordedAt: nil, temp: nil
        )
    }
}
