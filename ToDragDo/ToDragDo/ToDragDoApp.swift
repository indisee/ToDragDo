import SwiftUI
import ToDragDoCore

@main
struct ToDragDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var repository: Repository
    @State private var settings: AppSettings
    @State private var panelController: PanelController

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
        _repository = State(initialValue: repository)
        _settings = State(initialValue: settings)
        _panelController = State(initialValue: panelController)
    }

    var body: some Scene {
        // No `Settings` scene — SwiftUI was auto-opening it at launch
        // even with `LSUIElement = YES` and an `AppDelegate` close
        // loop. Settings is now a custom NSWindow shown on demand from
        // `MenuBarMenu`.
        MenuBarExtra("ToDragDo", systemImage: "checkmark.square.fill") {
            MenuBarMenu()
                .environment(panelController)
        }
    }
}
