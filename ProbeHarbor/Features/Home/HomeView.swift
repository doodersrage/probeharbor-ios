import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var model: HomeModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { HomeContent(model: model) } else { ProgressView() }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark(size: 18) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model?.refresh(full: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .screenBackground()
        }
        .onAppear {
            if model == nil { model = HomeModel(api: app.api) }
            model?.startPolling()
        }
        .onDisappear { model?.stopPolling() }
    }
}

private struct HomeContent: View {
    @Bindable var model: HomeModel

    var body: some View {
        if model.loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live readings").font(.title2.weight(.semibold))
                        Text(model.readings?.updatedAt.map { "Updated \(Format.relativeTime($0))" } ?? "From probeharbor.dev")
                            .font(.footnote).foregroundStyle(Theme.textMuted)
                        if let outdoor = model.outdoorTempF {
                            Text("Outdoor ~\(String(format: "%.0f", outdoor))°F")
                                .font(.footnote).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .listRowBackground(Color.clear)

                if let ingest = model.ingestStatus, ingest.waiting == true {
                    row { IngestWaitingCard(ingest: ingest) }
                }
                if let runway = model.homeInsights?.timeToFreeze {
                    row { TimeToFreezeCard(runway: runway) }
                }
                if let house = model.homeInsights?.house {
                    row { HouseCard(house: house) }
                }
                if let benchmark = model.homeInsights?.regionalBenchmark {
                    row {
                        Card {
                            Text("Regional benchmark").font(.subheadline.weight(.semibold))
                            Text(benchmark.message).font(.footnote).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                if let alerts = model.homeInsights?.nwsAlerts, !alerts.isEmpty {
                    Section("Weather alerts") {
                        ForEach(alerts, id: \.self) { alert in
                            Card(tint: Theme.warning) {
                                Text(alert.event).font(.subheadline.weight(.semibold))
                                Text(alert.headline).font(.footnote)
                                Text([alert.severity, alert.expires.map { "Expires \(Format.dateTime($0))" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.textMuted)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                if let nights = model.homeInsights?.nightsAtRisk, !nights.isEmpty {
                    Section {
                        ForEach(nights, id: \.self) { night in
                            HStack {
                                Text(night.dateLabel)
                                Spacer()
                                Text(String(format: "%.1f°F", night.minTempF))
                                    .foregroundStyle(night.atRisk ? Theme.warning : Theme.text)
                                if night.atRisk { Text("at risk").font(.caption).foregroundStyle(Theme.warning) }
                            }
                            .font(.subheadline)
                        }
                    } header: {
                        SectionHeader(title: "Nights at risk", subtitle: "Forecast freeze risk for the next 7 nights.")
                    }
                }
                if !model.doorSessions.isEmpty {
                    Section("Door open sessions") {
                        ForEach(model.doorSessions, id: \.self) { session in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.label).font(.subheadline.weight(.medium))
                                Text(doorDetail(session)).font(.caption).foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                if !model.insights.isEmpty {
                    Section {
                        ForEach(model.insights, id: \.self) { insight in
                            Card(tint: insight.severity == .warning ? Theme.danger : nil) {
                                Text(insight.label).font(.subheadline.weight(.semibold))
                                Text(insight.detail).font(.footnote).foregroundStyle(Theme.textMuted)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        SectionHeader(title: "Heating insights", subtitle: "Temperature and humidity vs outdoor conditions.")
                    }
                }

                let spaces = model.readings?.allSpaces ?? []
                if !spaces.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                spaceChip("All spaces", selected: model.selectedSpace == nil) { nil }
                                ForEach(spaces, id: \.self) { space in
                                    spaceChip(space, selected: model.selectedSpace == space) { space }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                if let error = model.error {
                    StatusBanner(error: error).listRowBackground(Color.clear)
                }

                let sensors = model.readings?.allSensors ?? []
                Section("Sensors") {
                    if sensors.isEmpty, model.error == nil {
                        Text("No sensors yet. Add devices on probeharbor.dev.")
                            .font(.subheadline).foregroundStyle(Theme.textMuted)
                    }
                    ForEach(sensors) { sensor in
                        SensorRow(sensor: sensor)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refresh(full: true) }
            .overlay(alignment: .top) {
                if model.refreshing { ProgressView().padding(6) }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Section { content() }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
    }

    private func spaceChip(_ title: String, selected: Bool, value: @escaping () -> String?) -> some View {
        Button(title) { Task { await model.selectSpace(value()) } }
            .buttonStyle(.bordered)
            .tint(selected ? Theme.accent : Theme.textMuted)
    }

    private func doorDetail(_ session: DoorSession) -> String {
        var parts = ["Opened \(Format.relativeTime(session.openedAt))"]
        if session.stillOpen == true { parts.append("still open") }
        if let ms = session.durationMs { parts.append(Format.duration(ms: ms)) }
        return parts.joined(separator: " · ")
    }
}

private struct SensorRow: View {
    var sensor: LiveSensor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sensor.label.isEmpty ? sensor.key : sensor.label).font(.body.weight(.semibold))
                Spacer()
                Text(sensor.kind)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
            Text([sensor.deviceName, sensor.space].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.textMuted)
            Text(Format.sensorValue(sensor)).font(.title3.monospacedDigit())
            if let recorded = sensor.recordedAt {
                Text(Format.relativeTime(recorded)).font(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IngestWaitingCard: View {
    var ingest: IngestStatusResponse

    var body: some View {
        Card(tint: Theme.warning) {
            Text("Waiting for first POST").font(.subheadline.weight(.semibold))
            Text("\(ingest.waitingCount ?? 0) device(s) created but no data received yet.")
                .font(.footnote).foregroundStyle(Theme.textMuted)
            ForEach((ingest.devices ?? []).prefix(3)) { device in
                Text("\(device.name): \((device.sensorKeys ?? []).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

private struct TimeToFreezeCard: View {
    var runway: TimeToFreeze

    var body: some View {
        let threshold = runway.freezeThresholdF ?? 34
        Card(tint: Theme.accent) {
            Text("Time to freeze").font(.subheadline.weight(.semibold))
            Text("\(sourceLabel) vs your \(Format.number(threshold))°F threshold.")
                .font(.footnote).foregroundStyle(Theme.textMuted)
            if let clock = clock(threshold) {
                Text(clock).font(.headline)
            }
            if let message = runway.message, !message.isEmpty {
                Text(message).font(.footnote)
            }
            let meta = [confidenceLabel, cooling].compactMap { $0 }
            if !meta.isEmpty {
                Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func clock(_ threshold: Double) -> String? {
        if runway.hours == 0 { return "At \(Format.number(threshold))°F now" }
        if let label = runway.hitsAtLabel, !label.isEmpty { return "Hits \(Format.number(threshold))°F around \(label)" }
        return nil
    }

    private var sourceLabel: String {
        switch runway.source {
        case "forecast_model": return "Forecast-backed from this space"
        case "trend": return "Cooling-rate estimate"
        case "already_below": return "At threshold now"
        default: return "Not enough data yet"
        }
    }

    private var confidenceLabel: String? {
        switch runway.confidence {
        case "high": return "High confidence"
        case "medium": return "Medium confidence"
        case "low": return "Low confidence"
        default: return nil
        }
    }

    private var cooling: String? {
        guard let rate = runway.rateFPerHour, rate < -0.05 else { return nil }
        return String(format: "Cooling %.1f°F/hr", abs(rate))
    }
}

private struct HouseCard: View {
    var house: HouseInsight

    var body: some View {
        Card {
            Text(title).font(.subheadline.weight(.semibold))
            Text(String(format: "%.0f°F", house.ambientTempF ?? 0)).font(.title2.monospacedDigit())
            if let detail = house.detail, !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var title: String {
        if house.source == "reference_sensor", let label = house.referenceLabel, !label.isEmpty { return label }
        return house.source == "reference_sensor" ? "Indoor reference" : "House"
    }
}
