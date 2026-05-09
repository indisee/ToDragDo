#if canImport(SwiftData)
import Foundation
import SwiftData

@MainActor
public final class SwiftDataStorage: ItemStorage {
    private let container: ModelContainer

    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        self.container = try ModelContainer(for: schema, configurations: config)
    }

    private var ctx: ModelContext { container.mainContext }

    // MARK: - Items

    public func items(in folder: Folder, includeDeleted: Bool) async throws -> [Item] {
        let raw = folder.rawValue
        let descriptor = FetchDescriptor<PersistedItem>(
            predicate: #Predicate { $0.folderRaw == raw },
            sortBy: [SortDescriptor(\.orderKey)]
        )
        let rows = try ctx.fetch(descriptor)
        return rows
            .filter { includeDeleted || $0.deletedAt == nil }
            .map { $0.toDTO() }
    }

    public func item(id: UUID) async throws -> Item? {
        try fetchPersistedItem(id: id)?.toDTO()
    }

    // MARK: - Item writes

    public func upsert(_ item: Item, change: ChangeRecord) async throws {
        try ctx.transaction {
            if let existing = try fetchPersistedItem(id: item.id) {
                existing.apply(item)
            } else {
                ctx.insert(PersistedItem(from: item))
            }
            ctx.insert(PersistedChange(from: change))
        }
    }

    public func softDelete(id: UUID, at deletedAt: Date, change: ChangeRecord) async throws {
        try ctx.transaction {
            guard let row = try fetchPersistedItem(id: id) else { return }
            row.deletedAt = deletedAt
            row.updatedAt = deletedAt
            ctx.insert(PersistedChange(from: change))
        }
    }

    public func hardDelete(folder: Folder, changes: [ChangeRecord]) async throws {
        let raw = folder.rawValue
        try ctx.transaction {
            let descriptor = FetchDescriptor<PersistedItem>(
                predicate: #Predicate { $0.folderRaw == raw }
            )
            let rows = try ctx.fetch(descriptor)
            for row in rows {
                ctx.delete(row)
            }
            for change in changes {
                ctx.insert(PersistedChange(from: change))
            }
        }
    }

    // MARK: - Outbox

    public func pendingChanges(for providerId: String, limit: Int) async throws -> [ChangeRecord] {
        var descriptor = FetchDescriptor<PersistedChange>(
            predicate: #Predicate { change in
                !change.syncStatuses.contains { status in
                    status.providerId == providerId && status.pushedAt != nil
                }
            },
            sortBy: [SortDescriptor(\.ts)]
        )
        descriptor.fetchLimit = limit
        return try ctx.fetch(descriptor).map { $0.toDTO() }
    }

    public func pendingPushCount(for providerId: String) async throws -> Int {
        let descriptor = FetchDescriptor<PersistedChange>(
            predicate: #Predicate { change in
                !change.syncStatuses.contains { status in
                    status.providerId == providerId && status.pushedAt != nil
                }
            }
        )
        return try ctx.fetchCount(descriptor)
    }

    public func markPushed(_ ids: [UUID], to providerId: String, at: Date) async throws {
        guard !ids.isEmpty else { return }
        try ctx.transaction {
            let rows = try fetchChanges(ids: ids)
            for row in rows {
                if let existing = row.status(for: providerId) {
                    existing.pushedAt = at
                    existing.lastError = nil
                    existing.lastAttemptAt = at
                } else {
                    let status = PersistedChangeSyncStatus(
                        providerId: providerId,
                        pushedAt: at,
                        lastAttemptAt: at,
                        change: row
                    )
                    ctx.insert(status)
                }
            }
        }
    }

    public func recordPushFailure(_ ids: [UUID], to providerId: String, error: String, at: Date) async throws {
        guard !ids.isEmpty else { return }
        try ctx.transaction {
            let rows = try fetchChanges(ids: ids)
            for row in rows {
                if let existing = row.status(for: providerId) {
                    existing.lastError = error
                    existing.lastAttemptAt = at
                    existing.attemptCount += 1
                } else {
                    let status = PersistedChangeSyncStatus(
                        providerId: providerId,
                        lastAttemptAt: at,
                        lastError: error,
                        attemptCount: 1,
                        change: row
                    )
                    ctx.insert(status)
                }
            }
        }
    }

    public func syncStatus(forChange changeId: UUID, providerId: String) async throws -> ChangeSyncStatus? {
        guard let change = try fetchChange(id: changeId) else { return nil }
        return change.status(for: providerId)?.toDTO()
    }

    // MARK: - Helpers

    private func fetchPersistedItem(id: UUID) throws -> PersistedItem? {
        let descriptor = FetchDescriptor<PersistedItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try ctx.fetch(descriptor).first
    }

    private func fetchChange(id: UUID) throws -> PersistedChange? {
        let descriptor = FetchDescriptor<PersistedChange>(
            predicate: #Predicate { $0.id == id }
        )
        return try ctx.fetch(descriptor).first
    }

    private func fetchChanges(ids: [UUID]) throws -> [PersistedChange] {
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<PersistedChange>(
            predicate: #Predicate { idSet.contains($0.id) }
        )
        return try ctx.fetch(descriptor)
    }
}
#endif
