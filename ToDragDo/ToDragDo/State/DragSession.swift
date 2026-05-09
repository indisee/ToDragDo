import Foundation
import Observation
import ToDragDoCore

/// Panel-wide drag state. Drop-target views update it as the cursor
/// moves across them; views observe `target` to render overlays and
/// to hide content (e.g. the input text field) that would otherwise
/// intercept drops.
///
/// `target` clears on a short debounce so transitions between adjacent
/// drop targets (input ↔ item, item ↔ item) don't flicker the overlay
/// off and back on.
@MainActor
@Observable
final class DragSession {
    enum Target: Hashable, Sendable {
        case input
        case item(UUID)
    }

    private(set) var target: Target?

    var isActive: Bool { target != nil }

    private var pendingClear: Task<Void, Never>?

    /// Called by a `dropTarget` modifier when its area becomes the
    /// active drop destination.
    func enter(_ target: Target) {
        pendingClear?.cancel()
        pendingClear = nil
        self.target = target
    }

    /// Called when a drop area stops being the active destination.
    /// Clearing is deferred so a sibling target can claim the session
    /// before the overlay disappears.
    func exit(_ target: Target) {
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
    }
}
