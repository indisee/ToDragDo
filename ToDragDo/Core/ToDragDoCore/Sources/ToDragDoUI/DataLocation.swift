import Foundation
import Observation
#if os(iOS)
import ToDragDoIntents
#endif

/// Resolves the on-disk directory where the SwiftData store lives.
///
/// macOS: the app's sandboxed `Application Support` directory.
/// iOS: `Application Support` inside the App Group container, so the
/// app, share extension and widgets read and write the same store.
@MainActor
@Observable
public final class DataLocation {
    public let resolvedDirectory: URL

    public init() {
        #if os(iOS)
        let dir = AppGroup.containerURL.appendingPathComponent("Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.resolvedDirectory = dir
        #else
        if let url = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            self.resolvedDirectory = url
        } else {
            self.resolvedDirectory = URL(fileURLWithPath: NSHomeDirectory())
        }
        #endif
    }

    /// `.store` file path the SwiftData container should use.
    public var storeURL: URL {
        resolvedDirectory.appendingPathComponent("default.store")
    }

    #if os(iOS)
    /// CKAsset staging area — outside Application Support so a future
    /// store reset doesn't wipe in-flight uploads, but still inside the
    /// app group so the share extension uploads the same files the main
    /// app does.
    public var cloudKitAssetDirectory: URL {
        let dir = AppGroup.containerURL.appendingPathComponent("CloudKitAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    #endif
}
