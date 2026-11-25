import Foundation

/// Project CRUD and assigning items to projects.
extension Repository {
    /// Reassign an existing item to a different project, or `nil` to
    /// clear it. No-op if the project already matches.
    public func setProject(itemId: UUID, to projectId: UUID?) async throws {
        guard var item = try await storage.item(id: itemId) else {
            throw StorageError.notFound(itemId)
        }
        guard item.projectId != projectId else { return }
        item.projectId = projectId
        item.updatedAt = .now
        item.lastEditedBy = deviceId
        let change = makeChange(op: .update, item: item)
        try await storage.upsert(item, change: change)
        try await reloadAndNotify()
    }

    /// Create a new project. `orderKey` defaults to one past the
    /// current max so it lands at the end of the list.
    @discardableResult
    public func addProject(name: String, colorHex: String) async throws -> Project {
        let nextKey = (projects.map(\.orderKey).max() ?? 0) + 1
        let project = Project(name: name, colorHex: colorHex, orderKey: nextKey)
        let change = makeProjectChange(op: .insert, project: project)
        try await storage.upsertProject(project, change: change)
        try await reloadAndNotify()
        return project
    }

    public func renameProject(id: UUID, to name: String) async throws {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.name = name
        project.updatedAt = .now
        let change = makeProjectChange(op: .update, project: project)
        try await storage.upsertProject(project, change: change)
        try await reloadAndNotify()
    }

    public func recolorProject(id: UUID, to colorHex: String) async throws {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.colorHex = colorHex
        project.updatedAt = .now
        let change = makeProjectChange(op: .update, project: project)
        try await storage.upsertProject(project, change: change)
        try await reloadAndNotify()
    }

    /// Delete a project. Items previously assigned to it are cleared
    /// (their `projectId` becomes `nil`) and each emits its own update
    /// change record so the cascade propagates through sync without
    /// the receiver having to repeat the lookup.
    public func deleteProject(id: UUID) async throws {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        let now = Date.now
        let affected = try await storage.itemsAssigned(toProjectId: id)
        var cleared: [Item] = []
        var itemChanges: [ChangeRecord] = []
        cleared.reserveCapacity(affected.count)
        itemChanges.reserveCapacity(affected.count)
        for var item in affected {
            item.projectId = nil
            item.updatedAt = now
            item.lastEditedBy = deviceId
            cleared.append(item)
            itemChanges.append(makeChange(op: .update, item: item))
        }
        let projectChange = makeProjectChange(op: .hardDelete, project: project)
        try await storage.deleteProject(
            id: id,
            change: projectChange,
            clearedItems: cleared,
            itemChanges: itemChanges
        )
        try await reloadAndNotify()
    }
}
