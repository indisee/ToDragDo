import AppKit

/// Owns the macOS menu-bar `NSStatusItem` for the app.
///
/// Manually managed (rather than going through SwiftUI's `MenuBarExtra`)
/// because `MenuBarExtra` registration was unreliable under `LSUIElement
/// = YES` on macOS 26 — the icon would silently fail to install. The
/// REQUIREMENTS spec also calls for `NSStatusItem` directly.
@MainActor
final class MenuBarStatusItem: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var panelController: PanelController?

    init(panelController: PanelController) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.panelController = panelController
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        let image = NSImage(
            systemSymbolName: "checklist",
            accessibilityDescription: "ToDragDo"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "ToDragDo"
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(
            title: "Show ToDragDo",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit ToDragDo",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func showSettings() {
        // Dispatch async so the status-bar menu finishes its tracking
        // run-loop mode before we try to activate the app. Calling
        // `NSApp.activate()` synchronously from inside menu tracking
        // gets swallowed on the first click, leaving the Settings
        // window built but never ordered front.
        let controller = panelController
        DispatchQueue.main.async {
            controller?.showSettings()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.items.first?.title = (panelController?.isVisible ?? false)
                ? "Hide ToDragDo"
                : "Show ToDragDo"
        }
    }
}
