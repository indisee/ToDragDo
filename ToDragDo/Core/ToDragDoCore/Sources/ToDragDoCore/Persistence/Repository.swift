import Foundation
import Observation

@MainActor
@Observable
public final class Repository: RemoteApplier {
    public private(set) var items: [Folder: [Item]] = [:]
    /// Soft-deleted items within the trash retention window, most recently
    /// deleted first. Refreshed by `reload()`.
    public private(set) var trashItems: [Item] = []
    /// All projects, sorted by `orderKey`. Refreshed by `reload()` and
    /// seeded with `Project.defaults` on first launch.
    public private(set) var projects: [Project] = []

    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    private let storage: any ItemStorage
    public let deviceId: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Fires after every user-initiated write (add, update, move, delete,
    /// rollover, …) — once `reload()` has refreshed the published state.
    /// Not called from `applyRemote(_:)` because remote-pulled changes
    /// shouldn't trigger another sync round.
    ///
    /// Excluded from `@Observable` tracking so views that read repository
    /// state don't redraw when the callback is (re)assigned.
    @ObservationIgnored
    public var onWriteCallback: (@MainActor () -> Void)?

    public init(storage: any ItemStorage, deviceId: String = DeviceID.current) {
        self.storage = storage
        self.deviceId = deviceId
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
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
        let cutoff = Date.now.addingTimeInterval(-Self.trashRetention)
        trashItems = try await storage.trashItems(since: cutoff)

        var stored = try await storage.projects()
        // First launch (and any prior install that's missing a default
        // row): re-insert defaults so Work and Personal are always
        // resolvable for the migration fallback.
        let storedIds = Set(stored.map(\.id))
        let missing = Project.defaults.filter { !storedIds.contains($0.id) }
        if !missing.isEmpty {
            for project in missing {
                try await storage.upsertProject(project)
            }
            stored = try await storage.projects()
        }
        projects = stored
    }

    /// Resolves `id` to a known project, falling back to Work for unknown
    /// ids (e.g. items pulled from a device that hasn't synced its
    /// project list yet).
    public func project(for id: UUID) -> Project {
        if let match = projects.first(where: { $0.id == id }) {
            return match
        }
        return projects.first(where: { $0.id == Project.workId })
            ?? Project.defaultWork()
    }

    /// `reload()` + fire `onWriteCallback`. Used by every user-initiated
    /// write so the host (e.g., `SyncCoordinator`) can react immediately.
    /// `applyRemote(_:)` deliberately uses plain `reload()` instead, so
    /// pulled remote changes don't trigger another push cycle.
    private func reloadAndNotify() async throws {
        try await reload()
        onWriteCallback?()
    }

    @discardableResult
    public func add(
        folder: Folder,
        typeIdentifier: String,
        payload: Data,
        projectId: UUID = Project.workId
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
            projectId: projectId
        )
        let change = makeChange(op: .insert, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
        return item
    }

    /// Reassign an existing item to a different project. No-op if the
    /// project already matches.
    public func setProject(itemId: UUID, to projectId: UUID) async throws {
        guard var item = try await storage.item(id: itemId) else {
            throw StorageError.notFound(itemId)
        }
        guard item.projectId != projectId else { return }
        item.projectId = projectId
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
    }

    // MARK: - Project CRUD

    /// Create a new project. `orderKey` defaults to one past the
    /// current max so it lands at the end of the list.
    @discardableResult
    public func addProject(name: String, colorHex: String) async throws -> Project {
        let nextKey = (projects.map(\.orderKey).max() ?? 0) + 1
        let project = Project(name: name, colorHex: colorHex, orderKey: nextKey)
        try await storage.upsertProject(project)
        try await reload()
        return project
    }

    public func renameProject(id: UUID, to name: String) async throws {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.name = name
        project.updatedAt = .now
        try await storage.upsertProject(project)
        try await reload()
    }

    public func recolorProject(id: UUID, to colorHex: String) async throws {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.colorHex = colorHex
        project.updatedAt = .now
        try await storage.upsertProject(project)
        try await reload()
    }

    /// Delete a custom project. Items assigned to it are reassigned to
    /// `reassignTo` (default: Work). Refuses to delete the seed Work
    /// project — it's the system-wide migration fallback.
    public func deleteProject(id: UUID, reassignTo: UUID = Project.workId) async throws {
        guard id != Project.workId else { return }
        try await storage.deleteProject(id: id, reassignTo: reassignTo)
        try await reloadAndNotify()
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
        let nextKey = (dest.map(\.orderKey).max() ?? 0) + 1
        let wasDone = item.folder == .done
        item.folder = destination
        item.orderKey = nextKey
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        // Dragging a trash item onto a folder tab implicitly restores it.
        item.deletedAt = nil
        if destination == .done {
            item.completedAt = .now
        } else if wasDone {
            item.completedAt = nil
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

    /// Day rollover: items left in Today move to Tomorrow, then Tomorrow
    /// becomes the new Today. Net effect — old Today + old Tomorrow merge
    /// into Today (old-Tomorrow first, old-Today appended), and Tomorrow
    /// is cleared. Then any Limbo items whose `dueDate` has arrived are
    /// promoted into Today/Tomorrow.
    public func rolloverDay(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws {
        let todays = try await storage.items(in: .today, includeDeleted: false)
            .sorted { $0.orderKey < $1.orderKey }
        let tomorrows = try await storage.items(in: .tomorrow, includeDeleted: false)
            .sorted { $0.orderKey < $1.orderKey }

        let stamp = Date.now
        if !todays.isEmpty || !tomorrows.isEmpty {
            var key: Double = 0
            for item in tomorrows + todays {
                key += 1
                var moved = item
                moved.folder = .today
                moved.orderKey = key
                moved.updatedAt = stamp
                moved.lastEditedBy = deviceId
                let change = makeChange(op: .update, item: moved)
                try await storage.upsert(moved, change: change)
            }
        }

        try await promoteScheduledItems(now: now, calendar: calendar, reloadAfter: false)
        try await reloadAndNotify()
    }

    /// Sets (or clears) `dueDate` on an item and routes it to the right
    /// folder: today/past → Today; +1 day → Tomorrow; further future →
    /// Limbo. Clearing the date leaves the current folder untouched —
    /// the user moves it explicitly via the row actions.
    public func setDueDate(
        id: UUID,
        to date: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws {
        guard var item = try await storage.item(id: id) else {
            throw StorageError.notFound(id)
        }
        item.dueDate = date
        item.updatedAt = .now
        item.lastEditedBy = deviceId

        // Done items hold their own date for archival/log purposes —
        // assigning a past date shouldn't yank them back into Today.
        if let date, item.folder != .done {
            let target = destinationFolder(for: date, now: now, calendar: calendar)
            if item.folder != target {
                let dest = try await storage.items(in: target, includeDeleted: false)
                item.folder = target
                item.orderKey = (dest.map(\.orderKey).max() ?? 0) + 1
            }
        }

        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
    }

    /// Scans Limbo for items whose `dueDate` has arrived and moves them:
    /// past or today → Today, exact-tomorrow → Tomorrow.
    public func promoteScheduledItems(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        reloadAfter: Bool = true
    ) async throws {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        let limbo = try await storage.items(in: .libmo, includeDeleted: false)
        let toToday = limbo.filter { item in
            guard let due = item.dueDate else { return false }
            return calendar.startOfDay(for: due) <= today
        }
        let toTomorrow = limbo.filter { item in
            guard let due = item.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: tomorrow)
        }
        guard !toToday.isEmpty || !toTomorrow.isEmpty else { return }

        let todayItems = try await storage.items(in: .today, includeDeleted: false)
        let tomorrowItems = try await storage.items(in: .tomorrow, includeDeleted: false)
        var todayKey = todayItems.map(\.orderKey).max() ?? 0
        var tomorrowKey = tomorrowItems.map(\.orderKey).max() ?? 0
        let stamp = Date.now

        for var item in toToday {
            todayKey += 1
            item.folder = .today
            item.orderKey = todayKey
            item.updatedAt = stamp
            item.lastEditedBy = deviceId
            let change = makeChange(op: .update, item: item)
            try await storage.upsert(item, change: change)
        }
        for var item in toTomorrow {
            tomorrowKey += 1
            item.folder = .tomorrow
            item.orderKey = tomorrowKey
            item.updatedAt = stamp
            item.lastEditedBy = deviceId
            let change = makeChange(op: .update, item: item)
            try await storage.upsert(item, change: change)
        }
        if reloadAfter {
            try await reloadAndNotify()
        }
    }

    private func destinationFolder(
        for dueDate: Date,
        now: Date,
        calendar: Calendar
    ) -> Folder {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: dueDate)
        if day <= today { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        return .libmo
    }

    public func emptyDone() async throws {
        let dones = try await storage.items(in: .done, includeDeleted: true)
        let changes = dones.map { makeChange(op: .hardDelete, item: $0) }
        try await storage.hardDelete(folder: .done, changes: changes)
        try await reloadAndNotify()
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

    /// Apply remote ChangeRecords pulled by a `RemoteAdapter`. Routes each
    /// record to the storage's `*WithoutChange` methods so we don't echo
    /// the change back into the outbox. Records originating from this
    /// device are dropped — they're either echoes of our own pushes or
    /// records we already wrote locally.
    public func applyRemote(_ records: [ChangeRecord]) async throws {
        var changed = false
        for record in records where record.deviceId != deviceId {
            switch record.op {
            case .insert, .update:
                let item = try decoder.decode(Item.self, from: record.snapshot)
                try await storage.upsertWithoutChange(item)
            case .softDelete:
                let item = try? decoder.decode(Item.self, from: record.snapshot)
                let at = item?.deletedAt ?? record.ts
                try await storage.softDeleteWithoutChange(id: record.entityId, at: at)
            case .hardDelete:
                try await storage.hardDeleteWithoutChange(id: record.entityId)
            }
            changed = true
        }
        if changed {
            // applyRemote is the post-pull path — use plain `reload()` so
            // we don't recursively trigger another sync round on records
            // that came *from* the remote.
            try await reload()
        }
    }

    /// Append a fresh current-state outbox row for every local item
    /// (including soft-deleted ones). Used after switching CloudKit
    /// environments — the new destination is empty, but the existing
    /// outbox rows are marked pushed against the old environment under
    /// the same provider id, so they will not re-emit on their own.
    ///
    /// Soft-deleted items emit a `.softDelete` change; live items emit
    /// `.update`. The local items are not mutated. Returns the number of
    /// outbox rows appended. After calling, the host should trigger a
    /// sync cycle.
    @discardableResult
    public func resyncAllItems() async throws -> Int {
        let allItems = try await storage.allItems()
        guard !allItems.isEmpty else { return 0 }
        let now = Date()
        let changes: [ChangeRecord] = allItems.map { item in
            let op: ChangeOp = item.deletedAt != nil ? .softDelete : .update
            let snapshot = (try? encoder.encode(item)) ?? Data()
            return ChangeRecord(
                entityType: "Item",
                entityId: item.id,
                op: op,
                snapshot: snapshot,
                deviceId: deviceId,
                ts: now
            )
        }
        try await storage.appendChanges(changes)
        onWriteCallback?()
        return changes.count
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
