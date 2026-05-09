import SwiftUI

/// Appearance pane in the Settings scene.
struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(width: 420)
    }
}

#Preview {
    AppearanceSettingsView()
        .environment(AppSettings())
}
