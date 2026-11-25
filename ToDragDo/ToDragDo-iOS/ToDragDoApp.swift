import OSLog
import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes
import ToDragDoIntents
import ToDragDoSync
import WidgetKit

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
    @State private var productionMigration: ProductionMigration
    @State private var backgroundRefresh: BackgroundRefresh
    @State private var captureMonitor: ScreenCaptureMonitor
    @State private var panelState = PanelState()

    static let iCloudContainerIdentifier = AppGroup.iCloudContainerIdentifier
    private static let log = Logger.todragdo(category: "Launch")

    init() {
        let dataLocation = DataLocation()
        // `-DemoMode`: in-memory store with fake data and no sync, for
        // screenshots. Never opens the real store or talks to CloudKit.
        let demoMode = DemoData.isRequested
        let storage: any ItemStorage
        let health: StorageHealth
        if demoMode {
            storage = Self.makeDemoStorage()
            health = StorageHealth()
        } else {
            let outcome = StorageFactory.makeItemStorageWithRecovery(
                url: dataLocation.storeURL
            )
            storage = Self.resolveStorage(from: outcome)
            health = StorageHealth.from(outcome)
            Self.logOutcome(outcome)
        }
        let repository = Repository(storage: storage)
        let settings = AppSettings()
        settings.bindToSync(repository)
        let coordinator = SyncCoordinator(applier: repository)
        let cloudAdapter = CloudKitRemoteAdapter(
            containerIdentifier: Self.iCloudContainerIdentifier,
            assetDirectory: dataLocation.cloudKitAssetDirectory
        )
        if !demoMode {
            coordinator.register(cloudAdapter)
        }
        // First launch of a Production-signed build: back up local data
        // and upload it to the (empty) Production database. No-op in
        // Development builds and after it has run once.
        let productionMigration = ProductionMigration(
            repository: repository,
            coordinator: coordinator,
            backupDirectory: dataLocation.storeURL
                .deletingLastPathComponent()
                .appendingPathComponent("Backups", isDirectory: true)
        )
        if demoMode {
            Task { @MainActor in try? await DemoData.seed(repository) }
        } else {
            productionMigration.start()
        }
        let accountWatcher = CloudKitAccountWatcher(
            containerIdentifier: Self.iCloudContainerIdentifier,
            coordinator: coordinator,
            preference: settings
        )
        let dayRollover = DayRollover(
            repository: repository,
            prepare: { [weak accountWatcher, weak coordinator] in
                // Pull first (best effort — offline just proceeds) so
                // rollover sees other devices' edits. At launch the
                // provider stays disabled until the account check lands.
                _ = await accountWatcher?.refresh()
                await coordinator?.syncAll()
            }
        )
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
        // Also nudge installed widgets so they redraw against the new
        // store contents — no-op on the host if no widget is installed.
        repository.onWriteCallback = { [weak coordinator] in
            Task { @MainActor [weak coordinator] in
                await coordinator?.refreshAllPendingCounts()
                await coordinator?.sync(CloudKitConfig.providerId)
                WidgetCenter.shared.reloadAllTimelines()
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
        _productionMigration = State(initialValue: productionMigration)
        _backgroundRefresh = State(initialValue: backgroundRefresh)
        _captureMonitor = State(initialValue: ScreenCaptureMonitor())
    }

    private static func makeDemoStorage() -> any ItemStorage {
        do {
            return try StorageFactory.makeItemStorage(inMemory: true)
        } catch {
            fatalError("Demo mode: in-memory storage unavailable: \(error)")
        }
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
