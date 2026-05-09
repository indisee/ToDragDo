import Foundation

public enum StorageFactory {
    @MainActor
    public static func makeItemStorage(
        platform: Platform = .current,
        inMemory: Bool = false
    ) throws -> any ItemStorage {
        switch platform {
        case .macOS, .iOS:
            #if canImport(SwiftData)
            return try SwiftDataStorage(inMemory: inMemory)
            #else
            throw StorageError.unsupportedPlatform(platform)
            #endif
        case .windows, .linux, .unknown:
            throw StorageError.unsupportedPlatform(platform)
        }
    }
}
