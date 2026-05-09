import Foundation
import Observation

@MainActor
@Observable
public final class Repository {
    public private(set) var items: [Folder: [Item]] = [:]

    private let storage: any ItemStorage
    private let deviceId: String
    private let encoder: JSONEncoder

    public init(storage: any ItemStorage, deviceId: String = DeviceID.current) {
        self.storage = storage
        self.deviceId = deviceId
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        for folder in Folder.allCases {
            items[folder] = []
        }
    }

    public func reload() async throws {
        var fresh: [Folder: [Item]] = [:]
        for folder in Folder.allCases {
            let rows = try await storage.items(in: folder, includeDeleted: false)
            fresh[folder] = rows.sorted { $0.orderKey < $1.orderKey }
        }
        items = fresh
    }

    @discardableResult
    public func add(
        folder: Folder,
        typeIdentifier: String,
        payload: Data
    ) async throws -> Item {
        let nextKey = (items[folder]?.last?.orderKey ?? 0) + 1
        let item = Item(
            folder: folder,
            orderKey: nextKey,
            typeIdentifier: typeIdentifier,
            payload: payload,
            lastEditedBy: deviceId
        )
        let change = makeChange(op: .insert, item: item)
        try await storage.upsert(item, change: change)
        try await reload()
        return item
    }

    public func update(id: UUID, mutate: (inout Item) -> Void) async throws {
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        mutate(&item)
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reload()
    }

    public func move(id: UUID, to destination: Folder) async throws {
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        let dest = try await storage.items(in: destination, includeDeleted: false)
        let nextKey = (dest.map(\.orderKey).max() ?? 0) + 1
        item.folder = destination
        item.orderKey = nextKey
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reload()
    }

    /// Reorder `id` to sit immediately before `targetId` within the same folder.
    /// `targetId == nil` appends to the end. No-op if `id == targetId`.
    public func reorder(id: UUID, before targetId: UUID?) async throws {
        guard id != targetId else { return }
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        let siblings = try await storage.items(in: item.folder, includeDeleted: false)
            .filter { $0.id != id }
            .sorted { $0.orderKey < $1.orderKey }

        let newKey: Double
        if let targetId, let targetIndex = siblings.firstIndex(where: { $0.id == targetId }) {
            let target = siblings[targetIndex].orderKey
            if targetIndex > 0 {
                newKey = (siblings[targetIndex - 1].orderKey + target) / 2
            } else {
                newKey = target - 1
            }
        } else {
            newKey = (siblings.last?.orderKey ?? 0) + 1
        }

        item.orderKey = newKey
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reload()
    }

    public func softDelete(id: UUID) async throws {
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        let now = Date.now
        item.deletedAt = now
        item.updatedAt = now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .softDelete, item: item)
        try await storage.softDelete(id: id, at: now, change: change)
        try await reload()
    }

    public func emptyDone() async throws {
        let dones = try await storage.items(in: .done, includeDeleted: true)
        let changes = dones.map { makeChange(op: .hardDelete, item: $0) }
        try await storage.hardDelete(folder: .done, changes: changes)
        try await reload()
    }

    public func pendingChanges(
        for providerId: String,
        limit: Int = 500
    ) async throws -> [ChangeRecord] {
        try await storage.pendingChanges(for: providerId, limit: limit)
    }

    public func pendingPushCount(for providerId: String) async throws -> Int {
        try await storage.pendingPushCount(for: providerId)
    }

    public func markPushed(_ ids: [UUID], to providerId: String) async throws {
        try await storage.markPushed(ids, to: providerId, at: .now)
    }

    public func recordPushFailure(
        _ ids: [UUID],
        to providerId: String,
        error: String
    ) async throws {
        try await storage.recordPushFailure(ids, to: providerId, error: error, at: .now)
    }

    public func syncStatus(
        forChange changeId: UUID,
        providerId: String
    ) async throws -> ChangeSyncStatus? {
        try await storage.syncStatus(forChange: changeId, providerId: providerId)
    }

    private func makeChange(op: ChangeOp, item: Item) -> ChangeRecord {
        let snapshot = (try? encoder.encode(item)) ?? Data()
        return ChangeRecord(
            entityType: "Item",
            entityId: item.id,
            op: op,
            snapshot: snapshot,
            deviceId: deviceId
        )
    }
}
