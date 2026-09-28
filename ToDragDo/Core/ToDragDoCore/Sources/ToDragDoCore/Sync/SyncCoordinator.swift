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
    /// One sync cycle per provider at a time. `CloudKitRemoteAdapter`
    /// keeps per-call buffers (`pullBuffer`, `cycleSucceeded`), so two
    /// overlapping cycles clobber each other — a second `pull` wipes the
    /// records the first one already fetched, and since CKSyncEngine has
    /// advanced its state token those records are never redelivered.
    private var inFlight: [String: Task<Void, Never>] = [:]
    /// Providers that got a `sync` request while a cycle was running.
    /// The running task loops once more so the caller's request is
    /// served by a cycle that *started* after it asked.
    private var rerunRequested: Set<String> = []

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

    /// Runs a pull-then-push cycle for `providerId`. Concurrent calls are
    /// coalesced: if a cycle is already running, the caller waits for it
    /// plus one follow-up cycle instead of starting an overlapping one.
    public func sync(_ providerId: String) async {
        if let running = inFlight[providerId] {
            rerunRequested.insert(providerId)
            await running.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.rerunRequested.remove(providerId)
                await self.runCycle(providerId)
            } while self.rerunRequested.contains(providerId)
            self.inFlight[providerId] = nil
        }
        inFlight[providerId] = task
        await task.value
    }

    private func runCycle(_ providerId: String) async {
        guard let adapter = adapters[providerId] else { return }
        guard statuses.first(where: { $0.providerId == providerId })?.enabled == true else { return }

        updateStatus(providerId: providerId) { $0.lastAttempt = .now }

        // Track pull and push errors separately so we report both when both
        // fail — the previous code overwrote the pull error with the push
        // error and silently lost half the diagnostic context.
        var pullError: (any Error)?
        var pushError: (any Error)?

        // Pull
        let cursor = cursors[providerId] ?? .initial
        do {
            let (changes, next) = try await adapter.pull(since: cursor)
            try await applier.applyRemote(changes)
            cursors[providerId] = next
            saveCursor(next, providerId: providerId)
        } catch {
            pullError = error
        }

        // Push — attempt regardless of pull outcome so a transient pull
        // failure doesn't block local writes from reaching the remote.
        do {
            let pending = try await applier.pendingChanges(for: providerId, limit: 500)
            if !pending.isEmpty {
                let ids = pending.map(\.id)
                do {
                    let outcome = try await adapter.push(pending)
                    if !outcome.succeeded.isEmpty {
                        try await applier.markPushed(outcome.succeeded, to: providerId)
                    }
                    // Group failures by error string so we issue one
                    // recordPushFailure per distinct error rather than one
                    // per record. Reduces storage churn when CloudKit
                    // rejects a whole batch with the same reason.
                    if !outcome.failed.isEmpty {
                        let byError = Dictionary(grouping: outcome.failed, by: \.error)
                        for (errorString, group) in byError {
                            try? await applier.recordPushFailure(
                                group.map(\.id),
                                to: providerId,
                                error: errorString
                            )
                        }
                        pushError = PushFailedError(failures: outcome.failed)
                    }
                } catch {
                    try? await applier.recordPushFailure(
                        ids,
                        to: providerId,
                        error: descriptionFor(error)
                    )
                    pushError = error
                }
            }
        } catch {
            pushError = error
        }

        let count = (try? await applier.pendingPushCount(for: providerId)) ?? 0
        updateStatus(providerId: providerId) { s in
            s.pendingPushCount = count
            switch (pullError, pushError) {
            case (nil, nil):
                s.lastSuccess = .now
                s.lastError = nil
            case (let p?, nil):
                s.lastError = "Pull: " + descriptionFor(p)
            case (nil, let p?):
                s.lastError = "Push: " + descriptionFor(p)
            case (let pull?, let push?):
                s.lastError = """
                Pull: \(descriptionFor(pull))

                Push: \(descriptionFor(push))
                """
            }
        }
    }

    /// Prefer `LocalizedError.errorDescription` (which our CloudKit
    /// wrapper populates with the full multi-line CKError chain) over
    /// `localizedDescription` (which CloudKit collapses to a generic
    /// string like "Failed to send changes").
    private func descriptionFor(_ error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return error.localizedDescription
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

/// Error surfaced via `SyncStatus.lastError` when one or more records in a
/// push batch failed but others may have succeeded. Distinct from a thrown
/// batch-level error so the UI can render "N of M failed" later.
public struct PushFailedError: Error, LocalizedError {
    public let failures: [PushOutcome.Failure]

    public var errorDescription: String? {
        // Preserve order of first occurrence while collapsing duplicates.
        // CloudKit typically rejects every record in a batch with the same
        // root cause; rendering it once with a record count keeps the UI
        // readable without truncating the underlying reason.
        var seen = Set<String>()
        var unique: [(reason: String, count: Int)] = []
        for failure in failures {
            if seen.insert(failure.error).inserted {
                unique.append((failure.error, 1))
            } else if let idx = unique.firstIndex(where: { $0.reason == failure.error }) {
                unique[idx].count += 1
            }
        }

        if unique.count == 1 {
            let entry = unique[0]
            if entry.count == 1 {
                return entry.reason
            }
            return "\(entry.count) records failed with:\n\(entry.reason)"
        }

        var blocks: [String] = ["\(failures.count) records failed (\(unique.count) distinct reasons):"]
        for entry in unique {
            blocks.append("— \(entry.count)× —\n\(entry.reason)")
        }
        return blocks.joined(separator: "\n\n")
    }
}
