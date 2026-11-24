import Foundation

/// Single source of truth for CloudKit identifiers shared by the macOS
/// app, the iOS app, the widget extension and the intents.
public enum CloudKitConfig {
    /// CloudKit container used by every ToDragDo client. Must match the
    /// `com.apple.developer.icloud-container-identifiers` entitlement.
    public nonisolated static let containerIdentifier =
        "iCloud.com.turtle.todragdo.sync.container"

    /// `SyncCoordinator` provider id of the iCloud remote adapter.
    public nonisolated static let providerId = "icloud"
}
