import Foundation
import Observation

/// Resolves the on-disk directory where the SwiftData store lives.
///
/// iOS variant: anchors inside the App Group container so the main app,
/// share extension, and widget extensions can read/write the same store.
/// The path is fixed for the app lifetime; the General settings pane
/// reads it through this observable so the user can copy / share it.
@MainActor
@Observable
final class DataLocation {
    let resolvedDirectory: URL

    init() {
        let base = AppGroup.containerURL
        let dir = base.appendingPathComponent("Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.resolvedDirectory = dir
    }

    var storeURL: URL {
        resolvedDirectory.appendingPathComponent("default.store")
    }

    /// CKAsset staging area — outside Application Support so a future
    /// store reset doesn't wipe in-flight uploads, but still inside the
    /// app group so the share extension uploads the same files the main
    /// app does.
    var cloudKitAssetDirectory: URL {
        let dir = AppGroup.containerURL.appendingPathComponent("CloudKitAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
