import Foundation
import Observation
import ToDragDoCore

/// Transient UI state for the floating panel.
/// Lives for the panel's lifetime; not persisted.
@MainActor
@Observable
final class PanelState {
    var selectedFolder: Folder = .today {
        didSet {
            guard oldValue != selectedFolder else { return }
            currentPage = 0
            expandedItemId = nil
        }
    }
    var expandedItemId: UUID? = nil
    var inputDraft: String = ""
    var pendingAttachments: [Attachment] = []
    var isListCollapsed: Bool = false
    /// Zero-based page index for the current folder list. Resets to 0
    /// whenever the selected folder changes; ItemList clamps it against
    /// the live page count when items are added or removed.
    var currentPage: Int = 0

    /// Toggle a row's expanded state. Collapses if already expanded.
    func toggleExpanded(_ id: UUID) {
        expandedItemId = (expandedItemId == id) ? nil : id
    }

    func openItem(_ id: UUID) {
        expandedItemId = id
    }

    func closeItem() {
        expandedItemId = nil
    }
}
