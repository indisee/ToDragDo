import SwiftUI
import ToDragDoCore

/// Lists items for the currently-selected folder.
/// Pagination at 10/page lands in a follow-up round.
struct ItemList: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    var body: some View {
        let items = repository.items[panelState.selectedFolder] ?? []
        if items.isEmpty {
            emptyPlaceholder
        } else {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    ItemRow(item: item)
                    if item.id != items.last?.id {
                        Divider().opacity(0.4)
                    }
                }
                EndDropZone()
            }
        }
    }

    private var emptyPlaceholder: some View {
        Text("Nothing here.")
            .font(.system(size: theme.captionSize))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }
}
