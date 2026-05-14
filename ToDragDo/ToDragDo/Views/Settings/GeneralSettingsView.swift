import AppKit
import SwiftUI

/// General pane in the Settings scene. Hosts cross-cutting toggles plus
/// the on-disk data-location display (read-only path, copy, reveal in
/// Finder).
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DataLocation.self) private var dataLocation

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Privacy") {
                Toggle("Hide during screen sharing", isOn: $settings.hideFromScreenSharing)
            }

            Section("Limbo") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Stepper(
                        value: $settings.limboBlinkDays,
                        in: AppSettings.limboBlinkDaysRange
                    ) {
                        Text(limboBlinkLabel)
                    }
                    .fixedSize()
                    Text(limboBlinkHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("Data Location") {
                HStack(alignment: .top, spacing: 8) {
                    Text(dataLocation.resolvedDirectory.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        copyPath()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy path")

                    Button {
                        revealInFinder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var limboBlinkLabel: LocalizedStringKey {
        let n = settings.limboBlinkDays
        if n == 0 { return "Days before Limbo blinks: off" }
        if n == 1 { return "Days before Limbo blinks: 1 day" }
        return "Days before Limbo blinks: \(n) days"
    }

    private var limboBlinkHint: LocalizedStringKey {
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
