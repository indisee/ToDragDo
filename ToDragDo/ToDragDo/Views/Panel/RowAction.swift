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
    case restore
    case purge

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .moveToToday:    "sun.max"
        case .moveToTomorrow: "arrow.right"
        case .moveToLimbo:    "tray"
        case .markDone:       "checkmark"
        case .delete:         "trash"
        case .restore:        "arrow.uturn.backward"
        case .purge:          "xmark.bin"
        }
    }

    var helpText: LocalizedStringKey {
        switch self {
        case .moveToToday:    "Move to Today"
        case .moveToTomorrow: "Move to Tomorrow"
        case .moveToLimbo:    "Move to Limbo"
        case .markDone:       "Mark Done"
        case .delete:         "Delete"
        case .restore:        "Restore to Today"
        case .purge:          "Delete Permanently"
        }
    }

    /// Action set shown for items currently in `folder`, in display order.
    /// When `inTrash` is true the row sits in the trash view and any
    /// folder-move action restores the item there (move() clears
    /// `deletedAt`); `.purge` hard-deletes it.
    static func actions(for folder: Folder, inTrash: Bool = false) -> [RowAction] {
        if inTrash {
            return [.moveToTomorrow, .markDone, .purge]
        }
        switch folder {
        case .today:    return [.moveToTomorrow, .delete, .markDone]
        case .tomorrow: return [.delete, .markDone]
        case .libmo:    return [.delete, .markDone]
        case .done:     return [.delete]
        }
    }
}
