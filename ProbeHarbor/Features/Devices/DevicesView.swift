import SwiftUI

@MainActor
@Observable
final class DevicesModel {
    var loading = true
    var saving = false
    var devices: [DeviceSummary] = []
    var thermostat: ThermostatStatusResponse?
    var ingest: IngestStatusResponse?
    var editing: DeviceSummary?
    var draftName = ""
    var draftSpace = ""
    var message: String?
    var error: String?

    private let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    func refresh() async {
        error = nil
        let api = self.api
        async let thermostatTask = bestEffort { try await api.thermostat() }
        async let ingestTask = bestEffort { try await api.ingestStatus() }
        do {
            devices = DeviceSummary.aggregate(try await api.homeReadings().allSensors)
        } catch {
            self.error = error.localizedDescription
        }
        thermostat = await thermostatTask
        ingest = await ingestTask
        loading = false
    }

    func startEdit(_ device: DeviceSummary) {
        editing = device
        draftName = device.name
        draftSpace = device.space ?? ""
    }

    func saveEdit() async {
        guard let device = editing else { return }
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "Name is required"; return }
        saving = true
        error = nil
        do {
            if name != device.name { try await api.renameDevice(id: device.id, name: name) }
            let space = draftSpace.trimmingCharacters(in: .whitespaces)
            if space != (device.space ?? "") { try await api.setDeviceSpace(id: device.id, space: space) }
            message = "Device updated."
            editing = nil
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var model: DevicesModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { ProgressView() }
            }
            .navigationTitle("Devices")
            .screenBackground()
        }
        .task {
            if model == nil { model = DevicesModel(api: app.api) }
            await model?.refresh()
        }
    }

    @ViewBuilder
    private func content(_ model: DevicesModel) -> some View {
        @Bindable var model = model
        List {
            Section { StatusBanner(message: model.message, error: model.error) }
                .listRowBackground(Color.clear)

            if let ingest = model.ingest, ingest.waiting == true {
                Section("Waiting for first data") {
                    ForEach(ingest.devices ?? []) { device in
                        VStack(alignment: .leading) {
                            Text(device.name).font(.subheadline.weight(.medium))
                            Text((device.sensorKeys ?? []).joined(separator: ", "))
                                .font(.caption).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }

            Section {
                if model.devices.isEmpty, !model.loading {
                    Text("No devices reporting yet.").foregroundStyle(Theme.textMuted)
                }
                ForEach(model.devices) { device in
                    Button {
                        model.startEdit(device)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            Text([device.space, "\(device.sensorCount) sensor(s)", device.kinds.joined(separator: ", ")]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("Tap a device to rename it or set its space.")
            }

            Section {
                Button {
                    openURL(app.config.devicesSetupURL)
                } label: {
                    Label("Add a device on probeharbor.dev", systemImage: "plus.circle")
                }
            } footer: {
                Text("Push devices, pull feeds, Home Assistant, and MQTT are set up from the web dashboard.")
            }

            if let thermostat = model.thermostat {
                Section("Thermostat") {
                    ForEach(thermostat.connections ?? [], id: \.self) { connection in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.provider.capitalized).font(.subheadline.weight(.medium))
                            Text([
                                connection.ambientTempF.map { String(format: "House %.0f°F", $0) },
                                connection.heatSetpointF.map { String(format: "Heat to %.0f°F", $0) },
                                connection.hvacMode,
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                        }
                    }
                    if (thermostat.connections ?? []).isEmpty {
                        if thermostat.canConnect == true {
                            if let nest = thermostat.connectUrls?.nest, let url = URL(string: nest) {
                                Button("Connect Nest") { openURL(url) }
                            }
                            if let ecobee = thermostat.connectUrls?.ecobee, let url = URL(string: ecobee) {
                                Button("Connect Ecobee") { openURL(url) }
                            }
                        } else {
                            Text("Thermostat reference is a Pro feature.")
                                .font(.footnote).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
        .sheet(item: $model.editing) { device in
            NavigationStack {
                Form {
                    TextField("Name", text: $model.draftName)
                    TextField("Space (e.g. Garage)", text: $model.draftSpace)
                    StatusBanner(error: model.error)
                }
                .navigationTitle(device.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.editing = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await model.saveEdit() } }.disabled(model.saving)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
