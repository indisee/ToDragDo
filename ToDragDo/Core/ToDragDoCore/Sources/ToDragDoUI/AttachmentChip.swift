import SwiftUI
import ToDragDoCore

/// Compact representation of a `pendingAttachment` shown inside the
/// `InputBar` while the user types accompanying text.
public struct AttachmentChip: View {
    @Environment(\.theme) private var theme

    let attachment: Attachment
    /// Upper bound for the label, so long URLs collapse into a
    /// `head…tail` form instead of pushing the chip past its container.
    let maxLabelWidth: CGFloat
    let onRemove: () -> Void

    public init(
        attachment: Attachment,
        maxLabelWidth: CGFloat,
        onRemove: @escaping () -> Void
    ) {
        self.attachment = attachment
        self.maxLabelWidth = maxLabelWidth
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 6) {
            TypeBadge(typeIdentifier: attachment.typeIdentifier)
            Text(label)
                .font(.system(size: theme.captionSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: maxLabelWidth, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.captionSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
            .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background.tertiary, in: Capsule())
    }

    private var label: String {
        let raw = attachment.displayLabel
        return raw.isEmpty ? "Attachment" : raw
    }
}
