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

    init() {
        let storage: any ItemStorage
        do {
            storage = try StorageFactory.makeItemStorage()
        } catch {
            fatalError("Failed to create item storage: \(error)")
        }
        let repository = Repository(storage: storage)
        let settings = AppSettings()
        let panelController = PanelController(
            repository: repository,
            settings: settings
        )
        let dayRollover = DayRollover(repository: repository)
        dayRollover.start()
        let menuBar = MenuBarStatusItem(panelController: panelController)
        _repository = State(initialValue: repository)
        _settings = State(initialValue: settings)
        _panelController = State(initialValue: panelController)
        _dayRollover = State(initialValue: dayRollover)
        _menuBar = State(initialValue: menuBar)
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
