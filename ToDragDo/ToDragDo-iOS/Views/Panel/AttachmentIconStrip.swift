import SwiftUI
import ToDragDoCore

/// A compact horizontal strip of icons summarizing an item's attachments.
/// Verbatim port from the macOS app.
struct AttachmentIconStrip: View {
    let attachments: [Attachment]

    private static let maxIcons = 2

    var body: some View {
        if !attachments.isEmpty {
            let visible = attachments.prefix(Self.maxIcons)
            let overflow = attachments.count - visible.count
            HStack(spacing: 4) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, attachment in
                    Image(systemName: symbol(for: attachment.kind))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color(for: attachment.kind))
                        .frame(width: 16, height: 16)
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 16)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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
