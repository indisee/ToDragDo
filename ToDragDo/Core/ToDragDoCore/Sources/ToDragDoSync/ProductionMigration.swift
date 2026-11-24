import Foundation
import OSLog
import ToDragDoCore

/// One-time Development → Production CloudKit migration, run on the first
/// launch of a Production-signed build.
///
/// A binary talks to exactly one CloudKit environment (chosen by the signed
/// entitlement), so Production can't read the Development database. The
/// local store is the source instead. On the first successful pull from
/// Production, before the pulled records are applied:
///
/// 1. All local data is written to a JSON backup (`RepositoryBackup`).
/// 2. Every local item and project the pull did **not** contain is queued
///    for upload via `Repository.resyncAllItems(excluding:)`.
///
/// The first device to run this finds Production empty and uploads
/// everything. Later devices find that data already there and only upload
/// what they alone have, so they never overwrite records another device
/// pushed (`applyRemote` has no newer-wins check). Only a simultaneous
/// first launch on two devices can still race; the backup covers that.
@MainActor
public final class ProductionMigration {
    public static let doneKey = "todragdo.migration.production.done"
    /// Human-readable result, shown in Settings → Sync.
    public static let summaryKey = "todragdo.migration.production.summary"
    public static let backupFilePrefix = "pre-production"

    private let repository: Repository
    private let coordinator: SyncCoordinator
    private let backupDirectory: URL
    private let environment: String?
    private let providerId: String
    private let defaults: UserDefaults
    private let log = Logger.todragdo(category: "ProdMigration")
    private var inProgress = false

    public init(
        repository: Repository,
        coordinator: SyncCoordinator,
        backupDirectory: URL,
        environment: String? = CloudKitEnvironmentProbe.resolved,
        providerId: String = CloudKitConfig.providerId,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.coordinator = coordinator
        self.backupDirectory = backupDirectory
        self.environment = environment
        self.providerId = providerId
        self.defaults = defaults
    }

    /// Whether this launch still has to migrate.
    public var isPending: Bool {
        environment == "Production" && !defaults.bool(forKey: Self.doneKey)
    }

    /// Call once at launch, before the first sync cycle can run. No-op
    /// outside Production or once the migration has completed.
    public func start() {
        guard isPending else { return }
        log.notice("Production migration armed; waiting for the first pull")
        coordinator.pullObserver = { [weak self] providerId, changes in
            await self?.handlePull(providerId: providerId, changes: changes)
        }
    }

    /// Runs inside the sync cycle, after a successful pull and before the
    /// pulled records are applied. Exposed for tests.
    func handlePull(providerId: String, changes: [ChangeRecord]) async {
        guard providerId == self.providerId, isPending, !inProgress else { return }
        inProgress = true
        defer { inProgress = false }

        do {
            let backup = try await repository.makeBackup()
            guard !backup.isEmpty else {
                finish(summary: "Nothing to migrate: no local data.")
                return
            }
            let backupURL = try backup.write(to: backupDirectory, prefix: Self.backupFilePrefix)

            let remoteIds = Set(
                changes
                    .filter { $0.entityType != SettingsSnapshot.entityType }
                    .map(\.entityId)
            )
            let queued = try await repository.resyncAllItems(excluding: remoteIds)
            let localCount = backup.items.count + backup.projects.count
            let summary = remoteIds.isEmpty
                ? "Uploaded \(queued) of \(localCount) local records to Production. Backup: \(backupURL.path)"
                : "Production already had \(remoteIds.count) records; uploaded \(queued) missing ones. Backup: \(backupURL.path)"
            finish(summary: summary)
        } catch {
            // Nothing is marked done, so the next successful pull retries.
            // By then this pull's records are applied locally, so local
            // copies of them match the remote and re-uploading is harmless.
            log.error("Production migration failed: \(error.localizedDescription)")
            defaults.set("Migration failed, will retry: \(error.localizedDescription)", forKey: Self.summaryKey)
        }
    }

    private func finish(summary: String) {
        defaults.set(true, forKey: Self.doneKey)
        defaults.set(summary, forKey: Self.summaryKey)
        coordinator.pullObserver = nil
        log.notice("Production migration done: \(summary)")
    }
}
