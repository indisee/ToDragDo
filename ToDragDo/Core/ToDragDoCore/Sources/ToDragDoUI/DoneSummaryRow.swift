import SwiftUI
import ToDragDoCore

/// Row shown above the Done tab's item list. Tapping a pill hands the
/// requested period to the caller, which presents the summary (a window
/// on macOS, a sheet on iOS).
public struct DoneSummaryRow: View {
    @Environment(\.theme) private var theme

    let onOpen: (SummaryMode) -> Void

    public init(onOpen: @escaping (SummaryMode) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
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
                .padding(.horizontal, PlatformMetrics.pillHorizontal)
                .padding(.vertical, PlatformMetrics.pillVertical)
                .foregroundStyle(.primary)
                .background(theme.accent.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
