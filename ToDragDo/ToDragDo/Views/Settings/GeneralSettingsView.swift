import SwiftUI

/// General pane in the Settings scene. Hosts cross-cutting toggles that
/// don't fit a more specific tab — currently the screen-sharing privacy
/// switch.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle("Hide during screen sharing", isOn: $settings.hideFromScreenSharing)
        }
        .padding(20)
        .frame(width: 420)
    }
}

#Preview {
    GeneralSettingsView()
        .environment(AppSettings())
}
