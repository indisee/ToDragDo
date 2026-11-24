import CloudKit
import Foundation
import OSLog
import ToDragDoCore

/// `RemoteAdapter` for iCloud, backed by `CKSyncEngine` against the user's
/// private database and a custom record zone (`CloudKitSchema.zoneName`).
///
/// CKSyncEngine inverts control — it owns the sync loop and delivers events
/// via its delegate. We adapt that to the passive `push`/`pull` shape by:
/// * `push(_:)` stages records into the engine's pending state, then awaits
///   `sendChanges()`. The delegate translates each pending change into a
///   `CKRecord` via `CloudKitSchema.makeRecord`. After the call returns we
///   inspect which IDs CloudKit saved vs. failed and return a `PushOutcome`
///   — the coordinator marks the survivors pushed and re-queues the rest
///   instead of treating every batch as all-or-nothing.
/// * `pull(since:)` awaits `fetchChanges()`. Incoming records are decoded
///   into a per-call buffer and returned to the coordinator.
/// * Engine server-state token is persisted by `CloudKitStateStore` on
///   `.stateUpdate` events.
///
/// `automaticallySync` is `false` so we don't need APNs push entitlements
/// in stage-1; the host drives sync via `SyncCoordinator.syncAll()`.
@MainActor
public final class CloudKitRemoteAdapter: NSObject, RemoteAdapter, CKSyncEngineDelegate {
    public nonisolated let providerId: String = CloudKitConfig.providerId
    public nonisolated let displayName: String = "iCloud"

    private let log = Logger.todragdo(category: "CloudKit")
    private let container: CKContainer
    private let database: CKDatabase
    private let stateStore: CloudKitStateStore
    private let assetDirectory: URL

    private lazy var engine: CKSyncEngine = makeEngine()

    /// Records staged by `push(_:)` keyed by id, materialized on demand by
    /// the delegate's `nextRecordZoneChangeBatch`.
    private var stagedPushes: [UUID: ChangeRecord] = [:]
    /// IDs that succeeded in the current `push(_:)` cycle, populated by the
    /// `.sentRecordZoneChanges` delegate event.
    private var cycleSucceeded: Set<UUID> = []
    /// Per-ID failure reason from CloudKit for the current `push(_:)` cycle.
    private var cycleFailed: [UUID: String] = [:]
    /// Records pulled during the current `pull(since:)` call.
    private var pullBuffer: [ChangeRecord] = []

    /// `assetDirectory` defaults to `applicationSupportDirectory/CloudKitAssets`,
    /// which is correct on macOS. iOS callers that need a shared App Group
    /// directory should pass it in explicitly.
    public init(
        containerIdentifier: String,
        assetDirectory: URL? = nil
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.stateStore = CloudKitStateStore()
        self.assetDirectory = assetDirectory ?? Self.makeDefaultAssetDirectory()
        super.init()
    }

    /// CKAsset upload happens asynchronously after `push` returns; if the
    /// file backing the asset disappears (the OS sweeps `/tmp` on its own
    /// schedule) the save fails permanently. Stash assets in the app's
    /// Application Support directory instead and clean them up only after
    /// CloudKit confirms the save.
    private static func makeDefaultAssetDirectory() -> URL {
        let fm = FileManager.default
        let base: URL
        do {
            base = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            base = fm.temporaryDirectory
        }
        let dir = base.appendingPathComponent("CloudKitAssets", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine() -> CKSyncEngine {
        var config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateStore.load(),
            delegate: self
        )
        config.automaticallySync = false
        let engine = CKSyncEngine(config)
        let zone = CKRecordZone(zoneID: CloudKitSchema.recordZoneID)
        engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        return engine
    }

    // MARK: - RemoteAdapter

    public func push(_ changes: [ChangeRecord]) async throws -> PushOutcome {
        guard !changes.isEmpty else { return .empty }

        cycleSucceeded.removeAll(keepingCapacity: true)
        cycleFailed.removeAll(keepingCapacity: true)
        for change in changes {
            stagedPushes[change.id] = change
        }

        let pending: [CKSyncEngine.PendingRecordZoneChange] = changes.map {
            let id = CKRecord.ID(
                recordName: $0.id.uuidString,
                zoneID: CloudKitSchema.recordZoneID
            )
            return .saveRecord(id)
        }
        engine.state.add(pendingRecordZoneChanges: pending)

        var topLevelReason: String?
        do {
            try await engine.sendChanges()
        } catch {
            topLevelReason = CloudKitErrorDescribe.verbose(error, phase: "sendChanges")
            log.error("CKSyncEngine.sendChanges threw: \(topLevelReason ?? "", privacy: .public)")
        }

        let pushedIds = changes.map(\.id)
        var succeeded: [UUID] = []
        var failed: [PushOutcome.Failure] = []
        for id in pushedIds {
            if cycleSucceeded.contains(id) {
                succeeded.append(id)
            } else if let reason = cycleFailed[id] {
                failed.append(PushOutcome.Failure(id: id, error: reason))
            } else if let topLevelReason {
                failed.append(PushOutcome.Failure(id: id, error: topLevelReason))
            } else {
                failed.append(PushOutcome.Failure(
                    id: id,
                    error: "CloudKit returned no outcome for this record (engine state may have leftover pending changes)"
                ))
            }
        }

        for id in pushedIds {
            stagedPushes.removeValue(forKey: id)
        }
        return PushOutcome(succeeded: succeeded, failed: failed)
    }

    public func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor) {
        _ = cursor
        pullBuffer.removeAll(keepingCapacity: true)
        var caughtError: (any Error)?
        do {
            try await engine.fetchChanges()
        } catch {
            caughtError = error
            let detail = CloudKitErrorDescribe.verbose(error, phase: "fetchChanges")
            log.error("CKSyncEngine.fetchChanges errored: \(detail, privacy: .public)")
        }
        // When CKSyncEngine bails on per-record asset fetches (common on
        // the iOS Simulator, whose `mmcs` service can't reliably fetch
        // CKAssets), side-fetch the failed records WITHOUT the CKAsset
        // field. Records pushed by clients on the new schema also carry
        // a `snapshotData` inline field, so the fallback decodes them
        // cleanly even though the engine's primary fetch couldn't.
        if let caughtError {
            let failedIDs = Self.extractFailedRecordIDs(from: caughtError)
            if !failedIDs.isEmpty {
                await fallbackFetchInline(failedIDs)
            }
        }
        let result = pullBuffer
        pullBuffer.removeAll(keepingCapacity: false)
        return (result, SyncCursor(token: stateStore.fingerprint))
    }

