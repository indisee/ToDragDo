import SwiftUI

/// Standalone chevron button that toggles `PanelState.isListCollapsed`.
/// Kept outside `InputBar` so the input's visual treatment isn't affected
/// by collapsed state.
struct CollapseChevron: View {
    @Environment(\.theme) private var theme
    @Environment(PanelState.self) private var panelState

    var body: some View {
        Button(action: toggle) {
            Image(systemName: panelState.isListCollapsed
                  ? "chevron.down"
                  : "chevron.up")
                .font(.system(size: theme.captionSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(panelState.isListCollapsed ? "Expand list" : "Collapse list")
    }

    private func toggle() {
        panelState.isListCollapsed.toggle()
    }
}
