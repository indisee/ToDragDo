import SwiftUI
import ToDragDoCore

/// A compact horizontal strip of icons summarizing an item's attachments.
/// One small SF Symbol per attachment, color-keyed to its kind.
struct AttachmentIconStrip: View {
    let attachments: [Attachment]

    var body: some View {
        if !attachments.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                    Image(systemName: symbol(for: attachment.kind))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color(for: attachment.kind))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
        }
    }

    private func symbol(for kind: Attachment.Kind) -> String {
        switch kind {
        case .image:   "photo"
        case .url:     "link"
        case .fileURL: "doc"
        case .text:    "text.alignleft"
        }
    }

    private func color(for kind: Attachment.Kind) -> Color {
        switch kind {
        case .image:   .green
        case .url:     .blue
        case .fileURL: .orange
        case .text:    .secondary
        }
    }
}
