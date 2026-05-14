import Foundation
import Testing
@testable import ToDragDoCore

@MainActor
@Suite("Repository")
struct RepositoryTests {

    private static let provider = "test-provider"

    private func makeSUT() -> (Repository, InMemoryItemStorage) {
        let storage = InMemoryItemStorage()
        let repo = Repository(storage: storage, deviceId: "test-device")
        return (repo, storage)
    }

    @Test("add inserts an item with consistent timestamps and no soft-delete")
    func addInsertsItem() async throws {
        let (repo, _) = makeSUT()
        let item = try await repo.add(
            folder: .today,
            typeIdentifier: "text/plain",
            payload: Data("hello".utf8)
        )
        #expect(item.folder == .today)
        #expect(item.deletedAt == nil)
        #expect(item.createdAt == item.updatedAt)
        #expect(item.lastEditedBy == "test-device")
        #expect(repo.items[.today]?.count == 1)
        #expect(repo.items[.today]?.first?.id == item.id)
    }

    @Test("add produces exactly one insert ChangeRecord")
    func addProducesInsertChange() async throws {
        let (repo, storage) = makeSUT()
        let item = try await repo.add(
            folder: .today,
            typeIdentifier: "text/plain",
            payload: Data("a".utf8)
        )
        let pending = try await repo.pendingChanges(for: Self.provider)
        #expect(pending.count == 1)
        let change = try #require(pending.first)
        #expect(change.op == .insert)
        #expect(change.entityId == item.id)
        #expect(change.entityType == "Item")
        let allChanges = await storage.allChanges()
        #expect(allChanges.count == 1)
    }

    @Test("update bumps updatedAt and emits an update change")
    func updateBumpsTimestampAndEmitsChange() async throws {
        let (repo, _) = makeSUT()
        let original = try await repo.add(
            folder: .today,
            typeIdentifier: "text/plain",
            payload: Data("a".utf8)
        )
        try await Task.sleep(nanoseconds: 1_000_000)
        try await repo.update(id: original.id) { item in
            item.payload = Data("b".utf8)
        }
        let updated = try #require(repo.items[.today]?.first)
        #expect(updated.payload == Data("b".utf8))
        #expect(updated.updatedAt > original.updatedAt)

        let pending = try await repo.pendingChanges(for: Self.provider)
        #expect(pending.count == 2)
        #expect(pending.last?.op == .update)
    }

    @Test("move changes folder and assigns end-of-destination orderKey")
    func moveTransitionsFolder() async throws {
        let (repo, _) = makeSUT()
        let a = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let b = try await repo.add(folder: .tomorrow, typeIdentifier: "t", payload: Data())

        try await repo.move(id: a.id, to: .tomorrow)

        let tomorrow = try #require(repo.items[.tomorrow])
        #expect(tomorrow.count == 2)
        #expect(tomorrow.last?.id == a.id)
        #expect(tomorrow.last!.orderKey > b.orderKey)
        #expect(repo.items[.today]?.isEmpty == true)
    }

    @Test("softDelete hides the item from default reads but keeps the row")
    func softDeleteHidesItem() async throws {
        let (repo, storage) = makeSUT()
        let item = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        try await repo.softDelete(id: item.id)

        #expect(repo.items[.today]?.isEmpty == true)
        let underlying = try await storage.item(id: item.id)
        #expect(underlying?.deletedAt != nil)

        let pending = try await repo.pendingChanges(for: Self.provider)
        #expect(pending.last?.op == .softDelete)
    }

    @Test("emptyDone removes only Done items and emits hardDelete changes")
    func emptyDoneClearsDone() async throws {
        let (repo, storage) = makeSUT()
        _ = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let d1 = try await repo.add(folder: .done, typeIdentifier: "t", payload: Data())
        let d2 = try await repo.add(folder: .done, typeIdentifier: "t", payload: Data())

        try await repo.emptyDone()

        #expect(repo.items[.done]?.isEmpty == true)
        #expect(repo.items[.today]?.count == 1)
        #expect(await storage.itemCount() == 1)

        let hardDeletes = try await repo.pendingChanges(for: Self.provider)
            .filter { $0.op == .hardDelete }
            .map(\.entityId)
            .sorted { $0.uuidString < $1.uuidString }
        let expected = [d1.id, d2.id].sorted { $0.uuidString < $1.uuidString }
        #expect(hardDeletes == expected)
    }

