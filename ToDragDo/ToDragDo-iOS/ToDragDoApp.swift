import OSLog
import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes
import ToDragDoSync

@main
struct ToDragDoApp: App {
    @UIApplicationDelegateAdaptor(iOSAppDelegate.self) private var appDelegate
    @State private var repository: Repository
    @State private var settings: AppSettings
    @State private var coordinator: SyncCoordinator
    @State private var accountWatcher: CloudKitAccountWatcher
    @State private var syncTicker: SyncTicker
    @State private var dayRollover: DayRollover
    @State private var contentTypes: ContentTypeRegistry
    @State private var storageHealth: StorageHealth
    @State private var dataLocation: DataLocation
    @State private var backgroundRefresh: BackgroundRefresh
    @State private var captureMonitor: ScreenCaptureMonitor
    @State private var panelState = PanelState()

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
        settings.bindToSync(repository)
        let coordinator = SyncCoordinator(applier: repository)
        let cloudAdapter = CloudKitRemoteAdapter(
            containerIdentifier: Self.iCloudContainerIdentifier,
            assetDirectory: dataLocation.cloudKitAssetDirectory
        )
        coordinator.register(cloudAdapter)
        let accountWatcher = CloudKitAccountWatcher(
            containerIdentifier: Self.iCloudContainerIdentifier,
            coordinator: coordinator,
            preference: settings
        )
        let dayRollover = DayRollover(repository: repository)
        dayRollover.start()
        let syncTicker = SyncTicker(
            coordinator: coordinator,
            repository: repository,
            accountWatcher: accountWatcher
        )
        syncTicker.start()
        let backgroundRefresh = BackgroundRefresh(coordinator: coordinator)
        backgroundRefresh.install()
        let contentTypes = ContentTypeRegistry()
        contentTypes.registerBuiltIns()

        // Mirror the macOS post-write hook: any local mutation refreshes
        // the pending-push count and kicks an immediate iCloud sync so
        // the UI surfaces failures without waiting for the next ticker.
        repository.onWriteCallback = { [weak coordinator] in
            Task { @MainActor [weak coordinator] in
                await coordinator?.refreshAllPendingCounts()
                await coordinator?.sync("icloud")
            }
        }

        _repository = State(initialValue: repository)
        _settings = State(initialValue: settings)
        _coordinator = State(initialValue: coordinator)
        _accountWatcher = State(initialValue: accountWatcher)
        _syncTicker = State(initialValue: syncTicker)
        _dayRollover = State(initialValue: dayRollover)
        _contentTypes = State(initialValue: contentTypes)
        _storageHealth = State(initialValue: health)
        _dataLocation = State(initialValue: dataLocation)
        _backgroundRefresh = State(initialValue: backgroundRefresh)
        _captureMonitor = State(initialValue: ScreenCaptureMonitor())
    }

    private static func resolveStorage(from outcome: StorageFactory.InitOutcome) -> any ItemStorage {
        if let storage = outcome.storage { return storage }
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
        WindowGroup {
            RootView()
                .environment(repository)
                .environment(settings)
                .environment(coordinator)
                .environment(accountWatcher)
                .environment(storageHealth)
                .environment(dataLocation)
                .environment(captureMonitor)
                .environment(panelState)
                .environment(\.contentTypes, contentTypes)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
