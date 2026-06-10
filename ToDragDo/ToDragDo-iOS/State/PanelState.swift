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
    /// The tab the user is currently looking at. Distinct from
    /// `selectedFolder` because `.more` lives off the folder axis — if
    /// we derived the tab from `selectedFolder` alone, any settings-pane
    /// re-render would snap the tab bar back to a folder tab.
    var selectedTab: Tab = .today {
        didSet {
            if let folder = selectedTab.folder, folder != selectedFolder {
                selectedFolder = folder
            }
            // Widget-driven quick-add mode is scoped to one input session;
            // bailing to another tab ends it so the list comes back when
            // the user returns to a folder tab.
            if oldValue != selectedTab { widgetInputMode = false }
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

    /// Token bumped by the deep-link handler when the input bar should
    /// grab keyboard focus (Quick Add widget tap, future Shortcuts entry).
    /// `InputBar` watches this with `.onChange` and sets its
    /// `@FocusState` to `true` whenever the value changes — a fresh
    /// `UUID()` per request makes repeats observable even when the
    /// value would otherwise compare equal.
    var focusInputBarRequest: UUID? = nil

    /// Set true by the widget deep-link path so the folder tab hides
    /// its list while the input bar is focused — gives the keyboard +
    /// the field full attention for a one-shot quick-add. Cleared when
    /// the field loses focus or the user switches tabs. Manually tapping
    /// the input bar does NOT toggle this on, so normal in-app focus
    /// keeps the list visible.
    var widgetInputMode: Bool = false

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
