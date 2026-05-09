import SwiftUI
import UniformTypeIdentifiers
import ToDragDoCore

/// A single folder tab in the FolderTabBar.
///
/// Tapping switches to the folder; dropping an item-drag URL onto it
/// moves the item to that folder.
struct FolderTab: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    let folder: Folder
    let isSelected: Bool
    let count: Int?
    let isCompact: Bool
    let action: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !isCompact {
                    Text(folder.displayName)
                        .font(.system(size: theme.captionSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(isSelected ? 1 : 0)
                }
                Text("\(count ?? 0)")
                    .font(.system(size: theme.captionSize - 1, weight: .bold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        isSelected ? theme.accent : theme.accent.opacity(0.12),
                        in: Capsule()
                    )
                    .accessibilityLabel(folder.displayName)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.primary : .secondary)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.url], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var background: Color {
        if isDropTargeted { return theme.accent.opacity(0.25) }
        if isSelected     { return theme.accent.opacity(0.12) }
        return .clear
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task { @MainActor in
            guard let id = await ItemDragURL.itemID(from: provider) else { return }
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
