import SwiftUI
import ToDragDoCore
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Built-in provider for image attachments. Decodes `imageData` into
/// the platform image type and renders it scaled-to-fit with a tap
/// gesture that writes it to a temp file and hands off to the system.
public final class ImageProvider: ContentTypeProvider {
    public nonisolated let identifier = "image"
    public init() {}

    public nonisolated func handles(attachment: Attachment) -> Bool {
        attachment.kind == .image
    }

    public nonisolated func handles(itemTypeIdentifier: String) -> Bool {
        itemTypeIdentifier == identifier
    }

    public nonisolated func badge(forItemTypeIdentifier _: String) -> ContentBadge? {
        ContentBadge(symbol: "■", color: .green)
    }

    public nonisolated func chipBadge(for _: Attachment) -> ContentBadge? {
        ContentBadge(symbol: "■", color: .green)
    }

    public func fullView(for attachment: Attachment) -> AnyView {
        AnyView(ImagePreview(attachment: attachment))
    }
}

private struct ImagePreview: View {
    let attachment: Attachment

    @State private var isHovering = false

    var body: some View {
        Group {
            if let data = attachment.imageData, let image = makePlatformImage(data: data) {
                imageView(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if isHovering { openButton }
                    }
                    #if os(macOS)
                    .onHover { isHovering = $0 }
                    #endif
                    .onTapGesture(perform: openImage)
                    .help("Open image")
            } else {
                Text("Image unavailable")
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

    #if canImport(AppKit)
    private func makePlatformImage(data: Data) -> NSImage? { NSImage(data: data) }
    private func imageView(_ image: NSImage) -> Image { Image(nsImage: image) }
    #elseif canImport(UIKit)
    private func makePlatformImage(data: Data) -> UIImage? { UIImage(data: data) }
    private func imageView(_ image: UIImage) -> Image { Image(uiImage: image) }
    #endif

    private func openImage() {
        guard let data = attachment.imageData else { return }
        let ext = (attachment.fileName as NSString?)?.pathExtension.nilIfEmpty ?? "png"
        let base = (attachment.fileName as NSString?)?.deletingPathExtension ?? "Image"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6))")
            .appendingPathExtension(ext)
        do {
            try data.write(to: url, options: .atomic)
            PlatformOpen.open(url)
        } catch {
            // Keep the swallow behavior macOS had — no crash if /tmp is wedged.
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
