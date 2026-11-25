import Foundation

/// Item CRUD: add, edit, move between folders, reorder, trash and purge.
extension Repository {
    @discardableResult
    public func add(
        folder: Folder,
        typeIdentifier: String,
        payload: Data,
        projectId: UUID? = nil
    ) async throws -> Item {
        // New items prepend to the folder so the user sees them
        // immediately without scrolling/paging — orderKey one tick
        // below the current minimum.
        let firstKey = items[folder]?.first?.orderKey ?? 1
        let item = Item(
            folder: folder,
            orderKey: firstKey - 1,
            typeIdentifier: typeIdentifier,
            payload: payload,
            lastEditedBy: deviceId,
            projectId: projectId,
            limboEnteredAt: folder == .libmo ? .now : nil
        )
        let change = makeChange(op: .insert, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
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
        try await reloadAndNotify()
    }

    /// Append `attachment` to an existing item's payload. The item's
    /// `typeIdentifier` is left unchanged — the primary content type is
    /// the one the item was created with.
    public func addAttachment(to id: UUID, _ attachment: Attachment) async throws {
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        var payload = ItemPayload.decode(item.payload)
        payload.attachments.append(attachment)
        item.payload = try payload.encoded()
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
    }

    public func move(id: UUID, to destination: Folder) async throws {
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        let dest = try await storage.items(in: destination, includeDeleted: false)
            .filter { $0.id != id }
        // Land moved items at the TOP of the destination so the user
        // sees them immediately — mirrors `add()`'s prepend behavior.
        // In Done this also means most-recently-finished sits first.
        let firstKey = dest.map(\.orderKey).min() ?? 1
        let wasDone = item.folder == .done
        let wasInLimbo = item.folder == .libmo
        item.folder = destination
        item.orderKey = firstKey - 1
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        // Dragging a trash item onto a folder tab implicitly restores it.
        item.deletedAt = nil
        if destination == .done {
            item.completedAt = .now
        } else if wasDone {
            item.completedAt = nil
        }
        // Limbo idle timer: start on entry, leave alone on within-Limbo
        // moves (drag-to-tab while already there), clear on exit.
        if destination == .libmo {
            if !wasInLimbo { item.limboEnteredAt = .now }
        } else {
            item.limboEnteredAt = nil
        }
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
    }

    /// Restores a soft-deleted item: clears `deletedAt` and moves it to
    /// the destination folder (defaults to Today).
    public func restore(id: UUID, to destination: Folder = .today) async throws {
        try await move(id: id, to: destination)
    }

    /// Resets the Limbo idle timer for `id` (only if the item currently
    /// sits in Limbo). Called when the user opens a Limbo row so it
    /// stops blinking. No-op for non-Limbo items so opens elsewhere
    /// don't churn the outbox.
    public func noteOpened(id: UUID) async throws {
        guard var item = try await storage.item(id: id) else { return }
        guard item.folder == .libmo else { return }
        item.limboEnteredAt = .now
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
    }

    /// Hard-deletes a single item (used to purge a trash entry).
    public func purgeItem(id: UUID) async throws {
        guard let item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        let change = makeChange(op: .hardDelete, item: item)
        try await storage.hardDeleteItem(id: id, change: change)
        try await reloadAndNotify()
    }

    /// Hard-deletes soft-deleted items older than the trash retention
    /// window. Safe to call repeatedly; emits one change record per
    /// purged item for the sync log.
    public func purgeExpiredTrash(now: Date = .now) async throws {
        let cutoff = now.addingTimeInterval(-Self.trashRetention)
        let expired = try await storage.trashItems(since: .distantPast)
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        guard !expired.isEmpty else { return }
        let changes = expired.map { makeChange(op: .hardDelete, item: $0) }
        try await storage.purgeTrash(before: cutoff, changes: changes)
        try await reloadAndNotify()
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
        try await reloadAndNotify()
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
        try await reloadAndNotify()
    }

    public func emptyDone() async throws {
        let dones = try await storage.items(in: .done, includeDeleted: true)
        let changes = dones.map { makeChange(op: .hardDelete, item: $0) }
        try await storage.hardDelete(folder: .done, changes: changes)
        try await reloadAndNotify()
    }
}
