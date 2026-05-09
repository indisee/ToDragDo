import SwiftUI
import UniformTypeIdentifiers
import ToDragDoCore

/// Invisible drop target placed after the last row in `ItemList`.
/// Lets a drag land "at the end" of the current folder, since `ItemRow`
/// only accepts drops as "place before this row."
struct EndDropZone: View {
    /// Vertical footprint of the drop zone. Exposed so callers can
    /// reserve the same slot when the zone itself is omitted (e.g. on
    /// intermediate pages of a paginated list).
    static let reservedHeight: CGFloat = 14

    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository

    @State private var isTargeted = false

    var body: some View {
        Color.clear
            .frame(height: Self.reservedHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if isTargeted {
                    Rectangle()
                        .fill(theme.accent)
                        .frame(height: 2)
                }
            }
            .onDrop(of: [.url], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task { @MainActor in
            guard let id = await ItemDragURL.itemID(from: provider) else { return }
            try? await repository.reorder(id: id, before: nil)
        }
        return true
    }
}
