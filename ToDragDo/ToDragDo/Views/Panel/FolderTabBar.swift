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
        // Recompute staleness once per render — TimelineView keeps the
        // Limbo badge in sync with wall-clock time even when nothing else
        // in the panel changes, so items cross the threshold without
        // requiring a panel toggle.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let limboItems = repository.items[.libmo] ?? []
            let filter = panelState.filterProjectIds
            let limboBlinks = LimboStaleness.anyStale(
                in: filter.isEmpty ? limboItems : limboItems.filter { filter.contains($0.projectId) },
                threshold: settings.limboBlinkDays,
                now: now
            )
            HStack(spacing: 4) {
                ForEach(Folder.allCases, id: \.self) { folder in
                    FolderTab(
                        folder: folder,
                        // In trash mode the tab bar acts as a restore target
                        // picker (drag) and a navigation control (click), so
                        // no single tab is "the current view".
                        isSelected: !panelState.isTrashOpen
                            && folder == panelState.selectedFolder,
                        count: count(for: folder),
                        isCompact: settings.panelWidth < Self.compactThreshold,
                        blinkBadge: folder == .libmo && limboBlinks,
                        action: {
                            // Close trash explicitly: when the user is in
                            // trash and clicks the tab they came from, the
                            // selectedFolder value doesn't change and its
                            // didSet (which would otherwise close trash)
                            // never fires.
                            panelState.isTrashOpen = false
                            panelState.selectedFolder = folder
                        }
                    )
                }
            }
        }
    }

    private func count(for folder: Folder) -> Int? {
        guard let items = repository.items[folder] else { return nil }
        let filter = panelState.filterProjectIds
        guard !filter.isEmpty else { return items.count }
        return items.lazy.filter { filter.contains($0.projectId) }.count
    }
}
