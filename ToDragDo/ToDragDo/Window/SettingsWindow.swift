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
            // The SwiftUI tree fixes its own size via `SettingsLayout`,
            // identical for every tab. Tracking preferred content size
            // is still useful (it sizes the window to fit on first
            // display) but the tabs no longer cause the window to jump.
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
        guard let window else { return }
        window.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
        // `.accessory` apps need a forced front-order: `NSApp.activate()`
        // is async, and `makeKeyAndOrderFront` silently no-ops if the app
        // isn't already active. `orderFrontRegardless()` puts the window
        // on screen regardless of activation state — same pattern the
        // floating panel uses successfully.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
