import SwiftUI
import AppKit
import ToDragDoCore

/// Root view of the always-on-top panel.
/// Composes Input + Folder tabs + Item list. Owns no business logic;
/// state lives in `PanelState` (UI-only) and `Repository` (Core).
///
/// Width is fixed at 420pt; height is driven by `NSHostingController`
/// with `sizingOptions = [.preferredContentSize]` in `PanelController`,
/// which makes the panel auto-fit SwiftUI's ideal size.
struct PanelView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Repository.self) private var repository

    @State private var panelState = PanelState()
    @State private var dragSession = DragSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragArea()
                .frame(height: 12)
            VStack(alignment: .leading, spacing: 10) {
                InputBar()
                tabsRow
                if !panelState.isListCollapsed {
                    ItemList()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.background)
        )
        .environment(panelState)
        .environment(dragSession)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear { applyAppearance(settings.appearance) }
        .onChange(of: settings.appearance) { _, new in
            applyAppearance(new)
        }
        .task {
            do { try await repository.reload() }
            catch { print("Initial reload failed: \(error)") }
        }
    }

    private var tabsRow: some View {
        HStack(spacing: 8) {
            if panelState.isListCollapsed {
                CollapsedCaption()
            } else {
                FolderTabBar()
            }
            Spacer(minLength: 0)
            CollapseChevron()
        }
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        // `.preferredColorScheme(nil)` does not always undo a prior forced
        // appearance on the underlying NSWindow chrome. Setting
        // `NSApp.appearance` directly forces a real update.
        NSApp.appearance = mode.nsAppearance
    }
}

#Preview {
    let storage = try! StorageFactory.makeItemStorage(inMemory: true)
    let repo = Repository(storage: storage, deviceId: "preview")
    return PanelView()
        .environment(AppSettings())
        .environment(repo)
}
