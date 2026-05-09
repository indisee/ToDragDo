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
           let url = await loadURL(from: provider, type: .fileURL) {
            return Attachment(
                kind: .fileURL,
                urlString: url.absoluteString,
                fileName: url.lastPathComponent
            )
        }
        if let url = await loadAnyWebURL(from: provider) {
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

    /// Combines the `.url` UTType path with a text-fallback path. Safari's
    /// address-bar drag advertises `public.url` on most macOS versions,
    /// but on some installs it only carries the URL as `public.utf8-plain-text`
    /// — `loadObject(ofClass: URL.self)` then resumes with `nil`. Probing
    /// the text payload and re-parsing it as a URL covers that case.
    private static func loadAnyWebURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(from: provider, type: .url) {
            return url
        }
        if provider.canLoadObject(ofClass: NSString.self),
           let text = await loadString(from: provider) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed),
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "ftp"].contains(scheme) {
                return url
            }
        }
        return nil
    }

    /// Two-step URL extraction. `loadObject(ofClass: URL.self)` is the
    /// happy path, but some browsers vend a provider where it resumes
    /// with `nil` even though the URL UTType is conformed to. In that
    /// case fall back to the raw data representation, which is how
    /// `kPasteboardTypeFileURLPromise`-style payloads arrive.
    private static func loadURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        if let url: URL = await withCheckedContinuation({ cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                cont.resume(returning: url)
            }
        }) {
            return url
        }
        return await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    cont.resume(returning: nil)
                    return
                }
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
