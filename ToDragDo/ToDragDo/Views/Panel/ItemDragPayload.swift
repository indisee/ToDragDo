import Foundation
import UniformTypeIdentifiers

/// In-app item drags use a URL with a custom scheme rather than a
/// custom UTType, because custom UTTypes need to be declared in
/// Info.plist to be properly registered with AppKit's drop system.
/// `URL` is a built-in `Transferable`, so SwiftUI's `.draggable(URL)`
/// + receivers registering `.url` work without any project config.
///
/// Receivers detect an internal drag by inspecting the URL scheme.
enum ItemDragURL {
    static let scheme = "todragdo"
    static let host = "item"

    static func url(for id: UUID) -> URL {
        URL(string: "\(scheme)://\(host)/\(id.uuidString)")!
    }

    /// Parses an internal item-drag URL. Returns `nil` for any URL
    /// that isn't ours — including all external URLs (browser links,
    /// file URLs).
    static func itemID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let last = url.lastPathComponent
        return UUID(uuidString: last)
    }

    /// Async-loads a URL from the provider and returns its item id if
    /// it's an internal drag.
    static func itemID(from provider: NSItemProvider) async -> UUID? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }
        let url: URL? = await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                cont.resume(returning: url)
            }
        }
        guard let url else { return nil }
        return itemID(from: url)
    }
}
