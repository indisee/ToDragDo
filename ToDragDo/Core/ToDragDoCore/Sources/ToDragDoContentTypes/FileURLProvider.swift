import SwiftUI
import ToDragDoCore

/// Built-in provider for file URL attachments.
public final class FileURLProvider: ContentTypeProvider {
    public nonisolated let identifier = "file"
    public init() {}

    public nonisolated func handles(attachment: Attachment) -> Bool {
        attachment.kind == .fileURL
    }

    public nonisolated func handles(itemTypeIdentifier: String) -> Bool {
        itemTypeIdentifier == identifier
    }

    public nonisolated func badge(forItemTypeIdentifier _: String) -> ContentBadge? {
        ContentBadge(symbol: "▤", color: .orange)
    }

    public nonisolated func chipBadge(for _: Attachment) -> ContentBadge? {
        ContentBadge(symbol: "▤", color: .orange)
    }

    public func fullView(for attachment: Attachment) -> AnyView {
        AnyView(FilePreview(attachment: attachment))
    }
}

private struct FilePreview: View {
    let attachment: Attachment

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            Text(label)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let action = openAction {
                Button(action: action) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Open file")
            }
        }
        .padding(8)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var label: String {
        attachment.fileName ?? attachment.urlString ?? "File"
    }

    private var openAction: (() -> Void)? {
        guard let raw = attachment.urlString, let url = URL(string: raw) else { return nil }
        return { PlatformOpen.open(url) }
    }
}
