import AppIntents
import Foundation
import ToDragDoCore

/// AppIntents wrapper around `Project`, used as the configuration
/// parameter for the project-list widget so users can pick which project
/// it displays. Reads projects out of the App Group SwiftData store via
/// `IntentStorage.sharedRepository()` — synthesizing the seeded
/// Personal default when the store hasn't been initialized yet (widget
/// added before the host app's first launch).
public struct ProjectEntity: AppEntity, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let colorHex: String

    public init(id: UUID, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    public init(project: Project) {
        self.init(id: project.id, name: project.name, colorHex: project.colorHex)
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Project")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public static var defaultQuery: ProjectEntityQuery { ProjectEntityQuery() }

    /// Seeded Personal default — falls back to this when the store
    /// has no rows yet so the picker always offers a working selection.
    public static var personalDefault: ProjectEntity {
        ProjectEntity(project: Project.defaultPersonal())
    }
}

public struct ProjectEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [ProjectEntity.ID]) async throws -> [ProjectEntity] {
        let all = try await loadAll()
        let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { lookup[$0] }
    }

    public func suggestedEntities() async throws -> [ProjectEntity] {
        try await loadAll()
    }

    public func defaultResult() async -> ProjectEntity? {
        if let stored = try? await loadAll().first(where: { $0.id == Project.personalId }) {
            return stored
        }
        return ProjectEntity.personalDefault
    }

    private func loadAll() async throws -> [ProjectEntity] {
        let mapped: [ProjectEntity] = await MainActor.run {
            guard let repo = try? IntentStorage.sharedRepository() else { return [] }
            return repo.projects.map(ProjectEntity.init(project:))
        }
        if !mapped.isEmpty { return mapped }

        // Cached repo had no projects — either fresh process or fresh
        // install. Force a reload (cheap if already populated) and re-read.
        _ = try? await IntentStorage.reload()
        let reloaded: [ProjectEntity] = await MainActor.run {
            (try? IntentStorage.sharedRepository())
                .map { $0.projects.map(ProjectEntity.init(project:)) } ?? []
        }
        if !reloaded.isEmpty { return reloaded }

        // Store still has no rows — synthesize the seeded defaults so
        // the picker shows Personal + Work on a fresh install.
        return Project.defaults.map(ProjectEntity.init(project:))
    }
}
