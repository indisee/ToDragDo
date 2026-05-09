import Foundation

/// A single dropped (or pasted) artifact carried by an `Item`.
///
/// Plain Codable struct — Core stays portable, so image bytes live as
/// raw `Data` rather than `NSImage`/`UIImage`. The macOS app target is
/// responsible for translating an `NSItemProvider` into one of these.
public struct Attachment: Sendable, Codable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case text
        case url
        case fileURL
        case image
    }

    public var kind: Kind
    public var text: String?
    public var urlString: String?
    public var fileName: String?
    public var imageData: Data?

    public init(
        kind: Kind,
        text: String? = nil,
        urlString: String? = nil,
        fileName: String? = nil,
        imageData: Data? = nil
    ) {
        self.kind = kind
        self.text = text
        self.urlString = urlString
        self.fileName = fileName
        self.imageData = imageData
    }

    /// `Item.typeIdentifier` to use when this attachment is the item's
    /// primary content. Mirrors the strings `TypeBadge` switches on.
    public var typeIdentifier: String {
        switch kind {
        case .text:    "text/plain"
        case .url:     "url"
        case .fileURL: "file"
        case .image:   "image"
        }
    }

    /// Best-effort one-line label for collapsed list rows / chips.
    public var displayLabel: String {
        switch kind {
        case .text:    text ?? ""
        case .url:     urlString ?? ""
        case .fileURL: fileName ?? urlString ?? ""
        case .image:   fileName ?? "Image"
        }
    }
}
