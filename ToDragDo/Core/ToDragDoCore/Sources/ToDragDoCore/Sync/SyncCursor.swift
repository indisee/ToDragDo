import Foundation

public struct SyncCursor: Codable, Sendable, Equatable, Hashable {
    public var ts: Date?
    public var token: String?

    public init(ts: Date? = nil, token: String? = nil) {
        self.ts = ts
        self.token = token
    }

    public static let initial = SyncCursor()
}
