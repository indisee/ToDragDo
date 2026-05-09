import SwiftUI
import AppKit

/// Contents of the macOS menu-bar `MenuBarExtra` menu.
/// App-level controls only — Hide/Show, Settings, Quit.
struct MenuBarMenu: View {
    @Environment(PanelController.self) private var panelController

    var body: some View {
        if panelController.isVisible {
            Button("Hide ToDragDo") { panelController.toggle() }
        } else {
            Button("Show ToDragDo") { panelController.toggle() }
        }

        Divider()

        Button("Settings…") { panelController.showSettings() }

        Divider()

        Button("Quit ToDragDo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
