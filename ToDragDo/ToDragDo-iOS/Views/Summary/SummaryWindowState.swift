import Foundation
import Observation
import ToDragDoUI

/// Period the summary covers. Verbatim port from the macOS app.

/// Lightweight observable that the Done-summary sheet uses to track
/// which period it's anchored on. iOS variant — same shape as macOS,
/// driven by the sheet's chevrons instead of a window controller.
@MainActor
@Observable
final class SummaryWindowState {
    var mode: SummaryMode
    var anchor: Date

    init(
        mode: SummaryMode,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.mode = mode
        self.anchor = Self.normalize(now, mode: mode, calendar: calendar)
    }

    func reset(
        to mode: SummaryMode,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.mode = mode
        self.anchor = Self.normalize(now, mode: mode, calendar: calendar)
    }

    static func normalize(
        _ date: Date,
        mode: SummaryMode,
        calendar: Calendar
    ) -> Date {
        switch mode {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }
    }
}