    @Test("update on missing id throws notFound")
    func updateMissingIdThrows() async throws {
        let (repo, _) = makeSUT()
        let bogus = UUID()
        await #expect(throws: StorageError.notFound(bogus)) {
            try await repo.update(id: bogus) { _ in }
        }
    }

    @Test("add prepends new items to the folder")
    func addPrepends() async throws {
        let (repo, _) = makeSUT()
        let a = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("a".utf8))
        let b = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("b".utf8))
        let c = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("c".utf8))

        let order = try #require(repo.items[.today]).map(\.id)
        #expect(order == [c.id, b.id, a.id])
    }

    @Test("reorder before target inserts between target's predecessor and target")
    func reorderBeforeTargetInsertsAbove() async throws {
        let (repo, _) = makeSUT()
        // Add prepends, so the resulting order is c, b, a.
        let a = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("a".utf8))
        let b = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("b".utf8))
        let c = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("c".utf8))

        // Move a to sit before b. New order: c, a, b.
        try await repo.reorder(id: a.id, before: b.id)

        let order = try #require(repo.items[.today]).map(\.id)
        #expect(order == [c.id, a.id, b.id])
    }

    @Test("reorder before nil appends to the end")
    func reorderBeforeNilAppends() async throws {
        let (repo, _) = makeSUT()
        // Add prepends, so the resulting order is c, b, a.
        let a = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let b = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let c = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        // Move c to the end. New order: b, a, c.
        try await repo.reorder(id: c.id, before: nil)

        let order = try #require(repo.items[.today]).map(\.id)
        #expect(order == [b.id, a.id, c.id])
    }

    @Test("reorder before the first item lands the dragged item at the top")
    func reorderBeforeFirstItem() async throws {
        let (repo, _) = makeSUT()
        // Add prepends, so the resulting order is c, b, a.
        let a = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let b = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let c = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        // Move a above c (the current top). New order: a, c, b.
        try await repo.reorder(id: a.id, before: c.id)

        let order = try #require(repo.items[.today]).map(\.id)
        #expect(order == [a.id, c.id, b.id])
    }

    @Test("reorder onto self is a no-op")
    func reorderOntoSelfNoOp() async throws {
        let (repo, _) = makeSUT()
        let a = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())
        let b = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data())

        try await repo.reorder(id: a.id, before: a.id)

        // Add prepends, so b lands above a.
        let order = try #require(repo.items[.today]).map(\.id)
        #expect(order == [b.id, a.id])
    }

    @Test("resyncAllItems appends a fresh outbox row per item, marked pending for the provider")
    func resyncAllItemsAppendsPendingRows() async throws {
        let (repo, storage) = makeSUT()

        let live = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("a".utf8))
        let alsoLive = try await repo.add(folder: .libmo, typeIdentifier: "t", payload: Data("b".utf8))
        let toDelete = try await repo.add(folder: .today, typeIdentifier: "t", payload: Data("c".utf8))
        try await repo.softDelete(id: toDelete.id)

        // Simulate that the existing outbox is fully pushed to the
        // provider — this is the state right after switching env, where
        // pre-existing changes are marked pushed but the new environment
        // is empty.
        let pendingBefore = try await repo.pendingChanges(for: Self.provider)
        try await repo.markPushed(pendingBefore.map(\.id), to: Self.provider)
        #expect(try await repo.pendingPushCount(for: Self.provider) == 0)

        let count = try await repo.resyncAllItems()
        #expect(count == 3)

        let pending = try await repo.pendingChanges(for: Self.provider)
        #expect(pending.count == 3)

        let opsByEntity = Dictionary(uniqueKeysWithValues: pending.map { ($0.entityId, $0.op) })
        #expect(opsByEntity[live.id] == .update)
        #expect(opsByEntity[alsoLive.id] == .update)
        #expect(opsByEntity[toDelete.id] == .softDelete)

        // Each snapshot decodes back to a current-state Item with the
        // right id and (for the deleted one) deletedAt populated.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for change in pending {
            let decoded = try decoder.decode(Item.self, from: change.snapshot)
            #expect(decoded.id == change.entityId)
            if change.entityId == toDelete.id {
                #expect(decoded.deletedAt != nil)
            } else {
                #expect(decoded.deletedAt == nil)
            }
        }

        // The local item table is unchanged — resync only touches the outbox.
        let storageCount = await storage.itemCount()
        #expect(storageCount == 3)
    }

    @Test("ChangeRecord snapshot decodes back to the saved Item")
    func snapshotRoundTrips() async throws {
        let (repo, _) = makeSUT()
        let item = try await repo.add(
            folder: .libmo,
            typeIdentifier: "text/plain",
            payload: Data("snap".utf8)
        )
        let change = try #require(try await repo.pendingChanges(for: Self.provider).first)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Item.self, from: change.snapshot)
        #expect(decoded.id == item.id)
        #expect(decoded.folder == .libmo)
        #expect(decoded.payload == Data("snap".utf8))
    }
}
