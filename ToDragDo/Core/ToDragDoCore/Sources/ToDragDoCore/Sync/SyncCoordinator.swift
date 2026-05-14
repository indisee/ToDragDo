import Foundation
import Observation

/// Owns enabled `RemoteAdapter`s and publishes a `[SyncStatus]` the UI binds
/// to. Per-provider cycle is pull-then-push; errors are caught and surfaced
/// via `SyncStatus.lastError` so the coordinator never throws. `syncAll()`
/// runs providers concurrently.
///
/// The host (app) decides when to call `syncAll()` (launch, periodic tick,
/// account-availability change) and what `enabled` means policy-wise — the
/// coordinator just respects the flag.
@MainActor
@Observable
public final class SyncCoordinator {
    public private(set) var statuses: [SyncStatus] = []

    private let applier: any RemoteApplier
    private let defaults: UserDefaults
    private var adapters: [String: any RemoteAdapter] = [:]
    private var cursors: [String: SyncCursor] = [:]
    private let cursorEncoder: JSONEncoder
    private let cursorDecoder: JSONDecoder

    public init(applier: any RemoteApplier, defaults: UserDefaults = .standard) {
        self.applier = applier
        self.defaults = defaults
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.cursorEncoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.cursorDecoder = dec
    }

    public func register(_ adapter: any RemoteAdapter) {
        let providerId = adapter.providerId
        adapters[providerId] = adapter
        cursors[providerId] = loadCursor(providerId: providerId)
        if !statuses.contains(where: { $0.providerId == providerId }) {
            statuses.append(SyncStatus(
                providerId: providerId,
                displayName: adapter.displayName
            ))
        }
        Task { @MainActor [weak self] in
            await self?.refreshPendingCount(providerId: providerId)
        }
    }

    public func setEnabled(_ enabled: Bool, for providerId: String) {
        updateStatus(providerId: providerId) { $0.enabled = enabled }
    }

    public func syncAll() async {
        // Serial across providers: each `sync` already awaits at network
        // boundaries (so the main actor yields between providers), and v1
        // ships one provider. If multiple network-bound providers ever
        // contend, switch to a Task-group pattern that doesn't capture
        // main-actor state across the boundary.
        for providerId in Array(adapters.keys) {
            await sync(providerId)
        }
    }

    public func sync(_ providerId: String) async {
        guard let adapter = adapters[providerId] else { return }
        guard statuses.first(where: { $0.providerId == providerId })?.enabled == true else { return }

        updateStatus(providerId: providerId) { $0.lastAttempt = .now }

        var cycleError: (any Error)?

        // Pull
        let cursor = cursors[providerId] ?? .initial
        do {
            let (changes, next) = try await adapter.pull(since: cursor)
            try await applier.applyRemote(changes)
            cursors[providerId] = next
            saveCursor(next, providerId: providerId)
        } catch {
            cycleError = error
        }

        // Push — attempt regardless of pull outcome so a transient pull
        // failure doesn't block local writes from reaching the remote.
        do {
            let pending = try await applier.pendingChanges(for: providerId, limit: 500)
            if !pending.isEmpty {
                let ids = pending.map(\.id)
                do {
                    try await adapter.push(pending)
                    try await applier.markPushed(ids, to: providerId)
                } catch {
                    try? await applier.recordPushFailure(
                        ids,
                        to: providerId,
                        error: error.localizedDescription
                    )
                    cycleError = error
                }
            }
        } catch {
            cycleError = error
        }

        let count = (try? await applier.pendingPushCount(for: providerId)) ?? 0
        updateStatus(providerId: providerId) { s in
            s.pendingPushCount = count
            if let err = cycleError {
                s.lastError = err.localizedDescription
            } else {
                s.lastSuccess = .now
                s.lastError = nil
            }
        }
    }

    private func refreshPendingCount(providerId: String) async {
        let count = (try? await applier.pendingPushCount(for: providerId)) ?? 0
        updateStatus(providerId: providerId) { $0.pendingPushCount = count }
    }

    /// Refresh `pendingPushCount` for every registered provider without
    /// running a full sync cycle. Useful right after a local write so the
    /// UI shows the queued change before the push completes.
    public func refreshAllPendingCounts() async {
        for providerId in Array(adapters.keys) {
            await refreshPendingCount(providerId: providerId)
        }
    }

    private func updateStatus(providerId: String, _ mutate: (inout SyncStatus) -> Void) {
        guard let idx = statuses.firstIndex(where: { $0.providerId == providerId }) else { return }
        mutate(&statuses[idx])
    }

    private func loadCursor(providerId: String) -> SyncCursor {
        guard let data = defaults.data(forKey: cursorKey(providerId)) else { return .initial }
        return (try? cursorDecoder.decode(SyncCursor.self, from: data)) ?? .initial
    }

    private func saveCursor(_ cursor: SyncCursor, providerId: String) {
        guard let data = try? cursorEncoder.encode(cursor) else { return }
        defaults.set(data, forKey: cursorKey(providerId))
    }

    private func cursorKey(_ providerId: String) -> String {
        "todragdo.sync.cursor.\(providerId)"
    }
}
