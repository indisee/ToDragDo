import Foundation

public struct Item: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var folder: Folder
    public var orderKey: Double
    public var typeIdentifier: String
    public var payload: Data
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var lastEditedBy: String
    /// Project this item belongs to, or `nil` for unassigned items.
    /// Unknown ids coming in from sync resolve to `nil` (the project
    /// row hasn't been pulled yet or has been deleted elsewhere).
    public var projectId: UUID?
    /// Optional calendar day the user wants to act on this item. Items
    /// with a future `dueDate` live in Limbo until their day arrives;
    /// items whose day is today or earlier sit in Today (with past-due
    /// items rendered in red); items whose day is tomorrow sit in
    /// Tomorrow. Time component is irrelevant — only the calendar day
    /// matters.
    public var dueDate: Date?
    /// Set when the item enters Done, cleared when it leaves Done.
    /// Distinct from `updatedAt` so subsequent edits to a Done item
    /// (rare but possible) don't shift its archival timestamp.
    public var completedAt: Date?
    /// Drives the "stale Limbo" blink: the moment the item's Limbo
    /// idle-timer was last (re)started. Set on entry into Limbo and
    /// reset every time the user opens the row while it sits in Limbo;
    /// cleared when the item leaves Limbo. Nil for items that never
    /// visited Limbo. The threshold (X days) is a user setting; this
    /// field carries the per-item state across devices.
    public var limboEnteredAt: Date?

    public init(
        id: UUID = UUID(),
        folder: Folder,
        orderKey: Double,
        typeIdentifier: String,
        payload: Data,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        lastEditedBy: String,
        projectId: UUID? = nil,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        limboEnteredAt: Date? = nil
    ) {
        self.id = id
        self.folder = folder
        self.orderKey = orderKey
        self.typeIdentifier = typeIdentifier
        self.payload = payload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastEditedBy = lastEditedBy
        self.projectId = projectId
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.limboEnteredAt = limboEnteredAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, folder, orderKey, typeIdentifier, payload
        case createdAt, updatedAt, deletedAt, lastEditedBy
        case projectId, dueDate, completedAt, limboEnteredAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.folder = try c.decode(Folder.self, forKey: .folder)
        self.orderKey = try c.decode(Double.self, forKey: .orderKey)
        self.typeIdentifier = try c.decode(String.self, forKey: .typeIdentifier)
        self.payload = try c.decode(Data.self, forKey: .payload)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.lastEditedBy = try c.decode(String.self, forKey: .lastEditedBy)
        self.projectId = try c.decodeIfPresent(UUID.self, forKey: .projectId)
        self.dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        self.limboEnteredAt = try c.decodeIfPresent(Date.self, forKey: .limboEnteredAt)
    }
}

extension Item {
    /// Last-writer-wins comparison for remote applies: newer `updatedAt`
    /// wins; exact ties go to the lexically greater `lastEditedBy` so all
    /// devices resolve the same way.
    public static func remoteWins(
        remote: (updatedAt: Date, editedBy: String),
        over local: (updatedAt: Date, editedBy: String)
    ) -> Bool {
        if remote.updatedAt != local.updatedAt {
            return remote.updatedAt > local.updatedAt
        }
        return remote.editedBy > local.editedBy
    }
}
