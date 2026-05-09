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

    public init(
        id: UUID = UUID(),
        folder: Folder,
        orderKey: Double,
        typeIdentifier: String,
        payload: Data,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        lastEditedBy: String
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
    }
}
