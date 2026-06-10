import Foundation
import ToDragDoCore
import ToDragDoSync

/// Per-process holder for the App Group SwiftData `Repository` so the
/// widget extension and any AppIntent can read/write the same store the
/// host app uses. Holds the storage handle for the lifetime of the
/// extension process to avoid the ~tens-of-ms open cost on every call.
@MainActor
public enum IntentStorage {
    private static var cached: Repository?
    private static var didInitialReload = false

    /// Returns the cached `Repository`, opening the App Group store on
    /// first call. Does NOT reload — callers that want fresh data must
    /// call `reload()` first. (Reading projects/items from `Repository`
    /// after `reload()` is the canonical path.)
    public static func sharedRepository() throws -> Repository {
        if let cached { return cached }
        let storeURL = AppGroup.containerURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
        let outcome = StorageFactory.makeItemStorageWithRecovery(url: storeURL)
        guard let storage = outcome.storage else {
            throw IntentStorageError.unrecoverable
        }
        let repository = Repository(storage: storage)
        cached = repository
        return repository
    }

    /// Refreshes the cached repository (or opens it first if needed) so
    /// `repository.projects` / `.items` reflect the latest committed rows.
    @discardableResult
    public static func reload() async throws -> Repository {
        let repo = try sharedRepository()
        try await repo.reload()
        didInitialReload = true
        return repo
    }

    /// Convenience wrapper that handles the "open store, add an item,
    /// best-effort sync, set fallback flag on timeout" path used by the
    /// Action Button intent. Returns the inserted item id.
    @discardableResult
    public static func appendTextItem(
        note: String,
        folder: Folder,
        projectId: UUID? = nil,
        iCloudContainerIdentifier: String
    ) async throws -> UUID {
        let repository = try await reload()
        let payload = ItemPayload(note: note, attachments: [])
        let resolvedProject = projectId ?? repository.projects.first?.id
        let item = try await repository.add(
            folder: folder,
            typeIdentifier: "text/plain",
            payload: try payload.encoded(),
            projectId: resolvedProject
        )
        await bestEffortSync(repository: repository, container: iCloudContainerIdentifier)
        return item.id
    }

    /// Stands up a one-shot SyncCoordinator + CloudKitRemoteAdapter and
    /// awaits a single sync round with a short timeout. Sets the
    /// `pendingActionButtonSync` flag in AppGroup defaults if the sync
    /// throws / times out so the main app drains on next foreground.
    private static func bestEffortSync(
        repository: Repository,
        container: String
    ) async {
        let assetDirectory = AppGroup.containerURL
            .appendingPathComponent("CloudKitAssets", isDirectory: true)
        let coordinator = SyncCoordinator(applier: repository, defaults: AppGroup.defaults)
        let adapter = CloudKitRemoteAdapter(
            containerIdentifier: container,
            assetDirectory: assetDirectory
        )
        coordinator.register(adapter)

        let syncTask = Task { await coordinator.sync(adapter.providerId) }
        let timeout: UInt64 = 12_000_000_000 // 12s — leaves headroom in the ~30s extension budget
        let timeoutTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: timeout)
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await syncTask.value }
            group.addTask { await timeoutTask.value }
            await group.next()
            group.cancelAll()
        }

        let succeeded = coordinator.statuses
            .first(where: { $0.providerId == adapter.providerId })?
            .lastError == nil
        if !succeeded {
            AppGroup.defaults.set(true, forKey: AppGroup.Keys.pendingActionButtonSync)
        }
    }
}

public enum IntentStorageError: Error {
    case unrecoverable
}
