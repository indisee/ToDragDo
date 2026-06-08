import Foundation
import ToDragDoCore

/// Pure helpers that decide whether a Limbo item has crossed the
/// user-configured idle threshold and should blink red. Centralised so
/// the row view and the tab badge can't drift.
enum LimboStaleness {
    /// True when `item` lives in Limbo, has an idle timestamp, and the
    /// configured threshold (in days, > 0) has elapsed since it last
    /// reset. Items without `limboEnteredAt` (legacy rows that pre-date
    /// the field) are treated as not-stale until the user touches them.
    ///
    /// When `dueDate` is set the threshold runs from the due date
    /// instead — the user has signalled an intended action time, so a
    /// future date suppresses the warning entirely and a past one
    /// arms the countdown from that moment.
    static func isStale(
        _ item: Item,
        threshold days: Int,
        now: Date = .now
    ) -> Bool {
        guard item.folder == .libmo, days > 0 else { return false }
        let anchor: Date
        if let due = item.dueDate {
            anchor = due
        } else if let entered = item.limboEnteredAt {
            anchor = entered
        } else {
            return false
        }
        let cutoff = TimeInterval(days) * 86_400
        return now.timeIntervalSince(anchor) >= cutoff
    }

    /// True when any item in `items` is stale under `threshold`.
    /// `items` is expected to be the current Limbo slice.
    static func anyStale(
        in items: [Item],
        threshold days: Int,
        now: Date = .now
    ) -> Bool {
        guard days > 0 else { return false }
        return items.contains { isStale($0, threshold: days, now: now) }
    }
}
