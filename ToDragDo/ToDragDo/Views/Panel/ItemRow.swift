import AppKit
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
    @Environment(AppSettings.self) private var settings

    let item: Item
    var trashMode: Bool = false

    @State private var isRowHover = false
    @State private var isMenuHover = false

    private var actions: [RowAction] {
        RowAction.actions(for: item.folder, inTrash: trashMode)
    }
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
            .onTapGesture {
                // Closed: tap anywhere opens. Expanded: tap on free space
                // closes. Text selection still works because it uses drag,
                // not tap. Buttons/links inside the row consume their own
                // taps before this gesture fires.
                if isExpanded { close() } else { open() }
            }
    }

    // MARK: - Core (visual + drop targets)

    private var rowCore: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                // Keep the expanded layout rendered even while a drag is
                // hovering. Swapping in a placeholder during drag would
                // collapse the row's height, the cursor would fall off,
                // exit fires, the row re-expands — and the drop target
                // flickers in a loop. The DropOverlay still renders on
                // top via the .overlay below.
                expandedBody
            } else if isReceivingDrop {
                Color.clear.frame(minHeight: 32)
            } else {
                mainRow
            }
        }
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHoverStable { isRowHover = $0 }
        .overlay(alignment: .top) { reorderIndicator }
        .overlay(alignment: .topLeading) { projectDotCorner }
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

    // MARK: - Main row

    private var mainRow: some View {
        contentLine
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(minHeight: 32, alignment: isExpanded ? .top : .center)
    }

    /// Top-left project dot, floated as an overlay so the content area
    /// can use uniform padding without reserving header space.
    @ViewBuilder
    private var projectDotCorner: some View {
        if !isReceivingDrop {
            ProjectBadge(
                behavior: .single(
                    current: item.projectId,
                    allowFlip: false,
                    onPick: { picked in
                        guard picked != item.projectId else { return }
                        Task {
                            try? await repository.setProject(itemId: item.id, to: picked)
                        }
                    }
                ),
                style: .dot
            )
            .padding(.leading, 12)
            .padding(.top, isExpanded ? 10 : 14)
        }
    }

    /// Done items show completion; other folders show due-date when set.
    private var headerDate: Date? {
        if item.folder == .done { return completedStamp }
        return item.dueDate
    }

    /// Past due in non-Done folders renders in red (mirrors the old
    /// TypeBadge red treatment that this header replaces).
    private var headerDateColor: Color {
        if item.folder != .done,
           let due = item.dueDate,
           Calendar.autoupdatingCurrent.startOfDay(for: due)
            < Calendar.autoupdatingCurrent.startOfDay(for: .now) {
            return .red
        }
        return .secondary
    }

    /// Note + optional date stamp + attachment icon strip. The date sits
    /// between text and attachments so it stays visible when the note
    /// truncates from the right.
    private var contentLine: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: 8) {
            noteText
            if item.folder == .done {
                AttachmentIconStrip(attachments: payload.attachments)
                if let stamp = headerDate {
                    dateStamp(stamp)
                }
            } else {
                if let stamp = headerDate {
                    dateStamp(stamp)
                }
                AttachmentIconStrip(attachments: payload.attachments)
            }
        }
    }

    private func dateStamp(_ stamp: Date) -> some View {
        Text(stamp, format: .dateTime.day(.twoDigits).month(.abbreviated))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(headerDateColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Fallback to `updatedAt` for items completed before `completedAt`
    /// was introduced — close enough since Done items are rarely edited.
    private var completedStamp: Date? {
        item.completedAt ?? (item.folder == .done ? item.updatedAt : nil)
    }

    /// Note text. Single line + truncation when closed; full multi-line
    /// + selection when open. `.fixedSize(vertical:)` keeps the frame
    /// from collapsing during the expand/close transition.
    @ViewBuilder
    private var noteText: some View {
        if isExpanded {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        } else {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(.trailing, 20)
                .offset(y: -20)
        } else if isHovered {
            collapsedHoverActions
                .padding(.trailing, 20)
                .padding(.top, max(0, (32 - hoverPanelHeight) / 2))
        }
    }

    /// Open: hover actions + date assign + edit + always-visible X close.
    /// Floats outside the row's bounds, above the top edge.
    private var floatingActionPanel: some View {
        HStack(spacing: 6) {
            HoverActions(actions: actions) { dispatch($0) }
            Divider().frame(height: 14)
            DateAssignButton(item: item)
            Divider().frame(height: 14)
            Button(action: edit) {
                Image(systemName: "pencil")
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit")
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

    /// Open row body. The mainRow + attachment previews live inside a
    /// ScrollView capped at `theme.expandedMaxHeight` so a long note or
    /// many image attachments scroll internally instead of stretching
    /// the panel beyond the screen.
    ///
    /// The hidden `ScrollerStyleProbe` inside the content walks up to
    /// the enclosing `NSScrollView` and forces overlay/.mini scrollers
    /// — SwiftUI exposes no API for indicator width, so this is the
    /// least invasive way to keep the bar slim regardless of the user's
    /// "Show scroll bars" system preference.
    private var expandedBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                mainRow
                if !payload.attachments.isEmpty {
                    attachmentPreviews
                }
            }
            .background(ScrollerStyleProbe())
        }
        .frame(maxHeight: theme.expandedMaxHeight)
        .scrollIndicators(.automatic)
    }

    private var attachmentPreviews: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(payload.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentPreview(attachment: attachment)
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Drag preview

    private var dragPreview: some View {
        HStack(spacing: 6) {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }

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
        let shape = RoundedRectangle(cornerRadius: 6)
        if isStaleInLimbo {
            // Pulsing red wash signals "this has sat in Limbo too long".
            // Layered under any hover tint so the warning still shows
            // when the cursor isn't over the row.
            shape
                .fill(.red)
                .phaseAnimator([0.06, 0.22]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.7)
                }
                .overlay {
                    if isHovered { shape.fill(theme.accent.opacity(0.06)) }
                }
        } else if isHovered {
            shape.fill(theme.accent.opacity(0.06))
        } else {
            Color.clear
        }
    }

    /// Recomputed when the parent re-renders (the panel re-evaluates on
    /// every Repository write and on the FolderTabBar's TimelineView
    /// tick), so a row that crosses the threshold while the panel is
    /// open does pick up the pulse on the next refresh.
    private var isStaleInLimbo: Bool {
        LimboStaleness.isStale(item, threshold: settings.limboBlinkDays)
    }

    // MARK: - Helpers

    private var displayText: String {
        if !payload.note.isEmpty { return payload.note }
        if let label = payload.attachments.first?.displayLabel, !label.isEmpty {
            return label
        }
        return "—"
    }

    /// `displayText` with detected URLs styled as blue underlined links.
    /// Clicks route through the `openURL` environment, which on macOS
    /// hands off to the user's default browser via NSWorkspace.
    private var attributedDisplay: AttributedString {
        Self.linkify(displayText)
    }

    private static let linkDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static func linkify(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !text.isEmpty, let detector = linkDetector else { return attr }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let stringRange = Range(match.range, in: text),
                  let url = match.url,
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attr),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attr)
            else { continue }
            let attrRange = lower..<upper
            attr[attrRange].link = url
            attr[attrRange].foregroundColor = .blue
            attr[attrRange].underlineStyle = .single
        }
        return attr
    }

    // Open/close are intentionally NOT wrapped in `withAnimation`.
    // The panel window resizes via `NSHostingController`'s
    // preferredContentSize, which doesn't follow SwiftUI's animation
    // clock — animating the row's height made the window snap to its
    // new size while the row was still mid-animation, producing a
    // visible "jump from center" mismatch. An instant state change
    // keeps the row and the window in sync.
    private func open() {
        panelState.openItem(item.id)
        // Reset the Limbo idle timer if this is a Limbo row. `noteOpened`
        // is a no-op for non-Limbo items, but we gate on the local view
        // of the folder anyway so we don't enqueue a stray write per tap.
        if item.folder == .libmo {
            let id = item.id
            Task {
                try? await repository.noteOpened(id: id)
            }
        }
    }

    private func close() {
        panelState.closeItem()
    }

    /// Move this item's note text into the input bar for editing.
    /// `beginEdit` stashes any draft already in the bar so it can be
    /// restored once the user finishes (or cancels) the edit.
    private func edit() {
        panelState.beginEdit(itemId: item.id, note: payload.note, projectId: item.projectId)
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
                case .restore:        try await repository.restore(id: item.id)
                case .purge:          try await repository.purgeItem(id: item.id)
                }
            } catch {
                print("ItemRow action failed: \(error)")
            }
        }
    }
}

// MARK: - Scroller customization

/// Zero-size probe that finds its enclosing `NSScrollView` and forces
/// overlay-style scrollers at `.mini` control size. SwiftUI doesn't
/// expose a knob for indicator width, and on systems set to "Show
/// scroll bars: Always" the legacy thick scroller would otherwise eat
/// noticeable horizontal space inside the row.
private struct ScrollerStyleProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.applyStyle()
    }

    private final class ProbeView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { .zero }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyStyle()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyStyle()
        }

        func applyStyle() {
            var ancestor: NSView? = superview
            while let current = ancestor, !(current is NSScrollView) {
                ancestor = current.superview
            }
            guard let scroll = ancestor as? NSScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.verticalScroller?.scrollerStyle = .overlay
            scroll.verticalScroller?.controlSize = .mini
            scroll.horizontalScroller?.scrollerStyle = .overlay
            scroll.horizontalScroller?.controlSize = .mini
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
}
