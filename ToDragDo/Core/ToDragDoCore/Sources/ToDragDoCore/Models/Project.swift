import Foundation

/// A user-defined grouping an `Item` can belong to. Independent of
/// `Folder` (which is a timing/state bucket): a "Buy milk" item can be
/// in Today × Personal, while "Ship feature" is in Today × Work. The
/// assignment is optional — items can also live without a project.
///
/// Two seed projects (Work, Personal) are inserted on first launch with
/// fixed UUIDs so every device starts from the same defaults without
/// needing to round-trip project rows through sync.
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

    /// Stable UUID for the seed "Work" project. Same id across devices
    /// so the first-launch defaults converge without sync.
    public static let workId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    /// Stable UUID for the seed "Personal" project.
    public static let personalId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    /// Yellowish amber. Tuned to read against both light and dark
    /// surfaces without needing a per-appearance value.
    public static let workColorHex = "#E5A82B"
    /// System green; matches the design palette.
    public static let personalColorHex = "#34C759"

    /// Fixed timestamp stamped on seeded defaults across every device.
    /// `Date.distantPast` so any user-initiated edit (which uses
    /// `Date.now`) is unambiguously newer in the LWW comparison — the
    /// seeded row never spuriously wins against an incoming recolor
    /// just because that device happened to seed more recently than
    /// the other device's edit.
    private static let seedTimestamp: Date = .distantPast

    public static func defaultWork() -> Project {
        Project(
            id: workId,
            name: "Work",
            colorHex: workColorHex,
            orderKey: 1,
            createdAt: seedTimestamp,
            updatedAt: seedTimestamp
        )
    }

    public static func defaultPersonal() -> Project {
        Project(
            id: personalId,
            name: "Personal",
            colorHex: personalColorHex,
            orderKey: 2,
            createdAt: seedTimestamp,
            updatedAt: seedTimestamp
        )
    }

    public static var defaults: [Project] {
        [defaultWork(), defaultPersonal()]
    }
}
