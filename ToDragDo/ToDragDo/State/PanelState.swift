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
    /// Set while the user is editing an existing item via the input bar.
    /// `inputDraft` / `pendingAttachments` hold the item's content during
    /// edit; the user's prior draft is stashed in `savedDraftBeforeEdit`
    /// and restored when editing finishes or cancels.
    var editingItemId: UUID? = nil
    /// Project assigned to the item being edited (`nil` = unassigned).
    /// Local UI state — not persisted until `Return` commits the edit,
    /// so flipping projects mid-edit doesn't churn the outbox or fire
    /// CloudKit pushes. Only meaningful when `editingItemId != nil`.
    var editingProjectId: UUID? = nil
    private var savedDraftBeforeEdit: String? = nil
    private var savedAttachmentsBeforeEdit: [Attachment]? = nil
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
    /// Project assigned to new items submitted through the input bar.
    /// `nil` = unassigned. Picks via the badge next to the field.
    var inputProjectId: UUID? = nil
    /// Filter applied to the visible item list. Empty set shows items
    /// regardless of project (the gray "All" state); any non-empty set
    /// keeps only items whose `projectId` is in it — `.none` matches
    /// unassigned items.
    var filterProjectIds: Set<UUID?> = [] {
        didSet {
            guard oldValue != filterProjectIds else { return }
            currentPage = 0
            expandedItemId = nil
        }
    }

    func toggleFilterProject(_ id: UUID?) {
        if filterProjectIds.contains(id) {
            filterProjectIds.remove(id)
        } else {
            filterProjectIds.insert(id)
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

    /// Stash the current draft, move the item's note into the input bar,
    /// and close the expanded row. If an edit is already in progress, it
    /// is cancelled (the original stashed draft survives — the partially
    /// edited text is discarded).
    func beginEdit(itemId: UUID, note: String, projectId: UUID?) {
        if editingItemId == nil {
            savedDraftBeforeEdit = inputDraft
            savedAttachmentsBeforeEdit = pendingAttachments
        }
        editingItemId = itemId
        editingProjectId = projectId
        inputDraft = note
        pendingAttachments = []
        expandedItemId = nil
    }

    /// Restore the pre-edit draft and clear edit state.
    func endEdit() {
        inputDraft = savedDraftBeforeEdit ?? ""
        pendingAttachments = savedAttachmentsBeforeEdit ?? []
        editingItemId = nil
        editingProjectId = nil
        savedDraftBeforeEdit = nil
        savedAttachmentsBeforeEdit = nil
    }
}
