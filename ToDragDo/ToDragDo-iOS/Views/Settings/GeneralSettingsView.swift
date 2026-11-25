import SwiftUI
import ToDragDoUI
import UIKit

/// General pane (More → General). Hosts the hide-during-capture toggle,
/// Limbo blink stepper, and the read-only on-disk data location. The
/// toggle drives `RootView`'s capture observer; the path is shareable to
/// Files via `ShareLink`.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DataLocation.self) private var dataLocation

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Hide during screen sharing", isOn: $settings.hideFromScreenSharing)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Hides the list while the device is recording, sharing the screen, or mirroring. The input bar stays visible.")
            }

            Section {
                Stepper(
                    value: $settings.limboBlinkDays,
                    in: AppSettings.limboBlinkDaysRange
                ) {
                    LabeledContent("Blink idle items") {
                        Text(limboValueText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Limbo")
            } footer: {
                Text(limboFooterText)
            }

            Section("Data Location") {
                LabeledContent("Folder") {
                    Text(dataLocation.resolvedDirectory.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Spacer()
                    Button("Copy Path", action: copyPath)
                    ShareLink(item: dataLocation.resolvedDirectory) {
                        Text("Share…")
                    }
                }
            }
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var limboValueText: String {
        let n = settings.limboBlinkDays
        if n == 0 { return "Off" }
        if n == 1 { return "1 day" }
        return "\(n) days"
    }

    private var limboFooterText: String {
        settings.limboBlinkDays == 0
            ? "Limbo items never blink."
            : "Items idle in Limbo this long start blinking red. Opening an item resets its timer."
    }

    private func copyPath() {
        UIPasteboard.general.string = dataLocation.resolvedDirectory.path
    }
}
