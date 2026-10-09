import SwiftUI

@MainActor
@Observable
final class HouseholdModel {
    var loading = true
    var saving = false
    var householdId: String?
    var households: [UserHousehold] = []
    var members: [HouseholdMember] = []
    var invites: [HouseholdInvite] = []
    var draftName = ""
    var inviteEmail = ""
    var inviteRole = "viewer"
    var message: String?
    var error: String?

    private let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    var currentName: String {
        households.first(where: { $0.householdId == householdId })?.name ?? ""
    }

    func refresh() async {
        error = nil
        do {
            let response = try await api.household()
            householdId = response.householdId
            households = response.households ?? []
            members = response.members ?? []
            invites = response.invites ?? []
            if draftName.isEmpty { draftName = currentName }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func saveName() async {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "Name is required"; return }
        await run(success: "Household renamed.") { try await self.api.renameHousehold(name) }
    }

    func sendInvite() async {
        let email = inviteEmail.trimmingCharacters(in: .whitespaces)
        guard email.contains("@") else { error = "Enter an email to invite"; return }
        await run(success: "Invite sent to \(email).") { try await self.api.invite(email: email, role: self.inviteRole) }
        if error == nil { inviteEmail = "" }
    }

    func switchTo(_ id: String) async {
        await run(success: "Switched household.") { try await self.api.switchHousehold(id) }
        draftName = currentName
    }

    private func run(success: String, _ work: () async throws -> Void) async {
        saving = true
        error = nil
        message = nil
        do {
            try await work()
            message = success
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

struct HouseholdView: View {
    @Environment(AppModel.self) private var app
    @State private var model: HouseholdModel?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("Household")
        .screenBackground()
        .task {
            if model == nil { model = HouseholdModel(api: app.api) }
            await model?.refresh()
        }
    }

    @ViewBuilder
    private func content(_ model: HouseholdModel) -> some View {
        @Bindable var model = model
        List {
            Section { StatusBanner(message: model.message, error: model.error) }
                .listRowBackground(Color.clear)

            if model.households.count > 1 {
                Section("Your households") {
                    ForEach(model.households) { household in
                        Button {
                            Task { await model.switchTo(household.householdId) }
                        } label: {
                            HStack {
                                Text(household.name ?? "Household").foregroundStyle(Theme.text)
                                Spacer()
                                Text(household.role ?? "").font(.caption).foregroundStyle(Theme.textMuted)
                                if household.householdId == model.householdId {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }

            Section("Name") {
                TextField("Household name", text: $model.draftName)
                Button("Save name") { Task { await model.saveName() } }.disabled(model.saving)
            }

            Section("Members") {
                ForEach(Array(model.members.enumerated()), id: \.offset) { _, member in
                    HStack {
                        Text(member.email ?? member.userId ?? "Member")
                        Spacer()
                        Text(member.role ?? "member").font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
            }

            if !model.invites.isEmpty {
                Section("Pending invites") {
                    ForEach(model.invites) { invite in
                        HStack {
                            Text(invite.email ?? "Invite")
                            Spacer()
                            Text(invite.role ?? "viewer").font(.caption).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }

            Section {
                TextField("Email", text: $model.inviteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Picker("Role", selection: $model.inviteRole) {
                    Text("Viewer").tag("viewer")
                    Text("Member").tag("member")
                }
                Button("Send invite") { Task { await model.sendInvite() } }.disabled(model.saving)
            } header: {
                Text("Invite someone")
            } footer: {
                Text("Viewers see readings and alerts; members can also change settings and devices.")
            }
        }
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
    }
}
