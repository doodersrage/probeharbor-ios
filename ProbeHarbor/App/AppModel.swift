import Foundation
import Observation

enum AppTab: Hashable {
    case home, history, alerts, devices, account
}

/// Root state: which screen set to show, shared services, and deep links from
/// notifications.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case signedOut, needsMfa, signedIn }

    let config: AppConfig
    let sessionStore: SessionStoring
    let client: APIClient
    let api: ProbeHarborAPI
    let auth: AuthService
    let push: PushManager

    var phase: Phase
    var selectedTab: AppTab = .home
    /// Alert to highlight after opening a notification.
    var highlightedEventId: Int64?

    init(config: AppConfig = .current, sessionStore: SessionStoring = KeychainSessionStore()) {
        self.config = config
        self.sessionStore = sessionStore
        let client = APIClient(config: config, sessionStore: sessionStore)
        self.client = client
        api = ProbeHarborAPI(client: client)
        auth = AuthService(config: config, store: sessionStore, api: client)
        push = PushManager(api: ProbeHarborAPI(client: client))
        if let tokens = sessionStore.load() {
            phase = tokens.mfaSatisfied ? .signedIn : .needsMfa
        } else {
            phase = .signedOut
        }
        client.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.handleUnauthorized() }
        }
    }

    func didSignIn(_ outcome: AuthOutcome) {
        phase = outcome.needsMfa ? .needsMfa : .signedIn
        if phase == .signedIn { push.registerIfAuthorized() }
    }

    func didVerifyMfa() {
        phase = .signedIn
        push.registerIfAuthorized()
    }

    func signOut() async {
        await push.unregister()
        await auth.signOut()
        selectedTab = .home
        phase = .signedOut
    }

    func openAlert(eventId: Int64?) {
        highlightedEventId = eventId
        selectedTab = .alerts
    }

    private func handleUnauthorized() {
        guard phase != .signedOut else { return }
        sessionStore.clear()
        phase = .signedOut
    }
}
