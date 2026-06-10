import SwiftUI
import ToDragDoCore

/// Discrete actions surfaced through the two-phased swipe (Phase 3).
/// Phase 1 actions reveal on a short trailing swipe; phase 2 actions
/// reveal as the user pulls further. The user always commits via a
/// tap on a revealed button (or a full destructive pull) — there's no
/// leading-edge shortcut.
enum RowAction: Hashable, Identifiable {
    case moveToToday
    case moveToTomorrow
    case moveToLimbo
    case markDone
    case delete
    case restore
    case purge
    case edit
    case assignDate
    case assignProject

    var id: Self { self }

    /// Which phase of the trailing-swipe reveal this action appears in.
    enum Phase {
        case primary, secondary
    }

    var systemImage: String {
        switch self {
        case .moveToToday:    "sun.max"
        case .moveToTomorrow: "arrow.right.circle.fill"
        case .moveToLimbo:    "tray.circle.fill"
        case .markDone:       "checkmark"
        case .delete:         "trash"
        case .restore:        "arrow.uturn.backward"
        case .purge:          "xmark.bin"
        case .edit:           "pencil"
        case .assignDate:     "calendar"
        case .assignProject:  "folder"
        }
    }

    /// Short caption rendered under the SF Symbol in the swipe strip.
    var shortLabel: String {
        switch self {
        case .moveToToday:    "Today"
        case .moveToTomorrow: "Tomorrow"
        case .moveToLimbo:    "Limbo"
        case .markDone:       "Done"
        case .delete:         "Delete"
        case .restore:        "Restore"
        case .purge:          "Purge"
        case .edit:           "Edit"
        case .assignDate:     "Date"
        case .assignProject:  "Project"
        }
    }

    /// Background tint for the swipe-strip button. Destructive actions
    /// share red so the user can spot the "pull all the way to fire"
    /// target without reading labels.
    var tint: Color {
        switch self {
        case .delete, .purge:                       return .red
        case .markDone, .restore:                   return .green
        case .moveToToday:                          return .orange
        case .moveToTomorrow:                       return .blue
        case .moveToLimbo:                          return .gray
        case .edit:                                 return Color(red: 0.45, green: 0.45, blue: 0.55)
        case .assignDate:                           return .purple
        case .assignProject:                        return .indigo
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
        case .edit:           "Edit"
        case .assignDate:     "Assign date"
        case .assignProject:  "Assign project"
        }
    }

    /// Phase-1 actions display first as the user swipes; phase-2 adds the
    /// less-common destinations and edit/date/project triggers. Order is
    /// also the rendering order (leftmost = revealed last). Actions fire
    /// only on explicit button taps — there is no implicit full-pull
    /// trigger.
    static func actions(for folder: Folder, phase: Phase, inTrash: Bool = false) -> [RowAction] {
        if inTrash {
            switch phase {
            case .primary:   return [.moveToToday, .markDone, .purge]
            case .secondary: return []
            }
        }
        switch (folder, phase) {
        case (.today, .primary):      return [.moveToTomorrow, .markDone, .delete]
        case (.today, .secondary):    return [.moveToLimbo, .edit, .assignDate, .assignProject]
        case (.tomorrow, .primary):   return [.markDone, .delete]
        case (.tomorrow, .secondary): return [.moveToToday, .moveToLimbo, .edit, .assignDate, .assignProject]
        case (.libmo, .primary):      return [.markDone, .delete]
        case (.libmo, .secondary):    return [.moveToToday, .moveToTomorrow, .edit, .assignDate, .assignProject]
        case (.done, .primary):       return [.delete]
        case (.done, .secondary):     return [.moveToToday, .moveToTomorrow, .moveToLimbo, .edit, .assignProject]
        }
    }

}
