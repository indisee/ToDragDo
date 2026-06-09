import Foundation

/// Portable, framework-free wrapper around a single dropped/pasted item's
/// bytes plus the UTType identifiers the platform advertised it as.
///
/// `NSItemProvider` and `UIDropSession` produce platform types that don't
/// cross targets cleanly. Hosts convert their platform handle into a
/// `DropPayload` at the boundary; from there everything downstream
/// (attachment conversion, provider routing, share-extension import) is
/// the same on macOS and iOS.
public struct DropPayload: Sendable, Hashable {
    /// Raw bytes for the payload's primary representation. Empty for
    /// reference-only payloads such as a file URL the host hasn't read
    /// yet — consult `fileURL` / `urlString` in that case.
    public var data: Data

    /// UTType identifier strings the platform advertised, in the order
    /// reported. Providers match on the first one they recognize.
    public var typeIdentifiers: [String]

    /// Optional file URL when the payload represents a file the host has
    /// promised on-disk. `data` may still be populated with the loaded
    /// contents; both can coexist.
    public var fileURL: URL?

    /// Optional canonical URL string for link-style payloads (e.g. a
    /// Safari share that produced a `public.url`).
    public var urlString: String?

    /// Optional plain-text representation when the host already decoded
    /// the bytes (saves providers from re-doing it for `public.text`).
    public var text: String?

    /// Optional display name for files / images.
    public var suggestedFileName: String?

    public init(
        data: Data = Data(),
        typeIdentifiers: [String] = [],
        fileURL: URL? = nil,
        urlString: String? = nil,
        text: String? = nil,
        suggestedFileName: String? = nil
    ) {
        self.data = data
        self.typeIdentifiers = typeIdentifiers
        self.fileURL = fileURL
        self.urlString = urlString
        self.text = text
        self.suggestedFileName = suggestedFileName
    }
}
