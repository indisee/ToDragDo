import Foundation

/// The one place ToDragDo resolves its `Application Support` directory.
///
/// Inside the App Sandbox, `Application Support` is already private to the
/// app (`~/Library/Containers/<bundle id>/Data/Library/Application Support`),
/// so files go straight in, at the paths existing installs already use.
///
/// Outside the sandbox (an unsigned build, `swift run`, a test host) the
/// same call returns the user's shared `~/Library/Application Support`.
/// Other software keeps files there with generic names: a SwiftData store
/// called `default.store` once got migrated to ToDragDo's schema and
/// wiped. So an unsandboxed process always gets its own subfolder.
public enum AppSupportDirectory {
    /// `true` when the process runs inside the App Sandbox.
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Directory for ToDragDo's files. Created if missing.
    public static func url() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        #if os(macOS)
        guard !isSandboxed else { return base }
        let name = Bundle.main.bundleIdentifier ?? "com.turtle.todragdo.unbundled"
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        // iOS apps are always sandboxed.
        return base
        #endif
    }
}
