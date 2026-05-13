import AppKit
import SwiftUI

extension View {
    /// Drop-in replacement for `.onHover` that also fires when the view
    /// appears under a stationary cursor — e.g. when a list reorders
    /// after a deletion and the next row shifts under the mouse.
    /// SwiftUI's `.onHover` only fires on cursor movement, so the hover
    /// state stays stale until the user jiggles the mouse.
    func onHoverStable(_ action: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(onChange: action))
    }
}

private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onChange: onChange)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void
        private var isInside = false

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            // AppKit only synthesizes enter/exit on cursor movement.
            // After layout (e.g. list reorder after deletion) the view
            // can appear under a stationary cursor — manually check.
            evaluateHover()
        }

        override func mouseEntered(with event: NSEvent) { setInside(true) }
        override func mouseExited(with event: NSEvent) { setInside(false) }

        private func evaluateHover() {
            guard let window = window, window.isVisible else {
                setInside(false)
                return
            }
            let mouseInScreen = NSEvent.mouseLocation
            guard NSMouseInRect(mouseInScreen, window.frame, false) else {
                setInside(false)
                return
            }
            let mouseInWindow = window.convertPoint(fromScreen: mouseInScreen)
            let pointInView = convert(mouseInWindow, from: nil)
            setInside(bounds.contains(pointInView))
        }

        private func setInside(_ value: Bool) {
            guard isInside != value else { return }
            isInside = value
            onChange(value)
        }
    }
}
