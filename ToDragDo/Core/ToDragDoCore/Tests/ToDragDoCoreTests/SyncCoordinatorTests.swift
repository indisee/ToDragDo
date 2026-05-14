import Foundation
import Testing
@testable import ToDragDoCore

@MainActor
@Suite("SyncCoordinator")
struct SyncCoordinatorTests {

    private static let provider = "test-provider"

    private func makeSUT(
        adapter: any RemoteAdapter,
        deviceId: String = "device-A"
    ) -> (SyncCoordinator, Repository, InMemoryItemStorage) {
        let storage = InMemoryItemStorage()
        let repo = Repository(storage: storage, deviceId: deviceId)
        let defaults = UserDefaults(suiteName: "todragdo.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(applier: repo, defaults: defaults)
        coordinator.register(adapter)
        coordinator.setEnabled(true, for: adapter.providerId)
        return (coordinator, repo, storage)
    }

    @Test("register adds a SyncStatus with the adapter's displayName and disabled by default")
    func registerCreatesStatus() async throws {
        let storage = InMemoryItemStorage()
        let repo = Repository(storage: storage, deviceId: "test")
        let defaults = UserDefaults(suiteName: "todragdo.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(applier: repo, defaults: defaults)

        coordinator.register(FakeAdapter(providerId: "x", displayName: "X-Sync"))

        try #require(coordinator.statuses.count == 1)
        let status = coordinator.statuses[0]
        #expect(status.providerId == "x")
        #expect(status.displayName == "X-Sync")
        #expect(status.enabled == false)
    }

    @Test("sync skips a disabled provider")
    func syncSkipsDisabled() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        let storage = InMemoryItemStorage()
        let repo = Repository(storage: storage, deviceId: "test")
        let defaults = UserDefaults(suiteName: "todragdo.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(applier: repo, defaults: defaults)
        coordinator.register(adapter)
        // intentionally NOT enabled

        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        await coordinator.sync(Self.provider)

        #expect(await adapter.pushCallCount == 0)
        #expect(await adapter.pullCallCount == 0)
    }

    @Test("sync pushes pending changes and marks them pushed on success")
    func syncPushesAndMarks() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        let (coordinator, repo, _) = makeSUT(adapter: adapter)

        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        await coordinator.sync(Self.provider)

        #expect(await adapter.pushCallCount == 1)
        #expect(await adapter.lastPushedIds.count == 2)
        let remaining = try await repo.pendingPushCount(for: Self.provider)
        #expect(remaining == 0)

        let status = coordinator.statuses[0]
        #expect(status.lastError == nil)
        #expect(status.lastSuccess != nil)
        #expect(status.pendingPushCount == 0)
    }

    @Test("push failure leaves rows pending and captures error in status")
    func syncCapturesPushError() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        await adapter.setPushError(FakeError.network)
        let (coordinator, repo, _) = makeSUT(adapter: adapter)

        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        await coordinator.sync(Self.provider)

        let remaining = try await repo.pendingPushCount(for: Self.provider)
        #expect(remaining == 1, "Failed push keeps rows in the outbox")

        let status = coordinator.statuses[0]
        #expect(status.lastError != nil)
        #expect(status.lastSuccess == nil)
        #expect(status.pendingPushCount == 1)

        // The failed change has a recorded failure
        let pending = try await repo.pendingChanges(for: Self.provider)
        let failed = try await repo.syncStatus(
            forChange: pending[0].id,
            providerId: Self.provider
        )
        #expect(failed?.attemptCount == 1)
        #expect(failed?.lastError != nil)
    }

    @Test("partial push outcome marks succeeded ids pushed and leaves failed ids pending")
    func syncHandlesPartialPushOutcome() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        let (coordinator, repo, _) = makeSUT(adapter: adapter)

        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        // Pre-fetch the pending change IDs so we can target one for failure.
        let pendingBefore = try await repo.pendingChanges(for: Self.provider)
        try #require(pendingBefore.count == 2)
        let goodId = pendingBefore[0].id
        let badId = pendingBefore[1].id

        await adapter.setPushOutcome(PushOutcome(
            succeeded: [goodId],
            failed: [PushOutcome.Failure(id: badId, error: "schema mismatch")]
        ))

        await coordinator.sync(Self.provider)

