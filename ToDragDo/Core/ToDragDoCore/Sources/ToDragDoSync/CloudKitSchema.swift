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
public enum CloudKitSchema {
    public nonisolated static let zoneName = "TDDChanges"
    public nonisolated static let recordType = "ChangeRecord"

    public enum Field {
        public nonisolated static let entityType = "entityType"
        public nonisolated static let entityId = "entityId"
        public nonisolated static let op = "op"
        public nonisolated static let ts = "ts"
        public nonisolated static let deviceId = "deviceId"
        /// Legacy field — the original `CKAsset`. Decoders still read it
        /// when a record from before the inline switch arrives.
        public nonisolated static let snapshot = "snapshot"
        /// Preferred field — the snapshot bytes inlined as a CKRecord
        /// `Data` value. Avoids the iCloud asset transfer service
        /// (`mmcs`), which fails intermittently on iOS Simulator with
        /// "Fetching asset failed" errors.
        public nonisolated static let snapshotData = "snapshotData"
    }

    /// CloudKit caps a single CKRecord field at 1 MB. Encoders fall back
    /// to a CKAsset above this threshold so giant image attachments
    /// still go through.
    public nonisolated static let inlineSnapshotLimit = 900_000

    public nonisolated static var recordZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Encodes a `ChangeRecord` into a `CKRecord`. Prefers an inline
    /// `Data` field for snapshots ≤ `inlineSnapshotLimit`; falls back to
    /// a `CKAsset` for larger payloads (e.g. high-res image attachments).
    ///
    /// `assetDirectory` should be a stable on-disk location — `CKAsset`
    /// uploads happen asynchronously after the record is staged, so a
    /// file in `/tmp` may be swept by the OS before CloudKit reads it.
    /// Only used when a snapshot exceeds the inline limit; otherwise no
    /// file is written. Caller is responsible for creating the directory.
    public nonisolated static func makeRecord(
        from change: ChangeRecord,
        assetDirectory: URL
    ) throws -> CKRecord {
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

        // Write BOTH representations whenever the payload fits the inline
        // limit. Two reader populations matter:
        //  * Pre-inline-schema clients (released before the inline field
        //    existed) only know how to decode the CKAsset — without it
        //    they read an empty snapshot and the change applies as a
        //    no-op. Keeping the CKAsset alongside makes the schema change
        //    transparently backward compatible.
        //  * Inline-aware clients (new Mac, iOS) prefer the inline field
        //    via `decode(_:)` and never need to fetch the asset.
        // For payloads above the inline limit (huge image attachments)
        // we fall back to CKAsset only — there's no way to squeeze >1 MB
        // into a single CloudKit field.
        let assetURL = assetDirectory.appendingPathComponent("\(change.id.uuidString).json")
        try change.snapshot.write(to: assetURL, options: .atomic)
        if change.snapshot.count <= inlineSnapshotLimit {
            record[Field.snapshotData] = change.snapshot as NSData
        }
        record[Field.snapshot] = CKAsset(fileURL: assetURL)
        return record
    }

    public nonisolated static func decode(_ record: CKRecord) -> ChangeRecord? {
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

        // Inline data wins over the legacy asset path — both encoders
        // write one or the other, never both. The CKAsset branch is
        // strictly a back-compat read for records that pre-date the
        // inline switch.
        let snapshot: Data
        if let inline = record[Field.snapshotData] as? Data {
            snapshot = inline
        } else if let asset = record[Field.snapshot] as? CKAsset, let url = asset.fileURL {
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
