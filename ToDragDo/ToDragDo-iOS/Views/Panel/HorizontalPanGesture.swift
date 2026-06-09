import SwiftUI
import UIKit

/// UIKit-backed pan recognizer for the row swipe. Bridged into SwiftUI
/// via `UIGestureRecognizerRepresentable` (iOS 18+) so it can coexist
/// with the enclosing `UIScrollView`'s pan recognizer.
///
/// SwiftUI's own `DragGesture` + `simultaneousGesture` only coexists
/// with other SwiftUI gestures — once it recognizes, UIScrollView's
/// pan is canceled and vertical scroll dies. Here, a real
/// `UIGestureRecognizerDelegate` (the `Coordinator`) lets us:
/// - return `true` to `shouldRecognizeSimultaneouslyWith`, so the
///   scroll view's pan keeps tracking in parallel;
/// - return horizontal-dominance from `gestureRecognizerShouldBegin`,
///   so vertical pans never start our recognizer and fall through to
///   the scroll view.
struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        // SwiftUI redraws hand fresh closures; the Coordinator persists,
        // so refresh its stored callbacks to keep `@State` mutations
        // routed at the live row.
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            context.coordinator.onChanged(dx)
        case .ended, .cancelled, .failed:
            context.coordinator.onEnded(dx)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return false }
            let v = pan.velocity(in: view)
            // Strict horizontal dominance: any pan that's not clearly
            // horizontal returns to the ScrollView untouched.
            return abs(v.x) > abs(v.y) * 1.4
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
