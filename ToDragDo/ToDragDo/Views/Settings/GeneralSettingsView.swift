import AppKit
import SwiftUI
import ToDragDoUI

/// General pane in the Settings scene. Hosts cross-cutting toggles plus
/// the on-disk data-location display (read-only path, copy, reveal in
/// Finder).
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
                Text("Excludes every ToDragDo window from screenshots, screen recordings, and shared screens.")
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
                    Button("Reveal in Finder", action: revealInFinder)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(dataLocation.resolvedDirectory.path, forType: .string)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataLocation.resolvedDirectory])
    }
}
