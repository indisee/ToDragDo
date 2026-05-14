import Foundation

/// Per-provider sync state published by `SyncCoordinator`. UI binds to a
/// `[SyncStatus]` and renders one row per registered adapter.
public struct SyncStatus: Sendable, Identifiable, Hashable {
    public var id: String { providerId }
    public let providerId: String
    public let displayName: String
    public var enabled: Bool
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var lastError: String?
    public var pendingPushCount: Int

    public init(
        providerId: String,
        displayName: String,
        enabled: Bool = false,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        lastError: String? = nil,
        pendingPushCount: Int = 0
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.enabled = enabled
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.lastError = lastError
        self.pendingPushCount = pendingPushCount
    }
}
