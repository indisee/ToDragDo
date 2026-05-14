import CloudKit
import Foundation
import ToDragDoCore

/// CloudKit record-type/field constants plus `ChangeRecord` ↔ `CKRecord`
/// mapping. Snapshots travel as `CKAsset` so we don't bump into per-field
/// size limits when payloads carry attachments.
///
/// Members are `nonisolated`: the encoder/decoder are pure functions called
/// from CloudKit's Sendable closures, which the project's MainActor default
/// isolation would otherwise reject.
enum CloudKitSchema {
    nonisolated static let zoneName = "TDDChanges"
    nonisolated static let recordType = "ChangeRecord"

    enum Field {
        nonisolated static let entityType = "entityType"
        nonisolated static let entityId = "entityId"
        nonisolated static let op = "op"
        nonisolated static let ts = "ts"
        nonisolated static let deviceId = "deviceId"
        nonisolated static let snapshot = "snapshot"
    }

    nonisolated static var recordZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    nonisolated static func makeRecord(from change: ChangeRecord) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: change.id.uuidString,
            zoneID: recordZoneID
        )
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[Field.entityType] = change.entityType
        record[Field.entityId] = change.entityId.uuidString
        record[Field.op] = change.op.rawValue
        record[Field.ts] = change.ts
        record[Field.deviceId] = change.deviceId

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("todragdo-ck-assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(change.id.uuidString).json")
        try change.snapshot.write(to: url, options: .atomic)
        record[Field.snapshot] = CKAsset(fileURL: url)
        return record
    }

    nonisolated static func decode(_ record: CKRecord) -> ChangeRecord? {
        guard
            let id = UUID(uuidString: record.recordID.recordName),
            let entityType = record[Field.entityType] as? String,
            let entityIdStr = record[Field.entityId] as? String,
            let entityId = UUID(uuidString: entityIdStr),
            let opStr = record[Field.op] as? String,
            let op = ChangeOp(rawValue: opStr),
            let ts = record[Field.ts] as? Date,
            let deviceId = record[Field.deviceId] as? String
        else { return nil }

        let snapshot: Data
        if let asset = record[Field.snapshot] as? CKAsset, let url = asset.fileURL {
            snapshot = (try? Data(contentsOf: url)) ?? Data()
        } else {
            snapshot = Data()
        }

        return ChangeRecord(
            id: id,
            entityType: entityType,
            entityId: entityId,
            op: op,
            snapshot: snapshot,
            deviceId: deviceId,
            ts: ts
        )
    }
}
