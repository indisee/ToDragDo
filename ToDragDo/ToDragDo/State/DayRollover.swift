import AppKit
import Foundation
import ToDragDoCore

/// Drives the end-of-day rollover: when the calendar day changes,
/// everything in Today merges into Tomorrow, and Tomorrow becomes the
/// new Today (cleared). Triggers on app launch (catching missed days
/// while the app was closed), at the next local midnight while running,
/// and on system wake.
@MainActor
final class DayRollover {
    private let repository: Repository
    private let calendar: Calendar
    private let defaults: UserDefaults
    private var midnightTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(
        repository: Repository,
        calendar: Calendar = .autoupdatingCurrent,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.calendar = calendar
        self.defaults = defaults
    }

    deinit {
        midnightTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func start() {
        Task { @MainActor in
            await runIfNeeded()
            scheduleNextMidnight()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runIfNeeded()
                self.scheduleNextMidnight()
            }
        }
    }

    private func runIfNeeded() async {
        let today = calendar.startOfDay(for: .now)
        let lastSeen = defaults.object(forKey: Keys.lastSeenDay) as? Date

        let dayChanged = lastSeen.map { !calendar.isDate($0, inSameDayAs: today) } ?? false
        do {
            if dayChanged {
                try await repository.rolloverDay()
            } else {
                // No day boundary crossed, but limbo items whose date was
                // already due (e.g. a past-due item synced in from another
                // device) should still surface in Today.
                try await repository.promoteScheduledItems()
            }
        } catch {
            NSLog("DayRollover: rollover failed: \(error)")
            return
        }
        defaults.set(today, forKey: Keys.lastSeenDay)
    }

    private func scheduleNextMidnight() {
        midnightTimer?.invalidate()
        let nextMidnight = calendar.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(24 * 60 * 60)
        let interval = max(1, nextMidnight.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runIfNeeded()
                self.scheduleNextMidnight()
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    private enum Keys {
        static let lastSeenDay = "todragdo.dayRollover.lastSeenDay"
    }
}
