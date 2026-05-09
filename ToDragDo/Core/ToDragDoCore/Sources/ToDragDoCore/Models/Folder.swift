import Foundation

public enum Folder: String, Codable, Sendable, CaseIterable, Hashable {
    case today
    case tomorrow
    case libmo
    case done
}
