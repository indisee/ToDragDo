import Foundation

public protocol ItemStorage: Sendable {
    // MARK: - Items

    func items(in folder: Folder, includeDeleted: Bool) async throws -> [Item]
    func item(id: UUID) async throws -> Item?

    /// All soft-deleted items whose `deletedAt >= since`, across folders.
    /// Backs the hidden Trash view; older items are eligible for purge.
    func trashItems(since: Date) async throws -> [Item]

    func upsert(_ item: Item, change: ChangeRecord) async throws
    func softDelete(id: UUID, at deletedAt: Date, change: ChangeRecord) async throws
    func hardDelete(folder: Folder, changes: [ChangeRecord]) async throws
    func hardDeleteItem(id: UUID, change: ChangeRecord) async throws
    /// Hard-deletes soft-deleted items whose `deletedAt < before`.
    func purgeTrash(before: Date, changes: [ChangeRecord]) async throws

    /// Every item in the store including soft-deleted ones. Backs the
    /// "Re-sync everything to iCloud" path, where the caller needs the
    /// current state of every row to emit fresh outbox entries.
    func allItems() async throws -> [Item]

    // MARK: - Outbox (per-provider)

    /// Returns ChangeRecords that have not yet been successfully pushed to `providerId`.
    /// "Not pushed" = no `ChangeSyncStatus` row for the provider, OR a row with `pushedAt == nil`.
    func pendingChanges(for providerId: String, limit: Int) async throws -> [ChangeRecord]

    /// Count of pending changes for `providerId` (used by Settings UI).
    func pendingPushCount(for providerId: String) async throws -> Int

    /// Marks each id as successfully pushed to `providerId` at `at`.
    /// Upserts a `ChangeSyncStatus` row; clears any prior `lastError`.
    func markPushed(_ ids: [UUID], to providerId: String, at: Date) async throws

    /// Records a failed push attempt for each id: bumps `attemptCount`,
    /// stores `lastError` and `lastAttemptAt`, leaves `pushedAt` untouched.
    func recordPushFailure(_ ids: [UUID], to providerId: String, error: String, at: Date) async throws

    /// Reads the sync status for one (change × provider) pair, if any exists.
    func syncStatus(forChange changeId: UUID, providerId: String) async throws -> ChangeSyncStatus?

    /// Append outbox change rows without touching the item table. Used by
    /// the "Re-sync everything" path to enqueue current-state snapshots
    /// after switching CloudKit environments — the items themselves
    /// haven't changed, only their pushed-to-provider state needs to.
    func appendChanges(_ changes: [ChangeRecord]) async throws

    // MARK: - Remote apply (no outbox row)

    /// Apply a remotely-originated insert/update without appending an outbox
    /// row. Implementations resolve concurrent edits last-write-wins on
    /// `updatedAt`: if the existing row's `updatedAt >= item.updatedAt`,
    /// the incoming write is dropped.
    func upsertWithoutChange(_ item: Item) async throws

    /// Remote-originated soft delete; no outbox row. LWW on `updatedAt`: if
    /// the local row has a newer `updatedAt`, drop.
    func softDeleteWithoutChange(id: UUID, at deletedAt: Date) async throws

    /// Remote-originated hard delete; no outbox row. Always wins.
    func hardDeleteWithoutChange(id: UUID) async throws

    // MARK: - Projects

    /// All projects sorted by `orderKey` ascending.
    func projects() async throws -> [Project]

    /// Inserts or updates a project row. No outbox row — project entities
    /// aren't synced (yet); items reference projects by id, and unknown
    /// ids resolve to Work at the Repository layer.
    func upsertProject(_ project: Project) async throws

    /// Removes a project row. Items previously assigned to it are
    /// reassigned to `reassignTo` in the same transaction. The two ids
    /// must differ.
    func deleteProject(id: UUID, reassignTo: UUID) async throws
}

public enum StorageError: Error, Sendable, Equatable {
    case unsupportedPlatform(Platform)
    case notFound(UUID)
}
