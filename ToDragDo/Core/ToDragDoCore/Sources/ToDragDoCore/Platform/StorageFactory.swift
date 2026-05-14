import Foundation

public enum StorageFactory {
    @MainActor
    public static func makeItemStorage(
        platform: Platform = .current,
        inMemory: Bool = false,
        url: URL? = nil
    ) throws -> any ItemStorage {
        switch platform {
        case .macOS, .iOS:
            #if canImport(SwiftData)
            return try SwiftDataStorage(inMemory: inMemory, url: url)
            #else
            throw StorageError.unsupportedPlatform(platform)
            #endif
        case .windows, .linux, .unknown:
            throw StorageError.unsupportedPlatform(platform)
        }
    }

    /// Outcome of `makeItemStorageWithRecovery` — the caller always gets a
    /// usable `ItemStorage`, and an optional advisory describing what had
    /// to happen to keep the app alive.
    public enum InitOutcome: Sendable {
        /// Normal launch: existing on-disk store opened cleanly.
        case healthy(any ItemStorage)
        /// On-disk store wouldn't open, but we extracted items via the
        /// rescue schema, moved the broken files aside, and rebuilt.
        /// `rescuedItemCount` is how many items we recovered; the broken
        /// store files live at `default.store.broken-<timestamp>` siblings.
        case rescued(any ItemStorage, rescuedItemCount: Int, originalError: any Error)
        /// On-disk store wouldn't open AND rescue read failed, so we
        /// rebuilt empty. The original files are still preserved as
        /// `.broken-<timestamp>` siblings for offline recovery.
        case rebuiltEmpty(any ItemStorage, originalError: any Error, rescueError: any Error)
        /// Disk path is completely unusable — we fell back to an in-memory
        /// store so the app can still launch. Anything the user types in
        /// this session is ephemeral.
        case inMemoryFallback(any ItemStorage, originalError: any Error)
        /// We couldn't even build an in-memory container. Very rare;
        /// caller has to decide what to do.
        case unrecoverable(originalError: any Error)

        public var storage: (any ItemStorage)? {
            switch self {
            case .healthy(let s): return s
            case .rescued(let s, _, _): return s
            case .rebuiltEmpty(let s, _, _): return s
            case .inMemoryFallback(let s, _): return s
            case .unrecoverable: return nil
            }
        }
    }

    /// Recovery-aware factory for the macOS/iOS app target. Returns an
    /// `InitOutcome` instead of throwing so the host can launch the UI in
    /// every reasonable failure mode and surface what happened to the user.
    @MainActor
    public static func makeItemStorageWithRecovery(
        platform: Platform = .current,
        url: URL? = nil
    ) -> InitOutcome {
        switch platform {
        case .macOS, .iOS:
            #if canImport(SwiftData)
            do {
                let storage = try SwiftDataStorage(inMemory: false, url: url)
                return .healthy(storage)
            } catch let primary {
                // First failure — try the rescue pipeline.
                do {
                    let outcome = try SwiftDataRescue.rescueAndRebuild(at: url)
                    if let extractionError = outcome.extractionError {
                        return .rebuiltEmpty(
                            outcome.storage,
                            originalError: primary,
                            rescueError: extractionError
                        )
                    }
                    return .rescued(
                        outcome.storage,
                        rescuedItemCount: outcome.rescuedItemCount,
                        originalError: primary
                    )
                } catch {
                    // Disk is fully unhappy — degrade to in-memory.
                    if let inMem = try? SwiftDataStorage(inMemory: true) {
                        return .inMemoryFallback(inMem, originalError: primary)
                    }
                    return .unrecoverable(originalError: primary)
                }
            }
            #else
            return .unrecoverable(originalError: StorageError.unsupportedPlatform(platform))
            #endif
        case .windows, .linux, .unknown:
            return .unrecoverable(originalError: StorageError.unsupportedPlatform(platform))
        }
    }
}
