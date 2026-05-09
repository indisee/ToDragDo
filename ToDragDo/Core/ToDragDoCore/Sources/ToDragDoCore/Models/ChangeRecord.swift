import Foundation

public enum ChangeOp: String, Codable, Sendable, Hashable {
    case insert
    case update
    case softDelete
    case hardDelete
}

public struct ChangeRecord: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let entityType: String
    public let entityId: UUID
    public let op: ChangeOp
    public let snapshot: Data
    public let ts: Date
    public let deviceId: String

    public init(
        id: UUID = UUID(),
        entityType: String,
        entityId: UUID,
        op: ChangeOp,
        snapshot: Data,
        deviceId: String,
        ts: Date = .now
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.op = op
        self.snapshot = snapshot
        self.ts = ts
        self.deviceId = deviceId
    }
}
