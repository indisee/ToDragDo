import CloudKit
import Foundation
import OSLog

/// Installs the silent-push `CKDatabaseSubscription` the iOS app needs to
/// react to remote writes without polling. Idempotent — gated on a
/// `UserDefaults` flag so we don't churn the subscription on every launch.
///
/// macOS doesn't use this (the wake/activate observers + 20 s ticker keep
/// state fresh without push). iOS calls `installIfNeeded()` from the
/// AppDelegate's `didFinishLaunchingWithOptions`.
@MainActor
public final class CloudKitSubscriptionInstaller {
    public static let subscriptionID = "todragdo-private"

    private let log = Logger(subsystem: "com.turtle.todragdo", category: "CKSubscription")
    private let container: CKContainer
    private let defaults: UserDefaults
    private let installedKey: String

    public init(
        containerIdentifier: String,
        defaults: UserDefaults
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.defaults = defaults
        self.installedKey = "todragdo.cloudkit.subscription.installed.\(containerIdentifier)"
    }

    /// Creates the silent-push subscription if we haven't already.
    /// Caller spawns this off the main loop — the CloudKit call blocks
    /// on the network.
    public func installIfNeeded() async {
        if defaults.bool(forKey: installedKey) { return }
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        // Silent push: no banner / sound / badge — just a wake to fetch.
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let database = container.privateCloudDatabase
        do {
            _ = try await database.save(subscription)
            defaults.set(true, forKey: installedKey)
            log.info("Installed CKDatabaseSubscription \(Self.subscriptionID, privacy: .public)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Server already has a subscription with that ID — treat as
            // success so we stop retrying. Happens when the install flag
            // got cleared but the subscription survived on iCloud.
            defaults.set(true, forKey: installedKey)
            log.notice("CKDatabaseSubscription already exists on server")
        } catch {
            log.error("Failed to install CKDatabaseSubscription: \(error.localizedDescription, privacy: .public)")
        }
    }
}
