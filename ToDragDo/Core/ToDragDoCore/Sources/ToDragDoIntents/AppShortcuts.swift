import AppIntents

/// Exposes `AppendItemIntent` to the system shortcut surfaces — Action
/// Button picker, Siri, Spotlight, the Shortcuts app. iOS picks these
/// up automatically when the host app is installed; no additional
/// registration step is required.
public struct ToDragDoAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppendItemIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add a note to \(.applicationName)",
                "Capture in \(.applicationName)"
            ],
            shortTitle: "Add to ToDragDo",
            systemImageName: "plus.square.on.square"
        )
    }
}
