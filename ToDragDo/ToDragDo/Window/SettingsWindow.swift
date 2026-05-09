import AppKit
import SwiftUI

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
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let host = NSHostingController(
                rootView: AnyView(SettingsView().environment(settings))
            )
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
