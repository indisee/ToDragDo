import Foundation
import Testing
@testable import ToDragDoCore
@testable import ToDragDoSync

@MainActor
@Suite("ProductionMigration")
struct ProductionMigrationTests {

    private static let provider = "icloud-test"

    private struct SUT {
        let repo: Repository
        let coordinator: SyncCoordinator
        let adapter: ScriptedAdapter
        let migration: ProductionMigration
        let defaults: UserDefaults
        let backupDir: URL
    }

    private func makeSUT(environment: String?) -> SUT {
        let repo = Repository(storage: InMemoryItemStorage(), deviceId: "device-A")
        let defaults = UserDefaults(suiteName: "todragdo.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(applier: repo, defaults: defaults)
        let adapter = ScriptedAdapter(providerId: Self.provider)
        coordinator.register(adapter)
        coordinator.setEnabled(true, for: Self.provider)
        let backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todragdo-backup-tests-\(UUID().uuidString)", isDirectory: true)
        let migration = ProductionMigration(
            repository: repo,
            coordinator: coordinator,
            backupDirectory: backupDir,
            environment: environment,
            providerId: Self.provider,
            defaults: defaults
        )
        return SUT(repo: repo, coordinator: coordinator, adapter: adapter,
                   migration: migration, defaults: defaults, backupDir: backupDir)
    }

    /// The state right after switching environments: local data exists,
    /// and every outbox row is already marked pushed (to Development).
    private func seedPushedLocalData(_ sut: SUT) async throws -> [Item] {
        let a = try await sut.repo.add(folder: .today, typeIdentifier: "t", payload: Data("a".utf8))
        let b = try await sut.repo.add(folder: .libmo, typeIdentifier: "t", payload: Data("b".utf8))
        let pending = try await sut.repo.pendingChanges(for: Self.provider)
        try await sut.repo.markPushed(pending.map(\.id), to: Self.provider)
        return [a, b]
    }

    private func backupFiles(_ sut: SUT) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: sut.backupDir, includingPropertiesForKeys: nil)) ?? []
    }

    @Test("empty Production: backs up and uploads every local item and project")
    func uploadsEverythingWhenProductionEmpty() async throws {
        let sut = makeSUT(environment: "Production")
        let items = try await seedPushedLocalData(sut)
        let projectIds = Set(sut.repo.projects.map(\.id))

        sut.migration.start()
        await sut.coordinator.sync(Self.provider)

        let pushed = Set(await sut.adapter.pushedEntityIds)
        #expect(pushed == Set(items.map(\.id)).union(projectIds))
        #expect(sut.defaults.bool(forKey: ProductionMigration.doneKey))
        #expect(sut.coordinator.pullObserver == nil)

        let files = backupFiles(sut)
        try #require(files.count == 1)
        let backup = try RepositoryBackup.decode(from: Data(contentsOf: files[0]))
        #expect(Set(backup.items.map(\.id)) == Set(items.map(\.id)))
        #expect(backup.projects.count == projectIds.count)
    }

    @Test("Production with data: uploads only what is missing, backup holds pre-pull state")
    func uploadsOnlyMissingWhenProductionHasData() async throws {
        let sut = makeSUT(environment: "Production")
        let items = try await seedPushedLocalData(sut)
        let (a, b) = (items[0], items[1])

        // Another device already migrated item `a`, with a newer payload.
        var remoteA = a
        remoteA.payload = Data("a-from-device-B".utf8)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let remoteRecord = ChangeRecord(
            entityType: "Item", entityId: a.id, op: .update,
            snapshot: try encoder.encode(remoteA), deviceId: "device-B", ts: .now
        )
        // Projects pushed by device B as well.
        let remoteProjects = try sut.repo.projects.map {
            ChangeRecord(entityType: "Project", entityId: $0.id, op: .update,
                         snapshot: try encoder.encode($0), deviceId: "device-B", ts: .now)
        }
        await sut.adapter.queuePull([remoteRecord] + remoteProjects)

        sut.migration.start()
        await sut.coordinator.sync(Self.provider)

        #expect(await sut.adapter.pushedEntityIds == [b.id])
        #expect(sut.defaults.bool(forKey: ProductionMigration.doneKey))

        let backup = try RepositoryBackup.decode(from: Data(contentsOf: try #require(backupFiles(sut).first)))
        let backedUpA = try #require(backup.items.first { $0.id == a.id })
        #expect(backedUpA.payload == Data("a".utf8))
    }

    @Test("Development build: does nothing")
    func noOpOutsideProduction() async throws {
        let sut = makeSUT(environment: "Development")
        _ = try await seedPushedLocalData(sut)

        sut.migration.start()
        await sut.coordinator.sync(Self.provider)

        #expect(await sut.adapter.pushedEntityIds.isEmpty)
        #expect(!sut.defaults.bool(forKey: ProductionMigration.doneKey))
        #expect(backupFiles(sut).isEmpty)
    }

    @Test("runs once: later syncs don't re-upload")
    func runsOnce() async throws {
        let sut = makeSUT(environment: "Production")
        _ = try await seedPushedLocalData(sut)

        sut.migration.start()
        await sut.coordinator.sync(Self.provider)
        await sut.adapter.resetPushed()
        await sut.coordinator.sync(Self.provider)

        #expect(await sut.adapter.pushedEntityIds.isEmpty)
        #expect(backupFiles(sut).count == 1)

        // A new launch with the flag set doesn't arm it again.
        sut.migration.start()
        #expect(sut.coordinator.pullObserver == nil)
    }
}

private actor ScriptedAdapter: RemoteAdapter {
    nonisolated let providerId: String
    nonisolated let displayName = "Scripted"
    private(set) var pushedEntityIds: [UUID] = []
    private var queuedPull: [ChangeRecord] = []

    init(providerId: String) { self.providerId = providerId }

    func queuePull(_ records: [ChangeRecord]) { queuedPull = records }
    func resetPushed() { pushedEntityIds = [] }

    func push(_ changes: [ChangeRecord]) async throws -> PushOutcome {
        pushedEntityIds += changes.map(\.entityId)
        return .allSucceeded(changes.map(\.id))
    }

    func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor) {
        defer { queuedPull = [] }
        return (queuedPull, cursor)
    }
}
