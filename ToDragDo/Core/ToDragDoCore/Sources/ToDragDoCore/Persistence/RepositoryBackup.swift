import Foundation

/// JSON-serializable snapshot of all local data, written before risky
/// operations such as the Development → Production CloudKit migration.
/// Independent of the SwiftData schema, so it stays readable even if the
/// store format changes.
public struct RepositoryBackup: Codable, Sendable {
    public var formatVersion: Int = 1
    public var createdAt: Date
    public var deviceId: String
    public var items: [Item]
    public var projects: [Project]

    public init(createdAt: Date, deviceId: String, items: [Item], projects: [Project]) {
        self.createdAt = createdAt
        self.deviceId = deviceId
        self.items = items
        self.projects = projects
    }

    public var isEmpty: Bool { items.isEmpty && projects.isEmpty }

    /// Pretty-printed JSON with ISO-8601 dates.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> RepositoryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RepositoryBackup.self, from: data)
    }

    /// Writes the backup into `directory` (created if needed) as
    /// `<prefix>-<timestamp>.json` and returns the file URL.
    @discardableResult
    public func write(to directory: URL, prefix: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let url = directory.appendingPathComponent("\(prefix)-\(formatter.string(from: createdAt)).json")
        try encoded().write(to: url, options: .atomic)
        return url
    }
}
