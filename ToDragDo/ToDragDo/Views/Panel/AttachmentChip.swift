import SwiftUI
import ToDragDoCore

/// Compact representation of a `pendingAttachment` shown inside the
/// `InputBar` while the user types accompanying text.
struct AttachmentChip: View {
    @Environment(\.theme) private var theme

    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TypeBadge(typeIdentifier: attachment.typeIdentifier)
            Text(label)
                .font(.system(size: theme.captionSize))
                .lineLimit(1)
                .truncationMode(.middle)
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
}
