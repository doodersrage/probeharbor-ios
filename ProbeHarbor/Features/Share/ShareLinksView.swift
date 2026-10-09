import SwiftUI
import UIKit

@MainActor
@Observable
final class ShareModel {
    var loading = true
    var busy = false
    var canCreate = false
    var links: [ShareLinkInfo] = []
    var label = ""
    var scope = "live"
    var expiresDays = 7
    var message: String?
    var error: String?

    let api: ProbeHarborAPI

    init(api: ProbeHarborAPI) { self.api = api }

    func refresh() async {
        error = nil
        let api = self.api
        async let exportTask = bestEffort { try await api.export() }
        do {
            links = try await api.shareLinks()
        } catch {
            self.error = error.localizedDescription
        }
        canCreate = await exportTask?.entitlements?.canCreateShareLinks == true
        loading = false
    }

    func create() async {
        busy = true
        error = nil
        message = nil
        do {
            let token = try await api.createShareLink(label: label, scope: scope, expiresDays: expiresDays)
            label = ""
            if let token {
                let url = api.client.config.shareURL(token: token).absoluteString
                UIPasteboard.general.string = url
                message = "Link created and copied: \(url)"
            } else {
                message = "Link created."
            }
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    func revoke(_ link: ShareLinkInfo) async {
        busy = true
        error = nil
        do {
            try await api.revokeShareLink(id: link.id)
            message = "Link revoked."
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

struct ShareLinksView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ShareModel?

    private static let expiryOptions: [(Int, String)] = [
        (0, "Never"), (2, "2 days"), (7, "7 days (guest)"), (14, "14 days"), (30, "30 days"),
    ]

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("Share links")
        .screenBackground()
        .task {
            if model == nil { model = ShareModel(api: app.api) }
            await model?.refresh()
        }
    }

    @ViewBuilder
    private func content(_ model: ShareModel) -> some View {
        @Bindable var model = model
        List {
            Section {
                StatusBanner(message: model.message, error: model.error)
            } footer: {
                Text("Read-only links for family or short guest/renter visits. Pro + household manager.")
            }

            Section("Create share link") {
                if !model.canCreate, !model.loading {
                    Text("Upgrade to Pro to create share links.").font(.footnote).foregroundStyle(Theme.textMuted)
                }
                TextField("Label", text: $model.label)
                Picker("Scope", selection: $model.scope) {
                    Text("Live").tag("live")
                    Text("History").tag("history")
                    Text("Metrics").tag("metrics")
                }
                Picker("Expires", selection: $model.expiresDays) {
                    ForEach(Self.expiryOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                Button("Create link") { Task { await model.create() } }
                    .disabled(!model.canCreate || model.busy)
            }

            Section("Your links") {
                if model.links.isEmpty, !model.loading {
                    Text("No share links yet.").foregroundStyle(Theme.textMuted)
                }
                ForEach(model.links) { link in
                    let url = app.config.shareURL(token: link.token)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(link.label?.isEmpty == false ? link.label! : "Share link").font(.subheadline.weight(.semibold))
                        Text([link.scope ?? "live", link.expiresAt.map { "Expires \(Format.dateTime($0))" } ?? "Never expires"]
                            .joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                        HStack {
                            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button("Copy") { UIPasteboard.general.string = url.absoluteString }
                            Button("Revoke", role: .destructive) { Task { await model.revoke(link) } }
                        }
                        .buttonStyle(.borderless)
                        .font(.footnote)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
    }
}
