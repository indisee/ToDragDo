import Foundation
import Observation
import ToDragDoCore

/// Transient UI state for the floating panel.
/// Lives for the panel's lifetime; not persisted.
@MainActor
@Observable
final class PanelState {
    var selectedFolder: Folder = .today
    var expandedItemId: UUID? = nil
    var inputDraft: String = ""
    var pendingAttachment: Attachment? = nil
    var isListCollapsed: Bool = false

    /// Toggle a row's expanded state. Collapses if already expanded.
    func toggleExpanded(_ id: UUID) {
        expandedItemId = (expandedItemId == id) ? nil : id
    }
}
