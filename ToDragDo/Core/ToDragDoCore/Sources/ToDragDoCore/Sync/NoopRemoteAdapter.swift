import Foundation

public struct NoopRemoteAdapter: RemoteAdapter {
    public let providerId: String
    public let displayName: String

    public init(providerId: String = "noop", displayName: String = "No-op") {
        self.providerId = providerId
        self.displayName = displayName
    }

    public func push(_ changes: [ChangeRecord]) async throws {}

    public func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor) {
        ([], cursor)
    }
}
