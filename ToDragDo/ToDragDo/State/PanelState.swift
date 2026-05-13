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
            // Switching folders from the tab bar implicitly leaves the
            // trash view.
            isTrashOpen = false
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
    /// When true, the panel shows the (hidden) Trash list instead of the
    /// items in `selectedFolder`. Folder tabs stay visible so a trash
    /// item can be dragged onto a tab to restore it.
    var isTrashOpen: Bool = false {
        didSet {
            guard oldValue != isTrashOpen else { return }
            currentPage = 0
            expandedItemId = nil
        }
    }

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
