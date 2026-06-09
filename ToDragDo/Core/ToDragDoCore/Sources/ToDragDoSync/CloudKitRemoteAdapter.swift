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
    public nonisolated let providerId: String = "icloud"
    public nonisolated let displayName: String = "iCloud"

    private let log = Logger(subsystem: "com.turtle.todragdo", category: "CloudKit")
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
        do {
            try await engine.fetchChanges()
        } catch {
            let detail = CloudKitErrorDescribe.verbose(error, phase: "fetchChanges")
            log.error("CKSyncEngine.fetchChanges threw: \(detail, privacy: .public)")
            pullBuffer.removeAll(keepingCapacity: false)
            throw CloudKitAdapterError(detail: detail, underlying: error)
        }
        let result = pullBuffer
        pullBuffer.removeAll(keepingCapacity: false)
        return (result, SyncCursor(token: stateStore.fingerprint))
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
                let reason = CloudKitErrorDescribe.verbose(
                    failure.error,
                    phase: "saveRecord(\(recordName))"
                )
                log.error("iCloud save failed for \(recordName, privacy: .public): \(reason, privacy: .public)")
                if let id = UUID(uuidString: recordName) {
                    cycleFailed[id] = reason
                    if failure.error.code == .serverRecordChanged {
                        cycleFailed.removeValue(forKey: id)
                        cycleSucceeded.insert(id)
                        deleteAssetFile(forChangeId: id)
                    }
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
