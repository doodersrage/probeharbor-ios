import Charts
import QuickLook
import SwiftUI

@MainActor
@Observable
final class HistoryModel {
    var loading = true
    var days = 7
    var points: [ChartPoint] = []
    var housePoints: [ChartPoint] = []
    var houseSource: String?
    var readings: [HistoryReading] = []
    var canUseClaimsPack = false
    var error: String?
    var claimsBusy = false
    var claimsMessage: String?
    var claimsFile: URL?

    private let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    func refresh(days: Int? = nil) async {
        if let days { self.days = days }
        if points.isEmpty { loading = true }
        error = nil
        claimsMessage = nil
        let api = self.api
        let window = self.days
        async let exportTask = bestEffort { try await api.export() }
        do {
            let history = try await api.history(days: window)
            points = history.chart?.points ?? []
            housePoints = history.houseOverlay?.points ?? []
            houseSource = history.houseOverlay?.source
            readings = history.readings?.readings ?? []
        } catch {
            self.error = error.localizedDescription
        }
        canUseClaimsPack = await exportTask?.entitlements?.canUseClaimsPack == true
        loading = false
    }

    func downloadClaimsPack() async {
        guard canUseClaimsPack else {
            claimsMessage = "Claims pack requires ProbeHarbor Pro — upgrade on probeharbor.dev."
            return
        }
        claimsBusy = true
        do {
            claimsFile = try await api.downloadClaimsPack(days: days)
        } catch {
            claimsMessage = error.localizedDescription
        }
        claimsBusy = false
    }

    func emailClaimsPack(to email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@") else { claimsMessage = "Enter the adjuster's email"; return false }
        claimsBusy = true
        defer { claimsBusy = false }
        do {
            _ = try await api.emailClaimsPack(adjusterEmail: trimmed, days: days)
            claimsMessage = "Claims pack sent to \(trimmed)."
            return true
        } catch {
            claimsMessage = error.localizedDescription
            return false
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var model: HistoryModel?
    @State private var adjusterEmail = ""
    @State private var emailSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { ProgressView() }
            }
            .navigationTitle("History")
            .screenBackground()
        }
        .task {
            if model == nil { model = HistoryModel(api: app.api) }
            await model?.refresh()
        }
    }

    @ViewBuilder
    private func content(_ model: HistoryModel) -> some View {
        @Bindable var model = model
        List {
            Section {
                Picker("Window", selection: Binding(
                    get: { model.days },
                    set: { value in Task { await model.refresh(days: value) } }
                )) {
                    Text("24 h").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            Section("Temperature (°F)") {
                if model.loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let error = model.error {
                    StatusBanner(error: error)
                } else if model.points.isEmpty {
                    Text("No chart points in this window.").foregroundStyle(Theme.textMuted)
                } else {
                    TemperatureChart(points: model.points, housePoints: model.housePoints)
                        .frame(height: 220)
                    let temps = model.points.map(\.tempf)
                    if let min = temps.min(), let max = temps.max() {
                        Text(String(format: "Min %.1f°F · Max %.1f°F", min, max))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    }
                    if !model.housePoints.isEmpty {
                        Text("\(houseLabel(model.houseSource)) overlay shown as dashed line.")
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
            }

            Section {
                Text(model.canUseClaimsPack
                     ? "Printable pack for the selected window. Share it, or print to PDF."
                     : "Claims pack is a Pro feature. Upgrade on probeharbor.dev to download or email a printable pack.")
                    .font(.footnote).foregroundStyle(Theme.textMuted)
                Button {
                    Task { await model.downloadClaimsPack() }
                } label: {
                    Label("Open claims pack", systemImage: "doc.richtext")
                }
                .disabled(model.claimsBusy || !model.canUseClaimsPack)
                Button {
                    emailSheet = true
                } label: {
                    Label("Email claims pack to adjuster", systemImage: "envelope")
                }
                .disabled(model.claimsBusy || !model.canUseClaimsPack)
                if model.claimsBusy { ProgressView() }
                if let message = model.claimsMessage {
                    Text(message).font(.footnote)
                }
            } header: {
                Text("Claims / insurance pack")
            }

            Section("Recent readings") {
                if model.readings.isEmpty, !model.loading {
                    Text("No readings.").foregroundStyle(Theme.textMuted)
                }
                ForEach(Array(model.readings.enumerated()), id: \.offset) { _, reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.probeLabel ?? reading.feedName ?? "Probe").font(.subheadline)
                            Text(Format.dateTime(reading.timestamp)).font(.caption).foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f°F", reading.tempf ?? 0)).font(.subheadline.monospacedDigit())
                            if let humidity = reading.humidity, humidity > 0 {
                                Text("\(Int(humidity))% RH").font(.caption).foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await model.refresh() }
        .quickLookPreview($model.claimsFile)
        .sheet(isPresented: $emailSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Adjuster email", text: $adjusterEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    } footer: {
                        Text("Sends a printable claims pack for the selected window.")
                    }
                }
                .navigationTitle("Email claims pack")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { emailSheet = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            Task { if await model.emailClaimsPack(to: adjusterEmail) { emailSheet = false } }
                        }
                        .disabled(model.claimsBusy)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func houseLabel(_ source: String?) -> String {
        switch source {
        case "thermostat": return "House thermostat"
        case "reference": return "Indoor reference"
        default: return "House"
        }
    }
}

/// Probe temperatures by label, with the freeze-free house overlay dashed.
struct TemperatureChart: View {
    var points: [ChartPoint]
    var housePoints: [ChartPoint]

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                if let date = point.date {
                    LineMark(x: .value("Time", date), y: .value("°F", point.tempf))
                        .foregroundStyle(by: .value("Probe", point.probeLabel ?? "Probe"))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(Array(housePoints.enumerated()), id: \.offset) { _, point in
                if let date = point.date {
                    LineMark(x: .value("Time", date), y: .value("°F", point.tempf), series: .value("Series", "House"))
                        .foregroundStyle(Theme.textMuted)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
        }
        .chartYAxisLabel("°F")
        .chartLegend(position: .bottom)
    }
}
