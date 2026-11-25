import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// General pane (macOS Settings window; iOS More → General). Hosts the
/// screen-sharing toggle, the Limbo blink stepper, and the read-only
/// on-disk data location (copy, plus Reveal in Finder / Share…).
public struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DataLocation.self) private var dataLocation

    public init() {}

    public var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Hide during screen sharing", isOn: $settings.hideFromScreenSharing)
            } header: {
                Text("Privacy")
            } footer: {
                Text(privacyFooterText)
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
                    #if os(macOS)
                    Button("Reveal in Finder", action: revealInFinder)
                    #else
                    ShareLink(item: dataLocation.resolvedDirectory) {
                        Text("Share…")
                    }
                    #endif
                }
            }
        }
        .settingsPaneStyle(title: "General")
    }

    private var privacyFooterText: String {
        #if os(macOS)
        "Excludes every ToDragDo window from screenshots, screen recordings, and shared screens."
        #else
        "Hides the list while the device is recording, sharing the screen, or mirroring. The input bar stays visible."
        #endif
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
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(dataLocation.resolvedDirectory.path, forType: .string)
        #else
        UIPasteboard.general.string = dataLocation.resolvedDirectory.path
        #endif
    }

    #if os(macOS)
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataLocation.resolvedDirectory])
    }
    #endif
}
