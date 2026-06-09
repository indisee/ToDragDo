import AppKit
import Foundation
import ToDragDoSync

/// macOS-only bridge that forwards `NSWorkspace.didWakeNotification` and
/// `NSApplication.didBecomeActiveNotification` into `SyncTicker.noteWake`.
/// Lives in the macOS app target so `ToDragDoSync` stays AppKit-free and
/// iOS can use the same ticker via its own scene-foreground hook.
@MainActor
final class SyncTickerWakeBridge {
    private let ticker: SyncTicker
    private var wakeObserver: (any NSObjectProtocol)?
    private var activateObserver: (any NSObjectProtocol)?

    init(ticker: SyncTicker) {
        self.ticker = ticker
    }

    func install() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ticker.noteWake(reason: "system wake")
            }
        }
        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ticker.noteWake(reason: "app became active")
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let activateObserver {
            NotificationCenter.default.removeObserver(activateObserver)
        }
    }
}
