import Foundation

/// A user-defined grouping that every `Item` belongs to. Independent of
/// `Folder` (which is a timing/state bucket): a "Buy milk" item can be
/// in Today × Personal, while "Ship feature" is in Today × Work.
///
/// Two seed projects (Work, Personal) exist on every device with fixed
/// UUIDs so the migration path — and any device that hasn't created
/// custom projects yet — converges on the same defaults without needing
/// to round-trip project rows through sync.
public struct Project: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var name: String
    /// Hex string `#RRGGBB`. Stored as a string rather than RGB ints so
    /// the value round-trips cleanly through JSON and is human-readable
    /// in the change log / store inspector.
    public var colorHex: String
    public var orderKey: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        orderKey: Double,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.orderKey = orderKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Defaults

    /// Stable UUID for the seed "Work" project. Used as the migration
    /// fallback when an existing item has no project assigned.
    public static let workId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    /// Stable UUID for the seed "Personal" project.
    public static let personalId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    /// Yellowish amber. Tuned to read against both light and dark
    /// surfaces without needing a per-appearance value.
    public static let workColorHex = "#E5A82B"
    /// System green; matches the design palette.
    public static let personalColorHex = "#34C759"

    public static func defaultWork() -> Project {
        Project(
            id: workId,
            name: "Work",
            colorHex: workColorHex,
            orderKey: 1
        )
    }

    public static func defaultPersonal() -> Project {
        Project(
            id: personalId,
            name: "Personal",
            colorHex: personalColorHex,
            orderKey: 2
        )
    }

    public static var defaults: [Project] {
        [defaultWork(), defaultPersonal()]
    }
}
