import SwiftUI
import ToDragDoCore

/// A single folder tab in the FolderTabBar.
///
/// Tapping switches to the folder; dropping an item drag onto it moves
/// the item to that folder.
struct FolderTab: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    let folder: Folder
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(folder.displayName)
                    .font(.system(size: theme.captionSize, weight: .semibold))
                if let count, isSelected {
                    Text("\(count)")
                        .font(.system(size: theme.captionSize - 1, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.primary : .secondary)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { droppedIds, _ in
            handleDrop(droppedIds)
        } isTargeted: { isDropTargeted = $0 }
    }

    private var background: Color {
        if isDropTargeted { return theme.accent.opacity(0.25) }
        if isSelected     { return theme.accent.opacity(0.12) }
        return .clear
    }

    private func handleDrop(_ droppedIds: [String]) -> Bool {
        guard let raw = droppedIds.first, let id = UUID(uuidString: raw) else {
            return false
        }
        Task {
            try? await repository.move(id: id, to: folder)
        }
        return true
    }
}

private extension Folder {
    var displayName: LocalizedStringKey {
        switch self {
        case .today:    "Today"
        case .tomorrow: "Tomorrow"
        case .libmo:    "Limbo"
        case .done:     "Done"
        }
    }
}
