import OSLog
import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes
import ToDragDoSync

@main
struct ToDragDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var repository: Repository
    @State private var settings: AppSettings
    @State private var panelController: PanelController
    @State private var dayRollover: DayRollover
    @State private var coordinator: SyncCoordinator
    @State private var accountWatcher: CloudKitAccountWatcher
    @State private var syncTicker: SyncTicker
    @State private var wakeBridge: SyncTickerWakeBridge
    @State private var contentTypes: ContentTypeRegistry
    @State private var storageHealth: StorageHealth
    @State private var dataLocation: DataLocation
    @State private var productionMigration: ProductionMigration

    static let iCloudContainerIdentifier = CloudKitConfig.containerIdentifier
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
            containerIdentifier: Self.iCloudContainerIdentifier
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
        let contentTypes = ContentTypeRegistry()
        contentTypes.registerBuiltIns()
        let panelController = PanelController(
            repository: repository,
            settings: settings,
            coordinator: coordinator,
            accountWatcher: accountWatcher,
            contentTypes: contentTypes,
            storageHealth: health,
            dataLocation: dataLocation
        )
        PanelController.shared = panelController
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
        let wakeBridge = SyncTickerWakeBridge(ticker: syncTicker)
        wakeBridge.install()

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
                await coordinator?.sync(CloudKitConfig.providerId)
            }
        }

        // One-shot CloudKit schema migration. Re-emits every existing
        // item, trashed item, and project as a fresh `update` ChangeRecord
        // so the zone is rewritten with the current field layout
        // (`snapshotData` inline + `CKAsset` for back-compat). Without
        // this pass, clients that can't decode legacy records — iOS, in
        // particular — never see anything that was written before the
        // schema change. UserDefaults flag gates it so it runs once per
        // device.
        let migrationKey = "todragdo.schema.migration.inline_v1"
        if !demoMode && !UserDefaults.standard.bool(forKey: migrationKey) {
            Task { @MainActor [weak repository] in
                guard let repository else { return }
                do {
                    try await repository.reload()
                    let count = try await repository.reEmitAllAsChanges()
                    UserDefaults.standard.set(true, forKey: migrationKey)
                    Self.log.notice("Schema migration: re-emitted \(count) records")
                } catch {
                    Self.log.error("Schema migration failed: \(error.localizedDescription)")
                }
            }
        }
        _repository = State(initialValue: repository)
        _settings = State(initialValue: settings)
        _panelController = State(initialValue: panelController)
        _dayRollover = State(initialValue: dayRollover)
        _coordinator = State(initialValue: coordinator)
        _accountWatcher = State(initialValue: accountWatcher)
        _syncTicker = State(initialValue: syncTicker)
        _wakeBridge = State(initialValue: wakeBridge)
        _contentTypes = State(initialValue: contentTypes)
        _storageHealth = State(initialValue: health)
        _dataLocation = State(initialValue: dataLocation)
        _productionMigration = State(initialValue: productionMigration)
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
        // The status bar icon is owned by `MenuBarStatusItem`. SwiftUI
        // requires at least one Scene; `Settings` is inert here because
        // `.accessory` apps have no app menu to invoke it from, and the
        // close-loop in AppDelegate dismisses it if macOS auto-restores
        // it. Unlike `MenuBarExtra`, `Settings` doesn't hook
        // `NSStatusBar.system`, so the manual `NSStatusItem` stays a
        // real `NSStatusItem` instead of being wrapped as
        // `NSSceneStatusItem` (which silently drops clicks).
        Settings {
            EmptyView()
        }
    }
}
