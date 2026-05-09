import SwiftUI
import ToDragDoCore

/// Inline caption shown next to `CollapseChevron` when the list is
/// minimized. The chevron button itself communicates the action, so
/// this is just a status label.
struct CollapsedCaption: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    var body: some View {
        Text("\(count) items in \(folderName)")
            .font(.system(size: theme.captionSize))
            .foregroundStyle(.secondary)
    }

    private var count: Int {
        repository.items[panelState.selectedFolder]?.count ?? 0
    }

    private var folderName: String {
        switch panelState.selectedFolder {
        case .today:    return "Today"
        case .tomorrow: return "Tomorrow"
        case .libmo:    return "Limbo"
        case .done:     return "Done"
        }
    }
}
