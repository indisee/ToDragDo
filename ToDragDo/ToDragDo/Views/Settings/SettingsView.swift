import SwiftUI

/// Settings scene root. Every pane shares the same window size and the
/// same `.formStyle(.grouped)` chrome so switching tabs feels like one
/// surface, not four.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProjectsSettingsView()
                .tabItem { Label("Projects", systemImage: "folder") }
            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath.icloud") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
    }
}

/// Single source of truth for the Settings window's content size.
/// Picking one width/height for every pane keeps the window from
/// resizing as the user clicks between tabs, which was the loudest
/// complaint about the prior design.
enum SettingsLayout {
    static let width: CGFloat = 540
    static let height: CGFloat = 460
}
