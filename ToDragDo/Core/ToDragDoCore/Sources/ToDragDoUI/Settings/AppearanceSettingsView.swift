import SwiftUI

/// Appearance pane (macOS Settings window; iOS More → Appearance).
public struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    public init() {}

    public var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Auto follows your \(PlatformCopy.systemName) appearance.")
            }
        }
        .settingsPaneStyle(title: "Appearance")
    }
}
