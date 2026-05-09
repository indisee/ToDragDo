import SwiftUI

/// Settings scene root. Tabs are added as new panes land
/// (Sync, Content providers, Hotkeys, …).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
