import Foundation

public protocol RemoteAdapter: Sendable {
    var providerId: String { get }
    var displayName: String { get }

    func push(_ changes: [ChangeRecord]) async throws
    func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor)
}
