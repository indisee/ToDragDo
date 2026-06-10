import Foundation
import ToDragDoCore

/// `todragdo://` URL routes fired by widget taps. Centralized so the
/// widget extension's `Link(destination:)` calls and the host app's
/// `.onOpenURL` parser stay in sync — change a route here, both sides
/// follow.
public enum DeepLink {
    case input(folder: Folder)
    case item(id: UUID)

    public static let scheme = "todragdo"

    /// Builds the URL the widget hands to `Link(destination:)`.
    public static func inputURL(folder: Folder) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "input"
        components.queryItems = [URLQueryItem(name: "folder", value: folder.rawValue)]
        return components.url ?? URL(string: "\(Self.scheme)://input")!
    }

    public static func itemURL(id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "item"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url ?? URL(string: "\(Self.scheme)://item")!
    }

    /// Parses an incoming URL. Returns `nil` for anything we don't know
    /// — silently dropping unknown routes is fine for v1 since the URL
    /// scheme is private to our own widgets.
    public init?(url: URL) {
        guard url.scheme == DeepLink.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.host {
        case "input":
            let raw = components.queryItems?.first(where: { $0.name == "folder" })?.value
            let folder = Folder(rawValue: raw ?? "") ?? .today
            self = .input(folder: folder)
        case "item":
            guard let raw = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let id = UUID(uuidString: raw) else { return nil }
            self = .item(id: id)
        default:
            return nil
        }
    }
}
