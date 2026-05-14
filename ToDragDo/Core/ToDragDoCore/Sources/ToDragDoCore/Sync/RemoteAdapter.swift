import Foundation

public protocol RemoteAdapter: Sendable {
    var providerId: String { get }
    var displayName: String { get }

    /// Push a batch of outbox changes. Returns a per-record outcome so the
    /// coordinator can mark successes and record failures independently.
    /// Throws only on batch-level errors (network, auth, schema) where no
    /// per-record breakdown is available — in that case the coordinator
    /// treats the whole batch as failed.
    func push(_ changes: [ChangeRecord]) async throws -> PushOutcome

    func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor)
}

/// Per-record result of a push call. `succeeded` IDs are safe to
/// `markPushed`; `failed` IDs stay in the outbox and bump their
/// `attemptCount`/`lastError`.
public struct PushOutcome: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let id: UUID
        public let error: String

        public init(id: UUID, error: String) {
            self.id = id
            self.error = error
        }
    }

    public let succeeded: [UUID]
    public let failed: [Failure]

    public init(succeeded: [UUID] = [], failed: [Failure] = []) {
        self.succeeded = succeeded
        self.failed = failed
    }

    public static let empty = PushOutcome()

    public static func allSucceeded(_ ids: [UUID]) -> PushOutcome {
        PushOutcome(succeeded: ids, failed: [])
    }
}
