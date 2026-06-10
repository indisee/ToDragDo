import AppIntents
import Foundation
import WidgetKit

/// Writes `projectId` to the App Group defaults the project-list widget
/// reads, then forces a timeline reload so the widget redraws against
/// the new project. Wired into widget-side `Button(intent:)` chips.
public struct SetWidgetProjectIntent: AppIntent {
    public static var title: LocalizedStringResource { "Show Project" }
    public static var description: IntentDescription {
        IntentDescription("Switch the project shown in the ToDragDo widget.")
    }
    public static var openAppWhenRun: Bool { false }
    public static var isDiscoverable: Bool { false }

    @Parameter(title: "Project ID")
    public var projectId: String

    public init() {}

    public init(projectId: String) {
        self.projectId = projectId
    }

    public func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(projectId, forKey: AppGroup.Keys.widgetProjectId)
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}
