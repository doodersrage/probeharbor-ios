import SwiftUI

@MainActor
@Observable
final class AccountModel {
    var loading = true
    var saving = false
    var email: String?
    var tier: String?
    var preferences = UserPreferences()
    var referral: ReferralResponse?
    var pushBusy = false
    var message: String?
    var error: String?

    private let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    func refresh() async {
        error = nil
        let api = self.api
        async let referralTask = bestEffort { try await api.referral() }
        do {
            let export = try await api.export()
            email = export.user?.email
            tier = export.entitlements?.tier
            if let prefs = export.preferences { preferences = prefs }
        } catch {
            self.error = error.localizedDescription
        }
        referral = await referralTask
        loading = false
    }

    func save() async {
        saving = true
        error = nil
        message = nil
        do {
            try await api.savePreferences(preferences)
            message = "Preferences saved."
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }

    func enablePush(_ push: PushManager) async {
        pushBusy = true
        error = nil
        message = nil
        do {
            try await push.enable()
            message = "Push alerts enabled on this iPhone."
        } catch {
            self.error = error.localizedDescription
        }
        pushBusy = false
    }

    var referralShareText: String? {
        guard let referral else { return nil }
        return "Try ProbeHarbor — freeze and leak monitoring for vacant homes. Sign up with my link for \(referral.bonusTrialDays ?? 7) bonus trial days: \(referral.registerUrl)"
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var model: AccountModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) } else { ProgressView() }
            }
            .navigationTitle("Account")
            .screenBackground()
        }
        .task {
            if model == nil { model = AccountModel(api: app.api) }
            await model?.refresh()
        }
    }

    @ViewBuilder
    private func content(_ model: AccountModel) -> some View {
        @Bindable var model = model
        List {
            Section("Signed in") {
                Text(model.email ?? app.auth.currentEmail ?? "—")
                if let tier = model.tier {
                    LabeledContent("Plan", value: tier.capitalized)
                }
                Button("Plans & billing") { openURL(app.config.plansURL) }
                StatusBanner(message: model.message, error: model.error)
            }

            Section {
                NavigationLink("Household") { HouseholdView() }
                NavigationLink("Share links") { ShareLinksView() }
                NavigationLink("Portfolio") { PortfolioView() }
            } footer: {
                Text("Household and billing extras.")
            }

            Section("Display") {
                Toggle("Show probe temps on home", isOn: $model.preferences.showGarageTemps)
                Toggle("Show weather", isOn: $model.preferences.showWeather)
                Toggle("Use Celsius", isOn: $model.preferences.useCelsius)
                Picker("Theme", selection: $model.preferences.theme) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                Button {
                    Task { await model.save() }
                } label: {
                    if model.saving { ProgressView() } else { Text("Save preferences") }
                }
                .disabled(model.saving)
            }

            Section {
                Button {
                    Task { await model.enablePush(app.push) }
                } label: {
                    if model.pushBusy { ProgressView() } else { Text("Enable push on this iPhone") }
                }
                .disabled(model.pushBusy)
            } header: {
                Text("Push alerts")
            } footer: {
                Text(app.push.isAvailable
                     ? "Registers this iPhone with probeharbor.dev. Requires Pro and the Push channel enabled under Alerts."
                     : "Push needs Apple push signing and GoogleService-Info.plist in this build.")
            }

            if let referral = model.referral, let text = model.referralShareText {
                Section("Refer a friend") {
                    Text("Code: \(referral.code) · \(referral.signupCount ?? 0) signup(s) · +\(referral.bonusTrialDays ?? 7) trial days")
                        .font(.footnote)
                    ShareLink("Share referral link", item: text)
                }
            }

            Section {
                Button("Open settings on web") { openURL(app.config.url("/dashboard/settings")) }
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            }
        }
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
    }
}
