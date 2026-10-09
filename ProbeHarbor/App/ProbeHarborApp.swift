import SwiftUI
import UIKit

@main
struct ProbeHarborApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor lazy var model = AppModel()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            model.push.configure()
            model.push.onOpenAlert = { [weak self] eventId in
                self?.model.openAlert(eventId: eventId)
            }
            if model.phase == .signedIn { model.push.registerIfAuthorized() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { model.push.didRegister(deviceToken: deviceToken) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .signedOut:
                LoginView()
            case .needsMfa:
                MFAView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.default, value: model.phase)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.history)
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(AppTab.alerts)
            DevicesView()
                .tabItem { Label("Devices", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppTab.devices)
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
    }
}
