import Foundation
import Observation
import ToDragDoCore

/// Panel-wide drag state. Drop-target views update it as the cursor
/// moves across them; views observe the published targets to render
/// overlays and to hide content (e.g. the input text field) that
/// would otherwise intercept drops.
///
/// Two channels:
/// - `target`: an external attachment drop is hovering — receivers
///   show the full `DropOverlay` and hide their content.
/// - `reorderTarget`: an in-app item-row drag is hovering — receivers
///   show a thin "drop above this row" line. Content stays visible
///   so the user can see what they're aiming at.
///
/// `target` clears on a short debounce so transitions between adjacent
/// drop targets don't flicker. `reorderTarget` clears immediately —
/// the line indicator should track the cursor exactly.
@MainActor
@Observable
final class DragSession {
    enum Target: Hashable, Sendable {
        case input
        case item(UUID)
    }

    private(set) var target: Target?
    private(set) var reorderTarget: Target?

    var isActive: Bool { target != nil || reorderTarget != nil }

    private var pendingClear: Task<Void, Never>?

    /// External attachment drag entered this target.
    func enter(_ target: Target) {
        pendingClear?.cancel()
        pendingClear = nil
        self.target = target
        self.reorderTarget = nil
    }

    /// In-app item-row drag entered this target. Doesn't show the
    /// attachment overlay; receivers render their own line indicator.
    func enterReorder(_ target: Target) {
        pendingClear?.cancel()
        pendingClear = nil
        self.reorderTarget = target
        self.target = nil
    }

    /// Called when a drop area stops being the active destination.
    /// Clears `reorderTarget` immediately; debounces clearing `target`
    /// so a sibling target can claim the session before the overlay
    /// disappears.
    func exit(_ target: Target) {
        if self.reorderTarget == target {
            self.reorderTarget = nil
        }
        guard self.target == target else { return }
        pendingClear?.cancel()
        pendingClear = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.target == target {
                self.target = nil
            }
            self.pendingClear = nil
        }
    }

    /// Called once a drop has been accepted (or aborted) so the overlay
    /// state collapses immediately, regardless of any pending debounce.
    func complete() {
        pendingClear?.cancel()
        pendingClear = nil
        target = nil
        reorderTarget = nil
    }
}
