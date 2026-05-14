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

    private func copyPath() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(dataLocation.resolvedDirectory.path, forType: .string)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataLocation.resolvedDirectory])
    }
}