        // Only the failed record remains in the outbox.
        let remaining = try await repo.pendingChanges(for: Self.provider)
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == badId)

        let status = coordinator.statuses[0]
        #expect(status.lastError != nil)
        #expect(status.pendingPushCount == 1)

        let failed = try await repo.syncStatus(forChange: badId, providerId: Self.provider)
        #expect(failed?.attemptCount == 1)
        #expect(failed?.lastError == "schema mismatch")

        // Succeeded record has no leftover pending row.
        let goodStatus = try await repo.syncStatus(forChange: goodId, providerId: Self.provider)
        #expect(goodStatus?.pushedAt != nil)
    }

    @Test("pull applies remote ChangeRecords to local storage")
    func pullAppliesRemoteChanges() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        let (coordinator, repo, _) = makeSUT(adapter: adapter, deviceId: "device-A")

        let remoteItem = Item(
            folder: .today,
            orderKey: 5,
            typeIdentifier: "text",
            payload: Data("hello".utf8),
            lastEditedBy: "device-B"
        )
        let remoteSnapshot = try JSONEncoder.iso.encode(remoteItem)
        let remoteRecord = ChangeRecord(
            entityType: "Item",
            entityId: remoteItem.id,
            op: .insert,
            snapshot: remoteSnapshot,
            deviceId: "device-B"
        )
        await adapter.queuePull(records: [remoteRecord], next: SyncCursor(token: "T1"))

        await coordinator.sync(Self.provider)

        let inToday = repo.items[.today] ?? []
        try #require(inToday.count == 1)
        #expect(inToday[0].id == remoteItem.id)
        #expect(inToday[0].lastEditedBy == "device-B")
    }

    @Test("echoed remote records (same deviceId) are dropped on apply")
    func pullDropsEchoes() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        let (coordinator, repo, _) = makeSUT(adapter: adapter, deviceId: "device-A")

        let echoItem = Item(
            folder: .today,
            orderKey: 1,
            typeIdentifier: "text",
            payload: Data(),
            lastEditedBy: "device-A"
        )
        let snapshot = try JSONEncoder.iso.encode(echoItem)
        let echo = ChangeRecord(
            entityType: "Item",
            entityId: echoItem.id,
            op: .insert,
            snapshot: snapshot,
            deviceId: "device-A"  // our own device
        )
        await adapter.queuePull(records: [echo], next: .initial)

        await coordinator.sync(Self.provider)

        let inToday = repo.items[.today] ?? []
        #expect(inToday.isEmpty, "Echo of our own write should not re-appear locally")
    }

    @Test("cursor advances and is persisted across sync calls")
    func cursorPersistsBetweenCalls() async throws {
        let adapter = FakeAdapter(providerId: Self.provider, displayName: "Fake")
        let (coordinator, _, _) = makeSUT(adapter: adapter)

        await adapter.queuePull(records: [], next: SyncCursor(token: "cursor-1"))
        await coordinator.sync(Self.provider)
        #expect(await adapter.lastPulledCursor == .initial)

        await adapter.queuePull(records: [], next: SyncCursor(token: "cursor-2"))
        await coordinator.sync(Self.provider)
        #expect(await adapter.lastPulledCursor == SyncCursor(token: "cursor-1"))
    }
}

// MARK: - Fakes

private enum FakeError: Error, LocalizedError {
    case network
    var errorDescription: String? { "fake network error" }
}

private actor FakeAdapter: RemoteAdapter {
    nonisolated let providerId: String
    nonisolated let displayName: String

    private(set) var pushCallCount = 0
    private(set) var pullCallCount = 0
    private(set) var lastPushedIds: [UUID] = []
    private(set) var lastPulledCursor: SyncCursor = .initial

    private var pushError: (any Error)?
    private var pushPartialOutcome: PushOutcome?
    private var queuedPull: (changes: [ChangeRecord], next: SyncCursor) = ([], .initial)

    init(providerId: String, displayName: String) {
        self.providerId = providerId
        self.displayName = displayName
    }

    func setPushError(_ error: (any Error)?) {
        self.pushError = error
    }

    /// When set, the next `push` returns this outcome verbatim instead of
    /// the default "everything succeeded" result.
    func setPushOutcome(_ outcome: PushOutcome?) {
        self.pushPartialOutcome = outcome
    }

    func queuePull(records: [ChangeRecord], next: SyncCursor) {
        self.queuedPull = (records, next)
    }

    func push(_ changes: [ChangeRecord]) async throws -> PushOutcome {
        pushCallCount += 1
        lastPushedIds = changes.map(\.id)
        if let pushError { throw pushError }
        if let pushPartialOutcome {
            self.pushPartialOutcome = nil
            return pushPartialOutcome
        }
        return .allSucceeded(changes.map(\.id))
    }

    func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor) {
        pullCallCount += 1
        lastPulledCursor = cursor
        let result = queuedPull
        queuedPull = ([], result.next)
        return result
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
