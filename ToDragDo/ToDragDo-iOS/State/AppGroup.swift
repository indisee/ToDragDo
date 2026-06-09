import Foundation

/// Centralizes the App Group identifier so the main app, Share Extension,
/// and widget extensions stay in sync. Matches the
/// `com.apple.security.application-groups` entitlement.
enum AppGroup {
    nonisolated static let identifier = "group.com.turtle.todragdo"

    /// `UserDefaults` suite shared across the app group. Returns the
    /// standard defaults as a last-resort fallback (e.g. when running
    /// against a development build that's missing the App Group
    /// entitlement) so the app still launches.
    ///
    /// `nonisolated` so it can be referenced as a default-parameter
    /// expression on non-MainActor init signatures — both the underlying
    /// `UserDefaults(suiteName:)` call and the fallback are thread-safe.
    nonisolated static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Shared on-disk container — `Application Support` lives under this
    /// URL so the SwiftData store and CloudKit asset directory survive
    /// across the main app + share extension. Falls back to the per-app
    /// sandbox when the group is unavailable.
    nonisolated static var containerURL: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSHomeDirectory())
    }
}
