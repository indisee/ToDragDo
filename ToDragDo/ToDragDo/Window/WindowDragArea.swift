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
/// Width-only — height is driven by SwiftUI's ideal size and must not
/// be touched here, or we lose the auto-hug behavior.
struct WidthResizeHandle: NSViewRepresentable {
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        ResizeNSView(minWidth: minWidth, maxWidth: maxWidth)
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let resize = nsView as? ResizeNSView else { return }
        resize.minWidth = minWidth
        resize.maxWidth = maxWidth
    }
}

private final class ResizeNSView: NSView {
    var minWidth: CGFloat
    var maxWidth: CGFloat
    private var anchorX: CGFloat?
    private var startFrame: NSRect?

    init(minWidth: CGFloat, maxWidth: CGFloat) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        anchorX = NSEvent.mouseLocation.x
        startFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let anchorX, let startFrame else { return }
        let dx = NSEvent.mouseLocation.x - anchorX
        let proposed = startFrame.width + dx
        let clamped = max(minWidth, min(maxWidth, proposed))
        var frame = window.frame
        frame.size.width = clamped
        // Pin the left edge — only the right edge follows the cursor.
        frame.origin.x = startFrame.origin.x
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        anchorX = nil
        startFrame = nil
    }
}
