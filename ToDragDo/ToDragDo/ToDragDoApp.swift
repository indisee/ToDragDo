import OSLog
import SwiftUI
import ToDragDoCore

@main
struct ToDragDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var repository: Repository
    @State private var settings: AppSettings
    @State private var panelController: PanelController
    @State private var dayRollover: DayRollover
    @State private var menuBar: MenuBarStatusItem
    @State private var coordinator: SyncCoordinator
    @State private var accountWatcher: CloudKitAccountWatcher
    @State private var syncTicker: SyncTicker
    @State private var storageHealth: StorageHealth
    @State private var dataLocation: DataLocation

    static let iCloudContainerIdentifier = "iCloud.com.turtle.todragdo.sync.container"
    private static let log = Logger(subsystem: "com.turtle.todragdo", category: "Launch")

    init() {
        let dataLocation = DataLocation()
        let outcome = StorageFactory.makeItemStorageWithRecovery(
            url: dataLocation.storeURL
        )
        let storage = Self.resolveStorage(from: outcome)
        let health = StorageHealth.from(outcome)
        Self.logOutcome(outcome)
        let repository = Repository(storage: storage)
        let settings = AppSettings()
        let coordinator = SyncCoordinator(applier: repository)
        let cloudAdapter = CloudKitRemoteAdapter(
            containerIdentifier: Self.iCloudContainerIdentifier
        )
        coordinator.register(cloudAdapter)
        let accountWatcher = CloudKitAccountWatcher(
            containerIdentifier: Self.iCloudContainerIdentifier,
            coordinator: coordinator,
            settings: settings
        )
        let panelController = PanelController(
            repository: repository,
            settings: settings,
            coordinator: coordinator,
            accountWatcher: accountWatcher,
            storageHealth: health,
            dataLocation: dataLocation
        )
        let dayRollover = DayRollover(repository: repository)
        dayRollover.start()
        let menuBar = MenuBarStatusItem(panelController: panelController)
        let syncTicker = SyncTicker(
            coordinator: coordinator,
            repository: repository,
            accountWatcher: accountWatcher
        )
        syncTicker.start()

        // After every local write: refresh the pending-push count so the
        // Sync settings UI reflects the queue immediately, then kick a
        // sync. The push usually finishes before the user looks, so the
        // count goes 0 → 1 → 0 in quick succession — but at least the
        // "1" is visible while the network round-trip is in flight, and
        // any push failure surfaces as `lastError` right away instead of
        // 60 s later on the next ticker fire.
        repository.onWriteCallback = { [weak coordinator] in
            Task { @MainActor [weak coordinator] in
                await coordinator?.refreshAllPendingCounts()
                await coordinator?.sync("icloud")
            }
        }
        _repository = State(initialValue: repository)
        _settings = State(initialValue: settings)
        _panelController = State(initialValue: panelController)
        _dayRollover = State(initialValue: dayRollover)
        _menuBar = State(initialValue: menuBar)
        _coordinator = State(initialValue: coordinator)
        _accountWatcher = State(initialValue: accountWatcher)
        _syncTicker = State(initialValue: syncTicker)
        _storageHealth = State(initialValue: health)
        _dataLocation = State(initialValue: dataLocation)
    }

    private static func resolveStorage(from outcome: StorageFactory.InitOutcome) -> any ItemStorage {
        if let storage = outcome.storage { return storage }
        // Last-ditch: build an in-memory store directly. If even this
        // throws, the runtime is too broken to recover and we crash —
        // but we've at least logged everything we could.
        log.fault("Storage unrecoverable; attempting raw in-memory fallback")
        do {
            return try StorageFactory.makeItemStorage(inMemory: true)
        } catch {
            fatalError("Storage completely unavailable: \(error)")
        }
    }

    private static func logOutcome(_ outcome: StorageFactory.InitOutcome) {
        switch outcome {
        case .healthy:
            log.info("Storage opened cleanly")
        case .rescued(_, let count, let primary):
            log.warning("Storage rescued: \(count) items recovered. Original error: \(primary.localizedDescription)")
        case .rebuiltEmpty(_, let primary, let rescue):
            log.error("Storage rebuilt empty. Original: \(primary.localizedDescription). Rescue: \(rescue.localizedDescription)")
        case .inMemoryFallback(_, let primary):
            log.error("Storage fell back to in-memory. Original: \(primary.localizedDescription)")
        case .unrecoverable(let primary):
            log.fault("Storage unrecoverable: \(primary.localizedDescription)")
        }
    }

    var body: some Scene {
        // The actual menu bar icon is the `NSStatusItem` owned by
        // `MenuBarStatusItem`. SwiftUI requires at least one Scene; this
        // hidden `MenuBarExtra` (`isInserted: false`) satisfies that
        // without registering a duplicate icon.
        MenuBarExtra(
            "ToDragDo",
            systemImage: "checklist",
            isInserted: .constant(false)
        ) {
            EmptyView()
        }
    }
}
