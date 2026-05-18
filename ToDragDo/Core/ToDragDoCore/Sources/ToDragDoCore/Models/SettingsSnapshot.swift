import Foundation

/// Cross-device user preferences that ride the same change-record sync
/// as `Item` / `Project`. Stored as a single record with a fixed entity
/// id so each device LWWs against the same logical row.
///
/// Fields are individually optional so a build that doesn't know about
/// a newer key can still decode an incoming snapshot — only the keys
/// it understands are applied. New keys append to `CodingKeys` without
/// breaking older clients.
public struct SettingsSnapshot: Sendable, Codable, Hashable {
    /// Stable singleton entity id. Every device writes under this id so
    /// remote pulls naturally merge by timestamp instead of accumulating
    /// per-device duplicates.
    public static let entityId = UUID(uuidString: "00000000-0000-0000-0000-534554544E47")!
    public static let entityType = "Settings"

    public var limboBlinkDays: Int?

    public init(limboBlinkDays: Int? = nil) {
        self.limboBlinkDays = limboBlinkDays
    }
}
