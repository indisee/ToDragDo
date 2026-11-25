import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Row shown above the Done tab's item list. Tapping a pill opens the
/// Done-summary sheet anchored on the requested period.
struct DoneSummaryRow: View {
    @Environment(\.theme) private var theme

    /// Caller owns the presentation — when a pill is tapped we hand back
    /// the requested mode and the FolderTabView raises the sheet.
    let onOpen: (SummaryMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            pill("Today") { onOpen(.day) }
            pill("Week") { onOpen(.week) }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func pill(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: theme.captionSize, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.primary)
                .background(theme.accent.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
