import Foundation
import Observation
import ToDragDoCore

/// User-facing description of how the local store opened at launch.
/// Mirrors the macOS type verbatim — `StorageFactory.InitOutcome` is in
/// `ToDragDoCore` so both platforms render the same notices.
@MainActor
@Observable
final class StorageHealth {
    enum Notice: Sendable {
        case rescued(itemCount: Int, originalError: String)
        case rebuiltEmpty(originalError: String, rescueError: String)
        case inMemoryFallback(originalError: String)

        var title: String {
            switch self {
            case .rescued: return "Database rebuilt"
            case .rebuiltEmpty: return "Database reset"
            case .inMemoryFallback: return "Storage unavailable"
            }
        }

        var message: String {
            switch self {
            case .rescued(let count, let original):
                return "Couldn't open the existing database (\(original)). Rebuilt it and recovered \(count) item\(count == 1 ? "" : "s"). The old files were preserved alongside the new store with a `.broken-…` suffix."
            case .rebuiltEmpty(let original, let rescue):
                return "Couldn't open the existing database (\(original)). Item recovery also failed (\(rescue)). The old files are preserved with a `.broken-…` suffix so they can be inspected; new items will sync to iCloud normally."
            case .inMemoryFallback(let original):
                return "Couldn't open or rebuild on-disk storage (\(original)). The app is running with in-memory data — anything you add this session will be lost on quit."
            }
        }
    }

    var notice: Notice?

    init(notice: Notice? = nil) {
        self.notice = notice
    }

    static func from(_ outcome: StorageFactory.InitOutcome) -> StorageHealth {
        switch outcome {
        case .healthy:
            return StorageHealth(notice: nil)
        case .rescued(_, let count, let primary):
            return StorageHealth(notice: .rescued(
                itemCount: count,
                originalError: primary.localizedDescription
            ))
        case .rebuiltEmpty(_, let primary, let rescue):
            return StorageHealth(notice: .rebuiltEmpty(
                originalError: primary.localizedDescription,
                rescueError: rescue.localizedDescription
            ))
        case .inMemoryFallback(_, let primary):
            return StorageHealth(notice: .inMemoryFallback(
                originalError: primary.localizedDescription
            ))
        case .unrecoverable:
            return StorageHealth(notice: .inMemoryFallback(
                originalError: "Storage was unrecoverable"
            ))
        }
    }
}
