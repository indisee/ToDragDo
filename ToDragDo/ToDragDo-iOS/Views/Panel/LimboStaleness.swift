import Foundation
import ToDragDoCore

/// Pure helpers that decide whether a Limbo item has crossed the
/// user-configured idle threshold and should blink red. Verbatim port
/// from the macOS app.
enum LimboStaleness {
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

    static func anyStale(
        in items: [Item],
        threshold days: Int,
        now: Date = .now
    ) -> Bool {
        guard days > 0 else { return false }
        return items.contains { isStale($0, threshold: days, now: now) }
    }
}
