import SwiftUI
import ToDragDoCore

/// Horizontal tab strip below the input. Drives `PanelState.selectedFolder`.
struct FolderTabBar: View {
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(AppSettings.self) private var settings

    /// Below this width, folder tabs collapse to count-only chips so the
    /// strip still fits without clipping. Roughly the point at which all
    /// four full-name tabs stop fitting next to the chevron.
    private static let compactThreshold: CGFloat = 400

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Folder.allCases, id: \.self) { folder in
                FolderTab(
                    folder: folder,
                    isSelected: folder == panelState.selectedFolder,
                    count: count(for: folder),
                    isCompact: settings.panelWidth < Self.compactThreshold,
                    action: { panelState.selectedFolder = folder }
                )
            }
        }
    }

    private func count(for folder: Folder) -> Int? {
        repository.items[folder]?.count
    }
}
