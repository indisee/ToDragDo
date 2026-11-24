import SwiftUI
import ToDragDoCore
import ToDragDoIntents
import ToDragDoSync

/// Bottom tab bar — five tabs, in the order from REQUIREMENTS-iOS.md
/// §Navigation. Phase 1 ships all five as placeholders; Phase 2 ports
/// real `FolderTabView` content into the four folder tabs and Phase 5
/// fleshes out the More tab.
struct RootView: View {
    @Environment(PanelState.self) private var panelState
    @Environment(Repository.self) private var repository
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
                .tabItem { Label("Tomorrow", systemImage: "arrow.right.circle.fill") }
                .tag(Tab.tomorrow)

            FolderTabView(folder: .libmo)
                .tabItem { Label("Limbo", systemImage: "tray.circle.fill") }
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
                // Drain the Action-Button "we couldn't sync ourselves"
                // fallback flag — see IntentStorage.bestEffortSync.
                if AppGroup.defaults.bool(forKey: AppGroup.Keys.pendingActionButtonSync) {
                    AppGroup.defaults.removeObject(forKey: AppGroup.Keys.pendingActionButtonSync)
                }
                await coordinator.sync(CloudKitConfig.providerId)
            }
        }
        .onReceive(pushPublisher) { _ in
            // AppDelegate received a silent push; pull immediately.
            Task { @MainActor in
                await coordinator.sync(CloudKitConfig.providerId)
            }
        }
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            handle(link)
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
    ///
    /// Re-tapping the currently-selected folder tab focuses the input
    /// bar (without flipping `widgetInputMode`, so the list stays
    /// visible — only widget taps hide the list).
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { panelState.selectedTab },
            set: { newTab in
                if newTab == panelState.selectedTab, newTab.folder != nil {
                    panelState.focusInputBarRequest = UUID()
                }
                panelState.selectedTab = newTab
            }
        )
    }

    private func handle(_ link: DeepLink) {
        switch link {
        case .input(let folder):
            panelState.selectedTab = Tab(folder: folder)
            panelState.widgetInputMode = true
            panelState.focusInputBarRequest = UUID()
        case .item(let id):
            // Repository keeps folder slices; find which one holds the
            // item so we can both switch the tab and expand it. If the
            // item hasn't been pulled yet (cold-launch race) bail —
            // user can re-tap the widget after the initial reload.
            for folder in Folder.allCases {
                guard let item = repository.items[folder]?.first(where: { $0.id == id }) else {
                    continue
                }
                panelState.selectedTab = Tab(folder: folder)
                if let projectId = item.projectId {
                    panelState.filterProjectIds = [projectId]
                } else {
                    panelState.filterProjectIds = []
                }
                // Defer expansion: the filter change above triggers a
                // list re-render, and setting `expandedItemId` in the
                // same synchronous mutation block lands before the new
                // rows are mounted — they read the cleared value (the
                // `filterProjectIds.didSet` resets it) and stay closed.
                // One runloop hop lets the filtered list build first.
                Task { @MainActor in
                    panelState.expandedItemId = id
                }
                return
            }
        }
    }
}