    /// Side-channel fetch that explicitly excludes the legacy CKAsset
    /// `snapshot` field. CloudKit normally downloads CKAssets eagerly;
    /// listing only the small fields in `desiredKeys` keeps the fetch
    /// in metadata-only mode, so per-asset transfer failures don't
    /// abort the operation.
    private func fallbackFetchInline(_ ids: [CKRecord.ID]) async {
        let desiredKeys = [
            CloudKitSchema.Field.entityType,
            CloudKitSchema.Field.entityId,
            CloudKitSchema.Field.op,
            CloudKitSchema.Field.ts,
            CloudKitSchema.Field.deviceId,
            CloudKitSchema.Field.snapshotData,
        ]
        do {
            let results = try await database.records(for: ids, desiredKeys: desiredKeys)
            var recovered = 0
            for (_, result) in results {
                guard case .success(let record) = result,
                      let change = CloudKitSchema.decode(record) else { continue }
                // Legacy records without an inline field decode to an
                // empty snapshot — there's no useful data to apply, so
                // skip them.
                guard !change.snapshot.isEmpty else { continue }
                pullBuffer.append(change)
                recovered += 1
            }
            if recovered > 0 {
                log.notice("Inline fallback recovered \(recovered) of \(ids.count) records")
            }
        } catch {
            log.error("Inline fallback fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Walks a (possibly nested) CKError and collects every record-id
    /// key in its `partialErrorsByItemID`. Used by `pull()` to discover
    /// which records the engine couldn't fetch so we can retry them via
    /// the inline-only fallback path.
    private nonisolated static func extractFailedRecordIDs(from error: any Error) -> [CKRecord.ID] {
        var collected: Set<CKRecord.ID> = []
        walk(error, into: &collected)
        return Array(collected)
    }

    private nonisolated static func walk(_ error: any Error, into out: inout Set<CKRecord.ID>) {
        let nsError = error as NSError
        if let ck = error as? CKError, let partials = ck.partialErrorsByItemID {
            for (key, inner) in partials {
                if let id = key as? CKRecord.ID {
                    out.insert(id)
                }
                walk(inner, into: &out)
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            walk(underlying, into: &out)
        }
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            stateStore.save(update.stateSerialization)

        case .fetchedRecordZoneChanges(let fetched):
            for modification in fetched.modifications {
                if let change = CloudKitSchema.decode(modification.record) {
                    pullBuffer.append(change)
                } else {
                    log.warning("Dropped undecodable record from iCloud: \(modification.record.recordID.recordName)")
                }
            }
            if !fetched.deletions.isEmpty {
                log.notice("Ignored \(fetched.deletions.count) record deletions from iCloud")
            }

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords {
                if let id = UUID(uuidString: saved.recordID.recordName) {
                    cycleSucceeded.insert(id)
                    deleteAssetFile(forChangeId: id)
                }
            }
            for failure in sent.failedRecordSaves {
                let recordName = failure.record.recordID.recordName
                // `.serverRecordChanged` here = "record already exists
                // on the server" (CKInternalErrorDomain 2004). Reached
                // when CKSyncEngine retries a record we already pushed
                // — local state lost track of the success or the
                // engine submitted it twice. Either way the server's
                // copy is canonical, so mark the change pushed and
                // move on without spamming the log.
                if failure.error.code == .serverRecordChanged,
                   let id = UUID(uuidString: recordName) {
                    log.notice("iCloud record \(recordName, privacy: .public) already on server; treated as pushed")
                    cycleSucceeded.insert(id)
                    deleteAssetFile(forChangeId: id)
                    continue
                }
                let reason = CloudKitErrorDescribe.verbose(
                    failure.error,
                    phase: "saveRecord(\(recordName))"
                )
                log.error("iCloud save failed for \(recordName, privacy: .public): \(reason, privacy: .public)")
                if let id = UUID(uuidString: recordName) {
                    cycleFailed[id] = reason
                }
            }

        case .accountChange(let change):
            log.notice("iCloud account change: \(String(describing: change.changeType))")

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        let staged = stagedPushes
        let assetDir = assetDirectory
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard
                let id = UUID(uuidString: recordID.recordName),
                let change = staged[id]
            else { return nil }
            return try? CloudKitSchema.makeRecord(from: change, assetDirectory: assetDir)
        }
    }

    private func deleteAssetFile(forChangeId id: UUID) {
        let url = assetDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}

/// Wraps a CloudKit error so the verbose multi-line detail appears in
/// `localizedDescription` — the only channel the cross-platform
/// `SyncCoordinator` reads when it builds `SyncStatus.lastError`.
public struct CloudKitAdapterError: LocalizedError {
    public let detail: String
    public let underlying: any Error
    public var errorDescription: String? { detail }

    public init(detail: String, underlying: any Error) {
        self.detail = detail
        self.underlying = underlying
    }
}
