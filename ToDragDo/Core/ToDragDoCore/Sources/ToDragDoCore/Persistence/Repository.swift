import Foundation
import Observation

@MainActor
@Observable
public final class Repository: RemoteApplier {
    public private(set) var items: [Folder: [Item]] = [:]
    /// Soft-deleted items within the trash retention window, most recently
    /// deleted first. Refreshed by `reload()`.
    public private(set) var trashItems: [Item] = []
    /// All projects, sorted by `orderKey`. Refreshed by `reload()` and
    /// seeded with `Project.defaults` on first launch.
    public private(set) var projects: [Project] = []

    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    let storage: any ItemStorage
    public let deviceId: String
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    /// Fires after every user-initiated write (add, update, move, delete,
    /// rollover, …) — once `reload()` has refreshed the published state.
    /// Not called from `applyRemote(_:)` because remote-pulled changes
    /// shouldn't trigger another sync round.
    ///
    /// Excluded from `@Observable` tracking so views that read repository
    /// state don't redraw when the callback is (re)assigned.
    @ObservationIgnored
    public var onWriteCallback: (@MainActor () -> Void)?

    /// Fires when a `SettingsSnapshot` arrives via `applyRemote`. The
    /// host (`AppSettings`) decides whether the incoming snapshot's `ts`
    /// is newer than the locally-applied value and applies it if so —
    /// the Repository carries the bytes but doesn't own the merge
    /// policy because local persistence (UserDefaults) lives in the app
    /// layer.
    @ObservationIgnored
    public var onRemoteSettings: (@MainActor (SettingsSnapshot, Date) -> Void)?

    public init(storage: any ItemStorage, deviceId: String = DeviceID.current) {
        self.storage = storage
        self.deviceId = deviceId
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        for folder in Folder.allCases {
            items[folder] = []
        }
    }

    public func reload() async throws {
        var fresh: [Folder: [Item]] = [:]
        for folder in Folder.allCases {
            let rows = try await storage.items(in: folder, includeDeleted: false)
            fresh[folder] = rows.sorted { $0.orderKey < $1.orderKey }
        }
        items = fresh
        let cutoff = Date.now.addingTimeInterval(-Self.trashRetention)
        trashItems = try await storage.trashItems(since: cutoff)

        var stored = try await storage.projects()
        // First launch (and any prior install that's missing a default
        // row): re-insert defaults so Work and Personal are always
        // resolvable for the migration fallback.
        let storedIds = Set(stored.map(\.id))
        let missing = Project.defaults.filter { !storedIds.contains($0.id) }
        if !missing.isEmpty {
            for project in missing {
                try await storage.upsertProject(project)
            }
            stored = try await storage.projects()
        }
        projects = stored
    }

    /// Resolves `id` to a known project. Returns `nil` for unassigned
    /// items (`id == nil`) or unknown ids (project row hasn't been
    /// pulled yet, or has been deleted elsewhere).
    public func project(for id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first(where: { $0.id == id })
    }

    /// `reload()` + fire `onWriteCallback`. Used by every user-initiated
    /// write so the host (e.g., `SyncCoordinator`) can react immediately.
    /// `applyRemote(_:)` deliberately uses plain `reload()` instead, so
    /// pulled remote changes don't trigger another push cycle.
    func reloadAndNotify() async throws {
        try await reload()
        onWriteCallback?()
    }

    // MARK: - Project CRUD

    func makeChange(op: ChangeOp, item: Item) -> ChangeRecord {
        let snapshot = (try? encoder.encode(item)) ?? Data()
        return ChangeRecord(
            entityType: "Item",
            entityId: item.id,
            op: op,
            snapshot: snapshot,
            deviceId: deviceId
        )
    }

    func makeProjectChange(op: ChangeOp, project: Project) -> ChangeRecord {
        let snapshot = (try? encoder.encode(project)) ?? Data()
        return ChangeRecord(
            entityType: "Project",
            entityId: project.id,
            op: op,
            snapshot: snapshot,
            deviceId: deviceId
        )
    }
}
