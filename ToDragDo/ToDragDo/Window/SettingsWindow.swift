import AppKit
import SwiftUI
import ToDragDoCore

/// On-demand `NSWindow` for Settings.
///
/// Replaces the SwiftUI `Settings` scene because that scene was being
/// auto-opened at launch (state restoration / SwiftUI default behavior)
/// even with `LSUIElement = YES` and an `AppDelegate` close loop. With
/// no `Settings` scene declared, SwiftUI has nothing to auto-open; this
/// controller shows the window only when the menu bar item asks for it.
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let repository: Repository
    private let settings: AppSettings
    private let coordinator: SyncCoordinator
    private let accountWatcher: CloudKitAccountWatcher
    private let storageHealth: StorageHealth
    private let dataLocation: DataLocation

    init(
        repository: Repository,
        settings: AppSettings,
        coordinator: SyncCoordinator,
        accountWatcher: CloudKitAccountWatcher,
        storageHealth: StorageHealth,
        dataLocation: DataLocation
    ) {
        self.repository = repository
        self.settings = settings
        self.coordinator = coordinator
        self.accountWatcher = accountWatcher
        self.storageHealth = storageHealth
        self.dataLocation = dataLocation
    }

    func show() {
        if window == nil {
            let host = NSHostingController(
                rootView: AnyView(
                    SettingsView()
                        .environment(repository)
                        .environment(settings)
                        .environment(coordinator)
                        .environment(accountWatcher)
                        .environment(storageHealth)
                        .environment(dataLocation)
                )
            )
            // Track the SwiftUI tree's preferred content size so the
            // window resizes when the active tab changes. Without this
            // the TabView grows to fit the largest tab on first open
            // and never shrinks back when a smaller tab is selected.
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "ToDragDo Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
            window.center()
            self.window = window
        }
        window?.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
