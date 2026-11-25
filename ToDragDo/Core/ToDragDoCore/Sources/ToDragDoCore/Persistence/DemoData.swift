import Foundation

/// Fake projects and items for screenshots and demos.
///
/// Launch either app with the `-DemoMode` argument: the host then uses an
/// in-memory store, registers no sync provider, and seeds it with this
/// data. Nothing touches the real store or CloudKit, so it's safe on a
/// device that also runs the real app.
public enum DemoData {
    public static let launchArgument = "-DemoMode"

    public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    private struct Entry {
        let folder: Folder
        let project: String
        let note: String
        var url: String? = nil
    }

    /// Listed top to bottom as they should appear in each folder.
    private static let entries: [Entry] = [
        Entry(folder: .today, project: "Work", note: "Draft Q3 roadmap slides"),
        Entry(folder: .today, project: "Work", note: "Review onboarding PR before standup"),
        Entry(folder: .today, project: "Side project", note: "Read before the sync refactor",
              url: "https://developer.apple.com/documentation/cloudkit/cksyncengine"),
        Entry(folder: .today, project: "Personal", note: "Call the dentist to reschedule"),
        Entry(folder: .today, project: "Side project", note: "Sketch icon ideas for the widget"),
        Entry(folder: .today, project: "Personal", note: "Buy oat milk and coffee beans"),

        Entry(folder: .tomorrow, project: "Work", note: "1:1 with Alex: growth plan"),
        Entry(folder: .tomorrow, project: "Personal", note: "Pick up dry cleaning"),
        Entry(folder: .tomorrow, project: "Side project", note: "Try out swift-collections",
              url: "https://github.com/apple/swift-collections"),

        Entry(folder: .libmo, project: "Personal", note: "Plan a weekend hike"),
        Entry(folder: .libmo, project: "Side project", note: "Learn Vapor basics"),
        Entry(folder: .libmo, project: "Personal", note: "Renew passport"),

        Entry(folder: .done, project: "Work", note: "Ship v1.2 release notes"),
        Entry(folder: .done, project: "Personal", note: "Book flights to Lisbon"),
    ]

    /// Seeds `repository` (expected to be empty, e.g. in-memory) with the
    /// demo projects and items.
    @MainActor
    public static func seed(_ repository: Repository) async throws {
        try await repository.reload()

        var projectIds: [String: UUID] = [:]
        for project in repository.projects {
            projectIds[project.name] = project.id
        }
        if projectIds["Side project"] == nil {
            let side = try await repository.addProject(name: "Side project", colorHex: "#AF52DE")
            projectIds[side.name] = side.id
        }

        // `add` prepends, so insert each folder's entries bottom-up.
        for entry in entries.reversed() {
            var attachments: [Attachment] = []
            if let url = entry.url {
                attachments.append(Attachment(kind: .url, urlString: url))
            }
            let payload = ItemPayload(note: entry.note, attachments: attachments)
            let insertFolder: Folder = entry.folder == .done ? .today : entry.folder
            let item = try await repository.add(
                folder: insertFolder,
                typeIdentifier: attachments.first?.typeIdentifier ?? "text/plain",
                payload: try payload.encoded(),
                projectId: projectIds[entry.project]
            )
            if entry.folder == .done {
                try await repository.move(id: item.id, to: .done)
            }
        }
    }
}
