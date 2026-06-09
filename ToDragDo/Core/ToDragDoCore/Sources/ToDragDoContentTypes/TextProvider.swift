import SwiftUI
import ToDragDoCore

/// Built-in provider for plain text attachments / items.
public final class TextProvider: ContentTypeProvider {
    public nonisolated let identifier = "text/plain"
    public init() {}

    public nonisolated func handles(attachment: Attachment) -> Bool {
        attachment.kind == .text
    }

    public nonisolated func handles(itemTypeIdentifier: String) -> Bool {
        // Plain text is the default — covers anything that isn't one of
        // the other built-ins. The registry stops at the first `true`,
        // so register TextProvider last among the built-ins.
        itemTypeIdentifier == identifier || itemTypeIdentifier.isEmpty
    }

    public nonisolated func badge(forItemTypeIdentifier _: String) -> ContentBadge? {
        ContentBadge(symbol: "=", color: .secondary)
    }

    public nonisolated func chipBadge(for _: Attachment) -> ContentBadge? {
        ContentBadge(symbol: "=", color: .secondary)
    }

    public func fullView(for attachment: Attachment) -> AnyView {
        AnyView(TextPreview(attachment: attachment))
    }
}

private struct TextPreview: View {
    let attachment: Attachment

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            Text(attachment.text ?? "")
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let text = attachment.text, !text.isEmpty {
                Button {
                    PlatformOpen.copyText(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Copy text")
            }
        }
        .padding(8)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}
