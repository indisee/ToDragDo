import SwiftUI
import ToDragDoCore

/// Invisible drop target placed after the last row in `ItemList`.
/// Lets a drag land "at the end" of the current folder, since `ItemRow`
/// only accepts drops as "place before this row."
struct EndDropZone: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository

    @State private var isTargeted = false

    var body: some View {
        Color.clear
            .frame(height: 14)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if isTargeted {
                    Rectangle()
                        .fill(theme.accent)
                        .frame(height: 2)
                }
            }
            .dropDestination(for: String.self) { droppedIds, _ in
                handleDrop(droppedIds)
            } isTargeted: { isTargeted = $0 }
    }

    private func handleDrop(_ droppedIds: [String]) -> Bool {
        guard let raw = droppedIds.first, let id = UUID(uuidString: raw) else {
            return false
        }
        Task {
            try? await repository.reorder(id: id, before: nil)
        }
        return true
    }
}
