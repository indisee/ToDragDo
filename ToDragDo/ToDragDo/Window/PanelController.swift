import AppKit
import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes
import ToDragDoSync

/// Owns the always-on-top `NSPanel` and the SwiftUI tree it hosts.
///
/// Sizing: `NSHostingController.sizingOptions = [.preferredContentSize]`
/// makes the controller expose SwiftUI's ideal size; `NSWindow` resizes
/// its content area to match. Width comes from `AppSettings.panelWidth` in `PanelView`.
@MainActor @Observable
final class PanelController {
    /// Set in `ToDragDoApp.init` so AppKit-scope code (the AppDelegate,
    /// which creates the manual `NSStatusItem`) can drive the panel
    /// without a direct dependency wire-up.
    static weak var shared: PanelController?

    private let panel: NSPanel
    private let settingsWindow: SettingsWindow
    private let summaryWindow: SummaryWindow
    private(set) var isVisible: Bool
    private var keyMonitor: Any?

    init(
        repository: Repository,
        settings: AppSettings,
        coordinator: SyncCoordinator,
        accountWatcher: CloudKitAccountWatcher,
        contentTypes: ContentTypeRegistry,
        storageHealth: StorageHealth,
        dataLocation: DataLocation
    ) {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: AppSettings.defaultPanelWidth, height: 200),
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
        self.settingsWindow = SettingsWindow(
            repository: repository,
            settings: settings,
            coordinator: coordinator,
            accountWatcher: accountWatcher,
            contentTypes: contentTypes,
            storageHealth: storageHealth,
            dataLocation: dataLocation
        )
        self.summaryWindow = SummaryWindow(
            repository: repository,
            settings: settings,
            contentTypes: contentTypes
        )
        self.isVisible = false

        // Wire the SwiftUI host after `self` is fully initialized so the
        // panel tree can read `PanelController` from the environment.
        let host = NSHostingController(
            rootView: AnyView(
                PanelView()
                    .environment(repository)
                    .environment(settings)
                    .environment(self)
                    .environment(\.contentTypes, contentTypes)
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

    func showSummary(mode: SummaryMode) {
        summaryWindow.show(mode: mode)
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
///
/// Also intercepts height-changing `setFrame` calls so the panel grows
/// downward by default (top edge stays put) but flips to growing upward
/// (bottom edge stays put) when expansion would push the panel off the
/// bottom of the visible screen, or when the user has parked the panel
/// within `bottomStickZone` of the bottom. The chosen edge is remembered
/// until the user moves the panel, so collapsing mirrors the expansion.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Distance (pt) above the visible area's bottom edge within which
    /// the panel counts as "at the bottom" and keeps its bottom edge
    /// fixed on height changes.
    private static let bottomStickZone: CGFloat = 80

    /// Which edge height changes keep fixed. Set when an expansion has
    /// to grow upward (or the user parks the panel near the bottom) and
    /// kept until the user moves the panel, so collapses mirror it.
    private var anchoredToBottom = false
    /// The frame this class last produced; a mismatch means the panel
    /// was moved by something else (a user drag) since.
    private var lastAnchoredFrame: NSRect?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(anchoredFrame(forProposed: frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        super.setFrame(
            anchoredFrame(forProposed: frameRect),
            display: flag,
            animate: animate
        )
    }

    /// Adjusts the proposed frame's Y so height changes anchor to the
    /// correct edge, then clamps the result back inside the visible
    /// screen. Width changes and moves pass through unchanged.
    private func anchoredFrame(forProposed proposed: NSRect) -> NSRect {
        let current = frame
        let heightDelta = proposed.height - current.height
        // No meaningful height change: don't touch Y (preserves drags,
        // width resizes, and identity setFrame calls).
        guard abs(heightDelta) > 0.5 else { return proposed }

        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else {
            return proposed
        }

        // Top-anchored: keep current top edge → grow/shrink toward the
        // bottom. Bottom-anchored: keep current bottom edge → grow/shrink
        // toward the top.
        let topAnchoredY = current.maxY - proposed.height
        let bottomAnchoredY = current.minY

        // The anchor edge is remembered across resizes so a collapse
        // undoes the preceding expansion from the same edge. If the frame
        // no longer matches what we last set, the user moved the panel
        // (or this is the first resize): re-derive the anchor from where
        // it sits — near the bottom means the user parked it there.
        if !Self.approximatelyEqual(lastAnchoredFrame, current) {
            anchoredToBottom = current.minY <= visible.minY + Self.bottomStickZone
        }

        // Growing downward would run off the bottom: flip to growing
        // upward and stay bottom-anchored so the later collapse keeps the
        // input bar in place instead of jumping it up.
        if !anchoredToBottom, heightDelta > 0, topAnchoredY < visible.minY {
            anchoredToBottom = true
        }

        let newY = anchoredToBottom ? bottomAnchoredY : topAnchoredY

        var result = NSRect(
            x: proposed.origin.x,
            y: newY,
            width: proposed.width,
            height: proposed.height
        )

        // Clamp into the visible screen so the user can always reach the
        // panel — without this, dragging the panel below the Dock and
        // then collapsing keeps the (now small) panel below the visible
        // area and effectively hides it.
        if result.maxY > visible.maxY {
            result.origin.y = visible.maxY - result.height
        }
        if result.minY < visible.minY {
            result.origin.y = visible.minY
        }

        lastAnchoredFrame = result
        return result
    }

    private static func approximatelyEqual(_ a: NSRect?, _ b: NSRect) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}
