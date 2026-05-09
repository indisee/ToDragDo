import SwiftUI
import AppKit
import ToDragDoCore

/// Root view of the always-on-top panel.
/// Composes Input + Folder tabs + Item list. Owns no business logic;
/// state lives in `PanelState` (UI-only) and `Repository` (Core).
///
/// Width is user-adjustable (persisted on `AppSettings.panelWidth`) via
/// a thin resize handle on the trailing edge; height is driven by
/// `NSHostingController` with `sizingOptions = [.preferredContentSize]`
/// in `PanelController`, which makes the panel auto-fit SwiftUI's ideal
/// size — so the controller picks up width changes through the same
/// preferredContentSize path.
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
        .frame(width: settings.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.background)
        )
        .overlay(alignment: .trailing) { resizeHandle }
        .environment(panelState)
        .environment(dragSession)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear { applyAppearance(settings.appearance) }
        .onChange(of: settings.appearance) { _, new in
            applyAppearance(new)
        }
        .onChange(of: settings.hideFromScreenSharing) { _, _ in
            AppDelegate.applySharingPolicyToAllWindows()
        }
        .task {
            do { try await repository.reload() }
            catch { print("Initial reload failed: \(error)") }
        }
    }

    /// 6pt invisible strip on the trailing edge that drives width
    /// resize. Sits inside the panel bounds so the rounded corner
    /// doesn't swallow the hit.
    private var resizeHandle: some View {
        WidthResizeHandle(
            minWidth: AppSettings.panelWidthRange.lowerBound,
            maxWidth: AppSettings.panelWidthRange.upperBound,
            onResize: { settings.panelWidth = $0 },
            currentWidth: { settings.panelWidth }
        )
        .frame(width: 6)
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
        //
        // Defer the assignment to the next runloop tick. A synchronous
        // change while a click is being handled by `NSSegmentedControl`
        // (the segmented Picker in Settings) tears down its tracking
        // state mid-click; rapid back-and-forth toggles eventually leave
        // the segments unresponsive.
        let appearance = mode.nsAppearance
        DispatchQueue.main.async {
            NSApp.appearance = appearance
        }
    }
}

#Preview {
    let storage = try! StorageFactory.makeItemStorage(inMemory: true)
    let repo = Repository(storage: storage, deviceId: "preview")
    let settings = AppSettings()
    let controller = PanelController(repository: repo, settings: settings)
    return PanelView()
        .environment(settings)
        .environment(repo)
        .environment(controller)
}
