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
    /// Optional calendar day the user wants to act on this item. Items
    /// with a future `dueDate` live in Limbo until their day arrives;
    /// items whose day is today or earlier sit in Today (with past-due
    /// items rendered in red); items whose day is tomorrow sit in
    /// Tomorrow. Time component is irrelevant — only the calendar day
    /// matters.
    public var dueDate: Date?

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
        dueDate: Date? = nil
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
        self.dueDate = dueDate
    }
}
