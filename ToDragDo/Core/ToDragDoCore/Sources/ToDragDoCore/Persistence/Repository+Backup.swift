import Foundation

/// Full-data backup and re-emitting everything into the outbox (environment switches, schema migrations).
extension Repository {
    /// Full snapshot of local data (every item, trashed ones included,
    /// and every project) for a safety backup. The outbox is not part of
    /// it: it only describes what still has to be sent somewhere.
    public func makeBackup() async throws -> RepositoryBackup {
        RepositoryBackup(
            createdAt: .now,
            deviceId: deviceId,
            items: try await storage.allItems(),
            projects: try await storage.projects()
        )
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
    ///
    /// `excluding` skips entity ids the remote already has (used by the
    /// Development → Production migration so it only fills in what is
    /// missing instead of overwriting records another device pushed).
    @discardableResult
    public func resyncAllItems(excluding excludedIds: Set<UUID> = []) async throws -> Int {
        let allItems = try await storage.allItems().filter { !excludedIds.contains($0.id) }
        let allProjects = try await storage.projects().filter { !excludedIds.contains($0.id) }
        guard !allItems.isEmpty || !allProjects.isEmpty else { return 0 }
        let now = Date()
        var changes: [ChangeRecord] = []
        changes.reserveCapacity(allItems.count + allProjects.count)
        for item in allItems {
            let op: ChangeOp = item.deletedAt != nil ? .softDelete : .update
            let snapshot = (try? encoder.encode(item)) ?? Data()
            changes.append(ChangeRecord(
                entityType: "Item",
                entityId: item.id,
                op: op,
                snapshot: snapshot,
                deviceId: deviceId,
                ts: now
            ))
        }
        for project in allProjects {
            let snapshot = (try? encoder.encode(project)) ?? Data()
            changes.append(ChangeRecord(
                entityType: "Project",
                entityId: project.id,
                op: .update,
                snapshot: snapshot,
                deviceId: deviceId,
                ts: now
            ))
        }
        try await storage.appendChanges(changes)
        onWriteCallback?()
        return changes.count
    }

    /// One-shot re-push of every live item, trashed item, and project as
    /// a fresh `update` ChangeRecord. The host (macOS) calls this once
    /// per device after a CloudKit schema migration so the zone is
    /// rewritten with the current field layout (inline `snapshotData`
    /// alongside the legacy `CKAsset`). Without it, clients that can't
    /// decode legacy records — e.g. iOS Simulator, whose `mmcs` service
    /// can't fetch the `CKAsset` field — never see records that were
    /// written by older builds.
    ///
    /// Returns the number of records queued.
    @discardableResult
    public func reEmitAllAsChanges() async throws -> Int {
        var changes: [ChangeRecord] = []
        for (_, slice) in items {
            for item in slice {
                changes.append(makeChange(op: .update, item: item))
            }
        }
        for item in trashItems {
            changes.append(makeChange(op: .update, item: item))
        }
        for project in projects {
            changes.append(makeProjectChange(op: .update, project: project))
        }
        if changes.isEmpty { return 0 }
        try await storage.appendChanges(changes)
        onWriteCallback?()
        return changes.count
    }
}
