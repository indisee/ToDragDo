import AppKit
import SwiftUI
import ToDragDoContentTypes
import ToDragDoCore
import ToDragDoUI

/// On-demand `NSWindow` that hosts `SummaryView` — the "done items in
/// this day/week" review window.
///
/// One shared window is reused for both Today and Week buttons. Clicking
/// either button while the window is already up flips the mode and
/// re-anchors to the current period, then orders the window front.
@MainActor
final class SummaryWindow {
    private var window: NSWindow?
    private let repository: Repository
    private let settings: AppSettings
    private let contentTypes: ContentTypeRegistry
    private let state = SummaryWindowState(mode: .day)
    // The summary window reuses `ItemRow`, which reads PanelState and
    // DragSession from its environment. Giving the window its own
    // instances keeps expand/collapse and drag state from leaking into
    // the floating panel and vice-versa.
    private let panelState = PanelState()
    private let dragSession = DragSession()

    init(
        repository: Repository,
        settings: AppSettings,
        contentTypes: ContentTypeRegistry
    ) {
        self.repository = repository
        self.settings = settings
        self.contentTypes = contentTypes
    }

    func show(mode: SummaryMode) {
        state.reset(to: mode)
        if window == nil {
            let host = NSHostingController(
                rootView: AnyView(
                    SummaryView()
                        .environment(repository)
                        .environment(settings)
                        .environment(state)
                        .environment(panelState)
                        .environment(dragSession)
                        .environment(\.contentTypes, contentTypes)
                )
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = host
            window.title = "Done summary"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentMinSize = NSSize(width: 360, height: 400)
            window.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
            // Open with no initial focus ring around the chevron arrows.
            window.initialFirstResponder = nil
            window.center()
            self.window = window
        }
        guard let window else { return }
        window.sharingType = settings.hideFromScreenSharing ? .none : .readOnly
        // `.accessory` apps need a forced front-order — same pattern the
        // settings window and the floating panel use.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(nil)
    }
}
