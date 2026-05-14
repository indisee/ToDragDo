import CloudKit
import Foundation
import Observation
import OSLog
import ToDragDoCore

/// Observes the user's iCloud account availability and toggles the
/// "icloud" provider's `enabled` flag on `SyncCoordinator` accordingly.
///
/// Policy: a provider is enabled when the user hasn't explicitly opted out
/// (`AppSettings.iCloudSyncEnabled`) AND `CKContainer.accountStatus` is
/// `.available`. If the user signs out of iCloud, we flip enabled off; if
/// they sign back in and never opted out, we flip it on.
@MainActor
@Observable
final class CloudKitAccountWatcher {
    private let container: CKContainer
    private let coordinator: SyncCoordinator
    private let settings: AppSettings
    private let log = Logger(subsystem: "com.turtle.todragdo", category: "CloudKitAccount")
    private var observer: NSObjectProtocol?

    init(
        containerIdentifier: String,
        coordinator: SyncCoordinator,
        settings: AppSettings
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.coordinator = coordinator
        self.settings = settings
        self.observer = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    // No deinit observer removal: watcher lives for the app's lifetime.

    /// Recomputes and applies the enabled flag for the iCloud provider.
    /// Returns the resolved enabled state for callers that want to chain
    /// a sync right after (e.g., on app launch).
    @discardableResult
    func refresh() async -> Bool {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            log.error("Failed to read CKAccountStatus: \(error.localizedDescription)")
            coordinator.setEnabled(false, for: "icloud")
            return false
        }
        let available = status == .available
        let enabled = available && settings.iCloudSyncEnabled
        coordinator.setEnabled(enabled, for: "icloud")
        if !available {
            log.notice("iCloud unavailable: status=\(String(describing: status))")
        }
        return enabled
    }

    /// Called when the user toggles the iCloud switch in Settings. Persists
    /// the preference and re-applies policy.
    func setUserPreference(_ enabled: Bool) async {
        settings.iCloudSyncEnabled = enabled
        await refresh()
    }
}
