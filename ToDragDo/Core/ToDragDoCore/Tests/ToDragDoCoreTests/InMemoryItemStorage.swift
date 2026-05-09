import Foundation
@testable import ToDragDoCore

actor InMemoryItemStorage: ItemStorage {
    private var items: [UUID: Item] = [:]
    private var changes: [UUID: ChangeRecord] = [:]
    /// Nested map: changeId -> providerId -> ChangeSyncStatus
    private var statuses: [UUID: [String: ChangeSyncStatus]] = [:]

    // MARK: - Items

    func items(in folder: Folder, includeDeleted: Bool) async throws -> [Item] {
        items.values
            .filter { $0.folder == folder && (includeDeleted || $0.deletedAt == nil) }
            .sorted { $0.orderKey < $1.orderKey }
    }

    func item(id: UUID) async throws -> Item? {
        items[id]
    }

    func upsert(_ item: Item, change: ChangeRecord) async throws {
        items[item.id] = item
        changes[change.id] = change
    }

    func softDelete(id: UUID, at deletedAt: Date, change: ChangeRecord) async throws {
        guard var existing = items[id] else { return }
        existing.deletedAt = deletedAt
        existing.updatedAt = deletedAt
        items[id] = existing
        changes[change.id] = change
    }

    func hardDelete(folder: Folder, changes incoming: [ChangeRecord]) async throws {
        let toRemove = items.values.filter { $0.folder == folder }.map(\.id)
        for id in toRemove { items.removeValue(forKey: id) }
        for change in incoming { changes[change.id] = change }
    }

    // MARK: - Outbox

    func pendingChanges(for providerId: String, limit: Int) async throws -> [ChangeRecord] {
        changes.values
            .filter { isPending(changeId: $0.id, providerId: providerId) }
            .sorted { $0.ts < $1.ts }
            .prefix(limit)
            .map { $0 }
    }

    func pendingPushCount(for providerId: String) async throws -> Int {
        changes.values.lazy.filter { self.isPending(changeId: $0.id, providerId: providerId) }.count
    }

    func markPushed(_ ids: [UUID], to providerId: String, at: Date) async throws {
        for id in ids {
            guard changes[id] != nil else { continue }
            var perProvider = statuses[id] ?? [:]
            var status = perProvider[providerId] ?? ChangeSyncStatus(changeId: id, providerId: providerId)
            status.pushedAt = at
            status.lastAttemptAt = at
            status.lastError = nil
            perProvider[providerId] = status
            statuses[id] = perProvider
        }
    }

    func recordPushFailure(_ ids: [UUID], to providerId: String, error: String, at: Date) async throws {
        for id in ids {
            guard changes[id] != nil else { continue }
            var perProvider = statuses[id] ?? [:]
            var status = perProvider[providerId] ?? ChangeSyncStatus(changeId: id, providerId: providerId)
            status.lastAttemptAt = at
            status.lastError = error
            status.attemptCount += 1
            perProvider[providerId] = status
            statuses[id] = perProvider
        }
    }

    func syncStatus(forChange changeId: UUID, providerId: String) async throws -> ChangeSyncStatus? {
        statuses[changeId]?[providerId]
    }

    // MARK: - Test helpers

    func allChanges() -> [ChangeRecord] {
        changes.values.sorted { $0.ts < $1.ts }
    }

    func itemCount() -> Int { items.count }

    func allStatuses(forChange changeId: UUID) -> [ChangeSyncStatus] {
        statuses[changeId]?.values.map { $0 } ?? []
    }

    // MARK: - Private

    private func isPending(changeId: UUID, providerId: String) -> Bool {
        guard let status = statuses[changeId]?[providerId] else { return true }
        return status.pushedAt == nil
    }
}
