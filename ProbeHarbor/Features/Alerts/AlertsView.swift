import SwiftUI

@MainActor
@Observable
final class AlertsModel {
    enum Tab: Hashable { case inbox, settings }

    var tab: Tab = .inbox
    var loading = true
    var saving = false
    var settings = AlertSettings()
    var events: [AlertEvent] = []
    var unackedCount = 0
    var message: String?
    var error: String?

    private let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    func refresh() async {
        error = nil
        let api = self.api
        async let exportTask = bestEffort { try await api.export() }
        do {
            let response = try await api.alertEvents()
            events = response.events ?? []
            unackedCount = response.unackedCount ?? 0
        } catch {
            self.error = error.localizedDescription
        }
        if let alertSettings = await exportTask?.alertSettings { settings = alertSettings }
        loading = false
    }

    func save() async {
        await run(success: "Alert settings saved.") { try await self.api.saveAlertSettings(self.settings) }
    }

    func acknowledge(_ event: AlertEvent) async {
        await run(success: "Acknowledged.") { try await self.api.acknowledge(eventId: event.id) }
        await refresh()
    }

    func sendTest() async {
        saving = true
        error = nil
        do { message = try await api.sendTestAlert() } catch { self.error = error.localizedDescription }
        saving = false
        await refresh()
    }

    func snooze(hours: Int) async {
        await run(success: "Snoozed for \(hours)h.") { try await self.api.snooze(action: "snooze", hours: hours) }
        await refresh()
    }

    func vacation(days: Int) async {
        await run(success: "Vacation mode for \(days) days.") { try await self.api.snooze(action: "vacation", days: days) }
        await refresh()
    }

    func clear(_ action: String) async {
        await run(success: "Cleared.") { try await self.api.snooze(action: action) }
        await refresh()
    }

    private func run(success: String, _ work: () async throws -> Void) async {
        saving = true
        error = nil
        message = nil
        do {
            try await work()
            message = success
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

struct AlertsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: AlertsModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { AlertsContent(model: model, highlighted: app.highlightedEventId) } else { ProgressView() }
            }
            .navigationTitle("Alerts")
            .screenBackground()
        }
        .task {
            if model == nil { model = AlertsModel(api: app.api) }
            await model?.refresh()
        }
        .onChange(of: app.highlightedEventId) { _, id in
            guard id != nil else { return }
            model?.tab = .inbox
            Task { await model?.refresh() }
        }
    }
}

private struct AlertsContent: View {
    @Bindable var model: AlertsModel
    var highlighted: Int64?

    var body: some View {
        List {
            Section {
                Picker("View", selection: $model.tab) {
                    Text(model.unackedCount > 0 ? "Inbox (\(model.unackedCount))" : "Inbox").tag(AlertsModel.Tab.inbox)
                    Text("Settings").tag(AlertsModel.Tab.settings)
                }
                .pickerStyle(.segmented)
                StatusBanner(message: model.message, error: model.error)
            }
            .listRowBackground(Color.clear)

            switch model.tab {
            case .inbox: inbox
            case .settings: AlertSettingsSections(model: model)
            }
        }
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
    }

    @ViewBuilder
    private var inbox: some View {
        Section {
            Button {
                Task { await model.sendTest() }
            } label: {
                Label("Send test alert", systemImage: "paperplane")
            }
            .disabled(model.saving)
        } footer: {
            Text("Acknowledge events and send a channel test.")
        }

        Section("Recent alerts") {
            if model.events.isEmpty, !model.loading {
                Text("No alert events yet.").foregroundStyle(Theme.textMuted)
            }
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.title ?? event.kind ?? "Alert").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Format.relativeTime(event.createdAt)).font(.caption).foregroundStyle(Theme.textMuted)
                    }
                    if let body = event.body, !body.isEmpty {
                        Text(body).font(.footnote)
                    }
                    if let sent = event.channelsSent, !sent.isEmpty {
                        Text("Sent: \(sent.joined(separator: ", "))").font(.caption).foregroundStyle(Theme.textMuted)
                    }
                    if event.isAcknowledged {
                        Label("Acknowledged", systemImage: "checkmark").font(.caption).foregroundStyle(Theme.success)
                    } else {
                        Button("Acknowledge") { Task { await model.acknowledge(event) } }
                            .buttonStyle(.bordered)
                            .disabled(model.saving)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(event.id == highlighted ? Theme.accent.opacity(0.15) : Theme.surface)
            }
        }
    }
}

private struct AlertSettingsSections: View {
    @Bindable var model: AlertsModel

    var body: some View {
        Section("Snooze") {
            if let until = model.settings.snoozeUntil {
                Text("Snoozed until \(Format.dateTime(until))").font(.footnote)
                Button("Clear snooze") { Task { await model.clear("clear_snooze") } }
            }
            if let until = model.settings.vacationUntil {
                Text("Vacation until \(Format.dateTime(until))").font(.footnote)
                Button("Clear vacation") { Task { await model.clear("clear_vacation") } }
            }
            HStack {
                ForEach([4, 12, 24, 48], id: \.self) { hours in
                    Button("\(hours)h") { Task { await model.snooze(hours: hours) } }.buttonStyle(.bordered)
                }
            }
            HStack {
                Button("Vacation 3d") { Task { await model.vacation(days: 3) } }.buttonStyle(.bordered)
                Button("Vacation 7d") { Task { await model.vacation(days: 7) } }.buttonStyle(.bordered)
            }
            Text("Freeze and leak alerts still fire during snooze/vacation.")
                .font(.caption).foregroundStyle(Theme.textMuted)
        }
        .disabled(model.saving)

        Section("Alert settings") {
            Toggle("Alerts enabled", isOn: $model.settings.enabled)
            Toggle("Email digest", isOn: $model.settings.digestEnabled)
            Toggle("Forecast freeze alerts", isOn: $model.settings.forecastFreezeEnabled)
            Toggle("NWS freeze alerts", isOn: $model.settings.nwsFreezeAlertsEnabled)
            Toggle("Quiet hours", isOn: $model.settings.quietHoursEnabled)
            NumberField(title: "Freeze threshold (°F)", value: $model.settings.freezeThresholdF)
            NumberField(title: "Humidity threshold (%)", value: $model.settings.humidityThreshold)
            NumberField(title: "Rate-of-change (°F)", value: $model.settings.rateChangeF)
            NumberField(title: "Outage hours", value: $model.settings.outageHours)
        }

        Section("Channels") {
            Toggle("Email", isOn: $model.settings.channelEmail)
            Toggle("Push", isOn: $model.settings.channelPush)
            Toggle("Discord", isOn: $model.settings.channelDiscord)
            Toggle("Slack", isOn: $model.settings.channelSlack)
            Toggle("Telegram", isOn: $model.settings.channelTelegram)
            TextField("Alert email", text: Binding(
                get: { model.settings.email ?? "" },
                set: { model.settings.email = $0.isEmpty ? nil : $0 }
            ))
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        }

        Section {
            Button {
                Task { await model.save() }
            } label: {
                if model.saving { ProgressView() } else { Text("Save alert settings") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.saving)
        }
        .listRowBackground(Color.clear)
    }
}

/// Labeled decimal field bound to a Double.
struct NumberField: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
    }
}
