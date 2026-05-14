import Foundation

/// What `SyncCoordinator` needs from local persistence to run a sync cycle:
/// read the outbox for a provider, mark rows pushed or failed, and apply
/// pulled remote changes back to local state **without** re-emitting outbox
/// rows (those records came from the remote — pushing them back would loop).
///
/// `Repository` is the production conformer; tests can use a real Repository
/// over an in-memory `ItemStorage` fake.
@MainActor
public protocol RemoteApplier {
    var deviceId: String { get }

    func pendingChanges(for providerId: String, limit: Int) async throws -> [ChangeRecord]
    func pendingPushCount(for providerId: String) async throws -> Int
    func markPushed(_ ids: [UUID], to providerId: String) async throws
    func recordPushFailure(_ ids: [UUID], to providerId: String, error: String) async throws
    func applyRemote(_ records: [ChangeRecord]) async throws
}
