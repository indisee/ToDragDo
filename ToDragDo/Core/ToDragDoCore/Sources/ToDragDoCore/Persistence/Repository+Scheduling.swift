import Foundation

/// Day rollover, due dates and promotion of scheduled items.
extension Repository {
    /// Day rollover: Tomorrow becomes the new Today. Old-Tomorrow items
    /// move into Today above the existing Today items (keeping their
    /// relative order); Today items are left untouched. Then any Limbo
    /// items whose `dueDate` has arrived are promoted into Today/Tomorrow.
    ///
    /// Sync-safety: rollover is automatic, not a user edit, and often
    /// runs on wake against stale local state (before the pull lands).
    /// So it only writes the items it actually moves, and stamps them
    /// with `automaticStamp` (≈ local midnight) rather than `.now` —
    /// otherwise a laptop waking up the next morning would re-stamp its
    /// stale copies as the newest version and overwrite every edit made
    /// on other devices overnight.
    public func rolloverDay(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws {
        let todays = try await storage.items(in: .today, includeDeleted: false)
        let tomorrows = try await storage.items(in: .tomorrow, includeDeleted: false)
            .sorted { $0.orderKey < $1.orderKey }

        if !tomorrows.isEmpty {
            let dayStart = calendar.startOfDay(for: now)
            let topKey = todays.map(\.orderKey).min() ?? Double(tomorrows.count + 1)
            for (index, item) in tomorrows.enumerated() {
                var moved = item
                moved.folder = .today
                moved.orderKey = topKey - Double(tomorrows.count - index)
                moved.updatedAt = Self.automaticStamp(for: item, dayStart: dayStart)
                moved.lastEditedBy = deviceId
                let change = makeChange(op: .update, item: moved)
                try await storage.upsert(moved, change: change)
            }
        }

        try await promoteScheduledItems(now: now, calendar: calendar, reloadAfter: false)
        try await reloadAndNotify()
    }

    /// `updatedAt` for writes the app makes on its own (rollover, due-date
    /// promotion). Pinned to the start of the day the move logically
    /// happened, so any real edit made on another device after that
    /// still wins LWW. Nudged just past the item's current stamp so the
    /// move itself still beats the version it was derived from.
    static func automaticStamp(for item: Item, dayStart: Date) -> Date {
        max(dayStart, item.updatedAt.addingTimeInterval(0.001))
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
                let wasInLimbo = item.folder == .libmo
                item.folder = target
                item.orderKey = (dest.map(\.orderKey).max() ?? 0) + 1
                if target == .libmo {
                    if !wasInLimbo { item.limboEnteredAt = .now }
                } else {
                    item.limboEnteredAt = nil
                }
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

        for var item in toToday {
            todayKey += 1
            item.folder = .today
            item.orderKey = todayKey
            item.updatedAt = Self.automaticStamp(for: item, dayStart: today)
            item.lastEditedBy = deviceId
            item.limboEnteredAt = nil
            let change = makeChange(op: .update, item: item)
            try await storage.upsert(item, change: change)
        }
        for var item in toTomorrow {
            tomorrowKey += 1
            item.folder = .tomorrow
            item.orderKey = tomorrowKey
            item.updatedAt = Self.automaticStamp(for: item, dayStart: today)
            item.lastEditedBy = deviceId
            item.limboEnteredAt = nil
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
}
