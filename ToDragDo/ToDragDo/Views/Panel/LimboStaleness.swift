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
    static func isStale(
        _ item: Item,
        threshold days: Int,
        now: Date = .now
    ) -> Bool {
        guard item.folder == .libmo, days > 0 else { return false }
        guard let entered = item.limboEnteredAt else { return false }
        let cutoff = TimeInterval(days) * 86_400
        return now.timeIntervalSince(entered) >= cutoff
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
