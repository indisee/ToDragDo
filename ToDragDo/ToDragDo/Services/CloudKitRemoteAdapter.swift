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
///   `CKRecord` via `CloudKitSchema.makeRecord`.
/// * `pull(since:)` awaits `fetchChanges()`. Incoming records are decoded
///   into a per-call buffer and returned to the coordinator.
/// * Engine server-state token is persisted by `CloudKitStateStore` on
///   `.stateUpdate` events.
///
/// `automaticallySync` is `false` so we don't need APNs push entitlements
/// in stage-1; the host drives sync via `SyncCoordinator.syncAll()`.
@MainActor
final class CloudKitRemoteAdapter: NSObject, RemoteAdapter, CKSyncEngineDelegate {
    nonisolated let providerId: String = "icloud"
    nonisolated let displayName: String = "iCloud"

    private let log = Logger(subsystem: "com.turtle.todragdo", category: "CloudKit")
    private let container: CKContainer
    private let database: CKDatabase
    private let stateStore: CloudKitStateStore

    private lazy var engine: CKSyncEngine = makeEngine()

    /// Records staged by `push(_:)` keyed by id, materialized on demand by
    /// the delegate's `nextRecordZoneChangeBatch`.
    private var stagedPushes: [UUID: ChangeRecord] = [:]
    /// Records pulled during the current `pull(since:)` call.
    private var pullBuffer: [ChangeRecord] = []

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.stateStore = CloudKitStateStore()
        super.init()
    }

    private func makeEngine() -> CKSyncEngine {
        var config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateStore.load(),
            delegate: self
        )
        config.automaticallySync = false
        let engine = CKSyncEngine(config)
        // Ensure our custom zone exists on first send.
        let zone = CKRecordZone(zoneID: CloudKitSchema.recordZoneID)
        engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        return engine
    }

    // MARK: - RemoteAdapter

    func push(_ changes: [ChangeRecord]) async throws {
        guard !changes.isEmpty else { return }
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
        try await engine.sendChanges()
    }

    func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor) {
        _ = cursor  // engine maintains its own state; argument is informational
        pullBuffer.removeAll(keepingCapacity: true)
        try await engine.fetchChanges()
        let result = pullBuffer
        pullBuffer.removeAll(keepingCapacity: false)
        return (result, SyncCursor(token: stateStore.fingerprint))
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
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
            // Deletions on our append-only zone aren't expected during
            // normal operation — log if they occur.
            if !fetched.deletions.isEmpty {
                log.notice("Ignored \(fetched.deletions.count) record deletions from iCloud")
            }

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords {
                if let id = UUID(uuidString: saved.recordID.recordName) {
                    stagedPushes.removeValue(forKey: id)
                }
            }
            for failure in sent.failedRecordSaves {
                log.error("iCloud save failed for \(failure.record.recordID.recordName): \(failure.error.localizedDescription)")
            }

        case .accountChange(let change):
            log.notice("iCloud account change: \(String(describing: change.changeType))")

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        // Snapshot the staged map so the Sendable closure passed to
        // `RecordZoneChangeBatch` doesn't capture main-actor state.
        let staged = stagedPushes
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard
                let id = UUID(uuidString: recordID.recordName),
                let change = staged[id]
            else { return nil }
            return try? CloudKitSchema.makeRecord(from: change)
        }
    }
}
