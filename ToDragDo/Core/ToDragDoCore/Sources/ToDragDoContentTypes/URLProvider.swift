import LinkPresentation
import SwiftUI
import ToDragDoCore

/// Built-in provider for URL attachments. Fetches `LPMetadataProvider`
/// title on first show; renders a card with title + open button.
public final class URLProvider: ContentTypeProvider {
    public nonisolated let identifier = "url"
    public init() {}

    public nonisolated func handles(attachment: Attachment) -> Bool {
        attachment.kind == .url
    }

    public nonisolated func handles(itemTypeIdentifier: String) -> Bool {
        itemTypeIdentifier == identifier
    }

    public nonisolated func badge(forItemTypeIdentifier _: String) -> ContentBadge? {
        ContentBadge(symbol: "0", color: .blue)
    }

    public nonisolated func chipBadge(for _: Attachment) -> ContentBadge? {
        ContentBadge(symbol: "0", color: .blue)
    }

    public func fullView(for attachment: Attachment) -> AnyView {
        AnyView(LinkPreview(attachment: attachment))
    }
}

private struct LinkPreview: View {
    let attachment: Attachment

    @State private var title: String?
    @State private var didStartFetch = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? host ?? urlString)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Button(action: open) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Open in browser")
        }
        .padding(8)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: fetchTitleIfNeeded)
    }

    private var urlString: String { attachment.urlString ?? "" }
    private var url: URL? { URL(string: urlString) }
    private var host: String? { url?.host }

    private func open() {
        guard let url else { return }
        PlatformOpen.open(url)
    }

    private func fetchTitleIfNeeded() {
        guard !didStartFetch, title == nil, let url else { return }
        didStartFetch = true
        let provider = LPMetadataProvider()
        provider.timeout = 6
        provider.startFetchingMetadata(for: url) { metadata, _ in
            guard let fetched = metadata?.title, !fetched.isEmpty else { return }
            DispatchQueue.main.async { title = fetched }
        }
    }
}
