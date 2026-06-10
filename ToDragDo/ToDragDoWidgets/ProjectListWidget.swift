import AppIntents
import SwiftUI
import ToDragDoCore
import ToDragDoIntents
import WidgetKit

/// Widget showing active items in a project chosen by in-widget chip
/// buttons (Home Screen `systemMedium` / `systemLarge`). Lock Screen
/// `accessoryRectangular` is read-only and falls back to whatever is
/// persisted as the current project.
struct ProjectListWidget: Widget {
    static let kind = "ProjectListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ProjectListProvider()) { entry in
            ProjectListWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Project")
        .description("Active items in a project.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ProjectListEntry: TimelineEntry {
    let date: Date
    let selectedProjectId: UUID
    let projects: [ProjectChip]
    let items: [ProjectListItem]

    var selectedProject: ProjectChip? {
        projects.first(where: { $0.id == selectedProjectId })
    }
}

struct ProjectChip: Hashable, Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct ProjectListItem: Hashable, Identifiable {
    let id: UUID
    let title: String
    let folder: Folder
}

struct ProjectListProvider: TimelineProvider {
    typealias Entry = ProjectListEntry

    func placeholder(in _: Context) -> ProjectListEntry {
        ProjectListEntry(
            date: Date(timeIntervalSinceReferenceDate: 0),
            selectedProjectId: Project.personalId,
            projects: [
                ProjectChip(id: Project.personalId, name: "Personal", colorHex: Project.personalColorHex),
                ProjectChip(id: Project.workId, name: "Work", colorHex: Project.workColorHex)
            ],
            items: (0..<3).map {
                ProjectListItem(id: UUID(), title: "Item \($0 + 1)", folder: .today)
            }
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (ProjectListEntry) -> Void) {
        Task {
            let entry = await buildEntry()
            completion(entry)
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ProjectListEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            // 15-min fallback — the host app's onWriteCallback also
            // reloads timelines after each commit, so this only matters
            // when no app activity has happened in a while.
            let next = entry.date.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func buildEntry() async -> ProjectListEntry {
        let selectedId = readSelectedProjectId()
        return await MainActor.run {
            do {
                let repo = try IntentStorage.sharedRepository()
                Task { try? await repo.reload() }
                let projects = repo.projects.map {
                    ProjectChip(id: $0.id, name: $0.name, colorHex: $0.colorHex)
                }
                let resolvedId: UUID = {
                    if projects.contains(where: { $0.id == selectedId }) { return selectedId }
                    return projects.first(where: { $0.id == Project.personalId })?.id
                        ?? projects.first?.id
                        ?? Project.personalId
                }()
                let items = activeItems(for: resolvedId, in: repo)
                return ProjectListEntry(
                    date: Date(timeIntervalSinceReferenceDate: 0),
                    selectedProjectId: resolvedId,
                    projects: projects.isEmpty ? defaultChips : projects,
                    items: items
                )
            } catch {
                return ProjectListEntry(
                    date: Date(timeIntervalSinceReferenceDate: 0),
                    selectedProjectId: Project.personalId,
                    projects: defaultChips,
                    items: []
                )
            }
        }
    }

    private func readSelectedProjectId() -> UUID {
        if let raw = AppGroup.defaults.string(forKey: AppGroup.Keys.widgetProjectId),
           let id = UUID(uuidString: raw) {
            return id
        }
        return Project.personalId
    }

    private var defaultChips: [ProjectChip] {
        Project.defaults.map {
            ProjectChip(id: $0.id, name: $0.name, colorHex: $0.colorHex)
        }
    }

    @MainActor
    private func activeItems(for projectId: UUID, in repo: Repository) -> [ProjectListItem] {
        let folders: [Folder] = [.today, .tomorrow, .libmo]
        var rows: [ProjectListItem] = []
        for folder in folders {
            for item in repo.items[folder] ?? [] where item.projectId == projectId {
                let payload = ItemPayload.decode(item.payload)
                let title = payload.note.isEmpty ? "Untitled" : firstLine(payload.note)
                rows.append(ProjectListItem(id: item.id, title: title, folder: folder))
            }
        }
        return rows
    }

    private func firstLine(_ note: String) -> String {
        note.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? note
    }
}
