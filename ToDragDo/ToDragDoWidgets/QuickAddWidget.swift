import SwiftUI
import ToDragDoCore
import ToDragDoIntents
import WidgetKit

/// Static "looks like a text field" widget. Tap launches the host app
/// deep-linked to the chosen folder's input bar (`todragdo://input?...`)
/// because iOS widgets can't host a real TextField.
struct QuickAddWidget: Widget {
    static let kind = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: QuickAddProvider()) { _ in
            QuickAddWidgetView()
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Tap to jump into ToDragDo with the keyboard up.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

/// Single-entry, never-refreshing provider — the widget is pure chrome
/// with no data dependency, so timeline reloads would be wasted work.
struct QuickAddProvider: TimelineProvider {
    func placeholder(in _: Context) -> QuickAddEntry {
        QuickAddEntry(date: Date(timeIntervalSinceReferenceDate: 0))
    }

    func getSnapshot(in _: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: Date(timeIntervalSinceReferenceDate: 0)))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        let entry = QuickAddEntry(date: Date(timeIntervalSinceReferenceDate: 0))
        completion(Timeline(entries: [entry], policy: .never))
    }
}
