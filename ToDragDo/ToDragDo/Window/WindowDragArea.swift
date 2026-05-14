import AppKit
import SwiftUI

/// Thin invisible strip at the top of the panel. Returns
/// `mouseDownCanMoveWindow = true` so a click+drag inside it moves the
/// host window — even if `isMovableByWindowBackground` is off so item
/// rows can keep their drag gesture. Falls back to manual frame-origin
/// updates if AppKit's auto-drag is suppressed by the SwiftUI host view.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragNSView: NSView {
    private var anchor: NSPoint?
    private var startOrigin: NSPoint?

    override var mouseDownCanMoveWindow: Bool { true }

    /// The panel is non-activating, so when it's not key, AppKit would
    /// otherwise swallow the first click as a focus-grab and never
    /// deliver mouseDown here. Accepting first mouse lets the user
    /// pick up and move the window in a single gesture.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        anchor = NSEvent.mouseLocation
        startOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let anchor, let startOrigin else { return }
        let now = NSEvent.mouseLocation
        let origin = NSPoint(
            x: startOrigin.x + (now.x - anchor.x),
            y: startOrigin.y + (now.y - anchor.y)
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        anchor = nil
        startOrigin = nil
    }
}

/// Vertical strip on the right edge that resizes the panel's width via
/// drag. Kept narrow (6pt) so it doesn't steal hits from the list rows.
///
/// The handle does not touch the window frame directly — the panel's
/// `NSHostingController` is in `.preferredContentSize` mode, so the
/// window auto-fits SwiftUI's ideal size. Mutating the frame here would
/// be reverted on the next layout pass. Instead, the handle reports a
/// new desired width through `onResize`; the caller stores that on
/// `AppSettings`, and `PanelView` re-applies it via `.frame(width:)`,
/// which triggers the controller to resize the window.
struct WidthResizeHandle: NSViewRepresentable {
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// Called with the clamped desired width while the handle is dragged.
    let onResize: (CGFloat) -> Void
    /// Returns the current width to anchor the drag against. Read once
    /// at `mouseDown` so subsequent SwiftUI re-renders don't shift the
    /// reference under the cursor.
    let currentWidth: () -> CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = ResizeNSView()
        view.minWidth = minWidth
        view.maxWidth = maxWidth
        view.onResize = onResize
        view.currentWidth = currentWidth
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let resize = nsView as? ResizeNSView else { return }
        resize.minWidth = minWidth
        resize.maxWidth = maxWidth
        resize.onResize = onResize
        resize.currentWidth = currentWidth
    }
}

private final class ResizeNSView: NSView {
    var minWidth: CGFloat = 360
    var maxWidth: CGFloat = 720
    var onResize: ((CGFloat) -> Void)?
    var currentWidth: (() -> CGFloat)?

    private var anchorX: CGFloat?
    private var startWidth: CGFloat?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        // Selectable Text inside the expanded row becomes first responder
        // on click. SwiftUI mis-lays it out when the parent width changes
        // while it's active — the text renders as empty until the row is
        // re-opened. Dropping focus before the drag avoids the bad path.
        window?.makeFirstResponder(nil)
        anchorX = NSEvent.mouseLocation.x
        startWidth = currentWidth?() ?? window?.frame.size.width
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchorX, let startWidth else { return }
        let dx = NSEvent.mouseLocation.x - anchorX
        let proposed = startWidth + dx
        let clamped = max(minWidth, min(maxWidth, proposed))
        onResize?(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        anchorX = nil
        startWidth = nil
    }
}
