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

    func trashItems(since: Date) async throws -> [Item] {
        items.values
            .filter { ($0.deletedAt ?? .distantPast) >= since }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
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

    func hardDeleteItem(id: UUID, change: ChangeRecord) async throws {
        items.removeValue(forKey: id)
        changes[change.id] = change
    }

    func allItems() async throws -> [Item] {
        Array(items.values)
    }

    func purgeTrash(before: Date, changes incoming: [ChangeRecord]) async throws {
        let toRemove = items.values
            .filter { ($0.deletedAt ?? .distantFuture) < before }
            .map(\.id)
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

    func appendChanges(_ incoming: [ChangeRecord]) async throws {
        for change in incoming {
            changes[change.id] = change
        }
    }

    // MARK: - Remote apply (no outbox row)

    func upsertWithoutChange(_ item: Item) async throws {
        if let existing = items[item.id], existing.updatedAt >= item.updatedAt { return }
        items[item.id] = item
    }

    func softDeleteWithoutChange(id: UUID, at deletedAt: Date) async throws {
        guard var existing = items[id] else { return }
        if existing.updatedAt > deletedAt { return }
        existing.deletedAt = deletedAt
        existing.updatedAt = deletedAt
        items[id] = existing
    }

    func hardDeleteWithoutChange(id: UUID) async throws {
        items.removeValue(forKey: id)
    }

    // MARK: - Projects

    private var projectStore: [UUID: Project] = [:]

    func projects() async throws -> [Project] {
        projectStore.values.sorted { $0.orderKey < $1.orderKey }
    }

    func upsertProject(_ project: Project) async throws {
        projectStore[project.id] = project
    }

    func deleteProject(id: UUID, reassignTo: UUID) async throws {
        guard id != reassignTo else { return }
        for (itemId, var item) in items where item.projectId == id {
            item.projectId = reassignTo
            item.updatedAt = .now
            items[itemId] = item
        }
        projectStore.removeValue(forKey: id)
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
