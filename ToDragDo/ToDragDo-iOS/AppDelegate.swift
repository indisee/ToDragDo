import OSLog
import ToDragDoCore
import UIKit

/// iOS lifecycle bridge for the SwiftUI app.
///
/// Two duties beyond what SwiftUI offers natively:
/// 1. Register for remote notifications so CloudKit's silent push
///    (driven by the `CKDatabaseSubscription` installed in
///    `RootView.task`) can wake us when a remote write lands.
/// 2. Fan the silent push event out as a `NotificationCenter`
///    notification so the SwiftUI tree can react to it — UIKit's
///    `application(_:didReceiveRemoteNotification:…)` has no SwiftUI
///    equivalent today.
final class iOSAppDelegate: NSObject, UIApplicationDelegate {
    private let log = Logger.todragdo(category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit doesn't need the token directly — the database
        // subscription is keyed on the iCloud account. Logging only.
        log.info("Registered for remote notifications (\(deviceToken.count) bytes)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        log.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        log.info("Silent push received; broadcasting sync-push event")
        NotificationCenter.default.post(name: .todragdoCloudKitPush, object: nil)
        // We hand back `.newData` immediately — the actual sync happens
        // asynchronously in the SwiftUI tree. Holding the completion
        // handler open until the sync finishes would risk the 30 s
        // wallclock budget iOS enforces.
        completionHandler(.newData)
    }
}

extension Notification.Name {
    /// Posted by the AppDelegate when a CloudKit silent push lands.
    /// Subscribed by `RootView` to trigger an immediate sync.
    static let todragdoCloudKitPush = Notification.Name("todragdo.cloudkit.push")
}
