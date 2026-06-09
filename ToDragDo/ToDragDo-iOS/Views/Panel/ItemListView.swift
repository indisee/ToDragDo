import SwiftUI
import ToDragDoCore

/// Lists items for the given folder. iOS replacement for the macOS
/// `ItemList` — drops pagination, missing-rows spacer, footer settings
/// menu, and the EndDropZone. Stays as a plain
/// `ScrollView { LazyVStack }` so the Phase 3 swipe gesture isn't
/// shadowed by `List.swipeActions`.
struct ItemListView: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    let folder: Folder
    var trashMode: Bool = false

    var body: some View {
        let unfiltered = trashMode
            ? repository.trashItems
            : (repository.items[folder] ?? [])
        let items: [Item] = {
            let filter = panelState.filterProjectIds
            guard !filter.isEmpty else { return unfiltered }
            return unfiltered.filter { filter.contains($0.projectId) }
        }()

        Group {
            if items.isEmpty {
                emptyPlaceholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            RowSwipeContainer(item: item, trashMode: trashMode) {
                                ItemRow(item: item, trashMode: trashMode)
                            }
                            if item.id != items.last?.id {
                                Divider().opacity(0.4)
                                    .padding(.leading, 24)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyPlaceholder: some View {
        Text(trashMode ? "Trash is empty." : "Nothing here.")
            .font(.system(size: theme.bodySize))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
    }
}
