#if canImport(SwiftData)
import Foundation
import SwiftData

@Model
final class PersistedProject {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#E5A82B"
    var orderKey: Double = 0
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(from dto: Project) {
        self.id = dto.id
        self.name = dto.name
        self.colorHex = dto.colorHex
        self.orderKey = dto.orderKey
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
    }

    func apply(_ dto: Project) {
        self.name = dto.name
        self.colorHex = dto.colorHex
        self.orderKey = dto.orderKey
        self.updatedAt = dto.updatedAt
    }

    func toDTO() -> Project {
        Project(
            id: id,
            name: name,
            colorHex: colorHex,
            orderKey: orderKey,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
#endif
