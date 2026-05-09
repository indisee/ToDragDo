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
        try await reload()
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
        try await reload()
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
            try await reload()
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
