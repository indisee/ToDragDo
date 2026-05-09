import AppKit
import Foundation
import UniformTypeIdentifiers
import ToDragDoCore

/// Bridges AppKit's `NSItemProvider` into `Attachment`.
/// Lives in the app target — Core stays Apple-framework-free.
extension Attachment {
    /// Probe a drag's payload in priority order: file URL → web URL →
    /// image → plain text. Returns `nil` if nothing matches.
    static func from(provider: NSItemProvider) async -> Attachment? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(from: provider) {
            return Attachment(
                kind: .fileURL,
                urlString: url.absoluteString,
                fileName: url.lastPathComponent
            )
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(from: provider) {
            return Attachment(kind: .url, urlString: url.absoluteString)
        }
        if provider.canLoadObject(ofClass: NSImage.self),
           let png = await loadImagePNG(from: provider) {
            return Attachment(
                kind: .image,
                fileName: provider.suggestedName ?? "Image",
                imageData: png
            )
        }
        if provider.canLoadObject(ofClass: NSString.self),
           let text = await loadString(from: provider) {
            return Attachment(kind: .text, text: text)
        }
        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                cont.resume(returning: url)
            }
        }
    }

    private static func loadImagePNG(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:])
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: png)
            }
        }
    }

    private static func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                cont.resume(returning: (obj as? NSString) as String?)
            }
        }
    }
}
