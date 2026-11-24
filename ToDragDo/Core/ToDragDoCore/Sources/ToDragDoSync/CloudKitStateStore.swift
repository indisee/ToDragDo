import CloudKit
import Foundation

/// Persists the opaque `CKSyncEngine.State.Serialization` (the server-state
/// token that lets the engine resume an incremental sync) in `UserDefaults`.
/// Stored as JSON because `Serialization` is `Codable`.
///
/// The state is keyed per CloudKit environment: Development and Production
/// are separate databases, so a serialization (change tokens, zone state)
/// captured against one must never be replayed against the other. Switching
/// a device from a Development build to a Production build therefore starts
/// the engine fresh instead of resuming with foreign tokens.
@MainActor
public final class CloudKitStateStore {
    private let key: String
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        providerId: String = CloudKitConfig.providerId,
        environment: String? = CloudKitEnvironmentProbe.resolved,
        defaults: UserDefaults = .standard
    ) {
        let legacyKey = "todragdo.cloudkit.state.\(providerId)"
        if let environment {
            let key = "\(legacyKey).\(environment)"
            // Every build before per-environment keys talked to
            // Development, so the unsuffixed state belongs there.
            if environment == "Development",
               defaults.object(forKey: key) == nil,
               let legacy = defaults.data(forKey: legacyKey) {
                defaults.set(legacy, forKey: key)
                defaults.removeObject(forKey: legacyKey)
            }
            self.key = key
        } else {
            // Environment unknown: keep the historical key rather than
            // guessing.
            self.key = legacyKey
        }
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
