import Foundation
import OSLog
import ToDragDoCore

/// Drives `SyncCoordinator.syncAll()` while the app is running. Stage-1
/// timing: one sync on launch, then every `interval` seconds. Hosts can
/// also kick out-of-band syncs via `noteWake()` when the platform signals
/// a relevant event (system wake on macOS, scene foreground on iOS).
///
/// The ticker stays platform-clean — no AppKit / UIKit imports. The
/// host app target subscribes to platform notifications and forwards
/// them in.
@MainActor
public final class SyncTicker {
    private let coordinator: SyncCoordinator
    private let repository: Repository
    private let accountWatcher: CloudKitAccountWatcher?
    private let interval: TimeInterval
    private let log = Logger(subsystem: "com.turtle.todragdo", category: "SyncTicker")
    private var task: Task<Void, Never>?

    public init(
        coordinator: SyncCoordinator,
        repository: Repository,
        accountWatcher: CloudKitAccountWatcher? = nil,
        interval: TimeInterval = 20
    ) {
        self.coordinator = coordinator
        self.repository = repository
        self.accountWatcher = accountWatcher
        self.interval = interval
    }

    public func start() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.repository.reload()
            // Wait for the iCloud account check to settle before the first
            // sync — otherwise the initial syncAll() runs with enabled=false
            // (the default) and the user sees "failed" / no progress until
            // the next tick fires 20 s later.
            if let accountWatcher = self.accountWatcher {
                _ = await accountWatcher.refresh()
            }
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
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Fire a sync right now (out-of-band of the regular ticker). Used by
    /// the Settings UI on appear so users always see fresh data when they
    /// open the Sync pane, and by hosts forwarding platform wake events
    /// via `noteWake(reason:)`.
    public func kickNow(reason: String) {
        log.info("Out-of-band sync: \(reason, privacy: .public)")
        Task { @MainActor [weak self] in
            await self?.coordinator.syncAll()
        }
    }

    /// Host-side notification that the app/device just came back from a
    /// dormant state. macOS forwards `NSWorkspace.didWakeNotification` and
    /// `NSApplication.didBecomeActiveNotification`; iOS forwards
    /// `UIScene.willEnterForegroundNotification`.
    public func noteWake(reason: String) {
        kickNow(reason: reason)
    }
}
