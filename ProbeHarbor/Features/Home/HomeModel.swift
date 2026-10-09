import Foundation
import Observation

@MainActor
@Observable
final class HomeModel {
    var loading = true
    var refreshing = false
    var readings: HomeReadingsResponse?
    var selectedSpace: String?
    var insights: [HeatingInsight] = []
    var outdoorTempF: Double?
    var homeInsights: HomeInsightsResponse?
    var doorSessions: [DoorSession] = []
    var ingestStatus: IngestStatusResponse?
    var error: String?

    private let api: ProbeHarborAPI
    private var pollTask: Task<Void, Never>?
    private var pollCount = 0

    init(api: ProbeHarborAPI) {
        self.api = api
    }

    /// Live readings every 30 s; insights, weather, and history every fifth poll.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.refresh(full: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                self.pollCount += 1
                await self.refresh(full: self.pollCount % 5 == 0)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func selectSpace(_ space: String?) async {
        selectedSpace = space
        await refresh(full: true)
    }

    func refresh(full: Bool) async {
        if readings == nil { loading = true } else { refreshing = true }
        error = nil
        let space = selectedSpace
        async let readingsTask = api.homeReadings(space: space)
        let api = self.api
        async let ingestTask = bestEffort { try await api.ingestStatus() }
        async let doorsTask = bestEffort { try await api.doorEvents() }

        do {
            readings = try await readingsTask
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
        if let ingest = await ingestTask { ingestStatus = ingest }
        if let doors = await doorsTask { doorSessions = doors.liveSessions ?? [] }

        if full { await refreshExtras() }
        refreshing = false
    }

    private func refreshExtras() async {
        let api = self.api
        async let exportTask = bestEffort { try await api.export() }
        async let historyTask = bestEffort { try await api.history(days: 7) }
        async let insightsTask = bestEffort { try await api.homeInsights() }
        let export = await exportTask
        let history = await historyTask
        let home = await insightsTask
        if let home { homeInsights = home }

        var outdoor: Double?
        if let weather = try? await api.weather(cityId: export?.preferences?.weatherCityId) {
            outdoor = weather.weather?.temp
        }
        outdoor = outdoor ?? home?.outdoorTempF ?? home?.weather?.tempF
        outdoorTempF = outdoor

        insights = HeatingInsights.build(
            points: history?.chart?.points ?? [],
            outdoorTempF: outdoor,
            freezeThresholdF: export?.alertSettings?.freezeThresholdF ?? 34,
            house: home?.house
        )
    }
}

/// Result of a best-effort call, or nil when it fails.
func bestEffort<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> T? {
    try? await operation()
}
