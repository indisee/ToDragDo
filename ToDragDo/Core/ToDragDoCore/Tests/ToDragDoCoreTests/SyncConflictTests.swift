import Foundation
import Testing
@testable import ToDragDoCore

/// Multi-device scenarios: two Repositories exchanging outbox rows the
/// way the sync pipe would, checking who wins.
@MainActor
@Suite("Sync conflicts")
struct SyncConflictTests {

    private static let provider = "p"

    private func makeDevice(_ id: String) -> Repository {
        Repository(storage: InMemoryItemStorage(), deviceId: id)
    }

    /// Deliver `from`'s pending outbox to `to` and mark it pushed.
    private func ship(from: Repository, to: Repository) async throws {
        let pending = try await from.pendingChanges(for: Self.provider, limit: 10_000)
        try await to.applyRemote(pending)
        try await from.markPushed(pending.map(\.id), to: Self.provider)
    }

    @Test("stale device rolling over on wake doesn't clobber later edits from another device")
    func staleRolloverLosesToLaterEdit() async throws {
        let storageA = InMemoryItemStorage()
        let storageB = InMemoryItemStorage()
        let a = Repository(storage: storageA, deviceId: "A")
        let b = Repository(storage: storageB, deviceId: "B")

        // Both devices hold the same item, last edited yesterday, sitting
        // in Tomorrow.
        let yesterday = Date().addingTimeInterval(-26 * 60 * 60)
        let item = Item(
            folder: .tomorrow,
            orderKey: 1,
            typeIdentifier: "t",
            payload: Data(),
            createdAt: yesterday,
            updatedAt: yesterday,
            lastEditedBy: "A"
        )
        try await storageA.upsertWithoutChange(item)
        try await storageB.upsertWithoutChange(item)

        // B wakes first, rolls over, then the user moves the item.
        try await b.rolloverDay()
        try await b.move(id: item.id, to: .libmo)

        // A wakes later with stale state and rolls over before pulling.
        try await a.rolloverDay()

        try await ship(from: a, to: b)
        try await ship(from: b, to: a)
        try await a.reload()
        try await b.reload()

        #expect(a.items[.libmo]?.map(\.id) == [item.id])
        #expect(b.items[.libmo]?.map(\.id) == [item.id])
    }

    @Test("rollover leaves Today items untouched and lifts Tomorrow above them")
    func rolloverOnlyTouchesTomorrow() async throws {
        let a = makeDevice("A")
        let todayItem = try await a.add(folder: .today, typeIdentifier: "t", payload: Data())
        let tomorrow1 = try await a.add(folder: .tomorrow, typeIdentifier: "t", payload: Data())
        let tomorrow2 = try await a.add(folder: .tomorrow, typeIdentifier: "t", payload: Data())
        try await a.markPushed(
            a.pendingChanges(for: Self.provider, limit: 100).map(\.id),
            to: Self.provider
        )
        let tomorrowOrder = a.items[.tomorrow]?.map(\.id)

        try await a.rolloverDay()

        let pending = try await a.pendingChanges(for: Self.provider, limit: 100)
        #expect(Set(pending.map(\.entityId)) == [tomorrow1.id, tomorrow2.id])
        #expect(a.items[.today]?.map(\.id) == (tomorrowOrder ?? []) + [todayItem.id])
        #expect(a.items[.tomorrow]?.isEmpty ?? true)
    }

    @Test("equal updatedAt resolves the same way on both devices")
    func tieBreakConverges() {
        let t = Date()
        #expect(Item.remoteWins(remote: (t, "B"), over: (t, "A")))
        #expect(!Item.remoteWins(remote: (t, "A"), over: (t, "B")))
        #expect(!Item.remoteWins(remote: (t, "A"), over: (t, "A")))
    }

    @Test("overlapping sync calls never run two pulls at once")
    func syncCyclesDoNotOverlap() async throws {
        let adapter = OverlapProbeAdapter()
        let repo = makeDevice("A")
        let defaults = UserDefaults(suiteName: "todragdo.tests.\(UUID().uuidString)")!
        let coordinator = SyncCoordinator(applier: repo, defaults: defaults)
        coordinator.register(adapter)
        coordinator.setEnabled(true, for: adapter.providerId)

        async let s1: Void = coordinator.sync(adapter.providerId)
        async let s2: Void = coordinator.sync(adapter.providerId)
        async let s3: Void = coordinator.sync(adapter.providerId)
        _ = await (s1, s2, s3)

        #expect(await adapter.maxConcurrentPulls == 1)
        // Callers that arrive before or during a cycle coalesce into it
        // (plus at most one follow-up) instead of each running their own.
        #expect(await adapter.pullCount <= 2)
    }
}

private actor OverlapProbeAdapter: RemoteAdapter {
    nonisolated let providerId = "probe"
    nonisolated let displayName = "Probe"
    private var active = 0
    private(set) var maxConcurrentPulls = 0
    private(set) var pullCount = 0

    func push(_ changes: [ChangeRecord]) async throws -> PushOutcome {
        .allSucceeded(changes.map(\.id))
    }

    func pull(since cursor: SyncCursor) async throws -> (changes: [ChangeRecord], next: SyncCursor) {
        active += 1
        pullCount += 1
        maxConcurrentPulls = max(maxConcurrentPulls, active)
        try await Task.sleep(nanoseconds: 20_000_000)
        active -= 1
        return ([], cursor)
    }
}
