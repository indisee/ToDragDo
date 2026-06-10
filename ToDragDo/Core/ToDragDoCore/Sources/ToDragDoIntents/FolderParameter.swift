import AppIntents
import ToDragDoCore

/// `AppIntents`-friendly mirror of `Folder`. The runtime needs an
/// `AppEnum` to surface this as a parameter in the Action Button picker
/// and Shortcuts editor; `Folder` itself stays plain so the rest of
/// the codebase doesn't pull AppIntents.
public enum FolderParameter: String, AppEnum {
    case today
    case tomorrow
    case limbo

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Folder"
    }

    public static var caseDisplayRepresentations: [FolderParameter: DisplayRepresentation] {
        [
            .today: "Today",
            .tomorrow: "Tomorrow",
            .limbo: "Limbo"
        ]
    }

    public var folder: Folder {
        switch self {
        case .today: return .today
        case .tomorrow: return .tomorrow
        case .limbo: return .libmo
        }
    }

    public init(folder: Folder) {
        switch folder {
        case .today: self = .today
        case .tomorrow: self = .tomorrow
        case .libmo: self = .limbo
        case .done: self = .today
        }
    }
}
