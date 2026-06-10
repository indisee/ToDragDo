import AppIntents
import Foundation
import WidgetKit

/// Headless "Add a note to ToDragDo" intent. Exposed via
/// `ToDragDoAppShortcuts` so the user can assign it to the Action Button
/// (iPhone 15 Pro+) or invoke it from Siri / Shortcuts. The system
/// prompts for `text` natively when the parameter is missing.
///
/// Widgets do NOT invoke this directly — their tap deep-links via URL
/// (`todragdo://input?folder=...`) into the host app's input bar so the
/// user can type with full keyboard + paste / attachment support.
public struct AppendItemIntent: AppIntent {
    public static var title: LocalizedStringResource { "Add to ToDragDo" }
    public static var description: IntentDescription {
        IntentDescription("Adds a quick note into the chosen folder.")
    }

    /// `false` so the Action Button doesn't bounce into the app every
    /// time — the intent writes the row in the extension process and
    /// returns a confirmation dialog.
    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Note", requestValueDialog: "What should I add?")
    public var note: String

    @Parameter(title: "Folder", default: .today)
    public var folder: FolderParameter

    public init() {}

    public init(note: String, folder: FolderParameter = .today) {
        self.note = note
        self.folder = folder
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing to add.")
        }
        try await IntentStorage.appendTextItem(
            note: trimmed,
            folder: folder.folder,
            iCloudContainerIdentifier: AppGroup.iCloudContainerIdentifier
        )
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result(dialog: "Added to \(folder.rawValue.capitalized).")
    }
}
