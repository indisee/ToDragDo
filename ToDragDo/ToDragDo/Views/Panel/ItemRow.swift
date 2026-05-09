import SwiftUI
import ToDragDoCore
import UniformTypeIdentifiers

/// A single (closed or open) item row.
///
/// Closed:
/// - One line: badge + truncated text + attachment icon strip.
/// - The whole row is draggable (URL with our private scheme).
/// - Tap opens the row.
/// - Hover reveals a folder-actions menu that overlays the right edge,
///   sitting on top of the row's content with its own background.
///
/// Open:
/// - Multi-line text (selectable / copyable) + clickable attachment
///   previews.
/// - Drag is disabled so text selection works.
/// - A floating menu (folder actions + X close) sits above the row,
///   outside the row's bounds.
///
/// Drop (always):
/// - Dropping a row's drag URL reorders this item.
/// - Dropping anything else attaches it to this item.
/// - While a drag hovers this row, the row's content is hidden so the
///   `DropOverlay` reads cleanly (mirrors the input bar).
struct ItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(DragSession.self) private var session

    let item: Item

    @State private var isRowHover = false
    @State private var isMenuHover = false

    private var actions: [RowAction] { RowAction.actions(for: item.folder) }
    private var isExpanded: Bool { panelState.expandedItemId == item.id }
    private var payload: ItemPayload { ItemPayload.decode(item.payload) }
    private var isReceivingDrop: Bool { session.target == .item(item.id) }
    private var isReorderTarget: Bool { session.reorderTarget == .item(item.id) }

    /// Combined hover state: true while the cursor is over the row OR
    /// over the floating menu. Without this, the menu (which lives in
    /// an overlay) flickers because mousing onto the menu's buttons
    /// causes `.onHover` on the row to fire false.
    private var isHovered: Bool { isRowHover || isMenuHover }

    var body: some View {
        rowCore
            .draggableWhenClosed(!isExpanded, payload: ItemDragURL.url(for: item.id)) {
                dragPreview
            }
            .tapWhenClosed(!isExpanded) { open() }
    }

    // MARK: - Core (visual + drop targets)

    private var rowCore: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isReceivingDrop {
                Color.clear.frame(minHeight: theme.rowHeight)
            } else {
                mainRow
                if isExpanded, !payload.attachments.isEmpty {
                    attachmentPreviews
                }
            }
        }
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isRowHover = $0 }
        .overlay(alignment: .top) { reorderIndicator }
        .overlay(alignment: .topTrailing) { actionsOverlay }
        .dropTarget(
            .item(item.id),
            label: "Drop on item",
            icon: "paperclip",
            onAttachment: { attachment in
                Task {
                    try? await repository.addAttachment(to: item.id, attachment)
                }
            },
            onItemReorder: { droppedId in
                guard droppedId != item.id else { return }
                Task {
                    try? await repository.reorder(id: droppedId, before: item.id)
                }
            }
        )
        .zIndex(isExpanded || isHovered ? 1 : 0)
    }

    // MARK: - Main row (badge + text + icons)

    private var mainRow: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: 8) {
            TypeBadge(typeIdentifier: item.typeIdentifier)
                .frame(width: 24, height: theme.rowHeight)
            noteText
            AttachmentIconStrip(attachments: payload.attachments)
                .frame(height: theme.rowHeight)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: theme.rowHeight)
    }

    /// Note text. Single line + truncation when closed; full multi-line
    /// + selection when open. `.fixedSize(vertical:)` keeps the frame
    /// from collapsing during the expand/close transition.
    @ViewBuilder
    private var noteText: some View {
        if isExpanded {
            Text(displayText)
                .font(.system(size: theme.bodySize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .topLeading)
                .padding(.vertical, 6)
                .layoutPriority(1)
        } else {
            Text(displayText)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .leading)
                .layoutPriority(1)
        }
    }

    // MARK: - Hover / close menu overlay

    @ViewBuilder
    private var actionsOverlay: some View {
        if isReceivingDrop {
            EmptyView()
        } else if isExpanded {
            floatingActionPanel
                .padding(.trailing, 8)
                .offset(y: -16)
        } else if isHovered {
            collapsedHoverActions
                .padding(.trailing, 8)
                .padding(.top, max(0, (theme.rowHeight - hoverPanelHeight) / 2))
        }
    }

    /// Open: hover actions + always-visible X close. Floats outside the
    /// row's bounds, above the top edge.
    private var floatingActionPanel: some View {
        HStack(spacing: 6) {
            HoverActions(actions: actions) { dispatch($0) }
            Divider().frame(height: 14)
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .onHover { isMenuHover = $0 }
    }

    /// Closed + hover: actions overlay the right edge with their own
    /// background so they sit on top of the row content rather than
    /// reflowing it.
    private var collapsedHoverActions: some View {
        HoverActions(actions: actions) { dispatch($0) }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thickMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .onHover { isMenuHover = $0 }
    }

    private var hoverPanelHeight: CGFloat { theme.bodySize + 14 }

    // MARK: - Expanded body

    private var attachmentPreviews: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(payload.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentPreview(attachment: attachment)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    // MARK: - Drag preview

    private var dragPreview: some View {
        HStack(spacing: 6) {
            TypeBadge(typeIdentifier: item.typeIdentifier)
            Text(displayText)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }

    // MARK: - Visual feedback

    /// Thin accent line at the top of the row while an in-app drag
    /// is hovering — indicates "the dropped item lands above this row".
    @ViewBuilder
    private var reorderIndicator: some View {
        if isReorderTarget {
            Rectangle()
                .fill(theme.accent)
                .frame(height: 2)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isHovered {
            theme.accent.opacity(0.06)
        } else {
            Color.clear
        }
    }

    // MARK: - Helpers

    private var displayText: String {
        if !payload.note.isEmpty { return payload.note }
        if let label = payload.attachments.first?.displayLabel, !label.isEmpty {
            return label
        }
        return "—"
    }

    private func open() {
        withAnimation(.easeInOut(duration: 0.18)) {
            panelState.openItem(item.id)
        }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.18)) {
            panelState.closeItem()
        }
    }

    private func dispatch(_ action: RowAction) {
        Task {
            do {
                switch action {
                case .moveToToday:    try await repository.move(id: item.id, to: .today)
                case .moveToTomorrow: try await repository.move(id: item.id, to: .tomorrow)
                case .moveToLimbo:    try await repository.move(id: item.id, to: .libmo)
                case .markDone:       try await repository.move(id: item.id, to: .done)
                case .delete:         try await repository.softDelete(id: item.id)
                }
            } catch {
                print("ItemRow action failed: \(error)")
            }
        }
    }
}

// MARK: - Conditional modifiers

private extension View {
    /// Applies `.draggable` only when `enabled` is true. Used to disable
    /// drag while the row is open so text selection works.
    @ViewBuilder
    func draggableWhenClosed<P: Transferable, V: View>(
        _ enabled: Bool,
        payload: P,
        @ViewBuilder preview: () -> V
    ) -> some View {
        if enabled {
            self.draggable(payload, preview: preview)
        } else {
            self
        }
    }

    /// Applies `.onTapGesture` only when `enabled` is true.
    @ViewBuilder
    func tapWhenClosed(_ enabled: Bool, perform: @escaping () -> Void) -> some View {
        if enabled {
            self.onTapGesture(perform: perform)
        } else {
            self
        }
    }
}
