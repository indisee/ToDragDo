import SwiftUI
import ToDragDoCore

/// Horizontal tab strip below the input. Drives `PanelState.selectedFolder`.
struct FolderTabBar: View {
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Folder.allCases, id: \.self) { folder in
                FolderTab(
                    folder: folder,
                    isSelected: folder == panelState.selectedFolder,
                    count: count(for: folder),
                    action: { panelState.selectedFolder = folder }
                )
            }
        }
    }

    private func count(for folder: Folder) -> Int? {
        repository.items[folder]?.count
    }
}
