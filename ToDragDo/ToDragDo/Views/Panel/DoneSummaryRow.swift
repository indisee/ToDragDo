import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Row shown below the folder tabs and above the item list when the Done
/// tab is selected. Opens a `SummaryWindow` in the requested mode.
struct DoneSummaryRow: View {
    @Environment(\.theme) private var theme
    @Environment(PanelController.self) private var panelController

    var body: some View {
        HStack(spacing: 6) {
            pill("Today") { panelController.showSummary(mode: .day) }
            pill("Week") { panelController.showSummary(mode: .week) }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func pill(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: theme.captionSize, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.primary)
                .background(theme.accent.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
