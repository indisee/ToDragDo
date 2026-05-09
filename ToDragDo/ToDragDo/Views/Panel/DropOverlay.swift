import SwiftUI

/// Reusable visual treatment for an active drop target.
/// Matches the design's dashed accent border + centered label.
///
/// `isHighlighted` indicates that the cursor is currently over this
/// specific target (vs another target on the same panel) — used by
/// row-style targets to distinguish "you're hovering me" from
/// "a drag is happening somewhere".
struct DropOverlay: View {
    @Environment(\.theme) private var theme

    let label: String
    let icon: String
    let isHighlighted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.accent.opacity(isHighlighted ? 0.14 : 0.06))
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .strokeBorder(
                    theme.accent.opacity(isHighlighted ? 1 : 0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: theme.bodySize, weight: .medium))
                Text(label)
                    .font(.system(size: theme.bodySize, weight: .semibold))
            }
            .foregroundStyle(theme.accent)
        }
        .animation(.easeInOut(duration: 0.12), value: isHighlighted)
    }
}
