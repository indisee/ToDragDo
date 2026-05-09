import SwiftUI
import ToDragDoCore

/// Discrete actions surfaced on a row's hover bar.
/// The active set is determined by the row's folder context.
enum RowAction: Hashable, Identifiable {
    case moveToToday
    case moveToTomorrow
    case moveToLimbo
    case markDone
    case delete

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .moveToToday:    "sun.max"
        case .moveToTomorrow: "arrow.right"
        case .moveToLimbo:    "tray"
        case .markDone:       "checkmark"
        case .delete:         "trash"
        }
    }

    var helpText: LocalizedStringKey {
        switch self {
        case .moveToToday:    "Move to Today"
        case .moveToTomorrow: "Move to Tomorrow"
        case .moveToLimbo:    "Move to Limbo"
        case .markDone:       "Mark Done"
        case .delete:         "Delete"
        }
    }

    /// Action set shown for items currently in `folder`, in display order.
    static func actions(for folder: Folder) -> [RowAction] {
        switch folder {
        case .today:    [.moveToTomorrow, .moveToLimbo, .delete, .markDone]
        case .tomorrow: [.moveToLimbo, .delete, .markDone]
        case .libmo:    [.moveToToday, .delete, .markDone]
        case .done:     [.delete]
        }
    }
}
