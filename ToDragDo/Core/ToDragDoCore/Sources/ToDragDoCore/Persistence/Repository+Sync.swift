import Foundation

/// `RemoteApplier` conformance: outbox reads/marks and applying pulled changes, plus synced settings.
extension Repository {
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
            // Per-record tolerance: one undecodable or storage-rejecting
            // record (e.g., a future entityType this build doesn't know,
            // or a payload shape that fails to decode as Item/Project)
            // must not abort the rest of the batch. CKSyncEngine advances
            // its state token during fetch, so a throw here would also
            // mean the surviving records are never redelivered.
            do {
                switch record.entityType {
                case "Project":
                    try await applyRemoteProject(record)
                case SettingsSnapshot.entityType:
                    applyRemoteSettings(record)
                    // Settings don't touch the items table — skip the reload
                    // they don't need by not flipping `changed`.
                    continue
                default:
                    try await applyRemoteItem(record)
                }
                changed = true
            } catch {
                continue
            }
        }
        if changed {
            // applyRemote is the post-pull path — use plain `reload()` so
            // we don't recursively trigger another sync round on records
            // that came *from* the remote.
            try await reload()
        }
    }

    private func applyRemoteSettings(_ record: ChangeRecord) {
        guard let snapshot = try? decoder.decode(SettingsSnapshot.self, from: record.snapshot)
        else { return }
        onRemoteSettings?(snapshot, record.ts)
    }

    /// Append a Settings change record to the outbox. The local value
    /// is owned by the app (UserDefaults) — Repository only carries
    /// the snapshot through the same change-record pipe that already
    /// moves `Item` and `Project` rows.
    public func emitSettingsChange(
        _ snapshot: SettingsSnapshot,
        at ts: Date = .now
    ) async throws {
        let data = (try? encoder.encode(snapshot)) ?? Data()
        let change = ChangeRecord(
            entityType: SettingsSnapshot.entityType,
            entityId: SettingsSnapshot.entityId,
            op: .update,
            snapshot: data,
            deviceId: deviceId,
            ts: ts
        )
        try await storage.appendChanges([change])
        onWriteCallback?()
    }

    private func applyRemoteItem(_ record: ChangeRecord) async throws {
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
    }

    private func applyRemoteProject(_ record: ChangeRecord) async throws {
        switch record.op {
        case .insert, .update:
            let project = try decoder.decode(Project.self, from: record.snapshot)
            try await storage.upsertProjectWithoutChange(project)
        case .hardDelete:
            try await storage.deleteProjectWithoutChange(id: record.entityId)
        case .softDelete:
            // Projects don't soft-delete — drop the record instead of
            // throwing so a stray legacy/future op doesn't break the pull.
            return
        }
    }
}
