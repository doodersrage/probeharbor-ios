import SwiftUI

@MainActor
@Observable
final class PortfolioModel {
    var loading = true
    var switchingId: String?
    var properties: [PortfolioProperty] = []
    var message: String?
    var error: String?

    private let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    func refresh() async {
        error = nil
        do {
            properties = try await api.portfolio().properties ?? []
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func switchTo(_ property: PortfolioProperty) async -> Bool {
        switchingId = property.householdId
        error = nil
        defer { switchingId = nil }
        do {
            try await api.switchHousehold(property.householdId)
            message = "Switched to \(property.name)."
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct PortfolioView: View {
    @Environment(AppModel.self) private var app
    @State private var model: PortfolioModel?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("Portfolio")
        .screenBackground()
        .task {
            if model == nil { model = PortfolioModel(api: app.api) }
            await model?.refresh()
        }
    }

    @ViewBuilder
    private func content(_ model: PortfolioModel) -> some View {
        List {
            Section {
                StatusBanner(message: model.message, error: model.error)
            } footer: {
                Text("Tap a property to switch household.")
            }

            Section {
                if model.properties.isEmpty, !model.loading {
                    Text("No properties yet.").foregroundStyle(Theme.textMuted)
                }
                ForEach(model.properties) { property in
                    Button {
                        Task {
                            if await model.switchTo(property) { app.selectedTab = .home }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(property.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                    if property.atRisk == true {
                                        Text("At risk").font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Theme.warning.opacity(0.2), in: Capsule())
                                            .foregroundStyle(Theme.warning)
                                    }
                                }
                                Text(detail(property)).font(.caption).foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            if model.switchingId == property.householdId { ProgressView() }
                        }
                    }
                    .disabled(model.switchingId != nil)
                }
            }
        }
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
    }

    private func detail(_ property: PortfolioProperty) -> String {
        var parts = [property.role.capitalized]
        if let min = property.minTempF {
            parts.append(String(format: "Min %.1f°F (threshold %.0f°F)", min, property.freezeThresholdF ?? 34))
        }
        parts.append("\(property.deviceCount ?? 0) device(s)")
        if let last = property.lastReadingAt { parts.append(Format.relativeTime(last)) }
        return parts.joined(separator: " · ")
    }
}
