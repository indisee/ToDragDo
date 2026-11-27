#if canImport(SwiftData)
import Foundation
import SwiftData

/// Reads `Item` rows out of a SwiftData store that the full schema can't
/// open. Uses a minimal "rescue" schema that contains only `PersistedItem`
/// (whose fields have never changed) so we sidestep whatever schema or
/// migration issue is breaking the main load path.
///
/// On success, the caller renames the broken store files aside and creates
/// a fresh container, then re-imports the rescued items through the normal
/// outbox so they sync to iCloud as new inserts on this device.
@MainActor
enum SwiftDataRescue {

    /// Outcome of a rescue attempt.
    struct Outcome: Sendable {
        let storage: SwiftDataStorage
        /// How many `Item` rows we successfully extracted from the broken
        /// store. Zero if the store had no items, or if rescue-read failed
        /// (broken files are still moved aside).
        let rescuedItemCount: Int
        /// If the rescue-read step itself threw, the underlying error.
        /// `nil` when extraction succeeded (count may still be zero).
        let extractionError: (any Error)?
    }

    /// Default store URL: `default.store` in `AppSupportDirectory`, never
    /// SwiftData's own default, which outside the sandbox is the shared
    /// `~/Library/Application Support`. Throws if it can't be resolved.
    static func defaultStoreURL() throws -> URL {
        try AppSupportDirectory.url().appendingPathComponent("default.store")
    }

    /// Run the full rescue pipeline:
    /// 1. Try to read `Item` rows from the broken store at `storeURL`
    ///    (defaults to the standard location when `storeURL` is nil).
    /// 2. Rename `default.store{,-shm,-wal}` aside with a timestamp suffix.
    /// 3. Create a fresh `SwiftDataStorage` at the same URL.
    /// 4. Re-import each rescued `Item` through the normal upsert path so
    ///    the outbox picks them up for the iCloud push.
    static func rescueAndRebuild(
        at storeURL: URL? = nil,
        deviceId: String = DeviceID.current
    ) throws -> Outcome {
        let url = try storeURL ?? defaultStoreURL()

        var rescued: [Item] = []
        var extractionError: (any Error)?
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                rescued = try extractItems(at: url)
            } catch {
                extractionError = error
            }
        }

        moveBrokenStoreAside(at: url)

        let fresh = try SwiftDataStorage(inMemory: false, url: storeURL)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for item in rescued {
            let snapshot = (try? encoder.encode(item)) ?? Data()
            let change = ChangeRecord(
                entityType: "Item",
                entityId: item.id,
                op: .insert,
                snapshot: snapshot,
                deviceId: deviceId
            )
            // Don't let a single bad row sink the whole rebuild.
            try? fresh.upsertSync(item, change: change)
        }

        return Outcome(
            storage: fresh,
            rescuedItemCount: rescued.count,
            extractionError: extractionError
        )
    }

    /// Open the store at `url` with a schema that only knows about
    /// `PersistedItem` and fetch every row. SwiftData ignores tables it
    /// doesn't have models for, which is what lets this succeed when the
    /// full schema's load fails.
    private static func extractItems(at url: URL) throws -> [Item] {
        let rescueSchema = Schema([PersistedItem.self])
        // Same reason as `SwiftDataStorage.init`: opt out of CloudKit
        // auto-mirror so reading the broken store doesn't get blocked by
        // an unrelated iCloud-binding failure.
        let config = ModelConfiguration(
            schema: rescueSchema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: rescueSchema, configurations: config)
        let ctx = container.mainContext
        let rows = try ctx.fetch(FetchDescriptor<PersistedItem>())
        return rows.map { $0.toDTO() }
    }

    /// Move `default.store`, `default.store-shm`, `default.store-wal` to
    /// `default.store.broken-<timestamp>` siblings so the next container
    /// init starts from an empty slate but the user can recover the
    /// originals offline if needed. Missing files are skipped silently.
    private static func moveBrokenStoreAside(at storeURL: URL) {
        let ts = timestampSuffix()
        let fm = FileManager.default
        let suffixes = ["", "-shm", "-wal"]
        for suffix in suffixes {
            let fromPath = storeURL.path + suffix
            guard fm.fileExists(atPath: fromPath) else { continue }
            let toPath = fromPath + ".broken-\(ts)"
            try? fm.moveItem(atPath: fromPath, toPath: toPath)
        }
    }

    private static func timestampSuffix() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: .now)
    }
}
#endif
