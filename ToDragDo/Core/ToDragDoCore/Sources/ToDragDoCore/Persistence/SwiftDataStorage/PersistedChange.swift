#if canImport(SwiftData)
import Foundation
import SwiftData

@Model
final class PersistedChange {
    var id: UUID = UUID()
    var entityType: String = ""
    var entityId: UUID = UUID()
    var opRaw: String = ChangeOp.update.rawValue
    var snapshot: Data = Data()
    var ts: Date = Date.distantPast
    var deviceId: String = ""

    @Relationship(deleteRule: .cascade, inverse: \PersistedChangeSyncStatus.change)
    var syncStatuses: [PersistedChangeSyncStatus] = []

    init(from dto: ChangeRecord) {
        self.id = dto.id
        self.entityType = dto.entityType
        self.entityId = dto.entityId
        self.opRaw = dto.op.rawValue
        self.snapshot = dto.snapshot
        self.ts = dto.ts
        self.deviceId = dto.deviceId
    }

    func toDTO() -> ChangeRecord {
        ChangeRecord(
            id: id,
            entityType: entityType,
            entityId: entityId,
            op: ChangeOp(rawValue: opRaw) ?? .update,
            snapshot: snapshot,
            deviceId: deviceId,
            ts: ts
        )
    }

    func status(for providerId: String) -> PersistedChangeSyncStatus? {
        syncStatuses.first { $0.providerId == providerId }
    }
}
#endif
