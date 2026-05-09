#if canImport(SwiftData)
import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [PersistedItem.self, PersistedChange.self, PersistedChangeSyncStatus.self]
    }
}
#endif
