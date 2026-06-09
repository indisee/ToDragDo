import SwiftUI
import ToDragDoCore

/// Trash pane (More → Trash). Renders the soft-deleted items via the
/// shared `ItemListView` in `trashMode`. Folder arg is irrelevant in
/// trash mode but the parameter is non-optional, so we hand in `.libmo`
/// — the row swipe set is overridden by `RowAction.actions(for:phase:inTrash:)`.
struct TrashView: View {
    var body: some View {
        // VStack(spacing: 0) mirrors FolderTabView's container — without
        // it, the bare ItemListView inside a NavigationLink destination
        // doesn't get a proper height contract and the inner ScrollView
        // refuses to scroll even when content overflows.
        VStack(spacing: 0) {
            ItemListView(folder: .libmo, trashMode: true)
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
    }
}
