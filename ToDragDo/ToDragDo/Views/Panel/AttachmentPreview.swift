import AppKit
import LinkPresentation
import SwiftUI
import ToDragDoCore

/// Expanded preview for a single attachment.
///
/// - `.image`: rendered bitmap with a click-to-open affordance.
/// - `.url`: fetched title + URL with an open-in-browser button.
/// - `.fileURL` / `.text`: icon + label + an open/reveal button.
struct AttachmentPreview: View {
    @Environment(\.theme) private var theme

    let attachment: Attachment

    var body: some View {
        switch attachment.kind {
        case .image:   ImagePreview(attachment: attachment)
        case .url:     LinkPreview(attachment: attachment)
        case .fileURL: GenericPreview(attachment: attachment, kind: .file)
        case .text:    GenericPreview(attachment: attachment, kind: .text)
        }
    }
}

// MARK: - Image

private struct ImagePreview: View {
    @Environment(\.theme) private var theme
    let attachment: Attachment

    @State private var isHovering = false

    var body: some View {
        Group {
            if let data = attachment.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                    .overlay(alignment: .topTrailing) {
                        if isHovering { openButton }
                    }
                    .onHover { isHovering = $0 }
                    .onTapGesture(perform: openImage)
                    .help("Open image")
            } else {
                Text("Image unavailable")
                    .font(.system(size: theme.captionSize))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var openButton: some View {
        Image(systemName: "arrow.up.right.square.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white, .black.opacity(0.6))
            .padding(6)
    }

    private func openImage() {
        guard let data = attachment.imageData else { return }
        let ext = (attachment.fileName as NSString?)?.pathExtension.nilIfEmpty ?? "png"
        let base = (attachment.fileName as NSString?)?.deletingPathExtension ?? "Image"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6))")
            .appendingPathExtension(ext)
        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            print("AttachmentPreview: failed to open image: \(error)")
        }
    }
}

// MARK: - Link

private struct LinkPreview: View {
    @Environment(\.theme) private var theme
    let attachment: Attachment

    @State private var title: String?
    @State private var didStartFetch = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? host ?? urlString)
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .lineLimit(1)
                Text(urlString)
                    .font(.system(size: theme.captionSize))
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
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .onAppear(perform: fetchTitleIfNeeded)
    }

    private var urlString: String { attachment.urlString ?? "" }
    private var url: URL? { URL(string: urlString) }
    private var host: String? { url?.host }

    private func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
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

// MARK: - Generic (file / text)

private struct GenericPreview: View {
    enum Kind { case file, text }

    @Environment(\.theme) private var theme
    let attachment: Attachment
    let kind: Kind

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            Text(label)
                .font(.system(size: theme.bodySize))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let action = openAction {
                Button(action: action) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(openHelp)
            }
        }
        .padding(8)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }

    private var iconName: String {
        switch kind {
        case .file: "doc"
        case .text: "text.alignleft"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .file: .orange
        case .text: .secondary
        }
    }

    private var label: String {
        switch kind {
        case .file: attachment.fileName ?? attachment.urlString ?? "File"
        case .text: attachment.text ?? ""
        }
    }

    private var openAction: (() -> Void)? {
        switch kind {
        case .file:
            guard let raw = attachment.urlString, let url = URL(string: raw) else { return nil }
            return { NSWorkspace.shared.open(url) }
        case .text:
            guard let text = attachment.text, !text.isEmpty else { return nil }
            return {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
        }
    }

    private var openHelp: String {
        switch kind {
        case .file: "Open file"
        case .text: "Copy text"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
