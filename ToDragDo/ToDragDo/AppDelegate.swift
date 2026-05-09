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
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for window in NSApp.windows where !(window is NSPanel) {
            window.close()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
