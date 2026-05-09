import Foundation

/// Wire format for `Item.payload`. Combines a free-form `note` with a
/// list of attachments so a single item can be "text + dropped link",
/// "image with caption", "task with two screenshots", etc.
public struct ItemPayload: Sendable, Codable, Hashable {
    public var note: String
    public var attachments: [Attachment]

    public init(note: String = "", attachments: [Attachment] = []) {
        self.note = note
        self.attachments = attachments
    }

    /// Convenience for the "new item with at most one attachment" case
    /// that the input bar produces.
    public init(note: String, attachment: Attachment?) {
        self.note = note
        self.attachments = attachment.map { [$0] } ?? []
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decode JSON payload, falling back to "raw UTF-8 in `note`" so any
    /// items written before this format existed still render.
    public static func decode(_ data: Data) -> ItemPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let payload = try? decoder.decode(ItemPayload.self, from: data) {
            return payload
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return ItemPayload(note: raw)
    }

    private enum CodingKeys: String, CodingKey {
        case note
        case attachments
        // Legacy: payloads written before multi-attachment used a singular key.
        case attachment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.note = (try? c.decode(String.self, forKey: .note)) ?? ""
        if let arr = try? c.decode([Attachment].self, forKey: .attachments) {
            self.attachments = arr
        } else if let single = try c.decodeIfPresent(Attachment.self, forKey: .attachment) {
            self.attachments = [single]
        } else {
            self.attachments = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(note, forKey: .note)
        try c.encode(attachments, forKey: .attachments)
    }
}
