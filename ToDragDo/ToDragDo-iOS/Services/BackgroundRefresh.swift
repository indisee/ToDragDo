import BackgroundTasks
import OSLog
import ToDragDoCore
import UIKit

/// Wires `BGAppRefreshTask` into the iOS app — registers a handler at
/// launch and submits a refresh request whenever the app backgrounds.
/// Each fire runs `coordinator.syncAll()` then reschedules itself.
///
/// iOS gates this on its own heuristics (≈15 min minimum, usage-based
/// throttling); silent push is the fast path while this is the safety
/// net for cases where push isn't delivered (poor connectivity, no
/// recent foreground, etc.).
@MainActor
final class BackgroundRefresh {
    static let identifier = "com.turtle.todragdo.refresh"
    private static let log = Logger(subsystem: "com.turtle.todragdo", category: "BGRefresh")

    private let coordinator: SyncCoordinator
    private var didRegister = false
    private var observer: (any NSObjectProtocol)?

    init(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
    }

    /// Call once during app startup — before scenes connect. Registers
    /// the handler with `BGTaskScheduler` and arms a background-resign
    /// observer that submits the next refresh request.
    func install() {
        guard !didRegister else { return }
        didRegister = true

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await self?.handle(task)
            }
        }
        if !registered {
            Self.log.error("BGTaskScheduler.register returned false — check Info.plist BGTaskSchedulerPermittedIdentifiers")
        }

        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.schedule()
            }
        }
    }

    private func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        // Earliest 15 min — iOS won't run it sooner regardless, but the
        // earliestBeginDate hint helps with batching.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            Self.log.info("Scheduled next BGAppRefresh")
        } catch {
            Self.log.error("Failed to submit BGAppRefresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) async {
        Self.log.info("BGAppRefresh fired")
        // Reschedule first so iOS keeps the chain alive even if the
        // sync hits an error path.
        schedule()

        let syncTask = Task { @MainActor in
            await coordinator.syncAll()
            return true
        }
        task.expirationHandler = {
            syncTask.cancel()
        }
        _ = await syncTask.value
        task.setTaskCompleted(success: true)
    }
}
