import SwiftUI
import ToDragDoCore

/// Leading per-row indicator that hints at the item's content type.
/// `=` plain text · `+` Jira · `0` URL — colored per type.
struct TypeBadge: View {
    @Environment(\.theme) private var theme
    let typeIdentifier: String

    var body: some View {
        Text(symbol)
            .font(.system(size: theme.bodySize, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 18, alignment: .center)
    }

    private var symbol: String {
        switch typeIdentifier {
        case "jira":     "+"
        case "url":      "0"
        case "image":    "■"
        case "file":     "▤"
        default:         "="
        }
    }

    private var color: Color {
        switch typeIdentifier {
        case "jira":     theme.accent
        case "url":      .blue
        case "image":    .green
        case "file":     .orange
        default:         .secondary
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        TypeBadge(typeIdentifier: "text/plain")
        TypeBadge(typeIdentifier: "jira")
        TypeBadge(typeIdentifier: "url")
    }
    .padding()
}
