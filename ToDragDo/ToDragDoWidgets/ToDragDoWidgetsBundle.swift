import SwiftUI
import WidgetKit

@main
struct ToDragDoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        ProjectListWidget()
    }
}
