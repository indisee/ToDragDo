import AppKit

/// Hooks the app launch sequence to:
/// 1. Lock the activation policy to `.accessory` (menu-bar agent, no
///    dock icon) — `LSUIElement = YES` already does this via Info.plist
///    but setting it programmatically catches any path that bypasses
///    the plist.
/// 2. Disable window state restoration so macOS doesn't auto-pop the
///    previous session's Settings window at launch (the source of the
///    "Settings opens for no reason" bug).
/// 3. Close any window macOS still managed to auto-restore — except
///    `NSPanel`s (our floating panel uses `NSPanel`).
/// 4. Force `sharingType = .none` on every window the app shows so the
///    app is invisible to screen captures, recordings, and screen
///    sharing. The two windows we own (`FloatingPanel`,
///    `SettingsWindow`) already set this at creation; the observer
///    below is a safety net for any window AppKit creates on our behalf
///    (alerts, save panels, color pickers, etc.).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for window in NSApp.windows where !(window is NSPanel) {
            window.close()
        }
        for window in NSApp.windows {
            window.sharingType = .none
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            (notification.object as? NSWindow)?.sharingType = .none
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
