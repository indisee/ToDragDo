#if canImport(SwiftData)
import Foundation
import SwiftData

@Model
final class PersistedItem {
    var id: UUID = UUID()
    var folderRaw: String = Folder.today.rawValue
    var orderKey: Double = 0
    var typeIdentifier: String = ""
    var payload: Data = Data()
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    var deletedAt: Date?
    var lastEditedBy: String = ""

    init(from dto: Item) {
        self.id = dto.id
        self.folderRaw = dto.folder.rawValue
        self.orderKey = dto.orderKey
        self.typeIdentifier = dto.typeIdentifier
        self.payload = dto.payload
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
        self.deletedAt = dto.deletedAt
        self.lastEditedBy = dto.lastEditedBy
    }

    func apply(_ dto: Item) {
        self.folderRaw = dto.folder.rawValue
        self.orderKey = dto.orderKey
        self.typeIdentifier = dto.typeIdentifier
        self.payload = dto.payload
        self.updatedAt = dto.updatedAt
        self.deletedAt = dto.deletedAt
        self.lastEditedBy = dto.lastEditedBy
    }

    func toDTO() -> Item {
        Item(
            id: id,
            folder: Folder(rawValue: folderRaw) ?? .today,
            orderKey: orderKey,
            typeIdentifier: typeIdentifier,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastEditedBy: lastEditedBy
        )
    }
}
#endif
