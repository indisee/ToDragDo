import AppKit
import Foundation
import OSLog
import ToDragDoCore

/// Drives `SyncCoordinator.syncAll()` while the app is running. Stage-1
/// timing: one sync on launch, then every `interval` seconds. Also kicks
/// an extra sync when the Mac wakes from sleep or the app re-activates,
/// so users don't have to wait for the next tick after coming back to
/// the machine. Stage-2 will replace polling with APNs silent pushes.
@MainActor
final class SyncTicker {
    private let coordinator: SyncCoordinator
    private let repository: Repository
    private let interval: TimeInterval
    private let log = Logger(subsystem: "com.turtle.todragdo", category: "SyncTicker")
    private var task: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    init(
        coordinator: SyncCoordinator,
        repository: Repository,
        interval: TimeInterval = 20
    ) {
        self.coordinator = coordinator
        self.repository = repository
        self.interval = interval
    }

    func start() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.repository.reload()
            self.log.info("Initial sync starting")
            await self.coordinator.syncAll()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.interval))
                } catch {
                    return
                }
                self.log.info("Tick sync starting")
                await self.coordinator.syncAll()
            }
        }
        installSystemObservers()
    }

    func stop() {
        task?.cancel()
        task = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let activateObserver {
            NotificationCenter.default.removeObserver(activateObserver)
            self.activateObserver = nil
        }
    }

    /// Fire a sync right now (out-of-band of the regular ticker). Used by
    /// the Settings UI on appear so users always see fresh data when they
    /// open the Sync pane.
    func kickNow(reason: String) {
        log.info("Out-of-band sync: \(reason, privacy: .public)")
        Task { @MainActor [weak self] in
            await self?.coordinator.syncAll()
        }
    }

    private func installSystemObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.kickNow(reason: "system wake")
            }
        }
        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.kickNow(reason: "app became active")
            }
        }
    }
}
