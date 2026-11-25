import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Compact representation of a `pendingAttachment` shown inside the
/// `InputBar` while the user types accompanying text.
struct AttachmentChip: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings

    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TypeBadge(typeIdentifier: attachment.typeIdentifier)
            Text(label)
                .font(.system(size: theme.captionSize))
                .lineLimit(1)
                .truncationMode(.middle)
                // Cap the label width to the available attachment area so
                // long URLs collapse into a `head…tail` form instead of
                // pushing the chip past the panel edge.
                .frame(maxWidth: maxLabelWidth, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.captionSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background.tertiary, in: Capsule())
    }

    private var label: String {
        let raw = attachment.displayLabel
        return raw.isEmpty ? "Attachment" : raw
    }

    /// Reserve room for the panel's outer chrome (panel padding +
    /// InputBar padding) and the chip's own non-text content (badge,
    /// remove button, internal spacing/padding).
    private var maxLabelWidth: CGFloat {
        max(80, settings.panelWidth - 110)
    }
}
