import SwiftUI
import ToDragDoCore
import ToDragDoSync

/// Bottom tab bar — five tabs, in the order from REQUIREMENTS-iOS.md
/// §Navigation. Phase 1 ships all five as placeholders; Phase 2 ports
/// real `FolderTabView` content into the four folder tabs and Phase 5
/// fleshes out the More tab.
struct RootView: View {
    @Environment(PanelState.self) private var panelState
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase

    private let pushPublisher = NotificationCenter.default
        .publisher(for: .todragdoCloudKitPush)

    var body: some View {
        TabView(selection: tabBinding) {
            FolderTabView(folder: .today)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)

            FolderTabView(folder: .tomorrow)
                .tabItem { Label("Tomorrow", systemImage: "arrow.right") }
                .tag(Tab.tomorrow)

            FolderTabView(folder: .libmo)
                .tabItem { Label("Limbo", systemImage: "tray") }
                .tag(Tab.limbo)

            FolderTabView(folder: .done)
                .tabItem { Label("Done", systemImage: "checkmark.circle") }
                .tag(Tab.done)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(Tab.more)
        }
        .onChange(of: scenePhase) { _, phase in
            // Scene foreground is the iOS analogue of macOS wake/activate:
            // kick an immediate iCloud sync so the user sees fresh data
            // without waiting for the next 20 s ticker fire.
            guard phase == .active else { return }
            Task { @MainActor in
                await coordinator.sync("icloud")
            }
        }
        .onReceive(pushPublisher) { _ in
            // AppDelegate received a silent push; pull immediately.
            Task { @MainActor in
                await coordinator.sync("icloud")
            }
        }
        .task {
            // Install the CKDatabaseSubscription once per user; subsequent
            // launches early-out off the persisted flag.
            let installer = CloudKitSubscriptionInstaller(
                containerIdentifier: ToDragDoApp.iCloudContainerIdentifier,
                defaults: AppGroup.defaults
            )
            await installer.installIfNeeded()
        }
    }

    /// Drives the bottom tab bar off `PanelState.selectedTab` — the
    /// canonical store. `selectedTab.didSet` propagates folder picks
    /// down into `selectedFolder`; the More tab leaves it untouched.
    /// Deriving the tab from `selectedFolder` alone would lose `.more`
    /// across re-renders (appearance change, settings-pane mutation)
    /// and snap the user back to a folder tab.
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { panelState.selectedTab },
            set: { panelState.selectedTab = $0 }
        )
    }
}
