import Foundation
import ToDragDoCore
import ToDragDoSync

/// Centralizes the App Group identifier so the main app, widget extension,
/// and any future share extension stay in sync. Matches the
/// `com.apple.security.application-groups` entitlement.
public enum AppGroup {
    public nonisolated static let identifier = "group.com.turtle.todragdo"

    /// CloudKit container shared by every ToDragDo client. Same value as
    /// the host app's `com.apple.developer.icloud-container-identifiers`
    /// entitlement; centralized here so the widget extension and any
    /// future intent target don't redefine it.
    public nonisolated static let iCloudContainerIdentifier =
        CloudKitConfig.containerIdentifier

    /// `UserDefaults` suite shared across the app group. Returns the
    /// standard defaults as a last-resort fallback (e.g. when running
    /// against a development build that's missing the App Group
    /// entitlement) so the app still launches.
    public nonisolated static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Shared on-disk container — `Application Support` lives under this
    /// URL so the SwiftData store survives across the main app + widget
    /// extension. Falls back to the per-app sandbox when the group is
    /// unavailable.
    public nonisolated static var containerURL: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? (try? AppSupportDirectory.url())
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    /// UserDefaults keys read/written across the App Group boundary.
    public enum Keys {
        /// Set by `AppendItemIntent` when its best-effort in-extension sync
        /// failed or timed out. Main app's `scenePhase == .active` handler
        /// reads + clears + forces a sync.
        public static let pendingActionButtonSync = "pendingActionButtonSync"

        /// UUID string of the project currently displayed by the project
        /// list widget. Written by `SetWidgetProjectIntent`, read by the
        /// timeline provider. Nil means "use the seeded Personal default."
        public static let widgetProjectId = "widgetProjectId"
    }
}
