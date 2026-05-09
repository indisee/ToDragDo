import SwiftUI
import ToDragDoCore

/// Leading per-row indicator. Two modes:
/// - **Type**: `=` plain text · `+` Jira · `0` URL — colored per type.
/// - **Date**: when the item has a `dueDate`, shows `dd` over `MMM` in
///   two lines, replacing the type symbol. Past-due dates render in red.
struct TypeBadge: View {
    @Environment(\.theme) private var theme
    let typeIdentifier: String
    var dueDate: Date? = nil
    var calendar: Calendar = .autoupdatingCurrent
    var now: Date = .now

    var body: some View {
        if let dueDate {
            VStack(spacing: -2) {
                Text(dueDate, format: .dateTime.day(.twoDigits))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(dueDate, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
            }
            .foregroundStyle(isPast(dueDate) ? Color.red : .secondary)
            .frame(width: 24, alignment: .center)
            .accessibilityLabel(dueDate.formatted(date: .abbreviated, time: .omitted))
        } else {
            Text(symbol)
                .font(.system(size: theme.bodySize, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
        }
    }

    private func isPast(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
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
        TypeBadge(typeIdentifier: "text/plain", dueDate: .now)
        TypeBadge(typeIdentifier: "text/plain", dueDate: Date.now.addingTimeInterval(-86_400 * 3))
    }
    .padding()
}
