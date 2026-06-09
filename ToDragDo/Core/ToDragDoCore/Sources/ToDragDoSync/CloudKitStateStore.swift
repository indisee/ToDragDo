import CloudKit
import Foundation

/// Persists the opaque `CKSyncEngine.State.Serialization` (the server-state
/// token that lets the engine resume an incremental sync) in `UserDefaults`.
/// Stored as JSON because `Serialization` is `Codable`.
@MainActor
public final class CloudKitStateStore {
    private let key: String
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(providerId: String = "icloud", defaults: UserDefaults = .standard) {
        self.key = "todragdo.cloudkit.state.\(providerId)"
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func load() -> CKSyncEngine.State.Serialization? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    public func save(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    /// Short identifier used as the SyncCursor.token returned from pull.
    /// Real reconstruction comes from `load()` — this is just a fingerprint
    /// the coordinator can store/compare.
    public var fingerprint: String {
        guard let data = defaults.data(forKey: key) else { return "initial" }
        return String(data.count)
    }
}
