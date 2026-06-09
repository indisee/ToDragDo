import Foundation
import Observation
import ToDragDoCore

/// Transient UI state for the iOS tab-bar app. Mirrors the macOS
/// `PanelState` shape minus the bits that don't apply (no pagination,
/// no `isTrashOpen` from a folder-bar — trash lives under the More tab).
///
/// Phase 1 ships the minimum the tab bar + future folder views need:
/// selectedFolder, expandedItemId, the input-bar draft + project, the
/// project filter, and edit-state. Phase 3 adds `latchedSwipeItemId`.
@MainActor
@Observable
final class PanelState {
    var selectedFolder: Folder = .today {
        didSet {
            guard oldValue != selectedFolder else { return }
            expandedItemId = nil
        }
    }
    var expandedItemId: UUID? = nil
    /// Flip every row open / closed at once. The Done-summary sheet's
    /// Open/Closed segment toggles this so all rows in that view obey
    /// the segment regardless of individual expansion.
    var allExpanded: Bool = false
    /// Item whose `RowSwipeContainer` is currently latched open.
    /// Setting this collapses the previously latched row — each
    /// container observes the property and closes itself when it sees
    /// a different id (or `nil`) land.
    var latchedSwipeItemId: UUID? = nil

    var inputDraft: String = ""
    var pendingAttachments: [Attachment] = []

    /// Set while the user is editing an existing item via the input bar.
    /// Same semantics as macOS: while editing, the bar holds the item's
    /// content and the pre-edit draft is stashed for restoration.
    var editingItemId: UUID? = nil
    var editingProjectId: UUID? = nil
    private var savedDraftBeforeEdit: String? = nil
    private var savedAttachmentsBeforeEdit: [Attachment]? = nil

    /// Project assigned to new items submitted through the input bar.
    var inputProjectId: UUID? = nil

    /// Filter applied to the visible item list. Empty set = "All";
    /// any non-empty set keeps only items whose `projectId` is in it
    /// (`.none` matches unassigned items).
    var filterProjectIds: Set<UUID?> = [] {
        didSet {
            guard oldValue != filterProjectIds else { return }
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

    func toggleExpanded(_ id: UUID) {
        expandedItemId = (expandedItemId == id) ? nil : id
    }

    func openItem(_ id: UUID) {
        expandedItemId = id
    }

    func closeItem() {
        expandedItemId = nil
    }

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

    func endEdit() {
        inputDraft = savedDraftBeforeEdit ?? ""
        pendingAttachments = savedAttachmentsBeforeEdit ?? []
        editingItemId = nil
        editingProjectId = nil
        savedDraftBeforeEdit = nil
        savedAttachmentsBeforeEdit = nil
    }
}
