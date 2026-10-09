import SwiftUI

/// Harbor palette, matching probeharbor.dev's dark theme.
enum Theme {
    static let background = Color(hex: 0x07111A)
    static let surface = Color(hex: 0x0F1F2C)
    static let surfaceRaised = Color(hex: 0x142A3A)
    static let border = Color.white.opacity(0.08)
    static let text = Color(hex: 0xF3F8FB)
    static let textMuted = Color(hex: 0x8AA0AF)
    /// Signal teal brightened for dark UI; buttons use dark ink on it (7.1:1).
    static let accent = Color(hex: 0x22B8D4)
    static let accentInk = Color(hex: 0x03202E)
    static let sky = Color(hex: 0xE6F4FB)
    static let navy = Color(hex: 0x0B3D5B)
    static let warning = Color(hex: 0xFBBF24)
    static let danger = Color(hex: 0xF87171)
    static let success = Color(hex: 0x22C55E)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// "Probe" in sky + "Harbor" in teal, like the site wordmark.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        (Text("Probe").foregroundColor(Theme.sky) + Text("Harbor").foregroundColor(Theme.accent))
            .font(.system(size: size, weight: .bold))
            .accessibilityLabel("ProbeHarbor")
    }
}

/// Rounded panel used across screens.
struct Card<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(tint?.opacity(0.6) ?? Theme.border, lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// Inline success / error line after an action.
struct StatusBanner: View {
    var message: String?
    var error: String?

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Theme.danger)
        } else if let message {
            Label(message, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(Theme.success)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.accentInk)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    /// Dark scrolling background used by every tab.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }
}
