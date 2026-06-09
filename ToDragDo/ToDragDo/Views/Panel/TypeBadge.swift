import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes

/// Leading per-row indicator. Two modes:
/// - **Type**: symbol + tint resolved from the content-type registry.
/// - **Date**: when the item has a `dueDate`, shows `dd` over `MMM` in
///   two lines, replacing the type symbol. Past-due dates render in red.
///
/// The hardcoded `switch typeIdentifier` that used to live here moved into
/// `ContentTypeProvider.badge(forItemTypeIdentifier:)`. Provider plugins
/// (Jira, GitHub PR, …) ship their own glyph + tint without touching this
/// file.
struct TypeBadge: View {
    @Environment(\.theme) private var theme
    @Environment(\.contentTypes) private var contentTypes
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
            Text(badge.symbol)
                .font(.system(size: theme.bodySize, weight: .semibold, design: .monospaced))
                .foregroundStyle(symbolColor)
                .frame(width: 18, alignment: .center)
        }
    }

    private func isPast(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    private var badge: ContentBadge {
        contentTypes.resolve(itemTypeIdentifier: typeIdentifier)
            .badge(forItemTypeIdentifier: typeIdentifier)
            ?? ContentBadge(symbol: "=", color: .secondary)
    }

    private var symbolColor: Color {
        switch badge.color {
        case .accent: return theme.accent
        default:      return Color(badge.color)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        TypeBadge(typeIdentifier: "text/plain")
        TypeBadge(typeIdentifier: "url")
        TypeBadge(typeIdentifier: "file")
        TypeBadge(typeIdentifier: "image")
        TypeBadge(typeIdentifier: "text/plain", dueDate: .now)
        TypeBadge(typeIdentifier: "text/plain", dueDate: Date.now.addingTimeInterval(-86_400 * 3))
    }
    .padding()
}
