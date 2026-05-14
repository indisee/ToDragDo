import Foundation
import Observation

/// Resolves the on-disk directory where the SwiftData store lives.
///
/// Always the app's sandboxed `Application Support` directory. Kept as a
/// dedicated type (rather than an inline lookup) so the General settings
/// pane has something stable to read from and so the storage init in
/// `ToDragDoApp` flows through one well-named call site.
@MainActor
@Observable
final class DataLocation {
    let resolvedDirectory: URL

    init() {
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
    }

    /// `.store` file path the SwiftData container should use.
    var storeURL: URL {
        resolvedDirectory.appendingPathComponent("default.store")
    }
}
