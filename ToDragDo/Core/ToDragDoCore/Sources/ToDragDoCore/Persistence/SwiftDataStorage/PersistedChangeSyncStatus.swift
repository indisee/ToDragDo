#if canImport(SwiftData)
import Foundation
import SwiftData

@Model
final class PersistedChangeSyncStatus {
    var providerId: String = ""
    var pushedAt: Date?
    var lastAttemptAt: Date?
    var lastError: String?
    var attemptCount: Int = 0

    var change: PersistedChange?

    init(
        providerId: String,
        pushedAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil,
        attemptCount: Int = 0,
        change: PersistedChange? = nil
    ) {
        self.providerId = providerId
        self.pushedAt = pushedAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.attemptCount = attemptCount
        self.change = change
    }

    func toDTO() -> ChangeSyncStatus {
        ChangeSyncStatus(
            changeId: change?.id ?? UUID(),
            providerId: providerId,
            pushedAt: pushedAt,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            attemptCount: attemptCount
        )
    }
}
#endif
