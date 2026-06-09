import SwiftUI
import ToDragDoCore

/// Bottom tab bar — five tabs, in the order from REQUIREMENTS-iOS.md
/// §Navigation. Phase 1 ships all five as placeholders; Phase 2 ports
/// real `FolderTabView` content into the four folder tabs and Phase 5
/// fleshes out the More tab.
struct RootView: View {
    @Environment(PanelState.self) private var panelState

    var body: some View {
        @Bindable var bound = panelState

        TabView(selection: tabBinding) {
            FolderTabStub(folder: .today)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)

            FolderTabStub(folder: .tomorrow)
                .tabItem { Label("Tomorrow", systemImage: "arrow.right") }
                .tag(Tab.tomorrow)

            FolderTabStub(folder: .libmo)
                .tabItem { Label("Limbo", systemImage: "tray") }
                .tag(Tab.limbo)

            FolderTabStub(folder: .done)
                .tabItem { Label("Done", systemImage: "checkmark.circle") }
                .tag(Tab.done)

            MoreTabStub()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(Tab.more)
        }
    }

    /// `Tab` mirrors `Folder` for the four list tabs and adds `.more` for
    /// the settings hub. The binding flips `PanelState.selectedFolder`
    /// when the user picks one of the four folder tabs; the More tab
    /// leaves `selectedFolder` untouched (it lives outside the
    /// expanded-row / list-filter axis the panel state describes).
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { Tab(folder: panelState.selectedFolder) },
            set: { tab in
                if let folder = tab.folder {
                    panelState.selectedFolder = folder
                }
            }
        )
    }

    enum Tab: Hashable {
        case today, tomorrow, limbo, done, more

        init(folder: Folder) {
            switch folder {
            case .today:    self = .today
            case .tomorrow: self = .tomorrow
            case .libmo:    self = .limbo
            case .done:     self = .done
            }
        }

        var folder: Folder? {
            switch self {
            case .today:    .today
            case .tomorrow: .tomorrow
            case .limbo:    .libmo
            case .done:     .done
            case .more:     nil
            }
        }
    }
}
