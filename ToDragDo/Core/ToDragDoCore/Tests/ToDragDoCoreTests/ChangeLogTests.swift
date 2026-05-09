import Foundation
import Testing
@testable import ToDragDoCore

@MainActor
@Suite("ChangeLog (outbox)")
struct ChangeLogTests {

    private static let providerA = "provider-a"
    private static let providerB = "provider-b"

    private func makeSUT() -> (Repository, InMemoryItemStorage) {
        let storage = InMemoryItemStorage()
        let repo = Repository(storage: storage, deviceId: "test-device")
        return (repo, storage)
    }

    @Test("pendingChanges returns rows in chronological order")
    func pendingIsChronological() async throws {
        let (repo, _) = makeSUT()
        for i in 0..<5 {
            _ = try await repo.add(
                folder: .today,
                typeIdentifier: "text/plain",
                payload: Data("\(i)".utf8)
            )
        }
        let pending = try await repo.pendingChanges(for: Self.providerA)
        #expect(pending.count == 5)
        let timestamps = pending.map(\.ts)
        #expect(timestamps == timestamps.sorted())
    }

    @Test("markPushed for one provider does not affect another")
    func markPushedIsPerProvider() async throws {
        let (repo, _) = makeSUT()
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        var pendingA = try await repo.pendingChanges(for: Self.providerA)
        var pendingB = try await repo.pendingChanges(for: Self.providerB)
        #expect(pendingA.count == 2)
        #expect(pendingB.count == 2)

        try await repo.markPushed(pendingA.map(\.id), to: Self.providerA)

        pendingA = try await repo.pendingChanges(for: Self.providerA)
        pendingB = try await repo.pendingChanges(for: Self.providerB)
        #expect(pendingA.isEmpty)
        #expect(pendingB.count == 2, "Provider B should still see all pending changes")
    }

    @Test("pendingChanges respects the limit")
    func pendingRespectsLimit() async throws {
        let (repo, _) = makeSUT()
        for i in 0..<10 {
            _ = try await repo.add(
                folder: .today,
                typeIdentifier: "text/plain",
                payload: Data("\(i)".utf8)
            )
        }
        let limited = try await repo.pendingChanges(for: Self.providerA, limit: 3)
        #expect(limited.count == 3)
    }

    @Test("pendingPushCount mirrors pendingChanges")
    func pendingPushCountTracksList() async throws {
        let (repo, _) = makeSUT()
        for _ in 0..<4 {
            _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        }
        var count = try await repo.pendingPushCount(for: Self.providerA)
        #expect(count == 4)

        let pending = try await repo.pendingChanges(for: Self.providerA)
        try await repo.markPushed(Array(pending.prefix(2).map(\.id)), to: Self.providerA)

        count = try await repo.pendingPushCount(for: Self.providerA)
        #expect(count == 2)
    }

    @Test("markPushed creates a sync status with pushedAt set and no error")
    func markPushedWritesStatus() async throws {
        let (repo, _) = makeSUT()
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let change = try #require(try await repo.pendingChanges(for: Self.providerA).first)

        try await repo.markPushed([change.id], to: Self.providerA)

        let status = try #require(
            try await repo.syncStatus(forChange: change.id, providerId: Self.providerA)
        )
        #expect(status.changeId == change.id)
        #expect(status.providerId == Self.providerA)
        #expect(status.pushedAt != nil)
        #expect(status.lastError == nil)
    }

    @Test("recordPushFailure bumps attemptCount and stores error without setting pushedAt")
    func failureBumpsAttemptAndKeepsPending() async throws {
        let (repo, _) = makeSUT()
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let change = try #require(try await repo.pendingChanges(for: Self.providerA).first)

        try await repo.recordPushFailure([change.id], to: Self.providerA, error: "network down")
        try await repo.recordPushFailure([change.id], to: Self.providerA, error: "still down")

        let status = try #require(
            try await repo.syncStatus(forChange: change.id, providerId: Self.providerA)
        )
        #expect(status.attemptCount == 2)
        #expect(status.lastError == "still down")
        #expect(status.pushedAt == nil)
        #expect(status.lastAttemptAt != nil)

        let stillPending = try await repo.pendingChanges(for: Self.providerA)
        #expect(stillPending.count == 1, "Failed pushes stay in the pending list")
    }

    @Test("markPushed after a failure clears lastError")
    func successAfterFailureClearsError() async throws {
        let (repo, _) = makeSUT()
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let change = try #require(try await repo.pendingChanges(for: Self.providerA).first)

        try await repo.recordPushFailure([change.id], to: Self.providerA, error: "transient")
        try await repo.markPushed([change.id], to: Self.providerA)

        let status = try #require(
            try await repo.syncStatus(forChange: change.id, providerId: Self.providerA)
        )
        #expect(status.pushedAt != nil)
        #expect(status.lastError == nil)
        #expect(status.attemptCount == 1, "attemptCount is preserved across success")
    }

    @Test("NoopRemoteAdapter conforms to the multi-provider protocol")
    func noopAdapterCompiles() async throws {
        let adapter: any RemoteAdapter = NoopRemoteAdapter(
            providerId: "icloud",
            displayName: "iCloud"
        )
        #expect(adapter.providerId == "icloud")
        #expect(adapter.displayName == "iCloud")
        try await adapter.push([])
        let (changes, next) = try await adapter.pull(since: .initial)
        #expect(changes.isEmpty)
        #expect(next == .initial)
    }
}
