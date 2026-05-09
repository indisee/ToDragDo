import AppKit
import SwiftUI
import ToDragDoCore

/// Owns the always-on-top `NSPanel` and the SwiftUI tree it hosts.
///
/// Sizing: `NSHostingController.sizingOptions = [.preferredContentSize]`
/// makes the controller expose SwiftUI's ideal size; `NSWindow` resizes
/// its content area to match. Width is fixed at 420pt in `PanelView`.
@MainActor @Observable
final class PanelController {
    private let panel: NSPanel
    private let settingsWindow: SettingsWindow
    private(set) var isVisible: Bool
    private var keyMonitor: Any?

    init(repository: Repository, settings: AppSettings) {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]
        panel.isFloatingPanel = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = true
        panel.center()

        self.panel = panel
        self.settingsWindow = SettingsWindow(settings: settings)
        self.isVisible = false

        // Wire the SwiftUI host after `self` is fully initialized so the
        // panel tree can read `PanelController` from the environment.
        let host = NSHostingController(
            rootView: AnyView(
                PanelView()
                    .environment(repository)
                    .environment(settings)
                    .environment(self)
            )
        )
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host

        // App.init runs before `applicationDidFinishLaunching`. Calling
        // show synchronously here is unreliable — the run loop hasn't
        // started, and on `.accessory` apps `makeKeyAndOrderFront`
        // silently no-ops. Defer the show until after launch and force
        // it with `orderFrontRegardless`.
        let panelRef = panel
        DispatchQueue.main.async {
            NSApp.activate()
            panelRef.makeKeyAndOrderFront(nil)
            panelRef.orderFrontRegardless()
        }
        self.isVisible = true

        installToggleHotkey()
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func showSettings() {
        settingsWindow.show()
    }

    private func installToggleHotkey() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == [.command, .shift],
                  event.charactersIgnoringModifiers?.lowercased() == "h"
            else { return event }
            self.toggle()
            return nil
        }
    }
}

/// Borderless panels don't accept first-responder status by default —
/// `canBecomeKey` and `canBecomeMain` must be overridden, otherwise text
/// fields silently swallow keystrokes.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
