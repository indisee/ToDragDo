import SwiftUI
import UniformTypeIdentifiers
import ToDragDoCore

/// UTType buckets accepted by drop targets. Items don't accept plain
/// text drops because that conflicts with browser URL drags (which
/// also carry text). Only the input bar opts into text.
enum DropTargetTypes {
    static let standard: [UTType] = [
        .fileURL, .url, .image, .png, .jpeg, .tiff
    ]
    static let withText: [UTType] = standard + [
        .text, .plainText, .utf8PlainText
    ]
}

/// View modifier that turns any view into a drop target.
///
/// - Registers `.onDrop(of:)` for the requested UTTypes. `.url` is
///   always implicitly included (it's part of `.standard`) — that's
///   what carries in-app item-row drags too. The handler dispatches:
///   if the dropped URL is an internal item drag, we call
///   `onItemReorder`; otherwise it's an external attachment.
/// - Reports targeting state to the shared `DragSession` so other
///   views (and this one) can render overlays and hide content that
///   would intercept drops.
/// - Renders a single `DropOverlay` while the cursor is over this
///   target. The overlay is non-hit-testing — drops still go to the
///   underlying view that the modifier registered.
private struct DropTargetModifier: ViewModifier {
    @Environment(DragSession.self) private var session

    let id: DragSession.Target
    let label: String
    let icon: String
    let types: [UTType]
    let onAttachment: ((Attachment) -> Void)?
    let onItemReorder: ((UUID) -> Void)?

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if session.target == id {
                    DropOverlay(label: label, icon: icon, isHighlighted: true)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: types, isTargeted: $isTargeted) { providers in
                handle(providers)
            }
            .onChange(of: isTargeted) { _, new in
                if new {
                    session.enter(id)
                } else {
                    session.exit(id)
                }
            }
    }

    private func handle(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task { @MainActor in
            // Internal item drag (URL with our scheme) takes priority.
            if let onItemReorder, let id = await ItemDragURL.itemID(from: provider) {
                session.complete()
                onItemReorder(id)
                return
            }
            // Otherwise, treat as external attachment.
            if let onAttachment {
                let attachment = await Attachment.from(provider: provider)
                session.complete()
                if let attachment {
                    onAttachment(attachment)
                }
            } else {
                session.complete()
            }
        }
        return true
    }
}

extension View {
    /// Wires this view as a drop target.
    ///
    /// - Parameters:
    ///   - id: identity used by `DragSession` to disambiguate which
    ///     target the cursor is over.
    ///   - label: text shown inside the overlay while targeted.
    ///   - icon: SF Symbol shown next to the label.
    ///   - types: UTTypes the underlying drop destination accepts.
    ///   - onAttachment: invoked with the produced `Attachment` for
    ///     external drops. Pass nil for targets that only accept
    ///     in-app reorder drags (folder tabs, end-of-list zone).
    ///   - onItemReorder: invoked with the dragged item's id for
    ///     in-app reorder drags. Pass nil for targets that only
    ///     accept external content (input bar).
    func dropTarget(
        _ id: DragSession.Target,
        label: String,
        icon: String = "plus",
        types: [UTType] = DropTargetTypes.standard,
        onAttachment: ((Attachment) -> Void)? = nil,
        onItemReorder: ((UUID) -> Void)? = nil
    ) -> some View {
        modifier(
            DropTargetModifier(
                id: id,
                label: label,
                icon: icon,
                types: types,
                onAttachment: onAttachment,
                onItemReorder: onItemReorder
            )
        )
    }
}
