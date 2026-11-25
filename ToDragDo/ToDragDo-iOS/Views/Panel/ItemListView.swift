import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Lists items for the given folder. iOS replacement for the macOS
/// `ItemList` — drops pagination, missing-rows spacer, footer settings
/// menu, and the EndDropZone.
///
/// Uses `List(.plain)` instead of `ScrollView { LazyVStack }`. Multiple
/// SwiftUI perf guides agree: LazyVStack realises rows lazily but never
/// releases them — every off-screen row stays in memory, and per-row
/// UIKit objects (`HorizontalPanGesture`'s `UIPanGestureRecognizer`,
/// `.draggable` interactions) accumulate the longer the user scrolls,
/// driving stutter that scales with item count. `List` recycles cells
/// like `UITableView`, capping the live-row count at roughly the visible
/// window.
///
/// The original Phase 2 plan rejected `List` to avoid `.swipeActions`
/// shadowing the two-phased swipe — but our swipe runs through a
/// `UIGestureRecognizerRepresentable`, not SwiftUI's swipe API, so the
/// concern doesn't apply.
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

        if items.isEmpty {
            emptyPlaceholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(items) { item in
                    RowSwipeContainer(item: item, trashMode: trashMode) {
                        ItemRow(item: item, trashMode: trashMode)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .overlay(alignment: .bottom) {
                        if item.id != items.last?.id {
                            Divider()
                                .opacity(0.4)
                                .padding(.leading, 24)
                        }
                    }
                }
                .onMove(perform: trashMode ? nil : { source, destination in
                    handleMove(items: items, source: source, destination: destination)
                })
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// Translates SwiftUI's `(IndexSet, Int)` move semantics into a
    /// `Repository.reorder(id:before:)` call. `destination` is the
    /// pre-removal index where the item should land; the item ends up
    /// immediately before `items[destination]`, or at the end if
    /// `destination == items.count`. Single-item moves only.
    private func handleMove(items: [Item], source: IndexSet, destination: Int) {
        guard source.count == 1, let from = source.first else { return }
        let movingItem = items[from]
        let beforeId: UUID? = destination < items.count ? items[destination].id : nil
        Task { @MainActor in
            try? await repository.reorder(id: movingItem.id, before: beforeId)
        }
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
