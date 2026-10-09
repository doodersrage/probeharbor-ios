import Foundation

/// Port of the Android app's HeatingInsights: plain rules over the last week of
/// probe readings, outdoor temperature, and the house reference.
struct HeatingInsight: Hashable, Sendable {
    enum Severity: Sendable { case info, warning }
    var label: String
    var detail: String
    var severity: Severity
}

enum HeatingInsights {
    private static let heatingModes: Set<String> = ["HEAT", "HEATCOOL", "heat", "auxHeatOnly"]
    private static let coolingModes: Set<String> = ["COOL", "cool"]

    /// Dew point °F from air temperature and relative humidity (Magnus-Tetens).
    static func dewPointF(tempF: Double, rhPct: Double) -> Double? {
        guard tempF.isFinite, rhPct.isFinite, rhPct > 0, rhPct <= 100 else { return nil }
        let tC = (tempF - 32) * 5 / 9
        let a = 17.62, b = 243.12
        let gamma = log(rhPct / 100) + (a * tC) / (b + tC)
        let tdC = (b * gamma) / (a - gamma)
        guard tdC.isFinite else { return nil }
        return tdC * 9 / 5 + 32
    }

    /// °F per hour across the last 12 readings; negative means cooling.
    static func lossRate(_ points: [ChartPoint]) -> Double? {
        let temps = points.filter { $0.tempf.isFinite }.suffix(12)
        guard temps.count >= 2, let first = temps.first, let last = temps.last,
              let start = first.date, let end = last.date else { return nil }
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return nil }
        let rate = (last.tempf - first.tempf) / hours
        return rate.isFinite ? rate : nil
    }

    static func build(
        points: [ChartPoint],
        outdoorTempF: Double?,
        freezeThresholdF: Double,
        doorOpenMinutes: Double? = nil,
        house: HouseInsight? = nil
    ) -> [HeatingInsight] {
        var insights: [HeatingInsight] = []
        guard let latest = points.last(where: { $0.tempf.isFinite }) else { return insights }
        let rate = lossRate(points)
        let f0 = { (v: Double) in String(format: "%.0f", v) }
        let f1 = { (v: Double) in String(format: "%.1f", v) }

        if let rate, rate <= -2 {
            insights.append(.init(
                label: "Rapid temperature drop",
                detail: "Space is falling about \(f1(abs(rate)))°F/h. Check doors, heaters, and insulation.",
                severity: .warning
            ))
        }
        if let minutes = doorOpenMinutes, minutes >= 10, let rate, rate < 0 {
            insights.append(.init(
                label: "Door may be driving heat loss",
                detail: "Door open ~\(Int(minutes)) min while temperature is falling.",
                severity: .warning
            ))
        }
        if latest.tempf <= freezeThresholdF + 5 {
            insights.append(.init(
                label: "Near freeze threshold",
                detail: "Current \(f1(latest.tempf))°F — threshold is \(f0(freezeThresholdF))°F.",
                severity: latest.tempf <= freezeThresholdF ? .warning : .info
            ))
        }
        if let outdoor = outdoorTempF, outdoor <= 20, latest.tempf > freezeThresholdF {
            let margin = latest.tempf - freezeThresholdF
            insights.append(.init(
                label: "Cold snap outside",
                detail: "Outdoor \(f0(outdoor))°F — \(f0(margin))°F margin above your freeze alert.",
                severity: margin <= 8 ? .warning : .info
            ))
        }
        if let dew = dewPointF(tempF: latest.tempf, rhPct: latest.humidity ?? 0) {
            let margin = latest.tempf - dew
            if margin <= 5 {
                insights.append(.init(
                    label: "Condensation risk",
                    detail: "Dew point ~\(f0(dew))°F — air is within \(f0(max(margin, 0)))°F of saturating. Cold slabs and tools can sweat even if the probe is warmer.",
                    severity: margin <= 2 ? .warning : .info
                ))
            }
        }
        if let houseTemp = house?.ambientTempF, houseTemp.isFinite {
            let hasThermostat = house?.source == "thermostat"
            let mode = house?.hvacMode
            let delta = houseTemp - latest.tempf
            if delta >= 12 {
                let houseLabel = hasThermostat ? "House thermostat" : "Indoor reference"
                insights.append(.init(
                    label: "House–probe gap",
                    detail: "\(houseLabel) \(f0(houseTemp))°F vs probe \(f1(latest.tempf))°F (\(f0(delta))°F warmer inside). Freeze alerts still apply to the unconditioned probe.",
                    severity: latest.tempf <= freezeThresholdF + 5 ? .warning : .info
                ))
            }
            if latest.tempf <= freezeThresholdF, houseTemp > freezeThresholdF + 10 {
                insights.append(.init(
                    label: "Warm house, cold probe",
                    detail: "Probe is at or below \(f0(freezeThresholdF))°F while the house reads \(f0(houseTemp))°F — expected for an unheated shop, garage, or attic.",
                    severity: .info
                ))
            }
            if hasThermostat, let mode, heatingModes.contains(mode), latest.tempf < houseTemp - 15 {
                insights.append(.init(
                    label: "HVAC heating",
                    detail: "Furnace is on (house \(f0(houseTemp))°F) but the monitored space is unconditioned — it will stay colder than living areas.",
                    severity: .info
                ))
            }
            if hasThermostat, let mode, coolingModes.contains(mode), latest.tempf > houseTemp + 10 {
                insights.append(.init(
                    label: "HVAC cooling",
                    detail: "AC is running (house \(f0(houseTemp))°F). A hot attic, shop, or garage probe can still spike on sunny days.",
                    severity: .info
                ))
            }
        }
        return insights
    }
}
