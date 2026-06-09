import Foundation
import ToDragDoCore

/// The five buttons rendered in the bottom tab bar. Four map 1:1 to a
/// `Folder`; `more` is the catch-all settings hub that lives off the
/// item-list axis.
enum Tab: Hashable {
    case today, tomorrow, limbo, done, more

    init(folder: Folder) {
        switch folder {
        case .today:    self = .today
        case .tomorrow: self = .tomorrow
        case .libmo:    self = .limbo
        case .done:     self = .done
        }
    }

    var folder: Folder? {
        switch self {
        case .today:    .today
        case .tomorrow: .tomorrow
        case .limbo:    .libmo
        case .done:     .done
        case .more:     nil
        }
    }
}
