import Foundation

/// Per-provider push state for a single ChangeRecord.
/// Identity is the composite (changeId, providerId).
public struct ChangeSyncStatus: Sendable, Codable, Hashable, Identifiable {
    public let changeId: UUID
    public let providerId: String
    public var pushedAt: Date?
    public var lastAttemptAt: Date?
    public var lastError: String?
    public var attemptCount: Int

    public var id: String { "\(changeId.uuidString):\(providerId)" }

    public init(
        changeId: UUID,
        providerId: String,
        pushedAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil,
        attemptCount: Int = 0
    ) {
        self.changeId = changeId
        self.providerId = providerId
        self.pushedAt = pushedAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.attemptCount = attemptCount
    }

    public var isPushed: Bool { pushedAt != nil }
}
